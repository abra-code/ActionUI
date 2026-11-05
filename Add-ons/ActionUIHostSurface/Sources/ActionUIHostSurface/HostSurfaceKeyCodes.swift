// Add-ons/ActionUIHostSurface/Sources/ActionUIHostSurface/HostSurfaceKeyCodes.swift
//
// Portable key names for AUIHostInputEvent.code: the W3C UI Events "code" values (KeyA, Digit1,
// ArrowLeft, ShiftLeft, ...), which name a physical key position whatever the keyboard layout. Pure
// tables, so they are tested without events.
//
// - macOS: virtual key codes (NSEvent.keyCode, the kVK_ constants of Carbon's Events.h).
// - iOS: USB HID keyboard usages (UIKey.keyCode, UIKeyboardHIDUsage).

enum HostSurfaceKeyCodes {

    /// The W3C code for a macOS virtual key code, or "" when it has none.
    static func code(macKeyCode: UInt16) -> String {
        macCodes[macKeyCode] ?? ""
    }

    /// The W3C code for a USB HID keyboard usage, or "" when it has none.
    static func code(hidUsage: Int) -> String {
        hidCodes[hidUsage] ?? ""
    }

    private static let macCodes: [UInt16: String] = [
        0x00: "KeyA", 0x01: "KeyS", 0x02: "KeyD", 0x03: "KeyF", 0x04: "KeyH", 0x05: "KeyG", 0x06: "KeyZ",
        0x07: "KeyX", 0x08: "KeyC", 0x09: "KeyV", 0x0A: "IntlBackslash", 0x0B: "KeyB", 0x0C: "KeyQ",
        0x0D: "KeyW", 0x0E: "KeyE", 0x0F: "KeyR", 0x10: "KeyY", 0x11: "KeyT", 0x12: "Digit1",
        0x13: "Digit2", 0x14: "Digit3", 0x15: "Digit4", 0x16: "Digit6", 0x17: "Digit5", 0x18: "Equal",
        0x19: "Digit9", 0x1A: "Digit7", 0x1B: "Minus", 0x1C: "Digit8", 0x1D: "Digit0",
        0x1E: "BracketRight", 0x1F: "KeyO", 0x20: "KeyU", 0x21: "BracketLeft", 0x22: "KeyI", 0x23: "KeyP",
        0x24: "Enter", 0x25: "KeyL", 0x26: "KeyJ", 0x27: "Quote", 0x28: "KeyK", 0x29: "Semicolon",
        0x2A: "Backslash", 0x2B: "Comma", 0x2C: "Slash", 0x2D: "KeyN", 0x2E: "KeyM", 0x2F: "Period",
        0x30: "Tab", 0x31: "Space", 0x32: "Backquote", 0x33: "Backspace", 0x35: "Escape",
        0x36: "MetaRight", 0x37: "MetaLeft", 0x38: "ShiftLeft", 0x39: "CapsLock", 0x3A: "AltLeft",
        0x3B: "ControlLeft", 0x3C: "ShiftRight", 0x3D: "AltRight", 0x3E: "ControlRight", 0x3F: "Fn",
        0x40: "F17", 0x41: "NumpadDecimal", 0x43: "NumpadMultiply", 0x45: "NumpadAdd", 0x47: "NumLock",
        0x48: "AudioVolumeUp", 0x49: "AudioVolumeDown", 0x4A: "AudioVolumeMute", 0x4B: "NumpadDivide",
        0x4C: "NumpadEnter", 0x4E: "NumpadSubtract", 0x4F: "F18", 0x50: "F19", 0x51: "NumpadEqual",
        0x52: "Numpad0", 0x53: "Numpad1", 0x54: "Numpad2", 0x55: "Numpad3", 0x56: "Numpad4",
        0x57: "Numpad5", 0x58: "Numpad6", 0x59: "Numpad7", 0x5A: "F20", 0x5B: "Numpad8", 0x5C: "Numpad9",
        0x5D: "IntlYen", 0x5E: "IntlRo", 0x5F: "NumpadComma", 0x60: "F5", 0x61: "F6", 0x62: "F7",
        0x63: "F3", 0x64: "F8", 0x65: "F9", 0x66: "Lang2", 0x67: "F11", 0x68: "Lang1", 0x69: "F13",
        0x6A: "F16", 0x6B: "F14", 0x6D: "F10", 0x6E: "ContextMenu", 0x6F: "F12", 0x71: "F15",
        0x72: "Insert", 0x73: "Home", 0x74: "PageUp", 0x75: "Delete", 0x76: "F4", 0x77: "End", 0x78: "F2",
        0x79: "PageDown", 0x7A: "F1", 0x7B: "ArrowLeft", 0x7C: "ArrowRight", 0x7D: "ArrowDown",
        0x7E: "ArrowUp",
    ]

    private static let hidCodes: [Int: String] = {
        var codes: [Int: String] = [:]
        // 0x04...0x1D: KeyA...KeyZ.
        for (offset, letter) in "ABCDEFGHIJKLMNOPQRSTUVWXYZ".enumerated() {
            codes[0x04 + offset] = "Key\(letter)"
        }
        // 0x1E...0x26: Digit1...Digit9, then 0x27: Digit0.
        for digit in 1...9 {
            codes[0x1D + digit] = "Digit\(digit)"
        }
        codes[0x27] = "Digit0"
        // 0x3A...0x45: F1...F12; 0x68...0x73: F13...F24.
        for number in 1...12 {
            codes[0x39 + number] = "F\(number)"
        }
        for number in 13...24 {
            codes[0x68 + number - 13] = "F\(number)"
        }
        // 0x59...0x61: Numpad1...Numpad9, then 0x62: Numpad0.
        for digit in 1...9 {
            codes[0x58 + digit] = "Numpad\(digit)"
        }
        codes[0x62] = "Numpad0"
        let named: [Int: String] = [
            0x28: "Enter", 0x29: "Escape", 0x2A: "Backspace", 0x2B: "Tab", 0x2C: "Space", 0x2D: "Minus",
            0x2E: "Equal", 0x2F: "BracketLeft", 0x30: "BracketRight", 0x31: "Backslash",
            0x32: "Backslash",   // the non-US # and ~ key, which W3C UI Events also names Backslash
            0x33: "Semicolon",
            0x34: "Quote", 0x35: "Backquote", 0x36: "Comma", 0x37: "Period", 0x38: "Slash", 0x39: "CapsLock",
            0x46: "PrintScreen", 0x47: "ScrollLock", 0x48: "Pause", 0x49: "Insert", 0x4A: "Home",
            0x4B: "PageUp", 0x4C: "Delete", 0x4D: "End", 0x4E: "PageDown", 0x4F: "ArrowRight",
            0x50: "ArrowLeft", 0x51: "ArrowDown", 0x52: "ArrowUp", 0x53: "NumLock", 0x54: "NumpadDivide",
            0x55: "NumpadMultiply", 0x56: "NumpadSubtract", 0x57: "NumpadAdd", 0x58: "NumpadEnter",
            0x63: "NumpadDecimal", 0x64: "IntlBackslash", 0x65: "ContextMenu", 0x67: "NumpadEqual",
            0x7F: "AudioVolumeMute", 0x80: "AudioVolumeUp", 0x81: "AudioVolumeDown", 0x85: "NumpadComma", 0x87: "IntlRo", 0x89: "IntlYen", 0x90: "Lang1", 0x91: "Lang2",
            0xE0: "ControlLeft", 0xE1: "ShiftLeft", 0xE2: "AltLeft", 0xE3: "MetaLeft",
            0xE4: "ControlRight", 0xE5: "ShiftRight", 0xE6: "AltRight", 0xE7: "MetaRight",
        ]
        codes.merge(named) { _, new in new }
        return codes
    }()
}
