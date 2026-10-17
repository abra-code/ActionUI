// Sources/Views/Chart.swift
/*
 Sample JSON for Chart:
 {
   "type": "Chart",
   "id": 10,             // Required when the chart is replaced or fed at runtime (setElementProperty, rows) or selects
   "properties": {
     "valueChangeActionID": "chart.selected", // Optional: fires when the user changes the selection (below)
     "selectionActionTiming": "settled",      // Optional: "settled" (default): the action fires once the selection has
                                              //   rested for 150 ms, and at once when it is cleared; "continuous": on every change
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
       "chartPlotStyle": { "background": "gray.opacity(0.1)", "cornerRadius": 4 }, // Optional: View properties for the plot area: padding,
                                              //   background, border, frame, cornerRadius, clipShape, shadow, opacity, offset, foregroundStyle
       "chartXSelection": "value"             // Optional: the user selects on the x axis: "value" | "range" (a number or date
                                              //   axis); also chartYSelection;
                                              //   "chartAngleSelection": "value" selects a SectorMark. Without these keys the chart
                                              //   installs no selection gesture. Swift Charts draws nothing for a selection: draw it
                                              //   with "$selection" marks (below)
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
   // Selection marks: outside a ForEach, a plotted value "$selection" reads the selection: on x, xStart or xEnd the
   //   x selection, on y, yStart or yEnd the y selection; a range selection is read by xStart / xEnd (yStart / yEnd)
   //   as its start and end. Such a mark is drawn only while there is a selection and takes the axis's type, e.g.
   //   { "type": "RuleMark", "x": { "label": "Selected", "value": "$selection" }, "foregroundStyle": "gray.opacity(0.4)" }
   //   or a RectangleMark with "xStart" and "xEnd" "$selection" for a range. A selected category the chart does not
   //   plot is not drawn (it would add a category). Only these marks are rebuilt on a selection change.
   // One axis plots one type: number and integer may share an axis; a mark plotting another type is dropped.
   // A row whose referenced cell does not parse under its type is skipped, with one warning.
   // Note: Baseline View properties (padding, hidden, frame, background, opacity, animation, accessibility...)
   //   are inherited and applied via ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties).
   //   Without "value", the baseline "animation" modifier animates every property set, a replaced description included.
 }
 Observable state:
   value               String       The selection as a JSON string, "" when nothing is selected: {"x": "Tue"},
                                    {"x": [2.5, 7]} (a range), {"x": "2026-09-01", "y": 140}, {"angle": 51.2, "row": 1}
                                    ("row": the 0-based data row of the selected sector). Dates print as "yyyy-MM-dd" when
                                    the axis's first mark has a unit of a day or coarser, else as a local
                                    "yyyy-MM-ddTHH:mm:ss". setElementValue with the same shape selects (no action fires); a
                                    part that does not fit the axes reads as nothing selected, and a replaced description
                                    clears a selection it cannot hold.
   states["content"]   [[String]]   The chart's data rows (getElementRows / setElementRows / appendElementRows /
                                    clearElementRows). Changing the rows never changes the description.
*/

import SwiftUI
import Charts

struct Chart: ActionUIViewConstruction {
    static var valueType: Any.Type = String.self
    static var initialValue: (ViewModel) -> Any? = { model in model.value as? String ?? "" }
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = nil
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = nil
    static var insertableContainers: [String: ContainerShape]? = nil

    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        var validatedProperties = properties
        if let actionID = properties["valueChangeActionID"], !(actionID is String) {
            logger.log("Chart valueChangeActionID must be a String; ignoring", .warning)
            validatedProperties["valueChangeActionID"] = nil
        }
        if let timing = properties["selectionActionTiming"], !["settled", "continuous"].contains(timing as? String ?? "") {
            logger.log("Chart selectionActionTiming must be \"settled\" or \"continuous\"; using \"settled\"", .warning)
            validatedProperties["selectionActionTiming"] = nil
        }
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
        guard name == "chart" else { return }
        if let rows = takeInlineData(model) {
            model.states["content"] = rows
        }
        // A selection the new description cannot hold (another axis type, no such selection)
        // is cleared, so the value never reports what the chart does not show.
        if let value = model.value as? String, !value.isEmpty {
            let spec = ChartDescription.parse(model.validatedProperties["chart"] as? [String: Any] ?? [:], logger: nil).spec.selection
            let fitted = ChartSelection.decode(value, spec: spec).encode(spec: spec)
            if fitted != value {
                model.value = fitted
            }
        }
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
        let rendered = cache.render(description: description, rows: rows, selectionValue: model.value as? String ?? "",
                                    viewID: element.id, logger: logger)
        let items = rendered.items
        let plotStyle = rendered.spec.plotStyle
        // View.applyModifiers also draws the element's own background, overlay and safeAreaInset
        // subviews, which the chart as a whole already has: the plot area gets an element
        // without subviews.
        let plotElement = ActionUIElement(id: element.id, type: element.type, properties: plotStyle, subviews: nil)
        let binder = ChartSelectionBinder(model: model, spec: rendered.spec.selection, cache: cache, windowUUID: windowUUID,
                                          viewID: element.id, actionID: properties["valueChangeActionID"] as? String,
                                          continuous: properties["selectionActionTiming"] as? String == "continuous")
        return Charts.Chart(items, id: \.id) { $0.content }
            .chartModifiers(rendered.spec, plotStyle: plotStyle.isEmpty ? nil : { plot in
                AnyView(View.applyModifiers(plot, plotElement, windowUUID, plotStyle, logger))
            })
            .modifier(ChartSelector(binder: binder))
    }

    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, _, _ in
        view
    }
}

// Parsed description, typed rows and built marks, each reused while its inputs are unchanged:
// a body re-run for an unrelated reason rebuilds nothing. Rows are compared by value because the
// rows setters do not bump the view model's mutation token. Marks that read the selection
// ("$selection") are rebuilt on their own when it changes; the rest are not.
@MainActor
final class ChartRenderCache {
    // A mark with a stable identity: built marks are numbered in drawing order from 0 and
    // selection marks from -1 down, so a selection mark appearing does not renumber the others.
    struct Item {
        let id: Int
        let content: AnyChartContent
    }
    // The top-level content in drawing order (Plots flattened: their modifiers are already on
    // their marks): marks built once per description and rows, and marks that read the selection.
    private enum Segment {
        case built([AnyChartContent])
        case selection([ChartEntry])
    }

    private var description: NSDictionary?
    private var spec = ChartSpec()
    // The spec as drawn: axis strides that would draw too many marks fall back to automatic
    // values, which depends on the rows (ChartAxisStrideLimit).
    private var drawnSpec = ChartSpec()
    private var rows: [[String]]?
    private var segments: [Segment] = []
    private var selection: ChartSelection?
    private var items: [Item] = []
    private var sectorAngles: [(row: Int?, value: Double)] = []
    // The categories the built marks plot on each axis (onAxis).
    private var xCategories: Set<String> = []
    private var yCategories: Set<String> = []
    private var pendingAction: DispatchWorkItem?
    // Times the marks were built; lets tests see that unchanged inputs rebuild nothing.
    private(set) var buildCount = 0
    // Times the selection marks were built.
    private(set) var selectionBuildCount = 0

    func render(description newDescription: [String: Any], rows newRows: [[String]], selectionValue: String = "",
                viewID: Int, logger: any ActionUILogger) -> (spec: ChartSpec, items: [Item]) {
        let descriptionObject = newDescription as NSDictionary
        let descriptionChanged = description.map { !$0.isEqual(to: newDescription) } ?? true
        if descriptionChanged {
            // Already validated: parse without logging.
            spec = ChartDescription.parse(newDescription, logger: nil).spec
            description = descriptionObject
        }
        var rebuilt = false
        if descriptionChanged || rows != newRows {
            let columns = ChartTypedColumns(rows: newRows, refs: spec.referencedColumns)
            var builder = ChartContentBuilder(columns: columns)
            let runs = Self.segments(spec.content)
            builder.collectsCategories = runs.contains { $0.readsSelection }
            segments = runs.map { readsSelection, entries in
                readsSelection ? .selection(entries) : .built(builder.build(entries))
            }
            buildCount += 1
            rows = newRows
            sectorAngles = builder.sectorAngles
            (xCategories, yCategories) = (builder.xCategories, builder.yCategories)
            rebuilt = true
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
        let newSelection = ChartSelection.decode(selectionValue, spec: spec.selection)
        if rebuilt || newSelection != selection {
            selection = newSelection
            items = assemble(newSelection)
        }
        return (drawnSpec, items)
    }

    private func assemble(_ selection: ChartSelection) -> [Item] {
        var result: [Item] = []
        var builtID = 0
        var selectionID = -1
        // Selection marks read no rows.
        var builder = ChartContentBuilder(columns: ChartTypedColumns(rows: [], refs: []))
        var shown = selection
        shown.x = selection.x.flatMap { Self.onAxis($0, categories: xCategories) }
        shown.y = selection.y.flatMap { Self.onAxis($0, categories: yCategories) }
        builder.selection = shown
        for segment in segments {
            switch segment {
            case .built(let marks):
                for mark in marks {
                    result.append(Item(id: builtID, content: mark))
                    builtID += 1
                }
            case .selection(let entries):
                if shown.x != nil || shown.y != nil {
                    selectionBuildCount += 1
                    for mark in builder.build(entries) {
                        result.append(Item(id: selectionID, content: mark))
                        selectionID -= 1
                    }
                }
            }
        }
        return result
    }

    // A category the marks do not plot would add one to the axis, so a selection of it is not
    // drawn. Numbers and dates are drawn wherever they fall: Swift Charts reports values across
    // the drawn domain, which runs past the data.
    private static func onAxis(_ part: ChartSelectionPart, categories: Set<String>) -> ChartSelectionPart? {
        if case .value(.string(let category)) = part, !categories.contains(category) { return nil }
        return part
    }

    // Splits top-level content into runs of entries that do and do not read the selection.
    private static func segments(_ entries: [ChartEntry]) -> [(readsSelection: Bool, entries: [ChartEntry])] {
        var flat: [(Bool, ChartEntry)] = []
        func flatten(_ entries: [ChartEntry]) {
            for entry in entries {
                switch entry {
                case .mark(let mark): flat.append((mark.values.values.contains { $0.isSelection }, entry))
                case .plot(let children): flatten(children)
                case .forEach: flat.append((false, entry))
                }
            }
        }
        flatten(entries)
        var runs: [(readsSelection: Bool, entries: [ChartEntry])] = []
        for (readsSelection, entry) in flat {
            if let last = runs.last, last.readsSelection == readsSelection {
                runs[runs.count - 1].entries.append(entry)
            } else {
                runs.append((readsSelection, [entry]))
            }
        }
        return runs
    }

    /// The row of the sector whose share of the angle values holds `angle` (Swift Charts reports
    /// an angle selection as a position along the running sum of the sectors' values).
    func sectorRow(at angle: Double) -> Int? {
        var end = 0.0
        for sector in sectorAngles where sector.value.isFinite && sector.value > 0 {
            end += sector.value
            if angle <= end { return sector.row }
        }
        return nil
    }

    /// Fires a selection action now ("continuous", or a cleared selection) or once the selection
    /// has rested for `delay` ("settled"); either way a pending settled action is dropped.
    func scheduleSelectionAction(cleared: Bool, continuous: Bool, delay: TimeInterval, fire: @escaping @MainActor () -> Void) {
        pendingAction?.cancel()
        pendingAction = nil
        if continuous || cleared {
            fire()
            return
        }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.pendingAction = nil
                fire()
            }
        }
        pendingAction = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
}
