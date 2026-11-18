// Sources/Interop/LayoutPanel.swift
/*
 A WinUI Panel whose layout is Swift's: WinUI's measure and arrange passes over the panel call
 `measure` and `arrange`, which place `children` (with WinUIObject.measure and arrange). Every
 ActionUI container on Windows (stacks and the other layouts) is one of these, as on Linux every
 container is an ActionUI container widget with its own layout manager.

 The shim holds a context for the callbacks: a box with a weak reference to the LayoutPanel, so
 the panel object (which the box lives as long as) does not keep the LayoutPanel alive. The shim
 frees the box when the panel object goes away.
*/

import CWinUI

@MainActor private final class PanelBox {
    weak var panel: LayoutPanel?
    static var live = 0
}

/// The box behind a callback's context, taken before entering the main actor: the box is
/// main-actor isolated, so it may cross; the raw pointer may not.
private func panelBox(_ context: UnsafeMutableRawPointer?) -> PanelBox? {
    context.map { Unmanaged<PanelBox>.fromOpaque($0).takeUnretainedValue() }
}

private let measurePanel: ActionUIWinUIMeasureCallback = { context, _, available in
    let box = panelBox(context)
    return MainActor.assumeIsolated {
        box?.panel?.measure(available) ?? ActionUIWinUISize(width: 0, height: 0)
    }
}

private let arrangePanel: ActionUIWinUIArrangeCallback = { context, _, finalSize in
    let box = panelBox(context)
    MainActor.assumeIsolated {
        box?.panel?.arrange(finalSize)
    }
}

// Gives back the reference passRetained took, once the shim's panel object is gone.
private let releaseBox: ActionUIWinUICallback = { context in
    guard let context else { return }
    MainActor.assumeIsolated {
        PanelBox.live -= 1
    }
    Unmanaged<PanelBox>.fromOpaque(context).release()
}

@MainActor package final class LayoutPanel {
    /// The WinUI Panel.
    package let object: WinUIObject
    /// The panel's children, in the panel's order.
    package private(set) var children: [WinUIObject] = []

    /// Given the size offered, measures the children and returns the size the panel wants.
    package var measure: (ActionUIWinUISize) -> ActionUIWinUISize = { _ in ActionUIWinUISize(width: 0, height: 0) }
    /// Places every child inside the final size.
    package var arrange: (ActionUIWinUISize) -> Void = { _ in }

    /// How many panel objects are alive (their callback boxes not yet freed by the shim).
    package static var livePanelObjects: Int { PanelBox.live }

    package init() throws(WinUIError) {
        let box = PanelBox()
        let context = Unmanaged.passRetained(box).toOpaque()
        PanelBox.live += 1
        // On failure the shim has already called releaseBox.
        guard let object = WinUIObject(adopting: actionUIWinUIPanelCreate(measurePanel, arrangePanel, context, releaseBox)) else {
            throw WinUIError.last("creating a layout panel")
        }
        self.object = object
        box.panel = self
    }

    package func insert(_ child: WinUIObject, at index: Int) throws(WinUIError) {
        guard actionUIWinUIPanelInsertChild(object.pointer, Int32(index), child.pointer) else {
            throw WinUIError.last("adding a child to a layout panel")
        }
        children.insert(child, at: index)
    }

    package func append(_ child: WinUIObject) throws(WinUIError) {
        try insert(child, at: children.count)
    }

    package func remove(at index: Int) throws(WinUIError) {
        guard actionUIWinUIPanelRemoveChild(object.pointer, Int32(index)) else {
            throw WinUIError.last("removing a child from a layout panel")
        }
        children.remove(at: index)
    }

    /// Asks WinUI to lay the panel out again.
    package func invalidateLayout() {
        object.invalidateMeasure()
    }
}
