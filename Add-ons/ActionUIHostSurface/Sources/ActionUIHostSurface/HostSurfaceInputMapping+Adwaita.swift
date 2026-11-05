// Add-ons/ActionUIHostSurface/Sources/ActionUIHostSurface/HostSurfaceInputMapping+Adwaita.swift
//
// GDK's input values to the C header's: buttons, modifiers, scroll deltas, key names and click counts. Pure, so
// the tables are unit-tested without events (GDK events cannot be made by a program).

#if os(Linux)

import CAdwaita
import CActionUIHostSurface

enum HostSurfaceGtkInput {

    /// 0 primary, 1 secondary, 2 middle, from GDK's button number (1 left, 2 middle, 3 right; 8 and 9 back and
    /// forward become 7 and 8, past the three the header names).
    static func button(_ gdkButton: UInt32) -> Int32 {
        switch gdkButton {
        case 1: return 0
        case 2: return 2
        case 3: return 1
        case 0: return 0
        default: return Int32(gdkButton) - 1
        }
    }

    /// AUIHostModifier bits from GDK's modifier state.
    static func modifiers(_ state: UInt32) -> UInt32 {
        var bits: UInt32 = 0
        if state & GDK_SHIFT_MASK.rawValue != 0 { bits |= UInt32(AUIHostModifierShift) }
        if state & GDK_CONTROL_MASK.rawValue != 0 { bits |= UInt32(AUIHostModifierControl) }
        if state & GDK_ALT_MASK.rawValue != 0 { bits |= UInt32(AUIHostModifierAlt) }
        if state & (GDK_SUPER_MASK.rawValue | GDK_META_MASK.rawValue) != 0 { bits |= UInt32(AUIHostModifierMeta) }
        if state & GDK_LOCK_MASK.rawValue != 0 { bits |= UInt32(AUIHostModifierCapsLock) }
        return bits
    }

    /// A pointer button is held: a motion is a drag.
    static func buttonHeld(_ state: UInt32) -> Bool {
        let buttons = GDK_BUTTON1_MASK.rawValue | GDK_BUTTON2_MASK.rawValue | GDK_BUTTON3_MASK.rawValue
            | GDK_BUTTON4_MASK.rawValue | GDK_BUTTON5_MASK.rawValue
        return state & buttons != 0
    }

    /// The header's button for a drag: the primary when held, else the secondary, else the middle.
    static func heldButton(_ state: UInt32) -> Int32 {
        if state & GDK_BUTTON1_MASK.rawValue != 0 { return 0 }
        if state & GDK_BUTTON3_MASK.rawValue != 0 { return 1 }
        if state & GDK_BUTTON2_MASK.rawValue != 0 { return 2 }
        return 0
    }

    /// Control, Alt or Super is held: the key may be a shortcut of the window or the application.
    static func isShortcutCandidate(_ state: UInt32) -> Bool {
        state & (GDK_CONTROL_MASK.rawValue | GDK_ALT_MASK.rawValue | GDK_SUPER_MASK.rawValue | GDK_META_MASK.rawValue) != 0
    }

    /// How far the content should move (the header's sign: positive to the right and down) for GDK's deltas,
    /// which are how far the view scrolls.
    static func contentDelta(_ dx: Double, _ dy: Double) -> (Double, Double) {
        (-dx, -dy)
    }

    /// The content movement of one discrete wheel step, in steps.
    static func stepDelta(_ direction: GdkScrollDirection) -> (Double, Double)? {
        switch direction {
        case GDK_SCROLL_UP: return (0, 1)
        case GDK_SCROLL_DOWN: return (0, -1)
        case GDK_SCROLL_LEFT: return (1, 0)
        case GDK_SCROLL_RIGHT: return (-1, 0)
        default: return nil
        }
    }

    /// The text a key produced, or nil for none, for control characters, and while Control, Alt or Super is
    /// held (a shortcut, not text).
    static func text(unicode: UInt32, state: UInt32) -> String? {
        guard unicode >= 0x20, unicode != 0x7F, !isShortcutCandidate(state), let scalar = Unicode.Scalar(unicode) else {
            return nil
        }
        return String(Character(scalar))
    }

    /// The W3C UI Events code for a GDK hardware key code (an XKB key code: the Linux evdev code plus 8), or "".
    static func code(hardwareKeycode: UInt32) -> String {
        guard hardwareKeycode >= 8 else {
            return ""
        }
        return evdevCodes[hardwareKeycode - 8] ?? ""
    }

    /// Linux input event codes (linux/input-event-codes.h) to W3C UI Events codes.
    private static let evdevCodes: [UInt32: String] = {
        var table: [UInt32: String] = [
            1: "Escape", 11: "Digit0", 12: "Minus", 13: "Equal", 14: "Backspace", 15: "Tab",
            26: "BracketLeft", 27: "BracketRight", 28: "Enter", 29: "ControlLeft",
            39: "Semicolon", 40: "Quote", 41: "Backquote", 42: "ShiftLeft", 43: "Backslash",
            51: "Comma", 52: "Period", 53: "Slash", 54: "ShiftRight", 55: "NumpadMultiply", 56: "AltLeft",
            57: "Space", 58: "CapsLock", 69: "NumLock", 70: "ScrollLock",
            71: "Numpad7", 72: "Numpad8", 73: "Numpad9", 74: "NumpadSubtract", 75: "Numpad4", 76: "Numpad5",
            77: "Numpad6", 78: "NumpadAdd", 79: "Numpad1", 80: "Numpad2", 81: "Numpad3", 82: "Numpad0",
            83: "NumpadDecimal", 86: "IntlBackslash", 87: "F11", 88: "F12",
            96: "NumpadEnter", 97: "ControlRight", 98: "NumpadDivide", 99: "PrintScreen", 100: "AltRight",
            102: "Home", 103: "ArrowUp", 104: "PageUp", 105: "ArrowLeft", 106: "ArrowRight", 107: "End",
            108: "ArrowDown", 109: "PageDown", 110: "Insert", 111: "Delete", 117: "NumpadEqual", 119: "Pause",
            125: "MetaLeft", 126: "MetaRight", 127: "ContextMenu",
        ]
        for (offset, digit) in (1...9).enumerated() {
            table[UInt32(2 + offset)] = "Digit\(digit)"
        }
        for (offset, number) in (1...10).enumerated() {
            table[UInt32(59 + offset)] = "F\(number)"
        }
        let rows: [(UInt32, String)] = [(16, "QWERTYUIOP"), (30, "ASDFGHJKL"), (44, "ZXCVBNM")]
        for (start, letters) in rows {
            for (offset, letter) in letters.enumerated() {
                table[start + UInt32(offset)] = "Key\(letter)"
            }
        }
        return table
    }()
}

/// Counts the presses of a multiple click: the next press of the same button within the double-click time and
/// distance counts on, any other press starts again at 1.
struct HostSurfaceClickCounter {
    private var lastTime: UInt32 = 0
    private var lastX = 0.0
    private var lastY = 0.0
    private var lastButton: Int32 = -1
    private(set) var count: Int32 = 0

    mutating func press(button: Int32, x: Double, y: Double, timeMilliseconds: UInt32,
                        doubleClickTime: UInt32, doubleClickDistance: Double) -> Int32 {
        let close = abs(x - lastX) <= doubleClickDistance && abs(y - lastY) <= doubleClickDistance
        // Event times wrap after 49 days; the subtraction wraps with them.
        let soon = timeMilliseconds &- lastTime <= doubleClickTime
        count = (button == lastButton && close && soon && count > 0) ? count + 1 : 1
        lastTime = timeMilliseconds
        lastX = x
        lastY = y
        lastButton = button
        return count
    }
}

#endif
