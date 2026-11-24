// Add-ons/ActionUIHostSurface/Sources/ActionUIHostSurface/HostSurfaceView+WinUIInput.swift
//
// Input on Windows, as AUIHostInputEvent (the C header): the shim reports the panel's pointer events
// (actionUIWinUIElementOnPointerEvents: every button, the mouse, touch and the pen, the wheel), its keys
// (actionUIWinUIElementOnKeyEvents) and its keyboard focus, and this turns them into the header's events by the
// rules of the Apple and Linux views:
// - input only while a client is bound, the surface is on screen and the element is enabled; otherwise events
//   pass on, so an enclosing scroll view still scrolls;
// - the surface takes the wheel, so an enclosing scroll view does not scroll as well;
// - a press captures its pointer, so the drag and the release come to the surface wherever the pointer goes;
// - drags, releases and cancels only for a pointer whose press the client got: a press that began on another
//   element (WinUI moves no capture between elements) does not reach the client as a drag and a release;
// - it never takes focus unasked: a press focuses it when "focusable" is true; Tab and Shift-Tab move focus in
//   and out (not delivered; Control-Tab is the client's);
// - FocusIn and FocusOut follow the panel's keyboard focus and its window's activation, and FocusOut comes before
//   "destroyed".
// Keys with Control, Alt or Windows held are delivered and passed on as well, so the window's and the
// application's shortcuts still work. A key's text is what it types in the keyboard's layout (AltGr's too);
// dead keys and input methods are not composed, as on Linux.
// The wheel's notches are steps (a touchpad's come as parts of one); Windows tells no touchpad from a wheel there.

#if os(Windows)

import FoundationEssentials
import CWinUI
import CActionUIHostSurface

extension HostSurfaceView {

    func installInput() {
        let box = Unmanaged.passRetained(WeakHostSurfaceView(self)).toOpaque()
        if !actionUIWinUIElementOnPointerEvents(panel.pointer, hostSurfacePointerEvent, box, releaseWeakHostSurfaceView) {
            logger.log("HostSurface \(viewID): observing its pointer input failed: \(lastHostShimError())", .warning)
        }
        let keyBox = Unmanaged.passRetained(WeakHostSurfaceView(self)).toOpaque()
        if !actionUIWinUIElementOnKeyEvents(panel.pointer, hostSurfaceKeyEvent, keyBox, releaseWeakHostSurfaceView) {
            logger.log("HostSurface \(viewID): observing its keys failed: \(lastHostShimError())", .warning)
        }
        let focusBox = Unmanaged.passRetained(WeakHostSurfaceView(self)).toOpaque()
        if !actionUIWinUIElementOnFocusChanged(panel.pointer, hostSurfaceFocusChanged, focusBox, releaseWeakHostSurfaceView) {
            logger.log("HostSurface \(viewID): observing its keyboard focus failed: \(lastHostShimError())", .warning)
        }
    }

    /// The panel may take keyboard focus: "focusable", a client, not hidden, enabled (a WinUI panel has no IsEnabled
    /// to keep the focus off, as GTK's sensitivity and the Apple view's inputAllowed do).
    var canTakeFocus: Bool {
        properties.focusable && surfaceID != 0 && !properties.hidden && !isDisabled
    }

    /// Applies canTakeFocus to the panel, gives focus up when it is lost, and delivers the focus change.
    func updateFocusability() {
        let focusable = canTakeFocus
        if appliedFocusable != focusable {
            appliedFocusable = focusable
            _ = actionUIWinUIElementSetFocusable(panel.pointer, focusable)
        }
        if !focusable {
            // Best effort: with no other element to take it, the focus stays, and inputAllowed refuses the keys.
            _ = actionUIWinUIElementGiveUpFocus(panel.pointer)
        }
        updateFocusDelivery()
    }

    /// FocusIn or FocusOut when the surface's keyboard focus changed: focused in the active window, with a client.
    func updateFocusDelivery() {
        let focused = surfaceID != 0 && actionUIWinUIElementHasFocus(panel.pointer)
            && actionUIWinUIElementIsWindowActive(panel.pointer)
        guard focused != focusDelivered else {
            return
        }
        focusDelivered = focused
        var event = AUIHostInputEvent()
        event.kind = Int32(focused ? AUIHostInputFocusIn.rawValue : AUIHostInputFocusOut.rawValue)
        deliverInput(event)
    }

    /// FocusOut now when the client was told it has focus (before "destroyed"): its keys stop here.
    func endFocusDelivery() {
        _ = actionUIWinUIElementGiveUpFocus(panel.pointer)
        guard focusDelivered else {
            return
        }
        focusDelivered = false
        var event = AUIHostInputEvent()
        event.kind = Int32(AUIHostInputFocusOut.rawValue)
        deliverInput(event)
    }

    /// Turns one of the shim's key events into the header's, and delivers it; whether the surface took it.
    fileprivate func handleKey(_ key: ActionUIWinUIKeyEvent) -> Bool {
        let isTab = key.virtualKey == 0x09  // VK_TAB
        let control = key.modifiers & UInt32(ActionUIWinUIModifierControl) != 0
        // Tab moves focus on, as for any control; with Control held it is the client's.
        guard inputAllowed, actionUIWinUIElementHasFocus(panel.pointer), !(isTab && !control) else {
            return false
        }
        var input = AUIHostInputEvent()
        input.kind = Int32(key.type == ActionUIWinUIKeyDown ? AUIHostInputKeyDown.rawValue : AUIHostInputKeyUp.rawValue)
        input.modifiers = Self.modifiers(key.modifiers)
        input.keyCode = key.scanCode
        input.timestampSeconds = Double(key.timeMilliseconds) / 1000
        let text = key.text.map { String(cString: $0) }
        deliverInput(input, code: HostSurfaceWinUIKeys.code(scanCode: key.scanCode, virtualKey: key.virtualKey), text: text)
        // A possible shortcut goes on to the window and the application too. Not Control-Tab, the client's, and not
        // a key that typed text: AltGr, which Windows reports as Control with Alt.
        let shortcut = key.modifiers & UInt32(ActionUIWinUIModifierControl | ActionUIWinUIModifierAlt | ActionUIWinUIModifierWindows) != 0
        return isTab || !shortcut || text != nil
    }

    /// Input reaches the client: one is bound, the surface is on screen, and the element is enabled.
    var inputAllowed: Bool {
        surfaceID != 0 && !suspendedSent && !isDisabled
    }

    /// Turns one of the shim's pointer events into the header's, and delivers it; whether the surface took it.
    fileprivate func handle(_ pointer: ActionUIWinUIPointerEvent) -> Bool {
        guard inputAllowed else {
            return false
        }
        var input = AUIHostInputEvent()
        input.x = pointer.x
        input.y = pointer.y
        input.modifiers = Self.modifiers(pointer.modifiers)
        input.pointerType = Self.pointerType(pointer.device)
        // Stable while a touch lasts; 0 for the mouse and the pen, as on Linux.
        input.pointerID = pointer.device == ActionUIWinUIPointerDeviceTouch ? Int64(pointer.pointerID) : 0
        input.pressure = pointer.pressure
        input.tiltX = min(max(pointer.tiltX / 90, -1), 1)
        input.tiltY = min(max(pointer.tiltY / 90, -1), 1)
        input.timestampSeconds = Double(pointer.timestampMicroseconds) / 1_000_000
        let touch = pointer.device == ActionUIWinUIPointerDeviceTouch
        switch pointer.type {
        case ActionUIWinUIPointerEventEntered, ActionUIWinUIPointerEventExited:
            // A finger has no hover: WinUI reports its touch and lift as entering and leaving.
            guard !touch else {
                return false
            }
            input.kind = Int32(pointer.type == ActionUIWinUIPointerEventEntered
                               ? AUIHostInputPointerEnter.rawValue : AUIHostInputPointerExit.rawValue)
            input.pressure = 0
            deliverInput(input)
            return false
        case ActionUIWinUIPointerEventPressed:
            // A press focuses the surface, as a click does on the other platforms: FocusIn before the press.
            if canTakeFocus, !actionUIWinUIElementHasFocus(panel.pointer) {
                _ = actionUIWinUIElementFocus(panel.pointer)
            }
            // Also for a surface that kept the focus in an inactive window, should the activation come late.
            updateFocusDelivery()
            pressedPointers.insert(pointer.pointerID)
            input.kind = Int32(AUIHostInputPointerDown.rawValue)
            input.button = Self.button(pointer.button)
            input.clickCount = touch ? 1 : countClick(button: input.button, pointer)
        case ActionUIWinUIPointerEventReleased:
            guard pressedPointers.contains(pointer.pointerID) else {
                return false
            }
            if pointer.buttons == 0 {
                pressedPointers.remove(pointer.pointerID)
            }
            input.kind = Int32(AUIHostInputPointerUp.rawValue)
            input.button = Self.button(pointer.button)
            input.clickCount = touch ? 1 : clickCounter.count
            input.pressure = 0
        case ActionUIWinUIPointerEventMoved:
            if pointer.buttons != 0 {
                // A button held from a press elsewhere: not the client's drag.
                guard pressedPointers.contains(pointer.pointerID) else {
                    return false
                }
                input.kind = Int32(AUIHostInputPointerDrag.rawValue)
                // The button that drags, as on Apple platforms and Linux.
                input.button = Self.heldButton(pointer.buttons)
            } else {
                input.kind = Int32(AUIHostInputPointerMove.rawValue)
                input.pressure = 0
            }
        case ActionUIWinUIPointerEventCanceled:
            guard pressedPointers.remove(pointer.pointerID) != nil else {
                return false
            }
            input.kind = Int32(AUIHostInputPointerCancel.rawValue)
            input.pressure = 0
        case ActionUIWinUIPointerEventWheel:
            input.kind = Int32(AUIHostInputScroll.rawValue)
            // How far the content moves: against the wheel, as on Linux (a wheel turned toward the user moves it up).
            input.deltaX = -pointer.wheelX
            input.deltaY = -pointer.wheelY
            input.scrollUnit = Int32(AUIHostScrollSteps.rawValue)
            input.scrollPhase = Int32(AUIHostScrollPhaseNone.rawValue)
            input.pressure = 0
        default:
            return false
        }
        deliverInput(input)
        return true
    }

    /// The press's click count, by Windows' double-click time and distance (pixels, here in points).
    private func countClick(button: Int32, _ pointer: ActionUIWinUIPointerEvent) -> Int32 {
        var milliseconds: UInt32 = 500
        var width = 4.0
        var height = 4.0
        actionUIWinUIDoubleClickLimits(&milliseconds, &width, &height)
        let scale = max(lastGeometry?.scale ?? 1, 1)
        // The click must stay within the rectangle centered on the first: half its size either way.
        let distance = max(width, height) / 2 / scale
        return clickCounter.press(button: button, x: pointer.x, y: pointer.y,
                                  timeMilliseconds: UInt32(truncatingIfNeeded: pointer.timestampMicroseconds / 1000),
                                  doubleClickTime: milliseconds, doubleClickDistance: distance)
    }

    // MARK: the shim's values as the header's

    /// 0 primary, 1 secondary, 2 middle; back and forward become 7 and 8, as on Linux (past the three the header
    /// names).
    static func button(_ shimButton: Int32) -> Int32 {
        switch shimButton {
        case 3: return 7
        case 4: return 8
        default: return max(shimButton, 0)
        }
    }

    /// The lowest button held, by the header's numbers.
    static func heldButton(_ buttons: UInt32) -> Int32 {
        let order: [(UInt32, Int32)] = [
            (UInt32(ActionUIWinUIPointerButtonLeft), 0), (UInt32(ActionUIWinUIPointerButtonRight), 1),
            (UInt32(ActionUIWinUIPointerButtonMiddle), 2), (UInt32(ActionUIWinUIPointerButtonBack), 7),
            (UInt32(ActionUIWinUIPointerButtonForward), 8),
        ]
        return order.first { buttons & $0.0 != 0 }?.1 ?? 0
    }

    static func modifiers(_ shim: UInt32) -> UInt32 {
        var bits: UInt32 = 0
        if shim & UInt32(ActionUIWinUIModifierShift) != 0 { bits |= UInt32(AUIHostModifierShift) }
        if shim & UInt32(ActionUIWinUIModifierControl) != 0 { bits |= UInt32(AUIHostModifierControl) }
        if shim & UInt32(ActionUIWinUIModifierAlt) != 0 { bits |= UInt32(AUIHostModifierAlt) }
        if shim & UInt32(ActionUIWinUIModifierWindows) != 0 { bits |= UInt32(AUIHostModifierMeta) }
        if shim & UInt32(ActionUIWinUIModifierCapsLock) != 0 { bits |= UInt32(AUIHostModifierCapsLock) }
        return bits
    }

    static func pointerType(_ device: ActionUIWinUIPointerDevice) -> Int32 {
        switch device {
        case ActionUIWinUIPointerDeviceTouch: return Int32(AUIHostPointerTouch.rawValue)
        case ActionUIWinUIPointerDevicePen: return Int32(AUIHostPointerPen.rawValue)
        default: return Int32(AUIHostPointerMouse.rawValue)
        }
    }
}

/// The shim's pointer events, to the view through its weak reference (released by releaseWeakHostSurfaceView).
private let hostSurfacePointerEvent: @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<ActionUIWinUIPointerEvent>?) -> Bool = { context, event in
    guard let context, let event else {
        return false
    }
    nonisolated(unsafe) let target = (context, event.pointee)
    return MainActor.assumeIsolated {
        guard let view = Unmanaged<WeakHostSurfaceView>.fromOpaque(target.0).takeUnretainedValue().view else {
            return false
        }
        return view.handle(target.1)
    }
}

/// The shim's key events, to the view through its weak reference.
private let hostSurfaceKeyEvent: @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<ActionUIWinUIKeyEvent>?) -> Bool = { context, event in
    guard let context, let event else {
        return false
    }
    // The text pointer is valid during this call only: handleKey copies it before returning.
    nonisolated(unsafe) let target = (context, event.pointee)
    return MainActor.assumeIsolated {
        guard let view = Unmanaged<WeakHostSurfaceView>.fromOpaque(target.0).takeUnretainedValue().view else {
            return false
        }
        return view.handleKey(target.1)
    }
}

/// The panel's keyboard focus changed.
private let hostSurfaceFocusChanged: ActionUIWinUICallback = { context in
    guard let context else {
        return
    }
    nonisolated(unsafe) let box = context
    MainActor.assumeIsolated {
        Unmanaged<WeakHostSurfaceView>.fromOpaque(box).takeUnretainedValue().view?.updateFocusDelivery()
    }
}

#endif
