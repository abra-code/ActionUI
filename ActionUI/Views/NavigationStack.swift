// Sources/Views/NavigationStack.swift
/*
 Sample JSON for NavigationStack:

// Form 1: NavigationLink-based navigation (no selection binding)
 {
   "type": "NavigationStack",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "content": {          // Required: Single child view. Note: Declared as a top-level key in JSON but stored in subviews["content"] by ActionUIElement.init(from:).
     "type": "Text", "properties": { "text": "Home" }
   },
   "destinations": [ // Optional, needed if in "content" you placed NavigationLink(s) with destinationViewId
     { "type": "Text", "id": 10, "properties": { "text": "Destination View 10" } },
     { "type": "Text", "id": 11, "properties": { "text": "Destination View 11" } }
   ]
 }

// Form 2: Selectable List with programmatic push navigation
// When content is a List with actionID and children have destinationViewId,
// NavigationStack uses List(selection:) with path-based navigation.
// This mirrors NavigationSplitView's sidebar pattern but with push navigation.
 {
   "type": "NavigationStack",
   "id": 1,
   "content": {
     "type": "List",
     "id": 2,
     "properties": { "actionID": "navstack.list.selection.changed" },
     "children": [
       { "type": "Label", "id": 100, "properties": { "title": "Item A", "systemImage": "1.circle", "destinationViewId": 10 } },
       { "type": "Label", "id": 101, "properties": { "title": "Item B", "systemImage": "2.circle", "destinationViewId": 11 } }
     ]
   },
   "destinations": [
     { "type": "Text", "id": 10, "properties": { "text": "Detail A" } },
     { "type": "Text", "id": 11, "properties": { "text": "Detail B" } }
   ]
 }

 // Observable state (via getElementState / setElementState):
 //   states["navigationPath"]  [Int]   Current navigation path as array of destination IDs.
 //                                     Empty when at root. Write to push/pop programmatically:
 //                                     setElementState(windowUUID:, viewID:, key: "navigationPath", value: [destId])

 // Note: These properties are specific to NavigationStack. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties).
*/

import SwiftUI
import Combine

struct NavigationStack: ActionUIViewConstruction {
    static var valueType: Any.Type = Void.self
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, _, _ in view }
    static var initialValue: (ViewModel) -> Any? = { model in model.value }
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = nil
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = nil


    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        var validatedProperties = properties

        return validatedProperties
    }

    static var initialStates: (ViewModel) -> [String: Any] = { model in
        var states = model.states
        if states["navigationPath"] == nil {
            states["navigationPath"] = [] as [Int]
        }
        return states
    }

    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        let content = element.subviews?["content"] as? any ActionUIElementBase ?? ActionUIElement(id: ActionUIElement.generateNegativeID(), type: "EmptyView", properties: [:], subviews: nil)
        let destinations = element.subviews?["destinations"] as? [any ActionUIElementBase] ?? []
        let windowModel = ActionUIModel.shared.windowModels[windowUUID]
        let contentModel = windowModel?.viewModels[content.id]

        // Detect selectable-list pattern: content is a List with actionID,
        // children have destinationViewId, and destinations array exists.
        let isSelectableListPattern: Bool = {
            guard !destinations.isEmpty,
                  content.type == "List",
                  let contentModel = contentModel,
                  contentModel.validatedProperties["actionID"] is String else { return false }
            let children = content.subviews?["children"] as? [any ActionUIElementBase] ?? []
            guard !children.isEmpty else { return false }
            // At least one child must have destinationViewId
            return children.contains { child in
                windowModel?.viewModels[child.id]?.validatedProperties["destinationViewId"] is Int
            }
        }()

        if isSelectableListPattern {
            // Selectable-list-with-destinations pattern: NavigationStack manages the path
            // and builds the content List with selection binding (like NavigationSplitView sidebar).
            return NavigationPathContainer(model: model, contentModel: contentModel!) { pathBinding in
                SwiftUI.NavigationStack(path: pathBinding) {
                    Self.buildContentList(
                        content: content,
                        contentModel: contentModel!,
                        destinations: destinations,
                        pathBinding: pathBinding,
                        windowModel: windowModel,
                        windowUUID: windowUUID,
                        navStackElement: element
                    )
                    .navigationDestination(for: Int.self) { destinationViewId in
                        if let target = destinations.first(where: { $0.id == destinationViewId }),
                           let targetModel = windowModel?.viewModels[target.id] {
                            ActionUIView(element: target, model: targetModel, windowUUID: windowUUID)
                        } else {
                            SwiftUI.Text("Destination \(destinationViewId) not found")
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
        } else {
            // Standard NavigationLink-based navigation (no selection binding)
            return SwiftUI.NavigationStack() {
                if let windowModel = windowModel,
                   let childModel = contentModel {
                    ActionUIView(element: content, model: childModel, windowUUID: windowUUID)
                      .navigationDestination(for: Int.self) { destinationViewId in
                        if let target = destinations.first(where: { $0.id == destinationViewId }) {
                            if let targetModel = windowModel.viewModels[target.id] {
                               ActionUIView(element: target, model: targetModel, windowUUID: windowUUID)
                            }
                            else {
                                SwiftUI.Text("Destination \(destinationViewId) has no model")
                                    .foregroundStyle(.red)
                            }
                        } else {
                            SwiftUI.Text("Destination \(destinationViewId) not found")
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
        }
    }

    /// Builds the content List with a single-selection binding for destination pushing.
    /// Mirrors NavigationSplitView.buildSidebarList — uses bidirectional ID maps between
    /// child element IDs (ForEach identity) and destination view IDs (path values).
    /// On selection change: fires the List's actionID, then pushes the destination.
    /// Applies the List element's View modifiers to the built List.
    @ViewBuilder
    private static func buildContentList(
        content: any ActionUIElementBase,
        contentModel: ViewModel,
        destinations: [any ActionUIElementBase],
        pathBinding: Binding<[Int]>,
        windowModel: WindowModel?,
        windowUUID: String,
        navStackElement: any ActionUIElementBase
    ) -> some SwiftUI.View {
        let children = content.subviews?["children"] as? [any ActionUIElementBase] ?? []
        let actionID = contentModel.validatedProperties["actionID"] as? String

        // Build bidirectional maps: child element ID <-> destination view ID
        let maps = SelectionListHelper.buildIDMaps(children: children, windowModel: windowModel)
        let childToDestination = maps.childToDestination
        let destinationToChild = maps.destinationToChild

        let selectionBinding = Binding<Int?>(
            get: {
                // Reverse-map: if path has a destination, show corresponding child as selected
                if let destId = pathBinding.wrappedValue.last {
                    return destinationToChild[destId]
                }
                // Also check List model value for selection without navigation
                if let selected = contentModel.value as? [String],
                   let first = selected.first,
                   let childId = Int(first) {
                    return childId
                }
                return nil
            },
            set: { newValue in
                let destinationId = newValue.flatMap { childToDestination[$0] }
                let newStringValue: [String] = newValue.map { [String($0)] } ?? []

                DispatchQueue.main.async {
                    // Update List selection value
                    contentModel.value = newStringValue

                    // Fire List's actionID
                    if let actionID = actionID {
                        ActionUIModel.shared.actionHandler(
                            actionID,
                            windowUUID: windowUUID,
                            viewID: content.id,
                            viewPartID: 0,
                            context: newValue as Any
                        )
                    }

                    // Push destination
                    if let destId = destinationId {
                        pathBinding.wrappedValue = [destId]
                    }
                }
            }
        )

        SelectionListHelper.buildSelectableList(
            selection: selectionBinding,
            children: children,
            listElement: content,
            listModel: contentModel,
            windowModel: windowModel,
            windowUUID: windowUUID
        )
    }

    /// Wrapper view that owns @State for the navigation path so SwiftUI manages
    /// push/pop transitions. Changes are synced to/from the ViewModel asynchronously.
    /// Mirrors NavigationSplitView.ColumnVisibilityContainer pattern.
    private struct NavigationPathContainer<Content: SwiftUI.View>: SwiftUI.View {
        @ObservedObject var model: ViewModel
        @ObservedObject var contentModel: ViewModel
        @State private var path: [Int] = []
        let content: (Binding<[Int]>) -> Content

        init(model: ViewModel, contentModel: ViewModel, @ViewBuilder content: @escaping (Binding<[Int]>) -> Content) {
            self.model = model
            self.contentModel = contentModel
            self._path = State(initialValue: model.states["navigationPath"] as? [Int] ?? [])
            self.content = content
        }

        var body: some SwiftUI.View {
            content($path)
                .onChange(of: path) { oldPath, newPath in
                    // Clear selection when navigating back to root so same item can be re-selected
                    if newPath.isEmpty && !oldPath.isEmpty {
                        DispatchQueue.main.async {
                            contentModel.value = [] as [String]
                        }
                    }
                    // Sync path to model state
                    let modelPath = model.states["navigationPath"] as? [Int] ?? []
                    if modelPath != newPath {
                        DispatchQueue.main.async {
                            model.states["navigationPath"] = newPath
                        }
                    }
                }
                .onReceive(model.$states.map { $0["navigationPath"] as? [Int] ?? [] }) { modelPath in
                    // Sync programmatic changes from model to @State
                    if modelPath != path {
                        path = modelPath
                    }
                }
        }
    }
}
