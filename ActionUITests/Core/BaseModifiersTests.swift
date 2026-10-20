// Core/BaseModifiersTests.swift
/*
 Tests for BaseModifiers: every base property key reaches its field with the right type, unusable
 values give nil or the documented default, and the structured values go through ModifierParsing.
*/

import XCTest
@testable import ActionUI

final class BaseModifiersTests: XCTestCase {

    func testEmptyPropertiesGiveNothingToApply() {
        let mods = BaseModifiers([:])
        XCTAssertNil(mods.padding)
        XCTAssertNil(mods.font)
        XCTAssertNil(mods.foregroundStyle)
        XCTAssertNil(mods.tint)
        XCTAssertNil(mods.disabled)
        XCTAssertFalse(mods.hidden)
        XCTAssertNil(mods.frame)
        XCTAssertNil(mods.background)
        XCTAssertEqual(mods.backgroundAlignment, .center)
        XCTAssertNil(mods.cornerRadius)
        XCTAssertNil(mods.clipShape)
        XCTAssertNil(mods.offset)
        XCTAssertNil(mods.opacity)
        XCTAssertNil(mods.textSelection)
        XCTAssertNil(mods.rotationDegrees)
        XCTAssertNil(mods.scale)
        XCTAssertNil(mods.multilineTextAlignment)
        XCTAssertNil(mods.zIndex)
        XCTAssertNil(mods.border)
        XCTAssertEqual(mods.overlayAlignment, .center)
        XCTAssertNil(mods.ignoresSafeArea)
        XCTAssertNil(mods.buttonStyle)
        XCTAssertNil(mods.controlSize)
        XCTAssertFalse(mods.labelsHidden)
        XCTAssertNil(mods.scrollContentBackground)
        XCTAssertNil(mods.shadow)
        XCTAssertNil(mods.animation)
        XCTAssertNil(mods.transition)
        XCTAssertNil(mods.openURLActionID)
        XCTAssertNil(mods.onAppearActionID)
        XCTAssertNil(mods.onDisappearActionID)
        XCTAssertNil(mods.onHoverActionID)
        XCTAssertNil(mods.columnWidth)
        XCTAssertNil(mods.keyboardShortcut)
        XCTAssertNil(mods.navigationTitle)
        XCTAssertNil(mods.titleDisplayMode)
        XCTAssertNil(mods.help)
        XCTAssertNil(mods.accessibilityLabel)
        XCTAssertNil(mods.accessibilityHint)
        XCTAssertNil(mods.accessibilityHidden)
        XCTAssertNil(mods.accessibilityIdentifier)
        XCTAssertNil(mods.drop)
        XCTAssertNil(mods.sheetOnDismissActionID)
        XCTAssertNil(mods.fullScreenCoverOnDismissActionID)
        XCTAssertNil(mods.searchable)
        XCTAssertEqual(mods.popoverArrowEdge, .top)
        XCTAssertNil(mods.popoverActionID)
    }

    func testStringAndBoolKeys() {
        let mods = BaseModifiers([
            "foregroundStyle": "red", "tint": "blue", "background": "white",
            "disabled": false, "hidden": true, "labelsHidden": true,
            "openURLActionID": "url", "onAppearActionID": "appear", "onDisappearActionID": "disappear",
            "onHoverActionID": "hover", "navigationTitle": "Detail", "help": "Tip",
            "accessibilityLabel": "Label", "accessibilityHint": "Hint", "accessibilityHidden": true,
            "accessibilityIdentifier": "id_1", "sheetOnDismissActionID": "sheet",
            "fullScreenCoverOnDismissActionID": "cover", "popoverActionID": "popover",
        ])
        XCTAssertEqual(mods.foregroundStyle, "red")
        XCTAssertEqual(mods.tint, "blue")
        XCTAssertEqual(mods.background, "white")
        XCTAssertEqual(mods.disabled, false)
        XCTAssertTrue(mods.hidden)
        XCTAssertTrue(mods.labelsHidden)
        XCTAssertEqual(mods.openURLActionID, "url")
        XCTAssertEqual(mods.onAppearActionID, "appear")
        XCTAssertEqual(mods.onDisappearActionID, "disappear")
        XCTAssertEqual(mods.onHoverActionID, "hover")
        XCTAssertEqual(mods.navigationTitle, "Detail")
        XCTAssertEqual(mods.help, "Tip")
        XCTAssertEqual(mods.accessibilityLabel, "Label")
        XCTAssertEqual(mods.accessibilityHint, "Hint")
        XCTAssertEqual(mods.accessibilityHidden, true)
        XCTAssertEqual(mods.accessibilityIdentifier, "id_1")
        XCTAssertEqual(mods.sheetOnDismissActionID, "sheet")
        XCTAssertEqual(mods.fullScreenCoverOnDismissActionID, "cover")
        XCTAssertEqual(mods.popoverActionID, "popover")
    }

    func testWrongTypesAreIgnored() {
        let mods = BaseModifiers([
            "foregroundStyle": 5, "tint": [1] as [Any], "background": 3, "disabled": "yes", "hidden": 1,
            "labelsHidden": "true", "help": 5, "accessibilityHidden": "no", "navigationTitle": 5,
            "font": 12, "cornerRadius": "8", "opacity": "0.5", "rotationEffect": "45", "zIndex": "1",
        ])
        XCTAssertNil(mods.foregroundStyle)
        XCTAssertNil(mods.tint)
        XCTAssertNil(mods.background)
        XCTAssertNil(mods.disabled)
        XCTAssertFalse(mods.hidden)
        XCTAssertFalse(mods.labelsHidden)
        XCTAssertNil(mods.help)
        XCTAssertNil(mods.accessibilityHidden)
        XCTAssertNil(mods.navigationTitle)
        XCTAssertNil(mods.font)
        XCTAssertNil(mods.cornerRadius)
        XCTAssertNil(mods.opacity)
        XCTAssertNil(mods.rotationDegrees)
        XCTAssertNil(mods.zIndex)
    }

    func testFontKeepsAStringOrADictionary() {
        XCTAssertEqual(BaseModifiers(["font": "title"]).font as? String, "title")
        let descriptor = BaseModifiers(["font": ["name": "Menlo", "size": 12]]).font as? [String: Any]
        XCTAssertEqual(descriptor?["name"] as? String, "Menlo")
        XCTAssertEqual(descriptor?["size"] as? Int, 12)
    }

    func testNumbers() {
        let mods = BaseModifiers(["cornerRadius": 8, "rotationEffect": 45.5, "zIndex": 2, "opacity": 0.5])
        XCTAssertEqual(mods.cornerRadius, 8)
        XCTAssertEqual(mods.rotationDegrees, 45.5)
        XCTAssertEqual(mods.zIndex, 2)
        XCTAssertEqual(mods.opacity, 0.5)
    }

    func testOpacityOutsideZeroToOneIsIgnored() {
        XCTAssertEqual(BaseModifiers(["opacity": 0]).opacity, 0)
        XCTAssertEqual(BaseModifiers(["opacity": 1]).opacity, 1)
        XCTAssertNil(BaseModifiers(["opacity": 1.5]).opacity)
        XCTAssertNil(BaseModifiers(["opacity": -0.1]).opacity)
    }

    func testAlignmentsDefaultToCenter() {
        XCTAssertEqual(BaseModifiers(["backgroundAlignment": "top"]).backgroundAlignment, .top)
        XCTAssertEqual(BaseModifiers(["backgroundAlignment": "nowhere"]).backgroundAlignment, .center)
        XCTAssertEqual(BaseModifiers(["overlayAlignment": "bottomTrailing"]).overlayAlignment, .bottomTrailing)
        XCTAssertEqual(BaseModifiers(["overlayAlignment": 5]).overlayAlignment, .center)
    }

    func testPopoverArrowEdgeDefaultsToTop() {
        XCTAssertEqual(BaseModifiers(["popoverArrowEdge": "bottom"]).popoverArrowEdge, .bottom)
        XCTAssertEqual(BaseModifiers(["popoverArrowEdge": "nowhere"]).popoverArrowEdge, .top)
        XCTAssertEqual(BaseModifiers(["popoverArrowEdge": 5]).popoverArrowEdge, .top)
    }

    func testStyleNames() {
        for name in BaseModifiers.ButtonStyleName.allCases {
            XCTAssertEqual(BaseModifiers(["buttonStyle": name.rawValue]).buttonStyle, name)
        }
        for name in BaseModifiers.ControlSizeName.allCases {
            XCTAssertEqual(BaseModifiers(["controlSize": name.rawValue]).controlSize, name)
        }
        for name in BaseModifiers.ScrollContentBackground.allCases {
            XCTAssertEqual(BaseModifiers(["scrollContentBackground": name.rawValue]).scrollContentBackground, name)
        }
        for name in BaseModifiers.TextSelection.allCases {
            XCTAssertEqual(BaseModifiers(["textSelection": name.rawValue]).textSelection, name)
        }
        for name in BaseModifiers.TextAlignment.allCases {
            XCTAssertEqual(BaseModifiers(["multilineTextAlignment": name.rawValue]).multilineTextAlignment, name)
        }
        for name in BaseModifiers.TitleDisplayMode.allCases {
            XCTAssertEqual(BaseModifiers(["toolbarTitleDisplayMode": name.rawValue]).titleDisplayMode, name)
        }
    }

    func testUnknownStyleNamesAreIgnored() {
        let mods = BaseModifiers([
            "buttonStyle": "fancy", "controlSize": "huge", "scrollContentBackground": "gone",
            "textSelection": "maybe", "multilineTextAlignment": "justified", "toolbarTitleDisplayMode": "huge",
        ])
        XCTAssertNil(mods.buttonStyle)
        XCTAssertNil(mods.controlSize)
        XCTAssertNil(mods.scrollContentBackground)
        XCTAssertNil(mods.textSelection)
        XCTAssertNil(mods.multilineTextAlignment)
        XCTAssertNil(mods.titleDisplayMode)
    }

    func testIgnoresSafeArea() {
        XCTAssertEqual(BaseModifiers(["ignoresSafeArea": true]).ignoresSafeArea, BaseModifiers.SafeArea())
        XCTAssertNil(BaseModifiers(["ignoresSafeArea": false]).ignoresSafeArea)
        XCTAssertEqual(
            BaseModifiers(["ignoresSafeArea": ["regions": "keyboard", "edges": "vertical"]]).ignoresSafeArea,
            BaseModifiers.SafeArea(regions: .keyboard, edges: .vertical)
        )
        XCTAssertEqual(
            BaseModifiers(["ignoresSafeArea": ["edges": "nowhere"]]).ignoresSafeArea,
            BaseModifiers.SafeArea(regions: .all, edges: .all)
        )
        XCTAssertNil(BaseModifiers(["ignoresSafeArea": "all"]).ignoresSafeArea)
    }

    func testDropNeedsAnActionAndTypes() {
        XCTAssertEqual(
            BaseModifiers(["onDropActionID": "dropped", "onDropTypes": ["public.text"] as [Any], "onDropTargetedActionID": "targeted"]).drop,
            BaseModifiers.Drop(actionID: "dropped", types: ["public.text"], targetedActionID: "targeted")
        )
        XCTAssertEqual(
            BaseModifiers(["onDropActionID": "dropped", "onDropTypes": ["public.text"] as [Any], "onDropTargetedActionID": 5]).drop,
            BaseModifiers.Drop(actionID: "dropped", types: ["public.text"], targetedActionID: nil)
        )
        XCTAssertNil(BaseModifiers(["onDropActionID": "dropped", "onDropTypes": [Any]()]).drop)
        XCTAssertNil(BaseModifiers(["onDropActionID": "dropped", "onDropTypes": "public.text"]).drop)
        XCTAssertNil(BaseModifiers(["onDropTypes": ["public.text"] as [Any]]).drop)
    }

    func testSearchableNeedsANonEmptyAction() {
        XCTAssertEqual(
            BaseModifiers(["searchable": ["actionID": "query", "prompt": "Search"]]).searchable,
            BaseModifiers.Searchable(actionID: "query", prompt: "Search")
        )
        XCTAssertEqual(
            BaseModifiers(["searchable": ["actionID": "query", "prompt": 5]]).searchable,
            BaseModifiers.Searchable(actionID: "query", prompt: nil)
        )
        XCTAssertNil(BaseModifiers(["searchable": ["actionID": ""]]).searchable)
        XCTAssertNil(BaseModifiers(["searchable": ["prompt": "Search"]]).searchable)
        XCTAssertNil(BaseModifiers(["searchable": "query"]).searchable)
    }

    func testPropertiesOtherElementsRead() {
        let mods = BaseModifiers(["actionID": "row.selected", "destinationViewId": 12])
        XCTAssertEqual(mods.actionID, "row.selected")
        XCTAssertEqual(mods.destinationViewId, 12)
        XCTAssertNil(BaseModifiers([:]).actionID)
        XCTAssertNil(BaseModifiers([:]).destinationViewId)
        // An Int only, and a String only.
        XCTAssertNil(BaseModifiers(["destinationViewId": "12"]).destinationViewId)
        XCTAssertNil(BaseModifiers(["destinationViewId": 12.5]).destinationViewId)
        XCTAssertNil(BaseModifiers(["actionID": 5]).actionID)
    }

    func testStructuredKeysUseModifierParsing() {
        let mods = BaseModifiers([
            "padding": 10, "frame": ["width": 100], "clipShape": "circle", "offset": ["x": 1],
            "scaleEffect": 2, "border": [String: Any](), "shadow": ["radius": 5], "animation": "spring",
            "transition": "opacity", "navigationSplitViewColumnWidth": 300, "keyboardShortcut": ["key": "s"],
        ])
        XCTAssertEqual(mods.padding, .uniform(10))
        XCTAssertEqual(mods.frame, BaseModifiers.Frame(width: 100))
        XCTAssertEqual(mods.clipShape, .circle)
        XCTAssertEqual(mods.offset, BaseModifiers.Offset(x: 1, y: 0))
        XCTAssertEqual(mods.scale, BaseModifiers.Scale(x: 2, y: 2, anchor: .center))
        XCTAssertEqual(mods.border, BaseModifiers.Border(color: nil, width: 1))
        XCTAssertEqual(mods.shadow, BaseModifiers.Shadow(color: nil, radius: 5, x: 0, y: 0))
        XCTAssertEqual(mods.animation, BaseModifiers.Animation(curve: .spring))
        XCTAssertEqual(mods.transition, .opacity)
        XCTAssertEqual(mods.columnWidth, .fixed(300))
        XCTAssertEqual(mods.keyboardShortcut, BaseModifiers.KeyboardShortcut(key: "s", modifiers: [.command]))
    }
}
