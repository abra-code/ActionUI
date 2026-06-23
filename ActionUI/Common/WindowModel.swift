// Common/WindowModel.swift
import SwiftUI
import Combine

/*
 WindowModel manages the state for a single window, including its root element and associated view models.
*/

@MainActor
class WindowModel: ObservableObject {
    var element: (any ActionUIElementBase)?
    var viewModels: [Int: ViewModel] = [:]
    /// Maps a LoadableView's element ID to set of child view IDs it loaded
    var loadedSubViewIDs: [Int: Set<Int>] = [:]
    /// Maps a parentID to the set of view IDs inserted at runtime via insertElement / insertRow.
    /// Used so the parent's bookkeeping survives subsequent removes and so a parent's removal
    /// can cascade-clean its dynamic descendants.
    var dynamicallyInsertedIDs: [Int: Set<Int>] = [:]
    /// Active window-level modal (sheet or fullScreenCover). Set by ActionUIModel.presentModal.
    @Published var windowModal: WindowModal? = nil
    /// Active window-level dialog (alert or confirmationDialog). Set by ActionUIModel.presentAlert / presentConfirmationDialog.
    @Published var windowDialog: WindowDialog? = nil
    /// Currently visible window-level toast. Set by ActionUIModel.presentToast; cleared by dismissToast.
    @Published var windowToast: WindowToast? = nil
    /// Pending toasts waiting for the current one to dismiss (coalesces rapid posts; shown one at a time).
    var toastQueue: [WindowToast] = []
    let windowUUID: String
    private let logger: any ActionUILogger

    init(windowUUID: String, logger: any ActionUILogger) {
        self.windowUUID = windowUUID
        self.logger = logger
    }

    // Load description from JSON or plist data, populating viewModels
    func loadDescription(from data: Data, format: String) throws -> ActionUIElement {
        let filtered = try applyPlatformFilter(data: data, format: format)
        if format == "json" {
            let element = try JSONDecoder(logger: logger).decode(ActionUIElement.self, from: filtered)
            self.element = element
            self.viewModels = populateViewModels(from: element)
            self.loadedSubViewIDs = [:]
            logger.log("Loaded JSON description for windowUUID: \(windowUUID), element id: \(element.id)", .verbose)
            return element
        } else if format == "plist" {
            let element = try PropertyListDecoder(logger: logger).decode(ActionUIElement.self, from: filtered)
            self.element = element
            self.viewModels = populateViewModels(from: element)
            self.loadedSubViewIDs = [:]
            logger.log("Loaded plist description for windowUUID: \(windowUUID), element id: \(element.id)", .verbose)
            return element
        } else {
            logger.log("Unsupported format: \(format)", .error)
            throw NSError(domain: "WindowModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unsupported format: \(format)"])
        }
    }

    // Applies PlatformFilter to raw JSON or plist data: parse -> filter -> re-serialize.
    // Returns the filtered Data, ready for the typed decoder. Unsupported formats
    // pass through unchanged (caller will fail on its own).
    private func applyPlatformFilter(data: Data, format: String) throws -> Data {
        let filter = PlatformFilter(active: PlatformFilter.runtimeActiveSet, logger: logger)
        switch format {
        case "json":
            let parsed = try JSONSerialization.jsonObject(with: data, options: [])
            let filtered = filter.filter(parsed)
            return try JSONSerialization.data(withJSONObject: filtered, options: [])
        case "plist":
            var plistFormat: PropertyListSerialization.PropertyListFormat = .xml
            let parsed = try PropertyListSerialization.propertyList(from: data, options: [], format: &plistFormat)
            let filtered = filter.filter(parsed)
            return try PropertyListSerialization.data(fromPropertyList: filtered, format: plistFormat, options: 0)
        default:
            return data
        }
    }

    // Load description from dictionary, populating viewModels
    func loadDescription(from dict: [String: Any]) throws -> ActionUIElement {
        let filter = PlatformFilter(active: PlatformFilter.runtimeActiveSet, logger: logger)
        let filtered = filter.filter(dict) as? [String: Any] ?? dict
        let element = try ActionUIElement(from: filtered, logger: logger)
        self.element = element
        self.viewModels = populateViewModels(from: element)
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
        let filtered = try applyPlatformFilter(data: data, format: format)
        let subElement: ActionUIElement
        if format == "json" {
            subElement = try JSONDecoder(logger: logger).decode(ActionUIElement.self, from: filtered)
        } else if format == "plist" {
            subElement = try PropertyListDecoder(logger: logger).decode(ActionUIElement.self, from: filtered)
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
        // Build the merged dictionary first, then assign once.
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

        // Recurse over every named container (children/destinations/toolbar/commands,
        // rows, and all single-child keys incl. overlay/background) via the single
        // shared traversal. "template" is excluded by design (stateless blueprint).
        // ToolbarItem/ToolbarItemGroup content & children are handled automatically
        // because childElements walks them too.
        for child in element.childElements {
            let childViewModels = populateViewModels(from: child)
            for (id, childModel) in childViewModels {
                targetViewModels[id] = childModel
            }
        }

        return targetViewModels
    }

    // Decode JSON/plist for a window-level modal without touching the root element or loadedSubViewIDs.
    // Merges the new ViewModels into the window's pool; IDs are tracked externally by WindowModal.loadedViewIDs
    // so ActionUIModel.dismissModal can clean them up when the modal is dismissed.
    func loadModalDescription(from data: Data, format: String) throws -> ActionUIElement {
        let filtered = try applyPlatformFilter(data: data, format: format)
        let element: ActionUIElement
        if format == "json" {
            element = try JSONDecoder(logger: logger).decode(ActionUIElement.self, from: filtered)
        } else if format == "plist" {
            element = try PropertyListDecoder(logger: logger).decode(ActionUIElement.self, from: filtered)
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

    // MARK: - Runtime structural mutations (insertElement / insertRow / removeElement)
    //
    // These mutate `viewModels[parentID].dynamicSubviews[container]` so that the next render of
    // the parent (triggered via objectWillChange.send) sees a merged element with the new
    // children list. The static element graph is left untouched — the merge happens in
    // ActionUIRegistry.buildView via applyDynamicSubviews(to:from:).

    /// Runs a structural mutation, wrapping it in `withAnimation` when the inserted/removed
    /// `element` declares a `transition` so SwiftUI plays that element's `.transition()`. Without a
    /// declared transition the change applies instantly (the gap-#21 default - no behavior change).
    private func runStructuralMutation(animatedFor element: any ActionUIElementBase, _ body: () -> Void) {
        if element.properties["transition"] != nil {
            withAnimation { body() }
        } else {
            body()
        }
    }

    /// Insert an element into a flat container. Returns the inserted element's id.
    func insertElement(_ newElement: ActionUIElement, parentID: Int, container: String, position: InsertPosition) throws -> Int {
        guard let parent = locateElement(byID: parentID) else {
            throw InsertError.parentNotFound(parentID: parentID)
        }
        guard let parentModel = self.viewModels[parentID] else {
            throw InsertError.parentNotFound(parentID: parentID)
        }
        var current = effectiveFlatContainer(for: parent, model: parentModel, container: container)
        let index = try resolveFlatIndex(in: current, position: position, container: container)

        let newIDs = collectAllElementIDs(in: newElement)
        let conflicts = newIDs.intersection(Set(self.viewModels.keys))
        if !conflicts.isEmpty {
            throw InsertError.idConflict(ids: Array(conflicts).sorted())
        }

        current.insert(newElement, at: index)
        // The inserted view's `.transition()` plays only inside an animated transaction, so a
        // transition-bearing element animates its entrance; without one the insert is instant.
        runStructuralMutation(animatedFor: newElement) {
            self.setDynamicContainer(on: parentModel, container: container, value: current)

            let newVMs = self.populateViewModels(from: newElement)
            var merged = self.viewModels
            for (id, vm) in newVMs { merged[id] = vm }
            self.viewModels = merged

            self.dynamicallyInsertedIDs[parentID, default: []].formUnion(Set(newVMs.keys))
            parentModel.objectWillChange.send()
        }
        logger.log("Inserted element id \(newElement.id) into parent \(parentID).\(container) at index \(index)", .debug)
        return newElement.id
    }

    /// Insert a row of cells into a `rows` container. Returns the cell ids in order.
    func insertRow(_ cells: [ActionUIElement], parentID: Int, container: String, position: InsertPosition) throws -> [Int] {
        switch position {
        case .before, .after:
            throw InsertError.unsupportedPositionForRowContainer(container: container)
        default: break
        }
        guard let parent = locateElement(byID: parentID) else {
            throw InsertError.parentNotFound(parentID: parentID)
        }
        guard let parentModel = self.viewModels[parentID] else {
            throw InsertError.parentNotFound(parentID: parentID)
        }
        var current = effectiveRowsContainer(for: parent, model: parentModel, container: container)
        let index = try resolveRowIndex(in: current, position: position)

        var newIDs: Set<Int> = []
        for cell in cells { newIDs.formUnion(collectAllElementIDs(in: cell)) }
        let conflicts = newIDs.intersection(Set(self.viewModels.keys))
        if !conflicts.isEmpty {
            throw InsertError.idConflict(ids: Array(conflicts).sorted())
        }

        current.insert(cells, at: index)
        setDynamicContainer(on: parentModel, container: container, value: current)

        var merged = self.viewModels
        var insertedIDs: Set<Int> = []
        for cell in cells {
            let cellVMs = populateViewModels(from: cell)
            insertedIDs.formUnion(cellVMs.keys)
            for (id, vm) in cellVMs { merged[id] = vm }
        }
        self.viewModels = merged

        dynamicallyInsertedIDs[parentID, default: []].formUnion(insertedIDs)
        parentModel.objectWillChange.send()
        logger.log("Inserted row of \(cells.count) cells into parent \(parentID).\(container) at index \(index)", .debug)
        return cells.map { $0.id }
    }

    /// Remove an element by viewID. Refuses to remove the root.
    /// Note: For a Grid `rows` container, only individual cells (which carry ids) are addressable.
    /// Whole rows have no synthetic id and cannot be removed by viewID.
    func removeElement(viewID: Int) throws {
        if viewID == self.element?.id {
            throw InsertError.rootRemovalForbidden(rootID: viewID)
        }
        guard self.viewModels[viewID] != nil else {
            throw InsertError.viewNotFound(viewID: viewID)
        }
        guard let location = locateParent(of: viewID) else {
            throw InsertError.viewNotFound(viewID: viewID)
        }
        guard let parentModel = self.viewModels[location.parentID] else {
            throw InsertError.parentNotFound(parentID: location.parentID)
        }

        let descendantIDs = collectAllElementIDs(in: location.removedElement)
        // The removed view keeps its `.transition()`, so a transition-bearing element animates its
        // exit when the removal runs inside an animated transaction; otherwise the removal is instant.
        runStructuralMutation(animatedFor: location.removedElement) {
            switch location.shape {
            case .flat:
                var current = self.effectiveFlatContainer(for: location.parent, model: parentModel, container: location.container)
                if let idx = current.firstIndex(where: { $0.id == viewID }) {
                    current.remove(at: idx)
                    self.setDynamicContainer(on: parentModel, container: location.container, value: current)
                }
            case .rows:
                var current = self.effectiveRowsContainer(for: location.parent, model: parentModel, container: location.container)
                if let r = location.rowIndex, let c = location.colIndex,
                   r < current.count, c < current[r].count, current[r][c].id == viewID {
                    current[r].remove(at: c)
                    self.setDynamicContainer(on: parentModel, container: location.container, value: current)
                }
            }

            var updated = self.viewModels
            for id in descendantIDs { updated.removeValue(forKey: id) }
            self.viewModels = updated

            self.dynamicallyInsertedIDs[location.parentID]?.subtract(descendantIDs)
            if self.dynamicallyInsertedIDs[location.parentID]?.isEmpty == true {
                self.dynamicallyInsertedIDs.removeValue(forKey: location.parentID)
            }
            for id in descendantIDs {
                self.dynamicallyInsertedIDs.removeValue(forKey: id)
                self.loadedSubViewIDs.removeValue(forKey: id)
            }
            parentModel.objectWillChange.send()
        }
        logger.log("Removed element id \(viewID) from parent \(location.parentID).\(location.container); cleaned \(descendantIDs.count) viewModels", .debug)
    }

    // MARK: - Effective tree helpers

    private func setDynamicContainer(on model: ViewModel, container: String, value: Any) {
        var dyn = model.dynamicSubviews ?? [:]
        dyn[container] = value
        model.dynamicSubviews = dyn
    }

    private func effectiveFlatContainer(for parent: any ActionUIElementBase, model: ViewModel, container: String) -> [ActionUIElement] {
        if let dyn = model.dynamicSubviews?[container] as? [ActionUIElement] { return dyn }
        if let stat = parent.subviews?[container] as? [ActionUIElement] { return stat }
        if let stat = parent.subviews?[container] as? [any ActionUIElementBase] {
            return stat.compactMap { $0 as? ActionUIElement }
        }
        return []
    }

    private func effectiveRowsContainer(for parent: any ActionUIElementBase, model: ViewModel, container: String) -> [[ActionUIElement]] {
        if let dyn = model.dynamicSubviews?[container] as? [[ActionUIElement]] { return dyn }
        if let stat = parent.subviews?[container] as? [[ActionUIElement]] { return stat }
        if let stat = parent.subviews?[container] as? [[any ActionUIElementBase]] {
            return stat.map { $0.compactMap { $0 as? ActionUIElement } }
        }
        return []
    }

    private func resolveFlatIndex(in arr: [ActionUIElement], position: InsertPosition, container: String) throws -> Int {
        switch position {
        case .append: return arr.count
        case .prepend: return 0
        case .at(let i):
            if i < 0 || i > arr.count { throw InsertError.positionOutOfBounds(index: i, count: arr.count) }
            return i
        case .before(let id):
            guard let idx = arr.firstIndex(where: { $0.id == id }) else {
                throw InsertError.siblingNotFound(siblingID: id, container: container)
            }
            return idx
        case .after(let id):
            guard let idx = arr.firstIndex(where: { $0.id == id }) else {
                throw InsertError.siblingNotFound(siblingID: id, container: container)
            }
            return idx + 1
        }
    }

    private func resolveRowIndex(in rows: [[ActionUIElement]], position: InsertPosition) throws -> Int {
        switch position {
        case .append: return rows.count
        case .prepend: return 0
        case .at(let i):
            if i < 0 || i > rows.count { throw InsertError.positionOutOfBounds(index: i, count: rows.count) }
            return i
        case .before, .after:
            throw InsertError.unsupportedPositionForRowContainer(container: "rows")
        }
    }

    // Ids of the element subtree rooted at viewID (including viewID itself), or nil if the
    // view is not in this window. Used by pull-to-refresh so a client mutation anywhere
    // inside a refreshing view (e.g. a ScrollView's content) is recognized as the end signal.
    func subtreeIDs(of viewID: Int) -> Set<Int>? {
        guard let element = locateElement(byID: viewID) else { return nil }
        return collectAllElementIDs(in: element)
    }

    // Collect ids from an element subtree (used for conflict checks and cascade
    // cleanup) via the single shared descendant traversal (see childElements).
    private func collectAllElementIDs(in element: any ActionUIElementBase) -> Set<Int> {
        var ids: Set<Int> = [element.id]
        for child in element.childElements {
            ids.formUnion(collectAllElementIDs(in: child))
        }
        return ids
    }

    // Walks the effective tree (static + dynamicSubviews overrides per parent) to find
    // an element by id.
    private func locateElement(byID id: Int) -> ActionUIElement? {
        guard let root = self.element as? ActionUIElement else { return nil }
        return locateElementHelper(in: root, id: id)
    }

    private func locateElementHelper(in element: ActionUIElement, id: Int) -> ActionUIElement? {
        if element.id == id { return element }
        let subviews = effectiveSubviews(of: element)
        for key in ActionUISubviewContainers.arrayKeys {
            if let arr = subviews[key] as? [ActionUIElement] {
                for child in arr {
                    if let found = locateElementHelper(in: child, id: id) { return found }
                }
            }
        }
        if let rows = subviews[ActionUISubviewContainers.rowsKey] as? [[ActionUIElement]] {
            for row in rows {
                for child in row {
                    if let found = locateElementHelper(in: child, id: id) { return found }
                }
            }
        }
        for key in ActionUISubviewContainers.singleKeys {
            if let child = subviews[key] as? ActionUIElement,
               let found = locateElementHelper(in: child, id: id) { return found }
        }
        return nil
    }

    private func effectiveSubviews(of element: ActionUIElement) -> [String: Any] {
        var merged = element.subviews ?? [:]
        if let dyn = self.viewModels[element.id]?.dynamicSubviews {
            for (k, v) in dyn { merged[k] = v }
        }
        return merged
    }

    private struct ParentLocation {
        let parent: ActionUIElement
        let parentID: Int
        let container: String
        let shape: ContainerShape
        let rowIndex: Int?
        let colIndex: Int?
        let removedElement: ActionUIElement
    }

    private func locateParent(of childID: Int) -> ParentLocation? {
        guard let root = self.element as? ActionUIElement else { return nil }
        return locateParentHelper(in: root, childID: childID)
    }

    private func locateParentHelper(in element: ActionUIElement, childID: Int) -> ParentLocation? {
        let subviews = effectiveSubviews(of: element)
        for key in ActionUISubviewContainers.arrayKeys {
            if let arr = subviews[key] as? [ActionUIElement] {
                for child in arr where child.id == childID {
                    return ParentLocation(parent: element, parentID: element.id, container: key, shape: .flat, rowIndex: nil, colIndex: nil, removedElement: child)
                }
                for child in arr {
                    if let found = locateParentHelper(in: child, childID: childID) { return found }
                }
            }
        }
        if let rows = subviews[ActionUISubviewContainers.rowsKey] as? [[ActionUIElement]] {
            for r in rows.indices {
                for c in rows[r].indices where rows[r][c].id == childID {
                    return ParentLocation(parent: element, parentID: element.id, container: "rows", shape: .rows, rowIndex: r, colIndex: c, removedElement: rows[r][c])
                }
            }
            for row in rows {
                for child in row {
                    if let found = locateParentHelper(in: child, childID: childID) { return found }
                }
            }
        }
        for key in ActionUISubviewContainers.singleKeys {
            if let child = subviews[key] as? ActionUIElement {
                // Single-element containers: child cannot be removed via removeElement (use setElementProperty / LoadableView swap).
                if child.id == childID { return nil }
                if let found = locateParentHelper(in: child, childID: childID) { return found }
            }
        }
        return nil
    }
}
