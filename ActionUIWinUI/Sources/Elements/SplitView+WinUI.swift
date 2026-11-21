// Sources/Elements/SplitView+WinUI.swift
/*
 HSplitView and VSplitView on WinUI: the panes side by side (or stacked) with a 1 point divider
 between each pair, which the user drags, as macOS's split views draw them and the Linux renderer's
 SplitLayout lays them out (measured on macOS 27):
 - The panes start as an HStack (a VStack) with no spacing lays them out (StackSolver), the dividers
   1 point each: flexible panes share the space, panes that are not flexible take their own size, and
   a split view of such panes hugs them. The first pane's frame's ideal size (idealWidth, idealHeight),
   when it has one, sets the first divider instead (ActionUI's own setter on Apple). Each pane is
   placed as a one-child ZStack places it: as long as its share where it expands, else its own size,
   centered; across, the split view's breadth where it expands, else its own, centered.
 - Dragging a divider moves the space between its two panes, within each one's minimum and the
   largest it takes (its own size, or its frame's maximum when it expands). A press counts within 4
   points of a divider, where the resize cursor shows.
 - Once the user has dragged, the panes keep their sizes, and a change of the split view's size goes
   to the last pane (the content beside a sidebar), then to the ones before it as each reaches its
   minimum or maximum. A change in the panes (one added or removed) lays them out from the start
   again.
 - A pane that takes no place (an EmptyView) is no pane and gets no divider.

 Not yet: a Group's children as panes of their own (Windows has no Group yet; a Group is one pane);
 a pane's frame minimum (an expanding pane can be dragged down to nothing); the resize cursor while a
 drag leaves the divider's hit area (WinUI may show the default one there); a drag follows any
 pointer, not only the one that pressed.
*/

import CWinUI

/// A divider: a transparent hit area 2 x grabDistance + 1 wide (where a press grabs it and the resize
/// cursor shows) around its 1 point line in the theme's divider color.
@MainActor final class SplitDivider {
    let hitArea: LayoutPanel
    let line: LayoutPanel

    init(horizontal: Bool) throws(WinUIError) {
        hitArea = try LayoutPanel()
        line = try LayoutPanel()
        try hitArea.append(line.object)
        Paint.apply(.color(ActionUIWinUIColor(red: 0, green: 0, blue: 0, alpha: 0)), ActionUIWinUIBrushBackground,
                    to: hitArea.object, what: "a split view's divider")
        Paint.apply(.theme("DividerStrokeColorDefaultBrush"), ActionUIWinUIBrushBackground, to: line.object,
                    what: "a split view's divider line")
        if !actionUIWinUIPanelSetResizeCursor(hitArea.object.pointer, true, horizontal) {
            ActionUIModel.shared.logger.log("SplitView: \(WinUIError.last("setting the resize cursor"))", .error)
        }
        hitArea.measure = { [unowned self] _ in
            // Measured all the same: WinUI arranges only children measured in this pass.
            _ = line.object.measure(ActionUIWinUISize(width: 0, height: 0))
            return ActionUIWinUISize(width: 0, height: 0)
        }
        hitArea.arrange = { [unowned self] size in
            // The line in the middle of the hit area, across all of it.
            let thickness = Double(SplitLayout.dividerThickness)
            let rect = horizontal
                ? ActionUIWinUIRect(x: (size.width - thickness) / 2, y: 0, width: thickness, height: size.height)
                : ActionUIWinUIRect(x: 0, y: (size.height - thickness) / 2, width: size.width, height: thickness)
            line.object.arrange(rect)
        }
        line.measure = { _ in ActionUIWinUISize(width: 0, height: 0) }
    }
}

/// A split view's panes, dividers and sizes.
@MainActor final class SplitLayout {
    /// A divider's thickness, and how far from it a press grabs it.
    static let dividerThickness = 1
    static let grabDistance = 4.0

    struct Pane {
        let view: WinUIObject
        var expansion: Expansion = []
        var cap: (horizontal: Int?, vertical: Int?) = (nil, nil)
    }

    let panel: LayoutPanel
    let horizontal: Bool
    private(set) var panes: [Pane] = []
    private(set) var dividers: [SplitDivider] = []
    /// The first pane's ideal size in the axis, which sets the first divider.
    var firstIdeal: Int?
    /// The panes' sizes the user set by dragging; nil until then.
    private var userSizes: [Int]?
    /// The panes' sizes when last arranged, where the dividers are.
    private var arrangedSizes: [Int] = []
    /// The divider being dragged, the panes' sizes and the pointer's place when the drag began.
    private var drag: (index: Int, start: [Int], origin: Double)?
    /// From the last measure: each pane's size asked for, and the sizes for the length measured.
    private var desired: [ActionUIWinUISize] = []
    private var measuredSizes: (length: Int, sizes: [Int])?
    /// Each pane's size across from its last measure (for its share when the length was known), which
    /// arrange gives a pane that does not expand across: a wrapping text's height for its width.
    private var measuredAcross: [Double] = []

    init(horizontal: Bool) throws(WinUIError) {
        self.horizontal = horizontal
        panel = try LayoutPanel()
        panel.measure = { [unowned self] available in measure(available) }
        panel.arrange = { [unowned self] finalSize in arrange(finalSize) }
    }

    /// Makes `newPanes` the panes, in order, with a divider between each pair (drawn above them).
    func setPanes(_ newPanes: [Pane]) {
        let current = panes.map { ObjectIdentifier($0.view) }
        let wanted = newPanes.map { ObjectIdentifier($0.view) }
        let reshaped = panes.map(\.expansion.rawValue) != newPanes.map(\.expansion.rawValue)
            || !panes.elementsEqual(newPanes) { $0.cap == $1.cap }
        panes = newPanes
        if current != wanted {
            userSizes = nil
            drag = nil
            do {
                while !panel.children.isEmpty {
                    try panel.remove(at: panel.children.count - 1)
                }
                for pane in newPanes {
                    try panel.append(pane.view)
                }
                while dividers.count < max(0, newPanes.count - 1) {
                    dividers.append(try makeDivider(index: dividers.count))
                }
                dividers.removeLast(max(0, dividers.count - max(0, newPanes.count - 1)))
                for divider in dividers {
                    try panel.append(divider.hitArea.object)
                }
            } catch {
                ActionUIModel.shared.logger.log("SplitView: \(error)", .error)
            }
        }
        if current != wanted || reshaped {
            panel.invalidateLayout()
        }
    }

    // MARK: Sizes (as the Linux renderer's SplitLayout)

    /// The panes' sizes before the user drags: as a stack with dividers for spacing lays them out,
    /// the first pane at `firstIdeal` (within its range, leaving the others their minimums where it
    /// can) when given.
    static func initialSizes(_ panes: [StackChild], available: Int, firstIdeal: Int?) -> [Int] {
        var children = panes
        if let ideal = firstIdeal, var first = children.first {
            let room = available - dividerThickness * (children.count - 1) - children.dropFirst().reduce(0) { $0 + $1.minimum }
            let size = max(first.minimum, min(first.maximum.map { min(ideal, $0) } ?? ideal, room))
            first.minimum = size
            first.maximum = size
            children[0] = first
        }
        return StackSolver.mainSizes(children, available: available, spacing: dividerThickness)
    }

    /// The user's sizes fitted to `available`: the difference goes to the last pane, then to the ones
    /// before it as each reaches its minimum or maximum.
    static func fitted(_ sizes: [Int], _ panes: [StackChild], available: Int) -> [Int] {
        var result = sizes
        var difference = available - StackSolver.length(of: sizes, spacing: dividerThickness)
        for index in result.indices.reversed() where difference != 0 {
            let pane = panes[index]
            let wanted = result[index] + difference
            let size = max(pane.minimum, pane.maximum.map { min(wanted, $0) } ?? wanted)
            difference -= size - result[index]
            result[index] = size
        }
        return result
    }

    /// The sizes after the divider after pane `index` moved `delta` from where it was at `start`: the
    /// two panes beside it trade space, each kept within its range.
    static func dragged(_ start: [Int], _ panes: [StackChild], index: Int, delta: Int) -> [Int] {
        guard index + 1 < start.count else { return start }
        let before = panes[index]
        let after = panes[index + 1]
        var lower = before.minimum - start[index]
        var upper = before.maximum.map { $0 - start[index] } ?? Int.max
        lower = max(lower, after.maximum.map { start[index + 1] - $0 } ?? Int.min)
        upper = min(upper, start[index + 1] - after.minimum)
        guard lower <= upper else { return start }
        let move = min(max(delta, lower), upper)
        var result = start
        result[index] += move
        result[index + 1] -= move
        return result
    }

    // MARK: Layout

    private func along(_ size: ActionUIWinUISize) -> Double { horizontal ? size.width : size.height }
    private func across(_ size: ActionUIWinUISize) -> Double { horizontal ? size.height : size.width }
    private func size(along: Double, across: Double) -> ActionUIWinUISize {
        horizontal ? ActionUIWinUISize(width: along, height: across) : ActionUIWinUISize(width: across, height: along)
    }

    /// The panes as StackSolver sees them along the axis, from what they asked for.
    private func stackChildren() -> [StackChild] {
        zip(panes, desired).map { pane, desired in
            let length = StackSolver.length(along(desired), rounding: .up)
            let expands = pane.expansion.contains(horizontal ? .horizontal : .vertical)
            return expands ? .expanding(minimum: 0, cap: horizontal ? pane.cap.horizontal : pane.cap.vertical)
                           : .fixed(minimum: length, natural: length)
        }
    }

    private func sizes(available: Int) -> [Int] {
        let children = stackChildren()
        if let user = userSizes, user.count == children.count {
            return Self.fitted(user, children, available: available)
        }
        return Self.initialSizes(children, available: available, firstIdeal: firstIdeal)
    }

    private func measure(_ available: ActionUIWinUISize) -> ActionUIWinUISize {
        // Each pane asks for its size with unbounded room along the axis (its own length, as a
        // stack's children), the split view's breadth across.
        let offer = size(along: .infinity, across: across(available))
        desired = panes.map { $0.view.measureRequested(offer) }
        measuredAcross = desired.map(across)
        measuredSizes = nil
        // Measured all the same: WinUI arranges only children measured in this pass.
        for divider in dividers {
            _ = divider.hitArea.object.measure(ActionUIWinUISize(width: 0, height: 0))
        }
        guard !panes.isEmpty else { return ActionUIWinUISize(width: 0, height: 0) }
        var length = Double(StackSolver.length(of: desired.map { StackSolver.length(along($0), rounding: .up) },
                                               spacing: Self.dividerThickness))
        var breadth = desired.map(across).max() ?? 0
        if along(available).isFinite {
            // Each pane measured again for the share it gets, so arrange places it at the size it was
            // measured for (a pane's breadth can depend on its length: wrapping text).
            let available = StackSolver.length(along(available))
            let shares = sizes(available: available)
            measuredSizes = (available, shares)
            breadth = 0
            for (index, pane) in panes.enumerated() {
                let measured = pane.view.measureRequested(size(along: Double(shares[index]), across: across(offer)))
                measuredAcross[index] = across(measured)
                breadth = max(breadth, across(measured))
            }
            // The panes' shares, as a stack asks for its children's (all of `available` when a pane
            // expands without a cap): arranged in that, it shares out the same again.
            length = Double(StackSolver.length(of: shares, spacing: Self.dividerThickness))
        }
        return size(along: length, across: breadth)
    }

    private func arrange(_ finalSize: ActionUIWinUISize) {
        let length = StackSolver.length(along(finalSize))
        let breadth = StackSolver.length(across(finalSize))
        guard !panes.isEmpty else {
            arrangedSizes = []
            return
        }
        let shares = measuredSizes.flatMap { $0.length == length ? $0.sizes : nil } ?? sizes(available: length)
        arrangedSizes = shares
        let children = stackChildren()
        var position = 0
        for (index, pane) in panes.enumerated() {
            let share = shares[index]
            // As a one-child ZStack places its child: all of the share where it expands (up to its
            // cap), else its own size; centered.
            let alongLength = children[index].maximum.map { min(share, $0) } ?? share
            let expandsAcross = pane.expansion.contains(horizontal ? .vertical : .horizontal)
            let asked = StackSolver.length(measuredAcross[index], rounding: .up)
            let capAcross = horizontal ? pane.cap.vertical : pane.cap.horizontal
            let acrossLength = expandsAcross ? max(min(breadth, capAcross ?? breadth), asked) : asked
            let alongStart = position + StackSolver.centeredStart(length: alongLength, available: share)
            let acrossStart = StackSolver.centeredStart(length: acrossLength, available: breadth)
            pane.view.arrange(rect(along: alongStart, across: acrossStart, length: alongLength, breadth: acrossLength))
            position += share
            if index < dividers.count {
                // The hit area centered on the line, which sits in the gap after the pane.
                let grab = Int(Self.grabDistance)
                dividers[index].hitArea.object.arrange(rect(along: position - grab, across: 0,
                                                            length: 2 * grab + Self.dividerThickness, breadth: breadth))
                position += Self.dividerThickness
            }
        }
    }

    private func rect(along: Int, across: Int, length: Int, breadth: Int) -> ActionUIWinUIRect {
        horizontal
            ? ActionUIWinUIRect(x: Double(along), y: Double(across), width: Double(length), height: Double(breadth))
            : ActionUIWinUIRect(x: Double(across), y: Double(along), width: Double(breadth), height: Double(length))
    }

    // MARK: Dragging

    private func makeDivider(index: Int) throws(WinUIError) -> SplitDivider {
        let divider = try SplitDivider(horizontal: horizontal)
        SplitPointer.connect(divider.hitArea.object, relativeTo: panel.object) { [weak self] kind, x, y in
            guard let self else { return false }
            return self.pointer(kind, at: horizontal ? x : y, divider: index)
        }
        return divider
    }

    /// A pointer event on the divider after pane `index` at `point` along the axis (in the split view).
    private func pointer(_ kind: ActionUIWinUIPointerEventKind, at point: Double, divider index: Int) -> Bool {
        switch kind {
        case ActionUIWinUIPointerPressed:
            guard index + 1 < arrangedSizes.count else { return false }
            drag = (index, arrangedSizes, point)
            return true
        case ActionUIWinUIPointerMoved:
            guard let drag else { return false }
            let delta = Int((point - drag.origin).rounded())
            userSizes = Self.dragged(drag.start, stackChildren(), index: drag.index, delta: delta)
            panel.invalidateLayout()
            return true
        default:
            let dragging = drag != nil
            drag = nil
            return dragging
        }
    }
}

/// Swift closures as a divider's pointer handler (actionUIWinUIElementOnPointerDrag; a split view's, a Table header's edge), held
/// by the shim as WinUIEvents' handlers are.
@MainActor private final class PointerBox {
    let action: @MainActor (ActionUIWinUIPointerEventKind, Double, Double) -> Bool

    init(_ action: @escaping @MainActor (ActionUIWinUIPointerEventKind, Double, Double) -> Bool) {
        self.action = action
    }
}

private func pointerBox(_ context: UnsafeMutableRawPointer?) -> PointerBox? {
    context.map { Unmanaged<PointerBox>.fromOpaque($0).takeUnretainedValue() }
}

private let firePointer: ActionUIWinUIPointerCallback = { context, kind, x, y in
    let box = pointerBox(context)
    return MainActor.assumeIsolated {
        box?.action(kind, x, y) ?? false
    }
}

private let releasePointer: ActionUIWinUICallback = { context in
    guard let context else { return }
    Unmanaged<PointerBox>.fromOpaque(context).release()
}

@MainActor enum SplitPointer {
    /// Reports `element`'s drags to `action`, in `relativeTo`'s coordinates; `owner` names the element
    /// type in the log.
    static func connect(_ element: WinUIObject, relativeTo: WinUIObject, owner: String = "SplitView",
                        _ action: @escaping @MainActor (ActionUIWinUIPointerEventKind, Double, Double) -> Bool) {
        let context = Unmanaged.passRetained(PointerBox(action)).toOpaque()
        // On failure the shim has already called releasePointer.
        if !actionUIWinUIElementOnPointerDrag(element.pointer, relativeTo.pointer, firePointer, context, releasePointer) {
            ActionUIModel.shared.logger.log("\(owner): \(WinUIError.last("watching a divider's drags"))", .error)
        }
    }
}

@MainActor enum SplitPanes {
    static func makeView(_ node: RenderNode, horizontal: Bool) throws(WinUIError) -> WinUIObject {
        let layout = try SplitLayout(horizontal: horizontal)
        node.state = layout
        return layout.panel.object
    }

    /// Syncs a split view's children into its panes; `ideal` reads the size the first child's frame
    /// asks for in the split view's axis.
    static func update(_ node: RenderNode, ideal: (BaseModifiers.Frame?) -> Double?) {
        guard let layout = node.state as? SplitLayout else { return }
        let children = node.syncChildren(node.effectiveElement.subviews?["children"] as? [any ActionUIElementBase] ?? [])
        layout.setPanes(children.compactMap { child in
            guard !child.takesNoPlace, let view = child.outerView else { return nil }
            return SplitLayout.Pane(view: view, expansion: child.expansion, cap: child.caps)
        })
        let ideal = children.first.flatMap { ideal(BaseModifiers($0.properties).frame) }.map { StackSolver.length($0) }
        if ideal != layout.firstIdeal {
            layout.firstIdeal = ideal
            layout.panel.invalidateLayout()
        }
    }
}

extension HSplitView: ActionUIWinUIRenderer {
    static func expansion(_ node: RenderNode) -> Expansion { StackViews.childrenExpansion(node) }

    static func compression(_ node: RenderNode) -> Expansion { StackViews.childrenCompression(node) }

    static func makeView(_ node: RenderNode) throws(WinUIError) -> WinUIObject {
        try SplitPanes.makeView(node, horizontal: true)
    }

    static func update(_ view: WinUIObject, _ node: RenderNode) {
        SplitPanes.update(node) { $0?.idealWidth }
    }
}

extension VSplitView: ActionUIWinUIRenderer {
    static func expansion(_ node: RenderNode) -> Expansion { StackViews.childrenExpansion(node) }

    static func compression(_ node: RenderNode) -> Expansion { StackViews.childrenCompression(node) }

    static func makeView(_ node: RenderNode) throws(WinUIError) -> WinUIObject {
        try SplitPanes.makeView(node, horizontal: false)
    }

    static func update(_ view: WinUIObject, _ node: RenderNode) {
        SplitPanes.update(node) { $0?.idealHeight }
    }
}
