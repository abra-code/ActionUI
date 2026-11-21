// Sources/Layout/ModifierBox.swift
/*
 The box around every element's WinUI object, which applies the element's padding, frame,
 background, corner radius, offset and border with SwiftUI's rules (the shared FrameSolver), in
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
 - offset moves what the frame draws (background and content) and where it takes the pointer, not
   the layout, as SwiftUI's offset (a render transform).
 - border: a rectangle stroked inside the frame (its color, else black; its width, else 1), square
   and where the layout put the frame: SwiftUI applies it after cornerRadius and offset, so it
   neither follows the rounding nor moves with the offset (the Linux renderer's border does both).
 - opacity fades the whole box, background and border included, as on Linux (on Apple the border and
   shadow, applied after it, stay unfaded).
 - hidden keeps the element's space, as SwiftUI's .hidden() does: the box draws nothing and lets the
   pointer through. Its controls lose keyboard focus and accessibility tools skip it (RenderNode).

 Not yet: clipShape, shadow, rotationEffect, scaleEffect, blur, overlay and background views, and the
 other base modifiers the GTK ModifierBox applies. A rounded corner clips where the pointer is taken
 too: WinUI hit-tests a rounded Border's children inside its rounded shape.

 Content larger than its frame (a 220-wide column in a frame 150 wide) overflows it, centered or by
 the frame's alignment, as in SwiftUI: the group reports at most the room it was offered to WinUI
 (LayoutPanel), so WinUI arranges it at the frame's size, not at its content's size aligned to the
 top leading corner and clipped.
*/

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
        drawn.border = border
        return drawn == self
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
        if newGeometry.offset != geometry.offset || moved {
            if !actionUIWinUIElementSetOffset(frameView.pointer, newGeometry.offset.x, newGeometry.offset.y) {
                ActionUIModel.shared.logger.log("ModifierBox: \(WinUIError.last("offsetting an element"))", .error)
            }
        }
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
        do {
            try panel.remove(at: 0)
        } catch {
            logger.log("ModifierBox: \(error)", .error)
            return false
        }
        guard let box = WinUIObject(adopting: actionUIWinUIRoundedBoxCreate(group.object.pointer)) else {
            logger.log("ModifierBox: \(WinUIError.last("rounding an element's corners"))", .error)
            do {
                try panel.insert(group.object, at: 0)
            } catch {
                logger.log("ModifierBox: \(error)", .error)
            }
            return false
        }
        do {
            try panel.insert(box, at: 0)
        } catch {
            logger.log("ModifierBox: \(error)", .error)
            return false
        }
        panel.adoptThroughWrapper(group.object)
        rounded = box
        // The group's own background and offset go: the box paints and moves them now.
        Paint.apply(nil, ActionUIWinUIBrushBackground, to: group.object, what: "a background")
        _ = actionUIWinUIElementSetOffset(group.object.pointer, 0, 0)
        return true
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
                try panel.append(shape)
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
        _ = frameView.measure(offer)
        borderShape.map { _ = $0.measure(offer) }
        let width = frameSize(available.width, padded: padded.width, frame: geometry.frame.horizontal)
        let height = frameSize(available.height, padded: padded.height, frame: geometry.frame.vertical)
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
        borderShape?.arrange(frame)
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
