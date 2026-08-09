// Sources/Views/NavigationSplitView.swift
/*
 Sample JSON for NavigationSplitView:

// Form 1: Static panes (no destination switching)
 {
   "type": "NavigationSplitView",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "sidebar": {          // Required: Single child view for sidebar. Note: Declared as a top-level key in JSON but stored in subviews["sidebar"] by ActionUIElement.init(from:).
     "type": "Text", "properties": { "text": "Sidebar" }
   },
   "content": {          // Optional: Single child view for content (3-pane). Note: Declared as a top-level key in JSON but stored in subviews["content"].
     "type": "Text", "properties": { "text": "Content" }
   },
   "detail": {           // Required: Single child view for detail. Note: Declared as a top-level key in JSON but stored in subviews["detail"].
     "type": "Text", "properties": { "text": "Detail" }
   },
   "properties": {
     "columnVisibility": "all", // Optional: "automatic", "all", "doubleColumn", "detail"; defaults to "all"
     "style": "balanced" // Optional: "automatic", "balanced", "prominentDetail"; defaults to "automatic"
   }
 }

// Form 2: Selection-driven destination switching (2-pane)
// The sidebar must be a List whose children have a "destinationViewId" property
// linking them to destination views by id. All element ids must be unique.
// Selecting a child in the sidebar shows the corresponding destination in the detail pane.
 {
   "type": "NavigationSplitView",
   "id": 1,
   "sidebar": {
     "type": "List",
     "id": 2,
     "properties": { "actionID": "sidebar.selection.changed" },
     "children": [
       { "type": "Label", "id": 100, "properties": { "title": "Item A", "systemImage": "1.circle", "destinationViewId": 10 } },
       { "type": "Label", "id": 101, "properties": { "title": "Item B", "systemImage": "2.circle", "destinationViewId": 11 } }
     ]
   },
   "detail": {
     "type": "Text", "properties": { "text": "Select an item" }
   },
   "destinations": [
     { "type": "VStack", "id": 10, "children": [ ... ] },
     { "type": "VStack", "id": 11, "children": [ ... ] }
   ]
 }
 // Note: Sidebar children link to destinations via "destinationViewId" in properties.
 // NavigationLink is NOT needed in the sidebar for NavigationSplitView.
 // Use NavigationLink only inside NavigationStack for push-based navigation.

// Persistent toolbar: items that stay in the bar wherever the user navigates inside the split
// view, rather than only on the column that declares them. Same ToolbarItem / ToolbarItemGroup
// shapes as the per-screen "toolbar" key, and they compose with it.
 {
   "type": "NavigationSplitView",
   "id": 1,
   "persistentToolbar": [
     { "type": "ToolbarItem", "id": 16, "properties": { "placement": "primaryAction" },
       "content": { "type": "Image", "id": 17, "properties": { "systemName": "arrow.clockwise" } } }
   ],
   "sidebar": { ... },
   "detail": { ... }
 }
 // A "toolbar" declared on the NavigationSplitView itself is a DEPRECATED ALIAS for
 // "persistentToolbar"; it still works and logs a one-time warning.
 // Where the items land is per platform: macOS puts them in the shared window toolbar; platforms
 // whose columns each own a bar put them on the detail column, and on the leading columns only in
 // compact width, where the split view collapses into one stack rooted at the sidebar. A column
 // that is ITSELF a NavigationStack is the exception - there the items go onto that stack's own
 // screens, since a toolbar applied around a stack does not reach the bars inside it.
 // Implemented on Apple platforms only so far: Android and web currently ignore the key.

 // Note: These properties are specific to NavigationSplitView. Baseline View properties (padding, hidden, foregroundStyle, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties).

// Observable state (via getElementState / setElementState):
//   states["columnVisibility"]     String  Current column visibility: "automatic", "all", "doubleColumn", or
//                                          "detail". Updated on user interaction; write to change programmatically.
//   states["selectedDestination"]  Int?    Currently selected destination ID (matches a destination element's id).
//                                          nil when no destination is selected. Write to change programmatically.
*/

import SwiftUI
import Combine

struct NavigationSplitView: ActionUIViewConstruction {
    static var initialValue: (ViewModel) -> Any? = { model in model.value }
    static var initialStates: (ViewModel) -> [String: Any] = { model in model.states }
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = nil
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = nil
    static var insertableContainers: [String: ContainerShape]? = nil

    static var valueType: Any.Type = Void.self
    
    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        var validatedProperties = properties
                
        // Validate columnVisibility
        if let columnVisibility = validatedProperties["columnVisibility"] as? String,
           !["automatic", "all", "doubleColumn", "detail"].contains(columnVisibility) {
            logger.log("Invalid NavigationSplitView columnVisibility: \(columnVisibility); defaulting to 'all'", .warning)
            validatedProperties["columnVisibility"] = "all"
        }
        
        // Validate style
        if let style = validatedProperties["style"] as? String,
           !["automatic", "balanced", "prominentDetail"].contains(style) {
            logger.log("Invalid NavigationSplitView style: \(style); defaulting to 'automatic'", .warning)
            validatedProperties["style"] = "automatic"
        }
        
        return validatedProperties
    }
    
    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        let sidebar = element.subviews?["sidebar"] as? any ActionUIElementBase ?? ActionUIElement(id: ActionUIElement.generateNegativeID(), type: "EmptyView", properties: [:], subviews: nil)
        let content = element.subviews?["content"] as? any ActionUIElementBase
        let detail = element.subviews?["detail"] as? any ActionUIElementBase ?? ActionUIElement(id: ActionUIElement.generateNegativeID(), type: "EmptyView", properties: [:], subviews: nil)
        let destinations = element.subviews?["destinations"] as? [any ActionUIElementBase] ?? []

        let windowModel = ActionUIModel.shared.windowModels[windowUUID]

        // Items that stay in the bar wherever the user navigates inside this split view.
        // macOS applies them once outside the container (all columns share one window toolbar);
        // elsewhere they go on the columns - see PersistentToolbar.
        let persistentItems = ToolbarHelper.persistentToolbarItems(of: element)

        if !destinations.isEmpty {
            // Selection-driven destination switching:
            // Sidebar List children declare a "destinationViewId" property linking to a destination view.
            // Because ActionUIView returns AnyView (via applyViewModifiers), .tag() does not propagate
            // through the type-erased boundary. SwiftUI's List selection therefore uses the ForEach
            // identity (child.id) rather than any explicit .tag(). We bridge this with bidirectional
            // maps: childToDestination translates a selected child ID to its destination ID for storage
            // in states["selectedDestination"], and destinationToChild reverses the lookup so the List
            // highlight tracks the correct row.
            if sidebar.type != "List" {
                logger.log("NavigationSplitView with destinations requires sidebar to be a List for selection support; got '\(sidebar.type)'", .warning)
            }
            let sidebarChildren = sidebar.subviews?["children"] as? [any ActionUIElementBase] ?? []

            // Build bidirectional maps: child element ID <-> destination view ID
            let maps = SelectionListHelper.buildIDMaps(children: sidebarChildren, windowModel: windowModel)
            let childToDestination = maps.childToDestination
            let destinationToChild = maps.destinationToChild

            let selectionBinding: Binding<Int?> = mainActorBinding(
                get: {
                    // Reverse-map: states stores destination ID, List expects child element ID
                    if let destId = model.states["selectedDestination"] as? Int {
                        return destinationToChild[destId] ?? destId
                    }
                    return nil
                },
                set: { newValue in
                    // Forward-map: List provides child element ID, store destination ID
                    let destinationId = newValue.flatMap { childToDestination[$0] } ?? newValue
                    guard model.states["selectedDestination"] as? Int != destinationId else { return }
                    DispatchQueue.main.async {
                        model.states["selectedDestination"] = destinationId
                        if let sidebarModel = windowModel?.viewModels[sidebar.id],
                           let actionID = sidebarModel.validatedProperties["actionID"] as? String {
                            ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: sidebar.id, viewPartID: 0)
                        }
                    }
                }
            )

            if let content = content {
                // 3-pane with destinations: sidebar selection drives detail switching
                let container = ColumnVisibilityContainer(model: model, elementId: element.id, windowUUID: windowUUID, valueChangeActionID: properties["valueChangeActionID"] as? String) { visibilityBinding in
                    SwiftUI.NavigationSplitView(columnVisibility: visibilityBinding) {
                        PersistentToolbar.onSplitViewColumn(
                            SelectionListHelper.buildSelectableList(selection: selectionBinding, children: sidebarChildren, listElement: sidebar, listModel: windowModel?.viewModels[sidebar.id], windowModel: windowModel, windowUUID: windowUUID),
                            windowUUID: windowUUID, isDetail: false,
                            columnIsNavigationContainer: ToolbarHelper.isNavigationContainer(sidebar.type)
                        )
                    } content: {
                        Self.staticColumn(content, windowModel: windowModel, windowUUID: windowUUID, isDetail: false)
                    } detail: {
                        DestinationDetailView(model: model, destinations: destinations, defaultDetail: detail, windowModel: windowModel, windowUUID: windowUUID)
                    }
                }
                return PersistentToolbar.onContainer(container, items: persistentItems, windowUUID: windowUUID)
            } else {
                // 2-pane with destinations: sidebar selection drives detail switching
                let container = ColumnVisibilityContainer(model: model, elementId: element.id, windowUUID: windowUUID, valueChangeActionID: properties["valueChangeActionID"] as? String) { visibilityBinding in
                    SwiftUI.NavigationSplitView(columnVisibility: visibilityBinding) {
                        PersistentToolbar.onSplitViewColumn(
                            SelectionListHelper.buildSelectableList(selection: selectionBinding, children: sidebarChildren, listElement: sidebar, listModel: windowModel?.viewModels[sidebar.id], windowModel: windowModel, windowUUID: windowUUID),
                            windowUUID: windowUUID, isDetail: false,
                            columnIsNavigationContainer: ToolbarHelper.isNavigationContainer(sidebar.type)
                        )
                    } detail: {
                        DestinationDetailView(model: model, destinations: destinations, defaultDetail: detail, windowModel: windowModel, windowUUID: windowUUID)
                    }
                }
                return PersistentToolbar.onContainer(container, items: persistentItems, windowUUID: windowUUID)
            }
        } else if let content = content {
            // 3-pane without destinations: static sidebar | content | detail
            let container = ColumnVisibilityContainer(model: model, elementId: element.id, windowUUID: windowUUID, valueChangeActionID: properties["valueChangeActionID"] as? String) { visibilityBinding in
                SwiftUI.NavigationSplitView(columnVisibility: visibilityBinding) {
                    Self.staticColumn(sidebar, windowModel: windowModel, windowUUID: windowUUID, isDetail: false)
                } content: {
                    Self.staticColumn(content, windowModel: windowModel, windowUUID: windowUUID, isDetail: false)
                } detail: {
                    Self.staticColumn(detail, windowModel: windowModel, windowUUID: windowUUID, isDetail: true)
                }
            }
            return PersistentToolbar.onContainer(container, items: persistentItems, windowUUID: windowUUID)
        } else {
            // 2-pane without destinations: static sidebar | detail
            let container = ColumnVisibilityContainer(model: model, elementId: element.id, windowUUID: windowUUID, valueChangeActionID: properties["valueChangeActionID"] as? String) { visibilityBinding in
                SwiftUI.NavigationSplitView(columnVisibility: visibilityBinding) {
                    Self.staticColumn(sidebar, windowModel: windowModel, windowUUID: windowUUID, isDetail: false)
                } detail: {
                    Self.staticColumn(detail, windowModel: windowModel, windowUUID: windowUUID, isDetail: true)
                }
            }
            return PersistentToolbar.onContainer(container, items: persistentItems, windowUUID: windowUUID)
        }
    }

    /// One statically-declared column (sidebar, content or detail), with the split view's
    /// persistent items applied where this platform needs them.
    ///
    /// The is-a-container check lives here rather than at the call site because this is where the
    /// column's ELEMENT is known, and a column that is itself a NavigationStack has to apply
    /// those items to its own screens instead of having them wrapped around it - a toolbar
    /// applied outside a stack does not reach the bars of the screens inside it.
    @ViewBuilder
    private static func staticColumn(_ element: any ActionUIElementBase, windowModel: WindowModel?, windowUUID: String, isDetail: Bool) -> some SwiftUI.View {
        PersistentToolbar.onSplitViewColumn(
            Self.columnBody(element, windowModel: windowModel, windowUUID: windowUUID),
            windowUUID: windowUUID,
            isDetail: isDetail,
            columnIsNavigationContainer: ToolbarHelper.isNavigationContainer(element.type)
        )
    }

    /// The column's content itself, or an EmptyView when the element has no ViewModel.
    @ViewBuilder
    private static func columnBody(_ element: any ActionUIElementBase, windowModel: WindowModel?, windowUUID: String) -> some SwiftUI.View {
        if let childModel = windowModel?.viewModels[element.id] {
            ActionUIView(element: element, model: childModel, windowUUID: windowUUID)
        } else {
            SwiftUI.EmptyView()
        }
    }

    /// Wrapper view that owns @State for columnVisibility so SwiftUI's sidebar toggle
    /// updates synchronously. Changes are synced to/from the ViewModel asynchronously
    /// to avoid Combine "publishing changes from within view updates" crashes.
    private struct ColumnVisibilityContainer<Content: SwiftUI.View>: SwiftUI.View {
        @ObservedObject var model: ViewModel
        @State private var columnVisibility: NavigationSplitViewVisibility
        let elementId: Int
        let windowUUID: String
        let valueChangeActionID: String?
        let content: (Binding<NavigationSplitViewVisibility>) -> Content

        init(model: ViewModel, elementId: Int, windowUUID: String, valueChangeActionID: String?, @ViewBuilder content: @escaping (Binding<NavigationSplitViewVisibility>) -> Content) {
            self.model = model
            self.elementId = elementId
            self.windowUUID = windowUUID
            self.valueChangeActionID = valueChangeActionID
            self._columnVisibility = State(initialValue: Self.resolve(model.states["columnVisibility"] as? String))
            self.content = content
        }

        var body: some SwiftUI.View {
            content($columnVisibility)
                .onChange(of: columnVisibility) { _, newValue in
                    let str = Self.stringify(newValue)
                    guard model.states["columnVisibility"] as? String != str else { return }
                    DispatchQueue.main.async {
                        model.states["columnVisibility"] = str
                        if let actionID = valueChangeActionID {
                            ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: elementId, viewPartID: 0)
                        }
                    }
                }
                .onReceive(model.$states.map { $0["columnVisibility"] as? String }) { newStr in
                    // Sync programmatic model changes back to @State
                    let newVis = Self.resolve(newStr)
                    if columnVisibility != newVis {
                        columnVisibility = newVis
                    }
                }
        }

        private static func resolve(_ str: String?) -> NavigationSplitViewVisibility {
            switch str {
            case "automatic": return .automatic
            case "doubleColumn": return .doubleColumn
            case "detail": return .detailOnly
            default: return .all
            }
        }

        private static func stringify(_ vis: NavigationSplitViewVisibility) -> String {
            switch vis {
            case .automatic: return "automatic"
            case .doubleColumn: return "doubleColumn"
            case .detailOnly: return "detail"
            case .all: return "all"
            default: return "all"
            }
        }
    }

    /// View that observes the NavigationSplitView's model and switches the detail
    /// content based on states["selectedDestination"]. Using @ObservedObject ensures
    /// SwiftUI re-evaluates this view when the selection changes, even though
    /// NavigationSplitView manages its column closures independently.
    private struct DestinationDetailView: SwiftUI.View {
        @ObservedObject var model: ViewModel
        let destinations: [any ActionUIElementBase]
        let defaultDetail: any ActionUIElementBase
        let windowModel: WindowModel?
        let windowUUID: String

        var body: some SwiftUI.View {
            // The persistent items are applied HERE, not around the whole column, because which
            // element occupies the detail changes with the selection - and whether that element
            // is itself a navigation container (which must carry the items on its own screens
            // instead) changes with it. Wrapping the column once could only ever be right for
            // one of the destinations.
            if let selectedId = model.states["selectedDestination"] as? Int,
               let target = destinations.first(where: { $0.id == selectedId }),
               let targetModel = windowModel?.viewModels[target.id] {
                PersistentToolbar.onSplitViewColumn(
                    ActionUIView(element: target, model: targetModel, windowUUID: windowUUID),
                    windowUUID: windowUUID,
                    isDetail: true,
                    columnIsNavigationContainer: ToolbarHelper.isNavigationContainer(target.type)
                )
            } else if let childModel = windowModel?.viewModels[defaultDetail.id] {
                PersistentToolbar.onSplitViewColumn(
                    ActionUIView(element: defaultDetail, model: childModel, windowUUID: windowUUID),
                    windowUUID: windowUUID,
                    isDetail: true,
                    columnIsNavigationContainer: ToolbarHelper.isNavigationContainer(defaultDetail.type)
                )
            } else {
                SwiftUI.EmptyView()
            }
        }
    }
    
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, properties, logger in
        var modifiedView = view
        if let style = properties["style"] as? String {
            switch style {
            case "balanced":
                modifiedView = modifiedView.navigationSplitViewStyle(.balanced)
            case "prominentDetail":
                modifiedView = modifiedView.navigationSplitViewStyle(.prominentDetail)
            case "automatic":
                modifiedView = modifiedView.navigationSplitViewStyle(.automatic)
            default:
                break
            }
        }
        return modifiedView
    }
}
