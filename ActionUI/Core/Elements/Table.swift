// Core/Elements/Table.swift
/*
 Sample JSON for Table view (macOS, Linux, Android and Web; an empty view on iOS):
 {
   "type": "Table",
   "id": 1,              // Required: Non-zero positive integer for runtime programmatic interaction and diffing
   "properties": {
     "columns": ["Name", "Action", "Icon"], // Required: Array of strings for column headers
     "columnHeadersVisibility": "hidden",   // Optional: column headers visibility: "automatic", "hidden", "visible"
     "columnTypes": [                       // Optional: Per-column type config array. Defaults to all Text.
       { "viewType": "Text" },              // Each entry: { "viewType": "Text"|"Button"|"Image"|"AsyncImage"|"Toggle"
       { "viewType": "Button",              // Columns without an entry default to Text.
         "actionContext": "rowIndex",       // "actionContext": "title"|"rowIndex"|"columnIndex"|"rowColumnIndex" (Button only)
         "actionID": "row.action" },        // "actionID": "..." (Button only — fires on button click) }
       { "viewType": "Image",
         "dataInterpretation": "systemName" }, // "dataInterpretation": "path"|"systemName"|"assetName"|"resourceName"|"mixed" (Image & Button)
       { "viewType": "Toggle",              // A checkbox per row. The cell text is its state: "true" or "1" is on, "false", "0" or empty is off (any letter case).
         "style": "checkbox",               // "style": "checkbox" (default)|"switch"|"button" (Toggle only)
         "actionID": "row.toggled",         // "actionID": "..." (Toggle only - fires on a user toggle, after the cell is written; viewPartID = column index, context = row index)
         "disabledColumn": 4 }              // "disabledColumn": 1-based column number (hidden columns included) whose text, read the same way, disables the cell for that row (Toggle only)
     ],
     "widths": [100, 80, 40],               // Optional: Array of integers for ideal column widths (resizable; last column fills remaining space)
     "minWidths": [80, 60, 30],             // Optional: Array of integers for minimum column widths in points; columns cannot be resized below these. Missing entries default to 10.
     "actionID": "table.selection.changed", // Optional: Fires on selection change (all cell types)
     "doubleClickActionID": "table.double.click" // Optional: String for double-click action (context = row index)
   }
 }
   // Note: The Table view shows a multi-column table with per-column cell types specified by the columnTypes array. If columnTypes is omitted or shorter than columns, missing entries default to Text. Selection is stored as [String] in state["value"] (the selected row's columns) and highlights the row with those columns. A rows change keeps the selection on its row (an equal row, else the row with the same first column, the same one among several, with its new columns), or clears it; no actionID fires. The table-level actionID fires on every selection change the user makes, a deselect included. Button columns have their own actionID in their columnTypes entry, fired on click - this cleanly separates selection events from button click events. A Toggle column shows a checkbox with no title (the column header names it); a user toggle writes "true" or "false" into that cell of states["content"], keeps the selection where it was, and then fires the entry's actionID with viewPartID = the column index and context = the row index, so a handler reads the new state from the rows. Toggling does not select the row and does not fire the table-level actionID; a rows change made by the host fires nothing. Baseline View properties (padding, hidden, foregroundStyle, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties). The applyModifiers implementation is provided by the ActionUIViewConstruction protocol extension. SwiftUI types are explicitly prefixed (e.g., SwiftUI.Table, SwiftUI.TableColumn) to avoid namespace conflicts. Uses TableColumnForEach for dynamic columns.
   // Performance: Child views are strongly typed to avoid AnyView overhead, identified by stable indices in ForEach, optimizing SwiftUI diffing for large tables (e.g., 1000 rows x 50 columns). Image creation uses SwiftUI.Image extension, aligned with Image.swift, to minimize overhead. Ensure state updates are targeted to minimize re-renders.

 Observable state:
   value ([String])                    Selected row as an array of column strings (first column = display value).
                                       Access via getElementValue / setElementValue. Select a row
                                       programmatically (without replacing rows, firing no actionID) via
                                       selectElementRow(index:), selectElementRow(matching:column:), or
                                       clearElementSelection.
   states["content"]   [[String]]      All table rows; each inner array holds one row's column values.
                                       Access via getElementRows / setElementRows / appendElementRows /
                                       clearElementRows / getElementColumnCount.
 */

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension Table {
    /// Table's properties, parsed from the raw dictionary. Built at the start of every render.
    struct Props: Sendable {
        /// The cell of a column (columnTypes[i].viewType). An unknown name, or none, is Text.
        enum ViewType: String, Sendable, CaseIterable {
            case text = "Text", button = "Button", image = "Image", asyncImage = "AsyncImage", toggle = "Toggle"
        }

        /// How an Image or Button cell reads its row text (columnTypes[i].dataInterpretation).
        enum DataInterpretation: String, Sendable, CaseIterable {
            case path, systemName, assetName, resourceName, mixed
        }

        /// What a Button cell passes as its action's context (columnTypes[i].actionContext).
        enum ActionContext: String, Sendable, CaseIterable {
            case title, rowIndex, columnIndex, rowColumnIndex
        }

        /// A Toggle cell's look (columnTypes[i].style).
        enum ToggleStyle: String, Sendable, CaseIterable {
            case checkbox, `switch`, button
        }

        enum HeadersVisibility: String, Sendable, CaseIterable {
            case visible, hidden, automatic
        }

        /// One entry of columnTypes.
        struct ColumnType: Equatable, Sendable {
            var viewType = ViewType.text
            /// Image: always set, systemName when missing or unknown. Button: set only when given and
            /// known, which makes it an image-only button. Other cells: not read.
            var dataInterpretation: DataInterpretation?
            /// Button only.
            var actionContext = ActionContext.title
            /// Button and Toggle: the action of a click or a user toggle.
            var actionID: String?
            /// Toggle only.
            var toggleStyle = ToggleStyle.checkbox
            /// Toggle only: the 1-based number of the column whose text disables the cell. Below 1 is none.
            var disabledColumn: Int?

            init(_ raw: [String: Any]) {
                viewType = (raw["viewType"] as? String).flatMap(ViewType.init(rawValue:)) ?? .text
                dataInterpretation = (raw["dataInterpretation"] as? String).flatMap(DataInterpretation.init(rawValue:))
                if viewType == .image && dataInterpretation == nil {
                    dataInterpretation = .systemName
                }
                actionContext = (raw["actionContext"] as? String).flatMap(ActionContext.init(rawValue:)) ?? .title
                actionID = raw["actionID"] as? String
                toggleStyle = (raw["style"] as? String).flatMap(ToggleStyle.init(rawValue:)) ?? .checkbox
                disabledColumn = (raw["disabledColumn"] as? Int).flatMap { $0 >= 1 ? $0 : nil }
            }
        }

        /// The column headers; a value that is not an array of strings is no columns.
        var columns: [String] = []
        /// One entry per column at least: missing entries are Text. A list with anything but
        /// dictionaries in it is no list.
        var columnTypes: [ColumnType] = []
        /// Ideal column widths in points; only an array of Int counts.
        var widths: [Int]?
        /// Minimum column widths in points; only an array of Int counts.
        var minWidths: [Int]?
        var columnHeadersVisibility: HeadersVisibility?
        /// Fires on every selection change the user makes.
        var actionID: String?
        var doubleClickActionID: String?

        init(_ properties: [String: Any]) {
            columns = properties["columns"] as? [String] ?? []
            columnTypes = (properties["columnTypes"] as? [[String: Any]] ?? []).map(ColumnType.init)
            while columnTypes.count < columns.count {
                columnTypes.append(ColumnType([:]))
            }
            widths = properties["widths"] as? [Int]
            minWidths = properties["minWidths"] as? [Int]
            columnHeadersVisibility = (properties["columnHeadersVisibility"] as? String).flatMap(HeadersVisibility.init(rawValue:))
            actionID = properties["actionID"] as? String
            doubleClickActionID = properties["doubleClickActionID"] as? String
        }
    }
}

struct Table: ActionUIElementSpec {
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = nil
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = nil
    static var insertableContainers: [String: ContainerShape]? = nil

    static var valueType: Any.Type = [String].self // Value is the selected row as [String]

    static var initialStates: (ViewModel) -> [String: Any] = { model in
        var states: [String: Any] = model.states
        if states.isEmpty {
            states["content"] = [] as [[String]]
        }
        return states
    }

    static var initialValue: (ViewModel) -> Any? = { model in
        if let initialValue = model.value as? [String] {
            return initialValue
        }
        return [] as [String]
    }
}

extension Table {
    /// Whether a Toggle cell is disabled in `row`: the text of its disabledColumn (1-based) reads
    /// as on (TemplateHelper.rowBool). A row too short for that column leaves the cell enabled.
    static func isCellDisabled(disabledColumn: Int?, row: [String]) -> Bool {
        guard let disabledColumn, disabledColumn <= row.count else { return false }
        return TemplateHelper.rowBool(row[disabledColumn - 1]) == true
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
}
