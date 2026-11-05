// Sources/Runtime/AnimationTiming.swift
/*
 An element's `animation` as the GTK renderer runs it: SwiftUI's curve, with its duration, delay
 and speed. Measured on macOS 27 (the curves' own descriptions, and values recorded frame by frame
 from a live window):
 - linear, easeIn, easeOut and easeInOut are cubic Bezier curves, 0.35 s unless a duration is given:
   (0, 0, 1, 1), (0.42, 0, 1, 1), (0, 0, 0.58, 1) and (0.42, 0, 0.58, 1).
 - The rest are springs, a response (0.5 s unless a duration is given) and a damping ratio: spring,
   smooth and default 1.0 (default is the smooth spring, not easeInOut), snappy 0.85, bouncy 0.7,
   interactiveSpring 0.85 with a 0.15 s response whatever the duration.
 - speed divides the delay as well as the duration, and a spring's response.

 What a box draws itself (opacity, offset, rotation, scale, shadow: BoxAnimation) follows these
 curves exactly, a spring through libadwaita's spring animation, whose stiffness and damping ratio
 are SwiftUI's. Colors and rounding are CSS (StyleSheet), which a GTK transition animates, and CSS
 has no springs: a spring there is the cubic Bezier closest to it over its settling time (within
 0.04 of the spring's value for a damping ratio of 1.0, 0.06 for 0.85, 0.08 for 0.7).
*/

import CAdwaita

struct AnimationTiming: Equatable {
    enum Curve: Equatable {
        /// A cubic Bezier from (0, 0) to (1, 1) through these control points, over `duration` seconds.
        case bezier(x1: Double, y1: Double, x2: Double, y2: Double, duration: Double)
        /// A spring with this response (seconds) and damping ratio, mass 1.
        case spring(response: Double, dampingRatio: Double)
    }

    var curve: Curve
    /// Seconds before the animation starts.
    var delay: Double

    /// SwiftUI's default duration of the timed curves, and response of the springs.
    static let timedDuration = 0.35
    static let springResponse = 0.5

    init(curve: Curve, delay: Double = 0) {
        self.curve = curve
        self.delay = delay
    }

    init(_ animation: BaseModifiers.Animation) {
        let speed = animation.speed > 0 && animation.speed.isFinite ? animation.speed : 1
        let given = animation.duration.flatMap { $0 > 0 && $0.isFinite ? $0 : nil }
        // Kept where libadwaita's 32-bit milliseconds and a spring's stiffness can hold them: a
        // duration or delay of at most a million seconds, a response of at least a millisecond.
        func seconds(_ value: Double) -> Double { min(value, 1_000_000) }
        func spring(_ value: Double) -> Double { max(seconds(value), 0.001) }
        let timed = seconds((given ?? Self.timedDuration) / speed)
        let response = spring((given ?? Self.springResponse) / speed)
        switch animation.curve {
        case .linear: curve = .bezier(x1: 0, y1: 0, x2: 1, y2: 1, duration: timed)
        case .easeIn: curve = .bezier(x1: 0.42, y1: 0, x2: 1, y2: 1, duration: timed)
        case .easeOut: curve = .bezier(x1: 0, y1: 0, x2: 0.58, y2: 1, duration: timed)
        case .easeInOut: curve = .bezier(x1: 0.42, y1: 0, x2: 0.58, y2: 1, duration: timed)
        case .default, .spring, .smooth: curve = .spring(response: response, dampingRatio: 1)
        case .snappy: curve = .spring(response: response, dampingRatio: 0.85)
        case .bouncy: curve = .spring(response: response, dampingRatio: 0.7)
        case .interactiveSpring: curve = .spring(response: spring(0.15 / speed), dampingRatio: 0.85)
        }
        let delay = animation.delay.isFinite ? max(animation.delay, 0) : 0
        self.delay = seconds(delay / speed)
    }

    // MARK: Bezier curves

    /// The value of the Bezier curve through (x1, y1) and (x2, y2) at `x`, 0 to 1 (the share of the
    /// duration gone): the curve's y where its x is `x`.
    static func bezierValue(x1: Double, y1: Double, x2: Double, y2: Double, at x: Double) -> Double {
        guard x > 0 else { return 0 }
        guard x < 1 else { return 1 }
        // Each coordinate is 3(1-s)^2 s p1 + 3(1-s) s^2 p2 + s^3 = ((a s + b) s + c) s.
        func coefficients(_ p1: Double, _ p2: Double) -> (a: Double, b: Double, c: Double) {
            let c = 3 * p1
            let b = 3 * (p2 - p1) - c
            return (1 - c - b, b, c)
        }
        let cx = coefficients(x1, x2)
        let cy = coefficients(y1, y2)
        func sample(_ k: (a: Double, b: Double, c: Double), _ s: Double) -> Double { ((k.a * s + k.b) * s + k.c) * s }
        // Newton's method from s = x, then bisection where the slope is too flat to trust it (x is
        // monotonic in s, as both x control points lie in 0...1).
        var s = x
        for _ in 0..<8 {
            let error = sample(cx, s) - x
            if abs(error) < 1e-7 { return sample(cy, s) }
            let slope = (3 * cx.a * s + 2 * cx.b) * s + cx.c
            if abs(slope) < 1e-6 { break }
            s -= error / slope
        }
        var low = 0.0
        var high = 1.0
        s = x
        for _ in 0..<60 {
            let value = sample(cx, s)
            if abs(value - x) < 1e-7 { break }
            if value < x { low = s } else { high = s }
            s = (low + high) / 2
        }
        return sample(cy, s)
    }

    // MARK: CSS

    /// A spring's settling time over its response, and the Bezier closest to it over that time, by
    /// damping ratio (SwiftUI's settlingDuration: smooth 0.8 s, snappy 0.877 s and bouncy 1.045 s
    /// at a 0.5 s response). Fitted offline, the largest difference over 60 points minimized.
    private static func cssSpring(_ dampingRatio: Double) -> (settling: Double, x1: Double, y1: Double, x2: Double, y2: Double) {
        if dampingRatio >= 0.95 { return (1.6, 0.3, 0.75, 0.25, 1.145) }
        if dampingRatio >= 0.8 { return (1.7537, 0.35, 1.15, 0.25, 1.071) }
        return (2.0894, 0.3, 1.4, 0.25, 1.036)
    }

    /// The CSS declarations that make a GTK transition of `properties` follow this timing.
    func cssDeclarations(_ properties: [String]) -> [String] {
        let duration: Double
        let points: (Double, Double, Double, Double)
        switch curve {
        case let .bezier(x1, y1, x2, y2, seconds):
            duration = seconds
            points = (x1, y1, x2, y2)
        case let .spring(response, dampingRatio):
            let fit = Self.cssSpring(dampingRatio)
            duration = response * fit.settling
            points = (fit.x1, fit.y1, fit.x2, fit.y2)
        }
        func number(_ value: Double) -> String {
            let rounded = (value * 1000).rounded() / 1000
            return rounded == rounded.rounded() ? String(Int(rounded)) : String(rounded)
        }
        return [
            "transition-property: \(properties.joined(separator: ", "));",
            "transition-duration: \(Int((duration * 1000).rounded()))ms;",
            "transition-timing-function: cubic-bezier(\(number(points.0)), \(number(points.1)), \(number(points.2)), \(number(points.3)));",
            "transition-delay: \(Int((delay * 1000).rounded()))ms;",
        ]
    }
}
