// Views/PropsValidation/LayoutPropsValidationTests.swift
/*
 Props against validation (see PropsValidationSupport.swift) for HStack, ZStack, LazyVStack,
 LazyHStack, Spacer, Grid, LazyVGrid, LazyHGrid, GroupBox, Section, Color, Rectangle, Circle,
 Ellipse, Capsule and RoundedRectangle. Form, Group, EmptyView and Divider read no properties of
 their own, and HSplitView and VSplitView only the first child's frame, so they have no Props.
*/

import XCTest
@testable import ActionUI

@MainActor
final class HStackPropsValidationTests: PropsValidationTestCase {
    func testMatchesValidation() {
        assertPropsMatchValidation(
            elementType: "HStack", HStack.Props.init,
            casesByKey: [
                "spacing": [10, 10.5, 0, "10", "inf", true],
                "alignment": ["top", "center", "bottom", "firstTextBaseline", "lastTextBaseline", "leading", 5],
            ],
            combinations: [
                ["spacing": 8, "alignment": "bottom"],
                ["spacing": "x", "alignment": "x"],
            ]
        )
    }
}

@MainActor
final class ZStackPropsValidationTests: PropsValidationTestCase {
    func testMatchesValidation() {
        assertPropsMatchValidation(
            elementType: "ZStack", ZStack.Props.init,
            casesByKey: [
                "alignment": ["topLeading", "top", "topTrailing", "leading", "center", "trailing",
                              "bottomLeading", "bottom", "bottomTrailing", "middle", 5],
            ]
        )
    }
}

@MainActor
final class LazyVStackPropsValidationTests: PropsValidationTestCase {
    func testMatchesValidation() {
        assertPropsMatchValidation(
            elementType: "LazyVStack", LazyVStack.Props.init,
            casesByKey: [
                "spacing": [10, 10.5, 0, "10", "inf", true],
                "alignment": ["leading", "center", "trailing", "top", 5],
            ],
            combinations: [
                ["spacing": 8, "alignment": "trailing"],
                ["spacing": "x", "alignment": "x"],
            ]
        )
    }
}

@MainActor
final class LazyHStackPropsValidationTests: PropsValidationTestCase {
    func testMatchesValidation() {
        assertPropsMatchValidation(
            elementType: "LazyHStack", LazyHStack.Props.init,
            casesByKey: [
                "spacing": [10, 10.5, 0, "10", "inf", true],
                "alignment": ["top", "center", "bottom", "leading", 5],
            ],
            combinations: [
                ["spacing": 8, "alignment": "bottom"],
                ["spacing": "x", "alignment": "x"],
            ]
        )
    }
}

@MainActor
final class SpacerPropsValidationTests: PropsValidationTestCase {
    func testMatchesValidation() {
        assertPropsMatchValidation(
            elementType: "Spacer", Spacer.Props.init,
            casesByKey: [
                "minLength": [20, 20.5, 0, "20", "inf", true],
            ]
        )
    }
}

@MainActor
final class GridPropsValidationTests: PropsValidationTestCase {
    func testMatchesValidation() {
        assertPropsMatchValidation(
            elementType: "Grid", Grid.Props.init,
            casesByKey: [
                "alignment": ["topLeading", "top", "topTrailing", "leading", "center", "trailing",
                              "bottomLeading", "bottom", "bottomTrailing", "middle", 5],
                "horizontalSpacing": [8, 8.5, 0, "8", "inf", true],
                "verticalSpacing": [8, 8.5, 0, "8", "inf", true],
            ],
            combinations: [
                ["alignment": "top", "horizontalSpacing": 8, "verticalSpacing": 4],
                ["alignment": "x", "horizontalSpacing": "x", "verticalSpacing": "x"],
            ]
        )
    }
}

@MainActor
final class LazyVGridPropsValidationTests: PropsValidationTestCase {
    func testMatchesValidation() {
        assertPropsMatchValidation(
            elementType: "LazyVGrid", LazyVGrid.Props.init,
            casesByKey: [
                "columns": [
                    [["minimum": 80]] as [Any],
                    [["minimum": 40.5]] as [Any],
                    [["minimum": "inf"]] as [Any],
                    [["flexible": true]] as [Any],
                    [["flexible": false]] as [Any],
                    [["flexible": false], ["minimum": "x"], [String: Any]()] as [Any],
                    [["minimum": 40, "flexible": true]] as [Any],
                    [["minimum": "x", "flexible": true]] as [Any],
                    [["minimum": "x"]] as [Any],
                    [["flexible": 1]] as [Any],
                    [[String: Any]()] as [Any],
                    [["flexible": false], ["minimum": 50], [String: Any](), ["flexible": true]] as [Any],
                    [["minimum": 80], 3] as [Any],
                    [Any](),
                    [1, 2] as [Any],
                    "three", 3,
                ],
                "spacing": [10, 10.5, 0, "10", "inf", true],
                "alignment": ["leading", "center", "trailing", "top", 5],
            ],
            combinations: [
                ["columns": [["minimum": 80], ["flexible": true]] as [Any], "spacing": 12, "alignment": "leading"],
                ["columns": [["flexible": false]] as [Any], "spacing": "x", "alignment": "x"],
            ]
        )
    }
}

@MainActor
final class LazyHGridPropsValidationTests: PropsValidationTestCase {
    func testMatchesValidation() {
        assertPropsMatchValidation(
            elementType: "LazyHGrid", LazyHGrid.Props.init,
            casesByKey: [
                "rows": [
                    [["minimum": 80]] as [Any],
                    [["minimum": 40.5]] as [Any],
                    [["minimum": "inf"]] as [Any],
                    [["flexible": true]] as [Any],
                    [["flexible": false]] as [Any],
                    [["flexible": false], ["minimum": "x"], [String: Any]()] as [Any],
                    [["minimum": 40, "flexible": true]] as [Any],
                    [["minimum": "x", "flexible": true]] as [Any],
                    [["minimum": "x"]] as [Any],
                    [["flexible": 1]] as [Any],
                    [[String: Any]()] as [Any],
                    [["flexible": false], ["minimum": 50], [String: Any](), ["flexible": true]] as [Any],
                    [["minimum": 80], 3] as [Any],
                    [Any](),
                    [1, 2] as [Any],
                    "three", 3,
                ],
                "spacing": [10, 10.5, 0, "10", "inf", true],
                "alignment": ["top", "center", "bottom", "leading", 5],
            ],
            combinations: [
                ["rows": [["minimum": 80], ["flexible": true]] as [Any], "spacing": 12, "alignment": "top"],
                ["rows": [["flexible": false]] as [Any], "spacing": "x", "alignment": "x"],
            ]
        )
    }
}

@MainActor
final class GroupBoxPropsValidationTests: PropsValidationTestCase {
    func testMatchesValidation() {
        assertPropsMatchValidation(
            elementType: "GroupBox", GroupBox.Props.init,
            casesByKey: [
                "title": ["Options", "", 5, true],
            ]
        )
    }
}

@MainActor
final class SectionPropsValidationTests: PropsValidationTestCase {
    func testMatchesValidation() {
        assertPropsMatchValidation(
            elementType: "Section", Section.Props.init,
            casesByKey: [
                "header": ["General", "", 5, true],
            ]
        )
    }
}

@MainActor
final class ColorPropsValidationTests: PropsValidationTestCase {
    func testMatchesValidation() {
        assertPropsMatchValidation(
            elementType: "Color", Color.Props.init,
            casesByKey: [
                "color": ["red", "#FF0000", "", 5, true, ["r": 1] as [String: Any]],
            ]
        )
    }
}

@MainActor
final class RectanglePropsValidationTests: PropsValidationTestCase {
    func testMatchesValidation() {
        assertPropsMatchValidation(
            elementType: "Rectangle", Rectangle.Props.init,
            casesByKey: [
                "fill": ["blue", "", 5, true],
                "stroke": ["red", "", 5, true],
                "strokeLineWidth": [2, 2.5, 0, "2", "inf", true],
            ],
            combinations: [
                ["fill": "blue", "stroke": "red", "strokeLineWidth": 3],
                ["fill": 5, "stroke": "red", "strokeLineWidth": "x"],
            ]
        )
    }
}

@MainActor
final class CirclePropsValidationTests: PropsValidationTestCase {
    func testMatchesValidation() {
        assertPropsMatchValidation(
            elementType: "Circle", Circle.Props.init,
            casesByKey: [
                "fill": ["blue", "", 5, true],
                "stroke": ["red", "", 5, true],
                "strokeLineWidth": [2, 2.5, 0, "2", "inf", true],
            ],
            combinations: [
                ["fill": "blue", "stroke": "red", "strokeLineWidth": 3],
                ["fill": 5, "stroke": "red", "strokeLineWidth": "x"],
            ]
        )
    }
}

@MainActor
final class EllipsePropsValidationTests: PropsValidationTestCase {
    func testMatchesValidation() {
        assertPropsMatchValidation(
            elementType: "Ellipse", Ellipse.Props.init,
            casesByKey: [
                "fill": ["blue", "", 5, true],
                "stroke": ["red", "", 5, true],
                "strokeLineWidth": [2, 2.5, 0, "2", "inf", true],
            ],
            combinations: [
                ["fill": "blue", "stroke": "red", "strokeLineWidth": 3],
                ["fill": 5, "stroke": "red", "strokeLineWidth": "x"],
            ]
        )
    }
}

@MainActor
final class CapsulePropsValidationTests: PropsValidationTestCase {
    func testMatchesValidation() {
        assertPropsMatchValidation(
            elementType: "Capsule", Capsule.Props.init,
            casesByKey: [
                "style": ["circular", "continuous", "round", 5],
                "fill": ["blue", "", 5, true],
                "stroke": ["red", "", 5, true],
                "strokeLineWidth": [2, 2.5, 0, "2", "inf", true],
            ],
            combinations: [
                ["style": "continuous", "fill": "blue", "stroke": "red", "strokeLineWidth": 3],
                ["style": "x", "fill": 5, "stroke": "red", "strokeLineWidth": "x"],
            ]
        )
    }
}

@MainActor
final class RoundedRectanglePropsValidationTests: PropsValidationTestCase {
    func testMatchesValidation() {
        assertPropsMatchValidation(
            elementType: "RoundedRectangle", RoundedRectangle.Props.init,
            casesByKey: [
                "cornerRadius": [8, 8.5, 0, -4, "8", "inf", true],
                "cornerStyle": ["circular", "continuous", "round", 5],
                "fill": ["blue", "", 5, true],
                "stroke": ["red", "", 5, true],
                "strokeLineWidth": [2, 2.5, 0, "2", "inf", true],
            ],
            combinations: [
                ["cornerRadius": 12, "cornerStyle": "continuous", "fill": "blue", "stroke": "red", "strokeLineWidth": 3],
                ["cornerRadius": "x", "cornerStyle": "x", "fill": 5, "stroke": "red", "strokeLineWidth": "x"],
            ]
        )
    }
}
