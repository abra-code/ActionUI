// Sources/Layout/StackLayout.swift
/*
 VStack and HStack on WinUI: a LayoutPanel whose measure and arrange passes share the stack's
 length among its children with StackSolver, SwiftUI's stack rules, which the GTK renderer uses too
 (ActionUIRendererShared/Sources/Layout/StackSolver.swift).

 - Each child is measured with the stack's cross size and an unbounded length along the axis; what
   it asks for is its size along the axis (StackChild.fixed). A child that can be made smaller
   along the axis (RenderNode.compression: a Text in a row, which wraps, or a stack holding one)
   is also measured with nothing offered for its smallest length, then once more for the length
   the stack gives it, so a wrapping Text gets taller in a narrow row; arrange gives it that
   length again (layoutChildren). A Spacer expands, at least its
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
   (alignment: leading, center or trailing for a VStack; top, center or bottom for an HStack), or
   inside all it is given across when it fills across (fillsAcross: a LazyVStack, a LazyHStack).

 A stack expands as its children do (StackViews.childrenExpansion): a row holding a Color or a
 TextField takes the room its own stack gives it, as in SwiftUI.

 A compressed child keeps its padding and its frame's minimum: its smallest size is what its box
 asks for with nothing offered, read before WinUI caps it at the size offered
 (WinUIObject.measureRequested). Every size the stack reads from a child is that uncapped answer,
 along the axis and across, so a nested stack has its children's smallest size in both axes (a
 row in a row, a column in a row). A child larger across than the stack is offered makes the stack
 as large, centered in the room it is given, overflowing it as a SwiftUI stack does (WinUI is told
 no more than the room: LayoutPanel).

 A floor that changes while running (a bound minWidth or padding, a nested stack gaining a child)
 reaches the stack although WinUI's capped size of the child stays the same: the child's panel asks
 its parent for a new layout (LayoutPanel).

 Not yet: baselines. A compressed Text leaves what it does not use of its share to the others in
 one more sharing; SwiftUI offers each child in turn what the ones before it left, so the shares can
 differ by a few points when several Texts wrap in one row.
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
        /// The axes along which it can be made smaller than it asks for (RenderNode.compression):
        /// a ScrollView along its scroll axes, as SwiftUI's ScrollView shrinks to nothing; a Text
        /// across a row. Its smallest size is what its box asks for with nothing offered (its
        /// padding and frame minimum, a row nested in a row: its children at their smallest), read past
        /// WinUI's cap (WinUIObject.measureRequested); a fixed frame turns compression off
        /// (RenderNode.compression).
        var compressible: Expansion = []
    }

    let axis: Axis
    let panel: LayoutPanel
    var spacing: Double?
    var alignment = StackSolver.Alignment.center
    /// Whether the children are aligned across the stack's whole size when it is given more than its
    /// widest (tallest) child: a LazyVStack and a LazyHStack, which take all the room across.
    var fillsAcross = false
    /// The template instances of the container this lays out, in row order (its template form).
    let templateRows = TemplateRows()
    private(set) var items: [Item] = []
    /// Room before some children across the axis, by their view: a Form's rows without a title start
    /// in its content column (FormColumn). A child is offered and given the stack's size across less
    /// its inset, after it.
    private(set) var leadingInsets: [ObjectIdentifier: Int] = [:]

    /// Sets the room before each child across the axis (by view; none for the others); asks for a
    /// new layout when it changed.
    /// `invalidate` false: the stack's own measure is running and uses them.
    func setLeadingInsets(_ insets: [ObjectIdentifier: Int], invalidate: Bool = true) {
        let kept = insets.filter { $0.value != 0 }
        guard kept != leadingInsets else { return }
        leadingInsets = kept
        if invalidate {
            panel.invalidateLayout()
        }
    }

    private func inset(_ item: Item) -> Int {
        leadingInsets[ObjectIdentifier(item.view)] ?? 0
    }

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
    /// The length each compressible child that does not expand (a Text in a row) was given in the
    /// last measure pass, and the length along the axis it was last measured for there: arrange
    /// gives it that length and measures it for the same size again, a no-op for WinUI. Measured
    /// for another length its desired size would change (a wrapped Text's height), which
    /// invalidates the stack's measure, and the stack, measured again, would never settle.
    private var measuredLengths: [ObjectIdentifier: (length: Int, offer: Double)] = [:]
    /// The size across the children were measured for in the last measure pass. Arrange measures
    /// them for it again, not for its own size across: a child whose desired size follows the
    /// offer (a Color, a shape, a Divider) would ask for another size, which invalidates the
    /// stack's measure, and the stack, measured again for the first size, would never settle (an
    /// HStack in a VStack is measured unbounded in height and arranged as tall as its tallest
    /// child). Across, arrange still gives a child that expands the stack's whole size (crossSize).
    private var measuredCrossOffer = Double.infinity
    /// The children's lengths from the last measure pass when it was unbounded along the axis (each
    /// child's ideal length), else nil. Arranged in exactly what it then asked for, the stack gives
    /// each child that length again: shared out anew, a child with a frame's finite maximum would
    /// be offered a share above its ideal (the solver offers the least flexible first), measured
    /// for it, ask for another size, and the stack's layout would never finish.
    private var unboundedLengths: [Int]?

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
    /// minimum, read past WinUI's cap: WinUIObject.measureRequested), measured in the measure pass
    /// only. After a measure unbounded along the axis it is the child's ideal length instead: the
    /// stack asked for every child's ideal and is arranged in at least that (WinUI does not arrange
    /// an element smaller than it measured), so arrange keeps each compressible child at its ideal
    /// or more and measures it unbounded again, as its last measure was.
    private func layoutChildren(mainOffer: Double, crossOffer: Double, isMeasurePass: Bool)
        -> (sizes: [Int], crossSizes: [Int], gaps: [Int]) {
        var children: [StackChild] = []
        var crossSizes: [Int] = []
        var compressed: [Int] = []
        if isMeasurePass {
            compressedMinimums = [:]
            measuredLengths = [:]
            measuredCrossOffer = crossOffer
        }
        for (index, item) in items.enumerated() {
            // Offered across what the stack has less the child's inset.
            let measureCross = max(measuredCrossOffer - Double(inset(item)), 0)
            let itemCrossOffer = max(crossOffer - Double(inset(item)), 0)
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
                    let smallest = item.view.measureRequested(size(main: 0, cross: measureCross))
                    compressedMinimums[key] = StackSolver.length(main(smallest), rounding: .up)
                }
                children.append(.expanding(minimum: compressedMinimums[key] ?? 0, cap: capAlong))
                crossSizes.append(0)
                compressed.append(index)
                continue
            }
            if compressibleAlong(item) {
                // A Text in a row: its one line is its natural length; it can wrap down to what it
                // asks for with nothing offered. Arrange keeps the length the measure pass gave it.
                let key = ObjectIdentifier(item.view)
                if isMeasurePass {
                    let natural = item.view.measure(size(main: .infinity, cross: measureCross))
                    let naturalLength = StackSolver.length(main(natural), rounding: .up)
                    var smallestLength = naturalLength
                    if mainOffer.isFinite {
                        let smallest = item.view.measureRequested(size(main: 0, cross: measureCross))
                        smallestLength = min(StackSolver.length(main(smallest), rounding: .up), naturalLength)
                    }
                    children.append(.fixed(minimum: smallestLength, natural: naturalLength))
                } else {
                    let length = measuredLengths[key]?.length ?? 0
                    children.append(.fixed(minimum: length, natural: length))
                }
                crossSizes.append(0)
                compressed.append(index)
                continue
            }
            let desired = item.view.measureRequested(size(main: .infinity, cross: measureCross))
            let length = StackSolver.length(main(desired), rounding: .up)
            children.append(expandsAlong ? .expanding(minimum: length, cap: capAlong) : .fixed(minimum: length, natural: length))
            crossSizes.append(crossSize(desired, expandsAcross: expandsAcross, cap: capAcross, crossOffer: itemCrossOffer))
        }
        let gaps = gaps(children)
        var sizes: [Int]
        let hasExpanding = items.contains { $0.spacerMinimum != nil || expands($0).main }
        if mainOffer.isFinite && (hasExpanding || !compressed.isEmpty || !isMeasurePass) {
            sizes = StackSolver.mainSizes(children, available: StackSolver.length(mainOffer), gaps: gaps)
        } else {
            sizes = children.map(\.minimum)
        }
        if !isMeasurePass, let ideal = unboundedLengths, ideal.count == sizes.count,
           StackSolver.length(of: ideal, gaps: gaps) == StackSolver.length(mainOffer) {
            sizes = ideal
        }
        // A compressible child that does not expand (a Text in a row) is measured for the length it
        // is offered (unbounded: its one line), which arrange repeats, and takes what it asks for of
        // it, as SwiftUI's Text takes its widest wrapped line: the room it leaves goes to the children
        // that can use it, shared out once more.
        var leftRoom = false
        for index in compressed where !expands(items[index]).main {
            let item = items[index]
            let measureCross = max(measuredCrossOffer - Double(inset(item)), 0)
            let itemCrossOffer = max(crossOffer - Double(inset(item)), 0)
            let key = ObjectIdentifier(item.view)
            let offer = isMeasurePass ? (mainOffer.isFinite ? Double(sizes[index]) : .infinity)
                                      : (measuredLengths[key]?.offer ?? .infinity)
            let desired = item.view.measureRequested(size(main: offer, cross: measureCross))
            if isMeasurePass {
                let taken = StackSolver.length(main(desired), rounding: .up)
                if !mainOffer.isFinite || taken < sizes[index] {
                    leftRoom = leftRoom || mainOffer.isFinite
                    sizes[index] = taken
                }
                measuredLengths[key] = (sizes[index], offer)
                children[index] = .fixed(minimum: sizes[index], natural: sizes[index])
            }
            crossSizes[index] = crossSize(desired, expandsAcross: expands(item).cross, cap: caps(item).cross, crossOffer: itemCrossOffer)
        }
        if leftRoom {
            sizes = StackSolver.mainSizes(children, available: StackSolver.length(mainOffer), gaps: gaps)
        }
        for index in compressed where expands(items[index]).main {
            let item = items[index]
            let measureCross = max(measuredCrossOffer - Double(inset(item)), 0)
            let itemCrossOffer = max(crossOffer - Double(inset(item)), 0)
            // Unbounded: its ideal length, a ScrollView its content's (SwiftUI's ideal size). Arrange
            // after a measure unbounded along the axis measures it unbounded again (a no-op for
            // WinUI): the stack arranged larger than it asked for (filling a wider column) gives it
            // more than its ideal, and measured for that, a child with a frame's finite maximum
            // would ask for another size and the layout would never finish.
            let unbounded = !mainOffer.isFinite || (!isMeasurePass && unboundedLengths != nil)
            let desired = item.view.measureRequested(size(main: unbounded ? .infinity : Double(sizes[index]), cross: measureCross))
            if !mainOffer.isFinite {
                sizes[index] = StackSolver.length(main(desired), rounding: .up)
                if isMeasurePass {
                    compressedMinimums[ObjectIdentifier(item.view)] = sizes[index]
                }
            }
            crossSizes[index] = crossSize(desired, expandsAcross: expands(item).cross, cap: caps(item).cross, crossOffer: itemCrossOffer)
        }
        if isMeasurePass {
            unboundedLengths = mainOffer.isFinite ? nil : sizes
        }
        // Each child's size across with its inset before it.
        for (index, item) in items.enumerated() where item.spacerMinimum == nil {
            crossSizes[index] += inset(item)
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
        let block = max(crossSizes.max() ?? 0, fillsAcross ? finalCross : 0)
        // Centered in the room it was given, as SwiftUI centers a window's content: in more room
        // than it asked for, and around the middle in less (each child keeps its size), as the GTK
        // renderer places it too.
        var position = StackSolver.centeredStart(length: length, available: available)
        let blockStart = StackSolver.centeredStart(length: block, available: finalCross)
        for (index, item) in items.enumerated() {
            let crossSize = crossSizes[index]
            // The child after its inset (crossSize holds both).
            let before = item.spacerMinimum == nil ? inset(item) : 0
            let offset = blockStart + StackSolver.alignedOffset(size: crossSize, block: block, alignment: alignment) + before
            item.view.arrange(rect(main: Double(position), cross: Double(offset), mainLength: Double(sizes[index]),
                                   crossLength: Double(crossSize - before)))
            position += sizes[index] + (index < gaps.count ? gaps[index] : 0)
        }
    }
}

/// Makes `stack` show what `node` shows: its children (RenderNode.syncChildren), or one template
/// instance per content row (TemplateRows); puts their boxes (RenderNode.outerView) in the stack, with
/// how each expands (RenderNode.expansion, caps).
@MainActor func syncStackContent(_ node: RenderNode, _ stack: StackLayout) {
    stack.setItems(stackItems(stack.templateRows.contentNodes(of: node)))
}

/// A stack's items for its child nodes, in order (a child with no object has none, and an EmptyView
/// none: it takes no place and no spacing).
@MainActor func stackItems(_ children: [RenderNode]) -> [StackLayout.Item] {
    children.compactMap { child in
        guard child.element.type != "EmptyView", let view = child.outerView else { return nil }
        let spacerMinimum = child.element.type == "Spacer" ? (Spacer.Props(child.properties).minLength ?? Spacer.defaultMinLength) : nil
        return StackLayout.Item(view: view, spacerMinimum: spacerMinimum, expansion: child.expansion, cap: child.caps,
                                compressible: child.compression)
    }
}
