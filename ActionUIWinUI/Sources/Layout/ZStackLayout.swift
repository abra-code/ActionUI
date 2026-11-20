// Sources/Layout/ZStackLayout.swift
/*
 ZStack on WinUI: a LayoutPanel layering its children in order, as SwiftUI's ZStack and the GTK
 renderer's ZStackLayout: each child is offered the ZStack's room; the ZStack is as large as its
 largest child in each axis; each child is placed by the ZStack's alignment, and a child that
 expands in an axis (a Color, a frame with a maximum) takes the ZStack's whole size in it, up to
 its cap and at least what it asks for.

 Each child's size is what it asks for even beyond the room (WinUIObject.measureRequested), so a
 ZStack measured with nothing offered has its largest child's padding and frame minimum, its
 smallest size for a stack that squeezes it.
*/

import CWinUI

@MainActor
final class ZStackLayout {
    struct Item {
        let view: WinUIObject
        var expansion: Expansion = []
        var cap: (horizontal: Int?, vertical: Int?) = (nil, nil)
    }

    let panel: LayoutPanel
    var alignment = (horizontal: StackSolver.Alignment.center, vertical: StackSolver.Alignment.center)
    private(set) var items: [Item] = []
    /// Each child's desired size from the last measure pass, for arrange, which must not measure it
    /// with another size (that would start WinUI's layout again).
    private var desired: [ObjectIdentifier: ActionUIWinUISize] = [:]

    init() throws(WinUIError) {
        panel = try LayoutPanel()
        panel.measure = { [unowned self] available in measure(available) }
        panel.arrange = { [unowned self] finalSize in arrange(finalSize) }
    }

    func setItems(_ newItems: [Item]) {
        let current = items.map { ObjectIdentifier($0.view) }
        let wanted = newItems.map { ObjectIdentifier($0.view) }
        let changed = items.map(\.expansion.rawValue) != newItems.map(\.expansion.rawValue)
            || !items.elementsEqual(newItems) { $0.cap == $1.cap }
        items = newItems
        if current != wanted {
            do {
                while !panel.children.isEmpty {
                    try panel.remove(at: panel.children.count - 1)
                }
                for item in newItems {
                    try panel.append(item.view)
                }
            } catch {
                ActionUIModel.shared.logger.log("ZStackLayout: \(error)", .error)
            }
        }
        if current != wanted || changed {
            panel.invalidateLayout()
        }
    }

    private func measure(_ available: ActionUIWinUISize) -> ActionUIWinUISize {
        var width = 0
        var height = 0
        self.desired = [:]
        for item in items {
            let desired = item.view.measureRequested(available)
            self.desired[ObjectIdentifier(item.view)] = desired
            width = max(width, StackSolver.length(desired.width, rounding: .up))
            height = max(height, StackSolver.length(desired.height, rounding: .up))
        }
        return ActionUIWinUISize(width: Double(width), height: Double(height))
    }

    /// A child's size in one axis of the ZStack's `size`: all of it (up to its cap) when it expands
    /// there, and at least what it asked for, even beyond the ZStack's size (placed by the
    /// alignment, overflowing the ZStack as in SwiftUI).
    private func length(desired: Double, size: Int, expands: Bool, cap: Int?) -> Int {
        let asked = StackSolver.length(desired, rounding: .up)
        return expands ? max(min(size, cap ?? size), asked) : asked
    }

    private func arrange(_ finalSize: ActionUIWinUISize) {
        let width = StackSolver.length(finalSize.width)
        let height = StackSolver.length(finalSize.height)
        for item in items {
            let desired = self.desired[ObjectIdentifier(item.view)] ?? item.view.measureRequested(finalSize)
            let childWidth = length(desired: desired.width, size: width, expands: item.expansion.contains(.horizontal),
                                    cap: item.cap.horizontal)
            let childHeight = length(desired: desired.height, size: height, expands: item.expansion.contains(.vertical),
                                     cap: item.cap.vertical)
            let x = StackSolver.alignedOffset(size: childWidth, block: width, alignment: alignment.horizontal)
            let y = StackSolver.alignedOffset(size: childHeight, block: height, alignment: alignment.vertical)
            item.view.arrange(ActionUIWinUIRect(x: Double(x), y: Double(y), width: Double(childWidth), height: Double(childHeight)))
        }
    }
}

extension ZStack: ActionUIWinUIRenderer {
    static func expansion(_ node: RenderNode) -> Expansion { StackViews.childrenExpansion(node) }

    static func compression(_ node: RenderNode) -> Expansion { StackViews.childrenCompression(node) }

    static func makeView(_ node: RenderNode) throws(WinUIError) -> WinUIObject {
        let stack = try ZStackLayout()
        node.state = stack
        return stack.panel.object
    }

    static func update(_ view: WinUIObject, _ node: RenderNode) {
        guard let stack = node.state as? ZStackLayout else { return }
        let props = Props(node.properties)
        let alignment = ModifierBox.alignmentAxes(BaseModifiers.AlignmentName(rawValue: props.alignment.rawValue))
        if stack.alignment.horizontal != alignment.horizontal || stack.alignment.vertical != alignment.vertical {
            stack.alignment = alignment
            stack.panel.invalidateLayout()
        }
        let children = node.syncChildren(node.subviews("children"))
        stack.setItems(children.compactMap { child in
            // An EmptyView is no layer: its padding would size the ZStack and its background show.
            guard child.element.type != "EmptyView", let view = child.outerView else { return nil }
            return ZStackLayout.Item(view: view, expansion: child.expansion, cap: child.caps)
        })
    }
}
