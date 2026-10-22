// Tests/Support/AdwaitaTestHost.swift
/*
 What the renderer tests share: GTK and libadwaita initialized once per process (or a reason to
 skip, when there is no display), and the GLib main loop run by hand, since no application runs it
 in a test.
*/

import XCTest
import CAdwaita
@testable import ActionUI

@MainActor
enum AdwaitaTestHost {
    private static var initialized: Bool?

    /// Initializes GTK, libadwaita and MainLoopBridge, once. Throws XCTSkip when GTK cannot open a
    /// display: the renderer tests then skip, and the Core tests in the same run still pass.
    static func initialize() throws {
        if initialized == nil {
            let opened = gtk_init_check() != 0
            if opened {
                adw_init()
                MainLoopBridge.install()
            }
            initialized = opened
        }
        if initialized != true {
            throw XCTSkip("GTK could not open a display; renderer tests run in the desktop session")
        }
    }

    /// Runs the default main context until nothing is ready to run. This also runs libdispatch's
    /// main queue, through MainLoopBridge.
    static func drainMainLoop() {
        var iterations = 0
        while g_main_context_iteration(nil, 0) != 0 && iterations < 10_000 {
            iterations += 1
        }
    }

    /// Emits a signal that takes no arguments and returns nothing ("clicked", "activate"), as the
    /// user's input would, synchronously. (gtk_widget_activate on a button only starts its press
    /// animation, and g_signal_emit_by_name is variadic, which Swift cannot call.)
    static func emit(_ signal: String, on instance: UnsafeMutableRawPointer) {
        let type = instance.assumingMemoryBound(to: GTypeInstance.self).pointee.g_class.pointee.g_type
        let id = g_signal_lookup(signal, type)
        precondition(id != 0, "\(signal) is not a signal of this object")
        var target = GValue()
        g_value_init(&target, type)
        g_value_set_object(&target, instance)
        g_signal_emitv(&target, id, 0, nil)
        g_value_unset(&target)
    }

    /// Runs the default main context until `condition` holds, waiting for sources such as timers,
    /// for at most `timeoutMilliseconds`. Returns whether the condition held.
    static func runMainLoop(until condition: () -> Bool, timeoutMilliseconds: Int = 2000) -> Bool {
        let deadline = g_get_monotonic_time() + timeoutMilliseconds * 1000
        while !condition() {
            if g_get_monotonic_time() >= deadline {
                return false
            }
            // Non-blocking, so the deadline is checked even when nothing ever becomes ready.
            if g_main_context_iteration(nil, 0) == 0 {
                g_usleep(1000)
            }
        }
        return true
    }
}

/// A counter the main-actor closures under test can change.
@MainActor
final class CallCounter {
    var count = 0
}
