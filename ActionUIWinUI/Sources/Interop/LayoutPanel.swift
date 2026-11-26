// Sources/Interop/LayoutPanel.swift
/*
 A WinUI Panel whose layout is Swift's: WinUI's measure and arrange passes over the panel call
 `measure` and `arrange`, which place `children` (with WinUIObject.measure and arrange). Every
 ActionUI container on Windows (stacks and the other layouts) is one of these, as on Linux every
 container is an ActionUI container widget with its own layout manager.

 The shim holds a context for the callbacks: a box with a weak reference to the LayoutPanel, so
 the panel object (which the box lives as long as) does not keep the LayoutPanel alive. The shim
 frees the box when the panel object goes away.

 WinUI lays a parent out again only when a child's desired size changes, and that is capped at
 the size offered: a child squeezed below its floor (a label in a tight row) whose floor changes
 while running (a bound minWidth or padding, a nested stack gaining a child) keeps the same
 desired size, and its parent would keep the old floor. So a panel measured again for the size
 it was last offered whose answer (requested) changed asks its ActionUI parent for a new layout,
 after the current one. A panel with no ActionUI parent (a window's root) tells
 requestedChangedAtRoot instead, so the window can grow to content that needs more than it had.
*/

import CWinUI
import Dispatch

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
        guard let panel = box?.panel else { return ActionUIWinUISize(width: 0, height: 0) }
        let size = panel.measure(available)
        let sameOffer = available.width == panel.lastOffer.width && available.height == panel.lastOffer.height
        if sameOffer && (size.width != panel.requested.width || size.height != panel.requested.height) {
            if let parent = panel.parentPanel {
                parent.invalidateLayoutLater()
            } else {
                panel.requestedChangedAtRoot?(available, panel.requested, size)
            }
        }
        panel.lastOffer = available
        panel.requested = size
        // WinUI gets no more than it offered: its desired size is capped there anyway, but an
        // element whose measure asked for more is arranged at least that large, aligned to its
        // slot's top leading corner and clipped to the slot. ActionUI's parents read the full
        // answer (requested) and place a larger child themselves, centered or by its alignment, as
        // SwiftUI lets it overflow.
        return ActionUIWinUISize(width: min(size.width, available.width), height: min(size.height, available.height))
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
    /// What `measure` last returned, which can be larger than the size offered; WinUI gets it
    /// capped there (measurePanel): WinUIObject.measureRequested.
    package fileprivate(set) var requested = ActionUIWinUISize(width: 0, height: 0)
    /// The size offered to the last measure. Not a number before the first, so that no offer
    /// matches it: a first measure offered unbounded room is not one "for the same size".
    fileprivate var lastOffer = ActionUIWinUISize(width: .nan, height: .nan)
    /// The ActionUI panel holding this one, when there is one (set by its insert).
    fileprivate weak var parentPanel: LayoutPanel?
    /// Whether a new layout is already asked for after the current one (invalidateLayoutLater).
    private var layoutPending = false
    /// Called, inside the measure pass, when this panel has no ActionUI parent and its answer
    /// (requested) changed for the size it was offered before: the size offered, the answer before
    /// and the new answer. Its window's content (WinUIWindow.fit) grows the window from it, after
    /// the pass.
    package var requestedChangedAtRoot: ((ActionUIWinUISize, ActionUIWinUISize, ActionUIWinUISize) -> Void)?
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
        object.layoutPanel = self
    }

    package func insert(_ child: WinUIObject, at index: Int) throws(WinUIError) {
        guard actionUIWinUIPanelInsertChild(object.pointer, Int32(index), child.pointer) else {
            throw WinUIError.last("adding a child to a layout panel")
        }
        children.insert(child, at: index)
        child.layoutPanel?.parentPanel = self
    }

    package func append(_ child: WinUIObject) throws(WinUIError) {
        try insert(child, at: children.count)
    }

    package func remove(at index: Int) throws(WinUIError) {
        guard actionUIWinUIPanelRemoveChild(object.pointer, Int32(index)) else {
            throw WinUIError.last("removing a child from a layout panel")
        }
        let child = children.remove(at: index)
        if child.layoutPanel?.parentPanel === self {
            child.layoutPanel?.parentPanel = nil
        }
    }

    /// Makes `child`, a layout panel's object held through a WinUI element between the two (a rounded
    /// box), tell this panel of its size changes as a direct child does.
    package func adoptThroughWrapper(_ child: WinUIObject) {
        child.layoutPanel?.parentPanel = self
    }

    /// Asks WinUI to lay the panel out again.
    package func invalidateLayout() {
        object.invalidateMeasure()
    }

    /// Asks for a new layout once the current layout pass is over (once, however often asked):
    /// invalidating a parent from inside its child's measure would change the tree WinUI is
    /// walking.
    fileprivate func invalidateLayoutLater() {
        guard !layoutPending else { return }
        layoutPending = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.layoutPending = false
                self.invalidateLayout()
            }
        }
    }
}
