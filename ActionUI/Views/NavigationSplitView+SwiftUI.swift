// SwiftUI rendering of NavigationSplitView; its portable part is in Core/Elements/NavigationSplitView.swift.

import SwiftUI
import Combine

extension NavigationSplitView: ActionUISwiftUIRenderer {
    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        let props = Props(properties)
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
                           let actionID = BaseModifiers(sidebarModel.properties).actionID {
                            ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: sidebar.id, viewPartID: 0)
                        }
                    }
                }
            )

            if let content = content {
                // 3-pane with destinations: sidebar selection drives detail switching
                let container = ColumnVisibilityContainer(model: model, elementId: element.id, windowUUID: windowUUID, valueChangeActionID: props.valueChangeActionID) { visibilityBinding in
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
                let container = ColumnVisibilityContainer(model: model, elementId: element.id, windowUUID: windowUUID, valueChangeActionID: props.valueChangeActionID) { visibilityBinding in
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
            let container = ColumnVisibilityContainer(model: model, elementId: element.id, windowUUID: windowUUID, valueChangeActionID: props.valueChangeActionID) { visibilityBinding in
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
            let container = ColumnVisibilityContainer(model: model, elementId: element.id, windowUUID: windowUUID, valueChangeActionID: props.valueChangeActionID) { visibilityBinding in
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
        let model: ViewModel
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
            let _ = model.trackAllChanges()
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
                .onReceive(model.statesPublisher.map { $0["columnVisibility"] as? String }) { newStr in
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
    /// content based on states["selectedDestination"]. Reading the model in its body ensures
    /// SwiftUI re-evaluates this view when the selection changes, even though
    /// NavigationSplitView manages its column closures independently.
    private struct DestinationDetailView: SwiftUI.View {
        let model: ViewModel
        let destinations: [any ActionUIElementBase]
        let defaultDetail: any ActionUIElementBase
        let windowModel: WindowModel?
        let windowUUID: String

        var body: some SwiftUI.View {
            let _ = model.trackAllChanges()
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
        let props = Props(properties)
        switch props.style {
        case .balanced:
            modifiedView = modifiedView.navigationSplitViewStyle(.balanced)
        case .prominentDetail:
            modifiedView = modifiedView.navigationSplitViewStyle(.prominentDetail)
        case .automatic:
            modifiedView = modifiedView.navigationSplitViewStyle(.automatic)
        case nil:
            break
        }
        return modifiedView
    }
}
