// Common/ViewModel.swift
import SwiftUI
import Combine

/*
 ViewModel manages the state for a single view, including its value and validated properties.
*/

/// Context passed through the ViewModel when rendering a template instance.
/// When set, it signals that this view is being built as part of a data-driven template.
/// Views that need template-aware behavior (e.g. Button for action dispatch, containers for
/// child rendering) check `model.templateContext` to adjust their logic.
struct TemplateContext {
    let parentID: Int    // Container element ID — used as viewID in action dispatch
    let rowIndex: Int    // 0-based row index — used as viewPartID in action dispatch
    let row: [String]    // Column data for property substitution in nested children
}

@MainActor
class ViewModel: ObservableObject {
    @Published var value: Any?
    @Published var states: [String: Any]
    var validatedProperties: [String: Any] // Non-published cache
    var elementType: String // View type name (e.g. "TextField", "Slider")
    var templateContext: TemplateContext? // Set when rendering as a template instance

    init() {
        self.value = nil
        self.states = [:]
        self.validatedProperties = [:]
        self.elementType = ""
    }

    // Validate properties for the given element, updating validatedProperties
    func validateProperties(for element: any ActionUIElementBase) {
        let registry = ActionUIRegistry.shared
        self.validatedProperties = registry.getValidatedProperties(element: element, model: self)
    }

    // Validate properties from a dictionary, typically for runtime updates
    func validateProperties(_ properties: [String: Any], elementType: String, logger: any ActionUILogger) {
        let registry = ActionUIRegistry.shared
        self.validatedProperties = registry.validateProperties(forElementType: elementType, properties: properties)
    }
}
