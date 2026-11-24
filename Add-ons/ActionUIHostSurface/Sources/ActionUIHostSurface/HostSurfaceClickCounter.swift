// Add-ons/ActionUIHostSurface/Sources/ActionUIHostSurface/HostSurfaceClickCounter.swift
//
// The click count of a press, on the platforms whose events carry none (Linux, Windows). Pure, so it is
// unit-tested without events.

#if os(Linux) || os(Windows)

/// Counts the presses of a multiple click: the next press of the same button within the double-click time and
/// distance counts on, any other press starts again at 1.
struct HostSurfaceClickCounter {
    private var lastTime: UInt32 = 0
    private var lastX = 0.0
    private var lastY = 0.0
    private var lastButton: Int32 = -1
    private(set) var count: Int32 = 0

    mutating func press(button: Int32, x: Double, y: Double, timeMilliseconds: UInt32,
                        doubleClickTime: UInt32, doubleClickDistance: Double) -> Int32 {
        let close = abs(x - lastX) <= doubleClickDistance && abs(y - lastY) <= doubleClickDistance
        // Event times wrap after 49 days; the subtraction wraps with them.
        let soon = timeMilliseconds &- lastTime <= doubleClickTime
        count = (button == lastButton && close && soon && count > 0) ? count + 1 : 1
        lastTime = timeMilliseconds
        lastX = x
        lastY = y
        lastButton = button
        return count
    }
}

#endif
