// Sources/Elements/GeometryReader+WinUI.swift
/*
 GeometryReader on WinUI, as on Apple and Linux (the Linux renderer's geometry-* layout parity
 fixtures, measured on macOS): greedy, it takes the room it is offered in both axes and shares a stack
 like a Color, SwiftUI's ideal 10 x 10 when offered unbounded room, whatever its content; it offers its
 content its whole size, which the content takes (all of it, up to its cap, where it expands; what it
 asks for elsewhere), and places the content at its alignment (top leading unless set; content larger
 than the reader starts at its top leading corner in that axis). Its size goes to states["size"] as
 [width, height] after each layout that changes it, as SwiftUI reports it on appear and on change.
*/

import Dispatch
import CWinUI

/// A GeometryReader's panel: its content placed in the room it takes.
@MainActor final class GeometryLayout {
    let panel: LayoutPanel
    weak var node: RenderNode?
    var alignment = (horizontal: StackSolver.Alignment.start, vertical: StackSolver.Alignment.start)
    private(set) var item: ZStackLayout.Item?
    /// The content's desired size from the last measure pass, for arrange.
    private var desired = ActionUIWinUISize(width: 0, height: 0)
    /// The size last written to states["size"] (or waiting to be).
    private var reported: [Double]?

    init(node: RenderNode) throws(WinUIError) {
        self.node = node
        panel = try LayoutPanel()
        panel.measure = { [unowned self] available in measure(available) }
        panel.arrange = { [unowned self] finalSize in arrange(finalSize) }
    }

    func setItem(_ newItem: ZStackLayout.Item?) {
        let changed = newItem?.view !== item?.view
        let reshaped = newItem?.expansion != item?.expansion || newItem?.cap.horizontal != item?.cap.horizontal
            || newItem?.cap.vertical != item?.cap.vertical
        item = newItem
        if changed {
            do {
                while !panel.children.isEmpty {
                    try panel.remove(at: panel.children.count - 1)
                }
                if let newItem {
                    try panel.append(newItem.view)
                }
            } catch {
                ActionUIModel.shared.logger.log("GeometryReader: \(error)", .error)
            }
        }
        if changed || reshaped {
            panel.invalidateLayout()
        }
    }

    private func measure(_ available: ActionUIWinUISize) -> ActionUIWinUISize {
        let size = ActionUIWinUISize(width: available.width.isFinite ? available.width : FillLayout.idealLength,
                                     height: available.height.isFinite ? available.height : FillLayout.idealLength)
        // Its content is offered the reader's own size, never unbounded room, as SwiftUI's frame of
        // the proxy's size does (what it asks beyond it overflows at arrange).
        desired = item?.view.measureRequested(size) ?? ActionUIWinUISize(width: 0, height: 0)
        return size
    }

    /// The content's length in one axis of the reader's `size`: all of it (up to its cap) when it
    /// expands there, and at least what it asked for.
    private func length(desired: Double, size: Int, expands: Bool, cap: Int?) -> Int {
        let asked = StackSolver.length(desired, rounding: .up)
        return expands ? max(min(size, cap ?? size), asked) : asked
    }

    private func arrange(_ finalSize: ActionUIWinUISize) {
        let width = StackSolver.length(finalSize.width)
        let height = StackSolver.length(finalSize.height)
        report(width: width, height: height)
        guard let item else { return }
        let contentWidth = length(desired: desired.width, size: width, expands: item.expansion.contains(.horizontal), cap: item.cap.horizontal)
        let contentHeight = length(desired: desired.height, size: height, expands: item.expansion.contains(.vertical), cap: item.cap.vertical)
        // Content larger than the reader starts at its top leading corner whatever the alignment
        // (measured: geometry-overflow-center), as SwiftUI aligns it in a frame at least its size.
        let x = max(0, StackSolver.alignedOffset(size: contentWidth, block: width, alignment: alignment.horizontal))
        let y = max(0, StackSolver.alignedOffset(size: contentHeight, block: height, alignment: alignment.vertical))
        item.view.arrange(ActionUIWinUIRect(x: Double(x), y: Double(y), width: Double(contentWidth), height: Double(contentHeight)))
    }

    /// Writes the size to states["size"] after this layout, when it changed: a write during the layout
    /// would sync the window while WinUI lays it out.
    private func report(width: Int, height: Int) {
        let size = [Double(width), Double(height)]
        guard size != reported else { return }
        reported = size
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let node = self.node, node.isAttached, self.reported == size,
                      node.model.states["size"] as? [Double] != size else { return }
                node.model.states["size"] = size
            }
        }
    }
}

extension GeometryReader: ActionUIWinUIRenderer {
    static var defaultExpansion: Expansion { .both }

    static func makeView(_ node: RenderNode) throws(WinUIError) -> WinUIObject {
        let layout = try GeometryLayout(node: node)
        node.state = layout
        return layout.panel.object
    }

    static func update(_ view: WinUIObject, _ node: RenderNode) {
        guard let layout = node.state as? GeometryLayout else { return }
        let content = node.effectiveElement.subviews?["content"] as? any ActionUIElementBase
        let child = node.syncChildren(content.map { [$0] } ?? []).first
        layout.setItem(child.flatMap { child in
            guard !child.takesNoPlace, let view = child.outerView else { return nil }
            return ZStackLayout.Item(view: view, expansion: child.expansion, cap: child.caps)
        })
        let alignment = alignment(Props(node.properties).alignment)
        if alignment.0 != layout.alignment.horizontal || alignment.1 != layout.alignment.vertical {
            layout.alignment = (alignment.0, alignment.1)
            layout.panel.invalidateLayout()
        }
    }

    private static func alignment(_ alignment: Props.Alignment) -> (StackSolver.Alignment, StackSolver.Alignment) {
        switch alignment {
        case .topLeading: return (.start, .start)
        case .top: return (.center, .start)
        case .topTrailing: return (.end, .start)
        case .leading: return (.start, .center)
        case .center: return (.center, .center)
        case .trailing: return (.end, .center)
        case .bottomLeading: return (.start, .end)
        case .bottom: return (.center, .end)
        case .bottomTrailing: return (.end, .end)
        }
    }
}
