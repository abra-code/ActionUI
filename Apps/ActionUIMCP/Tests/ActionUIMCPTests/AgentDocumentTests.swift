// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

import Testing
import MCPStdio
@testable import ActionUIMCP

private func document(_ value: JSONValue) throws -> AgentDocument {
    try AgentDocument(arguments: ["document": value])
}

@Test func lazyHGridRowsArePropertiesNotChildren() throws {
    // LazyHGrid's "rows" are its row definitions, a property; Grid's "rows" hold child elements.
    let grid: JSONValue = ["type": "LazyHGrid", "id": 1,
                           "properties": ["rows": [["flexible": true], ["minimum": 40]], "spacing": 6],
                           "children": [["type": "Text", "properties": ["text": "One"]]]]
    #expect(throws: Never.self) { try document(grid) }
}

@Test func lazyHGridRowsCanBeSetAsAProperty() {
    // update_window: the same exemption as in a document.
    let rows: JSONValue = [["flexible": true], ["minimum": 40]]
    #expect(AgentDocument.checkProperty(type: "LazyHGrid", id: 1, name: "rows", value: rows).refusal == nil)
    #expect(AgentDocument.checkProperty(type: "Grid", id: 1, name: "rows", value: rows).refusal != nil)
}

@Test func childKeysInsidePropertiesAreStillRefused() {
    let grid: JSONValue = ["type": "Grid", "id": 1, "properties": ["rows": [[["type": "Text", "properties": ["text": "One"]]]]]]
    #expect(throws: (any Error).self) { try document(grid) }
    let stack: JSONValue = ["type": "VStack", "id": 1, "properties": ["children": [["type": "Text", "properties": ["text": "One"]]]]]
    #expect(throws: (any Error).self) { try document(stack) }
}
