// Sources/Layout/StackLayout.swift
/*
 VStack and HStack on WinUI: a LayoutPanel whose measure and arrange passes share the stack's
 length among its children with StackSolver, SwiftUI's stack rules, which the GTK renderer uses too
 (ActionUIRendererShared/Sources/Layout/StackSolver.swift).

 - Each child is measured with the stack's cross size and an unbounded length along the axis; what
   it asks for is its size along the axis (StackChild.fixed). A Spacer expands, at least its
   minLength long (StackChild.spacer), and so does a child whose renderer expands along the axis
   (a TextField in an HStack: StackChild.expanding, at least what it asked for). A child that
   expands across takes the stack's whole cross size (a TextField in a VStack), so the stack takes
   all the width it is offered. A frame decides per axis instead (RenderNode.expansion): one with a
   maximum expands, up to that maximum when it is finite (RenderNode.caps); a fixed one does not.
   A ScrollView along its scroll axis can be made smaller than its content, to its padding and
   frame minimum, as in SwiftUI (two of them share the space), and is measured for the length it
   gets (layoutChildren).
 - Default spacing (none given) is 8, and 0 next to a Spacer, as SwiftUI's; a given spacing is used
   everywhere.
 - The stack asks for its children's lengths and gaps along the axis (all it is offered when it
   holds a child that expands along it) and its widest child across.
 - Arranged in more room than it asked for (the root of a window), the stack is centered in it, as
   SwiftUI centers a window's content, and in less room around the middle, its children keeping
   their sizes (as on Linux); its children are aligned across inside the stack's own cross size
   (alignment: leading, center or trailing for a VStack; top, center or bottom for an HStack).

 Not yet: compressing children that do not fit (a Text that would wrap in an HStack), baselines,
 expansion through a nested stack (an HStack holding an HStack with a TextField keeps the inner
 stack at its own width; a stack's expansion is its renderer's, not yet its children's).
*/

import CWinUI

@MainActor
final class StackLayout {
    static let defaultSpacing = 8.0

    enum Axis {
        case vertical, horizontal
    }

    /// What the stack knows of each child, beside its WinUI object.
    struct Item {
        let view: WinUIObject
        /// A Spacer's minLength; nil for any other child.
        let spacerMinimum: Double?
        /// How the child grows (RenderNode.expansion).
        var expansion: Expansion = []
        /// How far it grows when it expands (RenderNode.caps): a frame's finite maximum.
        var cap: (horizontal: Int?, vertical: Int?) = (nil, nil)
        /// The axes along which, when it expands, it can be made smaller than it asks for: a
        /// ScrollView along its scroll axes, whose smallest size is its box measured with nothing
        /// offered (its padding and frame minimum), as SwiftUI's ScrollView shrinks to nothing.
        var compressible: Expansion = []
    }

    let axis: Axis
    let panel: LayoutPanel
    var spacing: Double?
    var alignment = StackSolver.Alignment.center
    private(set) var items: [Item] = []

    init(axis: Axis) throws(WinUIError) {
        self.axis = axis
        panel = try LayoutPanel()
        panel.measure = { [unowned self] available in measure(available) }
        panel.arrange = { [unowned self] finalSize in arrange(finalSize) }
    }

    /// Makes the panel hold `items`, in order; asks for a new layout when the children or their
    /// order changed.
    func setItems(_ newItems: [Item]) {
        let current = items.map { ObjectIdentifier($0.view) }
        let wanted = newItems.map { ObjectIdentifier($0.view) }
        let spacersChanged = items.map(\.spacerMinimum) != newItems.map(\.spacerMinimum)
            || items.map(\.expansion.rawValue) != newItems.map(\.expansion.rawValue)
            || items.map(\.compressible.rawValue) != newItems.map(\.compressible.rawValue)
            || !items.elementsEqual(newItems) { $0.cap == $1.cap }
        items = newItems
        if current != wanted {
            do {
                // Simple and correct while stacks are small: start over when anything moved.
                while !panel.children.isEmpty {
                    try panel.remove(at: panel.children.count - 1)
                }
                for item in newItems {
                    try panel.append(item.view)
                }
            } catch {
                ActionUIModel.shared.logger.log("StackLayout: \(error)", .error)
            }
        }
        if current != wanted || spacersChanged {
            panel.invalidateLayout()
        }
    }

    /// Asks for a new layout, after the spacing or the alignment changed.
    func invalidate() {
        panel.invalidateLayout()
    }

    // MARK: Axes

    private func main(_ size: ActionUIWinUISize) -> Double {
        axis == .vertical ? size.height : size.width
    }

    private func cross(_ size: ActionUIWinUISize) -> Double {
        axis == .vertical ? size.width : size.height
    }

    private func size(main: Double, cross: Double) -> ActionUIWinUISize {
        axis == .vertical ? ActionUIWinUISize(width: cross, height: main) : ActionUIWinUISize(width: main, height: cross)
    }

    /// Whether `item` grows along the stack's axis, and across it.
    private func expands(_ item: Item) -> (main: Bool, cross: Bool) {
        let horizontal = item.expansion.contains(.horizontal)
        let vertical = item.expansion.contains(.vertical)
        return axis == .vertical ? (vertical, horizontal) : (horizontal, vertical)
    }

    /// Whether `item` can be made smaller than it asks for along the stack's axis.
    private func compressibleAlong(_ item: Item) -> Bool {
        item.compressible.contains(axis == .vertical ? .vertical : .horizontal)
    }

    /// How far `item` grows along the stack's axis, and across it, when it expands.
    private func caps(_ item: Item) -> (main: Int?, cross: Int?) {
        axis == .vertical ? (item.cap.vertical, item.cap.horizontal) : (item.cap.horizontal, item.cap.vertical)
    }

    private func rect(main: Double, cross: Double, mainLength: Double, crossLength: Double) -> ActionUIWinUIRect {
        axis == .vertical
            ? ActionUIWinUIRect(x: cross, y: main, width: crossLength, height: mainLength)
            : ActionUIWinUIRect(x: main, y: cross, width: mainLength, height: crossLength)
    }

    // MARK: Layout

    /// The smallest length of each compressible child (by its view) from the last measure pass,
    /// for arrange, which must not measure it with another size (layoutChildren): its ideal length
    /// after a measure unbounded along the axis.
    private var compressedMinimums: [ObjectIdentifier: Int] = [:]
    /// The size across the children were measured for in the last measure pass. Arrange measures
    /// them for it again, not for its own size across: a child whose desired size follows the
    /// offer (a Color, a shape, a Divider) would ask for another size, which invalidates the
    /// stack's measure, and the stack, measured again for the first size, would never settle (an
    /// HStack in a VStack is measured unbounded in height and arranged as tall as its tallest
    /// child). Across, arrange still gives a child that expands the stack's whole size (crossSize).
    private var measuredCrossOffer = Double.infinity

    /// The size across of a child asking for `desired`: a child that expands across takes all the
    /// stack is offered across, when that is known, up to its cap.
    private func crossSize(_ desired: ActionUIWinUISize, expandsAcross: Bool, cap: Int?, crossOffer: Double) -> Int {
        let crossLength = StackSolver.length(cross(desired), rounding: .up)
        let fill = min(StackSolver.length(crossOffer), cap ?? Int.max)
        return expandsAcross && crossOffer.isFinite ? max(crossLength, fill) : crossLength
    }

    /// Each child measured for `crossOffer` across, and its length along the axis in `mainOffer`
    /// (infinite when unbounded: each child's ideal length), with the gaps between them.
    ///
    /// A child is measured unbounded along the axis; what it asks for is its length (its minimum
    /// when it expands). A compressible child (a ScrollView along its scroll axis) is measured
    /// once, for the length the stack gives it, as WinUI's own panels measure a star row: WinUI
    /// arranges an element at least as large as it last measured (clipping the rest), so one
    /// measured unbounded would be as long as its content and never scroll, and a measure during
    /// arrange that changes its desired size invalidates the stack's measure, which would then never
    /// settle. Its smallest length is what it asks for with nothing offered (its padding and frame
    /// minimum: WinUI gives no desired size above the size offered), measured in the measure pass
    /// only. After a measure unbounded along the axis it is the child's ideal length instead: the
    /// stack asked for every child's ideal and is arranged in at least that (WinUI does not arrange
    /// an element smaller than it measured), so arrange keeps each compressible child at its ideal
    /// or more, a size its last measure already gives.
    private func layoutChildren(mainOffer: Double, crossOffer: Double, isMeasurePass: Bool)
        -> (sizes: [Int], crossSizes: [Int], gaps: [Int]) {
        var children: [StackChild] = []
        var crossSizes: [Int] = []
        var compressed: [Int] = []
        if isMeasurePass {
            compressedMinimums = [:]
            measuredCrossOffer = crossOffer
        }
        let measureCross = measuredCrossOffer
        for (index, item) in items.enumerated() {
            if let minimum = item.spacerMinimum {
                // Measured all the same: WinUI arranges only children measured in this pass.
                _ = item.view.measure(ActionUIWinUISize(width: 0, height: 0))
                children.append(.spacer(minimum: StackSolver.length(minimum)))
                crossSizes.append(0)
                continue
            }
            let (expandsAlong, expandsAcross) = expands(item)
            let (capAlong, capAcross) = caps(item)
            if expandsAlong && compressibleAlong(item) {
                let key = ObjectIdentifier(item.view)
                if isMeasurePass && mainOffer.isFinite {
                    let smallest = item.view.measure(size(main: 0, cross: measureCross))
                    compressedMinimums[key] = StackSolver.length(main(smallest), rounding: .up)
                }
                children.append(.expanding(minimum: compressedMinimums[key] ?? 0, cap: capAlong))
                crossSizes.append(0)
                compressed.append(index)
                continue
            }
            let desired = item.view.measure(size(main: .infinity, cross: measureCross))
            let length = StackSolver.length(main(desired), rounding: .up)
            children.append(expandsAlong ? .expanding(minimum: length, cap: capAlong) : .fixed(minimum: length, natural: length))
            crossSizes.append(crossSize(desired, expandsAcross: expandsAcross, cap: capAcross, crossOffer: crossOffer))
        }
        let gaps = gaps(children)
        var sizes: [Int]
        let hasExpanding = items.contains { $0.spacerMinimum != nil || expands($0).main }
        if mainOffer.isFinite && (hasExpanding || !isMeasurePass) {
            sizes = StackSolver.mainSizes(children, available: StackSolver.length(mainOffer), gaps: gaps)
        } else {
            sizes = children.map(\.minimum)
        }
        for index in compressed {
            let item = items[index]
            // Unbounded: its ideal length, a ScrollView its content's (SwiftUI's ideal size).
            let desired = item.view.measure(size(main: mainOffer.isFinite ? Double(sizes[index]) : .infinity, cross: measureCross))
            if !mainOffer.isFinite {
                sizes[index] = StackSolver.length(main(desired), rounding: .up)
                if isMeasurePass {
                    compressedMinimums[ObjectIdentifier(item.view)] = sizes[index]
                }
            }
            crossSizes[index] = crossSize(desired, expandsAcross: expands(item).cross, cap: caps(item).cross, crossOffer: crossOffer)
        }
        return (sizes, crossSizes, gaps)
    }

    private func gaps(_ children: [StackChild]) -> [Int] {
        StackSolver.gaps(children, spacing: StackSolver.length(spacing ?? Self.defaultSpacing), isDefaultSpacing: spacing == nil)
    }

    private func measure(_ available: ActionUIWinUISize) -> ActionUIWinUISize {
        let (sizes, crossSizes, gaps) = layoutChildren(mainOffer: main(available), crossOffer: cross(available), isMeasurePass: true)
        let length = StackSolver.length(of: sizes, gaps: gaps)
        return size(main: Double(length), cross: Double(crossSizes.max() ?? 0))
    }

    private func arrange(_ finalSize: ActionUIWinUISize) {
        let available = StackSolver.length(main(finalSize))
        let (sizes, crossSizes, gaps) = layoutChildren(mainOffer: Double(available), crossOffer: cross(finalSize), isMeasurePass: false)
        let length = StackSolver.length(of: sizes, gaps: gaps)
        let finalCross = StackSolver.length(cross(finalSize))
        let block = crossSizes.max() ?? 0
        // Centered in the room it was given, as SwiftUI centers a window's content: in more room
        // than it asked for, and around the middle in less (each child keeps its size), as the GTK
        // renderer places it too.
        var position = StackSolver.centeredStart(length: length, available: available)
        let blockStart = StackSolver.centeredStart(length: block, available: finalCross)
        for (index, item) in items.enumerated() {
            let crossSize = crossSizes[index]
            let offset = blockStart + StackSolver.alignedOffset(size: crossSize, block: block, alignment: alignment)
            item.view.arrange(rect(main: Double(position), cross: Double(offset), mainLength: Double(sizes[index]),
                                   crossLength: Double(crossSize)))
            position += sizes[index] + (index < gaps.count ? gaps[index] : 0)
        }
    }
}

/// Makes a stack node's children match its element's (RenderNode.syncChildren) and puts their
/// boxes (RenderNode.outerView) in the stack, with how each expands (RenderNode.expansion, caps).
@MainActor func syncStackContent(_ node: RenderNode, _ stack: StackLayout) {
    let children = node.syncChildren(node.subviews("children"))
    stack.setItems(children.compactMap { child in
        guard let view = child.outerView else { return nil }
        let spacerMinimum = child.element.type == "Spacer" ? (Spacer.Props(child.properties).minLength ?? Spacer.defaultMinLength) : nil
        let compressible = child.element.type == "ScrollView" ? ScrollView.scrollAxes(ScrollView.Props(child.properties).axis) : []
        return StackLayout.Item(view: view, spacerMinimum: spacerMinimum, expansion: child.expansion, cap: child.caps,
                                compressible: compressible)
    })
}
