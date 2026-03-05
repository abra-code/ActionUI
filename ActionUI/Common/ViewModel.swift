// Common/ViewModel.swift
import SwiftUI
import Combine

/*
 ViewModel manages the state for a single view, including its value and validated properties.
*/

@MainActor
class ViewModel: ObservableObject {
    @Published var value: Any?
    @Published var states: [String: Any]
    var validatedProperties: [String: Any] // Non-published cache
    var elementType: String // View type name (e.g. "TextField", "Slider")

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
