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
       "content": [      // ForEach, Plot and the marks, in Swift Charts' vocabulary
         { "type": "ForEach", "content": [  // Draws its content once per row
           { "type": "Plot",                // Groups marks; its modifiers apply to each mark inside
             "foregroundStyle": { "by": { "label": "Platform", "value": "$platform" } }, // or a color: "blue"
             "content": [
               { "type": "LineMark",
                 "x": { "label": "Week", "value": "$week", "type": "date", "unit": "weekOfYear" },
                 "y": { "label": "Users", "value": "$users" },
                 "interpolationMethod": "catmullRom" },
               { "type": "PointMark",
                 "x": { "label": "Week", "value": "$week", "type": "date", "unit": "weekOfYear" },
                 "y": { "label": "Users", "value": "$users" } }
             ] }
         ] },
         { "type": "RuleMark", "y": { "label": "Goal", "value": 1500 }, "lineStyle": { "lineWidth": 1, "dash": [4, 3] } }
       ],
       "chartXScale": { "domain": [0, 100] },  // Optional: "domain": two numbers or two dates (a range), a list of strings
                                              //   (categories), or {"automatic": {"includesZero": false, "reversed": true}};
                                              //   "range": {"startPadding", "endPadding"}, {"padding"} or two numbers (points);
                                              //   "type": "linear" | "log" | "date" | "category" | "squareRoot" | "symmetricLog" |
                                              //   {"power": {"exponent": 2}} | {"symmetricLog": {"slopeAtZero": 1}}. On a number axis
                                              //   "log", "squareRoot" and "power" need a "domain" inside theirs (log: low end above 0);
                                              //   "date" and "category" never apply to a number or date axis (Swift Charts stops the app).
                                              //   Marks beyond a fixed domain (stacked bars add up) draw outside the plot area;
                                              //   chartPlotStyle {"clipShape": "rectangle"} cuts them off
       "chartYScale": { "domain": { "automatic": { "includesZero": true } } },
       "chartForegroundStyleScale": { "domain": ["iOS", "macOS"], "range": ["blue", "orange"] },
                                              // Optional style scales, each {"domain", "range"}: the domain is typed by the
                                              //   {"by"} values the scale styles (a list of strings, two numbers or dates, or
                                              //   {"automatic": {...}}). Ranges: chartForegroundStyleScale a list of colors or
                                              //   {"gradient": [colors]}; chartSymbolScale a list of symbol names;
                                              //   chartLineStyleScale a list of stroke styles; chartSymbolSizeScale two numbers,
                                              //   the smallest and largest symbol area
       "chartXAxis": "automatic",             // Optional: "automatic" | "visible" | "hidden", or up to 4 AxisMarks (below);
                                              //   also chartYAxis
       "chartYAxis": [
         { "type": "AxisMarks", "preset": "automatic", "position": "leading",
           "values": [0, 500, 1000, 1500],    // "automatic", {"automatic": {"desiredCount" (1 to 100), "roundLowerBound",
                                              //   "roundUpperBound"}}, {"stride": {"by": "month", "count": 1}} (a calendar unit, dates),
                                              //   {"stride": {"by": 10}} (numbers), or a list of values typed by the axis. A stride
                                              //   that would draw more than 1000 marks over the axis falls back to "automatic"
           "format": "decimal", "fractionLength": 0, // Without "content" only: labels' format (below); "stroke" likewise
           "content": [                       // Optional: up to 4 marks; absent = Swift's default marks, [] = none
             { "type": "AxisGridLine", "centered": false, "stroke": { "lineWidth": 0.5, "dash": [2, 2] } },
             { "type": "AxisTick", "length": "automatic" }, // or a number, "label", "longestLabel", {"label": {"extendPastBy": 2}}
             { "type": "AxisValueLabel", "format": "percent", "anchor": "top", "orientation": "automatic",
               "collisionResolution": "automatic", "font": "caption", "foregroundStyle": "gray", "offset": { "x": 0, "y": 2 } }
           ] }                                // AxisValueLabel also takes "centered", "multiLabelAlignment", "offsetsMarks",
       ],                                     //   "horizontalSpacing", "verticalSpacing"; every mark takes foregroundStyle, font, offset.
                                              //   Formats: on a number axis "integer" | "decimal" | "percent" | "currency" with
                                              //   "fractionLength" (n or {"min", "max"}) and "currencyCode"; on a date axis
                                              //   {"dateTime": {"year", "quarter", "month", "day", "weekday", "hour", "minute", "second"}}
                                              //   (Date.FormatStyle symbol names) or {"date": "abbreviated", "time": "omitted"}
       "chartXAxisLabel": "Week",             // Optional: axis title, or {"text", "position", "alignment", "spacing"};
                                              //   also chartYAxisLabel
       "chartLegend": "automatic",            // Optional: "automatic" | "visible" | "hidden", or {"position": "bottom"}
       "chartPlotStyle": { "background": "gray.opacity(0.1)", "cornerRadius": 4 } // Optional: View properties for the plot area: padding,
                                              //   background, border, frame, cornerRadius, clipShape, shadow, opacity, offset, foregroundStyle
     }
   }
   // Marks: every argument is a key named like Swift's initializer argument. A plottable value is an object
   //   (below); a number means points. The keys must match one initializer:
   //   BarMark   x + y | x (+ yStart/yEnd points) | x + yStart + yEnd | (xStart/xEnd points +) y |
   //             (xStart/xEnd points +) yStart + yEnd | xStart + xEnd + y | xStart + xEnd (+ yStart/yEnd points);
   //             "width" / "height" (where the initializer has them): a number (fixed), "automatic", {"ratio"},
   //             {"inset"} or {"fixed"}; "stacking": "standard" | "normalized" | "center" | "unstacked"
   //   LineMark  x + y | x + y + series
   //   PointMark x + y | (x point +) y | x (+ y point)
   //   RuleMark  (x point +) yStart + yEnd | x (+ yStart/yEnd points) | x + yStart + yEnd | (xStart/xEnd points +) y |
   //             xStart + xEnd (+ y point) | xStart + xEnd + y
   //   AreaMark  x + y | xStart + xEnd + y | x + yStart + yEnd, each (+ series); "stacking" on x + y (+ series)
   //   RectangleMark x + y | x (+ yStart/yEnd points) | (xStart/xEnd points +) y | xStart + xEnd + y |
   //             xStart + xEnd (+ yStart/yEnd points) | x + yStart + yEnd | (xStart/xEnd points +) yStart + yEnd |
   //             xStart + xEnd + yStart + yEnd | xStart/xEnd/yStart/yEnd points; "width" / "height" as BarMark
   //   SectorMark angle (+ angularInset points); the angle is a number or integer value, each sector's share of the
   //             sum; "innerRadius" / "outerRadius" take the forms of "width" (a pie or a donut: {"ratio": 0.6})
   //   A start and its end have one type.
   // ForEach: {"type": "ForEach", "content": [...]} draws its content once per row of the chart's rows. With
   //   "data" (inline rows, as the chart's "data") it draws over those rows instead, laid out by its own
   //   "columns" when it has them, else by the chart's. A ForEach's data stays in the description (only the
   //   chart's "data" becomes the rows), so it suits fixed series such as targets next to streamed rows.
   // Plot: {"type": "Plot", "content": [...], modifiers}. Its modifiers apply to every mark inside, after the
   //   mark's own. Inside a ForEach a Plot holds marks (and Plots); outside it may also hold a ForEach, and
   //   its modifiers then read no row ("$..." is literal there, as for any mark outside a ForEach).
   // Mark modifiers (a modifier that does not apply to a mark changes nothing):
   //   "foregroundStyle": color or {"by": value}   "symbol": circle|square|triangle|diamond|pentagon|plus|cross|asterisk or {"by"}
   //   "symbolSize": area, {"width", "height"} or {"by"}   "lineStyle": {"lineWidth", "lineCap", "lineJoin", "miterLimit",
   //   "dash", "dashPhase"} or {"by"}   "interpolationMethod": linear|cardinal|catmullRom|monotone|stepStart|stepCenter|
   //   stepEnd, {"cardinal": {"tension"}} or {"catmullRom": {"alpha"}}   "position": {"by", "axis": horizontal|vertical,
   //   "span": dimension}   "cornerRadius": number or {"radius", "style": continuous|circular}   "opacity", "zIndex",
   //   "blur": number   "offset": {"x", "y"} with start/end forms for ranges   "shadow": {"radius", "color", "x", "y"}
   //   "alignsMarkStylesWithPlotArea", "accessibilityHidden": bool   "accessibilityLabel", "accessibilityValue",
   //   "accessibilityIdentifier": text, which inside a ForEach may embed "$N" / "$name" references
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
        let plotStyle = rendered.spec.plotStyle
        // View.applyModifiers also draws the element's own background, overlay and safeAreaInset
        // subviews, which the chart as a whole already has: the plot area gets an element
        // without subviews.
        let plotElement = ActionUIElement(id: element.id, type: element.type, properties: plotStyle, subviews: nil)
        return Charts.Chart(items.indices, id: \.self) { items[$0] }
            .chartModifiers(rendered.spec, plotStyle: plotStyle.isEmpty ? nil : { plot in
                AnyView(View.applyModifiers(plot, plotElement, windowUUID, plotStyle, logger))
            })
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
    // The spec as drawn: axis strides that would draw too many marks fall back to automatic
    // values, which depends on the rows (ChartAxisStrideLimit).
    private var drawnSpec = ChartSpec()
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
                let place = first.inlineData ? "row \(first.row + 1) of a ForEach's data" : "row \(first.row + 1)"
                logger.log("Chart \(viewID): skipped \(builder.skippedRows) row(s) with a cell that does not parse; first: \(place), column \(first.column + 1) is not a \(first.type.rawValue)", .warning)
            }
            drawnSpec = spec
            drawnSpec.x.marks = ChartAxisStrideLimit.limited(spec.x.marks, domain: spec.x.domain, extent: builder.xExtent,
                                                             key: "chartXAxis", viewID: viewID, logger: logger)
            drawnSpec.y.marks = ChartAxisStrideLimit.limited(spec.y.marks, domain: spec.y.domain, extent: builder.yExtent,
                                                             key: "chartYAxis", viewID: viewID, logger: logger)
        }
        return (drawnSpec, items)
    }
}
