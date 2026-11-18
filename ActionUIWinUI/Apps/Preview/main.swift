// ActionUIWinUI/Apps/Preview/main.swift - ActionUIWinUIPreview: renders an ActionUI document with
// the WinUI renderer into a PNG of the window's whole content area (below the title bar), in a
// window of the given content size, and prints where WinUI placed each element (its frame in its
// parent), so a run can be compared with SwiftUI's and GTK's.
//
// Usage: ActionUIWinUIPreview DOCUMENT.json PNG_PATH [WIDTH HEIGHT] [options]
//   --invoke ID              after the first layout, operates element ID as an accessibility tool
//                            does (UI Automation's Invoke: a Button is pressed); repeatable, in order
//   --toggle ID              the same with UI Automation's Toggle (a Toggle turns over)
//   --set-text ID TEXT       the same with UI Automation's SetValue (a TextField's text, as typed)
//   --expect-action ACTION   fails unless the action ACTION fired; repeatable
//   --on-action ACTION ID TEXT  when ACTION fires, sets element ID's value to TEXT (a Text shows it)
// Every action that fires is printed. Prints "preview:" lines; exit status 0 when the document
// loaded and rendered, the PNG is not empty, every operation worked and every expected action
// fired at least once. Built and run by
// Scripts/ci-windows.py winui.

import ActionUI
import CWinUI
import Dispatch
import ucrt

@MainActor
final class Preview {
    static let shared = Preview()

    var documentPath = ""
    var pngPath = ""
    var contentSize = ActionUIWinUISize(width: 480, height: 320)
    var window: WinUIObject?
    var tree: WinUIWindow?
    var rendered = false
    /// The --invoke, --toggle and --set-text operations, in order.
    var invocations: [Operation] = []

    enum Operation {
        case invoke(Int), toggle(Int), setText(Int, String)

        var viewID: Int {
            switch self {
            case .invoke(let id), .toggle(let id), .setText(let id, _): return id
            }
        }
    }
    var expectedActions: [String] = []
    var valuesOnAction: [String: (viewID: Int, text: String)] = [:]
    var firedActions: [String] = []
    /// False once an --invoke found no element or the shim refused it.
    var invocationsWorked = true

    func say(_ line: String) {
        print("preview: \(line)")
    }

    func launched() {
        guard MainLoopBridge.install() else {
            say("the main queue bridge could not be installed")
            finish()
            return
        }
        guard let json = readFile(documentPath) else {
            say("cannot read \(documentPath)")
            finish()
            return
        }
        do {
            let tree = try WinUIWindow.load(json: json, windowUUID: "preview")
            self.tree = tree
            // No view: no element loaded, no view model for the root, or its WinUI object could not
            // be made (the log says which).
            guard let content = tree.view else {
                say("the document has no root element to show")
                finish()
                return
            }
            guard let window = WinUIObject(adopting: actionUIWinUIWindowCreate()) else {
                say(WinUIError.last("creating the window").description)
                finish()
                return
            }
            self.window = window
            guard actionUIWinUIWindowSetTitle(window.pointer, "ActionUI WinUI preview"),
                  actionUIWinUIWindowSetContentSize(window.pointer, contentSize.width, contentSize.height),
                  actionUIWinUIWindowSetContent(window.pointer, content.pointer),
                  actionUIWinUIWindowActivate(window.pointer) else {
                say(WinUIError.last("setting up the window").description)
                finish()
                return
            }
        } catch {
            say("the document did not load: \(error)")
            finish()
            return
        }
        ActionUIModel.shared.setDefaultActionHandler { actionID, windowUUID, viewID, _, _ in
            MainActor.assumeIsolated { Preview.shared.actionFired(actionID, windowUUID: windowUUID, viewID: viewID) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(800)) {
            MainActor.assumeIsolated { Preview.shared.invokeThenRender() }
        }
    }

    func actionFired(_ actionID: String, windowUUID: String, viewID: Int) {
        firedActions.append(actionID)
        say("action \(actionID) from element \(viewID)")
        if let change = valuesOnAction[actionID] {
            ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: change.viewID, value: change.text)
        }
    }

    /// Operates the elements named by --invoke, then lets the model's changes reach WinUI (a sync,
    /// then a layout) before reporting and rendering.
    func invokeThenRender() {
        guard !invocations.isEmpty else {
            reportAndRender()
            return
        }
        for operation in invocations {
            let viewID = operation.viewID
            guard let node = tree?.root.flatMap({ find(viewID, in: $0) }), let view = node.view else {
                say("element \(viewID): no such element on screen")
                invocationsWorked = false
                continue
            }
            let worked: Bool
            let what: String
            switch operation {
            case .invoke:
                worked = actionUIWinUIAutomationInvoke(view.pointer)
                what = "invoked"
            case .toggle:
                worked = actionUIWinUIAutomationToggle(view.pointer)
                what = "toggled"
            case .setText(_, let text):
                worked = actionUIWinUIAutomationSetValue(view.pointer, text)
                what = "set the text of"
            }
            if worked {
                say("\(what) \(node.element.type) \(viewID)")
            } else {
                say("element \(viewID): \(WinUIError.last(what))")
                invocationsWorked = false
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(500)) {
            MainActor.assumeIsolated { Preview.shared.reportAndRender() }
        }
    }

    /// The node of element `viewID` in the tree under `node`.
    func find(_ viewID: Int, in node: RenderNode) -> RenderNode? {
        if node.element.id == viewID {
            return node
        }
        for child in node.orderedChildren {
            if let found = find(viewID, in: child) {
                return found
            }
        }
        return nil
    }

    func reportAndRender() {
        if let root = tree?.root {
            report(root, indent: "")
        }
        guard let window else {
            finish()
            return
        }
        // The whole content area, as the window shows it below its title bar.
        let started = actionUIWinUIWindowRenderToPNG(window.pointer, pngPath, { _, succeeded in
            MainActor.assumeIsolated { Preview.shared.renderDone(succeeded) }
        }, nil)
        if !started {
            say(WinUIError.last("starting the render").description)
            finish()
        }
    }

    /// Prints the node's element and frame, then its children's, in document order.
    func report(_ node: RenderNode, indent: String) {
        let frame = node.view?.layoutFrame ?? ActionUIWinUIRect(x: 0, y: 0, width: 0, height: 0)
        say("\(indent)\(node.element.type) \(node.element.id): (\(frame.x), \(frame.y), \(frame.width), \(frame.height))")
        for child in node.orderedChildren {
            report(child, indent: indent + "  ")
        }
    }

    func renderDone(_ succeeded: Bool) {
        rendered = succeeded
        say(succeeded ? "rendered \(pngPath)" : WinUIError.last("rendering").description)
        finish()
    }

    /// Closes the window and lets go of every object, then quits; on the UI thread, before
    /// actionUIWinUIRun returns.
    func finish() {
        if let window {
            _ = actionUIWinUIWindowClose(window.pointer)
        }
        tree?.detach()
        tree = nil
        window = nil
        actionUIWinUIQuit()
    }
}

/// The UTF-8 text of the file at `path`, or nil. Through the C runtime's wide calls: its narrow ones
/// read a path in the ANSI code page.
func readFile(_ path: String) -> String? {
    var opened: UnsafeMutablePointer<FILE>?
    let status = path.withCString(encodedAs: UTF16.self) { widePath in
        "rb".withCString(encodedAs: UTF16.self) { wideMode in
            _wfopen_s(&opened, widePath, wideMode)
        }
    }
    guard status == 0, let file = opened else {
        return nil
    }
    defer { fclose(file) }
    var bytes: [UInt8] = []
    var chunk = [UInt8](repeating: 0, count: 65536)
    while true {
        let count = fread(&chunk, 1, chunk.count, file)
        if count == 0 {
            break
        }
        bytes.append(contentsOf: chunk[0..<count])
    }
    return String(decoding: bytes, as: UTF8.self)
}

/// The size of the file at `path`, or -1.
func fileSize(_ path: String) -> Int {
    var opened: UnsafeMutablePointer<FILE>?
    let status = path.withCString(encodedAs: UTF16.self) { widePath in
        "rb".withCString(encodedAs: UTF16.self) { wideMode in
            _wfopen_s(&opened, widePath, wideMode)
        }
    }
    guard status == 0, let file = opened else {
        return -1
    }
    defer { fclose(file) }
    guard fseek(file, 0, SEEK_END) == 0 else {
        return -1
    }
    return Int(ftell(file))
}

setvbuf(__acrt_iob_func(1), nil, _IONBF, 0)  // stdout, unbuffered: the lines must survive a crash

let arguments = CommandLine.arguments
let usage = "usage: ActionUIWinUIPreview DOCUMENT.json PNG_PATH [WIDTH HEIGHT] [--invoke ID | --toggle ID | --set-text ID TEXT]... [--expect-action ACTION]... [--on-action ACTION ID TEXT]..."
guard arguments.count >= 3 else {
    print(usage)
    exit(64)
}
let preview = Preview.shared
preview.documentPath = arguments[1]
preview.pngPath = arguments[2]
var index = 3
if arguments.count >= 5, let width = Double(arguments[3]), let height = Double(arguments[4]) {
    guard width > 0, height > 0 else {
        print("preview: WIDTH and HEIGHT must be positive")
        exit(64)
    }
    preview.contentSize = ActionUIWinUISize(width: width, height: height)
    index = 5
}
while index < arguments.count {
    let option = arguments[index]
    if option == "--invoke", index + 1 < arguments.count, let viewID = Int(arguments[index + 1]) {
        preview.invocations.append(.invoke(viewID))
        index += 2
    } else if option == "--toggle", index + 1 < arguments.count, let viewID = Int(arguments[index + 1]) {
        preview.invocations.append(.toggle(viewID))
        index += 2
    } else if option == "--set-text", index + 2 < arguments.count, let viewID = Int(arguments[index + 1]) {
        preview.invocations.append(.setText(viewID, arguments[index + 2]))
        index += 3
    } else if option == "--expect-action", index + 1 < arguments.count {
        preview.expectedActions.append(arguments[index + 1])
        index += 2
    } else if option == "--on-action", index + 3 < arguments.count, let viewID = Int(arguments[index + 2]) {
        preview.valuesOnAction[arguments[index + 1]] = (viewID, arguments[index + 3])
        index += 4
    } else {
        print("preview: cannot read the option \(option)")
        print(usage)
        exit(64)
    }
}
_ = preview.pngPath.withCString(encodedAs: UTF16.self) { _wremove($0) }

guard actionUIWinUIInitialize() else {
    print("preview: \(WinUIError.last("initializing the Windows App SDK runtime"))")
    exit(1)
}
let ran = actionUIWinUIRun({ _ in
    MainActor.assumeIsolated { Preview.shared.launched() }
}, nil)
if !ran {
    print("preview: \(WinUIError.last("running WinUI"))")
}
actionUIWinUIShutdown()

let size = fileSize(preview.pngPath)
let missing = preview.expectedActions.filter { !preview.firedActions.contains($0) }
if !missing.isEmpty {
    print("preview: expected actions that did not fire: \(missing)")
}
print("preview: run \(ran ? "ok" : "failed"), rendered \(preview.rendered ? "yes" : "no"), PNG \(size) bytes, actions fired \(preview.firedActions.count)")
exit(ran && preview.rendered && size > 0 && missing.isEmpty && preview.invocationsWorked ? 0 : 1)
