// Helpers/SplitViewInitialPositionSetter.swift
// Sets the initial divider position of the enclosing NSSplitView.
// Workaround for SwiftUI HSplitView/VSplitView ignoring idealWidth/idealHeight
// on children for initial sizing (defaulting to 50/50 split).

#if os(macOS)
import SwiftUI
import AppKit

struct SplitViewInitialPositionSetter: NSViewRepresentable {
    let position: CGFloat

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            if let splitView = view.enclosingSplitView() {
                splitView.setPosition(position, ofDividerAt: 0)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private extension NSView {
    func enclosingSplitView() -> NSSplitView? {
        var current: NSView? = self.superview
        while let view = current {
            if let splitView = view as? NSSplitView { return splitView }
            current = view.superview
        }
        return nil
    }
}
#endif
