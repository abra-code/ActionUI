// Sources/Elements/Canvas+WinUI.swift
/*
 Canvas on WinUI: the operations drawn with Direct2D into a bitmap at the window's scale (the shim's
 Drawing API), shown by a WinUI Image that fills the canvas, following ActionUI's Apple drawing code
 (Helpers/CanvasRenderer.swift) as the Linux renderer records it (Canvas+Adwaita.swift, measured on
 macOS 27). Greedy in both axes with Color's ideal size (FillLayout), as SwiftUI's Canvas is. The
 background color fills it first; a tap on it fires actionID. Drawn again when its properties change
 and when its size changes.

 As Apple's code draws, and the Linux renderer:
 - Coordinates: normalized values are fractions of the canvas, x of its width, y of its height, radii
   of the shorter side; line widths and dashes are points in both modes.
 - A fill without a valid color draws nothing.
 - An arc's clockwise flag is SwiftUI's (1 runs with decreasing angles on the screen); angles whole
   turns apart draw a circle with either flag; an arc after a point is joined to it by a line. A
   path's lines and curves before any moveTo are left out.
 - A roundedRect's cornerRadii use the first radius for all four corners; its corners are circular.
 - translate, scale, rotate (degrees, clockwise) and clip apply to the operations after them; after
   an infinite transform nothing more is drawn.
 - A line width of 0 draws nothing; past the miter limit a corner is beveled.
 - Drawing stops at the canvas's edges.
 - A tap is the canvas's own, with or without an actionID, as Apple's tap gesture is: an element
   around it does not see it.

 Not yet (skipped, logged once per kind): gradients, text, images, shadow, blur and layers. Not
 drawn again when the window moves to a monitor with another scale until its size or properties
 change.
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
// cos, sin, tan: FoundationEssentials does not bring the C math library on Windows.
#if canImport(Darwin)
import Darwin
#elseif os(Windows)
import ucrt
#endif
import CWinUI

/// What a Canvas keeps: its layout, the image showing its drawing, and what it drew for.
@MainActor final class CanvasState {
    let fill: FillLayout
    let image: WinUIObject
    var props = Canvas.Props([:])
    /// The size and scale last drawn at; nil before the first drawing.
    var drawnSize: ActionUIWinUISize?
    var drawnScale: Double?
    /// The properties changed since the last drawing.
    var needsDrawing = true
    /// The operation kinds not drawn yet, logged once each.
    var reportedSkipped: Set<String> = []

    init(fill: FillLayout, image: WinUIObject) {
        self.fill = fill
        self.image = image
    }
}

extension Canvas: ActionUIWinUIRenderer {
    static var defaultExpansion: Expansion { .both }

    static func makeView(_ node: RenderNode) throws(WinUIError) -> WinUIObject {
        guard let image = WinUIObject(adopting: actionUIWinUIImageCreate()) else {
            throw WinUIError.last("creating a Canvas's image")
        }
        let fill = try FillLayout(child: image)
        let state = CanvasState(fill: fill, image: image)
        node.state = state
        fill.arranged = { [weak state] size in
            guard let state else { return }
            drawIfNeeded(state, size: size)
        }
        // Hit-testable everywhere, also where nothing is drawn.
        Paint.apply(.color(ActionUIWinUIColor(red: 0, green: 0, blue: 0, alpha: 0)), ActionUIWinUIBrushBackground,
                    to: fill.panel.object, what: "a Canvas")
        WinUIEvents.connect(fill.panel.object, actionUIWinUIElementOnTapped, "a Canvas's tap") { [weak node] in
            guard let node, node.isAttached, let actionID = Props(node.properties).actionID else { return }
            ActionUIModel.shared.actionHandler(actionID, windowUUID: node.windowModel.windowUUID, viewID: node.element.id, viewPartID: 0)
        }
        return fill.panel.object
    }

    static func update(_ view: WinUIObject, _ node: RenderNode) {
        guard let state = node.state as? CanvasState else { return }
        state.props = Props(node.properties)
        state.needsDrawing = true
        if let size = state.drawnSize {
            drawIfNeeded(state, size: size)
        }
    }

    /// Draws for `size` when the properties, the size or the window's scale changed since the last
    /// drawing.
    private static func drawIfNeeded(_ state: CanvasState, size: ActionUIWinUISize) {
        let scale = actionUIWinUIElementRasterizationScale(state.image.pointer)
        let sameSize = state.drawnSize.map { $0.width == size.width && $0.height == size.height } ?? false
        guard state.needsDrawing || !sameSize || state.drawnScale != scale else { return }
        state.needsDrawing = false
        state.drawnSize = size
        state.drawnScale = scale
        guard size.width > 0, size.height > 0, size.width.isFinite, size.height.isFinite else { return }
        guard let drawing = actionUIWinUIDrawingBegin(size.width, size.height, scale) else {
            ActionUIModel.shared.logger.log("Canvas: \(WinUIError.last("starting a drawing of \(size.width) x \(size.height)"))", .error)
            return
        }
        let canvas = CanvasDrawing(drawing: drawing, state: state, points: state.props.coordinateMode == .points)
        if let background = state.props.backgroundColor.flatMap(ColorSpec.parse) {
            let color = ColorRGBA.resolve(background)
            if color.alpha > 0 {
                let path = CanvasPath()
                path.addRect(x: 0, y: 0, width: size.width, height: size.height)
                canvas.fill(path, color, transform: .identity)
            }
        }
        var transform = CanvasAffine.identity
        canvas.draw(state.props.operations, size: CanvasSize(width: size.width, height: size.height), transform: &transform)
        if !actionUIWinUIDrawingFinish(drawing, state.image.pointer) {
            ActionUIModel.shared.logger.log("Canvas: \(WinUIError.last("showing the drawing"))", .error)
        }
    }
}

struct CanvasSize {
    var width: Double
    var height: Double
}

/// A 2D affine transform: x' = a x + c y + tx, y' = b x + d y + ty.
struct CanvasAffine {
    var a = 1.0, b = 0.0, c = 0.0, d = 1.0, tx = 0.0, ty = 0.0

    static let identity = CanvasAffine()

    /// False after an infinite step (or one that made a NaN), after which SwiftUI draws nothing
    /// (measured on macOS 27), and after one Direct2D's floats cannot hold.
    var isFinite: Bool {
        [a, b, c, d, tx, ty].allSatisfy { $0.isFinite && Float($0).isFinite }
    }

    /// This transform after moving by (x, y) in its own coordinates.
    func translated(_ x: Double, _ y: Double) -> CanvasAffine {
        var result = self
        result.tx = a * x + c * y + tx
        result.ty = b * x + d * y + ty
        return result
    }

    func scaled(_ x: Double, _ y: Double) -> CanvasAffine {
        var result = self
        result.a = a * x
        result.b = b * x
        result.c = c * y
        result.d = d * y
        return result
    }

    /// Rotated by `degrees` clockwise on the screen (y down).
    func rotated(_ degrees: Double) -> CanvasAffine {
        let radians = degrees.truncatingRemainder(dividingBy: 360) * .pi / 180
        let cosine = cos(radians), sine = sin(radians)
        var result = self
        result.a = a * cosine + c * sine
        result.b = b * cosine + d * sine
        result.c = -a * sine + c * cosine
        result.d = -b * sine + d * cosine
        return result
    }
}

/// A path in a canvas's coordinates, as the shim's segments: arcs, circles, ellipses and rounded
/// corners are cubic Beziers (Direct2D draws no conics).
final class CanvasPath {
    enum Segment {
        case move(Double, Double)
        case line(Double, Double)
        case quad(Double, Double, Double, Double)
        case cubic(Double, Double, Double, Double, Double, Double)
        case close
    }

    private(set) var segments: [Segment] = []
    private var current: (Double, Double)?
    private var subpathStart: (Double, Double)?
    /// A coordinate that is not a number, or one Direct2D's floats cannot hold: the path draws nothing.
    private(set) var isFinite = true

    var isEmpty: Bool { segments.isEmpty }

    private func check(_ values: Double...) {
        if !values.allSatisfy({ $0.isFinite && Float($0).isFinite }) {
            isFinite = false
        }
    }

    func move(_ x: Double, _ y: Double) {
        check(x, y)
        segments.append(.move(x, y))
        current = (x, y)
        subpathStart = (x, y)
    }

    // A line or curve with no current point (no moveTo before it) is left out, as SwiftUI's Path
    // leaves it out (measured on macOS 27).
    func line(_ x: Double, _ y: Double) {
        guard current != nil else { return }
        check(x, y)
        segments.append(.line(x, y))
        current = (x, y)
    }

    func quad(_ cx: Double, _ cy: Double, _ x: Double, _ y: Double) {
        guard current != nil else { return }
        check(cx, cy, x, y)
        segments.append(.quad(cx, cy, x, y))
        current = (x, y)
    }

    func cubic(_ c1x: Double, _ c1y: Double, _ c2x: Double, _ c2y: Double, _ x: Double, _ y: Double) {
        guard current != nil else { return }
        check(c1x, c1y, c2x, c2y, x, y)
        segments.append(.cubic(c1x, c1y, c2x, c2y, x, y))
        current = (x, y)
    }

    func close() {
        guard current != nil else { return }
        segments.append(.close)
        current = subpathStart
    }

    /// A circular arc of `radius` around (cx, cy) from `startRadians` turning by `sweep` radians (at
    /// most a quarter turn), as one cubic Bezier.
    private func arcPiece(cx: Double, cy: Double, rx: Double, ry: Double, from startRadians: Double, sweep: Double) {
        let end = startRadians + sweep
        let k = 4.0 / 3.0 * tan(sweep / 4)
        let (cosA, sinA, cosB, sinB) = (cos(startRadians), sin(startRadians), cos(end), sin(end))
        cubic(cx + rx * (cosA - k * sinA), cy + ry * (sinA + k * cosA),
              cx + rx * (cosB + k * sinB), cy + ry * (sinB - k * cosB),
              cx + rx * cosB, cy + ry * sinB)
    }

    /// An arc of the circle at (cx, cy) with `radius` from `start` to `end` degrees, joined to the
    /// current point by a line. `clockwise` is SwiftUI's flag: true runs with decreasing angles on
    /// the screen (y down). The sweep is SwiftUI's (measured on macOS 27): in the flag's direction, a
    /// full turn and what is left past it; against it, the rest of a turn, or a full turn when the
    /// angles are whole turns apart. Non-finite angles draw nothing.
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
        let startRadians = start.truncatingRemainder(dividingBy: 360) * .pi / 180
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
            arcPiece(cx: cx, cy: cy, rx: radius, ry: radius, from: angle, sweep: step)
            angle += step
        }
    }

    func addRect(x: Double, y: Double, width: Double, height: Double) {
        move(x, y)
        line(x + width, y)
        line(x + width, y + height)
        line(x, y + height)
        close()
    }

    /// An ellipse touching the rect's sides, as four quarter arcs from its right end, clockwise on
    /// the screen.
    func addEllipse(x: Double, y: Double, width: Double, height: Double) {
        let rx = width / 2, ry = height / 2
        let cx = x + rx, cy = y + ry
        move(cx + rx, cy)
        for quarter in 0..<4 {
            arcPiece(cx: cx, cy: cy, rx: rx, ry: ry, from: Double(quarter) * .pi / 2, sweep: .pi / 2)
        }
        close()
    }

    /// A rect with circular corners of `radius`, at most half its shorter side, as SwiftUI clamps it.
    func addRoundedRect(x: Double, y: Double, width: Double, height: Double, radius: Double) {
        let r = min(max(radius, 0), min(abs(width), abs(height)) / 2)
        guard r > 0 else { return addRect(x: x, y: y, width: width, height: height) }
        let minX = x, maxX = x + width, minY = y, maxY = y + height
        let quarter = Double.pi / 2
        move(minX + r, minY)
        line(maxX - r, minY)
        arcPiece(cx: maxX - r, cy: minY + r, rx: r, ry: r, from: -quarter, sweep: quarter)
        line(maxX, maxY - r)
        arcPiece(cx: maxX - r, cy: maxY - r, rx: r, ry: r, from: 0, sweep: quarter)
        line(minX + r, maxY)
        arcPiece(cx: minX + r, cy: maxY - r, rx: r, ry: r, from: quarter, sweep: quarter)
        line(minX, minY + r)
        arcPiece(cx: minX + r, cy: minY + r, rx: r, ry: r, from: 2 * quarter, sweep: quarter)
        close()
    }
}

/// Draws a canvas's operations through the shim, as CanvasRenderer.draw does on Apple.
@MainActor struct CanvasDrawing {
    let drawing: OpaquePointer
    let state: CanvasState
    let points: Bool
    private var logger: any ActionUILogger { ActionUIModel.shared.logger }

    init(drawing: OpaquePointer, state: CanvasState, points: Bool) {
        self.drawing = drawing
        self.state = state
        self.points = points
    }

    func draw(_ operations: [[String: Any]], size: CanvasSize, transform: inout CanvasAffine) {
        for operation in operations {
            guard let type = operation["type"] as? String else { continue }
            switch type.lowercased() {
            case "fill":
                guard let path = makePath(operation["path"] as? [String: Any], size: size) else { continue }
                // A valid gradient is not drawn yet; an invalid one falls back to the color, as on
                // Linux and Apple.
                if let gradient = operation["gradient"] as? [String: Any], gradient["type"] is String,
                   ((gradient["colors"] as? [String]) ?? []).compactMap(ColorSpec.parse).count >= 1,
                   ((gradient["colors"] as? [String]) ?? []).count >= 2 {
                    skip("gradient")
                } else if let color = (operation["color"] as? String).flatMap(ColorSpec.parse) {
                    fill(path, ColorRGBA.resolve(color), transform: transform)
                } else {
                    logger.log("No valid color or gradient for fill", .warning)
                }

            case "stroke":
                guard let path = makePath(operation["path"] as? [String: Any], size: size),
                      let color = (operation["color"] as? String).flatMap(ColorSpec.parse) else {
                    logger.log("Missing/invalid path or color for stroke", .warning)
                    continue
                }
                stroke(path, ColorRGBA.resolve(color), operation, transform: transform)

            case "clip":
                if let path = makePath(operation["path"] as? [String: Any], size: size), transform.isFinite, path.isFinite {
                    if send(path, transform: transform), !actionUIWinUIDrawingClip(drawing) {
                        logger.log("Canvas: \(WinUIError.last("clipping"))", .error)
                    }
                }

            case "translate":
                transform = transform.translated(operation.double(forKey: "x") ?? 0, operation.double(forKey: "y") ?? 0)

            case "scale":
                transform = transform.scaled(operation.double(forKey: "x") ?? 1, operation.double(forKey: "y") ?? 1)

            case "rotate":
                if let degrees = operation.double(forKey: "angle") {
                    transform = transform.rotated(degrees)
                }

            case "text", "image", "shadow", "blur", "layer":
                skip(type.lowercased())

            default:
                logger.log("Unknown operation type: \(type)", .warning)
            }
        }
    }

    /// Logs once per canvas that an operation kind is not drawn on Windows yet.
    private func skip(_ kind: String) {
        guard state.reportedSkipped.insert(kind).inserted else { return }
        logger.log("Canvas: \(kind) is not drawn on Windows yet; skipped", .warning)
    }

    /// Gives the shim `path` under `transform`; false when there is nothing to draw.
    private func send(_ path: CanvasPath, transform: CanvasAffine) -> Bool {
        guard !path.isEmpty, path.isFinite, transform.isFinite else { return false }
        var sent = actionUIWinUIDrawingSetTransform(drawing, transform.a, transform.b, transform.c, transform.d, transform.tx, transform.ty)
        for segment in path.segments {
            switch segment {
            case let .move(x, y):
                sent = sent && actionUIWinUIDrawingMoveTo(drawing, x, y)
            case let .line(x, y):
                sent = sent && actionUIWinUIDrawingLineTo(drawing, x, y)
            case let .quad(cx, cy, x, y):
                sent = sent && actionUIWinUIDrawingQuadTo(drawing, cx, cy, x, y)
            case let .cubic(c1x, c1y, c2x, c2y, x, y):
                sent = sent && actionUIWinUIDrawingCubicTo(drawing, c1x, c1y, c2x, c2y, x, y)
            case .close:
                sent = sent && actionUIWinUIDrawingClose(drawing)
            }
        }
        if !sent {
            logger.log("Canvas: \(WinUIError.last("building a path"))", .error)
        }
        return sent
    }

    func fill(_ path: CanvasPath, _ color: ActionUIWinUIColor, transform: CanvasAffine) {
        guard send(path, transform: transform) else { return }
        if !actionUIWinUIDrawingFill(drawing, color) {
            logger.log("Canvas: \(WinUIError.last("filling a path"))", .error)
        }
    }

    private func stroke(_ path: CanvasPath, _ color: ActionUIWinUIColor, _ operation: [String: Any], transform: CanvasAffine) {
        // A line width of 0 draws nothing (measured on macOS 27).
        let lineWidth = operation.double(forKey: "lineWidth") ?? 1
        guard lineWidth > 0, lineWidth.isFinite, send(path, transform: transform) else { return }
        let cap: ActionUIWinUILineCap
        switch (operation["lineCap"] as? String ?? "butt").lowercased() {
        case "round": cap = ActionUIWinUILineCapRound
        case "square": cap = ActionUIWinUILineCapSquare
        default: cap = ActionUIWinUILineCapButt
        }
        let join: ActionUIWinUILineJoin
        switch (operation["lineJoin"] as? String ?? "miter").lowercased() {
        case "round": join = ActionUIWinUILineJoinRound
        case "bevel": join = ActionUIWinUILineJoinBevel
        default: join = ActionUIWinUILineJoinMiter
        }
        let dash = operation.doubleArray(forKey: "dash") ?? []
        let drawn = dash.withUnsafeBufferPointer { buffer in
            actionUIWinUIDrawingStroke(drawing, color, lineWidth, cap, join, operation.double(forKey: "miterLimit") ?? 10,
                                       buffer.baseAddress, Int32(buffer.count), operation.double(forKey: "dashPhase") ?? 0)
        }
        if !drawn {
            logger.log("Canvas: \(WinUIError.last("stroking a path"))", .error)
        }
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
}
