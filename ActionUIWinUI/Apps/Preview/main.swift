// ActionUIWinUI/Apps/Preview/main.swift - ActionUIWinUIPreview: renders an ActionUI document with
// the WinUI renderer into a PNG of the window's whole content area (below the title bar), in a
// window of the given content size, and prints where WinUI placed each element (its frame in its
// parent), so a run can be compared with SwiftUI's and GTK's.
//
// Usage: ActionUIWinUIPreview DOCUMENT.json PNG_PATH [WIDTH HEIGHT] [options]
//   Relative image paths in the document are taken from the document's folder.
//   --invoke ID              after the first layout, operates element ID as an accessibility tool
//                            does (UI Automation's Invoke: a Button is pressed); repeatable, in order
//   --toggle ID              the same with UI Automation's Toggle (a Toggle turns over)
//   --invoke-row ID ROW      the same with the element List ID shows in row ROW (from 0; a Button cell)
//   --invoke-part ID N       the same with the Nth part (from 0) of element ID that can be invoked (a
//                            Stepper's minus is 0, its plus 1)
//   --set-text ID TEXT       the same with UI Automation's SetValue (a TextField's text, as typed; a
//                            Slider's position, TEXT read as a number)
//   --scroll ID X Y          scrolls ScrollView ID to the offset (X, Y), without animation
//   --add-row ID TEXT        appends a row to element ID's content through the model, as an adapter
//                            does (a List's rows), its columns TEXT split at "|"; repeatable, in order.
//                            An operation on an element after rows or properties changed waits for
//                            the change to reach the screen (a template row's controls are made then)
//   --set-value ID VALUE     sets element ID's value through the model, as an adapter does (VALUE a
//                            number when it reads as one, else a string)
//   --set-property ID NAME VALUE  sets element ID's property NAME through the model, as an adapter
//                            does (VALUE a number when it reads as one, else a string)
//   --expect-action ACTION   fails unless the action ACTION fired; repeatable
//   --forbid-action ACTION   fails if the action ACTION fired (a renderer's own change taken for the
//                            user's); repeatable
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
    /// The --invoke, --toggle, --set-text, --scroll and --set-property operations, in order.
    var invocations: [Operation] = []

    enum Operation {
        case invoke(Int), invokeRow(Int, Int), invokePart(Int, Int), selectPart(Int, Int), toggle(Int), setText(Int, String), scroll(Int, Double, Double),
             setProperty(Int, String, String), setValue(Int, String), addRow(Int, String)

        var viewID: Int {
            switch self {
            case .invoke(let id), .invokeRow(let id, _), .invokePart(let id, _), .selectPart(let id, _), .toggle(let id), .setText(let id, _), .scroll(let id, _, _), .setProperty(let id, _, _), .setValue(let id, _),
                 .addRow(let id, _):
                return id
            }
        }

        /// Whether it changes the model rather than operating an element on screen.
        var changesModel: Bool {
            switch self {
            case .setProperty, .setValue, .addRow: true
            case .invoke, .invokeRow, .invokePart, .selectPart, .toggle, .setText, .scroll: false
            }
        }
    }
    var expectedActions: [String] = []
    var forbiddenActions: [String] = []
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
        // Relative image paths in the document are taken from its folder (the PNG path was made
        // absolute before).
        if let folder = documentFolder(documentPath) {
            let changed = folder.withCString(encodedAs: UTF16.self) { _wchdir($0) }
            if changed != 0 {
                say("cannot change to the document's folder \(folder)")
            }
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
        ActionUIModel.shared.setDefaultActionHandler { actionID, windowUUID, viewID, _, context in
            let shownContext = context.map { "\($0)" }
            MainActor.assumeIsolated {
                Preview.shared.actionFired(actionID, windowUUID: windowUUID, viewID: viewID, context: shownContext)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(800)) {
            MainActor.assumeIsolated { Preview.shared.invokeThenRender() }
        }
    }

    func actionFired(_ actionID: String, windowUUID: String, viewID: Int, context: String?) {
        firedActions.append(actionID)
        say("action \(actionID) from element \(viewID)" + (context.map { " with context \($0)" } ?? ""))
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
        runOperations(from: 0)
    }

    /// Runs the operations from `start` on, in order. One that operates an element on screen after
    /// one that changed the model waits for the change to be shown first.
    func runOperations(from start: Int) {
        for position in start..<invocations.count {
            let operation = invocations[position]
            if position > start, !operation.changesModel, invocations[position - 1].changesModel {
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(300)) {
                    MainActor.assumeIsolated { Preview.shared.runOperations(from: position) }
                }
                return
            }
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
            case .invokeRow(_, let row):
                if let element = WinUIObject(adopting: actionUIWinUIListCopyItemElement(view.pointer, Int32(row))) {
                    worked = actionUIWinUIAutomationInvoke(element.pointer)
                } else {
                    worked = false
                }
                what = "invoked row \(row) of"
            case .invokePart(_, let part):
                worked = actionUIWinUIAutomationInvokePart(view.pointer, Int32(part))
                what = "invoked part \(part) of"
            case .selectPart(_, let part):
                worked = actionUIWinUIAutomationSelectPart(view.pointer, Int32(part))
                what = "selected part \(part) of"
            case .toggle:
                worked = actionUIWinUIAutomationToggle(view.pointer)
                what = "toggled"
            case .setText(_, let text):
                worked = actionUIWinUIAutomationSetValue(view.pointer, text)
                what = "set the text of"
            case .scroll(_, let x, let y):
                worked = actionUIWinUIScrollViewerScrollTo(view.pointer, x, y)
                what = "scrolled"
            case .setProperty(_, let name, let text):
                let value: Any
                if let number = Double(text) {
                    value = number
                } else {
                    value = text
                }
                ActionUIModel.shared.setElementProperty(windowUUID: "preview", viewID: viewID, propertyName: name, value: value)
                worked = true
                what = "set \(name) to \(text) on"
            case .setValue(_, let text):
                let value: Any = Double(text) ?? text
                ActionUIModel.shared.setElementValue(windowUUID: "preview", viewID: viewID, value: value)
                worked = true
                what = "set the value to \(text) of"
            case .addRow(_, let text):
                let columns = text.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
                ActionUIModel.shared.appendElementRows(windowUUID: "preview", viewID: viewID, rows: [columns])
                worked = true
                what = "added the row \(text) to"
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
        // A template's ids repeat in every row: the first row's.
        for child in node.orderedChildren + node.templateNodes {
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
        // The box's frame in its parent: the element with its padding and frame, as SwiftUI reports one.
        let frame = node.outerView?.layoutFrame ?? ActionUIWinUIRect(x: 0, y: 0, width: 0, height: 0)
        say("\(indent)\(node.element.type) \(node.element.id): (\(frame.x), \(frame.y), \(frame.width), \(frame.height))")
        for child in node.orderedChildren + node.templateNodes {
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

/// `path` made absolute against the current folder (the C runtime's _wfullpath), or `path` itself when
/// that fails.
func absolutePath(_ path: String) -> String {
    let full = path.withCString(encodedAs: UTF16.self) { _wfullpath(nil, $0, 0) }
    guard let full else { return path }
    defer { free(full) }
    return String(decodingCString: full, as: UTF16.self)
}

/// The folder holding the file at `path` (its absolute form), or nil when it has none.
func documentFolder(_ path: String) -> String? {
    let absolute = absolutePath(path)
    guard let slash = absolute.lastIndex(where: { $0 == "\\" || $0 == "/" }) else { return nil }
    let folder = String(absolute[..<slash])
    // A drive's root keeps its backslash: "C:" alone is the current folder on drive C.
    return folder.hasSuffix(":") ? folder + "\\" : folder
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
let usage = "usage: ActionUIWinUIPreview DOCUMENT.json PNG_PATH [WIDTH HEIGHT] [--invoke ID | --invoke-row ID ROW | --invoke-part ID N | --select-part ID N | --toggle ID | --set-text ID TEXT | --scroll ID X Y | --set-value ID VALUE | --set-property ID NAME VALUE | --add-row ID TEXT]... [--expect-action ACTION]... [--forbid-action ACTION]... [--on-action ACTION ID TEXT]..."
guard arguments.count >= 3 else {
    print(usage)
    exit(64)
}
let preview = Preview.shared
preview.documentPath = arguments[1]
// Absolute, since the program changes to the document's folder once it has read it.
preview.pngPath = absolutePath(arguments[2])
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
    } else if option == "--invoke-row", index + 2 < arguments.count, let viewID = Int(arguments[index + 1]),
              let row = Int(arguments[index + 2]) {
        preview.invocations.append(.invokeRow(viewID, row))
        index += 3
    } else if option == "--invoke-part", index + 2 < arguments.count, let viewID = Int(arguments[index + 1]),
              let part = Int(arguments[index + 2]) {
        preview.invocations.append(.invokePart(viewID, part))
        index += 3
    } else if option == "--select-part", index + 2 < arguments.count, let viewID = Int(arguments[index + 1]),
              let part = Int(arguments[index + 2]) {
        preview.invocations.append(.selectPart(viewID, part))
        index += 3
    } else if option == "--toggle", index + 1 < arguments.count, let viewID = Int(arguments[index + 1]) {
        preview.invocations.append(.toggle(viewID))
        index += 2
    } else if option == "--set-text", index + 2 < arguments.count, let viewID = Int(arguments[index + 1]) {
        preview.invocations.append(.setText(viewID, arguments[index + 2]))
        index += 3
    } else if option == "--scroll", index + 3 < arguments.count, let viewID = Int(arguments[index + 1]),
              let x = Double(arguments[index + 2]), let y = Double(arguments[index + 3]) {
        preview.invocations.append(.scroll(viewID, x, y))
        index += 4
    } else if option == "--set-property", index + 3 < arguments.count, let viewID = Int(arguments[index + 1]) {
        preview.invocations.append(.setProperty(viewID, arguments[index + 2], arguments[index + 3]))
        index += 4
    } else if option == "--set-value", index + 2 < arguments.count, let viewID = Int(arguments[index + 1]) {
        preview.invocations.append(.setValue(viewID, arguments[index + 2]))
        index += 3
    } else if option == "--add-row", index + 2 < arguments.count, let viewID = Int(arguments[index + 1]) {
        preview.invocations.append(.addRow(viewID, arguments[index + 2]))
        index += 3
    } else if option == "--expect-action", index + 1 < arguments.count {
        preview.expectedActions.append(arguments[index + 1])
        index += 2
    } else if option == "--forbid-action", index + 1 < arguments.count {
        preview.forbiddenActions.append(arguments[index + 1])
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
let forbidden = preview.forbiddenActions.filter { preview.firedActions.contains($0) }
if !forbidden.isEmpty {
    print("preview: actions that must not fire fired: \(forbidden)")
}
print("preview: run \(ran ? "ok" : "failed"), rendered \(preview.rendered ? "yes" : "no"), PNG \(size) bytes, actions fired \(preview.firedActions.count)")
exit(ran && preview.rendered && size > 0 && missing.isEmpty && forbidden.isEmpty && preview.invocationsWorked ? 0 : 1)
