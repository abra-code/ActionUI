// Sources/Interop/MainLoopBridge.swift
/*
 Runs Swift's main-actor work while WinUI's message loop owns the main thread.

 On Windows the main actor's jobs (Task { @MainActor in }, await MainActor.run,
 DispatchQueue.main.async) go to libdispatch's main queue. Nothing drains that queue while
 actionUIWinUIRun blocks in WinUI's loop, so main-actor work would wait forever. libdispatch
 exposes the hooks CoreFoundation's run loop uses on Windows: an auto-reset event that is signaled
 when the main queue has work, and a call that runs it. The shim watches that event and calls back
 on the UI thread as soon as work arrives, with no polling. (On Linux, MainLoopBridge does the
 same with a GLib watch on libdispatch's eventfd.)
*/

import CWinUI

private let drainMainQueue: @convention(c) (UnsafeMutableRawPointer?) -> Void = { _ in
    _dispatch_main_queue_callback_4CF(nil)
}

@MainActor package enum MainLoopBridge {
    private static var installed = false

    /// Watches libdispatch's main queue from WinUI's UI thread. Call it once, on the main thread,
    /// while actionUIWinUIRun runs (from its on-launched callback); later calls do nothing.
    /// Returns false when the watch could not be set up.
    @discardableResult
    package static func install() -> Bool {
        guard !installed else { return true }
        guard let handle = _dispatch_get_main_queue_handle_4CF() else {
            ActionUIModel.shared.logger.log("MainLoopBridge: libdispatch has no main queue event; main-actor work will not run", .error)
            return false
        }
        guard actionUIWinUIWatchHandle(handle, drainMainQueue, nil) else {
            ActionUIModel.shared.logger.log("MainLoopBridge: \(WinUIError.last("watching the main queue"))", .error)
            return false
        }
        installed = true
        return true
    }
}
