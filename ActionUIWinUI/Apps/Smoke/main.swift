// ActionUIWinUI/Apps/Smoke/main.swift - ActionUIWinUISmoke, the WinUI renderer's smoke test from
// Swift: starts WinUI through the shim, installs MainLoopBridge, opens a window with a TextBlock,
// changes its text from main-actor work queued three ways (DispatchQueue.main.async, a hop from a
// global queue, a Task on the main actor), renders the window's content into a PNG and quits.
//
// Usage: ActionUIWinUISmoke PNG_PATH
// Prints "smoke:" lines; exit status 0 when every step worked, all three main-actor jobs ran on
// the UI thread and the PNG is not empty. Built and run by Scripts/ci-windows.py winui.

import ActionUI
import CWinUI
import Dispatch
import ucrt

@MainActor
final class Smoke {
    static let shared = Smoke()

    var pngPath = ""
    var window: OpaquePointer?
    var text: OpaquePointer?
    var mainActorJobs: [String] = []
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
        window = actionUIWinUIWindowCreate()
        text = actionUIWinUITextBlockCreate()
        guard let window, let text else {
            say(WinUIError.last("creating the window and its text").description)
            finish()
            return
        }
        var ok = actionUIWinUIWindowSetTitle(window, "ActionUI WinUI smoke test (Swift)")
        ok = ok && actionUIWinUIWindowSetContentSize(window, 480, 160)
        ok = ok && actionUIWinUITextBlockSetText(text, "set by onLaunched")
        ok = ok && actionUIWinUIWindowSetContent(window, text)
        ok = ok && actionUIWinUIWindowActivate(window)
        guard ok else {
            say(WinUIError.last("setting up the window").description)
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
        // Then render, whatever ran, after the window's first layout.
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(800)) {
            MainActor.assumeIsolated { Smoke.shared.render() }
        }
    }

    func ran(_ job: String) {
        mainActorJobs.append(job)
        say("main actor job ran: \(job)")
        if let text {
            _ = actionUIWinUITextBlockSetText(text, "ActionUI on WinUI 3, from Swift: \(mainActorJobs.count) of 3 main-actor jobs")
        }
    }

    func render() {
        guard let text else {
            finish()
            return
        }
        let started = actionUIWinUIRenderToPNG(text, pngPath, { _, succeeded in
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

    /// Releases the window and the text, then quits; on the UI thread, before actionUIWinUIRun
    /// returns.
    func finish() {
        if let window {
            _ = actionUIWinUIWindowClose(window)
        }
        actionUIWinUIRelease(text)
        actionUIWinUIRelease(window)
        text = nil
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
print("smoke: run \(ran ? "ok" : "failed"), main-actor jobs \(smoke.mainActorJobs.count) of 3, rendered \(smoke.rendered ? "yes" : "no"), PNG \(size) bytes")
exit(ran && smoke.mainActorJobs.count == 3 && smoke.rendered && size > 0 ? 0 : 1)
