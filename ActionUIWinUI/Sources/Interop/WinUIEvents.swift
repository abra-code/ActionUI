// Sources/Interop/WinUIEvents.swift
/*
 Swift closures as the handlers of a control's events (ActionUIWinUIShim.h, MARK: Events). Each
 handler is a box held by the shim with Unmanaged.passRetained; the shim calls the box's closure on
 the UI thread for each event and gives the reference back (destroyContext) once the control is
 gone. A closure that refers to what holds the control (a RenderNode) captures it weakly: the
 node holds the control, which holds the box.
*/

import CWinUI

@MainActor private final class EventBox {
    let action: @MainActor () -> Void

    init(_ action: @escaping @MainActor () -> Void) {
        self.action = action
    }
}

/// The box behind a callback's context, taken before entering the main actor: the box is
/// main-actor isolated, so it may cross; the raw pointer may not.
private func eventBox(_ context: UnsafeMutableRawPointer?) -> EventBox? {
    context.map { Unmanaged<EventBox>.fromOpaque($0).takeUnretainedValue() }
}

private let fireEvent: ActionUIWinUICallback = { context in
    let box = eventBox(context)
    MainActor.assumeIsolated {
        box?.action()
    }
}

// Gives back the reference passRetained took, once the shim lets go of the handler.
private let releaseEvent: ActionUIWinUICallback = { context in
    guard let context else { return }
    Unmanaged<EventBox>.fromOpaque(context).release()
}

/// A shim function that registers an event handler: (control, handler, context, destroyContext).
package typealias WinUIEventRegistration = (OpaquePointer?, ActionUIWinUICallback, UnsafeMutableRawPointer?, ActionUIWinUICallback) -> Bool

@MainActor package enum WinUIEvents {
    /// Runs `action` for each `event` of `control` (an actionUIWinUI...On... function), until the
    /// control is gone. Logs and returns false when the shim refused the handler.
    @discardableResult
    package static func connect(_ control: WinUIObject, _ event: WinUIEventRegistration, _ name: String,
                        _ action: @escaping @MainActor () -> Void) -> Bool {
        let context = Unmanaged.passRetained(EventBox(action)).toOpaque()
        // On failure the shim has already called releaseEvent.
        guard event(control.pointer, fireEvent, context, releaseEvent) else {
            ActionUIModel.shared.logger.log("WinUIEvents: \(WinUIError.last("connecting \(name)"))", .error)
            return false
        }
        return true
    }
}
