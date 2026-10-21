// Helpers/KeyEquivalentHelper.swift
import SwiftUI

struct KeyEquivalentHelper {
    /// The SwiftUI key for a shortcut's key (KeyName, Core/Helpers/KeyName.swift).
    static func keyEquivalent(for key: KeyName) -> KeyEquivalent {
        switch key {
        case .upArrow: return .upArrow
        case .downArrow: return .downArrow
        case .leftArrow: return .leftArrow
        case .rightArrow: return .rightArrow
        case .escape: return .escape
        case .delete: return .delete
        case .deleteForward: return .deleteForward
        case .home: return .home
        case .end: return .end
        case .pageUp: return .pageUp
        case .pageDown: return .pageDown
        case .clear: return .clear
        case .tab: return .tab
        case .space: return .space
        case .return: return .return
        case let .character(character): return KeyEquivalent(character)
        }
    }
}
