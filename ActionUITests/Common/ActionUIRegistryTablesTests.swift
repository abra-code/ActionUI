// Common/ActionUIRegistryTablesTests.swift
/*
 The registry's two tables: element specs and SwiftUI renderers. Their keys are the JSON "type"
 tokens documents use, so they must stay exactly the names registered before the tables existed.
*/

import XCTest
@testable import ActionUI

@MainActor
final class ActionUIRegistryTablesTests: XCTestCase {
    /// The names registered before the registry had two tables.
    private let builtInNames: Set<String> = [
        "AsyncImage", "Button", "Canvas", "Capsule", "Chart", "Circle", "Color", "ColorPicker",
        "ContentUnavailableView", "ControlGroup", "DatePicker", "DisclosureGroup", "Divider",
        "Ellipse", "EmptyView", "Form", "Gauge", "GeometryReader", "Grid", "Group", "GroupBox",
        "HSplitView", "HStack", "Image", "Label", "LabeledContent", "LazyHGrid", "LazyHStack",
        "LazyVGrid", "LazyVStack", "Link", "List", "LoadableView", "Map", "Menu", "NavigationLink",
        "NavigationSplitView", "NavigationStack", "Picker", "ProgressView", "Rectangle",
        "RoundedRectangle", "ScrollView", "ScrollViewReader", "Section", "SecureField", "ShareLink",
        "Slider", "Spacer", "Stepper", "Tab", "Table", "TabView", "Text", "TextEditor", "TextField",
        "Toggle", "ToolbarItem", "ToolbarItemGroup", "VideoPlayer", "View", "VSplitView", "VStack",
        "WebView", "ZStack"
    ]

    override func setUp() async throws {
        try await super.setUp()
        ActionUIRegistry.shared.resetForTesting()
    }

    override func tearDown() async throws {
        ActionUIRegistry.shared.resetForTesting()
        try await super.tearDown()
    }

    func testTheSpecTableHoldsExactlyTheBuiltInNames() {
        XCTAssertEqual(builtInNames.count, 65)
        XCTAssertEqual(Set(ActionUIRegistry.shared.specs.keys), builtInNames)
    }

    func testTheRendererTableHoldsTheSameNames() {
        XCTAssertEqual(Set(ActionUIRegistry.shared.renderers.keys), builtInNames)
        XCTAssertEqual(Set(ActionUIRegistry.builtInSwiftUIRenderers.keys), builtInNames)
    }

    func testEachBuiltInNameIsListedOnceAndNamesItsType() {
        let listed = ActionUIRegistry.builtInSpecs + ActionUIRegistry.appleOnlySpecs
        XCTAssertEqual(listed.count, Set(listed.map(\.name)).count, "a name is listed twice")
        for (name, type) in listed {
            XCTAssertEqual(String(describing: type), name)
        }
        for (name, type) in ActionUIRegistry.builtInSwiftUIRenderers {
            XCTAssertEqual(String(describing: type), name)
        }
    }

    func testRegisteringAnExistingNameReplacesItInBothTables() {
        let registry = ActionUIRegistry.shared
        registry.register(Toggle.self, as: "Button")
        XCTAssertTrue(registry.getElementValueType(forElementType: "Button") == Bool.self)
        XCTAssertTrue(registry.renderers["Button"] == Toggle.self)
    }

    func testAnAddOnIsRegisteredInBothTablesAndResetRemovesIt() {
        let registry = ActionUIRegistry.shared
        registry.register(Toggle.self, as: "AddOnToggle")
        XCTAssertNotNil(registry.specs["AddOnToggle"])
        XCTAssertNotNil(registry.renderers["AddOnToggle"])
        registry.resetForTesting()
        XCTAssertNil(registry.specs["AddOnToggle"])
        XCTAssertNil(registry.renderers["AddOnToggle"])
    }
}
