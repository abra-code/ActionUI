// ActionUIWinUI/Apps/Preview/main.swift - ActionUIWinUIPreview: renders an ActionUI document with
// the WinUI renderer into a PNG, in a window of the given content size, and prints where WinUI
// placed each element (its frame in its parent), so a run can be compared with SwiftUI's and GTK's.
//
// Usage: ActionUIWinUIPreview DOCUMENT.json PNG_PATH [WIDTH HEIGHT]
// Prints "preview:" lines; exit status 0 when the document loaded, rendered and the PNG is not
// empty. Built and run by Scripts/ci-windows.py winui.

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
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(800)) {
            MainActor.assumeIsolated { Preview.shared.reportAndRender() }
        }
    }

    func reportAndRender() {
        if let root = tree?.root {
            report(root, indent: "")
        }
        guard let content = tree?.view else {
            finish()
            return
        }
        let started = actionUIWinUIRenderToPNG(content.pointer, pngPath, { _, succeeded in
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
guard arguments.count == 3 || arguments.count == 5 else {
    print("usage: ActionUIWinUIPreview DOCUMENT.json PNG_PATH [WIDTH HEIGHT]")
    exit(64)
}
let preview = Preview.shared
preview.documentPath = arguments[1]
preview.pngPath = arguments[2]
if arguments.count == 5, let width = Double(arguments[3]), let height = Double(arguments[4]), width > 0, height > 0 {
    preview.contentSize = ActionUIWinUISize(width: width, height: height)
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
print("preview: run \(ran ? "ok" : "failed"), rendered \(preview.rendered ? "yes" : "no"), PNG \(size) bytes")
exit(ran && preview.rendered && size > 0 ? 0 : 1)
