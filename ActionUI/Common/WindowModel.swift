// Common/WindowModel.swift
import SwiftUI
import Combine

/*
 WindowModel manages the state for a single window, including its root element and associated view models.
*/

@MainActor
class WindowModel: ObservableObject {
    @Published var element: (any ActionUIElementBase)?
    @Published var viewModels: [Int: ViewModel] = [:]
    /// Maps a LoadableView's element ID to set of child view IDs it loaded
    var loadedSubViewIDs: [Int: Set<Int>] = [:]
    /// Active window-level modal (sheet or fullScreenCover). Set by ActionUIModel.presentModal.
    @Published var windowModal: WindowModal? = nil
    /// Active window-level dialog (alert or confirmationDialog). Set by ActionUIModel.presentAlert / presentConfirmationDialog.
    @Published var windowDialog: WindowDialog? = nil
    let windowUUID: String
    private let logger: any ActionUILogger

    init(windowUUID: String, logger: any ActionUILogger) {
        self.windowUUID = windowUUID
        self.logger = logger
    }

    // Load description from JSON or plist data, populating viewModels
    func loadDescription(from data: Data, format: String) throws -> ActionUIElement {
        if format == "json" {
            let element = try JSONDecoder(logger: logger).decode(ActionUIElement.self, from: data)
            self.element = element
            self.viewModels = populateViewModels(from: element) // Update self.viewModels
            self.loadedSubViewIDs = [:]
            logger.log("Loaded JSON description for windowUUID: \(windowUUID), element id: \(element.id)", .verbose)
            return element
        } else if format == "plist" {
            let element = try PropertyListDecoder(logger: logger).decode(ActionUIElement.self, from: data)
            self.element = element
            self.viewModels = populateViewModels(from: element) // Update self.viewModels
            self.loadedSubViewIDs = [:]
            logger.log("Loaded plist description for windowUUID: \(windowUUID), element id: \(element.id)", .verbose)
            return element
        } else {
            logger.log("Unsupported format: \(format)", .error)
            throw NSError(domain: "WindowModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unsupported format: \(format)"])
        }
    }

    // Load description from dictionary, populating viewModels
    func loadDescription(from dict: [String: Any]) throws -> ActionUIElement {
        let element = try ActionUIElement(from: dict, logger: logger)
        self.element = element
        self.viewModels = populateViewModels(from: element) // Update self.viewModels
        self.loadedSubViewIDs = [:]
        return element
    }

    // Load a sub-view from JSON or plist data without overwriting the root element.
    // When parentID != 0, removes old child models owned by that parent before loading,
    // enabling dynamic content swapping without ID conflicts.
    func loadSubViewDescription(from data: Data, format: String, parentID: Int = 0) throws -> ActionUIElement {
        // Remove old child models if replacing an existing parent's content
        if parentID != 0 {
            let oldIDs = collectAndRemoveSubViewIDs(for: parentID)
            if !oldIDs.isEmpty {
                var updated = self.viewModels
                for id in oldIDs { updated.removeValue(forKey: id) }
                self.viewModels = updated
                logger.log("Removed \(oldIDs.count) old child models for parent \(parentID)", .debug)
            }
        }

        // Decode new element
        let subElement: ActionUIElement
        if format == "json" {
            subElement = try JSONDecoder(logger: logger).decode(ActionUIElement.self, from: data)
        } else if format == "plist" {
            subElement = try PropertyListDecoder(logger: logger).decode(ActionUIElement.self, from: data)
        } else {
            logger.log("Unsupported format: \(format)", .error)
            throw NSError(domain: "WindowModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unsupported format: \(format)"])
        }

        // Populate new ViewModels and record ownership if tracking a parent
        let subViewModels = populateViewModels(from: subElement)
        if parentID != 0 {
            loadedSubViewIDs[parentID] = Set(subViewModels.keys)
        }

        // Merge subViewModels into main viewModels, ensuring no ID conflicts.
        // Build the merged dictionary first, then assign once to fire a single @Published notification.
        var merged = self.viewModels
        for (id, viewModel) in subViewModels {
            if merged[id] == nil {
                merged[id] = viewModel
            } else {
                logger.log("ID conflict for sub-view \(id); skipping merge", .error)
            }
        }
        self.viewModels = merged

        logger.log("Loaded sub-view with element id: \(subElement.id)" + (parentID != 0 ? " for parent \(parentID)" : ""), .debug)
        return subElement
    }

    /// Recursively collect all sub-view IDs owned by parentID (and their nested children)
    private func collectAndRemoveSubViewIDs(for parentID: Int) -> Set<Int> {
        guard let directChildren = loadedSubViewIDs.removeValue(forKey: parentID) else { return [] }
        var allIDs = directChildren
        for childID in directChildren {
            allIDs.formUnion(collectAndRemoveSubViewIDs(for: childID))
        }
        return allIDs
    }

    // Recursively populate viewModels for the element and its subviews, returning the populated dictionary
    internal func populateViewModels(from element: any ActionUIElementBase) -> [Int: ViewModel] {
        var targetViewModels: [Int: ViewModel] = [:]
        
        let viewModel = ViewModel()
        viewModel.elementType = element.type
        // Validate properties and set in ViewModel
        viewModel.validateProperties(for: element)
        // Fetch initial value from properties early if the element supports it
        viewModel.value = ActionUIRegistry.shared.getInitialValue(forElementType: element.type, model: viewModel)
        // Fetch initial states from properties early if the element supports it
        viewModel.states = ActionUIRegistry.shared.getInitialStates(forElementType: element.type, model: viewModel)
        targetViewModels[element.id] = viewModel
        
        // If this element has a template, initialize states["content"] for data-driven rendering.
        // Do NOT recurse into template children — they are stateless blueprints, not live views.
        if element.subviews?["template"] != nil {
            if viewModel.states["content"] == nil {
                viewModel.states["content"] = [[String]]()
            }
        }

        if let subviews = element.subviews {
            for key in ["children", "destinations"] {
                if let children = subviews[key] as? [any ActionUIElementBase] {
                    for child in children {
                        let childViewModels = populateViewModels(from: child)
                        for (id, viewModel) in childViewModels {
                            targetViewModels[id] = viewModel
                        }
                    }
                }
            }

            if let rows = subviews["rows"] as? [[any ActionUIElementBase]] {
                for row in rows.flatMap({ $0 }) {
                    let rowViewModels = populateViewModels(from: row)
                    for (id, viewModel) in rowViewModels {
                        targetViewModels[id] = viewModel
                    }
                }
            }
            // Note: "template" is intentionally excluded — it is a stateless blueprint.
            for key in ["content", "destination", "sidebar", "detail", "label", "popover", "sheet", "fullScreenCover"] {
                if let child = subviews[key] as? any ActionUIElementBase {
                    let childViewModels = populateViewModels(from: child)
                    for (id, viewModel) in childViewModels {
                        targetViewModels[id] = viewModel
                    }
                }
            }
            if let commands = subviews["commands"] as? [any ActionUIElementBase] {
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

    // Decode JSON/plist for a window-level modal without touching the root element or loadedSubViewIDs.
    // Merges the new ViewModels into the window's pool; IDs are tracked externally by WindowModal.loadedViewIDs
    // so ActionUIModel.dismissModal can clean them up when the modal is dismissed.
    func loadModalDescription(from data: Data, format: String) throws -> ActionUIElement {
        let element: ActionUIElement
        if format == "json" {
            element = try JSONDecoder(logger: logger).decode(ActionUIElement.self, from: data)
        } else if format == "plist" {
            element = try PropertyListDecoder(logger: logger).decode(ActionUIElement.self, from: data)
        } else {
            logger.log("Unsupported format for modal: \(format)", .error)
            throw NSError(domain: "WindowModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unsupported format: \(format)"])
        }
        let newViewModels = populateViewModels(from: element)
        var merged = self.viewModels
        for (id, vm) in newViewModels {
            if merged[id] == nil {
                merged[id] = vm
            } else {
                logger.log("Modal ID conflict for element \(id); skipping merge", .error)
            }
        }
        self.viewModels = merged
        logger.log("Loaded modal description, element id: \(element.id)", .debug)
        return element
    }
}
