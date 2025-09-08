// Common/WindowModel.swift
import SwiftUI
internal import Combine

/*
 WindowModel manages the state for a single window, including its root element and associated view models.
*/

@MainActor
class WindowModel: ObservableObject {
    @Published var element: (any ActionUIElement)?
    @Published var viewModels: [Int: ViewModel] = [:]
    @Published var isNetworkLoading: Bool = false // Added for network loading state
    let windowUUID: String
    private let logger: any ActionUILogger

    init(windowUUID: String, logger: any ActionUILogger) {
        self.windowUUID = windowUUID
        self.logger = logger
    }

    // Load description from JSON or plist data, populating viewModels
    func loadDescription(from data: Data, format: String) throws -> ViewElement {
        if format == "json" {
            let element = try JSONDecoder(logger: logger).decode(ViewElement.self, from: data)
            self.element = element
            populateViewModels(from: element)
            logger.log("Loaded JSON description for windowUUID: \(windowUUID)", .verbose)
            return element
        } else if format == "plist" {
            let element = try PropertyListDecoder(logger: logger).decode(ViewElement.self, from: data)
            self.element = element
            populateViewModels(from: element)
            logger.log("Loaded plist description for windowUUID: \(windowUUID)", .verbose)
            return element
        } else {
            logger.log("Unsupported format: \(format)", .error)
            throw NSError(domain: "WindowModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unsupported format: \(format)"])
        }
    }

    // Load description from dictionary, populating viewModels
    func loadDescription(from dict: [String: Any]) throws -> ViewElement {
        let element = try ViewElement(from: dict, logger: logger)
        self.element = element
        populateViewModels(from: element)
        return element
    }

    // Recursively populate viewModels for the element and its subviews
    internal func populateViewModels(from element: any ActionUIElement) {
        let viewModel = ViewModel()
        // Validate properties and set in ViewModel
        viewModel.validateProperties(for: element)
        viewModels[element.id] = viewModel
        if let subviews = element.subviews {
            if let children = subviews["children"] as? [any ActionUIElement] {
                children.forEach { populateViewModels(from: $0) }
            }
            if let rows = subviews["rows"] as? [[any ActionUIElement]] {
                rows.flatMap { $0 }.forEach { populateViewModels(from: $0) }
            }
            for key in ["content", "destination", "sidebar", "detail"] {
                if let child = subviews[key] as? any ActionUIElement {
                    populateViewModels(from: child)
                }
            }
        }
    }
}
