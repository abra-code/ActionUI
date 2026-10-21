// Core/Helpers/TemplateHelper.swift
/*
 TemplateHelper provides shared infrastructure for data-driven template containers.

 When a container view (VStack, HStack, List, etc.) declares a "template" subview key instead of
 "children", it renders one instance of the template per row in states["content"] ([[String]]).

 Column reference syntax in template string properties:
   $0  - all columns joined with ", "
   $1  - column 0 (first column)
   $2  - column 1 (second column)
   $N  - column N-1

 Action convention for Button and Toggle elements inside a template:
   actionID   - as declared in template
   viewID     - the parent container's id (via TemplateContext.parentID)
   viewPartID - 0-based row index (via TemplateContext.rowIndex)
   context    - Button: nil (host retrieves row via getElementRows if needed)
                Toggle: the new Bool

 Boolean properties from row data:
   "isOn", "disabled" and "hidden" written as a string in a template are read as a
   Bool after substitution (see rowBool): "true" or "1" is on, "false", "0" or an
   empty string is off, in any letter case. Any other text is off, with one warning.

 Row-bound Toggle:
   The row data is the source of truth for a Toggle in a template. When its "isOn"
   is exactly one column reference ("$N"), a user toggle writes "true" or "false"
   into that column of that row in the container's states["content"] and then fires
   the Toggle's actionID, so a handler that reads the rows sees the new value. Any
   other "isOn" leaves the Toggle display-only. The same write serves a Table's
   Toggle column (see writeRowCell).

 Rendering:
   All template views are rendered through the standard ActionUI registry pipeline
   (buildView, then applyViewModifiers) using throw-away ViewModels
   with TemplateContext set. This gives template instances the same property, modifier,
   and view-building support as regular ActionUI views - no special-casing required.

   (The view building is in Helpers/TemplateHelper+SwiftUI.swift.)

   Button and Toggle check model.templateContext for action dispatch override.
   Container views (HStack, VStack, ZStack) check model.templateContext to render
   their children via TemplateHelper instead of ActionUIView.
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

@MainActor
struct TemplateHelper {

    /// Matches a column reference `$N` (one or more ASCII digits). Used for single-pass,
    /// multi-digit-safe substitution (see `substituteString`). Matched by Unicode scalar, as
    /// NSRegularExpression matched: a digit followed by a combining mark still ends a reference,
    /// and a "$" after a prepended character (U+0600) still starts one.
    nonisolated(unsafe) static let columnRefRegex = /\$([0-9]+)/.matchingSemantics(.unicodeScalar)

    // MARK: - Column Substitution

    /// Recursively substitute $0, $1, $2 ... in all String property values.
    /// - $0: all columns joined with ", "
    /// - $1..$N: 1-based column index mapping to row[N-1]
    static func substituteProperties(_ properties: [String: Any], row: [String]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, value) in properties {
            result[key] = substituteValue(value, row: row)
        }
        return result
    }

    private static func substituteValue(_ value: Any, row: [String]) -> Any {
        switch value {
        case let str as String:
            return substituteString(str, row: row)
        case let dict as [String: Any]:
            return substituteProperties(dict, row: row)
        default:
            return value
        }
    }

    /// Substitute `$0`/`$1`/`$N` column references in `str` against `row`.
    ///
    /// Substitution is single-pass and multi-digit-safe: one regex sweep replaces
    /// every `$N`, so a column value that itself contains `$2` is not re-substituted,
    /// and `$12` reads as column 12 (not `$1` followed by a literal `2`). `$0` joins
    /// all columns with ", "; an out-of-range `$N` is left as literal text. This
    /// matches the Android and Web hosts (both regex-based); the previous ordered
    /// `replacingOccurrences` loop corrupted `$10`+ because `$1` matched inside `$10`.
    static func substituteString(_ str: String, row: [String]) -> String {
        str.replacing(columnRefRegex) { match -> String in
            guard let n = Int(match.output.1) else {
                return String(match.output.0)
            }
            if n == 0 {
                return row.joined(separator: ", ")
            }
            if n >= 1 && n <= row.count {
                return row[n - 1]
            }
            return String(match.output.0) // out of range: leave literal
        }
    }

    // MARK: - Boolean Row Data

    /// The properties a template may give as a string, read as a Bool after substitution.
    nonisolated static let rowBoolKeys = ["isOn", "disabled", "hidden"]

    /// Reads row text as a Bool: "true" or "1" is on, "false", "0" or an empty string is
    /// off, in any letter case. Returns nil for any other text (the caller treats it as off).
    /// The same rule on every host.
    nonisolated static func rowBool(_ text: String) -> Bool? {
        switch text.lowercased() {
        case "true", "1": return true
        case "false", "0", "": return false
        default: return nil
        }
    }

    /// The text a toggled cell stores.
    nonisolated static func rowBoolText(_ flag: Bool) -> String {
        flag ? "true" : "false"
    }

    /// The 0-based column a property names when it is exactly one column reference
    /// ("$N", N of 1 or more), else nil. "$0" (all columns) and text around a reference
    /// do not name one column.
    nonisolated static func singleColumnIndex(_ value: Any?) -> Int? {
        guard let str = value as? String,
              let match = str.wholeMatch(of: columnRefRegex),
              let n = Int(match.output.1), n >= 1 else { return nil }
        return n - 1
    }

    /// The properties of one template instance: the template's properties with the column
    /// references substituted from `row`, and the Boolean properties written as a string
    /// (`rowBoolKeys`) read from the row as a Bool.
    static func instanceProperties(
        of template: any ActionUIElementBase,
        row: [String],
        logger: any ActionUILogger
    ) -> [String: Any] {
        var properties = substituteProperties(template.properties, row: row)
        for key in rowBoolKeys where template.properties[key] is String {
            guard let text = properties[key] as? String else { continue }
            if let flag = rowBool(text) {
                properties[key] = flag
            } else {
                properties[key] = false
                warnOnce("\(template.type) \(key) '\(text)' in a template row is not a Boolean (true, false, 1, 0 or empty); treating as false", logger: logger)
            }
        }
        return properties
    }

    private static var warnedMessages = Set<String>()

    /// Logs a warning the first time it is seen: a template renders once per row on every
    /// refresh, so a per-row warning would otherwise repeat without end.
    static func warnOnce(_ message: String, logger: any ActionUILogger) {
        guard warnedMessages.insert(message).inserted else { return }
        logger.log(message, .warning)
    }

    // MARK: - Row Write-back

    /// The current index of a row a control was drawn for. A host may have replaced the
    /// rows between the render and the click: the row is taken at its drawn index when it
    /// is still there, else at the first place an equal row is found, else it is gone (nil).
    static func currentRowIndex(of drawnRow: [String], drawnAt rowIndex: Int, in rows: [[String]]) -> Int? {
        if rows.indices.contains(rowIndex), rows[rowIndex] == drawnRow {
            return rowIndex
        }
        return rows.firstIndex(of: drawnRow)
    }

    /// Writes `text` into one cell of a container's states["content"] after a user edit of
    /// a row-bound control (a Toggle in a template row or in a Table column). A row shorter
    /// than `column` is padded with empty strings. A selection resting on that row follows
    /// it, so the write loses no highlight and fires no selection action.
    /// Returns the index of the row written, or nil when the container or the row is gone.
    @discardableResult
    static func writeRowCell(
        windowUUID: String,
        containerID: Int,
        drawnRow: [String],
        rowIndex: Int,
        column: Int,
        text: String
    ) -> Int? {
        guard column >= 0,
              let model = ActionUIModel.shared.windowModels[windowUUID]?.viewModels[containerID] else { return nil }
        var rows = model.states["content"] as? [[String]] ?? []
        guard let index = currentRowIndex(of: drawnRow, drawnAt: rowIndex, in: rows) else { return nil }
        let oldRow = rows[index]
        var newRow = oldRow
        while newRow.count <= column {
            newRow.append("")
        }
        newRow[column] = text
        rows[index] = newRow
        model.states["content"] = rows
        if let selected = model.value as? [String], !selected.isEmpty, selected == oldRow {
            model.value = newRow
        }
        return index
    }

    /// A user toggle of a Toggle in a template row: writes the new state into the row
    /// (when `column` names one) and then fires `actionID` with the container's id, the
    /// row index and the new Bool. Without a column the Toggle is display-only and nothing
    /// happens. Returns whether the toggle was taken.
    @discardableResult
    static func commitRowToggle(
        _ isOn: Bool,
        context: TemplateContext,
        column: Int?,
        actionID: String?,
        windowUUID: String
    ) -> Bool {
        guard let column,
              let index = writeRowCell(
                windowUUID: windowUUID, containerID: context.parentID, drawnRow: context.row,
                rowIndex: context.rowIndex, column: column, text: rowBoolText(isOn)
              ) else { return false }
        if let actionID {
            ActionUIModel.shared.actionHandler(
                actionID, windowUUID: windowUUID, viewID: context.parentID, viewPartID: index, context: isOn
            )
        }
        return true
    }
}
