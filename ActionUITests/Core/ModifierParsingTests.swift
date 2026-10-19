// Core/ModifierParsingTests.swift
/*
 Tests for ModifierParsing: each rule for a structured base modifier value, with the values JSON
 decoding produces (Int for integral numbers, [String: Any], [Any]) and with unusable ones.
*/

import XCTest
@testable import ActionUI

final class ModifierParsingTests: XCTestCase {

    // MARK: - Padding

    func testPaddingNumberAndDefault() {
        XCTAssertEqual(ModifierParsing.padding(10), .uniform(10))
        XCTAssertEqual(ModifierParsing.padding(10.5), .uniform(10.5))
        XCTAssertEqual(ModifierParsing.padding("default"), .system)
        XCTAssertEqual(ModifierParsing.padding("DEFAULT"), .system)
        XCTAssertEqual(ModifierParsing.padding("inf"), .uniform(.infinity))
    }

    func testPaddingEdgesFillMissingWithZero() {
        XCTAssertEqual(ModifierParsing.padding(["top": 5]), .edges(top: 5, leading: 0, bottom: 0, trailing: 0))
        XCTAssertEqual(
            ModifierParsing.padding(["top": 1, "leading": 2.5, "bottom": 3, "trailing": 4]),
            .edges(top: 1, leading: 2.5, bottom: 3, trailing: 4)
        )
        // A non-numeric edge counts as missing when another edge is usable.
        XCTAssertEqual(ModifierParsing.padding(["top": "x", "leading": 5]), .edges(top: 0, leading: 5, bottom: 0, trailing: 0))
    }

    func testPaddingUnusable() {
        XCTAssertNil(ModifierParsing.padding(nil))
        XCTAssertNil(ModifierParsing.padding([String: Any]()))
        XCTAssertNil(ModifierParsing.padding(["top": "x"]))
        XCTAssertNil(ModifierParsing.padding("big"))
        XCTAssertNil(ModifierParsing.padding(true))
        XCTAssertNil(ModifierParsing.padding([1] as [Any]))
    }

    // MARK: - Frame

    func testFrameFixed() {
        let frame = ModifierParsing.frame(["width": 100, "height": 50.5, "alignment": "topLeading"])
        XCTAssertEqual(frame, BaseModifiers.Frame(width: 100, height: 50.5, alignment: .topLeading))
        XCTAssertEqual(frame?.isFixed, true)
        XCTAssertEqual(frame?.isFlexible, false)
    }

    func testFrameFlexibleAcceptsInfinity() {
        let frame = ModifierParsing.frame(["minWidth": 10, "maxWidth": "inf"])
        XCTAssertEqual(frame, BaseModifiers.Frame(minWidth: 10, maxWidth: .infinity))
        XCTAssertEqual(frame?.isFixed, false)
        XCTAssertEqual(frame?.isFlexible, true)
    }

    func testFrameMixingFormsIsRefused() {
        XCTAssertNil(ModifierParsing.frame(["width": 10, "minWidth": 5]))
    }

    func testFrameWithNonNumericSizeIsRefused() {
        XCTAssertNil(ModifierParsing.frame(["width": "wide"]))
        XCTAssertNil(ModifierParsing.frame(["minHeight": 10, "maxHeight": true]))
    }

    func testFrameUnknownAlignmentIsDropped() {
        XCTAssertEqual(ModifierParsing.frame(["width": 100, "alignment": "nowhere"]), BaseModifiers.Frame(width: 100))
    }

    func testFrameWithoutSizesOnlyAligns() {
        let aligned = ModifierParsing.frame(["alignment": "bottom"])
        XCTAssertEqual(aligned, BaseModifiers.Frame(alignment: .bottom))
        XCTAssertEqual(aligned?.isFixed, false)
        XCTAssertEqual(aligned?.isFlexible, false)
        XCTAssertEqual(ModifierParsing.frame([String: Any]()), BaseModifiers.Frame())
        XCTAssertEqual(ModifierParsing.frame(["alignment": 5]), BaseModifiers.Frame())
    }

    func testFrameNotADictionary() {
        XCTAssertNil(ModifierParsing.frame(nil))
        XCTAssertNil(ModifierParsing.frame("100"))
        XCTAssertNil(ModifierParsing.frame(100))
    }

    // MARK: - Offset

    func testOffset() {
        XCTAssertEqual(ModifierParsing.offset(["x": 10]), BaseModifiers.Offset(x: 10, y: 0))
        XCTAssertEqual(ModifierParsing.offset(["x": 10, "y": -5.5]), BaseModifiers.Offset(x: 10, y: -5.5))
    }

    func testOffsetUnusable() {
        XCTAssertNil(ModifierParsing.offset(["x": "a"]))
        XCTAssertNil(ModifierParsing.offset(["x": 1, "y": "a"]))
        XCTAssertNil(ModifierParsing.offset([String: Any]()))
        XCTAssertNil(ModifierParsing.offset(["z": 1]))
        XCTAssertNil(ModifierParsing.offset(5))
        XCTAssertNil(ModifierParsing.offset(nil))
    }

    // MARK: - Scale

    func testScaleNumberIsUniformAroundCenter() {
        XCTAssertEqual(ModifierParsing.scale(1.5), BaseModifiers.Scale(x: 1.5, y: 1.5, anchor: .center))
        XCTAssertEqual(ModifierParsing.scale(2), BaseModifiers.Scale(x: 2, y: 2, anchor: .center))
    }

    func testScaleDictionary() {
        XCTAssertEqual(ModifierParsing.scale(["x": 2]), BaseModifiers.Scale(x: 2, y: 1, anchor: .center))
        XCTAssertEqual(ModifierParsing.scale(["x": 2, "y": 0.5, "anchor": "top"]), BaseModifiers.Scale(x: 2, y: 0.5, anchor: .top))
        XCTAssertEqual(ModifierParsing.scale(["anchor": "top"]), BaseModifiers.Scale(x: 1, y: 1, anchor: .top))
        XCTAssertEqual(ModifierParsing.scale(["x": 2, "anchor": "nowhere"]), BaseModifiers.Scale(x: 2, y: 1, anchor: .center))
    }

    func testScaleUnusable() {
        XCTAssertNil(ModifierParsing.scale(["x": "a"]))
        XCTAssertNil(ModifierParsing.scale(["anchor": "nowhere"]))
        XCTAssertNil(ModifierParsing.scale([String: Any]()))
        XCTAssertNil(ModifierParsing.scale("big"))
        XCTAssertNil(ModifierParsing.scale(nil))
    }

    // MARK: - Shadow and border

    func testShadow() {
        XCTAssertEqual(ModifierParsing.shadow(["radius": 5]), BaseModifiers.Shadow(color: nil, radius: 5, x: 0, y: 0))
        XCTAssertEqual(
            ModifierParsing.shadow(["color": "black", "radius": 5, "x": 1, "y": 2.5]),
            BaseModifiers.Shadow(color: "black", radius: 5, x: 1, y: 2.5)
        )
    }

    func testShadowUnusable() {
        XCTAssertNil(ModifierParsing.shadow([String: Any]()))
        XCTAssertNil(ModifierParsing.shadow(["color": 5]))
        XCTAssertNil(ModifierParsing.shadow(["radius": "big"]))
        XCTAssertNil(ModifierParsing.shadow(["radius": 5, "y": "low"]))
        XCTAssertNil(ModifierParsing.shadow(["foo": 1]))
        XCTAssertNil(ModifierParsing.shadow(3))
    }

    func testBorder() {
        XCTAssertEqual(ModifierParsing.border([String: Any]()), BaseModifiers.Border(color: nil, width: 1))
        XCTAssertEqual(ModifierParsing.border(["color": "blue", "width": 2]), BaseModifiers.Border(color: "blue", width: 2))
        XCTAssertEqual(ModifierParsing.border(["foo": 1]), BaseModifiers.Border(color: nil, width: 1))
    }

    func testBorderUnusable() {
        XCTAssertNil(ModifierParsing.border(["color": 5]))
        XCTAssertNil(ModifierParsing.border(["width": "thick"]))
        XCTAssertNil(ModifierParsing.border("1"))
        XCTAssertNil(ModifierParsing.border(nil))
    }

    // MARK: - Clip shape

    func testClipShapeNames() {
        XCTAssertEqual(ModifierParsing.clipShape("rectangle"), .rectangle)
        XCTAssertEqual(ModifierParsing.clipShape("circle"), .circle)
        XCTAssertEqual(ModifierParsing.clipShape("capsule"), .capsule)
        XCTAssertEqual(ModifierParsing.clipShape("ellipse"), .ellipse)
        XCTAssertNil(ModifierParsing.clipShape("star"))
    }

    func testClipShapeRoundedRectangle() {
        XCTAssertEqual(
            ModifierParsing.clipShape(["type": "roundedRectangle", "cornerRadius": 12]),
            .roundedRectangle(radiusX: 12, radiusY: 12)
        )
        XCTAssertEqual(
            ModifierParsing.clipShape(["type": "roundedRectangle", "cornerRadiusX": 12, "cornerRadiusY": 8]),
            .roundedRectangle(radiusX: 12, radiusY: 8)
        )
        // The uniform radius wins over the per-axis pair.
        XCTAssertEqual(
            ModifierParsing.clipShape(["type": "roundedRectangle", "cornerRadius": 4, "cornerRadiusX": 12, "cornerRadiusY": 8]),
            .roundedRectangle(radiusX: 4, radiusY: 4)
        )
    }

    func testClipShapeUnusable() {
        XCTAssertNil(ModifierParsing.clipShape(["type": "roundedRectangle", "cornerRadiusX": 12]))
        XCTAssertNil(ModifierParsing.clipShape(["type": "roundedRectangle"]))
        XCTAssertNil(ModifierParsing.clipShape(["type": "star", "cornerRadius": 12]))
        XCTAssertNil(ModifierParsing.clipShape(["cornerRadius": 12]))
        XCTAssertNil(ModifierParsing.clipShape(5))
        XCTAssertNil(ModifierParsing.clipShape(nil))
    }

    // MARK: - Animation

    func testAnimationShorthand() {
        XCTAssertEqual(ModifierParsing.animation("spring"), BaseModifiers.Animation(curve: .spring))
        XCTAssertNil(ModifierParsing.animation("wobble"))
    }

    func testAnimationDictionary() {
        var expected = BaseModifiers.Animation(curve: .easeIn)
        expected.duration = 0.3
        expected.delay = 0.1
        expected.speed = 2
        expected.watchedValue = "opacity"
        XCTAssertEqual(
            ModifierParsing.animation(["curve": "easeIn", "duration": 0.3, "delay": 0.1, "speed": 2, "value": "opacity"]),
            expected
        )
    }

    func testAnimationOutOfRangeFieldsAreDropped() {
        XCTAssertEqual(
            ModifierParsing.animation(["curve": "linear", "duration": -1, "delay": -1, "speed": 0, "value": 5]),
            BaseModifiers.Animation(curve: .linear)
        )
        // A delay of 0 is allowed; a duration of 0 is not.
        var expected = BaseModifiers.Animation(curve: .linear)
        expected.delay = 0
        XCTAssertEqual(ModifierParsing.animation(["curve": "linear", "duration": 0, "delay": 0]), expected)
    }

    func testAnimationRequiresAValidCurve() {
        XCTAssertNil(ModifierParsing.animation(["curve": "wobble"]))
        XCTAssertNil(ModifierParsing.animation(["duration": 1]))
        XCTAssertNil(ModifierParsing.animation(5))
        XCTAssertNil(ModifierParsing.animation(nil))
    }

    func testAnimationAcceptsEveryCurveName() {
        for curve in BaseModifiers.Animation.Curve.allCases {
            XCTAssertEqual(ModifierParsing.animation(curve.rawValue)?.curve, curve)
        }
    }

    // MARK: - Transition

    func testTransitionShorthands() {
        XCTAssertEqual(ModifierParsing.transition("opacity"), .opacity)
        XCTAssertEqual(ModifierParsing.transition("slide"), .slide)
        XCTAssertEqual(ModifierParsing.transition("identity"), .identity)
        XCTAssertEqual(ModifierParsing.transition("scale"), .scale(factor: nil, anchor: .center))
        XCTAssertEqual(ModifierParsing.transition("move"), .move(edge: .bottom))
        XCTAssertEqual(ModifierParsing.transition("offset"), .offset(x: 0, y: 0))
        XCTAssertEqual(ModifierParsing.transition("asymmetric"), .asymmetric(insertion: .identity, removal: .identity))
        XCTAssertNil(ModifierParsing.transition("spin"))
    }

    func testTransitionDictionaries() {
        XCTAssertEqual(ModifierParsing.transition(["type": "move", "edge": "top"]), .move(edge: .top))
        XCTAssertEqual(ModifierParsing.transition(["type": "move", "edge": "nowhere"]), .move(edge: .bottom))
        XCTAssertEqual(ModifierParsing.transition(["type": "scale", "scale": 0.5, "anchor": "top"]), .scale(factor: 0.5, anchor: .top))
        XCTAssertEqual(ModifierParsing.transition(["type": "offset", "x": 5]), .offset(x: 5, y: 0))
        XCTAssertNil(ModifierParsing.transition(["type": "spin"]))
        XCTAssertNil(ModifierParsing.transition(["edge": "top"]))
    }

    func testTransitionAsymmetricTakesAnyFormForEachSide() {
        XCTAssertEqual(
            ModifierParsing.transition(["type": "asymmetric", "insertion": "opacity", "removal": ["type": "move", "edge": "bottom"]]),
            .asymmetric(insertion: .opacity, removal: .move(edge: .bottom))
        )
        XCTAssertEqual(
            ModifierParsing.transition(["type": "asymmetric", "insertion": "spin"]),
            .asymmetric(insertion: .identity, removal: .identity)
        )
    }

    func testTransitionArraysCombineTheValidEntries() {
        XCTAssertEqual(
            ModifierParsing.transition(["opacity", ["type": "scale"], "spin"] as [Any]),
            .combined([.opacity, .scale(factor: nil, anchor: .center)])
        )
        XCTAssertEqual(ModifierParsing.transition([["opacity"] as [Any]] as [Any]), .combined([.combined([.opacity])]))
        XCTAssertNil(ModifierParsing.transition(["spin"] as [Any]))
        XCTAssertNil(ModifierParsing.transition([Any]()))
        XCTAssertNil(ModifierParsing.transition(5))
        XCTAssertNil(ModifierParsing.transition(nil))
    }

    // MARK: - Keyboard shortcut

    func testKeyNames() {
        XCTAssertTrue(ModifierParsing.isValidKeyName("a"))
        XCTAssertTrue(ModifierParsing.isValidKeyName("1"))
        XCTAssertTrue(ModifierParsing.isValidKeyName("return"))
        XCTAssertTrue(ModifierParsing.isValidKeyName("UpArrow"))
        XCTAssertTrue(ModifierParsing.isValidKeyName("deleteForward"))
        XCTAssertFalse(ModifierParsing.isValidKeyName(""))
        XCTAssertFalse(ModifierParsing.isValidKeyName("ab"))
        XCTAssertFalse(ModifierParsing.isValidKeyName("enter"))
    }

    func testKeyboardShortcutModifiers() {
        XCTAssertEqual(ModifierParsing.keyboardShortcutModifiers(nil), [.command])
        XCTAssertEqual(ModifierParsing.keyboardShortcutModifiers([Any]()), [])
        XCTAssertEqual(ModifierParsing.keyboardShortcutModifiers(["Command", "shift", "shift"] as [Any]), [.command, .shift])
        XCTAssertEqual(ModifierParsing.keyboardShortcutModifiers(["capsLock", "hyper"] as [Any]), [.capslock])
        XCTAssertEqual(ModifierParsing.keyboardShortcutModifiers(["hyper"] as [Any]), [.command])
        XCTAssertEqual(ModifierParsing.keyboardShortcutModifiers("command"), [.command])
        XCTAssertEqual(ModifierParsing.keyboardShortcutModifiers(["command", 5] as [Any]), [.command])
    }

    func testKeyboardShortcut() {
        XCTAssertEqual(ModifierParsing.keyboardShortcut(["key": "a"]), BaseModifiers.KeyboardShortcut(key: "a", modifiers: [.command]))
        XCTAssertEqual(
            ModifierParsing.keyboardShortcut(["key": "return", "modifiers": [Any]()]),
            BaseModifiers.KeyboardShortcut(key: "return", modifiers: [])
        )
        XCTAssertNil(ModifierParsing.keyboardShortcut(["key": "ab"]))
        XCTAssertNil(ModifierParsing.keyboardShortcut(["key": ""]))
        XCTAssertNil(ModifierParsing.keyboardShortcut(["key": 5]))
        XCTAssertNil(ModifierParsing.keyboardShortcut(["modifiers": ["command"]]))
        XCTAssertNil(ModifierParsing.keyboardShortcut("a"))
    }

    // MARK: - Column width

    func testColumnWidth() {
        XCTAssertEqual(ModifierParsing.columnWidth(400), .fixed(400))
        XCTAssertEqual(ModifierParsing.columnWidth(["ideal": 360]), .range(min: nil, ideal: 360, max: nil))
        XCTAssertEqual(ModifierParsing.columnWidth(["ideal": 360, "min": 280, "max": 480]), .range(min: 280, ideal: 360, max: 480))
        XCTAssertEqual(ModifierParsing.columnWidth(["ideal": 360, "min": -1, "max": 0]), .range(min: nil, ideal: 360, max: nil))
    }

    func testColumnWidthUnusable() {
        XCTAssertNil(ModifierParsing.columnWidth(0))
        XCTAssertNil(ModifierParsing.columnWidth(-5))
        XCTAssertNil(ModifierParsing.columnWidth(["ideal": 0]))
        XCTAssertNil(ModifierParsing.columnWidth(["min": 100]))
        XCTAssertNil(ModifierParsing.columnWidth("400"))
        XCTAssertNil(ModifierParsing.columnWidth(nil))
    }
}
