// Sources/Interop/WinUIObject.swift
/*
 One reference to a WinUI object (ActionUIWinUIObject in the shim), given back when the
 WinUIObject goes away. The shim's create functions return a reference of the caller's own:
 `adopting` takes it over. A pointer the shim lends for the length of a call (a layout callback's
 panel) is taken with `retaining`, which adds a reference.

 XAML objects must be released on the UI thread, while WinUI runs: the class is main-actor
 isolated and its deinit too, so the last release always happens there.
*/

import CWinUI

@MainActor package final class WinUIObject {
    package let pointer: OpaquePointer
    /// The ActionUI panel this object is, when it is one (LayoutPanel sets it), for
    /// measureRequested.
    package weak var layoutPanel: LayoutPanel?

    /// Takes over the reference a shim function returned; nil (nothing to release) when it
    /// returned NULL.
    package init?(adopting pointer: OpaquePointer?) {
        guard let pointer else { return nil }
        self.pointer = pointer
    }

    /// A reference of its own to a pointer the shim lends.
    package init(retaining pointer: OpaquePointer) {
        self.pointer = actionUIWinUIRetain(pointer)
    }

    isolated deinit {
        actionUIWinUIRelease(pointer)
    }

    // MARK: Layout, for a panel's measure and arrange passes

    /// Measures this element with the size offered and returns the size it wants.
    package func measure(_ available: ActionUIWinUISize) -> ActionUIWinUISize {
        actionUIWinUIElementMeasure(pointer, available)
    }

    /// Measures this element with the size offered and returns the size it asked for, which can be
    /// larger than the size offered: an ActionUI panel's own answer (its padding, its frame's
    /// minimum, a stack's children at their smallest), where WinUI's desired size is capped at the
    /// size offered. Another element (a TextBlock) gives its desired size. When WinUI skips the
    /// measure (offered the same size again, nothing changed), the panel's answer is still the one
    /// for this size.
    package func measureRequested(_ available: ActionUIWinUISize) -> ActionUIWinUISize {
        let desired = measure(available)
        return layoutPanel?.requested ?? desired
    }

    /// Places this element at `frame`, in its parent's coordinates.
    package func arrange(_ frame: ActionUIWinUIRect) {
        if !actionUIWinUIElementArrange(pointer, frame) {
            ActionUIModel.shared.logger.log("WinUIObject: \(WinUIError.last("arranging an element"))", .error)
        }
    }

    /// Asks WinUI to measure this element again.
    package func invalidateMeasure() {
        _ = actionUIWinUIElementInvalidateMeasure(pointer)
    }

    /// Where this element was last placed: its offset in its parent and its size.
    package var layoutFrame: ActionUIWinUIRect {
        actionUIWinUIElementLayoutFrame(pointer)
    }
}
