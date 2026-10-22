// Sources/Interop/MainLoopBridge.swift
/*
 Runs Swift's main-actor work while GTK's main loop owns the main thread.

 On Linux the main actor's jobs (Task { @MainActor in }, await MainActor.run,
 DispatchQueue.main.async) go to libdispatch's main queue. Nothing drains that queue while
 g_application_run blocks in the GLib loop, so main-actor work would wait forever. libdispatch
 exposes the hooks CoreFoundation's run loop uses on Linux: an eventfd that becomes readable when
 the main queue has work, and a call that runs it. A GLib watch on that descriptor runs the queue
 as soon as work arrives, with no polling.
*/

import CAdwaita
import Glibc

private let drainMainQueue: @convention(c) (Int32, GIOCondition, gpointer?) -> gboolean = { descriptor, _, _ in
    // Reading resets the eventfd; the descriptor is non-blocking, so a read with nothing to read
    // returns at once.
    var count: UInt64 = 0
    _ = read(descriptor, &count, MemoryLayout<UInt64>.size)
    _dispatch_main_queue_callback_4CF(nil)
    return 1  // G_SOURCE_CONTINUE
}

@MainActor enum MainLoopBridge {
    private static var installed = false

    /// Watches libdispatch's main queue from the default GLib main context. Call it once, on the
    /// main thread, before the main loop runs; later calls do nothing.
    static func install() {
        guard !installed else { return }
        let descriptor = _dispatch_get_main_queue_handle_4CF()
        guard descriptor >= 0 else {
            ActionUIModel.shared.logger.log("MainLoopBridge: libdispatch has no main queue descriptor; main-actor work will not run", .error)
            return
        }
        installed = true
        let flags = fcntl(descriptor, F_GETFL)
        if flags >= 0 {
            _ = fcntl(descriptor, F_SETFL, flags | O_NONBLOCK)
        }
        g_unix_fd_add_full(G_PRIORITY_DEFAULT, descriptor, G_IO_IN, drainMainQueue, nil, nil)
    }
}
