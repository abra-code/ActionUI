// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

// Spot checks of the Swift verifier against the bundled schemas and the add-on schemas of this
// checkout. The full comparison with the Python verifier is Parity/validator_parity.py.

import Foundation
import Testing
@testable import ActionUIVerifier

private func makeValidator(platform: String?) throws -> DocumentValidator {
    let primary = try #require(SchemaSet.bundledSchemasDirectory)
    let schemas = try SchemaSet(primary: primary, extra: SchemaSet.discoverAddOnDirectories(schemasDirectory: primary))
    return DocumentValidator(schemas: schemas, targetPlatform: platform)
}

private func issues(_ document: JSONValue, platform: String? = "macos") throws -> [String] {
    try makeValidator(platform: platform).validate(document: document, rootPath: "doc").map(\.description)
}

private func errors(_ document: JSONValue, platform: String? = "macos") throws -> [String] {
    try issues(document, platform: platform).filter { $0.hasPrefix("[ERROR]") }
}

@Test func bundledSchemasLoad() throws {
    let schemas = try SchemaSet.bundled()
    #expect(schemas.knownTypes.contains("Button"))
    #expect(!schemas.knownTypes.contains("View"))
}

@Test func cleanDocumentHasNoIssues() throws {
    let document: JSONValue = ["type": "VStack", "properties": ["spacing": 8, "padding": 16], "children": [
        ["type": "TextField", "id": 1, "properties": ["title": "Name", "prompt": "Ada"]],
        ["type": "QuickLook", "id": 2, "properties": ["filePath": "/tmp/x.pdf"]],
    ]]
    #expect(try issues(document) == [])
}

@Test func typoAndWrongTypeAreReported() throws {
    let document: JSONValue = ["type": "Text", "properties": ["txt": "hi", "font": ["size": "big"]]]
    let found = try issues(document)
    #expect(found.contains("[WARNING] doc: properties.txt: 'txt' is not a known property for Text or View base; possible typo"))
    #expect(found.contains { $0.hasPrefix("[ERROR] doc: properties.font") })
}

@Test func platformRulesDependOnTheTarget() throws {
    let document: JSONValue = ["type": "Text", "properties": ["text": "a", "weight": 1, "text:android": 5]]
    // Deployed to macOS: the android variant is dropped, the android-only property is flagged.
    let mac = try issues(document)
    #expect(mac == ["[WARNING] doc: properties.weight: 'weight': property 'weight' is not available on target platform 'macos' (available on: ['android'])"])
    // Cross-platform authoring: the android variant is checked and has the wrong type.
    let any = try issues(document, platform: nil)
    #expect(any.contains("[ERROR] doc: properties.text:android: expected string, got integer"))
}

@Test func rowBooleansAreStringsOnlyInsideATemplate() throws {
    let toggle: JSONValue = ["type": "Toggle", "properties": [
        "style": "checkbox", "isOn": "$1", "title": "$2", "disabled": "$4", "hidden": "$5", "actionID": "packs.toggled",
    ]]
    // In a template (nested or not) the row supplies isOn, disabled and hidden.
    let list: JSONValue = ["type": "List", "id": 600, "template": ["type": "HStack", "children": [toggle]]]
    #expect(try issues(list) == [])
    // Outside one, the same strings are type errors, and no other type is loosened inside one.
    #expect(try errors(toggle).count == 3)
    let opacity: JSONValue = ["type": "List", "id": 600, "template": ["type": "Text", "properties": ["text": "$1", "opacity": "$2"]]]
    #expect(try errors(opacity) == ["[ERROR] doc: template.properties.opacity: expected number, got string"])
}

@Test func aTemplateToggleNeedsOneColumnForItsState() throws {
    func warnings(isOn: JSONValue?) throws -> [String] {
        var properties: [String: JSONValue] = ["title": "t"]
        properties["isOn"] = isOn
        let list: JSONValue = ["type": "List", "id": 600, "template": ["type": "Toggle", "properties": .object(properties)]]
        return try issues(list)
    }
    #expect(try warnings(isOn: "$1") == [])
    #expect(try warnings(isOn: "$12") == [])
    let displayOnly = "[WARNING] doc: template.properties.isOn: 'isOn' of a Toggle in a template must be a single column "
        + "reference such as \"$1\"; the Toggle cannot keep its state and is display-only"
    for isOn: JSONValue in ["$1 x", "$1$2", "$0", "true", true] {
        #expect(try warnings(isOn: isOn) == [displayOnly])
    }
    #expect(try warnings(isOn: nil) == ["[WARNING] doc: template.properties: Toggle in a template has no 'isOn' column "
        + "reference such as \"$1\"; it cannot keep its state and is display-only"])
}

@Test func tableToggleColumnIsClean() throws {
    let table: JSONValue = ["type": "Table", "id": 600, "properties": [
        "columns": ["", "Pack"],
        "columnTypes": [
            ["viewType": "Toggle", "style": "checkbox", "actionID": "packs.toggled", "disabledColumn": 4],
            ["viewType": "Text"],
        ],
        "widths": [28, 240],
        "actionID": "packs.selection.changed",
    ]]
    #expect(try issues(table) == [])
}

@Test func menuBarDocumentsHaveAnArrayRoot() throws {
    let document: JSONValue = [["type": "CommandMenu", "properties": ["name": "Tools"], "children": []], ["type": "VStack"]]
    let found = try issues(document)
    #expect(found == ["[ERROR] doc[1]: 'VStack' is not valid at the top level of a menu-bar document; expected one of: CommandMenu, CommandGroup"])
}

@Test func dataIsParsedAsTheLoaderParsesIt() throws {
    let validator = try makeValidator(platform: nil)
    // Trailing commas are accepted, as Foundation's parser accepts them.
    let found = try validator.validate(data: Data(#"{"type": "Text", "properties": {"text": "a",},}"#.utf8), rootPath: "doc")
    #expect(found == [])
    #expect(throws: (any Error).self) {
        try validator.validate(data: Data(#"{"type": "Text" // comment"#.utf8), rootPath: "doc")
    }
}

// MARK: Platform variants of type

@Test func deployedTypeIsTheTargetsVariant() throws {
    let document: JSONValue = ["type:macos": "Button", "type:ios": "Text", "properties": ["title": "Go"]]
    #expect(try issues(document, platform: "macos") == [])
    #expect(try issues(document, platform: "ios") == ["[WARNING] doc: properties.title: 'title' is not a known property for Text or View base; possible typo"])
}

@Test func exactSuffixBeatsUmbrellaBeatsPlain() throws {
    let document: JSONValue = ["type": "Text", "type:apple": "Image", "type:macos": "Button", "properties": ["title": "Go"]]
    #expect(try issues(document, platform: "macos") == [])
    #expect(try issues(document, platform: "ios").first?.contains("for Image or View base") == true)
    #expect(try issues(document, platform: "android").first?.contains("for Text or View base") == true)
}

@Test func noTypeForTheTargetIsAnError() throws {
    #expect(try issues(["type:ios": "Text"], platform: "macos") == ["[ERROR] doc: no 'type' variant applies to target platform 'macos'"])
}

@Test func crossPlatformVariantTypesCheckPlainPropertiesAgainstAll() throws {
    #expect(try issues(["type:macos": "Button", "type:ios": "Text", "properties": ["title": "Go"]], platform: nil) == [])
    let found = try issues(["type:ios": "Text", "type:macos": "Button", "properties": ["titel": "Go"]], platform: nil)
    #expect(found == ["[WARNING] doc: properties.titel: 'titel' is not a known property for Button or Text or View base; possible typo"])
}

// MARK: Discriminated items

@Test func nonStringDiscriminatorIsAnUnknownType() throws {
    let found = try issues(["type": "Canvas", "properties": ["operations": [["type": ["fill"]]]]], platform: nil)
    #expect(found.count == 1)
    #expect(found.first?.hasPrefix("[WARNING] doc: properties.operations[0].type: '['fill']' is not a known type; known: [") == true)
}

// MARK: Ids across platform variants of children

@Test func sameIDInPlatformVariantsOfChildrenIsClean() throws {
    let document: JSONValue = ["type": "VStack", "children": [["type": "Text", "id": 6]], "children:ios": [["type": "Text", "id": 6]]]
    #expect(try errors(document, platform: nil) == [])
    #expect(try errors(document, platform: "ios") == [])
}

@Test func idInAChildrenVariantDuplicatingTheRestOfTheTreeIsAnError() throws {
    let document: JSONValue = ["type": "VStack", "overlay": ["type": "Text", "id": 6],
                               "children": [["type": "Text", "id": 7]], "children:ios": [["type": "Text", "id": 6]]]
    // Subview keys are visited in sorted order: children before overlay.
    #expect(try errors(document, platform: nil) == ["[ERROR] doc: overlay: duplicate 'id' 6 — IDs must be unique across the entire view tree"])
}

@Test func duplicateIDInsideOneChildrenVariantIsAnError() throws {
    let document: JSONValue = ["type": "VStack", "children": [["type": "Text", "id": 6]],
                               "children:ios": [["type": "Text", "id": 6], ["type": "Text", "id": 6]]]
    #expect(try errors(document, platform: nil) == ["[ERROR] doc: children:ios[1]: duplicate 'id' 6 — IDs must be unique across the entire view tree"])
}

// MARK: Python-style rendering

@Test func stringsAreRenderedAsPythonReprRendersThem() {
    #expect(pyStringRepr("plain") == "'plain'")
    #expect(pyStringRepr("it's") == "\"it's\"")
    #expect(pyStringRepr("both ' and \"") == #"'both \' and "'"#)
    // A raw newline would split an output line.
    #expect(pyStringRepr("a\nb\tc\u{7}") == #"'a\nb\tc\x07'"#)
    #expect(pyStringRepr("caf\u{e9} zero\u{200b}width") == "'caf\u{e9} zero\\u200bwidth'")
}

// MARK: - $ref expansion and argument patterns (mirrored in Tools/verifier/test_validate_actionui.py)

@Test func referencesAreReplacedAndMergedWithSiblings() throws {
    let schema: JSONValue = [
        "definitions": ["num": ["types": ["number"], "description": "a"], "pair": ["a": ["$ref": "num"]]],
        "ownProperties": ["x": ["$ref": "num", "description": "b"],
                          "p": ["types": ["object"], "properties": ["$ref": "pair", "b": ["$ref": "num"]]]],
    ]
    let expanded = try SchemaSet.expandReferences(schema, schema: "T")
    #expect(expanded.object?["definitions"] == nil)
    #expect(expanded.object?["ownProperties"]?.object?["x"] == ["types": ["number"], "description": "b"])
    #expect(Set(expanded.object?["ownProperties"]?.object?["p"]?.object?["properties"]?.object?.keys ?? [:].keys) == ["a", "b"])
}

@Test func unknownSelfAndMalformedReferencesFail() {
    let schemas: [JSONValue] = [
        ["x": ["$ref": "missing"]],
        ["definitions": ["loop": ["inner": ["$ref": "loop"]]], "x": ["$ref": "loop"]],
        ["x": ["$ref": 3]],
    ]
    for schema in schemas {
        #expect(throws: SchemaReferenceError.self) { try SchemaSet.expandReferences(schema, schema: "T") }
    }
}

private func chart(_ marks: [JSONValue], forEach: Bool = true) -> JSONValue {
    let content: JSONValue = forEach ? [["type": "ForEach", "content": .array(marks)]] : .array(marks)
    return ["type": "Chart", "id": 1, "properties": ["chart": ["columns": ["day", ["name": "n", "type": "number"]], "content": content]]]
}

@Test func everyAcceptedChartFormIsClean() throws {
    let day: JSONValue = ["label": "Day", "value": "$day"]
    let n: JSONValue = ["label": "N", "value": "$n"]
    let marks: [JSONValue] = [
        ["type": "BarMark", "x": day, "yStart": 1, "yEnd": 2],
        ["type": "BarMark", "xStart": n, "xEnd": n, "y": day],
        ["type": "LineMark", "x": day, "y": n, "series": day],
        ["type": "PointMark", "x": 3, "y": n],
        ["type": "RuleMark", "x": 4, "yStart": n, "yEnd": n],
        ["type": "AreaMark", "x": day, "yStart": n, "yEnd": n, "series": day],
        ["type": "RectangleMark", "xStart": n, "xEnd": n, "yStart": n, "yEnd": n],
        ["type": "RectangleMark", "xStart": 1, "yEnd": 2],
        ["type": "SectorMark", "angle": n, "innerRadius": ["ratio": 0.6], "angularInset": 1.5],
        ["type": "Plot", "opacity": 0.5, "content": [["type": "PointMark", "x": day, "y": n]]],
    ]
    #expect(try issues(chart(marks)) == [])
}

@Test func aTopLevelPlotMayHoldAForEachOfPlots() throws {
    let day: JSONValue = ["label": "Day", "value": "$day"]
    let n: JSONValue = ["label": "N", "value": "$n"]
    let plot: JSONValue = ["type": "Plot", "foregroundStyle": "red", "content": [
        ["type": "ForEach", "content": [["type": "Plot", "content": [["type": "LineMark", "x": day, "y": n]]]]],
        ["type": "RuleMark", "y": n],
    ]]
    #expect(try issues(chart([plot], forEach: false)) == [])
}

@Test func forEachDataAndStyleScalesAreChecked() throws {
    let day: JSONValue = ["label": "Day", "value": "$day"]
    let n: JSONValue = ["label": "N", "value": "$n"]
    let good: JSONValue = ["type": "Chart", "id": 1, "properties": ["chart": [
        "content": [["type": "ForEach", "columns": ["day", ["name": "n", "type": "number"]], "data": [["Mon", 3]],
                     "content": [["type": "PointMark", "x": day, "y": n, "symbol": ["by": day]]]]],
        "chartForegroundStyleScale": ["domain": ["A"], "range": ["gradient": ["blue", "red"]]],
        "chartSymbolScale": ["domain": ["Mon"], "range": ["square"]],
        "chartLineStyleScale": ["range": [["lineWidth": 2]]],
        "chartSymbolSizeScale": ["domain": [0, 10], "range": [10, 100]],
    ]]]
    #expect(try issues(good) == [])
    let bad: JSONValue = ["type": "Chart", "id": 1, "properties": ["chart": [
        "content": [["type": "ForEach", "data": [1], "content": []]],
        "chartSymbolScale": ["range": ["hexagon"]],
        "chartSymbolSizeScale": ["range": ["big"]],
    ]]]
    let found = try issues(bad)
    #expect(found.count == 3)
    #expect(found.contains { $0.contains("content[0].data[0]: expected array, got integer") })
    #expect(found.contains { $0.contains("chartSymbolScale.range[0]: 'hexagon' is not a known value") })
    #expect(found.contains { $0.contains("chartSymbolSizeScale.range[0]: expected number, got string") })
}

@Test func axisMarksAreChecked() throws {
    let good: JSONValue = ["type": "Chart", "id": 1, "properties": ["chart": [
        "chartXAxis": [["type": "AxisMarks", "values": ["stride": ["by": "month", "count": 2]], "content": [
            ["type": "AxisGridLine", "stroke": ["lineWidth": 0.5]],
            ["type": "AxisTick", "length": "label"],
            ["type": "AxisValueLabel", "format": ["dateTime": ["month": "abbreviated"]], "font": "caption", "offset": ["y": 2]],
        ]]],
        "chartYAxis": [["type": "AxisMarks", "position": "leading", "values": [0, 50], "format": "percent", "fractionLength": 1]],
    ]]]
    #expect(try issues(good) == [])
    let bad: JSONValue = ["type": "Chart", "id": 1, "properties": ["chart": [
        "chartXAxis": [["type": "AxisMarks", "position": "middle", "content": [["type": "AxisLabel"], ["type": "AxisTick", "centered": "yes"]]]],
        "chartYAxis": "shown",
    ]]]
    let found = try issues(bad)
    #expect(found.count == 4)
    #expect(found.contains { $0.contains("chartXAxis[0].position: 'middle' is not a known value") })
    #expect(found.contains { $0.contains("'AxisLabel' is not a known type") })
    #expect(found.contains { $0.contains("content[1].centered: expected boolean, got string") })
    #expect(found.contains { $0.contains("chartYAxis: 'shown' is not a known value") })
}

@Test func selectionKeysAreChecked() throws {
    let rule: JSONValue = ["type": "RuleMark", "x": ["label": "Selected", "value": "$selection"]]
    let good: JSONValue = ["type": "Chart", "id": 1, "properties": ["selectionActionTiming": "continuous", "valueChangeActionID": "picked", "chart": [
        "columns": ["day", ["name": "n", "type": "number"]],
        "content": [["type": "ForEach", "content": [["type": "BarMark", "x": ["label": "Day", "value": "$day"], "y": ["label": "N", "value": "$n"]]]], rule],
        "chartXSelection": "value", "chartYSelection": "range", "chartAngleSelection": "value",
    ]]]
    #expect(try issues(good) == [])
    let bad: JSONValue = ["type": "Chart", "id": 1, "properties": ["selectionActionTiming": "often", "chart": [
        "chartXSelection": "hover", "chartAngleSelection": "range",
    ]]]
    let found = try issues(bad)
    #expect(found.count == 3)
    #expect(found.contains { $0.contains("selectionActionTiming: 'often' is not a known value") })
    #expect(found.contains { $0.contains("chartXSelection: 'hover' is not a known value") })
    #expect(found.contains { $0.contains("chartAngleSelection: 'range' is not a known value") })
}

@Test func scrollKeysAreChecked() throws {
    let good: JSONValue = ["type": "Chart", "id": 1, "properties": ["chart": [
        "chartScrollableAxes": ["horizontal", "vertical"], "chartXVisibleDomain": ["length": 30],
        "chartScrollPosition": ["initialX": "2026-09-01", "initialY": 5],
    ]]]
    #expect(try issues(good) == [])
    let bad: JSONValue = ["type": "Chart", "id": 1, "properties": ["chart": [
        "chartScrollableAxes": "sideways", "chartXVisibleDomain": ["length": "30"], "chartYVisibleDomain": [:],
        "chartScrollPosition": ["initialX": true],
    ]]]
    let found = try issues(bad)
    #expect(found.count == 4)
    #expect(found.contains { $0.contains("chartScrollableAxes: 'sideways' is not a known value") })
    #expect(found.contains { $0.contains("chartXVisibleDomain.length: expected number, got string") })
    #expect(found.contains { $0.contains("chartYVisibleDomain.length: required key 'length' is missing") })
    #expect(found.contains { $0.contains("chartScrollPosition.initialX: expected string or number, got boolean") })
}

@Test func annotationElementsAreCheckedAsTemplateRows() throws {
    let day: JSONValue = ["label": "Day", "value": "$day"]
    let n: JSONValue = ["label": "N", "value": "$n"]
    let good = chart([["type": "BarMark", "x": day, "y": n, "annotation": [
        "position": "top", "alignment": "leading", "spacing": 2, "overflowResolution": ["x": "fit", "y": ["fit": "plot"]],
        "content": ["type": "VStack", "children": [["type": "Text", "properties": ["text": "$n", "hidden": "$3"]]]],
    ]]])
    #expect(try issues(good) == [])
    // The annotation's ids are its own: id 1 is the chart's too, and is not reported.
    let bad = chart([
        ["type": "BarMark", "x": day, "y": n, "annotation": [
            "position": "above", "overflowResolution": ["x": "clip"],
            "content": ["type": "Text", "id": 1, "properties": ["text": 3, "colour": "red"]],
        ]],
        ["type": "PointMark", "x": day, "y": n, "annotation": ["spacing": 2]],
        ["type": "RuleMark", "y": n, "annotation": ["content": ["type": "Toggle", "properties": ["isOn": "yes"]]]],
    ])
    let found = try issues(bad)
    #expect(found.count == 6)
    #expect(found.contains { $0.contains("annotation.position: 'above' is not a known value") })
    #expect(found.contains { $0.contains("annotation.overflowResolution.x: value type 'string'") })
    #expect(found.contains { $0.contains("annotation.content.properties.text: expected string, got integer") })
    #expect(found.contains { $0.contains("annotation.content.properties.colour: 'colour' is not a known property") })
    #expect(found.contains { $0.contains("annotation.content: required key 'content' is missing") })
    #expect(found.contains { $0.contains("'isOn' of a Toggle in a template must be a single column reference") })
    // A Chart anywhere inside: ActionUI drops the annotation.
    let nested = chart([["type": "BarMark", "x": day, "y": n, "annotation": [
        "content": ["type": "VStack", "children": [["type": "Chart"]]],
    ]]])
    #expect(try issues(nested) == [
        "[ERROR] doc: properties.chart.content[0].content[0].annotation.content: 'Chart' is not allowed inside this element; ActionUI drops the element when it loads",
    ])
}

@Test func aSectorAngleOfAnotherTypeIsReported() throws {
    let found = try issues(chart([["type": "SectorMark", "angle": ["label": "Day", "value": "$day", "type": "date", "unit": "day"]]]))
    #expect(found.count == 2)
    #expect(found.contains { $0.contains("angle.type: 'date' is not a known value; expected one of: ['number', 'integer']") })
    #expect(found.contains { $0.contains("unexpected key 'unit'") })
}

@Test func chartArgumentsThatMatchNoInitializerError() throws {
    let found = try errors(chart([["type": "RuleMark", "x": 4, "y": 2]], forEach: false))
    #expect(found.count == 1)
    #expect(found.first?.contains("RuleMark arguments match no initializer (plottable values [], points ['x', 'y'])") == true)
    #expect(found.first?.contains("accepted: (x point +) yStart + yEnd |") == true)
}

@Test func anArgumentTheMarkLacksStillCounts() throws {
    // The element reads every argument key on every mark, so a PointMark's series drops it.
    let a: JSONValue = ["label": "A", "value": 1]
    let b: JSONValue = ["label": "B", "value": 2]
    let found = try errors(chart([["type": "PointMark", "x": a, "y": b, "series": a], ["type": "LineMark", "x:foo": a, "y": b]]))
    #expect(found.count == 2)
    #expect(found.contains { $0.contains("PointMark arguments match no initializer (plottable values ['series', 'x', 'y'], points [])") })
    #expect(found.contains { $0.contains("LineMark arguments match no initializer (plottable values ['y'], points [])") })
}

@Test func aBooleanIsNotAChartPoint() throws {
    let day: JSONValue = ["label": "Day", "value": "$day"]
    let found = try errors(chart([["type": "PointMark", "x": day, "y": true]]))
    #expect(found == ["[ERROR] doc: properties.chart.content[0].content[0].y: value type 'boolean' (value: True) does not match any allowed form"])
}
