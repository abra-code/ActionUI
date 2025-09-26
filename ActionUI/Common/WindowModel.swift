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
            self.viewModels = populateViewModels(from: element) // Update self.viewModels
            logger.log("Loaded JSON description for windowUUID: \(windowUUID), element id: \(element.id)", .verbose)
            return element
        } else if format == "plist" {
            let element = try PropertyListDecoder(logger: logger).decode(ViewElement.self, from: data)
            self.element = element
            self.viewModels = populateViewModels(from: element) // Update self.viewModels
            logger.log("Loaded plist description for windowUUID: \(windowUUID), element id: \(element.id)", .verbose)
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
        self.viewModels = populateViewModels(from: element) // Update self.viewModels
        return element
    }

    // Load a sub-view from JSON or plist data without overwriting the root element
    func loadSubViewDescription(from data: Data, format: String) throws -> ViewElement {
        let subElement: ViewElement
        if format == "json" {
            subElement = try JSONDecoder(logger: logger).decode(ViewElement.self, from: data)
        } else if format == "plist" {
            subElement = try PropertyListDecoder(logger: logger).decode(ViewElement.self, from: data)
        } else {
            logger.log("Unsupported format: \(format)", .error)
            throw NSError(domain: "WindowModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unsupported format: \(format)"])
        }
        
        let subViewModels = populateViewModels(from: subElement) // Get populated dictionary

        // Merge subViewModels into main viewModels, ensuring no ID conflicts
        for (id, viewModel) in subViewModels {
            if self.viewModels[id] == nil {
                self.viewModels[id] = viewModel
            } else {
                logger.log("ID conflict for sub-view \(id); skipping merge", .error)
            }
        }
        
        logger.log("Loaded sub-view with element id: \(subElement.id)", .debug)
        return subElement
    }

    // Recursively populate viewModels for the element and its subviews, returning the populated dictionary
    internal func populateViewModels(from element: any ActionUIElement) -> [Int: ViewModel] {
        var targetViewModels: [Int: ViewModel] = [:]
        
        let viewModel = ViewModel()
        // Validate properties and set in ViewModel
        viewModel.validateProperties(for: element)
        // Fetch initial value from properties early if the element supports it
        viewModel.value = ActionUIRegistry.shared.getInitialValue(forElementType: element.type, model: viewModel)
        targetViewModels[element.id] = viewModel
        
        if let subviews = element.subviews {
            if let children = subviews["children"] as? [any ActionUIElement] {
                for child in children {
                    let childViewModels = populateViewModels(from: child)
                    for (id, viewModel) in childViewModels {
                        targetViewModels[id] = viewModel
                    }
                }
            }
            if let rows = subviews["rows"] as? [[any ActionUIElement]] {
                for row in rows.flatMap({ $0 }) {
                    let rowViewModels = populateViewModels(from: row)
                    for (id, viewModel) in rowViewModels {
                        targetViewModels[id] = viewModel
                    }
                }
            }
            for key in ["content", "destination", "sidebar", "detail"] {
                if let child = subviews[key] as? any ActionUIElement {
                    let childViewModels = populateViewModels(from: child)
                    for (id, viewModel) in childViewModels {
                        targetViewModels[id] = viewModel
                    }
                }
            }
            if let commands = subviews["commands"] as? [any ActionUIElement] {
                for child in commands {
                    let childViewModels = populateViewModels(from: child)
                    for (id, viewModel) in childViewModels {
                        targetViewModels[id] = viewModel
                    }
                }
            }
        }
        
        return targetViewModels
    }
}
