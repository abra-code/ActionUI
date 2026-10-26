// Sources/Elements/Canvas+Adwaita.swift
/*
 Canvas on GTK: a widget that draws the operations with GTK's snapshot API (GSK paths, strokes,
 gradients, shadows, blur, blend modes), following ActionUI's Apple drawing code
 (Helpers/CanvasRenderer.swift) as it draws, not as the comments describe it. Greedy in both axes
 with Color's size, as SwiftUI's Canvas is (measured on macOS 27: it shares an HStack as a Color
 does). The background color fills it first; a click (press and release inside) fires actionID.

 What Apple's code does, and so this one (measured on macOS 27 where it is not plain from the code):
 - Coordinates: normalized values are fractions of the canvas (of a layer's frame inside a layer):
   x of its width, y of its height, radii of the shorter side. Line widths, dashes, font sizes,
   translations and filter radii and offsets are points in both modes; gradient points are always
   fractions.
 - A fill without a valid color or gradient draws nothing; a gradient's colors are evenly spaced
   (its locations are ignored).
 - An arc's clockwise flag is SwiftUI's: 1 runs with decreasing angles on the screen (measured:
   0 to 90 clockwise draws three quarters through the top), and angles whole turns apart draw a
   circle with either flag (0 to 360 clockwise too). An arc after a point is joined to it by a line.
 - A path's lines and curves before any moveTo are left out, as SwiftUI's Path leaves them out.
 - A roundedRect's cornerRadii use the first radius for all four corners; its corners are circular
   (SwiftUI's are continuous, as for RoundedRectangle).
 - A click on the canvas is its own, with or without an actionID, as Apple's tap gesture is.
 - Text is drawn in its frame from the top leading corner, wrapped at the frame's width, black and
   in the default font unless given; its alignment is ignored.
 - An image is stretched to its frame (measured: a symbol in a wide frame is drawn wide). A symbol
   is drawn in the text color. A file that cannot be read is the photo symbol, an asset that does
   not exist is nothing, as SwiftUI's Image draws them.
 - An image's opacity replaces the opacity it is drawn with, which is 1 again after it (Apple's
   code sets the context's opacity and resets it to 1, also inside a layer with an opacity).
 - translate, scale, rotate (degrees, clockwise) and clip apply to the operations after them.
 - shadow and blur apply to each drawing operation after them, in the order given; a shadow's
   blend mode is not drawn. A blur's radius is SwiftUI's (twice GSK's); a shadow's is the same in
   both (measured).
 - Drawing stops at the canvas's edges, as SwiftUI clips a Canvas.
 - Blend modes follow GSK, which is right in GTK's cairo renderer; GTK's GPU renderers (4.18 to
   main, read in gsk/gpu/shaders/blendmode.glsl) blend premultiplied colors with the formula for
   straight ones, so translucent pixels come out darker there.
 - A layer draws its operations in an offscreen layer, each at the layer's opacity and with its
   blend mode (multiply, screen, overlay) over what the layer drew before, and puts the layer
   over the canvas like one drawing operation. The layer does not clip to its frame.
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import CAdwaita

nonisolated(unsafe) private var canvasWidgetType: GType = 0
private let canvasStateKey = AttachKey<CanvasState>("actionui-canvas")

/// What a canvas draws, kept on its widget, and the images it read.
@MainActor private final class CanvasState {
    var props = Canvas.Props([:])
    /// Textures by file path; nil for a file that could not be read.
    var textures: [String: LoadedTexture?] = [:]
}

extension Canvas: ActionUIAdwaitaRenderer {
    static func makeWidget(_ node: RenderNode) -> WidgetPointer {
        let widget: WidgetPointer = typed(OpaquePointer(g_object_new_with_properties(widgetType(), 0, nil, nil)!))
        gtk_widget_set_hexpand(widget, 1)
        gtk_widget_set_vexpand(widget, 1)
        attach(CanvasState(), to: widget, key: canvasStateKey)
        let click = gtk_gesture_click_new()!
        gtk_gesture_single_set_button(click, guint(GDK_BUTTON_PRIMARY))
        connectClick(UnsafeMutableRawPointer(click), "released") { [weak node] _, x, y in
            // Claimed, as ContainerTap claims its click, also without an actionID: Apple's Canvas
            // has its tap gesture either way, and SwiftUI fires only the inner one, so an
            // enclosing tappable container does not fire.
            gtk_gesture_set_state(click, GTK_EVENT_SEQUENCE_CLAIMED)
            guard let node, let actionID = Props(node.properties).actionID else { return }
            // Released inside: a click, not a drag out of the canvas.
            guard x >= 0, y >= 0, x < Double(gtk_widget_get_width(widget)), y < Double(gtk_widget_get_height(widget)) else { return }
            ActionUIModel.shared.actionHandler(actionID, windowUUID: node.windowUUID, viewID: node.element.id, viewPartID: 0)
        }
        gtk_widget_add_controller(widget, click)
        return widget
    }

    static func update(_ widget: WidgetPointer, _ node: RenderNode) {
        guard let state = attached(on: widget, key: canvasStateKey) else { return }
        state.props = Props(node.properties)
        gtk_widget_queue_draw(widget)
    }

    static var defaultExpansion: Expansion { .both }

    private static func snapshot(_ widget: WidgetPointer, _ snapshot: OpaquePointer) {
        guard let state = attached(on: widget, key: canvasStateKey) else { return }
        let size = CanvasSize(width: Double(gtk_widget_get_width(widget)), height: Double(gtk_widget_get_height(widget)))
        guard size.width > 0, size.height > 0 else { return }
        let drawing = CanvasDrawing(widget: widget, state: state, points: state.props.coordinateMode == .points)
        let context = CanvasContext()
        if let background = state.props.backgroundColor.flatMap(ColorSpec.parse) {
            var color = drawing.rgba(background)
            if color.alpha > 0 {
                let builder = CanvasPath()
                builder.addRect(x: 0, y: 0, width: size.width, height: size.height)
                if let path = builder.gskPath(.identity) {
                    context.draw { gtk_snapshot_append_fill($0, path, GSK_FILL_RULE_WINDING, &color) }
                    gsk_path_unref(path)
                }
            }
        }
        drawing.draw(state.props.operations, into: context, size: size)
        if let node = context.finish() {
            // Within its bounds, as SwiftUI clips a Canvas (measured: a filter or a shape past the
            // edge is cut there).
            var bounds = graphene_rect_t(origin: graphene_point_t(x: 0, y: 0), size: graphene_size_t(width: Float(size.width), height: Float(size.height)))
            gtk_snapshot_push_clip(snapshot, &bounds)
            gtk_snapshot_append_node(snapshot, node)
            gtk_snapshot_pop(snapshot)
            gsk_render_node_unref(node)
        }
    }

    private static func widgetType() -> GType {
        if canvasWidgetType != 0 { return canvasWidgetType }
        var info = GTypeInfo()
        info.class_size = guint16(MemoryLayout<GtkWidgetClass>.size)
        info.instance_size = guint16(MemoryLayout<GtkWidget>.size)
        info.class_init = { klass, _ in
            guard let klass else { return }
            let widgetClass = klass.assumingMemoryBound(to: GtkWidgetClass.self)
            widgetClass.pointee.measure = { _, _, _, minimum, natural, minimumBaseline, naturalBaseline in
                minimum?.pointee = 0
                natural?.pointee = MainActor.assumeIsolated { Color.idealLength }
                minimumBaseline?.pointee = -1
                naturalBaseline?.pointee = -1
            }
            widgetClass.pointee.snapshot = { widget, snapshot in
                guard let widget, let snapshot else { return }
                MainActor.assumeIsolated { Canvas.snapshot(widget, snapshot) }
            }
            gtk_widget_class_set_css_name(widgetClass, "actionui-canvas")
        }
        canvasWidgetType = g_type_register_static(gtk_widget_get_type(), "ActionUICanvas", &info, GTypeFlags(0))
        return canvasWidgetType
    }
}

struct CanvasSize {
    var width: Double
    var height: Double
}

/// A 2D affine transform (x' = a x + c y + tx, y' = b x + d y + ty), and the steps that made it,
/// from which GSK's transform is built: a transform from a matrix is one GTK's renderers may not
/// draw (measured: the cairo renderer drew a translated fill in its error color).
struct CanvasAffine {
    enum Step {
        case translate(Double, Double)
        case scale(Double, Double)
        case rotate(Double)
    }

    var a = 1.0, b = 0.0, c = 0.0, d = 1.0, tx = 0.0, ty = 0.0
    private(set) var steps: [Step] = []

    static let identity = CanvasAffine()

    /// False after an infinite step (or one that made a NaN), after which SwiftUI draws nothing
    /// (measured on macOS 27: a fill after rotating by infinity), and after a step GSK's floats
    /// cannot hold.
    var isFinite: Bool {
        guard [a, b, c, d, tx, ty].allSatisfy(\.isFinite) else { return false }
        return steps.allSatisfy { step in
            switch step {
            case let .translate(x, y), let .scale(x, y): return Float(x).isFinite && Float(y).isFinite
            case .rotate: return true
            }
        }
    }

    func apply(_ x: Double, _ y: Double) -> (Double, Double) {
        (a * x + c * y + tx, b * x + d * y + ty)
    }

    /// This transform after moving by (x, y) in its own coordinates.
    func translated(_ x: Double, _ y: Double) -> CanvasAffine {
        var result = self
        result.tx = a * x + c * y + tx
        result.ty = b * x + d * y + ty
        result.steps.append(.translate(x, y))
        return result
    }

    func scaled(_ x: Double, _ y: Double) -> CanvasAffine {
        var result = self
        result.a = a * x
        result.b = b * x
        result.c = c * y
        result.d = d * y
        result.steps.append(.scale(x, y))
        return result
    }

    /// Rotated by `degrees` clockwise on the screen (y down).
    func rotated(_ degrees: Double) -> CanvasAffine {
        let radians = degrees * .pi / 180
        let cosine = cos(radians), sine = sin(radians)
        var result = self
        result.a = a * cosine + c * sine
        result.b = b * cosine + d * sine
        result.c = -a * sine + c * cosine
        result.d = -b * sine + d * cosine
        result.steps.append(.rotate(degrees))
        return result
    }

    /// The transform as GSK's (nil for none), which the caller releases.
    func gskTransform() -> OpaquePointer? {
        var transform: OpaquePointer?
        for step in steps {
            switch step {
            case let .translate(x, y):
                var point = graphene_point_t(x: Float(x), y: Float(y))
                transform = gsk_transform_translate(transform, &point)
            case let .scale(x, y):
                transform = gsk_transform_scale(transform, Float(x), Float(y))
            case let .rotate(degrees):
                // Within a turn: GSK subtracts 360 until it is, which never ends for a large float.
                transform = gsk_transform_rotate(transform, Float(degrees.truncatingRemainder(dividingBy: 360)))
            }
        }
        return transform
    }
}

/// A path recorded in a canvas's coordinates, turned into a GSK path under any transform (affine
/// maps keep lines, curves and conics what they are, so clips can be kept in canvas coordinates).
final class CanvasPath {
    enum Segment {
        case move(Double, Double)
        case line(Double, Double)
        case quad(Double, Double, Double, Double)
        case cubic(Double, Double, Double, Double, Double, Double)
        /// Control point, end point and weight: a quarter circle or less with weight cos(angle / 2).
        case conic(Double, Double, Double, Double, Double)
        case close
    }

    private(set) var segments: [Segment] = []
    private var current: (Double, Double)?
    private var subpathStart: (Double, Double)?

    var isEmpty: Bool { segments.isEmpty }

    func move(_ x: Double, _ y: Double) {
        segments.append(.move(x, y))
        current = (x, y)
        subpathStart = (x, y)
    }

    // A line or curve with no current point (no moveTo before it) is left out, as SwiftUI's Path
    // leaves it out (measured on macOS 27: lineTo, lineTo with no moveTo draws nothing).
    func line(_ x: Double, _ y: Double) {
        guard current != nil else { return }
        segments.append(.line(x, y))
        current = (x, y)
    }

    func quad(_ cx: Double, _ cy: Double, _ x: Double, _ y: Double) {
        guard current != nil else { return }
        segments.append(.quad(cx, cy, x, y))
        current = (x, y)
    }

    func cubic(_ c1x: Double, _ c1y: Double, _ c2x: Double, _ c2y: Double, _ x: Double, _ y: Double) {
        guard current != nil else { return }
        segments.append(.cubic(c1x, c1y, c2x, c2y, x, y))
        current = (x, y)
    }

    func close() {
        guard current != nil else { return }
        segments.append(.close)
        current = subpathStart
    }

    /// An arc of the circle at (cx, cy) with `radius` from `start` to `end` degrees, joined to the
    /// current point by a line. `clockwise` is SwiftUI's flag: true runs with decreasing angles on
    /// the screen (y down). The sweep is SwiftUI's (measured on macOS 27): in the flag's direction,
    /// a full turn and what is left past it (more turns draw nothing more); against it, the rest of a
    /// turn, or a full turn when the angles are whole turns apart (0 to 360 clockwise is a circle).
    /// Non-finite angles draw nothing.
    func arc(cx: Double, cy: Double, radius: Double, start: Double, end: Double, clockwise: Bool) {
        var sweep = clockwise ? start - end : end - start
        guard start.isFinite, sweep.isFinite else { return }
        if sweep >= 360 {
            sweep = 360 + sweep.truncatingRemainder(dividingBy: 360)
        } else if sweep < 0 {
            sweep = sweep.truncatingRemainder(dividingBy: 360)
            sweep = sweep == 0 ? 360 : sweep + 360
        }
        let direction = clockwise ? -1.0 : 1.0
        let startRadians = start * .pi / 180
        let startPoint = (cx + radius * cos(startRadians), cy + radius * sin(startRadians))
        if current == nil {
            move(startPoint.0, startPoint.1)
        } else {
            line(startPoint.0, startPoint.1)
        }
        guard sweep > 0 else { return }
        let pieces = max(1, Int((sweep / 90).rounded(.up)))
        let step = sweep / Double(pieces) * .pi / 180 * direction
        var angle = startRadians
        for _ in 0..<pieces {
            let next = angle + step
            let middle = (angle + next) / 2
            let half = abs(step) / 2
            let reach = radius / cos(half)
            segments.append(.conic(cx + reach * cos(middle), cy + reach * sin(middle),
                                   cx + radius * cos(next), cy + radius * sin(next), cos(half)))
            angle = next
        }
        current = (cx + radius * cos(angle), cy + radius * sin(angle))
    }

    func addRect(x: Double, y: Double, width: Double, height: Double) {
        move(x, y)
        line(x + width, y)
        line(x + width, y + height)
        line(x, y + height)
        close()
    }

    /// An ellipse touching the rect's sides, as four quarter conics.
    func addEllipse(x: Double, y: Double, width: Double, height: Double) {
        let weight = 0.5.squareRoot()
        let minX = x, maxX = x + width, minY = y, maxY = y + height
        let midX = x + width / 2, midY = y + height / 2
        move(maxX, midY)
        segments.append(.conic(maxX, maxY, midX, maxY, weight))
        segments.append(.conic(minX, maxY, minX, midY, weight))
        segments.append(.conic(minX, minY, midX, minY, weight))
        segments.append(.conic(maxX, minY, maxX, midY, weight))
        close()
    }

    /// A rect with circular corners of `radius`, at most half its shorter side, as SwiftUI clamps it.
    func addRoundedRect(x: Double, y: Double, width: Double, height: Double, radius: Double) {
        let r = min(max(radius, 0), min(abs(width), abs(height)) / 2)
        guard r > 0 else { return addRect(x: x, y: y, width: width, height: height) }
        let weight = 0.5.squareRoot()
        let minX = x, maxX = x + width, minY = y, maxY = y + height
        move(minX + r, minY)
        line(maxX - r, minY)
        segments.append(.conic(maxX, minY, maxX, minY + r, weight))
        line(maxX, maxY - r)
        segments.append(.conic(maxX, maxY, maxX - r, maxY, weight))
        line(minX + r, maxY)
        segments.append(.conic(minX, maxY, minX, maxY - r, weight))
        line(minX, minY + r)
        segments.append(.conic(minX, minY, minX + r, minY, weight))
        close()
    }

    /// The path under `transform`, which the caller releases with gsk_path_unref; nil when empty.
    func gskPath(_ transform: CanvasAffine) -> OpaquePointer? {
        guard !segments.isEmpty, let builder = gsk_path_builder_new() else { return nil }
        func point(_ x: Double, _ y: Double) -> (Float, Float) {
            let (px, py) = transform.apply(x, y)
            return (Float(px), Float(py))
        }
        for segment in segments {
            switch segment {
            case let .move(x, y):
                let p = point(x, y)
                gsk_path_builder_move_to(builder, p.0, p.1)
            case let .line(x, y):
                let p = point(x, y)
                gsk_path_builder_line_to(builder, p.0, p.1)
            case let .quad(cx, cy, x, y):
                let c = point(cx, cy), p = point(x, y)
                gsk_path_builder_quad_to(builder, c.0, c.1, p.0, p.1)
            case let .cubic(c1x, c1y, c2x, c2y, x, y):
                let c1 = point(c1x, c1y), c2 = point(c2x, c2y), p = point(x, y)
                gsk_path_builder_cubic_to(builder, c1.0, c1.1, c2.0, c2.1, p.0, p.1)
            case let .conic(cx, cy, x, y, weight):
                let c = point(cx, cy), p = point(x, y)
                gsk_path_builder_conic_to(builder, c.0, c.1, p.0, p.1, Float(weight))
            case .close:
                gsk_path_builder_close(builder)
            }
        }
        return gsk_path_builder_free_to_path(builder)
    }
}

/// A filter that applies to each drawing operation after it.
enum CanvasFilter {
    case shadow(GskShadow)
    case blur(Double)

    /// The largest blur or shadow radius drawn, in GSK's terms: GTK's GPU renderers crash past
    /// some size (measured with GTK 4.18: at a blur radius of 20000 on a 100-point canvas, and at
    /// an infinite one), and the cairo renderer takes seconds at 2000. A radius this large on
    /// SwiftUI already spreads a shape until it barely shows.
    static let maximumRadius: Float = 1000

    /// `radius` within 0...maximumRadius (0 for NaN).
    static func radius(_ radius: Double) -> Float {
        radius > 0 ? min(Float(radius), maximumRadius) : 0
    }
}

/// The drawing state of a canvas or a layer (SwiftUI's GraphicsContext), and what it has drawn so
/// far, in canvas coordinates.
@MainActor final class CanvasContext {
    var transform = CanvasAffine.identity
    /// Clip paths in canvas coordinates; each drawing is clipped by all of them.
    var clips: [OpaquePointer] = []
    var filters: [CanvasFilter] = []
    var opacity = 1.0
    var blendMode = GSK_BLEND_MODE_DEFAULT
    private var snapshot: OpaquePointer? = gtk_snapshot_new()

    isolated deinit {
        for clip in clips { gsk_path_unref(clip) }
        if let snapshot, let node = gtk_snapshot_free_to_node(snapshot) { gsk_render_node_unref(node) }
    }

    /// Draws one operation: `content` draws it in the context's coordinates; the context's clips,
    /// filters, opacity and blend mode apply to the result.
    func draw(transformed: Bool = true, _ content: (OpaquePointer) -> Void) {
        if transformed, !transform.isFinite { return }
        guard let operation = gtk_snapshot_new() else { return }
        gtk_snapshot_save(operation)
        for clip in clips {
            gtk_snapshot_push_fill(operation, clip, GSK_FILL_RULE_WINDING)
        }
        // The first filter given applies first, so it is the innermost.
        for filter in filters.reversed() {
            switch filter {
            case .shadow(var shadow):
                gtk_snapshot_push_shadow(operation, &shadow, 1)
            case .blur(let radius):
                // GSK's blur radius is twice the deviation, SwiftUI's is the deviation (measured:
                // a radius-8 edge fades over 20 points on macOS, 10 here at 8).
                gtk_snapshot_push_blur(operation, Double(CanvasFilter.radius(radius * 2)))
            }
        }
        if opacity < 1 {
            gtk_snapshot_push_opacity(operation, max(opacity, 0))
        }
        if transformed, let gsk = transform.gskTransform() {
            gtk_snapshot_transform(operation, gsk)
            gsk_transform_unref(gsk)
        }
        content(operation)
        if opacity < 1 { gtk_snapshot_pop(operation) }
        for _ in filters { gtk_snapshot_pop(operation) }
        for _ in clips { gtk_snapshot_pop(operation) }
        gtk_snapshot_restore(operation)
        guard let top = gtk_snapshot_free_to_node(operation) else { return }
        defer { gsk_render_node_unref(top) }
        guard let snapshot else { return }
        if blendMode == GSK_BLEND_MODE_DEFAULT {
            gtk_snapshot_append_node(snapshot, top)
            return
        }
        // Blended over what this context drew so far.
        let bottom = gtk_snapshot_free_to_node(snapshot)
        self.snapshot = gtk_snapshot_new()
        guard let bottom, let next = self.snapshot else {
            if let next = self.snapshot { gtk_snapshot_append_node(next, top) }
            return
        }
        defer { gsk_render_node_unref(bottom) }
        if let blended = gsk_blend_node_new(bottom, top, blendMode) {
            gtk_snapshot_append_node(next, blended)
            gsk_render_node_unref(blended)
        }
    }

    /// What the context drew, which the caller releases; nil when nothing.
    func finish() -> OpaquePointer? {
        guard let snapshot else { return nil }
        self.snapshot = nil
        return gtk_snapshot_free_to_node(snapshot)
    }
}

/// Draws a canvas's operations into contexts, as CanvasRenderer.draw does on Apple.
@MainActor struct CanvasDrawing {
    let widget: WidgetPointer
    fileprivate let state: CanvasState
    let points: Bool
    private var logger: any ActionUILogger { ActionUIModel.shared.logger }

    fileprivate init(widget: WidgetPointer, state: CanvasState, points: Bool) {
        self.widget = widget
        self.state = state
        self.points = points
    }

    func draw(_ operations: [[String: Any]], into context: CanvasContext, size: CanvasSize) {
        for operation in operations {
            guard let type = operation["type"] as? String else { continue }
            switch type.lowercased() {
            case "fill":
                guard let path = makePath(operation["path"] as? [String: Any], size: size) else { continue }
                if let gradient = operation["gradient"] as? [String: Any], let shading = shading(gradient, size: size) {
                    fill(path, with: shading, in: context)
                } else if let color = (operation["color"] as? String).flatMap(ColorSpec.parse) {
                    guard let gskPath = path.gskPath(.identity) else { continue }
                    var rgba = rgba(color)
                    context.draw { gtk_snapshot_append_fill($0, gskPath, GSK_FILL_RULE_WINDING, &rgba) }
                    gsk_path_unref(gskPath)
                } else {
                    logger.log("No valid color or gradient for fill", .warning)
                }

            case "stroke":
                guard let path = makePath(operation["path"] as? [String: Any], size: size),
                      let color = (operation["color"] as? String).flatMap(ColorSpec.parse),
                      let gskPath = path.gskPath(.identity) else {
                    logger.log("Missing/invalid path or color for stroke", .warning)
                    continue
                }
                defer { gsk_path_unref(gskPath) }
                // A line width of 0 draws nothing (measured on macOS 27); GSK refuses one (NULL).
                let lineWidth = operation.double(forKey: "lineWidth") ?? 1
                guard lineWidth > 0, let stroke = gsk_stroke_new(Float(lineWidth)) else { continue }
                defer { gsk_stroke_free(stroke) }
                switch (operation["lineCap"] as? String ?? "butt").lowercased() {
                case "round": gsk_stroke_set_line_cap(stroke, GSK_LINE_CAP_ROUND)
                case "square": gsk_stroke_set_line_cap(stroke, GSK_LINE_CAP_SQUARE)
                default: gsk_stroke_set_line_cap(stroke, GSK_LINE_CAP_BUTT)
                }
                switch (operation["lineJoin"] as? String ?? "miter").lowercased() {
                case "round": gsk_stroke_set_line_join(stroke, GSK_LINE_JOIN_ROUND)
                case "bevel": gsk_stroke_set_line_join(stroke, GSK_LINE_JOIN_BEVEL)
                default: gsk_stroke_set_line_join(stroke, GSK_LINE_JOIN_MITER)
                }
                gsk_stroke_set_miter_limit(stroke, Float(max(operation.double(forKey: "miterLimit") ?? 10, 0)))
                let dash = (operation.doubleArray(forKey: "dash") ?? []).map { Float(max($0, 0)) }
                if !dash.isEmpty {
                    gsk_stroke_set_dash(stroke, dash, gsize(dash.count))
                    gsk_stroke_set_dash_offset(stroke, Float(operation.double(forKey: "dashPhase") ?? 0))
                }
                var rgba = rgba(color)
                context.draw { gtk_snapshot_append_stroke($0, gskPath, stroke, &rgba) }

            case "text":
                guard let text = operation["text"] as? String, let frame = rect(operation.doubleArray(forKey: "frame"), size: size) else { continue }
                drawText(text, operation, in: frame, context)

            case "image":
                // Apple's code sets the context's opacity for the image and then sets it to 1, also
                // for an infinite frame, which draws nothing.
                guard let frame = rect(operation.doubleArray(forKey: "frame"), size: size) else {
                    context.opacity = 1
                    continue
                }
                context.opacity = operation.double(forKey: "opacity") ?? 1
                if !drawImage(operation, in: frame, context) {
                    logger.log("Failed to resolve image", .warning)
                }
                context.opacity = 1

            case "clip":
                if let path = makePath(operation["path"] as? [String: Any], size: size), let clip = path.gskPath(context.transform) {
                    context.clips.append(clip)
                }

            case "translate":
                context.transform = context.transform.translated(operation.double(forKey: "x") ?? 0, operation.double(forKey: "y") ?? 0)

            case "scale":
                context.transform = context.transform.scaled(operation.double(forKey: "x") ?? 1, operation.double(forKey: "y") ?? 1)

            case "rotate":
                if let degrees = operation.double(forKey: "angle") {
                    context.transform = context.transform.rotated(degrees)
                }

            case "shadow":
                // SwiftUI's default shadow color: black at 33% opacity.
                let color = (operation["color"] as? String).flatMap(ColorSpec.parse).map(rgba)
                    ?? GdkRGBA(red: 0, green: 0, blue: 0, alpha: 0.33)
                let shadow = GskShadow(color: color, dx: Float(operation.double(forKey: "x") ?? 0.002), dy: Float(operation.double(forKey: "y") ?? 0.004),
                                       radius: CanvasFilter.radius(operation.double(forKey: "radius") ?? 0.005))
                context.filters.append(.shadow(shadow))

            case "blur":
                if let radius = operation.double(forKey: "radius") {
                    context.filters.append(.blur(radius))
                } else {
                    logger.log("Blur missing radius", .warning)
                }

            case "layer":
                guard let frame = rect(operation.doubleArray(forKey: "frame"), size: size) else { continue }
                guard let operations = operation["operations"] as? [[String: Any]] else { continue }
                let layer = CanvasContext()
                layer.transform = context.transform.translated(frame.x, frame.y)
                layer.opacity = operation.double(forKey: "opacity") ?? 1
                layer.blendMode = Self.blendMode(operation["blendMode"] as? String)
                draw(operations, into: layer, size: CanvasSize(width: frame.width, height: frame.height))
                if let node = layer.finish() {
                    context.draw(transformed: false) { gtk_snapshot_append_node($0, node) }
                    gsk_render_node_unref(node)
                }

            default:
                logger.log("Unknown operation type: \(type)", .warning)
            }
        }
    }

    // MARK: Values

    struct Rect {
        var x, y, width, height: Double
    }

    private func rect(_ values: [Double]?, size: CanvasSize) -> Rect? {
        guard let values, values.count == 4 else { return nil }
        let rect = points ? Rect(x: values[0], y: values[1], width: values[2], height: values[3])
            : Rect(x: values[0] * size.width, y: values[1] * size.height, width: values[2] * size.width, height: values[3] * size.height)
        // An infinite frame ("inf" in a document) draws nothing, and must not reach GSK or Pango.
        guard [rect.x, rect.y, rect.width, rect.height].allSatisfy({ Float($0).isFinite }) else { return nil }
        return rect
    }

    static func blendMode(_ name: String?) -> GskBlendMode {
        switch name?.lowercased() {
        case "multiply": return GSK_BLEND_MODE_MULTIPLY
        case "screen": return GSK_BLEND_MODE_SCREEN
        case "overlay": return GSK_BLEND_MODE_OVERLAY
        default: return GSK_BLEND_MODE_DEFAULT
        }
    }

    /// A color as GDK's: named colors as the rest of ActionUI's GTK renderer shows them.
    func rgba(_ color: ColorSpec) -> GdkRGBA {
        ColorRGBA.resolve(color, for: widget)
    }

    // MARK: Paths

    private func makePath(_ dict: [String: Any]?, size: CanvasSize) -> CanvasPath? {
        guard let dict, let type = dict["type"] as? String else {
            logger.log("Missing or invalid path type", .warning)
            return nil
        }
        let shorter = min(size.width, size.height)
        let x: (Double) -> Double = { points ? $0 : $0 * size.width }
        let y: (Double) -> Double = { points ? $0 : $0 * size.height }
        let length: (Double) -> Double = { points ? $0 : $0 * shorter }
        let path = CanvasPath()
        switch type.lowercased() {
        case "circle":
            guard let center = dict.doubleArray(forKey: "center"), center.count == 2, let radius = dict.double(forKey: "radius") else {
                logger.log("Invalid circle: missing center or radius", .warning)
                return nil
            }
            let r = length(radius)
            path.addEllipse(x: x(center[0]) - r, y: y(center[1]) - r, width: r * 2, height: r * 2)

        case "ellipse":
            guard let frame = dict.doubleArray(forKey: "frame"), frame.count == 4 else {
                logger.log("Invalid ellipse: frame must be [x,y,w,h]", .warning)
                return nil
            }
            path.addEllipse(x: x(frame[0]), y: y(frame[1]), width: x(frame[2]), height: y(frame[3]))

        case "rect":
            guard let left = dict.double(forKey: "x"), let top = dict.double(forKey: "y"),
                  let width = dict.double(forKey: "width"), let height = dict.double(forKey: "height") else {
                logger.log("Invalid rect: missing x/y/width/height", .warning)
                return nil
            }
            path.addRect(x: x(left), y: y(top), width: x(width), height: y(height))

        case "roundedrect":
            guard let left = dict.double(forKey: "x"), let top = dict.double(forKey: "y"),
                  let width = dict.double(forKey: "width"), let height = dict.double(forKey: "height") else {
                logger.log("Invalid roundedRect: missing x/y/width/height", .warning)
                return nil
            }
            var corner = 0.0
            if let radius = dict.double(forKey: "cornerRadius") {
                corner = length(radius)
            } else if let radii = dict.doubleArray(forKey: "cornerRadii"), radii.count == 4 {
                corner = length(radii[0])
            }
            path.addRoundedRect(x: x(left), y: y(top), width: x(width), height: y(height), radius: corner)

        case "path":
            guard let commands = dict["commands"] as? [[Any]] else {
                logger.log("Custom path missing 'commands' array", .warning)
                return nil
            }
            for command in commands {
                guard let name = command.first as? String else { continue }
                let args = command.dropFirst().map { element -> Double in
                    if let number = JSONNumber.double(element) { return number }
                    logger.log("Invalid number: \(element)", .warning)
                    return 0
                }
                switch name.lowercased() {
                case "moveto":
                    if args.count >= 2 { path.move(x(args[0]), y(args[1])) }
                case "lineto":
                    if args.count >= 2 { path.line(x(args[0]), y(args[1])) }
                case "quadraticcurveto", "quadcurveto":
                    if args.count >= 4 { path.quad(x(args[0]), y(args[1]), x(args[2]), y(args[3])) }
                case "curveto", "cubiccurveto":
                    if args.count >= 6 { path.cubic(x(args[0]), y(args[1]), x(args[2]), y(args[3]), x(args[4]), y(args[5])) }
                case "arc":
                    if args.count >= 6 {
                        path.arc(cx: x(args[0]), cy: y(args[1]), radius: length(args[2]), start: args[3], end: args[4], clockwise: args[5] != 0)
                    }
                case "closepath", "close":
                    path.close()
                default:
                    logger.log("Unknown path command: \(name)", .warning)
                }
            }

        default:
            logger.log("Unsupported path type: \(type)", .warning)
            return nil
        }
        return path.isEmpty ? nil : path
    }

    // MARK: Gradients

    private enum Shading {
        case linear(start: graphene_point_t, end: graphene_point_t, stops: [GskColorStop])
        case radial(center: graphene_point_t, startRadius: Double, endRadius: Double, stops: [GskColorStop])
    }

    private func shading(_ dict: [String: Any], size: CanvasSize) -> Shading? {
        guard let type = dict["type"] as? String, let names = dict["colors"] as? [String], names.count >= 2 else {
            logger.log("Invalid gradient: missing type or colors", .warning)
            return nil
        }
        let colors = names.compactMap(ColorSpec.parse).map(rgba)
        guard !colors.isEmpty else { return nil }
        // Evenly spaced, as SwiftUI's Gradient(colors:); one color is a plain fill.
        let spaced = colors.count == 1 ? [colors[0], colors[0]] : colors
        let stops = spaced.enumerated().map { index, color in
            GskColorStop(offset: Float(index) / Float(spaced.count - 1), color: color)
        }
        let shorter = min(size.width, size.height)
        switch type.lowercased() {
        case "linear":
            guard let start = dict.doubleArray(forKey: "start"), start.count == 2,
                  let end = dict.doubleArray(forKey: "end"), end.count == 2 else { return nil }
            let from = graphene_point_t(x: Float(start[0] * size.width), y: Float(start[1] * size.height))
            let to = graphene_point_t(x: Float(end[0] * size.width), y: Float(end[1] * size.height))
            // An infinite point ("inf" in a document): GTK's cairo renderer warns of an invalid matrix
            // and fails to draw the nodes around it.
            guard [from.x, from.y, to.x, to.y].allSatisfy(\.isFinite) else { return nil }
            return .linear(start: from, end: to, stops: stops)
        case "radial":
            guard let center = dict.doubleArray(forKey: "center"), center.count == 2,
                  let endRadius = dict.double(forKey: "endRadius") else { return nil }
            let middle = graphene_point_t(x: Float(center[0] * size.width), y: Float(center[1] * size.height))
            let startRadius = (dict.double(forKey: "startRadius") ?? 0) * shorter
            // As for a linear gradient.
            guard [middle.x, middle.y, Float(startRadius), Float(endRadius * shorter)].allSatisfy(\.isFinite) else { return nil }
            return .radial(center: middle, startRadius: startRadius, endRadius: endRadius * shorter, stops: stops)
        default:
            logger.log("Unsupported gradient type: \(type)", .warning)
            return nil
        }
    }

    private func fill(_ path: CanvasPath, with shading: Shading, in context: CanvasContext) {
        guard let gskPath = path.gskPath(.identity) else { return }
        defer { gsk_path_unref(gskPath) }
        var bounds = graphene_rect_t()
        guard gsk_path_get_bounds(gskPath, &bounds) != 0, bounds.size.width > 0, bounds.size.height > 0 else { return }
        context.draw { snapshot in
            gtk_snapshot_push_fill(snapshot, gskPath, GSK_FILL_RULE_WINDING)
            switch shading {
            case .linear(var start, var end, let stops):
                if start.x == end.x && start.y == end.y {
                    // GSK needs two points; SwiftUI fills with the last color.
                    var color = stops[stops.count - 1].color
                    gtk_snapshot_append_color(snapshot, &color, &bounds)
                } else {
                    gtk_snapshot_append_linear_gradient(snapshot, &bounds, &start, &end, stops, gsize(stops.count))
                }
            case .radial(var center, let startRadius, let endRadius, let stops):
                // Checked as the floats GSK checks (a tiny radius is 0 there, a start just under the
                // end is 1): GSK refuses them with a critical, and the snapshot then crashes.
                let radius = Float(endRadius), start = Float(startRadius / endRadius)
                if radius > 0, start >= 0, start < 1 {
                    gtk_snapshot_append_radial_gradient(snapshot, &bounds, &center, radius, radius,
                                                        start, 1, stops, gsize(stops.count))
                } else {
                    var color = stops[stops.count - 1].color
                    gtk_snapshot_append_color(snapshot, &color, &bounds)
                }
            }
            gtk_snapshot_pop(snapshot)
        }
    }

    // MARK: Text and images

    private func drawText(_ text: String, _ operation: [String: Any], in frame: Rect, _ context: CanvasContext) {
        guard let layout = gtk_widget_create_pango_layout(widget, text) else { return }
        defer { g_object_unref(UnsafeMutableRawPointer(layout)) }
        let font = pango_font_description_copy(pango_context_get_font_description(pango_layout_get_context(layout)))!
        defer { pango_font_description_free(font) }
        if let size = operation.double(forKey: "fontSize"), size > 0 {
            pango_font_description_set_absolute_size(font, min(size, FontCSS.maximumSize) * Double(PANGO_SCALE))
        }
        if let name = (operation["fontWeight"] as? String)?.lowercased(),
           let weight = FontWeight.allCases.first(where: { $0.rawValue.lowercased() == name }) {
            pango_font_description_set_weight(font, PangoWeight(rawValue: UInt32(FontCSS.cssWeight(weight))))
        }
        pango_layout_set_font_description(layout, font)
        if frame.width > 0 {
            // Clamped as a Double: Int() traps on infinity and on what exceeds Int.
            pango_layout_set_width(layout, Int32(min(frame.width * Double(PANGO_SCALE), Double(Int32.max)).rounded(.down)))
            pango_layout_set_wrap(layout, PANGO_WRAP_WORD_CHAR)
        }
        if operation["alignment"] as? String != nil {
            logger.log("Text alignment currently not supported in Canvas - default alignment used", .info)
        }
        var color = (operation["color"] as? String).flatMap(ColorSpec.parse).map(rgba) ?? GdkRGBA(red: 0, green: 0, blue: 0, alpha: 1)
        context.draw { snapshot in
            var origin = graphene_point_t(x: Float(frame.x), y: Float(frame.y))
            gtk_snapshot_translate(snapshot, &origin)
            gtk_snapshot_append_layout(snapshot, layout, &color)
        }
    }

    /// Draws the image an operation names, stretched to `frame`. False when it names none that
    /// can be drawn.
    private func drawImage(_ operation: [String: Any], in frame: Rect, _ context: CanvasContext) -> Bool {
        let source: ImageSource
        if let name = operation["systemName"] as? String {
            source = .systemName(name)
        } else if let name = operation["assetName"] as? String {
            source = .assetName(name)
        } else if let name = operation["resourceName"] as? String {
            source = ImageSource.resolve(name, interpretation: "resourceName", lookup: Image.lookup)
        } else if let path = operation["filePath"] as? String {
            source = ImageSource.resolve(path, interpretation: "path", lookup: Image.lookup)
        } else {
            return false
        }
        guard frame.width != 0, frame.height != 0 else { return true }
        switch Image.content(source) {
        case .file(let path):
            guard let texture = texture(path) else {
                return drawIcon(Image.iconName(.symbol(ImageSource.placeholderSymbol)), in: frame, context)
            }
            context.draw { snapshot in
                var bounds = graphene_rect_t(origin: graphene_point_t(x: Float(frame.x), y: Float(frame.y)),
                                             size: graphene_size_t(width: Float(frame.width), height: Float(frame.height)))
                gtk_snapshot_append_texture(snapshot, texture, &bounds)
            }
            return true
        case .symbol(let name):
            return drawIcon(Image.iconName(.symbol(name)), in: frame, context)
        case .themeIcon(let name):
            // A missing asset draws nothing, as SwiftUI's Image(name) does.
            guard Image.hasThemeIcon(name) else { return false }
            return drawIcon(name, in: frame, context)
        }
    }

    /// The texture of an image file, read once per canvas; nil when it cannot be read.
    private func texture(_ path: String) -> OpaquePointer? {
        if let cached = state.textures[path] {
            return cached?.pointer
        }
        let texture = gdk_texture_new_from_filename(path, nil).map { LoadedTexture(adopting: $0) }
        state.textures[path] = texture
        return texture?.pointer
    }

    /// Draws the icon `name` stretched to `frame`, a symbolic one in the text color.
    private func drawIcon(_ name: String, in frame: Rect, _ context: CanvasContext) -> Bool {
        guard let display = gtk_widget_get_display(widget) else { return false }
        let side = max(abs(frame.width), abs(frame.height))
        guard side >= 1 else { return true }
        let theme = gtk_icon_theme_get_for_display(display)
        // The size looked up picks the icon's resolution; a document's frame can be any size, and
        // GTK renders the icon at the size looked up (Int32() also traps past Int32.max).
        let lookupSize = Int32(min(side, 2048).rounded(.up))
        guard let lookedUp = gtk_icon_theme_lookup_icon(theme, name, nil, lookupSize, gtk_widget_get_scale_factor(widget),
                                                        gtk_widget_get_direction(widget), GtkIconLookupFlags(0)) else { return false }
        let icon = OwnedObject(adopting: lookedUp)
        var colors = [GdkRGBA](repeating: GdkRGBA(), count: 4)
        gtk_widget_get_color(widget, &colors[0])
        colors[1] = GdkRGBA(red: 0.878, green: 0.106, blue: 0.141, alpha: 1)
        colors[2] = GdkRGBA(red: 0.804, green: 0.576, blue: 0.035, alpha: 1)
        colors[3] = GdkRGBA(red: 0.180, green: 0.761, blue: 0.494, alpha: 1)
        context.draw { snapshot in
            var origin = graphene_point_t(x: Float(frame.x), y: Float(frame.y))
            gtk_snapshot_translate(snapshot, &origin)
            gtk_snapshot_scale(snapshot, Float(frame.width / side), Float(frame.height / side))
            gtk_symbolic_paintable_snapshot_symbolic(icon.opaquePointer, snapshot, side, side, colors, 4)
        }
        return true
    }
}
