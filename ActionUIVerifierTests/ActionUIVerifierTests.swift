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
