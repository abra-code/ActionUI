// SwiftUI rendering of Chart; its portable part is in Core/Elements/Chart.swift.

import SwiftUI
import Charts

extension Chart: ActionUISwiftUIRenderer {
    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        let props = Props(properties)
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
                                    viewID: element.id, windowUUID: windowUUID, logger: logger)
        let items = rendered.items
        let plotStyle = rendered.spec.plotStyle
        // View.applyModifiers also draws the element's own background, overlay and safeAreaInset
        // subviews, which the chart as a whole already has: the plot area gets an element
        // without subviews.
        let plotElement = ActionUIElement(id: element.id, type: element.type, properties: plotStyle, subviews: nil)
        let binder = ChartSelectionBinder(model: model, spec: rendered.spec.selection, cache: cache, windowUUID: windowUUID,
                                          viewID: element.id, actionID: props.valueChangeActionID,
                                          continuous: props.selectionActionTiming == .continuous)
        return Charts.Chart(items, id: \.id) { $0.content }
            .chartModifiers(rendered.spec, plotStyle: plotStyle.isEmpty ? nil : { plot in
                AnyView(View.applyModifiers(plot, plotElement, windowUUID, plotStyle, logger))
            })
            .modifier(ChartSelector(binder: binder))
            .modifier(ChartScroller(spec: rendered.spec.scroll))
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
    // values, and visible lengths that would lay out too many are lengthened, which depends on the rows
    // (ChartAxisStrideLimit, ChartVisibleLengthLimit).
    private var drawnSpec = ChartSpec()
    private var rows: [[String]]?
    private var segments: [Segment] = []
    private var selection: ChartSelection?
    private var items: [Item] = []
    private var sectorAngles: [(row: Int?, value: Double)] = []
    // The categories the built marks plot on each axis (onAxis).
    private var xCategories: Set<String> = []
    private var yCategories: Set<String> = []
    // False when the built marks are too many annotations to draw (maxAnnotations).
    private var drawsAnnotations = true
    private var pendingAction: DispatchWorkItem?
    // Swift Charts lays out annotations on every render, in a time that grows with the square of
    // their count (measured on macOS 27: 0.13 s for 1000, 2.2 s for 5000, 8 s for 10000), so past
    // this many the marks are drawn without them.
    static let maxAnnotations = 1000
    // Times the marks were built; lets tests see that unchanged inputs rebuild nothing.
    private(set) var buildCount = 0
    // Times the selection marks were built.
    private(set) var selectionBuildCount = 0

    func render(description newDescription: [String: Any], rows newRows: [[String]], selectionValue: String = "",
                viewID: Int, windowUUID: String = "", logger: any ActionUILogger) -> (spec: ChartSpec, items: [Item]) {
        let descriptionObject = newDescription as NSDictionary
        let descriptionChanged = description.map { !$0.isEqual(to: newDescription) } ?? true
        if descriptionChanged {
            // Cleaned where it is stored (warnings were logged then): parse without logging.
            spec = ChartDescription.parse(newDescription, logger: nil).spec
            description = descriptionObject
        }
        var rebuilt = false
        if descriptionChanged || rows != newRows {
            let columns = ChartTypedColumns(rows: newRows, refs: spec.referencedColumns)
            var builder = ChartContentBuilder(columns: columns)
            (builder.viewID, builder.windowUUID, builder.logger) = (viewID, windowUUID, logger)
            let annotations = ChartSpec.annotationCount(in: spec.content, rowCount: newRows.count)
            drawsAnnotations = annotations <= Self.maxAnnotations
            builder.drawsAnnotations = drawsAnnotations
            if !drawsAnnotations {
                logger.log("Chart \(viewID): \(annotations) annotations would take Swift Charts seconds to draw on every render (more than \(Self.maxAnnotations)); drawing the marks without them", .warning)
            }
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
            drawnSpec.scroll = ChartVisibleLengthLimit.limited(spec.scroll, x: drawnSpec.x, y: drawnSpec.y, xExtent: builder.xExtent,
                                                               yExtent: builder.yExtent, viewID: viewID, logger: logger)
        }
        let newSelection = ChartSelection.decode(selectionValue, spec: spec.selection)
        if rebuilt || newSelection != selection {
            selection = newSelection
            items = assemble(newSelection, viewID: viewID, windowUUID: windowUUID, logger: logger)
        }
        return (drawnSpec, items)
    }

    private func assemble(_ selection: ChartSelection, viewID: Int, windowUUID: String, logger: any ActionUILogger) -> [Item] {
        var result: [Item] = []
        var builtID = 0
        var selectionID = -1
        // Selection marks read no rows.
        var builder = ChartContentBuilder(columns: ChartTypedColumns(rows: [], refs: []))
        (builder.viewID, builder.windowUUID, builder.logger) = (viewID, windowUUID, logger)
        builder.drawsAnnotations = drawsAnnotations
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
