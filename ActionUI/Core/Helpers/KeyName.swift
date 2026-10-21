// Core/Helpers/KeyName.swift
/*
 The key of a keyboard shortcut, parsed from a document's "keyboardShortcut": { "key": ... }.
 Each renderer maps it to its own key type (SwiftUI: Helpers/KeyEquivalentHelper.swift).
*/

enum KeyName: Equatable, Sendable {
    case upArrow, downArrow, leftArrow, rightArrow
    case escape, delete, deleteForward
    case home, end, pageUp, pageDown
    case clear, tab, space, `return`
    /// Any one character ("s", "1", "/").
    case character(Character)

    /// The special keys by name, compared without case ("return", "upArrow", "PAGEDOWN").
    private static let special: [String: KeyName] = [
        "uparrow": .upArrow, "downarrow": .downArrow, "leftarrow": .leftArrow, "rightarrow": .rightArrow,
        "escape": .escape, "delete": .delete, "deleteforward": .deleteForward,
        "home": .home, "end": .end, "pageup": .pageUp, "pagedown": .pageDown,
        "clear": .clear, "tab": .tab, "space": .space, "return": .return,
    ]

    /// The key `text` names: a special key name in any case, else a single character. nil for
    /// anything else ("", "ab", "enter").
    static func parse(_ text: String) -> KeyName? {
        if let key = special[text.lowercased()] {
            return key
        }
        if text.count == 1, let character = text.first {
            return .character(character)
        }
        return nil
    }

    /// How many special keys there are (for tests).
    static var specialCount: Int { special.count }
}
