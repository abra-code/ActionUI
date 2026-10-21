// Tests/Helpers/KeyEquivalentHelperTests.swift
/*
 Tests for KeyEquivalentHelper: every key a shortcut can name maps to the SwiftUI key the parser
 that came before KeyName gave (kept here as `legacyKeyEquivalent`, verbatim).
*/

import SwiftUI
import XCTest
@testable import ActionUI

final class KeyEquivalentHelperTests: XCTestCase {

    func testEveryKeyMapsAsBefore() {
        let names = ["upArrow", "downArrow", "leftArrow", "rightArrow", "escape", "delete", "deleteForward",
                     "home", "end", "pageUp", "pageDown", "clear", "tab", "space", "return",
                     "RETURN", "s", "S", "1", "/", " "]
        for name in names {
            let key = KeyName.parse(name).map(KeyEquivalentHelper.keyEquivalent(for:))
            XCTAssertEqual(key, legacyKeyEquivalent(name), name)
        }
        XCTAssertNil(KeyName.parse("enter"))
        XCTAssertNil(legacyKeyEquivalent("enter"))
    }
}

private func legacyKeyEquivalent(_ key: String) -> KeyEquivalent? {
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
            return nil
        }
    }
}
