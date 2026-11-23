// ActionUIWinUI/Apps/Smoke/main.swift - ActionUIWinUISmoke, the WinUI renderer's smoke test from
// Swift: starts WinUI through the shim, installs MainLoopBridge, opens a window whose content is a
// LayoutPanel holding three TextBlocks that Swift stacks vertically (8 apart), changes the first
// text from main-actor work queued three ways (DispatchQueue.main.async, a hop from a global
// queue, a Task on the main actor), checks that WinUI placed each child where Swift's arrange pass
// put it, renders the window's content into a PNG and quits.
//
// Usage: ActionUIWinUISmoke PNG_PATH
// Prints "smoke:" lines; exit status 0 when every step worked, all three main-actor jobs ran on
// the UI thread, every child is where the arrange pass put it and the PNG is not empty. Built and
// run by Scripts/ci-windows.py winui.

import ActionUI
import CWinUI
import Dispatch
import ucrt

@MainActor
final class Smoke {
    static let shared = Smoke()
    static let spacing = 8.0

    var pngPath = ""
    var window: WinUIObject?
    var panel: LayoutPanel?
    var texts: [WinUIObject] = []
    var mainActorJobs: [String] = []
    var arranged: [ActionUIWinUIRect] = []
    var layoutPasses = 0
    var framesMatch = false
    var rendered = false

    func say(_ line: String) {
        print("smoke: \(line)")
    }

    func launched() {
        say("launched")
        guard MainLoopBridge.install() else {
            say("the main queue bridge could not be installed")
            finish()
            return
        }
        do {
            try build()
        } catch {
            say(error.description)
            finish()
            return
        }

        // Main-actor work queued three ways; each must run here, on WinUI's UI thread.
        DispatchQueue.main.async {
            MainActor.assumeIsolated { Smoke.shared.ran("DispatchQueue.main.async") }
        }
        DispatchQueue.global().async {
            DispatchQueue.main.async {
                MainActor.assumeIsolated { Smoke.shared.ran("a hop from a global queue") }
            }
        }
        Task { @MainActor in
            Smoke.shared.ran("Task on the main actor")
        }
        // Then check the layout and render, whatever ran, after the window's layout.
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(800)) {
            MainActor.assumeIsolated { Smoke.shared.checkAndRender() }
        }
    }

    func build() throws(WinUIError) {
        guard let window = WinUIObject(adopting: actionUIWinUIWindowCreate()) else {
            throw WinUIError.last("creating the window")
        }
        self.window = window
        let panel = try LayoutPanel()
        self.panel = panel
        for line in ["set by onLaunched", "A second line, longer than the first one", "Third"] {
            guard let text = WinUIObject(adopting: actionUIWinUITextBlockCreate()) else {
                throw WinUIError.last("creating a text block")
            }
            guard actionUIWinUITextBlockSetText(text.pointer, line) else {
                throw WinUIError.last("setting a text")
            }
            try panel.append(text)
            texts.append(text)
        }
        // A vertical stack: as wide as its widest child, children one above the other.
        panel.measure = { [unowned panel] available in
            let sizes = panel.children.map { $0.measure(ActionUIWinUISize(width: available.width, height: .infinity)) }
            let width = sizes.map(\.width).max() ?? 0
            let height = sizes.map(\.height).reduce(0, +) + Smoke.spacing * Double(max(sizes.count - 1, 0))
            return ActionUIWinUISize(width: width, height: height)
        }
        panel.arrange = { [unowned panel] finalSize in
            var y = 0.0
            var frames: [ActionUIWinUIRect] = []
            for child in panel.children {
                let size = child.measure(ActionUIWinUISize(width: finalSize.width, height: .infinity))
                let frame = ActionUIWinUIRect(x: 0, y: y, width: size.width, height: size.height)
                child.arrange(frame)
                frames.append(frame)
                y += size.height + Smoke.spacing
            }
            Smoke.shared.arranged = frames
            Smoke.shared.layoutPasses += 1
        }
        guard actionUIWinUIWindowSetTitle(window.pointer, "ActionUI WinUI smoke test (Swift)"),
              actionUIWinUIWindowSetContentSize(window.pointer, 480, 160),
              actionUIWinUIWindowSetContent(window.pointer, panel.object.pointer),
              actionUIWinUIWindowActivate(window.pointer) else {
            throw WinUIError.last("setting up the window")
        }
    }

    func ran(_ job: String) {
        mainActorJobs.append(job)
        say("main actor job ran: \(job)")
        if let first = texts.first {
            _ = actionUIWinUITextBlockSetText(first.pointer, "ActionUI on WinUI 3, from Swift: \(mainActorJobs.count) of 3 main-actor jobs")
            // A longer text: WinUI measures and arranges the panel again.
        }
    }

    func describe(_ frame: ActionUIWinUIRect) -> String {
        "(\(frame.x), \(frame.y), \(frame.width), \(frame.height))"
    }

    func checkAndRender() {
        let placed = texts.map(\.layoutFrame)
        framesMatch = !arranged.isEmpty && placed.count == arranged.count && zip(placed, arranged).allSatisfy { actual, expected in
            abs(actual.x - expected.x) < 0.5 && abs(actual.y - expected.y) < 0.5
                && abs(actual.width - expected.width) < 0.5 && abs(actual.height - expected.height) < 0.5
        }
        say("layout passes: \(layoutPasses)")
        say("arranged by Swift: \(arranged.map(describe))")
        say("placed by WinUI:   \(placed.map(describe))")
        say("frames match: \(framesMatch)")
        guard let panel else {
            finish()
            return
        }
        let started = actionUIWinUIRenderToPNG(panel.object.pointer, pngPath, { _, succeeded in
            MainActor.assumeIsolated { Smoke.shared.renderDone(succeeded) }
        }, nil)
        if !started {
            say(WinUIError.last("starting the render").description)
            finish()
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
        texts = []
        panel = nil
        window = nil
        actionUIWinUIQuit()
    }
}

/// The size of the file at `path`, or -1. The C runtime's narrow calls read a path in the ANSI code
/// page, so the wide ones take it as UTF-16 (the shim converts its own UTF-8 path the same way).
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

// Before anything loads a DLL by name: a file named like one in the current folder is never loaded.
_ = actionUIWinUIRemoveCurrentFolderFromDLLSearch()
let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    print("usage: ActionUIWinUISmoke PNG_PATH")
    exit(64)
}
let smoke = Smoke.shared
smoke.pngPath = arguments[1]
_ = smoke.pngPath.withCString(encodedAs: UTF16.self) { _wremove($0) }

guard actionUIWinUIInitialize() else {
    print("smoke: \(WinUIError.last("initializing the Windows App SDK runtime"))")
    exit(1)
}
let ran = actionUIWinUIRun({ _ in
    MainActor.assumeIsolated { Smoke.shared.launched() }
}, nil)
if !ran {
    print("smoke: \(WinUIError.last("running WinUI"))")
}
actionUIWinUIShutdown()

let size = fileSize(smoke.pngPath)
print("smoke: panel objects still alive after the run: \(LayoutPanel.livePanelObjects)")
print("smoke: run \(ran ? "ok" : "failed"), main-actor jobs \(smoke.mainActorJobs.count) of 3, frames match \(smoke.framesMatch ? "yes" : "no"), rendered \(smoke.rendered ? "yes" : "no"), PNG \(size) bytes")
exit(ran && smoke.mainActorJobs.count == 3 && smoke.framesMatch && smoke.rendered && size > 0 ? 0 : 1)
