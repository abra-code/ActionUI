// Sources/Runtime/KeyboardShortcut+WinUI.swift
/*
 A view's keyboardShortcut (a base modifier) on WinUI: a keyboard accelerator on the element's
 accessible object (the control accessibility tools read: a switch in a Form, not its panel). WinUI
 handles it wherever the focus is in the element's window and does what the keyboard does to the
 control (a Button clicks, a Toggle toggles), as SwiftUI's keyboardShortcut triggers a control from
 anywhere in its window and the Linux renderer's ViewShortcut does; a disabled control is not
 activated. WinUI shows the accelerator in the control's tooltip; accessibility tools read it as the
 control's accelerator key (AutomationProperties.AcceleratorKey, which WinUI fills only for its app
 bar buttons and menu items, so the renderer writes it, in WinUI's own form: "Ctrl+Shift+S").

 The key and modifiers are read as the Linux renderer reads them (AppCommands.accelerator): command
 and control are Ctrl, option Alt, shift Shift; a list of only caps lock is Ctrl; an empty list the
 bare key. Named keys: return (enter), tab (with command or control: WinUI takes Tab accelerators
 only with Ctrl), space, escape, delete (Backspace), deleteForward, the arrows, home, end, pageUp,
 pageDown, F1 to F12; one character: a letter, a digit, or ; = + , - . / (the punctuation keys WinUI
 takes accelerators on; Windows names keys by their place, so on another layout the same punctuation
 may sit elsewhere). Another key (clear, ` [ ] \ ', which WinUI never matches) is logged once and
 takes no accelerator.

 A hidden control's shortcut does not fire: hidden turns the control's IsEnabled off on WinUI, and
 WinUI skips a disabled owner (the Linux renderer and SwiftUI still activate a hidden control).

 A bare Return (or Escape) fires whenever the focused control leaves the key alone (a button, a
 single-line field that does not take Return). Not yet: a bare Return making a button the window's
 default button in every case (Return in a field with an action of its own), as on macOS and Linux;
 WinUI's accelerator tooltip ("Ctrl+S") stays after a shortcut is taken away (no API removes it).
*/

import CWinUI

/// A keyboardShortcut as WinUI's virtual key and modifier flags.
struct WindowsShortcut: Equatable {
    /// Windows' virtual key code (VirtualKey).
    let key: Int32
    /// VirtualKeyModifiers: Control 1, Menu (Alt) 2, Shift 4.
    let modifiers: UInt32

    /// The shortcut for `shortcut`, nil for none or a key WinUI takes no accelerator on.
    init?(_ shortcut: BaseModifiers.KeyboardShortcut?) {
        guard let shortcut, let key = Self.virtualKey(shortcut.key) else { return nil }
        let set = shortcut.modifiers
        var control = set.contains(.command) || set.contains(.control)
        let alt = set.contains(.option)
        let shift = set.contains(.shift)
        // Caps lock alone cannot be held down as a modifier: the default, as on Linux.
        if !set.isEmpty && !control && !alt && !shift { control = true }
        // WinUI matches Tab only with Ctrl.
        if key == 0x09 && !control { return nil }
        self.key = key
        modifiers = (control ? 1 : 0) | (alt ? 2 : 0) | (shift ? 4 : 0)
    }

    /// Windows' virtual key for an ActionUI key name or one character.
    static func virtualKey(_ name: String) -> Int32? {
        switch name.lowercased() {
        case "return", "enter": return 0x0D
        case "tab": return 0x09
        case "space": return 0x20
        case "escape": return 0x1B
        case "delete", "backspace": return 0x08
        case "deleteforward": return 0x2E
        case "uparrow": return 0x26
        case "downarrow": return 0x28
        case "leftarrow": return 0x25
        case "rightarrow": return 0x27
        case "home": return 0x24
        case "end": return 0x23
        case "pageup": return 0x21
        case "pagedown": return 0x22
        case let lower where lower.count >= 2 && lower.hasPrefix("f"):
            guard let number = Int(lower.dropFirst()), (1...12).contains(number) else { return nil }
            return 0x70 + Int32(number - 1)
        default:
            guard name.unicodeScalars.count == 1, let scalar = name.lowercased().unicodeScalars.first else { return nil }
            switch scalar {
            case "a"..."z": return Int32(scalar.value) - 0x61 + 0x41
            case "0"..."9": return Int32(scalar.value)
            case ";": return 0xBA
            case "=", "+": return 0xBB
            case ",": return 0xBC
            case "-": return 0xBD
            case ".": return 0xBE
            case "/": return 0xBF
            default: return nil
            }
        }
    }

    /// The text WinUI shows for the accelerator (its tooltip, in US English): the modifiers then the
    /// key, joined with "+" ("Ctrl+Shift+S").
    var text: String {
        var parts: [String] = []
        if modifiers & 1 != 0 { parts.append("Ctrl") }
        if modifiers & 2 != 0 { parts.append("Alt") }
        if modifiers & 4 != 0 { parts.append("Shift") }
        parts.append(Self.keyText(key))
        return parts.joined(separator: "+")
    }

    /// WinUI's name for a virtual key virtualKey(_:) gives.
    static func keyText(_ key: Int32) -> String {
        switch key {
        case 0x0D: return "Enter"
        case 0x09: return "Tab"
        case 0x20: return "Space"
        case 0x1B: return "Esc"
        case 0x08: return "Back"
        case 0x2E: return "Delete"
        case 0x26: return "Up"
        case 0x28: return "Down"
        case 0x25: return "Left"
        case 0x27: return "Right"
        case 0x24: return "Home"
        case 0x23: return "End"
        case 0x21: return "PageUp"
        case 0x22: return "PageDown"
        case 0x70...0x7B: return "F\(key - 0x70 + 1)"
        // The = key: WinUI names it by its shifted "+".
        case 0xBB: return "+"
        case 0xBA: return ";"
        case 0xBC: return ","
        case 0xBD: return "-"
        case 0xBE: return "."
        case 0xBF: return "/"
        default: return Unicode.Scalar(UInt32(key)).map { String(Character($0)) } ?? ""
        }
    }
}

@MainActor private var reportedKeys: Set<String> = []

extension RenderNode {
    /// Gives `target` (the element's accessible object) the accelerator for `shortcut`, replacing the
    /// one it had; nil takes it away. Returns what was applied.
    static func applyShortcut(_ shortcut: BaseModifiers.KeyboardShortcut?, to target: WinUIObject,
                              applied: WindowsShortcut?) -> WindowsShortcut? {
        let wanted = WindowsShortcut(shortcut)
        if wanted == nil, let shortcut, reportedKeys.insert(shortcut.key).inserted {
            ActionUIModel.shared.logger.log("keyboardShortcut: no WinUI accelerator for \"\(shortcut.key)\"; ignored", .warning)
        }
        guard wanted != applied else { return applied }
        if !actionUIWinUIElementSetKeyboardShortcut(target.pointer, wanted?.key ?? 0, wanted?.modifiers ?? 0, wanted?.text) {
            ActionUIModel.shared.logger.log("RenderNode: \(WinUIError.last("giving an element its keyboard shortcut"))", .error)
            return applied
        }
        return wanted
    }
}
