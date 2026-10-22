// Sources/Layout/FrameSolver.swift
/*
 SwiftUI's padding and frame arithmetic for one axis, apart from GTK, so it is tested without a
 display. The rules are SwiftUI's (OpenSwiftUI's FrameLayout.swift and PaddingLayout.swift):

 - Padding: the child is offered the space less the padding, and the padded size is the child's
   size plus the padding.
 - frame(width:): the frame is that size whatever its content; the content is offered that size.
 - frame(minWidth:idealWidth:maxWidth:), given a size p by its parent:
   - min and max: the frame is p clamped to them, whatever its content;
   - only max: p clamped to max, but at least the content (so it expands up to max);
   - only min: the content's size, at least min (and the content is offered at least min);
   - neither: the content's size.
   Asked for its ideal size (GTK's natural size): the ideal if given, else the content's ideal
   clamped to min and max. SwiftUI normalizes the values: min at least 0, ideal at least min,
   max at least ideal.

 In GTK terms the result is what StackSolver needs: a minimum, a natural size, whether the frame
 expands (true for any max, false for a fixed size, nil to follow the content) and its cap.
*/

/// The frame of one axis, in whole pixels. Built from BaseModifiers.Frame.
struct FrameAxis: Equatable {
    /// frame(width:) or frame(height:).
    var fixed: Int?
    var minimum: Int?
    var ideal: Int?
    /// nil: no maximum; `FrameAxis.infinity`: .infinity.
    var maximum: Int?

    static let infinity = Int.max

    /// No frame in this axis.
    static let none = FrameAxis()

    /// A flexible frame, normalized as SwiftUI does: minimum at least 0, ideal at least the
    /// minimum, maximum at least the ideal (and 0). A minimum still above the maximum makes the
    /// frame invalid in that axis: SwiftUI then ignores both and sizes to the content.
    static func flexible(minimum: Int?, ideal: Int?, maximum: Int?) -> FrameAxis {
        let low = minimum.map { max($0, 0) }
        let idealValue = ideal.map { max($0, low ?? 0) }
        let high = maximum.map { max($0, idealValue ?? 0) }
        if let low, let high, low > high {
            return FrameAxis(fixed: nil, minimum: nil, ideal: idealValue, maximum: nil)
        }
        return FrameAxis(fixed: nil, minimum: low, ideal: idealValue, maximum: high)
    }

    /// Whether the frame decides expansion: true (any maximum: the frame takes the space it is
    /// offered, up to the maximum), false (a fixed size), nil (as its content).
    var expands: Bool? {
        if fixed != nil { return false }
        return maximum != nil ? true : nil
    }

    /// The finite maximum, which caps how far the frame expands.
    var cap: Int? {
        guard fixed == nil, let maximum, maximum != Self.infinity else { return nil }
        return maximum
    }

    /// The frame's smallest size, for content (padding included) of `contentMinimum`.
    func minimumSize(content contentMinimum: Int) -> Int {
        if let fixed { return fixed }
        switch (minimum, maximum) {
        case let (low?, _):
            // With a maximum below its content the frame still shrinks to its minimum; the
            // content overflows it.
            return low
        case let (nil, high?):
            return min(contentMinimum, high)
        case (nil, nil):
            return contentMinimum
        }
    }

    /// The frame's ideal (natural) size, for content of `contentNatural`.
    func naturalSize(content contentNatural: Int, contentMinimum: Int) -> Int {
        let natural: Int
        if let fixed {
            natural = fixed
        } else if let ideal {
            natural = ideal
        } else {
            var value = contentNatural
            if let minimum { value = max(value, minimum) }
            if let maximum { value = min(value, maximum) }
            natural = value
        }
        return max(natural, minimumSize(content: contentMinimum))
    }

    /// The frame's size when its box is allocated `boxSize`. A parent may give the box more than
    /// the frame takes (GTK fills; SwiftUI's parent centers the frame in the extra space): a fixed
    /// frame is its size, a frame with a maximum takes the space up to it, and one without follows
    /// its content, which takes the space only when it expands. Measured on macOS: a fixed 100 x 50
    /// frame of filling content in 300 x 100 stays 100 x 50; frame(minWidth: 50) of a 10-wide
    /// content in 300 is 50; frame(maxWidth: 100) in 300 is 100.
    func size(in boxSize: Int, contentMinimum: Int, contentNatural: Int, contentExpands: Bool) -> Int {
        if let fixed { return fixed }
        let low = minimumSize(content: contentMinimum)
        if let maximum { return max(min(boxSize, maximum), low) }
        if contentExpands { return max(boxSize, low) }
        return max(min(boxSize, naturalSize(content: contentNatural, contentMinimum: contentMinimum)), low)
    }
}

/// Padding along one axis: before (top, leading) and after (bottom, trailing). Negative padding is
/// allowed, as in SwiftUI: the padded size is smaller than the content, which overflows it.
struct PaddingAxis: Equatable {
    var before = 0
    var after = 0

    var total: Int { before + after }
}

enum FrameSolver {
    /// SwiftUI's padding with no length, measured on macOS.
    static let systemPadding = 16

    /// The content's size in a frame (or box) of `size`: offered the size less the padding, it
    /// takes that clamped to its own range ([minimum, natural], or [minimum, unbounded] when it
    /// expands), so it may be smaller than the space or overflow it.
    static func contentSize(in size: Int, padding: PaddingAxis, minimum: Int, natural: Int, expands: Bool) -> Int {
        let offered = size - padding.total
        let upper = expands ? offered : min(offered, natural)
        return max(minimum, upper)
    }
}
