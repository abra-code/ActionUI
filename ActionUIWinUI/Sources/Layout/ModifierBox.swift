// Sources/Layout/ModifierBox.swift
/*
 The box around every element's WinUI object, which applies the element's padding, frame,
 background, corner radius, clip shape, offset, rotation, scale and border with SwiftUI's rules (the shared FrameSolver), in
 View.applyModifiers' order, as the GTK renderer's ModifierBox does. Two panels, so the background
 follows the frame, not the room the box is given:

   ModifierBox (outer)   the frame: its size from the proposal and the content; a box given more
                         than its frame (the window's root) centers the frame in it
     (rounded box)       a WinUI Border, only for a box that has had a corner radius: exactly the
                         frame's size, its corners rounding and clipping the group, the background
     content group       exactly the frame's size: the background (without a rounded box), and the
                         padding and the frame's alignment of the element in it
       element object
     border              a stroked rectangle over the frame, when the element has a border

 A parent lays out the outer box, not the object.

 - Padding: the content is offered the space less the padding, and the padded size is the content
   plus the padding (negative padding lets the content overflow).
 - frame(width:height:): the frame is that size whatever its content, and the content is offered it.
 - A flexible frame, given a proposal: with a minimum and a maximum, the proposal clamped to them;
   only a maximum, the proposal up to it but at least the content (it expands up to the maximum);
   only a minimum, the content at least the minimum; with an unbounded proposal, the ideal if given.
   A frame with a maximum makes the element expand in that axis (its stack gives it the room), a
   fixed one keeps it from expanding.
 - background: a color, or a semantic style as the WinUI theme paints it (Paint: "fill.tertiary" is
   a control fill, "background" the window's), fills the frame behind the element.
 - cornerRadius rounds the frame (background and content, clipped), at most half its shorter side,
   as SwiftUI's rounded rectangle; the rounded box is made at the first corner radius and kept.
 - clipShape clips the frame (background and content) to a circle (the largest one, centered), an
   ellipse, a capsule, a rectangle or a rounded rectangle (its own horizontal and vertical radius),
   on the frame's composition visual. It clips what is drawn, not where the pointer is taken.
 - offset, rotationEffect and scaleEffect move what the frame draws and where it takes the pointer,
   not the layout, as in SwiftUI: offset first, then rotation (degrees, clockwise) around the center,
   then scale around its anchor; one matrix computed from the frame's size at each arrange (a render
   transform).
 - border: a rectangle stroked inside the frame (its color, else black; its width, else 1), square
   and where the layout put the frame: SwiftUI applies it after cornerRadius, clipShape, offset,
   rotation and scale, so it follows none of them (the Linux renderer's border does).
 - opacity fades the whole box, background and border included, as on Linux (on Apple the border and
   shadow, applied after it, stay unfaded).
 - hidden keeps the element's space, as SwiftUI's .hidden() does: the box draws nothing and lets the
   pointer through. Its controls lose keyboard focus and accessibility tools skip it (RenderNode).

 - shadow: a drop shadow in the shape of what the frame draws (background and content), not of the
   box, as SwiftUI's: its color (else black at 0.33, SwiftUI's), blurred by its radius, moved by its x
   and y; drawn by an empty element behind the frame from a live capture of the frame's visual, and
   moved with the frame's transform. Unlike SwiftUI's (applied last), it leaves out the border.

 - A background view (SwiftUI's background(alignment:) { view }) lies behind the element in the
   content group, applied before cornerRadius, clipShape and the transforms as on Apple: rounded and
   clipped with the frame, moved with it. An overlay view (overlay(alignment:) { view }) lies over
   the element and its border in the outer box, at the frame's place in the layout, not moved or
   clipped. Each is offered the frame: one that expands (a Color, a shape) fills it, another takes
   its own size (up to it where it can shrink, past it where it cannot: a fixed frame overflows),
   placed by backgroundAlignment or overlayAlignment (center by default);
   neither changes the element's size. A click goes to the overlay, then the element, then the
   background. (RenderNode makes their nodes, as the Linux renderer's NodeDecorations.) As on Linux,
   a background view covers the element's background color, where on Apple the color, applied
   first, covers the view; the element's opacity also fades its overlay (on Apple, applied after).

 Not yet: the other base modifiers the GTK ModifierBox applies. A rounded corner clips where the pointer is taken
 too: WinUI hit-tests a rounded Border's children inside its rounded shape.

 Content larger than its frame (a 220-wide column in a frame 150 wide) overflows it, centered or by
 the frame's alignment, as in SwiftUI: the group reports at most the room it was offered to WinUI
 (LayoutPanel), so WinUI arranges it at the frame's size, not at its content's size aligned to the
 top leading corner and clipped.
*/

// cos, sin: FoundationEssentials does not bring the C math library on Windows.
#if canImport(Darwin)
import Darwin
#elseif os(Windows)
import ucrt
#endif
import CWinUI

/// The padding, frame and background of one element, per axis in whole pixels.
struct BoxGeometry: Equatable {
    var padding = (horizontal: PaddingAxis(), vertical: PaddingAxis())
    var frame = (horizontal: FrameAxis.none, vertical: FrameAxis.none)
    var alignment = (horizontal: StackSolver.Alignment.center, vertical: StackSolver.Alignment.center)
    var background: Paint?
    /// The corner radius rounding the frame; nil: square.
    var cornerRadius: Double?
    /// What the frame draws moves by this, not its layout.
    var offset = (x: 0.0, y: 0.0)
    /// Degrees clockwise around the frame's center, after the offset.
    var rotation = 0.0
    /// A scale around `scaleAnchor` (a unit point of the frame), after the rotation.
    var scale = (x: 1.0, y: 1.0)
    var scaleAnchor = (x: 0.5, y: 0.5)
    /// The shape the frame is clipped to; nil: none.
    var clipShape: BaseModifiers.ClipShape?
    /// The drop shadow under what the frame draws; nil: none.
    var shadow: Shadow?
    /// Where a background view and an overlay view smaller than the frame lie in it.
    var backgroundAlignment = (horizontal: StackSolver.Alignment.center, vertical: StackSolver.Alignment.center)
    var overlayAlignment = (horizontal: StackSolver.Alignment.center, vertical: StackSolver.Alignment.center)

    /// A drop shadow's color, blur and offset.
    struct Shadow: Equatable {
        var color: ActionUIWinUIColor
        var radius: Double
        var x: Double
        var y: Double

        static func == (left: Shadow, right: Shadow) -> Bool {
            left.color.red == right.color.red && left.color.green == right.color.green && left.color.blue == right.color.blue
                && left.color.alpha == right.color.alpha && left.radius == right.radius && left.x == right.x && left.y == right.y
        }
    }
    /// A border stroked inside the frame.
    var border: Stroke?
    /// The whole box's opacity, 0 to 1.
    var opacity = 1.0
    /// Hidden: the box keeps its space but draws nothing and lets the pointer through.
    var hidden = false

    static func == (left: BoxGeometry, right: BoxGeometry) -> Bool {
        left.padding.horizontal == right.padding.horizontal && left.padding.vertical == right.padding.vertical
            && left.frame.horizontal == right.frame.horizontal && left.frame.vertical == right.frame.vertical
            && left.alignment.horizontal == right.alignment.horizontal && left.alignment.vertical == right.alignment.vertical
            && left.background == right.background && left.opacity == right.opacity && left.hidden == right.hidden
            && left.cornerRadius == right.cornerRadius && left.offset == right.offset && left.border == right.border
            && left.rotation == right.rotation && left.scale == right.scale && left.scaleAnchor == right.scaleAnchor
            && left.clipShape == right.clipShape && left.shadow == right.shadow
            && left.backgroundAlignment == right.backgroundAlignment && left.overlayAlignment == right.overlayAlignment
    }

    /// Whether the frame draws moved at all.
    var hasTransform: Bool {
        offset != (0, 0) || rotation != 0 || scale != (1, 1)
    }

    /// A border's paint and width.
    struct Stroke: Equatable {
        var paint: Paint?
        var width: Double
    }

    init() {}

    init(_ modifiers: BaseModifiers) {
        padding = ModifierBox.paddingAxes(modifiers.padding)
        frame = ModifierBox.frameAxes(modifiers.frame)
        alignment = ModifierBox.alignmentAxes(modifiers.frame?.alignment)
        background = Paint.parse(modifiers.background, role: .background)
        if let value = modifiers.opacity, value.isFinite {
            opacity = min(max(value, 0), 1)
        }
        hidden = modifiers.hidden
        if let radius = modifiers.cornerRadius, radius.isFinite, radius > 0 {
            cornerRadius = radius
        }
        if let value = modifiers.offset, value.x.isFinite, value.y.isFinite {
            offset = (value.x, value.y)
        }
        if let degrees = modifiers.rotationDegrees, degrees.isFinite {
            rotation = degrees
        }
        if let value = modifiers.scale, value.x.isFinite, value.y.isFinite {
            scale = (value.x, value.y)
            scaleAnchor = Self.unitPoint(value.anchor)
        }
        clipShape = modifiers.clipShape
        backgroundAlignment = ModifierBox.alignmentAxes(modifiers.backgroundAlignment)
        overlayAlignment = ModifierBox.alignmentAxes(modifiers.overlayAlignment)
        if let value = modifiers.shadow, value.radius.isFinite, value.x.isFinite, value.y.isFinite {
            // Its color when it is one, else SwiftUI's default shadow color.
            var color = ActionUIWinUIColor(red: 0, green: 0, blue: 0, alpha: 0.33)
            if case let .color(given)? = Paint.parse(value.color, role: .foreground) {
                color = given
            }
            shadow = Shadow(color: color, radius: max(value.radius, 0), x: value.x, y: value.y)
        }
        if let value = modifiers.border, value.width.isFinite, value.width > 0 {
            // No color, or one that does not parse: black, as on Apple (resolveColor ?? .black).
            border = Stroke(paint: Paint.parse(value.color, role: .foreground) ?? Paint.parse("black", role: .foreground),
                            width: value.width)
        }
    }

    /// Whether the layout depends on what changed between `self` and `other` (opacity and hidden do not).
    func sameLayout(as other: BoxGeometry) -> Bool {
        var drawn = other
        drawn.opacity = opacity
        drawn.hidden = hidden
        drawn.background = background
        drawn.cornerRadius = cornerRadius
        drawn.offset = offset
        drawn.rotation = rotation
        drawn.scale = scale
        drawn.scaleAnchor = scaleAnchor
        drawn.clipShape = clipShape
        drawn.shadow = shadow
        drawn.border = border
        return drawn == self
    }

    /// A unit point of a frame for an alignment name: (0, 0) top leading, (1, 1) bottom trailing.
    static func unitPoint(_ name: BaseModifiers.AlignmentName) -> (x: Double, y: Double) {
        switch name {
        case .center: return (0.5, 0.5)
        case .leading: return (0, 0.5)
        case .trailing: return (1, 0.5)
        case .top: return (0.5, 0)
        case .bottom: return (0.5, 1)
        case .topLeading: return (0, 0)
        case .topTrailing: return (1, 0)
        case .bottomLeading: return (0, 1)
        case .bottomTrailing: return (1, 1)
        }
    }

    /// The matrix moving what a frame of `width` by `height` draws: offset, then rotation around the
    /// center, then scale around the anchor (SwiftUI's order), as WinUI's (M11, M12, M21, M22,
    /// OffsetX, OffsetY): x' = x M11 + y M21 + OffsetX, y' = x M12 + y M22 + OffsetY.
    func transform(width: Double, height: Double) -> (m11: Double, m12: Double, m21: Double, m22: Double, dx: Double, dy: Double) {
        typealias Affine = (a: Double, b: Double, c: Double, d: Double, tx: Double, ty: Double)
        // first, then second: the point goes through `first`, then `second`.
        func then(_ first: Affine, _ second: Affine) -> Affine {
            (a: second.a * first.a + second.c * first.b, b: second.b * first.a + second.d * first.b,
             c: second.a * first.c + second.c * first.d, d: second.b * first.c + second.d * first.d,
             tx: second.a * first.tx + second.c * first.ty + second.tx, ty: second.b * first.tx + second.d * first.ty + second.ty)
        }
        func translation(_ x: Double, _ y: Double) -> Affine { (1, 0, 0, 1, x, y) }
        var matrix: Affine = translation(offset.x, offset.y)
        if rotation != 0 {
            // Clockwise on screen (y down), as SwiftUI's rotationEffect.
            let radians = rotation * Double.pi / 180
            let turn: Affine = (cos(radians), sin(radians), -sin(radians), cos(radians), 0, 0)
            matrix = then(then(then(matrix, translation(-width / 2, -height / 2)), turn), translation(width / 2, height / 2))
        }
        if scale != (1, 1) {
            let anchor = (x: width * scaleAnchor.x, y: height * scaleAnchor.y)
            let grow: Affine = (scale.x, 0, 0, scale.y, 0, 0)
            matrix = then(then(then(matrix, translation(-anchor.x, -anchor.y)), grow), translation(anchor.x, anchor.y))
        }
        return (matrix.a, matrix.b, matrix.c, matrix.d, matrix.tx, matrix.ty)
    }

    /// How the frame decides expansion in each axis: true or false, nil to follow the content.
    var frameExpansion: (horizontal: Bool?, vertical: Bool?) {
        (frame.horizontal.expands, frame.vertical.expands)
    }
}

@MainActor
final class ModifierBox {
    /// The outer box: the frame, centered in the room it is given.
    let panel: LayoutPanel
    /// Exactly the frame's size: the background, and the element inside the padding.
    let group: LayoutPanel
    let content: WinUIObject
    private(set) var geometry = BoxGeometry()
    /// Whether the content itself expands (its renderer's expansion): content that expands
    /// takes the room inside the padding.
    var contentExpansion: Expansion = []
    /// The padded content's size from the last measure pass, per axis.
    private var padded = (width: 0, height: 0)
    /// The rounded box between the outer box and the group, made at the first corner radius.
    private var rounded: WinUIObject?
    /// The rectangle stroking the border, while there is one.
    private var borderShape: WinUIObject?

    /// What the outer box lays out as the frame and paints and moves: the rounded box, else the group.
    private var frameView: WinUIObject { rounded ?? group.object }
    /// The frame's size at the last arrange, which the transform and the clip shape are computed for.
    private var frameSize = (width: 0.0, height: 0.0)
    /// The clip shape last given to the frame view and its size, so an arrange does not set it again.
    private var appliedClip: (shape: BaseModifiers.ClipShape, width: Double, height: Double)?
    /// The empty element behind the frame that draws its shadow, made at the first shadow and kept.
    private var shadowHost: WinUIObject?

    /// A background or overlay view: its box, and its node's expansion (it fills the frame in the
    /// axes it expands in).
    struct Decoration {
        let view: WinUIObject
        let expansion: () -> Expansion
    }
    /// The background view, behind the content in the group, and the overlay view, last in the
    /// outer box; their sizes from the last measure pass.
    private var backgroundView: Decoration?
    private var overlayView: Decoration?
    private var backgroundDesired = ActionUIWinUISize(width: 0, height: 0)
    private var overlayDesired = ActionUIWinUISize(width: 0, height: 0)
    /// The room the outer box was last offered, from which the group's measure finds the frame's
    /// size to offer the background view (the group itself is offered the frame's bounds).
    private var boxOffer = ActionUIWinUISize(width: .infinity, height: .infinity)

    /// Puts the element's background and overlay views in place, once, as its node is made.
    func setDecorations(background: Decoration?, overlay: Decoration?) {
        let logger = ActionUIModel.shared.logger
        if let background {
            do {
                try group.insert(background.view, at: 0)
                backgroundView = background
            } catch {
                logger.log("ModifierBox: \(error)", .error)
            }
        }
        if let overlay {
            do {
                try panel.append(overlay.view)
                overlayView = overlay
            } catch {
                logger.log("ModifierBox: \(error)", .error)
            }
        }
        if backgroundView != nil || overlayView != nil {
            panel.invalidateLayout()
            group.invalidateLayout()
        }
    }

    /// Where a decoration whose box asks for `desired` (measured for the frame's size) lies in
    /// `frame`: the frame's size in the axes it expands in, else what it asked for, placed by
    /// `alignment`. What it asked for is at most the frame where it can shrink (a Text wraps), and
    /// more where it cannot (a fixed frame wider than the element overflows it, centered by default,
    /// as on Apple, measured, and Linux).
    private func decorationRect(_ decoration: Decoration, desired: ActionUIWinUISize, in frame: ActionUIWinUIRect,
                                alignment: (horizontal: StackSolver.Alignment, vertical: StackSolver.Alignment)) -> ActionUIWinUIRect {
        let expansion = decoration.expansion()
        let frameWidth = StackSolver.length(frame.width)
        let frameHeight = StackSolver.length(frame.height)
        let width = expansion.contains(.horizontal) ? frameWidth : StackSolver.length(desired.width, rounding: .up)
        let height = expansion.contains(.vertical) ? frameHeight : StackSolver.length(desired.height, rounding: .up)
        return ActionUIWinUIRect(x: frame.x + Double(StackSolver.alignedOffset(size: width, block: frameWidth, alignment: alignment.horizontal)),
                                 y: frame.y + Double(StackSolver.alignedOffset(size: height, block: frameHeight, alignment: alignment.vertical)),
                                 width: Double(width), height: Double(height))
    }

    init(content: WinUIObject) throws(WinUIError) {
        self.content = content
        panel = try LayoutPanel()
        group = try LayoutPanel()
        try panel.append(group.object)
        // Last: if anything before fails, the content has no parent and can still be shown bare.
        try group.append(content)
        panel.measure = { [unowned self] available in measure(available) }
        panel.arrange = { [unowned self] finalSize in arrange(finalSize) }
        group.measure = { [unowned self] available in measureGroup(available) }
        group.arrange = { [unowned self] finalSize in arrangeGroup(finalSize) }
    }

    /// Applies new padding, frame, background, corner radius, offset, border, opacity and hidden state;
    /// asks for a layout when the padding or the frame changed, and an arrange when the corner radius
    /// or the border did.
    func update(_ newGeometry: BoxGeometry) {
        guard newGeometry != geometry else { return }
        var moved = false
        if newGeometry.cornerRadius != nil, rounded == nil {
            moved = makeRounded()
        }
        if newGeometry.background != geometry.background || moved {
            Paint.apply(newGeometry.background, ActionUIWinUIBrushBackground, to: frameView, what: "a background")
        }
        let effectsChanged = newGeometry.offset != geometry.offset || newGeometry.rotation != geometry.rotation
            || newGeometry.scale != geometry.scale || newGeometry.scaleAnchor != geometry.scaleAnchor
            || newGeometry.clipShape != geometry.clipShape || newGeometry.shadow != geometry.shadow
        if newGeometry.border != geometry.border {
            updateBorder(newGeometry.border)
        }
        if newGeometry.opacity != geometry.opacity || newGeometry.hidden != geometry.hidden {
            if !actionUIWinUIElementSetOpacity(panel.object.pointer, newGeometry.hidden ? 0 : newGeometry.opacity) {
                ActionUIModel.shared.logger.log("ModifierBox: \(WinUIError.last("setting the opacity"))", .error)
            }
        }
        if newGeometry.hidden != geometry.hidden, !actionUIWinUIElementSetHitTestVisible(panel.object.pointer, !newGeometry.hidden) {
            ActionUIModel.shared.logger.log("ModifierBox: \(WinUIError.last("hiding an element"))", .error)
        }
        let relayout = !newGeometry.sameLayout(as: geometry)
        // The corner radius is clamped to the frame, and the border placed on it, at each arrange.
        let rearrange = newGeometry.cornerRadius != geometry.cornerRadius || newGeometry.border != geometry.border
        geometry = newGeometry
        if effectsChanged || moved {
            applyEffects()
        }
        if relayout {
            panel.invalidateLayout()
            group.invalidateLayout()
        } else if rearrange {
            panel.invalidateLayout()
        }
    }

    /// Puts the group in a new rounded box, which takes its place in the outer box; true when it did
    /// (the background and the offset then move to it).
    private func makeRounded() -> Bool {
        let logger = ActionUIModel.shared.logger
        // Not always the first child: a shadow's host lies behind it.
        guard let index = panel.children.firstIndex(where: { $0 === group.object }) else { return false }
        do {
            try panel.remove(at: index)
        } catch {
            logger.log("ModifierBox: \(error)", .error)
            return false
        }
        guard let box = WinUIObject(adopting: actionUIWinUIRoundedBoxCreate(group.object.pointer)) else {
            logger.log("ModifierBox: \(WinUIError.last("rounding an element's corners"))", .error)
            do {
                try panel.insert(group.object, at: index)
            } catch {
                logger.log("ModifierBox: \(error)", .error)
            }
            return false
        }
        do {
            try panel.insert(box, at: index)
        } catch {
            logger.log("ModifierBox: \(error)", .error)
            return false
        }
        panel.adoptThroughWrapper(group.object)
        rounded = box
        // The group's own background, transform and clip go: the box paints, moves and clips them now.
        Paint.apply(nil, ActionUIWinUIBrushBackground, to: group.object, what: "a background")
        _ = actionUIWinUIElementSetRenderMatrix(group.object.pointer, 1, 0, 0, 1, 0, 0)
        // Only when it had one: asking for the group's composition visual makes WinUI keep it.
        if appliedClip != nil {
            _ = actionUIWinUIElementSetClipShape(group.object.pointer, ActionUIWinUIClipShapeNone, 0, 0, 0, 0)
            appliedClip = nil
        }
        return true
    }

    /// Gives the frame view its transform and clip shape for the frame's last size, and its shadow.
    private func applyEffects() {
        let logger = ActionUIModel.shared.logger
        let (width, height) = frameSize
        let m = geometry.transform(width: width, height: height)
        if !actionUIWinUIElementSetRenderMatrix(frameView.pointer, m.m11, m.m12, m.m21, m.m22, m.dx, m.dy) {
            logger.log("ModifierBox: \(WinUIError.last("moving an element"))", .error)
        }
        applyShadow(m)
        guard let shape = geometry.clipShape else {
            if appliedClip != nil {
                appliedClip = nil
                if !actionUIWinUIElementSetClipShape(frameView.pointer, ActionUIWinUIClipShapeNone, 0, 0, 0, 0) {
                    logger.log("ModifierBox: \(WinUIError.last("unclipping an element"))", .error)
                }
            }
            return
        }
        if let applied = appliedClip, applied.shape == shape, applied.width == width, applied.height == height {
            return
        }
        appliedClip = (shape, width, height)
        let kind: ActionUIWinUIClipShapeKind
        var radius = (x: 0.0, y: 0.0)
        switch shape {
        case .rectangle:
            kind = ActionUIWinUIClipShapeRectangle
        case .circle:
            kind = ActionUIWinUIClipShapeCircle
        case .ellipse:
            kind = ActionUIWinUIClipShapeEllipse
        case .capsule:
            kind = ActionUIWinUIClipShapeRoundedRectangle
            let half = min(width, height) / 2
            radius = (half, half)
        case let .roundedRectangle(radiusX, radiusY):
            kind = ActionUIWinUIClipShapeRoundedRectangle
            radius = (radiusX.isFinite ? radiusX : 0, radiusY.isFinite ? radiusY : 0)
        }
        if !actionUIWinUIElementSetClipShape(frameView.pointer, kind, width, height, radius.x, radius.y) {
            logger.log("ModifierBox: \(WinUIError.last("clipping an element"))", .error)
        }
    }

    /// Makes the shadow's host behind the frame at the first shadow, and draws or removes the shadow.
    /// The host is not moved: the capture of the frame already carries the frame's transform (`m`), so
    /// the shadow covers the bounds of the frame moved by it.
    private func applyShadow(_ m: (m11: Double, m12: Double, m21: Double, m22: Double, dx: Double, dy: Double)) {
        let logger = ActionUIModel.shared.logger
        if geometry.shadow != nil, shadowHost == nil {
            do {
                let host = try LayoutPanel()
                try panel.insert(host.object, at: 0)
                if !actionUIWinUIElementSetHitTestVisible(host.object.pointer, false) {
                    logger.log("ModifierBox: \(WinUIError.last("drawing a shadow"))", .error)
                }
                shadowHost = host.object
                // The outer box lays it out at the frame.
                panel.invalidateLayout()
            } catch {
                logger.log("ModifierBox: \(error)", .error)
                return
            }
        }
        guard let host = shadowHost else { return }
        let shown: Bool
        if let shadow = geometry.shadow {
            // Not before the frame has a size: WinUI draws no surface under half a pixel; the arrange
            // that gives it one draws the shadow.
            guard frameSize.width > 0, frameSize.height > 0 else { return }
            var color = shadow.color
            // The frame's corners moved by the transform, and the rectangle around them.
            let (width, height) = frameSize
            let corners = [(0.0, 0.0), (width, 0.0), (0.0, height), (width, height)].map { x, y in
                (x: x * m.m11 + y * m.m21 + m.dx, y: x * m.m12 + y * m.m22 + m.dy)
            }
            let left = corners.map(\.x).min() ?? 0
            let top = corners.map(\.y).min() ?? 0
            let right = corners.map(\.x).max() ?? 0
            let bottom = corners.map(\.y).max() ?? 0
            // SwiftUI's radius is the blur's deviation; Composition's blur radius is about twice it.
            shown = actionUIWinUIElementSetShadow(host.pointer, frameView.pointer, &color, shadow.radius * 2, shadow.x, shadow.y,
                                                  left, top, right - left, bottom - top)
        } else {
            shown = actionUIWinUIElementSetShadow(host.pointer, frameView.pointer, nil, 0, 0, 0, 0, 0, 0, 0)
        }
        if !shown {
            logger.log("ModifierBox: \(WinUIError.last("drawing a shadow"))", .error)
        }
    }

    /// Makes, paints or removes the rectangle stroking the border.
    private func updateBorder(_ border: BoxGeometry.Stroke?) {
        let logger = ActionUIModel.shared.logger
        guard let border else {
            if let shape = borderShape, let index = panel.children.firstIndex(where: { $0 === shape }) {
                do {
                    try panel.remove(at: index)
                } catch {
                    logger.log("ModifierBox: \(error)", .error)
                }
            }
            borderShape = nil
            return
        }
        if borderShape == nil {
            guard let shape = WinUIObject(adopting: actionUIWinUIShapeCreate(ActionUIWinUIShapeRectangle)) else {
                logger.log("ModifierBox: \(WinUIError.last("drawing a border"))", .error)
                return
            }
            // Over the frame, taking no input.
            if !actionUIWinUIElementSetHitTestVisible(shape.pointer, false) {
                logger.log("ModifierBox: \(WinUIError.last("drawing a border"))", .error)
            }
            do {
                // Under an overlay view, which SwiftUI applies after the border.
                if let overlay = overlayView, let index = panel.children.firstIndex(where: { $0 === overlay.view }) {
                    try panel.insert(shape, at: index)
                } else {
                    try panel.append(shape)
                }
            } catch {
                logger.log("ModifierBox: \(error)", .error)
                return
            }
            borderShape = shape
        }
        guard let shape = borderShape else { return }
        Paint.apply(border.paint, ActionUIWinUIBrushStroke, to: shape, what: "a border")
        if !actionUIWinUIShapeSetStrokeThickness(shape.pointer, border.width) {
            logger.log("ModifierBox: \(WinUIError.last("drawing a border"))", .error)
        }
    }

    // MARK: Layout, one axis at a time

    /// What the content group is offered in one axis, for a proposal of `offer` (infinite when
    /// unbounded): the proposal within the frame's bounds.
    private func groupOffer(_ offer: Double, frame: FrameAxis) -> Double {
        if let fixed = frame.fixed {
            return Double(fixed)
        }
        var size = offer
        if let minimum = frame.minimum, size.isFinite || frame.maximum != nil {
            size = max(size, Double(minimum))
        }
        if let maximum = frame.maximum, maximum != FrameAxis.infinity {
            size = min(size, Double(maximum))
        }
        return size
    }

    /// The frame's size in one axis for a proposal of `offer`, the padded content asking for `padded`.
    private func frameSize(_ offer: Double, padded: Int, frame: FrameAxis) -> Int {
        if let fixed = frame.fixed {
            return fixed
        }
        guard offer.isFinite else {
            // Unbounded: the frame's ideal size.
            return frame.naturalSize(content: padded, contentMinimum: padded)
        }
        let proposal = StackSolver.length(offer)
        switch (frame.minimum, frame.maximum) {
        case let (low?, high?):
            return high == FrameAxis.infinity ? max(proposal, low) : max(min(proposal, high), low)
        case let (nil, high?):
            return high == FrameAxis.infinity ? max(proposal, padded) : max(min(proposal, high), padded)
        case let (low?, nil):
            return max(padded, low)
        case (nil, nil):
            return padded
        }
    }

    private func measure(_ available: ActionUIWinUISize) -> ActionUIWinUISize {
        let offer = ActionUIWinUISize(width: groupOffer(available.width, frame: geometry.frame.horizontal),
                                      height: groupOffer(available.height, frame: geometry.frame.vertical))
        boxOffer = available
        _ = frameView.measure(offer)
        shadowHost.map { _ = $0.measure(offer) }
        borderShape.map { _ = $0.measure(offer) }
        let width = frameSize(available.width, padded: padded.width, frame: geometry.frame.horizontal)
        let height = frameSize(available.height, padded: padded.height, frame: geometry.frame.vertical)
        // The overlay view, offered the frame.
        if let overlay = overlayView {
            overlayDesired = overlay.view.measureRequested(ActionUIWinUISize(width: Double(width), height: Double(height)))
        }
        return ActionUIWinUISize(width: Double(width), height: Double(height))
    }

    /// The group's measure pass: the content offered the room less the padding; the padded size.
    private func measureGroup(_ available: ActionUIWinUISize) -> ActionUIWinUISize {
        func inner(_ size: Double, _ padding: PaddingAxis) -> Double {
            size.isFinite ? max(size - Double(padding.total), 0) : size
        }
        // What the content asks for even beyond the room (a stack's children at their smallest), so
        // the box's own answer is its true size: a stack measuring it with nothing offered learns
        // its smallest size.
        let desired = content.measureRequested(ActionUIWinUISize(width: inner(available.width, geometry.padding.horizontal),
                                                        height: inner(available.height, geometry.padding.vertical)))
        padded = (StackSolver.length(desired.width, rounding: .up) + geometry.padding.horizontal.total,
                  StackSolver.length(desired.height, rounding: .up) + geometry.padding.vertical.total)
        // The background view, offered the frame's size (as the outer measure computes it), not the
        // group's room, which can be wider or unbounded: a Text measured wider than the frame it is
        // arranged in would overflow it instead of wrapping.
        if let background = backgroundView {
            let frame = ActionUIWinUISize(width: Double(frameSize(boxOffer.width, padded: padded.width, frame: geometry.frame.horizontal)),
                                          height: Double(frameSize(boxOffer.height, padded: padded.height, frame: geometry.frame.vertical)))
            backgroundDesired = background.view.measureRequested(frame)
        }
        return ActionUIWinUISize(width: Double(max(padded.width, 0)), height: Double(max(padded.height, 0)))
    }

    private func arrange(_ finalSize: ActionUIWinUISize) {
        let boxWidth = StackSolver.length(finalSize.width)
        let boxHeight = StackSolver.length(finalSize.height)
        // The frame in the room given: what the frame takes of it, centered in the rest.
        let width = geometry.frame.horizontal.size(in: boxWidth, contentMinimum: padded.width, contentNatural: padded.width,
                                                   contentExpands: contentExpansion.contains(.horizontal))
        let height = geometry.frame.vertical.size(in: boxHeight, contentMinimum: padded.height, contentNatural: padded.height,
                                                  contentExpands: contentExpansion.contains(.vertical))
        let frame = ActionUIWinUIRect(x: Double(StackSolver.centeredStart(length: width, available: boxWidth)),
                                      y: Double(StackSolver.centeredStart(length: height, available: boxHeight)),
                                      width: Double(width), height: Double(height))
        if let rounded {
            // At most half the shorter side, as SwiftUI's rounded rectangle (WinUI clamps each axis on
            // its own, which would make the corners elliptical).
            let radius = min(geometry.cornerRadius ?? 0, Double(min(width, height)) / 2)
            if !actionUIWinUIRoundedBoxSetCornerRadius(rounded.pointer, max(radius, 0)) {
                ActionUIModel.shared.logger.log("ModifierBox: \(WinUIError.last("rounding an element's corners"))", .error)
            }
        }
        frameView.arrange(frame)
        shadowHost?.arrange(frame)
        borderShape?.arrange(frame)
        if let overlay = overlayView {
            overlay.view.arrange(decorationRect(overlay, desired: overlayDesired, in: frame, alignment: geometry.overlayAlignment))
        }
        // The transform's center and anchor, the clip shape and the shadow follow the frame's size.
        if frameSize != (frame.width, frame.height) {
            frameSize = (frame.width, frame.height)
            if geometry.hasTransform || geometry.clipShape != nil || geometry.shadow != nil {
                applyEffects()
            }
        }
    }

    /// Where the content goes in one axis of a group of `size`: its size (what it asked for, or all
    /// the room inside the padding when it expands) and its offset by the frame's alignment.
    private func place(size: Int, desired: Int, padding: PaddingAxis, expands: Bool,
                       alignment: StackSolver.Alignment) -> (offset: Int, size: Int) {
        let contentSize = FrameSolver.contentSize(in: size, padding: padding, minimum: desired, natural: desired, expands: expands)
        let room = size - padding.total
        return (padding.before + StackSolver.alignedOffset(size: contentSize, block: room, alignment: alignment), contentSize)
    }

    private func arrangeGroup(_ finalSize: ActionUIWinUISize) {
        let width = StackSolver.length(finalSize.width)
        let height = StackSolver.length(finalSize.height)
        let desiredWidth = padded.width - geometry.padding.horizontal.total
        let desiredHeight = padded.height - geometry.padding.vertical.total
        let horizontal = place(size: width, desired: desiredWidth, padding: geometry.padding.horizontal,
                               expands: contentExpansion.contains(.horizontal), alignment: geometry.alignment.horizontal)
        let vertical = place(size: height, desired: desiredHeight, padding: geometry.padding.vertical,
                             expands: contentExpansion.contains(.vertical), alignment: geometry.alignment.vertical)
        content.arrange(ActionUIWinUIRect(x: Double(horizontal.offset), y: Double(vertical.offset),
                                          width: Double(horizontal.size), height: Double(vertical.size)))
        if let background = backgroundView {
            background.view.arrange(decorationRect(background, desired: backgroundDesired,
                                                   in: ActionUIWinUIRect(x: 0, y: 0, width: Double(width), height: Double(height)),
                                                   alignment: geometry.backgroundAlignment))
        }
    }

    // MARK: From the document's modifiers (as the GTK renderer's ModifierBox reads them)

    nonisolated static func paddingAxes(_ padding: BaseModifiers.Padding?) -> (horizontal: PaddingAxis, vertical: PaddingAxis) {
        switch padding {
        case nil:
            return (PaddingAxis(), PaddingAxis())
        case .system:
            let value = FrameSolver.systemPadding
            return (PaddingAxis(before: value, after: value), PaddingAxis(before: value, after: value))
        case let .uniform(length):
            let value = StackSolver.signedLength(length)
            return (PaddingAxis(before: value, after: value), PaddingAxis(before: value, after: value))
        case let .edges(top, leading, bottom, trailing):
            return (PaddingAxis(before: StackSolver.signedLength(leading), after: StackSolver.signedLength(trailing)),
                    PaddingAxis(before: StackSolver.signedLength(top), after: StackSolver.signedLength(bottom)))
        }
    }

    nonisolated static func frameAxes(_ frame: BaseModifiers.Frame?) -> (horizontal: FrameAxis, vertical: FrameAxis) {
        guard let frame else { return (.none, .none) }
        // A fixed frame wins over the flexible keys, as on Apple and Linux.
        if frame.isFixed {
            return (FrameAxis(fixed: frame.width.map { StackSolver.length($0) }),
                    FrameAxis(fixed: frame.height.map { StackSolver.length($0) }))
        }
        func length(_ value: Double) -> Int { StackSolver.length(value) }
        func maximum(_ value: Double) -> Int { value == .infinity ? FrameAxis.infinity : StackSolver.length(value) }
        return (.flexible(minimum: frame.minWidth.map(length), ideal: frame.idealWidth.map(length), maximum: frame.maxWidth.map(maximum)),
                .flexible(minimum: frame.minHeight.map(length), ideal: frame.idealHeight.map(length), maximum: frame.maxHeight.map(maximum)))
    }

    nonisolated static func alignmentAxes(_ alignment: BaseModifiers.AlignmentName?) -> (horizontal: StackSolver.Alignment, vertical: StackSolver.Alignment) {
        switch alignment ?? .center {
        case .center: return (.center, .center)
        case .leading: return (.start, .center)
        case .trailing: return (.end, .center)
        case .top: return (.center, .start)
        case .bottom: return (.center, .end)
        case .topLeading: return (.start, .start)
        case .topTrailing: return (.end, .start)
        case .bottomLeading: return (.start, .end)
        case .bottomTrailing: return (.end, .end)
        }
    }
}
