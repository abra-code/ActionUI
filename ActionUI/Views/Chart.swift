// Sources/Views/Chart.swift
/*
 Sample JSON for Chart:
 {
   "type": "Chart",
   "id": 10,             // Required when the chart is replaced or fed at runtime (setElementProperty, rows)
   "properties": {
     "chart": {          // Optional: the chart description. Absent = an empty plot area.
                         //   Replace it whole at runtime with setElementProperty(10, "chart", {...}).
       "columns": ["week", "platform", { "name": "users", "type": "number" }],
                         // Optional: names and types of the row cells. An item is a name or {"name", "type"};
                         //   types: "string", "number", "integer", "date"; a bare name is a string column. Names are
                         //   identifiers (letters, digits, _).
       "data": [["2026-08-03", "iOS", 1180], ["2026-08-03", "macOS", 790]],
                         // Optional: inline rows (strings, numbers, booleans, null). Setting a description that
                         //   has "data" replaces the chart's rows with it, at load and at runtime; a description
                         //   without "data" keeps the rows. The stored description keeps no "data".
       "content": [      // The marks, in Swift Charts' vocabulary
         { "type": "ForEach", "content": [  // Draws its content once per row
           { "type": "LineMark",            // "BarMark" or "LineMark", each with "x" and "y"
             "x": { "label": "Week", "value": "$week", "type": "date", "unit": "weekOfYear" },
             "y": { "label": "Users", "value": "$users" },
             "foregroundStyle": { "by": { "label": "Platform", "value": "$platform" } } } // or a color: "blue"
         ] },
         { "type": "BarMark", "x": { "label": "Goal", "value": "Goal" }, "y": { "label": "Users", "value": 1500 } }
       ],
       "chartXScale": { "domain": [0, 100] },  // Optional: two numbers or two dates (a range), a list of strings
                                              //   (categories), or {"automatic": {"includesZero": false, "reversed": true}}
       "chartYScale": { "domain": { "automatic": { "includesZero": true } } },
       "chartXAxis": "automatic",             // Optional: "automatic" | "visible" | "hidden"; also chartYAxis
       "chartXAxisLabel": "Week",             // Optional: axis title; also chartYAxisLabel
       "chartLegend": "automatic"             // Optional: "automatic" | "visible" | "hidden", or {"position": "bottom"}
     }
   }
   // Plottable values: {"label": text, "value": v, "type": optional, "unit": optional}.
   //   Inside a ForEach, "$N" (1-based) or "$name" reads that cell of each row. Every column reference needs
   //   a type, from its column or the value's own "type" (which wins); an untyped one is plotted as text.
   //   Outside a ForEach, and when it names no column, a "$..." string is literal text (with a warning
   //   unless the value has "type": "string").
   //   A literal number is "number" (or "integer" with "type": "integer"); a literal string is "string"
   //   (or a date with "type": "date" or a "unit").
   //   "unit" is year | quarter | month | weekOfYear | weekOfMonth | day | hour | minute | second (dates).
   //   Dates are ISO 8601: "YYYY-MM-DD" is a calendar day; a zone designator ("Z", "+hh:mm") makes an instant.
   // One axis plots one type: number and integer may share an axis; a mark plotting another type is dropped.
   // A row whose referenced cell does not parse under its type is skipped, with one warning.
   // Note: Baseline View properties (padding, hidden, frame, background, opacity, animation, accessibility...)
   //   are inherited and applied via ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties).
   //   Without "value", the baseline "animation" modifier animates every property set, a replaced description included.
 }
 Observable state:
   states["content"]   [[String]]   The chart's data rows (getElementRows / setElementRows / appendElementRows /
                                    clearElementRows). Changing the rows never changes the description.
*/

import SwiftUI
import Charts

struct Chart: ActionUIViewConstruction {
    static var valueType: Any.Type = Void.self
    static var initialValue: (ViewModel) -> Any? = { model in model.value }
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = nil
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = nil
    static var insertableContainers: [String: ContainerShape]? = nil

    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        var validatedProperties = properties
        guard let description = properties["chart"] else {
            return validatedProperties
        }
        guard let object = description as? [String: Any] else {
            logger.log("Chart 'chart' must be an object (the chart description); ignoring", .warning)
            validatedProperties["chart"] = nil
            return validatedProperties
        }
        // A description set at runtime has not been through the document's platform filter.
        let filtered = PlatformFilter(active: PlatformFilter.runtimeActiveSet, logger: logger).filter(object) as? [String: Any] ?? object
        validatedProperties["chart"] = ChartDescription.parse(filtered, logger: logger).cleaned
        return validatedProperties
    }

    // Load (and insertElement, subview and modal loads): the description's inline data becomes the rows.
    static var initialStates: (ViewModel) -> [String: Any] = { model in
        var states = model.states
        if let rows = takeInlineData(model) {
            states["content"] = rows
        } else if states["content"] == nil {
            states["content"] = [] as [[String]]
        }
        return states
    }

    // Runtime replacement: setElementProperty has stored and validated the new description.
    static var didSetProperty: ((String, ViewModel, any ActionUILogger) -> Void)? = { name, model, _ in
        guard name == "chart", let rows = takeInlineData(model) else { return }
        model.states["content"] = rows
    }

    // Moves the validated description's `data` into row strings and removes it from the
    // description, so the stored description never holds stale data: reading it back and
    // setting it again cannot wipe rows a host streamed in.
    @MainActor
    private static func takeInlineData(_ model: ViewModel) -> [[String]]? {
        guard var description = model.validatedProperties["chart"] as? [String: Any],
              let data = description["data"] as? [Any] else { return nil }
        description["data"] = nil
        model.validatedProperties["chart"] = description
        return ChartDescription.rowStrings(data)
    }

    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        let cache: ChartRenderCache
        if let existing = model.elementCache as? ChartRenderCache {
            cache = existing
        } else {
            cache = ChartRenderCache()
            model.elementCache = cache
        }
        let description = properties["chart"] as? [String: Any] ?? [:]
        let rows = model.states["content"] as? [[String]] ?? []
        let rendered = cache.render(description: description, rows: rows, viewID: element.id, logger: logger)
        let items = rendered.items
        return Charts.Chart(items.indices, id: \.self) { items[$0] }
            .chartModifiers(rendered.spec)
    }

    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, _, _ in
        view
    }
}

// Parsed description, typed rows and built marks, each reused while its inputs are unchanged:
// a body re-run for an unrelated reason rebuilds nothing. Rows are compared by value because the
// rows setters do not bump the view model's mutation token.
@MainActor
final class ChartRenderCache {
    private var description: NSDictionary?
    private var spec = ChartSpec()
    private var rows: [[String]]?
    private var items: [AnyChartContent] = []
    // Times the marks were built; lets tests see that unchanged inputs rebuild nothing.
    private(set) var buildCount = 0

    func render(description newDescription: [String: Any], rows newRows: [[String]], viewID: Int,
                logger: any ActionUILogger) -> (spec: ChartSpec, items: [AnyChartContent]) {
        let descriptionObject = newDescription as NSDictionary
        let descriptionChanged = description.map { !$0.isEqual(to: newDescription) } ?? true
        if descriptionChanged {
            // Already validated: parse without logging.
            spec = ChartDescription.parse(newDescription, logger: nil).spec
            description = descriptionObject
        }
        if descriptionChanged || rows != newRows {
            let columns = ChartTypedColumns(rows: newRows, refs: spec.referencedColumns)
            var builder = ChartContentBuilder(columns: columns)
            items = builder.build(spec.content)
            buildCount += 1
            rows = newRows
            if builder.skippedRows > 0, let first = builder.firstSkip {
                logger.log("Chart \(viewID): skipped \(builder.skippedRows) row(s) with a cell that does not parse; first: row \(first.row + 1), column \(first.column + 1) is not a \(first.type.rawValue)", .warning)
            }
        }
        return (spec, items)
    }
}
