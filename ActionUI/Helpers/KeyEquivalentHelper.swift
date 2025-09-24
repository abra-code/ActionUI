// Sources/Helpers/KeyEquivalentHelper.swift
import SwiftUI

struct KeyEquivalentHelper {
    /// Converts a string key from JSON to a SwiftUI KeyEquivalent.
    /// - Parameters:
    ///   - key: The string representing the key (e.g., "a", "return", "space").
    ///   - logger: The logger for reporting warnings or errors.
    /// - Returns: A KeyEquivalent if the key is valid, or nil if invalid.
    static func resolveKeyEquivalent(_ key: String, logger: any ActionUILogger) -> KeyEquivalent? {
        // Handle special named keys
        switch key.lowercased() {
        case "uparrow":
            return .upArrow
        case "downarrow":
            return .downArrow
        case "leftarrow":
            return .leftArrow
        case "rightarrow":
            return .rightArrow
        case "escape":
            return .escape
        case "delete":
            return .delete
        case "deleteforward":
            return .deleteForward
        case "home":
            return .home
        case "end":
            return .end
        case "pageup":
            return .pageUp
        case "pagedown":
            return .pageDown
        case "clear":
            return .clear
        case "tab":
            return .tab
        case "space":
            return .space
        case "return":
            return .return
        default:
            // Handle single-character keys
            if key.count == 1, let character = key.first {
                return KeyEquivalent(character)
            } else {
                logger.log("Invalid key '\(key)' for keyboardShortcut: expected a single character or a valid special key (e.g., 'return', 'space', 'upArrow'), ignoring keyboardShortcut", .warning)
                return nil
            }
        }
    }
}
