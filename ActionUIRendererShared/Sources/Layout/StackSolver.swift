// Sources/Layout/StackSolver.swift
/*
 SwiftUI's stack arithmetic, apart from GTK, so it is tested without a display.

 Along the stack's axis SwiftUI does not give children their natural sizes and share the rest: it
 proposes space to one child at a time, least flexible first (ties in order), each time the
 space left divided by the number of children left, and each child takes what it wants of that,
 so space one child does not use goes to the children after it. Flexibility is the range of sizes
 a child can take (its largest minus its smallest). Both reimplementations of SwiftUI that publish
 their code (OpenSwiftUI and SwiftCrossUI) and the published measurements of SwiftUI's stacks
 agree on this. ActionUI has no layoutPriority, but SwiftUI's Spacer has the lowest one (measured
 on macOS 27, and OpenSwiftUI's Spacer says -infinity): the spacers form a second group, placed
 after all the other children, which share the space left once the spacers' minimums are set
 aside; the spacers then get those back plus whatever the others left. Among unbounded children
 the one with the larger minimum goes first (SwiftUI's FlexibilityEstimate). A stack given no
 spacing puts none next to a spacer (measured: a Spacer's spacing preference is zero).

 In GTK terms a child is its minimum size and the largest size it takes: its natural size, or,
 for a child that expands in that axis, its frame's maximum (unbounded without one). Offered a
 size, a child takes it clamped to that range.
*/

/// One child along one axis: the smallest and the largest size it takes.
struct StackChild: Equatable {
    var minimum: Int
    /// nil: unbounded (an expanding child without a maximum).
    var maximum: Int?
    /// A Spacer: placed after the other children, no default spacing next to it.
    var isSpacer = false

    /// A child that does not expand: it takes up to its natural size.
    static func fixed(minimum: Int, natural: Int) -> StackChild {
        StackChild(minimum: minimum, maximum: max(natural, minimum))
    }

    /// A child that expands: it takes any size offered, up to `cap`.
    static func expanding(minimum: Int, cap: Int? = nil) -> StackChild {
        StackChild(minimum: minimum, maximum: cap.map { max($0, minimum) })
    }

    /// A Spacer: expands, at least `minimum` long.
    static func spacer(minimum: Int) -> StackChild {
        StackChild(minimum: minimum, maximum: nil, isSpacer: true)
    }

    /// What the child takes when offered `proposal`.
    func size(offered proposal: Int) -> Int {
        let upper = maximum.map { min(proposal, $0) } ?? proposal
        return max(minimum, upper)
    }

    /// How far the child's size can range; unbounded children are the most flexible.
    var flexibility: Int {
        maximum.map { $0 - minimum } ?? Int.max
    }
}

enum StackSolver {
    /// The spacing between each pair of neighbors (one less than the children): `spacing`, except
    /// that a stack's default spacing (one given none) is 0 next to a spacer.
    static func gaps(_ children: [StackChild], spacing: Int, isDefaultSpacing: Bool) -> [Int] {
        guard children.count > 1 else { return [] }
        return (1..<children.count).map { index in
            isDefaultSpacing && (children[index - 1].isSpacer || children[index].isSpacer) ? 0 : spacing
        }
    }

    /// mainSizes with the same `spacing` between all neighbors.
    static func mainSizes(_ children: [StackChild], available: Int, spacing: Int) -> [Int] {
        mainSizes(children, available: available, gaps: gaps(children, spacing: spacing, isDefaultSpacing: false))
    }

    /// The children's sizes along the stack's axis, in their order, for `available` space and
    /// `gaps` between neighbors. The sizes may add up to less than the space (the stack is then
    /// smaller than its allocation) or more (the children's minimums do not fit).
    /// `proposal`: what the stack was proposed, when known exactly (a fixed frame's size): the
    /// space is shared out of it, as SwiftUI shares a proposal.
    static func mainSizes(_ children: [StackChild], available: Int, gaps: [Int], proposal: Int? = nil) -> [Int] {
        guard !children.isEmpty else { return [] }
        var remaining = (proposal ?? available) - gaps.reduce(0, +)
        // Without a known proposal: children that all have a largest size, given room for all of
        // them at it, each take it. GTK gives a stack of such children no more than the sum of
        // those sizes (its natural size, or its cap when it expands), where SwiftUI's parent
        // usually proposes more (a VStack its width), and SwiftUI's shares below give every child
        // its largest size in that proposal; shared out of just the sum, they can leave a child
        // short. A frame of fixed size proposes exactly its size, which SwiftUI shares even when
        // it leaves a child short (measured: the ideal layout parity fixtures).
        let largest = children.compactMap(\.maximum)
        if proposal == nil, largest.count == children.count, remaining >= largest.reduce(0, +) {
            return largest
        }
        var sizes = Array(repeating: 0, count: children.count)
        // SwiftUI's priority groups: the spacers come after everything else. The first group's
        // space leaves out the later groups' minimums, which they get back on their turn.
        let groups = [children.indices.filter { !children[$0].isSpacer },
                      children.indices.filter { children[$0].isSpacer }].filter { !$0.isEmpty }
        for (position, group) in groups.enumerated() {
            let minimums = group.reduce(0) { $0 + children[$1].minimum }
            if position == 0 {
                for later in groups.dropFirst() {
                    remaining -= later.reduce(0) { $0 + children[$1].minimum }
                }
            } else {
                remaining += minimums
            }
            var left = group.count
            for index in fittingOrder(group, in: children) {
                let proposal = max(remaining, 0) / left
                let size = children[index].size(offered: proposal)
                sizes[index] = size
                remaining -= size
                left -= 1
            }
        }
        return sizes
    }

    /// The order in which a group's children are offered space: the least flexible first; among
    /// unbounded children the one with the larger minimum first (SwiftUI's FlexibilityEstimate);
    /// ties in source order.
    private static func fittingOrder(_ indices: [Int], in children: [StackChild]) -> [Int] {
        indices.sorted { a, b in
            let first = children[a]
            let second = children[b]
            if first.flexibility != second.flexibility {
                return first.flexibility < second.flexibility
            }
            if first.maximum == nil, second.maximum == nil, first.minimum != second.minimum {
                return first.minimum > second.minimum
            }
            return a < b
        }
    }

    /// The space the children and the same `spacing` between them take.
    static func length(of sizes: [Int], spacing: Int) -> Int {
        sizes.reduce(0, +) + spacing * max(sizes.count - 1, 0)
    }

    /// The space the children and the `gaps` between them take.
    static func length(of sizes: [Int], gaps: [Int]) -> Int {
        sizes.reduce(0, +) + gaps.reduce(0, +)
    }

    /// The longest length a document's value becomes: half of GTK's int, so sums of lengths and
    /// GTK's own additions (margins, borders) stay in range.
    static let maximumLength = Int(Int32.max / 2)

    /// A length from a document (a spacing, a minimum, a frame maximum) as whole pixels: rounded,
    /// never negative, and at most maximumLength. Int(Double) traps on values out of its range,
    /// which a document can carry.
    static func length(_ value: Double, rounding: FloatingPointRoundingRule = .toNearestOrAwayFromZero) -> Int {
        guard value.isFinite, value > 0 else { return 0 }
        return Int(min(value.rounded(rounding), Double(maximumLength)))
    }

    /// A signed length from a document (a padding) as whole pixels: rounded, and within
    /// maximumLength either way.
    static func signedLength(_ value: Double) -> Int {
        guard value.isFinite else { return 0 }
        return Int(min(max(value.rounded(), -Double(maximumLength)), Double(maximumLength)))
    }

    /// Where content of `length` starts in `available` space: centered, as SwiftUI centers a stack
    /// in a larger proposal (and an overflowing one around the middle).
    static func centeredStart(length: Int, available: Int) -> Int {
        (available - length) / 2
    }

    /// Where along the cross axis.
    enum Alignment: Equatable {
        case start, center, end
    }

    /// The offset of a child of `size` aligned in a block of `block`.
    static func alignedOffset(size: Int, block: Int, alignment: Alignment) -> Int {
        switch alignment {
        case .start: return 0
        case .center: return (block - size) / 2
        case .end: return block - size
        }
    }
}
