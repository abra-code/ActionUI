// Add-ons/ActionUIHostSurface/Sources/ActionUIHostSurface/HostSurfaceInputMapping+WinUI.swift
//
// Windows' key positions to the C header's portable key names (the W3C UI Events "code" values). Pure, so the
// table can be tested without events.

#if os(Windows)

enum HostSurfaceWinUIKeys {

    /// The W3C UI Events code for a key's scan code (0xE000 added for an extended key, as the shim reports it), or
    /// "". Pause and Num Lock share scan code 0x45, so their virtual-key codes tell them apart.
    static func code(scanCode: UInt32, virtualKey: Int32) -> String {
        switch virtualKey {
        case 0x13: return "Pause"      // VK_PAUSE
        case 0x90: return "NumLock"    // VK_NUMLOCK
        default: return codes[scanCode] ?? ""
        }
    }

    /// PC keyboard scan codes (set 1, as Windows reports them) to W3C codes. Below 0x59 they are the Linux input
    /// event codes too (HostSurfaceInputMapping+Adwaita.swift).
    private static let codes: [UInt32: String] = {
        var table: [UInt32: String] = [
            0x01: "Escape", 0x0B: "Digit0", 0x0C: "Minus", 0x0D: "Equal", 0x0E: "Backspace", 0x0F: "Tab",
            0x1A: "BracketLeft", 0x1B: "BracketRight", 0x1C: "Enter", 0x1D: "ControlLeft",
            0x27: "Semicolon", 0x28: "Quote", 0x29: "Backquote", 0x2A: "ShiftLeft", 0x2B: "Backslash",
            0x33: "Comma", 0x34: "Period", 0x35: "Slash", 0x36: "ShiftRight", 0x37: "NumpadMultiply", 0x38: "AltLeft",
            0x39: "Space", 0x3A: "CapsLock", 0x46: "ScrollLock",
            0x47: "Numpad7", 0x48: "Numpad8", 0x49: "Numpad9", 0x4A: "NumpadSubtract", 0x4B: "Numpad4",
            0x4C: "Numpad5", 0x4D: "Numpad6", 0x4E: "NumpadAdd", 0x4F: "Numpad1", 0x50: "Numpad2", 0x51: "Numpad3",
            0x52: "Numpad0", 0x53: "NumpadDecimal", 0x56: "IntlBackslash", 0x57: "F11", 0x58: "F12",
            0x59: "NumpadEqual",
            // Extended keys.
            0xE01C: "NumpadEnter", 0xE01D: "ControlRight", 0xE035: "NumpadDivide", 0xE037: "PrintScreen",
            0xE038: "AltRight", 0xE047: "Home", 0xE048: "ArrowUp", 0xE049: "PageUp", 0xE04B: "ArrowLeft",
            0xE04D: "ArrowRight", 0xE04F: "End", 0xE050: "ArrowDown", 0xE051: "PageDown", 0xE052: "Insert",
            0xE053: "Delete", 0xE05B: "MetaLeft", 0xE05C: "MetaRight", 0xE05D: "ContextMenu",
        ]
        for (offset, digit) in (1...9).enumerated() {
            table[UInt32(0x02 + offset)] = "Digit\(digit)"
        }
        for (offset, number) in (1...10).enumerated() {
            table[UInt32(0x3B + offset)] = "F\(number)"
        }
        for (offset, number) in (13...23).enumerated() {
            table[UInt32(0x64 + offset)] = "F\(number)"
        }
        let rows: [(UInt32, String)] = [(0x10, "QWERTYUIOP"), (0x1E, "ASDFGHJKL"), (0x2C, "ZXCVBNM")]
        for (start, letters) in rows {
            for (offset, letter) in letters.enumerated() {
                table[start + UInt32(offset)] = "Key\(letter)"
            }
        }
        return table
    }()
}

#endif
