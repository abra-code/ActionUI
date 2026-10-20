// SwiftUI rendering of List; its portable part is in Core/Elements/List.swift.

import SwiftUI

extension List: ActionUISwiftUIRenderer {
    // MARK: - Row modifier helpers

    /// Applies row-level list modifiers to a view. Returns the view wrapped in AnyView with any
    /// configured modifiers applied. When no row modifiers are set, returns AnyView(view) unchanged.
    private static func applyRowModifiers(_ view: some SwiftUI.View, props: Props) -> AnyView {
        guard props.hasRowModifiers else { return AnyView(view) }
        var modified: any SwiftUI.View = view

        if let bgStr = props.rowBackground,
           let color = ColorHelper.resolveColor(bgStr) {
            modified = modified.listRowBackground(color)
        }

        #if os(iOS) || os(macOS) || os(visionOS)
        if let sep = props.rowSeparator {
            let visibility: Visibility
            switch sep {
            case .hidden:    visibility = .hidden
            case .visible:   visibility = .visible
            case .automatic: visibility = .automatic
            }
            modified = modified.listRowSeparator(visibility)
        }

        if let tintStr = props.rowSeparatorTint,
           let color = ColorHelper.resolveColor(tintStr) {
            modified = modified.listRowSeparatorTint(color)
        }
        #endif

        switch props.rowInsets {
        case .uniform(let n):
            modified = modified.listRowInsets(EdgeInsets(top: n, leading: n, bottom: n, trailing: n))
        case .edges(let top, let leading, let bottom, let trailing):
            modified = modified.listRowInsets(EdgeInsets(top: top, leading: leading, bottom: bottom, trailing: trailing))
        case nil:
            break
        }

        return AnyView(modified)
    }

    /// Builds one row for homogeneous lists. Always returns AnyView so row modifiers can be uniformly
    /// applied regardless of the underlying view type (Text, Button, Image, AsyncImage).
    private static func buildHomogeneousRow(
        item: String, index: Int, viewType: Props.ViewType,
        dataInterpretation: Props.DataInterpretation, buttonActionID: String?,
        actionContext: Props.ActionContext, windowUUID: String, elementID: Int
    ) -> AnyView {
        let row: any SwiftUI.View
        switch viewType {
        case .button:
            row = SwiftUI.Button(item) {
                if let aid = buttonActionID {
                    let ctx: Any = actionContext == .rowIndex ? index : item
                    ActionUIModel.shared.actionHandler(aid, windowUUID: windowUUID, viewID: elementID, viewPartID: 0, context: ctx)
                }
            }
        case .image:
            row = SwiftUI.Image(from: item, interpretation: dataInterpretation.rawValue)
        case .asyncImage:
            row = SwiftUI.AsyncImage(url: URL(string: item)) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                SwiftUI.ProgressView()
            }
        case .text:
            row = SwiftUI.Text(item)
        }
        return AnyView(row)
    }

    // MARK: - Protocol conformance

    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        // Template mode: render one template instance per row in states["content"].
        // Replaces itemType with full ActionUI template support for richer cell layouts.
        let props = Props(properties)

        if let template = element.subviews?["template"] as? any ActionUIElementBase {
            let rows = (model.states["content"] as? [[String]]) ?? []
            let parentID = element.id
            let doubleClickActionID = props.doubleClickActionID
            let rowViews: [AnyView] = rows.indices.map { rowIndex in
                let templateView = TemplateHelper.buildTemplateView(
                    template: template, row: rows[rowIndex], rowIndex: rowIndex,
                    parentID: parentID, windowUUID: windowUUID, logger: logger
                )
                return applyRowModifiers(templateView, props: props)
            }

            // Selection binding: the same index-based binding as the homogeneous list.
            let selectionBinding = SelectionListHelper.makeRowSelectionBinding(
                drawnRows: rows, model: model, actionID: props.actionID,
                windowUUID: windowUUID, viewID: element.id
            )

            return SwiftUI.List(selection: selectionBinding) {
                ForEach(rowViews.indices, id: \.self) { i in rowViews[i] }
            }
            #if canImport(AppKit)
            // .onTapGesture(count: 2) never fires for row clicks on macOS (rows consume
            // the mouse events for selection); use the List's primaryAction instead, which
            // is the supported double-click (and Return-key) hook.
            .contextMenu(forSelectionType: Int.self) { _ in
                // No context-menu items: used only for its primaryAction.
            } primaryAction: { indices in
                if let doubleClickActionID = doubleClickActionID,
                   let index = indices.first {
                    if rows.indices.contains(index) {   // an index into the rows as drawn
                        // Keep selection/value in sync for env export, with the row as it is now.
                        let current = model.states["content"] as? [[String]] ?? []
                        model.value = ActionUIModel.reconciledSelection(rows[index], from: rows, to: current)
                    }
                    ActionUIModel.shared.actionHandler(doubleClickActionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0, context: index)
                }
            }
            #endif
        }

        // Check for heterogeneous list (children array)
        let children = element.subviews?["children"] as? [any ActionUIElementBase] ?? []
        if !children.isEmpty {
            if let actionID = props.actionID {
                // Selectable heterogeneous list mode: List(selection:) with child ID mapping.
                // Same pattern as NavigationSplitView.buildSidebarList — Labels/Text are selectable,
                // actionID fires on selection change with child element ID as context.
                let windowModel = ActionUIModel.shared.windowModels[windowUUID]

                let selectionBinding = SelectionListHelper.makeHeterogeneousSelectionBinding(
                    model: model,
                    actionID: actionID,
                    windowUUID: windowUUID,
                    viewID: element.id
                )

                return SelectionListHelper.buildSelectableList(
                    selection: selectionBinding,
                    children: children,
                    listElement: element,
                    listModel: nil as ViewModel?,
                    windowModel: windowModel,
                    windowUUID: windowUUID,
                    rowModifier: props.hasRowModifiers ? { view in applyRowModifiers(view, props: props) } : nil
                )
            } else {
                // No-selection heterogeneous list mode: NavigationLinks handle their own taps.
                // No List(selection:) binding — on iOS, selection binding intercepts taps and
                // prevents NavigationLink from activating.
                // Row styling properties are applied to each child view.
                // rowTransitionAnimation: animate row insert/remove only when a child declares a
                // `transition` (List needs the animation attached here, keyed by row identity, to play it).
                let (rowAnimation, rowIDs) = SelectionListHelper.rowTransitionAnimation(children)
                return SwiftUI.List {
                    ForEach(children, id: \.id) { child in
                        if let childModel = ActionUIModel.shared.windowModels[windowUUID]?.viewModels[child.id] {
                            applyRowModifiers(
                                ActionUIView(element: child, model: childModel, windowUUID: windowUUID),
                                props: props
                            )
                        }
                    }
                }
                .animation(rowAnimation, value: rowIDs)
            }
        } else {
            // Homogeneous list mode
            let viewType = props.viewType
            let dataInterpretation = props.dataInterpretation
            let actionContext = props.actionContext
            let items: [[String]] = (model.states["content"] as? [[String]]) ?? []
            let shownIndices = shownRowIndices(items)
            let buttonActionID = props.itemActionID
            let doubleClickActionID = props.doubleClickActionID
            let elementID = element.id

            let selectionBinding = SelectionListHelper.makeRowSelectionBinding(
                drawnRows: items, model: model, actionID: props.actionID,
                windowUUID: windowUUID, viewID: elementID
            )

            return SwiftUI.List(selection: selectionBinding) {
                // Row ids are indices into content, stable even with duplicate display strings;
                // the selection binding and the double-click read the drawn rows by the same index.
                SwiftUI.ForEach(shownIndices, id: \.self) { index in
                    applyRowModifiers(
                        buildHomogeneousRow(
                            item: items[index][0], index: index, viewType: viewType,
                            dataInterpretation: dataInterpretation, buttonActionID: buttonActionID,
                            actionContext: actionContext, windowUUID: windowUUID, elementID: elementID
                        ),
                        props: props
                    )
                }
            }
            #if canImport(AppKit)
            // .onTapGesture(count: 2) never fires for row clicks on macOS (rows consume
            // the mouse events for selection); use the List's primaryAction instead, which
            // is the supported double-click (and Return-key) hook.
            .contextMenu(forSelectionType: Int.self) { _ in
                // No context-menu items: used only for its primaryAction.
            } primaryAction: { indices in
                if let doubleClickActionID = doubleClickActionID,
                   let index = indices.first {
                    if items.indices.contains(index) {   // an index into the rows as drawn
                        // Keep selection/value in sync for env export, with the row as it is now.
                        let current = model.states["content"] as? [[String]] ?? []
                        model.value = ActionUIModel.reconciledSelection(items[index], from: items, to: current)
                    }
                    ActionUIModel.shared.actionHandler(doubleClickActionID, windowUUID: windowUUID, viewID: elementID, viewPartID: 0, context: index)
                }
            }
            #endif
        }
    }

    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, element, windowUUID, properties, logger in
        var modifiedView = view
        let props = Props(properties)
        if let onRefreshActionID = props.onRefreshActionID {
            let viewID = element.id
            modifiedView = modifiedView.refreshable {
                await ActionUIModel.shared.runRefresh(windowUUID: windowUUID, viewID: viewID, actionID: onRefreshActionID)
            }
        }
        // A style this platform lacks applies nothing, as an unknown one does.
        switch props.listStyle {
        case .plain:
            modifiedView = modifiedView.listStyle(.plain)
        case .inset:
            #if os(iOS) || os(macOS) || os(visionOS)
            modifiedView = modifiedView.listStyle(.inset)
            #else
            break
            #endif
        case .sidebar:
            #if os(iOS) || os(macOS) || os(visionOS)
            modifiedView = modifiedView.listStyle(.sidebar)
            #else
            break
            #endif
        case .grouped:
            #if os(iOS) || os(tvOS) || os(visionOS)
            modifiedView = modifiedView.listStyle(.grouped)
            #else
            break
            #endif
        case .insetGrouped:
            #if os(iOS) || os(visionOS)
            modifiedView = modifiedView.listStyle(.insetGrouped)
            #else
            break
            #endif
        case .automatic, nil:
            break // the system default
        }
        return modifiedView
    }
}
