// Sources/Layout/ModifierBox.swift
/*
 The box around every element's WinUI object, which applies the element's padding, frame and
 background with SwiftUI's rules (the shared FrameSolver), as the GTK renderer's ModifierBox does.
 Two panels, so the background follows the frame, not the room the box is given:

   ModifierBox (outer)   the frame: its size from the proposal and the content; a box given more
                         than its frame (the window's root) centers the frame in it
     content group       exactly the frame's size: the background, and the padding and the
                         frame's alignment of the element in it
       element object

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
 - opacity fades the whole box, background included, as on Linux (on Apple the border and shadow,
   applied after it, stay unfaded).
 - hidden keeps the element's space, as SwiftUI's .hidden() does: the box draws nothing and lets the
   pointer through. Its controls lose keyboard focus and accessibility tools skip it (RenderNode).

 Not yet: overlay, border, cornerRadius, offset, background views, and the other base modifiers the
 GTK ModifierBox applies.

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
    /// The whole box's opacity, 0 to 1.
    var opacity = 1.0
    /// Hidden: the box keeps its space but draws nothing and lets the pointer through.
    var hidden = false

    static func == (left: BoxGeometry, right: BoxGeometry) -> Bool {
        left.padding.horizontal == right.padding.horizontal && left.padding.vertical == right.padding.vertical
            && left.frame.horizontal == right.frame.horizontal && left.frame.vertical == right.frame.vertical
            && left.alignment.horizontal == right.alignment.horizontal && left.alignment.vertical == right.alignment.vertical
            && left.background == right.background && left.opacity == right.opacity && left.hidden == right.hidden
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
    }

    /// Whether the layout depends on what changed between `self` and `other` (opacity and hidden do not).
    func sameLayout(as other: BoxGeometry) -> Bool {
        var drawn = other
        drawn.opacity = opacity
        drawn.hidden = hidden
        drawn.background = background
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

    /// Applies new padding, frame, background, opacity and hidden state; asks for a layout when the
    /// padding or the frame changed.
    func update(_ newGeometry: BoxGeometry) {
        guard newGeometry != geometry else { return }
        if newGeometry.background != geometry.background {
            Paint.apply(newGeometry.background, ActionUIWinUIBrushBackground, to: group.object, what: "a background")
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
        geometry = newGeometry
        if relayout {
            panel.invalidateLayout()
            group.invalidateLayout()
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
        _ = group.object.measure(offer)
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
        group.object.arrange(ActionUIWinUIRect(x: Double(StackSolver.centeredStart(length: width, available: boxWidth)),
                                               y: Double(StackSolver.centeredStart(length: height, available: boxHeight)),
                                               width: Double(width), height: Double(height)))
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
