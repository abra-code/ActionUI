// SwiftUI rendering of NavigationStack; its portable part is in Core/Elements/NavigationStack.swift.

import SwiftUI
import Combine

extension NavigationStack: ActionUISwiftUIRenderer {
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, _, _ in view }

    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        let content = element.subviews?["content"] as? any ActionUIElementBase ?? ActionUIElement(id: ActionUIElement.generateNegativeID(), type: "EmptyView", properties: [:], subviews: nil)
        let destinations = element.subviews?["destinations"] as? [any ActionUIElementBase] ?? []
        let windowModel = ActionUIModel.shared.windowModels[windowUUID]
        let contentModel = windowModel?.viewModels[content.id]

        // Items that stay in the bar wherever the user navigates inside this stack.
        // PersistentToolbar.onContainer / .onScreen pick the site that is right for the
        // platform and no-op on the other - see the comment on PersistentToolbar.
        let persistentItems = ToolbarHelper.persistentToolbarItems(of: element)

        // Detect selectable-list pattern: content is a List with actionID,
        // children have destinationViewId, and destinations array exists. The other elements'
        // properties are read untracked: a change to them does not render this container again.
        let isSelectableListPattern: Bool = UntrackedReads.perform {
            guard !destinations.isEmpty,
                  content.type == "List",
                  let contentModel = contentModel,
                  List.Props(contentModel.properties).actionID != nil else { return false }
            let children = content.subviews?["children"] as? [any ActionUIElementBase] ?? []
            guard !children.isEmpty else { return false }
            // At least one child must have destinationViewId
            return children.contains { child in
                windowModel?.viewModels[child.id].map { BaseModifiers($0.properties).destinationViewId != nil } ?? false
            }
        }

        if isSelectableListPattern {
            // Selectable-list-with-destinations pattern: NavigationStack manages the path
            // and builds the content List with selection binding (like NavigationSplitView sidebar).
            let container = NavigationPathContainer(model: model, contentModel: contentModel!) { pathBinding in
                SwiftUI.NavigationStack(path: pathBinding) {
                    PersistentToolbar.onScreen(
                        Self.buildContentList(
                            content: content,
                            contentModel: contentModel!,
                            destinations: destinations,
                            pathBinding: pathBinding,
                            windowModel: windowModel,
                            windowUUID: windowUUID,
                            navStackElement: element
                        ),
                        element: content,
                        windowUUID: windowUUID
                    )
                    .navigationDestination(for: Int.self) { destinationViewId in
                        if let target = destinations.first(where: { $0.id == destinationViewId }),
                           let targetModel = windowModel?.viewModels[target.id] {
                            PersistentToolbar.onScreen(
                                ActionUIView(element: target, model: targetModel, windowUUID: windowUUID),
                                element: target,
                                windowUUID: windowUUID
                            )
                        } else {
                            PersistentToolbar.onScreen(
                                SwiftUI.Text("Destination \(destinationViewId) not found")
                                    .foregroundStyle(.red),
                                element: nil,
                                windowUUID: windowUUID
                            )
                        }
                    }
                }
            }
            return PersistentToolbar.onContainer(container, items: persistentItems, windowUUID: windowUUID)
        } else {
            // Standard NavigationLink-based navigation (no selection binding).
            // Wrap in NavigationPathContainer so the `navigationPath` state drives
            // push/pop for ANY content type (VStack, grid, etc.), not just a List.
            // There is no row selection to clear on pop-to-root here, so
            // clearsSelectionOnPopToRoot is false; contentModel is only observed
            // (falling back to the stack's own model when content has no model).
            let container = NavigationPathContainer(model: model, contentModel: contentModel ?? model, clearsSelectionOnPopToRoot: false) { pathBinding in
                SwiftUI.NavigationStack(path: pathBinding) {
                    if let windowModel = windowModel,
                       let childModel = contentModel {
                        PersistentToolbar.onScreen(
                            ActionUIView(element: content, model: childModel, windowUUID: windowUUID),
                            element: content,
                            windowUUID: windowUUID
                        )
                          .navigationDestination(for: Int.self) { destinationViewId in
                            if let target = destinations.first(where: { $0.id == destinationViewId }) {
                                if let targetModel = windowModel.viewModels[target.id] {
                                   PersistentToolbar.onScreen(
                                       ActionUIView(element: target, model: targetModel, windowUUID: windowUUID),
                                       element: target,
                                       windowUUID: windowUUID
                                   )
                                }
                                else {
                                    PersistentToolbar.onScreen(
                                        SwiftUI.Text("Destination \(destinationViewId) has no model")
                                            .foregroundStyle(.red),
                                        element: nil,
                                        windowUUID: windowUUID
                                    )
                                }
                            } else {
                                PersistentToolbar.onScreen(
                                    SwiftUI.Text("Destination \(destinationViewId) not found")
                                        .foregroundStyle(.red),
                                    element: nil,
                                    windowUUID: windowUUID
                                )
                            }
                        }
                    }
                }
            }
            return PersistentToolbar.onContainer(container, items: persistentItems, windowUUID: windowUUID)
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
        let actionID = List.Props(contentModel.properties).actionID

        // Build bidirectional maps: child element ID <-> destination view ID
        let maps = RowSelection.buildIDMaps(children: children, windowModel: windowModel)
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
        let model: ViewModel
        let contentModel: ViewModel
        let clearsSelectionOnPopToRoot: Bool
        @State private var path: [Int] = []
        let content: (Binding<[Int]>) -> Content

        init(model: ViewModel, contentModel: ViewModel, clearsSelectionOnPopToRoot: Bool = true, @ViewBuilder content: @escaping (Binding<[Int]>) -> Content) {
            self.model = model
            self.contentModel = contentModel
            self.clearsSelectionOnPopToRoot = clearsSelectionOnPopToRoot
            self._path = State(initialValue: model.states["navigationPath"] as? [Int] ?? [])
            self.content = content
        }

        var body: some SwiftUI.View {
            let _ = model.trackAllChanges()
            let _ = contentModel.trackAllChanges()
            content($path)
                .onChange(of: path) { oldPath, newPath in
                    // Clear selection when navigating back to root so same item can be re-selected
                    // (selectable-list pattern only; the standard branch has no selection to clear).
                    if clearsSelectionOnPopToRoot && newPath.isEmpty && !oldPath.isEmpty {
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
                .onReceive(model.statesPublisher.map { $0["navigationPath"] as? [Int] ?? [] }) { modelPath in
                    // Sync programmatic changes from model to @State
                    if modelPath != path {
                        path = modelPath
                    }
                }
        }
    }
}
