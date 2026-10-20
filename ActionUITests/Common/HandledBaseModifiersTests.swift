// Common/HandledBaseModifiersTests.swift
/*
 Tests for ActionUIViewConstruction.handledBaseModifiers: the base View modifiers leave out the keys
 an element type applies itself (an add-on registered through register(_:as:), here), and keep every
 key for a type that declares none.
*/

import XCTest
import SwiftUI
@testable import ActionUI

/// An element that applies cornerRadius itself, as the CachedImage add-on does.
private struct CornerHandlingElement: ActionUIViewConstruction {
    static var valueType: Any.Type = Void.self
    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { _, _, _, _, _ in SwiftUI.EmptyView() }
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, _, _ in view }
    static var initialValue: (ViewModel) -> Any? = { model in model.value }
    static var initialStates: (ViewModel) -> [String: Any] = { model in model.states }
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = nil
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = nil
    static var insertableContainers: [String: ContainerShape]? = nil
    static var handledBaseModifiers: Set<String> { ["cornerRadius"] }
}

@MainActor
final class HandledBaseModifiersTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        ActionUIRegistry.shared.resetForTesting()
        ActionUIRegistry.shared.register(CornerHandlingElement.self, as: "CornerHandling")
    }

    override func tearDown() async throws {
        ActionUIRegistry.shared.resetForTesting()
        try await super.tearDown()
    }

    private let properties: [String: Any] = ["cornerRadius": 12, "padding": 8, "opacity": 0.5]

    func testDeclaredKeysAreLeftOutOfTheBaseModifiers() {
        let base = ActionUIRegistry.shared.baseModifierProperties(properties, forElementType: "CornerHandling")
        XCTAssertNil(base["cornerRadius"])
        XCTAssertEqual(base["padding"] as? Int, 8)
        XCTAssertEqual(base["opacity"] as? Double, 0.5)
    }

    func testTypesThatDeclareNoneKeepEveryKey() {
        let base = ActionUIRegistry.shared.baseModifierProperties(properties, forElementType: "Image")
        XCTAssertEqual(base.count, properties.count)
        XCTAssertEqual(base["cornerRadius"] as? Int, 12)
    }

    func testUnregisteredTypesKeepEveryKey() {
        let base = ActionUIRegistry.shared.baseModifierProperties(properties, forElementType: "NoSuchElement")
        XCTAssertEqual(base.count, properties.count)
    }

    func testBuiltInElementsDeclareNone() {
        XCTAssertTrue(Image.handledBaseModifiers.isEmpty)
        XCTAssertTrue(View.handledBaseModifiers.isEmpty)
    }
}
