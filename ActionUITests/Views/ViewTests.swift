// Tests/Views/ViewTests.swift
import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class ViewTests: XCTestCase {
    private var logger: XCTestLogger!
    private var windowUUID: String!
    
    override func setUp() async throws {
        try await super.setUp()
        logger = XCTestLogger(maxLevel: .verbose)
        ActionUIModel.shared.logger = logger
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        windowUUID = UUID().uuidString
    }
    
    override func tearDown() async throws {
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        logger = nil
        windowUUID = nil
        try await super.tearDown()
    }
    
    func testBaseModifiersValid() throws {
        let properties: [String: Any] = [
            "padding": 10.0,
            "hidden": false,
            "foregroundStyle": "blue",
            "tint": "red",
            "font": "body",
            "background": "#FFFFFF",
            "frame": ["width": 100.0, "height": 100.0, "alignment": "center"],
            "offset": ["x": 10.0, "y": -5.0],
            "opacity": 0.5,
            "cornerRadius": 5.0,
            "actionID": "view.action",
            "disabled": true,
            "accessibilityLabel": "Test View",
            "accessibilityHint": "Base view",
            "accessibilityHidden": false,
            "accessibilityIdentifier": "view_1",
            "shadow": ["color": "black", "radius": 5.0, "x": 0.0, "y": 2.0],
            "border": ["color": "red", "width": 2.0]
        ]

        let mods = BaseModifiers(properties)

        XCTAssertEqual(mods.padding, .uniform(10.0), "padding should be uniform 10.0")
        XCTAssertEqual(mods.hidden, false, "hidden should be valid Bool")
        XCTAssertEqual(mods.foregroundStyle, "blue", "foregroundStyle should be valid string")
        XCTAssertEqual(mods.tint, "red", "tint should be valid string")
        XCTAssertEqual(mods.font as? String, "body", "font should be valid string")
        XCTAssertEqual(mods.background, "#FFFFFF", "background should be valid string")
        XCTAssertNotNil(mods.frame, "frame should be parsed")
        XCTAssertEqual(mods.frame?.width, 100.0, "frame.width should be 100.0")
        XCTAssertEqual(mods.frame?.height, 100.0, "frame.height should be 100.0")
        XCTAssertEqual(mods.frame?.alignment, .center, "frame.alignment should be center")
        XCTAssertEqual(mods.offset, BaseModifiers.Offset(x: 10.0, y: -5.0), "offset should be (10.0, -5.0)")
        XCTAssertEqual(mods.opacity, 0.5, "opacity should be 0.5")
        XCTAssertEqual(mods.cornerRadius, 5.0, "cornerRadius should be 5.0")
        XCTAssertEqual(mods.actionID, "view.action", "actionID should be view.action")
        XCTAssertEqual(mods.disabled, true, "disabled should be true")
        XCTAssertEqual(mods.accessibilityLabel, "Test View", "accessibilityLabel should be Test View")
        XCTAssertEqual(mods.accessibilityHint, "Base view", "accessibilityHint should be Base view")
        XCTAssertEqual(mods.accessibilityHidden, false, "accessibilityHidden should be false")
        XCTAssertEqual(mods.accessibilityIdentifier, "view_1", "accessibilityIdentifier should be view_1")
        XCTAssertNotNil(mods.shadow, "shadow should be parsed")
        XCTAssertEqual(mods.shadow?.color, "black", "shadow.color should be black")
        XCTAssertEqual(mods.shadow?.radius, 5.0, "shadow.radius should be 5.0")
        XCTAssertEqual(mods.shadow?.x, 0.0, "shadow.x should be 0.0")
        XCTAssertEqual(mods.shadow?.y, 2.0, "shadow.y should be 2.0")
        XCTAssertNotNil(mods.border, "border should be parsed")
        XCTAssertEqual(mods.border?.color, "red", "border.color should be red")
        XCTAssertEqual(mods.border?.width, 2.0, "border.width should be 2.0")
    }

    func testBaseModifiersValidFlexibleFrame() throws {
        let properties: [String: Any] = [
            "frame": ["minWidth": 50.0, "idealWidth": 100.0, "maxWidth": 200.0, "minHeight": 50.0, "idealHeight": 100.0, "maxHeight": 200.0, "alignment": "topLeading"]
        ]

        let mods = BaseModifiers(properties)

        XCTAssertNotNil(mods.frame, "frame should be parsed")
        XCTAssertEqual(mods.frame?.minWidth, 50.0, "frame.minWidth should be 50.0")
        XCTAssertEqual(mods.frame?.idealWidth, 100.0, "frame.idealWidth should be 100.0")
        XCTAssertEqual(mods.frame?.maxWidth, 200.0, "frame.maxWidth should be 200.0")
        XCTAssertEqual(mods.frame?.minHeight, 50.0, "frame.minHeight should be 50.0")
        XCTAssertEqual(mods.frame?.idealHeight, 100.0, "frame.idealHeight should be 100.0")
        XCTAssertEqual(mods.frame?.maxHeight, 200.0, "frame.maxHeight should be 200.0")
        XCTAssertEqual(mods.frame?.alignment, .topLeading, "frame.alignment should be topLeading")
    }

    // MARK: - searchable

    func testSearchableValid() throws {
        let properties: [String: Any] = [
            "searchable": ["prompt": "Search receivers", "actionID": "home.search"]
        ]
        let mods = BaseModifiers(properties)
        XCTAssertNotNil(mods.searchable, "valid searchable dict should be read")
        XCTAssertEqual(mods.searchable?.actionID, "home.search")
        XCTAssertEqual(mods.searchable?.prompt, "Search receivers")
    }

    func testSearchablePromptOptional() throws {
        // actionID alone is sufficient; prompt is optional.
        let properties: [String: Any] = ["searchable": ["actionID": "home.search"]]
        let mods = BaseModifiers(properties)
        XCTAssertEqual(mods.searchable?.actionID, "home.search")
        XCTAssertNil(mods.searchable?.prompt, "prompt may be omitted")
    }

    func testSearchableMissingActionIDDropped() throws {
        // Missing required actionID -> entire searchable ignored.
        let properties: [String: Any] = ["searchable": ["prompt": "Search"]]
        let mods = BaseModifiers(properties)
        XCTAssertNil(mods.searchable, "searchable without actionID should be ignored")
    }

    func testSearchableEmptyActionIDDropped() throws {
        let properties: [String: Any] = ["searchable": ["actionID": ""]]
        let mods = BaseModifiers(properties)
        XCTAssertNil(mods.searchable, "searchable with empty actionID should be ignored")
    }

    func testSearchableInvalidTypeDropped() throws {
        let properties: [String: Any] = ["searchable": "not a dict"]
        let mods = BaseModifiers(properties)
        XCTAssertNil(mods.searchable, "non-dictionary searchable should be ignored")
    }

    func testSearchableInvalidPromptTypeStripped() throws {
        // Valid actionID but non-String prompt -> keep actionID, ignore prompt.
        let properties: [String: Any] = ["searchable": ["actionID": "home.search", "prompt": 42]]
        let mods = BaseModifiers(properties)
        XCTAssertEqual(mods.searchable?.actionID, "home.search")
        XCTAssertNil(mods.searchable?.prompt, "non-String prompt should be ignored while keeping actionID")
    }

    // MARK: - contextMenu / contextMenuPreview (top-level subview keys)

    func testContextMenuSubviewsDecode() throws {
        // contextMenu is an ARRAY subview (the menu's action items: real Button / Divider
        // elements) and contextMenuPreview is a SINGLE arbitrary subview (the preview) -
        // mirroring SwiftUI's `.contextMenu(menuItems:preview:)`, not a property descriptor.
        let json = """
        {
            "id": 1,
            "type": "Image",
            "properties": { "systemName": "photo" },
            "contextMenu": [
                { "id": 2, "type": "Button", "properties": { "title": "Rename", "systemImage": "pencil", "actionID": "ctx.rename" } },
                { "id": 3, "type": "Divider" },
                { "id": 4, "type": "Button", "properties": { "title": "Delete", "role": "destructive", "actionID": "ctx.delete" } }
            ],
            "contextMenuPreview": {
                "id": 5,
                "type": "Image",
                "properties": { "systemName": "photo", "imageScale": "large" }
            }
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let element = try JSONDecoder(logger: logger).decode(ActionUIElement.self, from: data)

        let items = try XCTUnwrap(element.subviews?["contextMenu"] as? [ActionUIElement])
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items[0].type, "Button")
        XCTAssertEqual(items[0].properties["actionID"] as? String, "ctx.rename")
        XCTAssertEqual(items[1].type, "Divider")
        XCTAssertEqual(items[2].properties["role"] as? String, "destructive")

        let preview = try XCTUnwrap(element.subviews?["contextMenuPreview"] as? ActionUIElement)
        XCTAssertEqual(preview.type, "Image")
        XCTAssertEqual(preview.properties["imageScale"] as? String, "large")
    }

    func testContextMenuItemsAndPreviewAreTraversedChildren() throws {
        // The items and the preview must be in the shared childElements walk so their ids
        // register in the window's ViewModel pool (Buttons need their actionID wiring).
        let json = """
        {
            "id": 1, "type": "Text", "properties": { "text": "Hi" },
            "contextMenu": [ { "id": 2, "type": "Button", "properties": { "title": "A", "actionID": "a" } } ],
            "contextMenuPreview": { "id": 3, "type": "Image", "properties": { "systemName": "star" } }
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let element = try JSONDecoder(logger: logger).decode(ActionUIElement.self, from: data)
        let childIDs = element.childElements.map { $0.id }
        XCTAssertTrue(childIDs.contains(2), "menu item id is a traversed child")
        XCTAssertTrue(childIDs.contains(3), "preview id is a traversed child")
    }

    func testContextMenuPreviewOptional() throws {
        // The preview is optional: a context menu can be just an action list.
        let json = """
        {
            "id": 1, "type": "Text", "properties": { "text": "Hi" },
            "contextMenu": [ { "id": 2, "type": "Button", "properties": { "title": "A", "actionID": "a" } } ]
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let element = try JSONDecoder(logger: logger).decode(ActionUIElement.self, from: data)
        XCTAssertNotNil(element.subviews?["contextMenu"])
        XCTAssertNil(element.subviews?["contextMenuPreview"], "preview may be omitted")
    }

    func testContextMenuAbsent() throws {
        let json = """
        {"id": 1, "type": "Text", "properties": { "text": "Hi" }}
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let element = try JSONDecoder(logger: logger).decode(ActionUIElement.self, from: data)
        XCTAssertNil(element.subviews?["contextMenu"])
        XCTAssertNil(element.subviews?["contextMenuPreview"])
    }

    // MARK: - swipeActions (top-level subview key)

    func testSwipeActionsSubviewDecode() throws {
        // swipeActions is an ARRAY subview of real Button elements - mirroring SwiftUI's
        // `.swipeActions(edge:allowsFullSwipe:)`, a ViewBuilder of Buttons. Each Button
        // carries its own title / systemImage / role / tint / actionID, plus the
        // swipe-specific `edge` and `allowsFullSwipe` read at apply time (View.swift).
        let json = """
        {
            "id": 1,
            "type": "Text",
            "properties": { "text": "Inbox row" },
            "swipeActions": [
                { "id": 2, "type": "Button", "properties": { "title": "Flag", "systemImage": "flag", "tint": "orange", "edge": "leading", "actionID": "row.flag" } },
                { "id": 3, "type": "Button", "properties": { "title": "Delete", "systemImage": "trash", "role": "destructive", "edge": "trailing", "allowsFullSwipe": false, "actionID": "row.delete" } }
            ]
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let element = try JSONDecoder(logger: logger).decode(ActionUIElement.self, from: data)

        let actions = try XCTUnwrap(element.subviews?["swipeActions"] as? [ActionUIElement])
        XCTAssertEqual(actions.count, 2)
        XCTAssertEqual(actions[0].type, "Button")
        XCTAssertEqual(actions[0].properties["edge"] as? String, "leading")
        XCTAssertEqual(actions[0].properties["tint"] as? String, "orange")
        XCTAssertEqual(actions[1].properties["role"] as? String, "destructive")
        XCTAssertEqual(actions[1].properties["edge"] as? String, "trailing")
        XCTAssertEqual(actions[1].properties["allowsFullSwipe"] as? Bool, false)
    }

    func testSwipeActionsAreTraversedChildren() throws {
        // The swipe Buttons must be in the shared childElements walk so their ids register
        // in the window's ViewModel pool (each Button needs its actionID wiring).
        let json = """
        {
            "id": 1, "type": "Text", "properties": { "text": "Row" },
            "swipeActions": [ { "id": 2, "type": "Button", "properties": { "title": "Delete", "role": "destructive", "actionID": "del" } } ]
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let element = try JSONDecoder(logger: logger).decode(ActionUIElement.self, from: data)
        let childIDs = element.childElements.map { $0.id }
        XCTAssertTrue(childIDs.contains(2), "swipe action button id is a traversed child")
    }

    func testSwipeActionsRoundTripEncode() throws {
        // swipeActions is an array subview key, so it must survive an encode/decode round trip
        // (the editor and setElement paths re-serialize elements).
        let json = """
        {
            "id": 1, "type": "Text", "properties": { "text": "Row" },
            "swipeActions": [ { "id": 2, "type": "Button", "properties": { "title": "Delete", "actionID": "del" } } ]
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let element = try JSONDecoder(logger: logger).decode(ActionUIElement.self, from: data)
        let reEncoded = try JSONEncoder(logger: logger).encode(element)
        let roundTripped = try JSONDecoder(logger: logger).decode(ActionUIElement.self, from: reEncoded)
        let actions = try XCTUnwrap(roundTripped.subviews?["swipeActions"] as? [ActionUIElement])
        XCTAssertEqual(actions.count, 1)
        XCTAssertEqual(actions[0].properties["actionID"] as? String, "del")
    }

    func testSwipeActionsAbsent() throws {
        let json = """
        {"id": 1, "type": "Text", "properties": { "text": "Row" }}
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let element = try JSONDecoder(logger: logger).decode(ActionUIElement.self, from: data)
        XCTAssertNil(element.subviews?["swipeActions"])
    }

    func testBaseModifiersInvalid() throws {
        let properties: [String: Any] = [
            "padding": "10",
            "hidden": "true",
            "foregroundStyle": 123,
            "tint": 123,
            "font": 456,
            "background": 789,
            "frame": ["width": "100", "height": true],
            "offset": ["x": "10", "y": true],
            "opacity": "0.5",
            "cornerRadius": "5.0",
            "actionID": 999,
            "disabled": "false",
            "accessibilityLabel": 123,
            "accessibilityHint": 456,
            "accessibilityHidden": "true",
            "accessibilityIdentifier": 789,
            "shadow": ["color": 123, "radius": "5", "x": "0", "y": true],
            "border": ["color": 123, "width": "2"]
        ]

        let mods = BaseModifiers(properties)

        XCTAssertNil(mods.padding, "padding should be nil for invalid type")
        XCTAssertFalse(mods.hidden, "hidden should be false for invalid type")
        XCTAssertNil(mods.foregroundStyle, "foregroundStyle should be nil for invalid type")
        XCTAssertNil(mods.tint, "tint should be nil for invalid type")
        XCTAssertNil(mods.font, "font should be nil for invalid type")
        XCTAssertNil(mods.background, "background should be nil for invalid type")
        XCTAssertNil(mods.frame, "frame should be nil for invalid types")
        XCTAssertNil(mods.offset, "offset should be nil for invalid types")
        XCTAssertNil(mods.opacity, "opacity should be nil for invalid type")
        XCTAssertNil(mods.cornerRadius, "cornerRadius should be nil for invalid type")
        XCTAssertNil(mods.actionID, "actionID should be nil for invalid type")
        XCTAssertNil(mods.disabled, "disabled should be nil for invalid type")
        XCTAssertNil(mods.accessibilityLabel, "accessibilityLabel should be nil for invalid type")
        XCTAssertNil(mods.accessibilityHint, "accessibilityHint should be nil for invalid type")
        XCTAssertNil(mods.accessibilityHidden, "accessibilityHidden should be nil for invalid type")
        XCTAssertNil(mods.accessibilityIdentifier, "accessibilityIdentifier should be nil for invalid type")
        XCTAssertNil(mods.shadow, "shadow should be nil for invalid types")
        XCTAssertNil(mods.border, "border should be nil for invalid types")
    }

    func testBaseModifiersMissing() throws {
        let properties: [String: Any] = [:]

        let mods = BaseModifiers(properties)

        XCTAssertNil(mods.padding, "padding should be nil when no properties provided")
        XCTAssertFalse(mods.hidden, "hidden should be false when no properties provided")
        XCTAssertNil(mods.foregroundStyle, "foregroundStyle should be nil when no properties provided")
        XCTAssertNil(mods.tint, "tint should be nil when no properties provided")
        XCTAssertNil(mods.font, "font should be nil when no properties provided")
        XCTAssertNil(mods.background, "background should be nil when no properties provided")
        XCTAssertNil(mods.frame, "frame should be nil when no properties provided")
        XCTAssertNil(mods.offset, "offset should be nil when no properties provided")
        XCTAssertNil(mods.opacity, "opacity should be nil when no properties provided")
        XCTAssertNil(mods.cornerRadius, "cornerRadius should be nil when no properties provided")
        XCTAssertNil(mods.actionID, "actionID should be nil when no properties provided")
        XCTAssertNil(mods.disabled, "disabled should be nil when no properties provided")
        XCTAssertNil(mods.accessibilityLabel, "accessibilityLabel should be nil when no properties provided")
        XCTAssertNil(mods.accessibilityHint, "accessibilityHint should be nil when no properties provided")
        XCTAssertNil(mods.accessibilityHidden, "accessibilityHidden should be nil when no properties provided")
        XCTAssertNil(mods.accessibilityIdentifier, "accessibilityIdentifier should be nil when no properties provided")
        XCTAssertNil(mods.shadow, "shadow should be nil when no properties provided")
        XCTAssertNil(mods.border, "border should be nil when no properties provided")
    }

    func testBaseModifiersPartial() throws {
        let properties: [String: Any] = [
            "padding": 20.0,
            "foregroundStyle": "red",
            "tint": "green",
            "offset": ["x": 15.0, "y": 25.0],
            "disabled": false,
            "accessibilityLabel": "Test View",
            "accessibilityIdentifier": "view_1"
        ]

        let mods = BaseModifiers(properties)

        XCTAssertEqual(mods.padding, .uniform(20.0), "padding should be uniform 20.0")
        XCTAssertEqual(mods.foregroundStyle, "red", "foregroundStyle should be valid string")
        XCTAssertEqual(mods.tint, "green", "tint should be valid string")
        XCTAssertEqual(mods.offset, BaseModifiers.Offset(x: 15.0, y: 25.0), "offset should be (15.0, 25.0)")
        XCTAssertEqual(mods.disabled, false, "disabled should be valid Bool")
        XCTAssertEqual(mods.accessibilityLabel, "Test View", "accessibilityLabel should be valid string")
        XCTAssertEqual(mods.accessibilityIdentifier, "view_1", "accessibilityIdentifier should be valid string")
        XCTAssertFalse(mods.hidden, "hidden should be false when not provided")
        XCTAssertNil(mods.font, "font should be nil when not provided")
        XCTAssertNil(mods.background, "background should be nil when not provided")
        XCTAssertNil(mods.frame, "frame should be nil when not provided")
        XCTAssertNil(mods.opacity, "opacity should be nil when not provided")
        XCTAssertNil(mods.cornerRadius, "cornerRadius should be nil when not provided")
        XCTAssertNil(mods.actionID, "actionID should be nil when not provided")
        XCTAssertNil(mods.accessibilityHint, "accessibilityHint should be nil when not provided")
        XCTAssertNil(mods.accessibilityHidden, "accessibilityHidden should be nil when not provided")
        XCTAssertNil(mods.shadow, "shadow should be nil when not provided")
    }

    func testBaseModifiersFramePartial() throws {
        let properties: [String: Any] = [
            "frame": ["width": 100.0]
        ]

        let mods = BaseModifiers(properties)

        XCTAssertNotNil(mods.frame, "frame should be parsed")
        XCTAssertEqual(mods.frame?.width, 100.0, "frame.width should be 100.0")
        XCTAssertNil(mods.frame?.height, "frame.height should be nil when not provided")
        XCTAssertNil(mods.frame?.alignment, "frame.alignment should be nil when not provided")
    }

    func testBaseModifiersFrameMixedForms() throws {
        let properties: [String: Any] = [
            "frame": ["width": 100.0, "minWidth": 50.0]
        ]

        let mods = BaseModifiers(properties)

        XCTAssertNil(mods.frame, "frame should be nil for mixed fixed and flexible keys")
    }

    func testBaseModifiersFrameInvalidAlignment() throws {
        let properties: [String: Any] = [
            "frame": ["alignment": "invalid"]
        ]

        let mods = BaseModifiers(properties)

        XCTAssertNotNil(mods.frame, "frame with only an alignment should still be parsed")
        XCTAssertNil(mods.frame?.alignment, "frame.alignment should be nil for an unknown value")
    }

    func testBaseModifiersFrameInvalidTypes() throws {
        let properties: [String: Any] = [
            "frame": ["width": "100", "height": true]
        ]

        let mods = BaseModifiers(properties)

        XCTAssertNil(mods.frame, "frame should be nil for invalid dimension types")
    }

    func testBaseModifiersShadowPartial() throws {
        let properties: [String: Any] = [
            "shadow": ["radius": 10.0, "x": 3.0]
        ]

        let mods = BaseModifiers(properties)

        XCTAssertNotNil(mods.shadow, "shadow should be parsed with partial properties")
        XCTAssertNil(mods.shadow?.color, "shadow.color should be nil when not provided")
        XCTAssertEqual(mods.shadow?.radius, 10.0, "shadow.radius should be 10.0")
        XCTAssertEqual(mods.shadow?.x, 3.0, "shadow.x should be 3.0")
        XCTAssertEqual(mods.shadow?.y, 0.0, "shadow.y should be 0.0 when not provided")
    }

    func testBaseModifiersShadowInvalidTypes() throws {
        let properties: [String: Any] = [
            "shadow": ["color": 123, "radius": "10", "x": true, "y": "2"]
        ]

        let mods = BaseModifiers(properties)

        XCTAssertNil(mods.shadow, "shadow should be nil for invalid types")
    }

    func testBaseModifiersShadowInvalidColorType() throws {
        let properties: [String: Any] = [
            "shadow": ["color": 123]
        ]

        let mods = BaseModifiers(properties)

        XCTAssertNil(mods.shadow, "shadow should be nil for invalid color type")
    }

    func testBaseModifiersShadowInvalidRadiusType() throws {
        let properties: [String: Any] = [
            "shadow": ["radius": "10"]
        ]

        let mods = BaseModifiers(properties)

        XCTAssertNil(mods.shadow, "shadow should be nil for invalid radius type")
    }

    func testBaseModifiersShadowInvalidXType() throws {
        let properties: [String: Any] = [
            "shadow": ["x": true]
        ]

        let mods = BaseModifiers(properties)

        XCTAssertNil(mods.shadow, "shadow should be nil for invalid x type")
    }

    func testBaseModifiersShadowInvalidYType() throws {
        let properties: [String: Any] = [
            "shadow": ["y": "2"]
        ]

        let mods = BaseModifiers(properties)

        XCTAssertNil(mods.shadow, "shadow should be nil for invalid y type")
    }

    func testBaseModifiersShadowEmptyDict() throws {
        let properties: [String: Any] = [
            "shadow": [:]
        ]

        let mods = BaseModifiers(properties)

        XCTAssertNil(mods.shadow, "shadow should be nil for empty dictionary")
    }

    func testBaseModifiersShadowInvalidType() throws {
        let properties: [String: Any] = [
            "shadow": "invalid"
        ]

        let mods = BaseModifiers(properties)

        XCTAssertNil(mods.shadow, "shadow should be nil for invalid type")
    }

    func testBaseModifiersPaddingDictPartial() throws {
        let properties: [String: Any] = [
            "padding": ["top": 10.0, "leading": 5.0]
        ]

        let mods = BaseModifiers(properties)

        XCTAssertEqual(mods.padding, .edges(top: 10.0, leading: 5.0, bottom: 0.0, trailing: 0.0),
                       "padding.top and padding.leading should be read; bottom and trailing are 0 when not provided")
    }

    func testBaseModifiersPaddingDictInvalidTypes() throws {
        let properties: [String: Any] = [
            "padding": ["top": "10", "bottom": true, "leading": "5", "trailing": 15.0]
        ]

        let mods = BaseModifiers(properties)

        XCTAssertEqual(mods.padding, .edges(top: 0.0, leading: 0.0, bottom: 0.0, trailing: 15.0),
                       "padding.trailing should be read; top, bottom and leading are 0 for invalid types")
    }

    func testBaseModifiersPaddingStringDefault() throws {
        let properties: [String: Any] = [
            "padding": "default"
        ]

        let mods = BaseModifiers(properties)

        XCTAssertEqual(mods.padding, .system, "padding should be the system padding for 'default'")
    }

    func testBaseModifiersPaddingStringInvalid() throws {
        let properties: [String: Any] = [
            "padding": "invalid"
        ]

        let mods = BaseModifiers(properties)

        XCTAssertNil(mods.padding, "padding should be nil for invalid string")
    }

    func testBaseModifiersPaddingInvalidType() throws {
        let properties: [String: Any] = [
            "padding": true
        ]

        let mods = BaseModifiers(properties)

        XCTAssertNil(mods.padding, "padding should be nil for invalid type")
    }

    func testBaseModifiersOpacityInvalidValue() throws {
        let properties: [String: Any] = [
            "opacity": 1.5
        ]

        let mods = BaseModifiers(properties)

        XCTAssertNil(mods.opacity, "opacity should be nil for value outside 0.0-1.0 range")
    }

    func testBaseModifiersOpacityValidBoundary() throws {
        let properties: [String: Any] = [
            "opacity": 0.0
        ]

        let mods = BaseModifiers(properties)

        XCTAssertEqual(mods.opacity, 0.0, "opacity should be valid at 0.0")
    }

    func testBaseModifiersOpacityValidOne() throws {
        let properties: [String: Any] = [
            "opacity": 1.0
        ]

        let mods = BaseModifiers(properties)

        XCTAssertEqual(mods.opacity, 1.0, "opacity should be valid at 1.0")
    }

    func testBaseModifiersFrameAlignmentOnly() throws {
        let properties: [String: Any] = [
            "frame": ["alignment": "center"]
        ]

        let mods = BaseModifiers(properties)

        XCTAssertNotNil(mods.frame, "frame with only an alignment should be parsed")
        XCTAssertEqual(mods.frame?.alignment, .center, "frame.alignment should be center")
        XCTAssertNil(mods.frame?.width, "frame.width should be nil when not provided")
    }
    
    func testBuildViewAndApplyModifiers() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "View",
            "properties": {
                "padding": 10.0,
                "foregroundStyle": "blue",
                "frame": {"width": 100.0, "height": 100.0, "alignment": "center"},
                "offset": {"x": 10.0, "y": -5.0},
                "accessibilityLabel": "Test View",
                "accessibilityHint": "Base view",
                "accessibilityHidden": false,
                "accessibilityIdentifier": "view_1",
                "shadow": {"color": "black", "radius": 5.0, "x": 0.0, "y": 2.0}
            }
        }
        """
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to Data")
            return
        }
        
        let actionUIModel = ActionUIModel.shared
        let element = try actionUIModel.loadDescription(from: jsonData, format: "json", windowUUID: windowUUID)
        
        guard let windowModel = actionUIModel.windowModels[windowUUID],
              let viewModel = windowModel.viewModels[element.id] else {
            XCTFail("Failed to retrieve viewModel")
            return
        }
        
        let properties = element.properties
        
        let view = View.buildView(element, viewModel, windowUUID, properties, logger)
        let _ = View.applyModifiers(view, element, windowUUID, properties, logger)
        
        logger.log("After buildView viewModel = \(String(describing: viewModel))", .debug)
        
        XCTAssertTrue(view is SwiftUI.EmptyView, "buildView should return EmptyView")
        //        XCTAssertFalse(modifiedView is SwiftUI.EmptyView, "applyModifiers returns a modified view due to SwiftUI modifier wrapping")
        if let frame = element.properties["frame"] as? [String: Any] {
            XCTAssertEqual(frame.cgFloat(forKey: "width"), 100.0, "frame.width should be 100.0")
            XCTAssertEqual(frame.cgFloat(forKey: "height"), 100.0, "frame.height should be 100.0")
            XCTAssertEqual(frame["alignment"] as? String, "center", "frame.alignment should be center")
        } else {
            XCTFail("frame should be a dictionary")
        }
        if let offset = element.properties["offset"] as? [String: Any] {
            XCTAssertEqual(offset.cgFloat(forKey: "x"), 10.0, "offset.x should be 10.0")
            XCTAssertEqual(offset.cgFloat(forKey: "y"), -5.0, "offset.y should be -5.0")
        } else {
            XCTFail("offset should be a dictionary")
        }
        if let shadow = element.properties["shadow"] as? [String: Any] {
            XCTAssertEqual(shadow["color"] as? String, "black", "shadow.color should be black")
            XCTAssertEqual(shadow.cgFloat(forKey: "radius"), 5.0, "shadow.radius should be 5.0")
            XCTAssertEqual(shadow.cgFloat(forKey: "x"), 0.0, "shadow.x should be 0.0")
            XCTAssertEqual(shadow.cgFloat(forKey: "y"), 2.0, "shadow.y should be 2.0")
        } else {
            XCTFail("shadow should be a dictionary")
        }
        XCTAssertEqual(element.properties.cgFloat(forKey: "padding"), 10.0, "padding should be 10.0")
        XCTAssertEqual(element.properties["foregroundStyle"] as? String, "blue", "foregroundStyle should be blue")
        XCTAssertEqual(element.properties["accessibilityLabel"] as? String, "Test View", "accessibilityLabel should be Test View")
        XCTAssertEqual(element.properties["accessibilityHint"] as? String, "Base view", "accessibilityHint should be Base view")
        XCTAssertEqual(element.properties["accessibilityHidden"] as? Bool, false, "accessibilityHidden should be false")
        XCTAssertEqual(element.properties["accessibilityIdentifier"] as? String, "view_1", "accessibilityIdentifier should be view_1")
    }
    
    func testBuildViewAndApplyModifiersFlexibleFrame() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "View",
            "properties": {
                "frame": {"minWidth": 50.0, "idealHeight": 100.0, "alignment": "topLeading"}
            }
        }
        """
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to Data")
            return
        }
        
        let actionUIModel = ActionUIModel.shared
        let element = try actionUIModel.loadDescription(from: jsonData, format: "json", windowUUID: windowUUID)
        
        guard let windowModel = actionUIModel.windowModels[windowUUID],
              let viewModel = windowModel.viewModels[element.id] else {
            XCTFail("Failed to retrieve viewModel")
            return
        }
        
        let properties = element.properties
        
        let view = View.buildView(element, viewModel, windowUUID, properties, logger)
        let _ = View.applyModifiers(view, element, windowUUID, properties, logger)
        
        logger.log("After buildView viewModel = \(String(describing: viewModel))", .debug)
        
        XCTAssertTrue(view is SwiftUI.EmptyView, "buildView should return EmptyView")
        //        XCTAssertFalse(modifiedView is SwiftUI.EmptyView, "applyModifiers returns a modified view due to flexible frame modifier")
        if let frame = element.properties["frame"] as? [String: Any] {
            XCTAssertEqual(frame.cgFloat(forKey: "minWidth"), 50.0, "frame.minWidth should be 50.0")
            XCTAssertEqual(frame.cgFloat(forKey: "idealHeight"), 100.0, "frame.idealHeight should be 100.0")
            XCTAssertEqual(frame["alignment"] as? String, "topLeading", "frame.alignment should be topLeading")
        } else {
            XCTFail("frame should be a dictionary")
        }
    }
    
    func testBuildViewAndApplyModifiersEmptyProperties() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "View",
            "properties": {}
        }
        """
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to Data")
            return
        }
        
        let actionUIModel = ActionUIModel.shared
        let element = try actionUIModel.loadDescription(from: jsonData, format: "json", windowUUID: windowUUID)
        
        guard let windowModel = actionUIModel.windowModels[windowUUID],
              let viewModel = windowModel.viewModels[element.id] else {
            XCTFail("Failed to retrieve viewModel")
            return
        }
        
        let properties = element.properties
        
        let view = View.buildView(element, viewModel, windowUUID, properties, logger)
        let _ = View.applyModifiers(view, element, windowUUID, properties, logger)
        
        logger.log("After buildView viewModel = \(String(describing: viewModel))", .debug)
        
        XCTAssertTrue(view is SwiftUI.EmptyView, "buildView should return EmptyView with empty properties")
    }
    
    func testBaseModifiersOffsetPartial() throws {
        let properties: [String: Any] = [
            "offset": ["x": 10.0]
        ]

        let mods = BaseModifiers(properties)

        XCTAssertEqual(mods.offset, BaseModifiers.Offset(x: 10.0, y: 0.0),
                       "offset.x should be 10.0; offset.y is 0 when not provided")
    }

    func testBaseModifiersOffsetInvalidX() throws {
        let properties: [String: Any] = [
            "offset": ["x": "10", "y": 20.0]
        ]

        let mods = BaseModifiers(properties)

        XCTAssertNil(mods.offset, "offset should be nil if x is not a number")
    }

    func testBaseModifiersOffsetInvalidY() throws {
        let properties: [String: Any] = [
            "offset": ["x": 10.0, "y": "20"]
        ]

        let mods = BaseModifiers(properties)

        XCTAssertNil(mods.offset, "offset should be nil if y is not a number")
    }

    func testBaseModifiersOffsetInvalidType() throws {
        let properties: [String: Any] = [
            "offset": "invalid"
        ]

        let mods = BaseModifiers(properties)

        XCTAssertNil(mods.offset, "offset should be nil for invalid type")
    }
    
    func testBuildViewAndApplyModifiersWithOffset() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "View",
            "properties": {
                "offset": {"x": 15.0, "y": -10.0},
                "padding": 10.0
            }
        }
        """
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to Data")
            return
        }
        
        let actionUIModel = ActionUIModel.shared
        let element = try actionUIModel.loadDescription(from: jsonData, format: "json", windowUUID: windowUUID)
        
        guard let windowModel = actionUIModel.windowModels[windowUUID],
              let viewModel = windowModel.viewModels[element.id] else {
            XCTFail("Failed to retrieve viewModel")
            return
        }
        
        let properties = element.properties
        
        let view = View.buildView(element, viewModel, windowUUID, properties, logger)
        let _ = View.applyModifiers(view, element, windowUUID, properties, logger)
        
        logger.log("After buildView viewModel = \(String(describing: viewModel))", .debug)
        
        XCTAssertTrue(view is SwiftUI.EmptyView, "buildView should return EmptyView")
        //        XCTAssertFalse(modifiedView is SwiftUI.EmptyView, "applyModifiers returns a modified view due to offset and padding modifiers")
        if let offset = element.properties["offset"] as? [String: Any] {
            XCTAssertEqual(offset.cgFloat(forKey: "x"), 15.0, "offset.x should be 15.0")
            XCTAssertEqual(offset.cgFloat(forKey: "y"), -10.0, "offset.y should be -10.0")
        } else {
            XCTFail("offset should be a dictionary")
        }
        XCTAssertEqual(element.properties.cgFloat(forKey: "padding"), 10.0, "padding should be 10.0")
    }
    
    func testBaseModifiersKeyboardShortcutValidSingleChar() throws {
        let properties: [String: Any] = [
            "keyboardShortcut": ["key": "a", "modifiers": ["command", "shift"]]
        ]

        let mods = BaseModifiers(properties)

        XCTAssertNotNil(mods.keyboardShortcut, "keyboardShortcut should be parsed")
        XCTAssertEqual(mods.keyboardShortcut?.key, "a", "keyboardShortcut.key should be 'a'")
        XCTAssertEqual(mods.keyboardShortcut?.modifiers, [.command, .shift], "keyboardShortcut.modifiers should be ['command', 'shift']")
    }

    func testBaseModifiersKeyboardShortcutValidSpecialKey() throws {
        let properties: [String: Any] = [
            "keyboardShortcut": ["key": "return", "modifiers": ["option"]]
        ]

        let mods = BaseModifiers(properties)

        XCTAssertNotNil(mods.keyboardShortcut, "keyboardShortcut should be parsed")
        XCTAssertEqual(mods.keyboardShortcut?.key, "return", "keyboardShortcut.key should be 'return'")
        XCTAssertEqual(mods.keyboardShortcut?.modifiers, [.option], "keyboardShortcut.modifiers should be ['option']")
    }

    func testBaseModifiersKeyboardShortcutDuplicateModifiers() throws {
        let properties: [String: Any] = [
            "keyboardShortcut": ["key": "b", "modifiers": ["command", "command", "shift"]]
        ]

        let mods = BaseModifiers(properties)

        XCTAssertNotNil(mods.keyboardShortcut, "keyboardShortcut should be parsed")
        XCTAssertEqual(mods.keyboardShortcut?.key, "b", "keyboardShortcut.key should be 'b'")
        XCTAssertEqual(mods.keyboardShortcut?.modifiers, [.command, .shift], "keyboardShortcut.modifiers should remove duplicates")
    }

    func testBaseModifiersKeyboardShortcutInvalidModifiers() throws {
        let properties: [String: Any] = [
            "keyboardShortcut": ["key": "c", "modifiers": ["invalid1", "invalid2"]]
        ]

        let mods = BaseModifiers(properties)

        XCTAssertNotNil(mods.keyboardShortcut, "keyboardShortcut should be parsed")
        XCTAssertEqual(mods.keyboardShortcut?.key, "c", "keyboardShortcut.key should be 'c'")
        XCTAssertEqual(mods.keyboardShortcut?.modifiers, [.command], "keyboardShortcut.modifiers should default to ['command'] for invalid modifiers")
    }

    func testBaseModifiersKeyboardShortcutCapsLockIsCaseInsensitive() throws {
        // "capsLock" is the documented spelling; the parser lowercases names, so it must
        // compare against "capslock" or the modifier is silently dropped (an old bug).
        let properties: [String: Any] = [
            "keyboardShortcut": ["key": "k", "modifiers": ["capsLock", "Shift"]]
        ]

        let mods = BaseModifiers(properties)

        XCTAssertNotNil(mods.keyboardShortcut, "keyboardShortcut should be parsed")
        XCTAssertEqual(mods.keyboardShortcut?.modifiers, [.capslock, .shift], "capsLock must be read regardless of case")
    }

    func testBaseModifiersKeyboardShortcutMissingModifiers() throws {
        let properties: [String: Any] = [
            "keyboardShortcut": ["key": "d"]
        ]

        let mods = BaseModifiers(properties)

        XCTAssertNotNil(mods.keyboardShortcut, "keyboardShortcut should be parsed")
        XCTAssertEqual(mods.keyboardShortcut?.key, "d", "keyboardShortcut.key should be 'd'")
        XCTAssertEqual(mods.keyboardShortcut?.modifiers, [.command], "keyboardShortcut.modifiers should default to ['command'] when missing")
    }

    func testBaseModifiersKeyboardShortcutEmptyModifiers() throws {
        let properties: [String: Any] = [
            "keyboardShortcut": ["key": "e", "modifiers": []]
        ]

        let mods = BaseModifiers(properties)

        XCTAssertNotNil(mods.keyboardShortcut, "keyboardShortcut should be parsed")
        XCTAssertEqual(mods.keyboardShortcut?.key, "e", "keyboardShortcut.key should be 'e'")
        // Provided but empty is not the same as omitted: it means the bare key, no modifier.
        XCTAssertEqual(mods.keyboardShortcut?.modifiers, [], "keyboardShortcut.modifiers [] must stay empty (no modifier), unlike a missing key which defaults to ['command']")
    }

    func testBaseModifiersKeyboardShortcutInvalidKey() throws {
        let properties: [String: Any] = [
            "keyboardShortcut": ["key": "invalid", "modifiers": ["command"]]
        ]

        let mods = BaseModifiers(properties)

        XCTAssertNil(mods.keyboardShortcut, "keyboardShortcut should be nil for invalid key")
    }

    func testBaseModifiersKeyboardShortcutMultiCharKey() throws {
        let properties: [String: Any] = [
            "keyboardShortcut": ["key": "ab", "modifiers": ["command"]]
        ]

        let mods = BaseModifiers(properties)

        XCTAssertNil(mods.keyboardShortcut, "keyboardShortcut should be nil for multi-character key (non-special)")
    }

    func testBaseModifiersKeyboardShortcutInvalidType() throws {
        let properties: [String: Any] = [
            "keyboardShortcut": "invalid"
        ]

        let mods = BaseModifiers(properties)

        XCTAssertNil(mods.keyboardShortcut, "keyboardShortcut should be nil for invalid type")
    }

    func testBaseModifiersKeyboardShortcutMissingKey() throws {
        let properties: [String: Any] = [
            "keyboardShortcut": ["modifiers": ["command"]]
        ]

        let mods = BaseModifiers(properties)

        XCTAssertNil(mods.keyboardShortcut, "keyboardShortcut should be nil for missing key")
    }

    func testBaseModifiersKeyboardShortcutInvalidModifiersType() throws {
        let properties: [String: Any] = [
            "keyboardShortcut": ["key": "f", "modifiers": "command"]
        ]

        let mods = BaseModifiers(properties)

        XCTAssertNotNil(mods.keyboardShortcut, "keyboardShortcut should be parsed")
        XCTAssertEqual(mods.keyboardShortcut?.key, "f", "keyboardShortcut.key should be 'f'")
        XCTAssertEqual(mods.keyboardShortcut?.modifiers, [.command], "keyboardShortcut.modifiers should default to ['command'] for invalid type")
    }
    
    func testBuildViewAndApplyModifiersWithKeyboardShortcut() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "View",
            "properties": {
                "keyboardShortcut": {"key": "s", "modifiers": ["command", "shift"]}
            }
        }
        """
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to Data")
            return
        }
        
        let actionUIModel = ActionUIModel.shared
        let element = try actionUIModel.loadDescription(from: jsonData, format: "json", windowUUID: windowUUID)
        
        guard let windowModel = actionUIModel.windowModels[windowUUID],
              let viewModel = windowModel.viewModels[element.id] else {
            XCTFail("Failed to retrieve viewModel")
            return
        }
        
        let properties = element.properties
        
        let view = View.buildView(element, viewModel, windowUUID, properties, logger)
        let _ = View.applyModifiers(view, element, windowUUID, properties, logger)
        
        logger.log("After buildView viewModel = \(String(describing: viewModel))", .debug)
        
        XCTAssertTrue(view is SwiftUI.EmptyView, "buildView should return EmptyView")
        if let shortcut = element.properties["keyboardShortcut"] as? [String: Any] {
            XCTAssertEqual(shortcut["key"] as? String, "s", "keyboardShortcut.key should be 's'")
            if let modifiers = shortcut["modifiers"] as? [String] {
                XCTAssertEqual(Set(modifiers), Set(["command", "shift"]), "keyboardShortcut.modifiers should be ['command', 'shift']")
            } else {
                XCTFail("keyboardShortcut.modifiers should be an array")
            }
        } else {
            XCTFail("keyboardShortcut should be a dictionary")
        }
    }
    
    func testBuildViewAndApplyModifiersWithSpecialKeyKeyboardShortcut() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "View",
            "properties": {
                "keyboardShortcut": {"key": "return", "modifiers": ["option"]}
            }
        }
        """
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to Data")
            return
        }
        
        let actionUIModel = ActionUIModel.shared
        let element = try actionUIModel.loadDescription(from: jsonData, format: "json", windowUUID: windowUUID)
        
        guard let windowModel = actionUIModel.windowModels[windowUUID],
              let viewModel = windowModel.viewModels[element.id] else {
            XCTFail("Failed to retrieve viewModel")
            return
        }
        
        let properties = element.properties
        
        let view = View.buildView(element, viewModel, windowUUID, properties, logger)
        let _ = View.applyModifiers(view, element, windowUUID, properties, logger)
        
        logger.log("After buildView viewModel = \(String(describing: viewModel))", .debug)
        
        XCTAssertTrue(view is SwiftUI.EmptyView, "buildView should return EmptyView")
        if let shortcut = element.properties["keyboardShortcut"] as? [String: Any] {
            XCTAssertEqual(shortcut["key"] as? String, "return", "keyboardShortcut.key should be 'return'")
            if let modifiers = shortcut["modifiers"] as? [String] {
                XCTAssertEqual(Set(modifiers), Set(["option"]), "keyboardShortcut.modifiers should be ['option']")
            } else {
                XCTFail("keyboardShortcut.modifiers should be an array")
            }
        } else {
            XCTFail("keyboardShortcut should be a dictionary")
        }
    }
    
    func testBuildViewAndApplyModifiersWithInvalidKeyboardShortcut() throws {
        let jsonString = """
            {
                "id": 1,
                "type": "View",
                "properties": {
                    "keyboardShortcut": {"key": "invalid", "modifiers": ["command"]}
                }
            }
            """
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to Data")
            return
        }
        
        let actionUIModel = ActionUIModel.shared
        let element = try actionUIModel.loadDescription(from: jsonData, format: "json", windowUUID: windowUUID)
        
        guard let windowModel = actionUIModel.windowModels[windowUUID],
              let viewModel = windowModel.viewModels[element.id] else {
            XCTFail("Failed to retrieve viewModel")
            return
        }
        
        let properties = element.properties
        
        let view = View.buildView(element, viewModel, windowUUID, properties, logger)
        let _ = View.applyModifiers(view, element, windowUUID, properties, logger)
        
        logger.log("After buildView viewModel = \(String(describing: viewModel))", .debug)
        
        XCTAssertTrue(view is SwiftUI.EmptyView, "buildView should return EmptyView")
        XCTAssertNil(BaseModifiers(properties).keyboardShortcut, "keyboardShortcut should be nil for invalid key")
    }

    // MARK: - controlSize Props

    func testBaseModifiersControlSizeValid() throws {
        for size in ["mini", "small", "regular", "large", "extraLarge"] {
            let properties: [String: Any] = ["controlSize": size]
            let mods = BaseModifiers(properties)
            XCTAssertEqual(mods.controlSize?.rawValue, size, "controlSize '\(size)' should be valid")
        }
    }

    func testBaseModifiersControlSizeInvalidValue() throws {
        let properties: [String: Any] = ["controlSize": "huge"]
        let mods = BaseModifiers(properties)
        XCTAssertNil(mods.controlSize, "Invalid controlSize should be nil")
    }

    func testBaseModifiersControlSizeInvalidType() throws {
        let properties: [String: Any] = ["controlSize": 42]
        let mods = BaseModifiers(properties)
        XCTAssertNil(mods.controlSize, "Non-string controlSize should be nil")
    }

    // MARK: - destinationViewId Props

    func testBaseModifiersDestinationViewIdValidInt() throws {
        let properties: [String: Any] = ["destinationViewId": 10]
        let mods = BaseModifiers(properties)
        XCTAssertEqual(mods.destinationViewId, 10, "destinationViewId should read a valid Int")
    }

    func testBaseModifiersDestinationViewIdInvalidType() throws {
        let properties: [String: Any] = ["destinationViewId": "ten"]
        let mods = BaseModifiers(properties)
        XCTAssertNil(mods.destinationViewId, "destinationViewId should be nil for String type")

        let properties2: [String: Any] = ["destinationViewId": 10.5]
        let mods2 = BaseModifiers(properties2)
        XCTAssertNil(mods2.destinationViewId, "destinationViewId should be nil for Double type")
    }

    func testBaseModifiersDestinationViewIdMissing() throws {
        let properties: [String: Any] = ["padding": 10.0]
        let mods = BaseModifiers(properties)
        XCTAssertNil(mods.destinationViewId, "destinationViewId should be nil when not provided")
    }

    func testBaseModifiersRotationEffectValid() throws {
        let mods = BaseModifiers(["rotationEffect": 45.0])
        XCTAssertEqual(mods.rotationDegrees, 45.0)
    }

    func testBaseModifiersRotationEffectNegative() throws {
        let mods = BaseModifiers(["rotationEffect": -90.0])
        XCTAssertEqual(mods.rotationDegrees, -90.0)
    }

    func testBaseModifiersRotationEffectInvalidType() throws {
        let mods = BaseModifiers(["rotationEffect": "45"])
        XCTAssertNil(mods.rotationDegrees)
    }

    func testBaseModifiersScaleEffectUniform() throws {
        let mods = BaseModifiers(["scaleEffect": 1.5])
        XCTAssertEqual(mods.scale, BaseModifiers.Scale(x: 1.5, y: 1.5, anchor: .center))
    }

    func testBaseModifiersScaleEffectDict() throws {
        let mods = BaseModifiers(["scaleEffect": ["x": 2.0, "y": 0.5, "anchor": "topLeading"]])
        XCTAssertEqual(mods.scale, BaseModifiers.Scale(x: 2.0, y: 0.5, anchor: .topLeading))
    }

    func testBaseModifiersScaleEffectDictInvalidAnchor() throws {
        let mods = BaseModifiers(["scaleEffect": ["x": 1.0, "y": 1.0, "anchor": "invalid"]])
        XCTAssertNotNil(mods.scale, "scaleEffect should still be parsed with an unknown anchor")
        XCTAssertEqual(mods.scale?.anchor, .center, "invalid anchor should fall back to center")
    }

    func testBaseModifiersScaleEffectInvalidType() throws {
        let mods = BaseModifiers(["scaleEffect": "big"])
        XCTAssertNil(mods.scale)
    }

    func testBaseModifiersZIndexValid() throws {
        let mods = BaseModifiers(["zIndex": 5.0])
        XCTAssertEqual(mods.zIndex, 5.0)
    }

    func testBaseModifiersZIndexNegative() throws {
        let mods = BaseModifiers(["zIndex": -10.0])
        XCTAssertEqual(mods.zIndex, -10.0)
    }

    func testBaseModifiersZIndexInvalidType() throws {
        let mods = BaseModifiers(["zIndex": "first"])
        XCTAssertNil(mods.zIndex)
    }

    func testBaseModifiersScaleEffectDictInvalidX() throws {
        let mods = BaseModifiers(["scaleEffect": ["x": "bad", "y": 1.0]])
        XCTAssertNil(mods.scale)
    }

    // MARK: - animation Props

    func testBaseModifiersAnimationStringShorthand() throws {
        let mods = BaseModifiers(["animation": "spring"])
        XCTAssertEqual(mods.animation?.curve, .spring)
    }

    func testBaseModifiersAnimationStringAllCurves() throws {
        let curves = ["default", "linear", "easeIn", "easeOut", "easeInOut",
                      "spring", "bouncy", "smooth", "snappy", "interactiveSpring"]
        for curve in curves {
            let mods = BaseModifiers(["animation": curve])
            XCTAssertNotNil(mods.animation, "curve '\(curve)' should be valid")
        }
    }

    func testBaseModifiersAnimationStringInvalidCurve() throws {
        let mods = BaseModifiers(["animation": "bounce"])
        XCTAssertNil(mods.animation)
    }

    func testBaseModifiersAnimationDictFullForm() throws {
        let props: [String: Any] = ["animation": [
            "curve": "easeInOut",
            "duration": 0.3,
            "delay": 0.1,
            "speed": 2.0,
            "value": "opacity"
        ]]
        let mods = BaseModifiers(props)
        XCTAssertNotNil(mods.animation, "animation should be parsed")
        XCTAssertEqual(mods.animation?.curve, .easeInOut)
        XCTAssertEqual(mods.animation?.duration, 0.3)
        XCTAssertEqual(mods.animation?.delay, 0.1)
        XCTAssertEqual(mods.animation?.speed, 2.0)
        XCTAssertEqual(mods.animation?.watchedValue, "opacity")
    }

    func testBaseModifiersAnimationDictMissingCurve() throws {
        let mods = BaseModifiers(["animation": ["duration": 0.3]])
        XCTAssertNil(mods.animation)
    }

    func testBaseModifiersAnimationDictInvalidCurve() throws {
        let mods = BaseModifiers(["animation": ["curve": "warp"]])
        XCTAssertNil(mods.animation)
    }

    func testBaseModifiersAnimationDictNegativeDurationIgnored() throws {
        let mods = BaseModifiers(["animation": ["curve": "spring", "duration": -1.0]])
        XCTAssertNotNil(mods.animation, "animation dict should still be valid without duration")
        XCTAssertNil(mods.animation?.duration, "negative duration should be ignored")
    }

    func testBaseModifiersAnimationDictInvalidSpeedIgnored() throws {
        let mods = BaseModifiers(["animation": ["curve": "linear", "speed": "fast"]])
        XCTAssertNotNil(mods.animation, "animation dict should still be valid without speed")
        XCTAssertEqual(mods.animation?.speed, 1.0, "invalid speed type should be ignored (default speed)")
    }

    func testBaseModifiersAnimationDictInvalidValueTypeIgnored() throws {
        let mods = BaseModifiers(["animation": ["curve": "spring", "value": 42]])
        XCTAssertNotNil(mods.animation, "animation dict should still be valid without value")
        XCTAssertNil(mods.animation?.watchedValue, "non-String value should be ignored")
    }

    func testBaseModifiersAnimationInvalidType() throws {
        let mods = BaseModifiers(["animation": true])
        XCTAssertNil(mods.animation)
    }

    // MARK: - transition Props

    func testBaseModifiersTransitionStringShorthand() throws {
        let mods = BaseModifiers(["transition": "opacity"])
        XCTAssertEqual(mods.transition, .opacity, "shorthand should read as the named transition")
    }

    func testBaseModifiersTransitionAllShorthands() throws {
        for name in ["opacity", "slide", "scale", "identity"] {
            let mods = BaseModifiers(["transition": name])
            XCTAssertNotNil(mods.transition, "shorthand '\(name)' should be valid")
        }
    }

    func testBaseModifiersTransitionInvalidShorthand() throws {
        let mods = BaseModifiers(["transition": "explode"])
        XCTAssertNil(mods.transition)
    }

    func testBaseModifiersTransitionMoveDict() throws {
        let mods = BaseModifiers(["transition": ["type": "move", "edge": "bottom"]])
        XCTAssertEqual(mods.transition, .move(edge: .bottom))
    }

    func testBaseModifiersTransitionDictMissingType() throws {
        let mods = BaseModifiers(["transition": ["edge": "top"]])
        XCTAssertNil(mods.transition)
    }

    func testBaseModifiersTransitionDictInvalidType() throws {
        let mods = BaseModifiers(["transition": ["type": "warp"]])
        XCTAssertNil(mods.transition)
    }

    func testBaseModifiersTransitionAsymmetricReadsHalves() throws {
        let props: [String: Any] = ["transition": [
            "type": "asymmetric",
            "insertion": "opacity",
            "removal": ["type": "move", "edge": "leading"]
        ]]
        let mods = BaseModifiers(props)
        XCTAssertEqual(mods.transition, .asymmetric(insertion: .opacity, removal: .move(edge: .leading)),
                       "insertion shorthand and removal dict should both be read")
    }

    func testBaseModifiersTransitionAsymmetricDefaultsMissingHalves() throws {
        let mods = BaseModifiers(["transition": ["type": "asymmetric"]])
        XCTAssertEqual(mods.transition, .asymmetric(insertion: .identity, removal: .identity))
    }

    func testBaseModifiersTransitionArrayCombined() throws {
        let mods = BaseModifiers(["transition": ["opacity", ["type": "scale", "scale": 0.8]]])
        XCTAssertEqual(mods.transition, .combined([.opacity, .scale(factor: 0.8, anchor: .center)]))
    }

    func testBaseModifiersTransitionArrayDropsInvalidEntries() throws {
        let mods = BaseModifiers(["transition": ["opacity", "explode"]])
        XCTAssertEqual(mods.transition, .combined([.opacity]), "the invalid entry should be skipped")
    }

    func testBaseModifiersTransitionEmptyArrayDropped() throws {
        let mods = BaseModifiers(["transition": ["explode", "warp"]])
        XCTAssertNil(mods.transition)
    }

    func testBaseModifiersTransitionInvalidType() throws {
        let mods = BaseModifiers(["transition": 42])
        XCTAssertNil(mods.transition)
    }

    // MARK: - clipShape Props

    func testBaseModifiersClipShapeCircle() throws {
        let mods = BaseModifiers(["clipShape": "circle"])
        XCTAssertEqual(mods.clipShape, .circle)
    }

    func testBaseModifiersClipShapeCapsule() throws {
        let mods = BaseModifiers(["clipShape": "capsule"])
        XCTAssertEqual(mods.clipShape, .capsule)
    }

    func testBaseModifiersClipShapeEllipse() throws {
        let mods = BaseModifiers(["clipShape": "ellipse"])
        XCTAssertEqual(mods.clipShape, .ellipse)
    }

    func testBaseModifiersClipShapeRectangle() throws {
        let mods = BaseModifiers(["clipShape": "rectangle"])
        XCTAssertEqual(mods.clipShape, .rectangle)
    }

    func testBaseModifiersClipShapeInvalidString() throws {
        let mods = BaseModifiers(["clipShape": "square"])
        XCTAssertNil(mods.clipShape)
    }

    func testBaseModifiersClipShapeRoundedRectangleUniform() throws {
        let mods = BaseModifiers(["clipShape": ["type": "roundedRectangle", "cornerRadius": 12] as [String: Any]])
        XCTAssertEqual(mods.clipShape, .roundedRectangle(radiusX: 12.0, radiusY: 12.0))
    }

    func testBaseModifiersClipShapeRoundedRectanglePerAxis() throws {
        let mods = BaseModifiers(["clipShape": ["type": "roundedRectangle", "cornerRadiusX": 20, "cornerRadiusY": 8] as [String: Any]])
        XCTAssertEqual(mods.clipShape, .roundedRectangle(radiusX: 20.0, radiusY: 8.0))
    }

    func testBaseModifiersClipShapeRoundedRectangleMissingRadius() throws {
        let mods = BaseModifiers(["clipShape": ["type": "roundedRectangle"] as [String: Any]])
        XCTAssertNil(mods.clipShape)
    }

    func testBaseModifiersClipShapeRoundedRectanglePartialPerAxis() throws {
        // cornerRadiusX without cornerRadiusY should be rejected
        let mods = BaseModifiers(["clipShape": ["type": "roundedRectangle", "cornerRadiusX": 12] as [String: Any]])
        XCTAssertNil(mods.clipShape)
    }

    func testBaseModifiersClipShapeUnsupportedDictType() throws {
        let mods = BaseModifiers(["clipShape": ["type": "star"] as [String: Any]])
        XCTAssertNil(mods.clipShape)
    }

    func testBaseModifiersClipShapeInvalidType() throws {
        let mods = BaseModifiers(["clipShape": 12])
        XCTAssertNil(mods.clipShape)
    }

    func testTextSelectionEnabled() throws {
        let mods = BaseModifiers(["textSelection": "enabled"])
        XCTAssertEqual(mods.textSelection, .enabled)
    }

    func testTextSelectionDisabled() throws {
        let mods = BaseModifiers(["textSelection": "disabled"])
        XCTAssertEqual(mods.textSelection, .disabled)
    }

    func testTextSelectionInvalidValue() throws {
        let mods = BaseModifiers(["textSelection": "yes"])
        XCTAssertNil(mods.textSelection)
    }

    func testTextSelectionInvalidType() throws {
        let mods = BaseModifiers(["textSelection": true])
        XCTAssertNil(mods.textSelection)
    }

    func testMultilineTextAlignmentValid() throws {
        for value in ["leading", "center", "trailing"] {
            let mods = BaseModifiers(["multilineTextAlignment": value])
            XCTAssertEqual(mods.multilineTextAlignment?.rawValue, value,
                           "multilineTextAlignment '\(value)' should be read")
        }
    }

    func testMultilineTextAlignmentInvalid() throws {
        let mods = BaseModifiers(["multilineTextAlignment": "justify"])
        XCTAssertNil(mods.multilineTextAlignment, "Invalid multilineTextAlignment should be ignored")
    }

    func testMultilineTextAlignmentInvalidType() throws {
        let mods = BaseModifiers(["multilineTextAlignment": 1])
        XCTAssertNil(mods.multilineTextAlignment, "Non-string multilineTextAlignment should be ignored")
    }

    // MARK: - help Props

    func testHelpValid() throws {
        let mods = BaseModifiers(["help": "Run action"])
        XCTAssertEqual(mods.help, "Run action")
    }

    func testHelpInvalidType() throws {
        let mods = BaseModifiers(["help": 42])
        XCTAssertNil(mods.help)
    }
}
