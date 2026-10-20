// SwiftUI rendering of Table; its portable part is in Core/Elements/Table.swift.

import SwiftUI

struct TableRowData: Identifiable {
    let id: String
    let values: [String]
}

struct ColumnData: Identifiable {
    let id: Int
    let name: String
    let minWidth: CGFloat?
    let idealWidth: CGFloat?
    let maxWidth: CGFloat?
}

/// A Toggle cell of a Table column: a checkbox (or switch, or button) with no title, showing
/// the cell's row data. A user toggle is handed to `onToggle` after the view update; the
/// table then redraws from the row written.
struct TableToggleCell: SwiftUI.View {
    let isOn: Bool
    let style: Table.Props.ToggleStyle
    let isDisabled: Bool
    let onToggle: @MainActor (Bool) -> Void

    var body: some SwiftUI.View {
        let binding = mainActorBinding(
            get: { isOn },
            set: { newValue in
                guard newValue != isOn else { return }
                DispatchQueue.main.async { onToggle(newValue) }
            }
        )
        styled(SwiftUI.Toggle("", isOn: binding).labelsHidden())
            .disabled(isDisabled)
    }

    @ViewBuilder
    private func styled(_ toggle: some SwiftUI.View) -> some SwiftUI.View {
        switch style {
        case .switch:
            toggle.toggleStyle(SwitchToggleStyle())
        case .button:
            toggle.toggleStyle(ButtonToggleStyle())
        case .checkbox:
            #if os(macOS)
            toggle.toggleStyle(CheckboxToggleStyle())
            #else
            toggle.toggleStyle(SwitchToggleStyle())
            #endif
        }
    }
}

extension Table: ActionUISwiftUIRenderer {
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, _, _ in view }

    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        #if canImport(AppKit)
        let props = Props(properties)
        let columnTypes = props.columnTypes
        let columns = props.columns
        let rows = (model.states["content"] as? [[String]]) ?? []
        let idealWidths = props.widths?.map { CGFloat($0) }
        let minWidths = props.minWidths?.map { CGFloat($0) }
        let lastVisibleIndex = columns.count - 1

        var columnHeadersVisibility: SwiftUI.Visibility = .automatic
        switch props.columnHeadersVisibility {
        case .hidden:
            columnHeadersVisibility = .hidden
        case .visible:
            columnHeadersVisibility = .visible
        case .automatic, nil:
            break
        }

        // Find the column with the largest ideal width — it fills remaining space
        let resolvedWidths = columns.indices.map { index in
            idealWidths.flatMap { $0.indices.contains(index) ? $0[index] : nil } ?? CGFloat(100)
        }
        let maxIdeal = resolvedWidths.max() ?? 100
        let columnData = columns.enumerated().map { (index, name) in
            let ideal = resolvedWidths[index]
            let isFillColumn = (ideal == maxIdeal)
            // Resolved minimum width: an explicit minWidths entry, else the legacy default of min(ideal, 10).
            let resolvedMin = minWidths.flatMap { $0.indices.contains(index) ? $0[index] : nil } ?? Swift.min(ideal, 10)
            // Honor the minimum: ideal (and a non-fill column's max) can never fall below it,
            // keeping min <= ideal <= max as SwiftUI's .width(min:ideal:max:) requires.
            let clampedIdeal = Swift.max(ideal, resolvedMin)
            return ColumnData(
                id: index,
                name: name,
                minWidth: resolvedMin,
                idealWidth: clampedIdeal,
                maxWidth: isFillColumn ? .infinity : clampedIdeal
            )
        }
        
        let rowData = rows.enumerated().map { (index, row) in
            TableRowData(id: "row-\(index)", values: row)
        }
        
        let selectionBinding = makeSelectionBinding(
            rowData: rowData, model: model, actionID: props.actionID,
            windowUUID: windowUUID, viewID: element.id
        )

        return SwiftUI.Table(rowData, selection: selectionBinding) {
            SwiftUI.TableColumnForEach(columnData) { column in
                SwiftUI.TableColumn(column.name) { row in
                    let value = column.id < row.values.count ? row.values[column.id] : ""
                    let colType = column.id < columnTypes.count ? columnTypes[column.id] : Props.ColumnType([:])
                    let viewType = colType.viewType
                    let dataInterpretation = colType.dataInterpretation
                    let actionContext = colType.actionContext
                    // Extract the button actionID here so the Button's main-actor action closure
                    // captures only this String?, not the whole column entry.
                    let buttonActionID = colType.actionID
                    let toggleStyle = colType.toggleStyle
                    let disabledColumn = colType.disabledColumn
                    SwiftUI.Group {
                        switch viewType {
                        case .toggle:
                            TableToggleCell(
                                isOn: TemplateHelper.rowBool(value) ?? false,
                                style: toggleStyle,
                                isDisabled: disabledColumn.map { $0 <= row.values.count && TemplateHelper.rowBool(row.values[$0 - 1]) == true } ?? false
                            ) { newValue in
                                Table.commitCellToggle(
                                    newValue, drawnRow: row.values,
                                    rowIndex: rowData.firstIndex(where: { $0.id == row.id }) ?? -1,
                                    column: column.id, actionID: buttonActionID,
                                    windowUUID: windowUUID, viewID: element.id
                                )
                            }
                        case .text:
                            SwiftUI.Text(value)
                        case .button:
                            SwiftUI.Button {
                                if let buttonActionID {
                                    let context: Any = {
                                        switch actionContext {
                                        case .rowIndex: return rowData.firstIndex(where: { $0.id == row.id }) ?? -1
                                        case .columnIndex: return column.id
                                        case .rowColumnIndex: return Point(row: rowData.firstIndex(where: { $0.id == row.id }) ?? -1, column: column.id)
                                        case .title: return value
                                        }
                                    }()
                                    ActionUIModel.shared.actionHandler(buttonActionID, windowUUID: windowUUID, viewID: element.id, viewPartID: column.id, context: context)
                                }
                            } label: {
                                if let dataInterpretation {
                                    SwiftUI.Image(from: value, interpretation: dataInterpretation.rawValue)
                                } else {
                                    SwiftUI.Text(value)
                                }
                            }
                        case .image:
                            SwiftUI.Image(from: value, interpretation: (dataInterpretation ?? .systemName).rawValue)
                        case .asyncImage:
                            SwiftUI.AsyncImage(url: URL(string: value)) { image in
                                image.resizable().scaledToFit()
                            } placeholder: {
                                SwiftUI.ProgressView()
                            }
                        }
                    }
                }
                .width(min: column.minWidth, ideal: column.idealWidth, max: column.maxWidth)
            }
        }
        .tableColumnHeaders(columnHeadersVisibility)
        // Double-click handling. A plain .onTapGesture(count: 2) on a Table never
        // fires for row clicks on macOS — the rows consume the mouse events for
        // selection. The collection's own primaryAction is the supported double-click
        // (and Return-key) hook, so route doubleClickActionID through it instead.
        .contextMenu(forSelectionType: String.self) { _ in
            // No context-menu items: this modifier is used only for its primaryAction.
        } primaryAction: { ids in
            if let doubleClickActionID = props.doubleClickActionID,
               let firstID = ids.first,
               let index = rowData.firstIndex(where: { $0.id == firstID }) {
                // Keep selection/value in sync for env export, with the row as it is now.
                let current = model.states["content"] as? [[String]] ?? []
                model.value = ActionUIModel.reconciledSelection(rowData[index].values, from: rowData.map(\.values), to: current)
                ActionUIModel.shared.actionHandler(doubleClickActionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0, context: index)
            }
        }
        #else
        return SwiftUI.EmptyView()
        #endif
    }
    
    /// A user toggle of a Toggle cell: writes "true" or "false" into that cell of the rows
    /// (the selection follows its row), then fires the column's `actionID` with the column
    /// as `viewPartID` and the row index as context, the Button cell's "rowIndex" convention.
    /// Returns whether the toggle was taken (false when the row is gone).
    @discardableResult
    static func commitCellToggle(
        _ isOn: Bool,
        drawnRow: [String],
        rowIndex: Int,
        column: Int,
        actionID: String?,
        windowUUID: String,
        viewID: Int
    ) -> Bool {
        guard let index = TemplateHelper.writeRowCell(
            windowUUID: windowUUID, containerID: viewID, drawnRow: drawnRow,
            rowIndex: rowIndex, column: column, text: TemplateHelper.rowBoolText(isOn)
        ) else { return false }
        if let actionID {
            ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: viewID, viewPartID: column, context: index)
        }
        return true
    }

    /// The Table's selection binding, by row id ("row-<index>") into `rowData`, the rows this
    /// render draws. The value is the selected row's columns (`[]` when nothing is selected);
    /// the user's changes, a deselect included, go through `SelectionListHelper.commitRowSelection`,
    /// which fires `actionID` and takes the row as it is in the current rows.
    static func makeSelectionBinding(
        rowData: [TableRowData],
        model: ViewModel,
        actionID: String?,
        windowUUID: String,
        viewID: Int
    ) -> Binding<Set<String>> {
        let drawnRows = rowData.map(\.values)
        return mainActorBinding(
            get: {
                guard let selectedRow = model.value as? [String],
                      !selectedRow.isEmpty,
                      let matchingRow = rowData.first(where: { $0.values == selectedRow }) else {
                    return Set<String>()
                }
                return Set([matchingRow.id])
            },
            set: { newSet in
                // Enforce single selection (take the first if several arrive).
                let clicked: [String]
                if let rowID = newSet.first {
                    guard let row = rowData.first(where: { $0.id == rowID }) else { return }
                    clicked = row.values
                } else {
                    clicked = []
                }
                SelectionListHelper.commitRowSelection(
                    clicked, drawnRows: drawnRows, model: model,
                    actionID: actionID, windowUUID: windowUUID, viewID: viewID
                )
            }
        )
    }
}
