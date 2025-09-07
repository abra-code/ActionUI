// Common/ViewModel.swift
import SwiftUI
internal import Combine

/*
 ViewModel manages the state for a single view, including its value and validated properties.
*/

@MainActor
class ViewModel: ObservableObject {
    @Published var value: Any?
    @Published var states: [String: Any]
    var validatedProperties: [String: Any] // Non-published cache

    init() {
        self.value = nil
        self.states = [:]
        self.validatedProperties = [:]
    }

    // Validate properties for the given element, updating validatedProperties
    func validateProperties(for element: any ActionUIElement) {
        let registry = ActionUIRegistry.shared
        self.validatedProperties = registry.getValidatedProperties(element: element, model: self)
    }

    // Validate properties from a dictionary, typically for runtime updates
    func validateProperties(_ properties: [String: Any], elementType: String, logger: any ActionUILogger) {
        let registry = ActionUIRegistry.shared
        let baseValidated = View.validateProperties(properties, logger)
        self.validatedProperties = registry.validateProperties(forElementType: elementType, properties: baseValidated)
    }
}
