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
   all the width it is offered.
 - Default spacing (none given) is 8, and 0 next to a Spacer, as SwiftUI's; a given spacing is used
   everywhere.
 - The stack asks for its children's lengths and gaps along the axis (all it is offered when it
   holds a child that expands along it) and its widest child across.
 - Arranged in more room than it asked for (the root of a window), the stack is centered in it, as
   SwiftUI centers a window's content, and in less room around the middle, its children keeping
   their sizes (as on Linux); its children are aligned across inside the stack's own cross size
   (alignment: leading, center or trailing for a VStack; top, center or bottom for an HStack).

 Not yet: frames with infinite maximums, compressing children that do not fit (a Text that would
 wrap in an HStack), baselines, expansion through a nested stack (an HStack holding an HStack with a
 TextField keeps the inner stack at its own width; a stack's expansion is its renderer's, not yet
 its children's).
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
        /// How the child grows (its renderer's defaultExpansion).
        var expansion: Expansion = []
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

    private func rect(main: Double, cross: Double, mainLength: Double, crossLength: Double) -> ActionUIWinUIRect {
        axis == .vertical
            ? ActionUIWinUIRect(x: cross, y: main, width: crossLength, height: mainLength)
            : ActionUIWinUIRect(x: main, y: cross, width: mainLength, height: crossLength)
    }

    // MARK: Layout

    /// Each child measured for `crossOffer` across and unbounded along the axis: its StackChild and
    /// its size across.
    private func measureChildren(crossOffer: Double) -> (children: [StackChild], crossSizes: [Int]) {
        var children: [StackChild] = []
        var crossSizes: [Int] = []
        for item in items {
            if let minimum = item.spacerMinimum {
                // Measured all the same: WinUI arranges only children measured in this pass.
                _ = item.view.measure(ActionUIWinUISize(width: 0, height: 0))
                children.append(.spacer(minimum: StackSolver.length(minimum)))
                crossSizes.append(0)
                continue
            }
            let desired = item.view.measure(size(main: .infinity, cross: crossOffer))
            let length = StackSolver.length(main(desired), rounding: .up)
            let (expandsAlong, expandsAcross) = expands(item)
            children.append(expandsAlong ? .expanding(minimum: length) : .fixed(minimum: length, natural: length))
            let crossLength = StackSolver.length(cross(desired), rounding: .up)
            // A child that expands across takes all the stack is offered across, when that is known.
            crossSizes.append(expandsAcross && crossOffer.isFinite ? max(crossLength, StackSolver.length(crossOffer)) : crossLength)
        }
        return (children, crossSizes)
    }

    private func gaps(_ children: [StackChild]) -> [Int] {
        StackSolver.gaps(children, spacing: StackSolver.length(spacing ?? Self.defaultSpacing), isDefaultSpacing: spacing == nil)
    }

    private func measure(_ available: ActionUIWinUISize) -> ActionUIWinUISize {
        let (children, crossSizes) = measureChildren(crossOffer: cross(available))
        let gaps = gaps(children)
        let offeredMain = main(available)
        let hasExpanding = items.contains { $0.spacerMinimum != nil || expands($0).main }
        let sizes: [Int]
        if offeredMain.isFinite && hasExpanding {
            sizes = StackSolver.mainSizes(children, available: StackSolver.length(offeredMain), gaps: gaps)
        } else {
            sizes = children.map(\.minimum)
        }
        let length = StackSolver.length(of: sizes, gaps: gaps)
        return size(main: Double(length), cross: Double(crossSizes.max() ?? 0))
    }

    private func arrange(_ finalSize: ActionUIWinUISize) {
        let (children, crossSizes) = measureChildren(crossOffer: cross(finalSize))
        let gaps = gaps(children)
        let available = StackSolver.length(main(finalSize))
        let sizes = StackSolver.mainSizes(children, available: available, gaps: gaps)
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
/// WinUI objects in the stack.
@MainActor func syncStackContent(_ node: RenderNode, _ stack: StackLayout) {
    let children = node.syncChildren(node.subviews("children"))
    stack.setItems(children.compactMap { child in
        guard let view = child.view else { return nil }
        let spacerMinimum = child.element.type == "Spacer" ? (Spacer.Props(child.properties).minLength ?? Spacer.defaultMinLength) : nil
        return StackLayout.Item(view: view, spacerMinimum: spacerMinimum, expansion: child.renderer.defaultExpansion)
    })
}
