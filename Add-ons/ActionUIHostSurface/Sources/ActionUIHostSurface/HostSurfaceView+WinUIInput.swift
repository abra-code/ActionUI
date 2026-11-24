// Add-ons/ActionUIHostSurface/Sources/ActionUIHostSurface/HostSurfaceView+WinUIInput.swift
//
// Pointer input on Windows, as AUIHostInputEvent (the C header): the shim reports the panel's pointer events
// (actionUIWinUIElementOnPointerEvents: every button, the mouse, touch and the pen, the wheel), and this turns
// them into the header's events by the rules of the Apple and Linux views:
// - input only while a client is bound, the surface is on screen and the element is enabled; otherwise events
//   pass on, so an enclosing scroll view still scrolls;
// - the surface takes the wheel, so an enclosing scroll view does not scroll as well;
// - a press captures its pointer, so the drag and the release come to the surface wherever the pointer goes;
// - drags, releases and cancels only for a pointer whose press the client got: a press that began on another
//   element (WinUI moves no capture between elements) does not reach the client as a drag and a release.
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

#endif
