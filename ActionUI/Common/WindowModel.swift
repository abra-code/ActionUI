// Common/WindowModel.swift
import SwiftUI
internal import Combine

@MainActor
class WindowModel: ObservableObject {
    @Published var description: (any ActionUIElement)?
    @Published var viewModels: [Int: ViewModel] = [:]
    let windowUUID: String
    private let logger: any ActionUILogger

    init(windowUUID: String, logger: any ActionUILogger) {
        self.windowUUID = windowUUID
        self.logger = logger
    }

    // Load description from JSON or plist data, populating viewModels
    func loadDescription(from data: Data, format: String) throws {
        if format == "json" {
            let element = try JSONDecoder(logger: logger).decode(ViewElement.self, from: data)
            description = element
            populateViewModels(from: element)
            logger.log("Loaded JSON description for windowUUID: \(windowUUID)", .verbose)
        } else if format == "plist" {
            let element = try PropertyListDecoder(logger: logger).decode(ViewElement.self, from: data)
            description = element
            populateViewModels(from: element)
            logger.log("Loaded plist description for windowUUID: \(windowUUID)", .verbose)
        } else {
            logger.log("Unsupported format: \(format)", .error)
            throw NSError(domain: "WindowModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unsupported format: \(format)"])
        }
    }

    // Load description from dictionary, populating viewModels
    func loadDescription(from dict: [String: Any]) throws {
        let element = try ViewElement(from: dict, logger: logger)
        description = element
        populateViewModels(from: element)
    }

    // Recursively populate viewModels for the element and its subviews
    private func populateViewModels(from element: any ActionUIElement) {
        viewModels[element.id] = ViewModel(properties: element.properties)
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
