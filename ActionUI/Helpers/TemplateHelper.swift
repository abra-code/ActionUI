// Helpers/TemplateHelper.swift
/*
 TemplateHelper provides shared infrastructure for data-driven template containers.

 When a container view (VStack, HStack, List, etc.) declares a "template" subview key instead of
 "children", it renders one instance of the template per row in states["content"] ([[String]]).

 Column reference syntax in template string properties:
   $0  — all columns joined with ", "
   $1  — column 0 (first column)
   $2  — column 1 (second column)
   $N  — column N-1

 Action convention for Button elements inside a template:
   actionID   — as declared in template
   viewID     — the parent container's id (via TemplateContext.parentID)
   viewPartID — 0-based row index (via TemplateContext.rowIndex)
   context    — nil (host retrieves row via getElementRows if needed)

 Rendering:
   All template views are rendered through the standard ActionUI registry pipeline
   (validateProperties → buildView → applyViewModifiers) using throw-away ViewModels
   with TemplateContext set. This gives template instances the same property, modifier,
   and view-building support as regular ActionUI views — no special-casing required.

   Button checks model.templateContext for action dispatch override.
   Container views (HStack, VStack, ZStack) check model.templateContext to render
   their children via TemplateHelper instead of ActionUIView.
*/

import SwiftUI
import Foundation

@MainActor
struct TemplateHelper {

    /// Matches a column reference `$N` (one or more digits). Used for single-pass,
    /// multi-digit-safe substitution (see `substituteString`).
    nonisolated static let columnRefRegex = try! NSRegularExpression(pattern: "\\$([0-9]+)")

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
        let ns = str as NSString
        let matches = columnRefRegex.matches(in: str, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return str }

        var result = ""
        var cursor = 0
        for match in matches {
            let whole = match.range
            result += ns.substring(with: NSRange(location: cursor, length: whole.location - cursor))
            let digits = ns.substring(with: match.range(at: 1))
            if let n = Int(digits) {
                if n == 0 {
                    result += row.joined(separator: ", ")
                } else if n >= 1 && n <= row.count {
                    result += row[n - 1]
                } else {
                    result += ns.substring(with: whole) // out of range: leave literal
                }
            } else {
                result += ns.substring(with: whole)
            }
            cursor = whole.location + whole.length
        }
        result += ns.substring(with: NSRange(location: cursor, length: ns.length - cursor))
        return result
    }

    // MARK: - Template View Building

    /// Build a SwiftUI view from a template element and a single data row using
    /// the full ActionUI registry pipeline.
    ///
    /// A throw-away ViewModel is created with TemplateContext set, enabling:
    /// - Button to dispatch actions with parentID/rowIndex
    /// - Container views to render children via TemplateHelper
    /// - All registered view types to work with full property and modifier support
    ///
    /// - Parameters:
    ///   - template:    The template element (from subviews["template"] or a child thereof)
    ///   - row:         Column strings for this row
    ///   - rowIndex:    0-based row index; used as viewPartID in action dispatch
    ///   - parentID:    The owning container's element id; used as viewID in action dispatch
    ///   - windowUUID:  Window identifier
    ///   - logger:      Logger instance
    /// - Returns: A rendered SwiftUI view wrapped in AnyView
    static func buildTemplateView(
        template: any ActionUIElementBase,
        row: [String],
        rowIndex: Int,
        parentID: Int,
        windowUUID: String,
        logger: any ActionUILogger
    ) -> AnyView {
        let substitutedProps = substituteProperties(template.properties, row: row)

        let vm = ViewModel()
        vm.templateContext = TemplateContext(parentID: parentID, rowIndex: rowIndex, row: row)

        let registry = ActionUIRegistry.shared
        let validated = registry.validateProperties(
            forElementType: template.type, properties: substitutedProps
        )
        let view = registry.buildView(
            for: template, model: vm, windowUUID: windowUUID, validatedProperties: validated
        )
        return registry.applyViewModifiers(
            to: view, properties: validated, element: template, model: vm, windowUUID: windowUUID
        )
    }
}
