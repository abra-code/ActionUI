// Sources/Layout/LazyRows.swift
/*
 The template form of LazyVStack and LazyHStack on WinUI, made lazily: an ItemsRepeater (the shim's
 repeater, WinUI's virtualizing control) shows one item per content row and asks for an item's
 element only when the item comes in or near the part of it its ScrollView shows, as SwiftUI's lazy
 stacks make their rows. The repeater estimates the sizes of the rows it has not made and keeps the
 scroll position anchored as they change; outside a ScrollView it makes every row.

 - A row's element is its template instance (RenderNode.templateRowNode, the template with the row's
   data) in a cell that aligns it across the stack by the stack's alignment: the repeater gives every
   element the stack's whole width (a LazyHStack's height), and the stack takes all the room it is
   offered across, as measured on macOS 27.
 - A row the repeater no longer shows is let go (its instance leaves the tree). Its data stays in the
   content rows (a row-bound Toggle writes its row), so a row made again shows the same; only
   transient state (keyboard focus, a text field's selection) goes, as SwiftUI lets go of a lazy row's
   views.
 - A row whose data changes is made again; rows added at the end are added, rows removed from the end
   removed: the same keeping as the eager template form (TemplateRows), by index.
 - The stack expands across its axis only and cannot be made smaller (LazyStacks.isLazy): the rows
   made at a moment do not decide its layout.
*/

import CWinUI

/// What gives a repeater its elements: a lazy stack's rows (LazyRows), a lazy grid's lines
/// (LazyGridLines).
@MainActor
protocol RepeaterSource: AnyObject {
    /// The element for item `index`, lent to the repeater; nil when it cannot be made.
    func make(_ index: Int) -> OpaquePointer?
    /// The repeater no longer shows `element`.
    func recycle(_ element: OpaquePointer)
}

/// A repeater (the shim's ItemsRepeater) whose elements come from `source`, held weakly.
@MainActor
func makeRepeater(vertical: Bool, source: any RepeaterSource, what: String) throws(WinUIError) -> WinUIObject {
    let box = RepeaterSourceBox()
    let context = Unmanaged.passRetained(box).toOpaque()
    guard let repeater = WinUIObject(adopting: actionUIWinUIRepeaterCreate(vertical, makeRepeaterElement, recycleRepeaterElement,
                                                                           context, releaseRepeaterSourceBox)) else {
        throw WinUIError.last("creating \(what)'s repeater")
    }
    box.source = source
    return repeater
}

/// What a lazy stack in its template form keeps: its repeater, the rows it shows and the rows made.
@MainActor
final class LazyRows: RepeaterSource {
    let axis: StackLayout.Axis
    private(set) var repeater: WinUIObject!
    private weak var node: RenderNode?
    /// The template, and the content rows the repeater's items stand for.
    private var template: (any ActionUIElementBase)?
    private(set) var rows: [[String]] = []
    /// Where a row's instance sits across the stack.
    private(set) var alignment = StackSolver.Alignment.center
    private var spacing = -1.0
    /// The rows made: each one's index, instance and cell.
    private(set) var made: [(index: Int, instance: RenderNode, cell: LazyRowCell)] = []

    init(node: RenderNode, axis: StackLayout.Axis) throws(WinUIError) {
        self.node = node
        self.axis = axis
        repeater = try makeRepeater(vertical: axis == .vertical, source: self, what: "a lazy stack")
    }

    /// Makes the repeater's items the content rows of `node`'s template, and its spacing and the
    /// rows' alignment the stack's.
    func update(template: (any ActionUIElementBase)?, rows newRows: [[String]], spacing: Double,
                alignment: StackSolver.Alignment) {
        self.template = template
        if spacing != self.spacing {
            if actionUIWinUIRepeaterSetSpacing(repeater.pointer, spacing) {
                self.spacing = spacing
            } else {
                ActionUIModel.shared.logger.log("LazyRows: \(WinUIError.last("setting the spacing"))", .error)
            }
        }
        if alignment != self.alignment {
            self.alignment = alignment
            for row in made {
                row.cell.panel.invalidateLayout()
            }
        }
        let old = rows
        // The rows first: the repeater may ask for an element as soon as its items change.
        rows = newRows
        for index in 0..<min(old.count, newRows.count) where old[index] != newRows[index] {
            if !actionUIWinUIRepeaterReplace(repeater.pointer, Int32(index)) {
                ActionUIModel.shared.logger.log("LazyRows: \(WinUIError.last("changing a row"))", .error)
            }
        }
        if newRows.count < old.count, !actionUIWinUIRepeaterTruncate(repeater.pointer, Int32(newRows.count)) {
            ActionUIModel.shared.logger.log("LazyRows: \(WinUIError.last("removing rows"))", .error)
        }
        for _ in old.count..<max(old.count, newRows.count) {
            if !actionUIWinUIRepeaterAppend(repeater.pointer) {
                ActionUIModel.shared.logger.log("LazyRows: \(WinUIError.last("adding a row"))", .error)
                // The rows the repeater has: the next update adds the others.
                let count = Int(actionUIWinUIRepeaterCount(repeater.pointer))
                rows = Array(newRows.prefix(max(count, 0)))
                break
            }
        }
    }

    /// The repeater asks for row `index`'s element: its instance, made and synced now (a layout pass
    /// is under way), in a cell. Nil when it cannot be made.
    func make(_ index: Int) -> OpaquePointer? {
        guard let node, node.isAttached, let template, rows.indices.contains(index) else { return nil }
        let instance = node.templateRowNode(template, row: rows[index], rowIndex: index)
        instance.sync()
        guard let box = instance.outerView else {
            node.releaseTemplateNode(instance)
            return nil
        }
        do {
            let cell = try LazyRowCell(content: box, instance: instance, rows: self)
            made.append((index, instance, cell))
            return cell.panel.object.pointer
        } catch {
            ActionUIModel.shared.logger.log("LazyRows: \(error)", .error)
            node.releaseTemplateNode(instance)
            return nil
        }
    }

    /// The repeater no longer shows `element`: its row's instance leaves the tree.
    func recycle(_ element: OpaquePointer) {
        guard let position = made.firstIndex(where: { actionUIWinUIObjectIsSame($0.cell.panel.object.pointer, element) }) else { return }
        let row = made.remove(at: position)
        node?.releaseTemplateNode(row.instance)
    }
}

/// A made row's cell: its instance's box, aligned across the stack.
@MainActor
final class LazyRowCell {
    let panel: LayoutPanel
    let content: WinUIObject
    private unowned let instance: RenderNode
    private unowned let rows: LazyRows
    private var measured = ActionUIWinUISize(width: 0, height: 0)

    init(content: WinUIObject, instance: RenderNode, rows: LazyRows) throws(WinUIError) {
        panel = try LayoutPanel()
        self.content = content
        self.instance = instance
        self.rows = rows
        try panel.append(content)
        panel.measure = { [unowned self] available in
            measured = self.content.measureRequested(available)
            return measured
        }
        panel.arrange = { [unowned self] finalSize in arrange(finalSize) }
    }

    /// The instance at its size along the stack and across it at its size (its whole room when it
    /// expands across), placed by the stack's alignment.
    private func arrange(_ finalSize: ActionUIWinUISize) {
        if rows.axis == .vertical {
            let width = instance.expansion.contains(.horizontal) ? max(finalSize.width, measured.width) : measured.width
            content.arrange(ActionUIWinUIRect(x: Self.offset(width, in: finalSize.width, rows.alignment), y: 0,
                                              width: width, height: max(finalSize.height, measured.height)))
        } else {
            let height = instance.expansion.contains(.vertical) ? max(finalSize.height, measured.height) : measured.height
            content.arrange(ActionUIWinUIRect(x: 0, y: Self.offset(height, in: finalSize.height, rows.alignment),
                                              width: max(finalSize.width, measured.width), height: height))
        }
    }

    private static func offset(_ length: Double, in room: Double, _ alignment: StackSolver.Alignment) -> Double {
        switch alignment {
        case .start: return 0
        case .center: return ((room - length) / 2).rounded(.down)
        case .end: return room - length
        }
    }
}

/// The repeater's callback context: a box with a weak reference to its source, so the repeater (which
/// holds the box) does not keep it alive.
@MainActor private final class RepeaterSourceBox {
    weak var source: (any RepeaterSource)?
}

private func repeaterSourceBox(_ context: UnsafeMutableRawPointer?) -> RepeaterSourceBox? {
    context.map { Unmanaged<RepeaterSourceBox>.fromOpaque($0).takeUnretainedValue() }
}

// The element's address crosses the main actor's closure as a number (a pointer is not Sendable).
private let makeRepeaterElement: ActionUIWinUIRepeaterMake = { context, index in
    let box = repeaterSourceBox(context)
    let address = MainActor.assumeIsolated {
        UInt(bitPattern: box?.source?.make(Int(index)))
    }
    return OpaquePointer(bitPattern: address)
}

private let recycleRepeaterElement: ActionUIWinUIRepeaterRecycle = { context, element in
    let box = repeaterSourceBox(context)
    let address = UInt(bitPattern: element)
    MainActor.assumeIsolated {
        guard let element = OpaquePointer(bitPattern: address) else { return }
        box?.source?.recycle(element)
    }
}

// Gives back the reference passRetained took, once the repeater's factory is gone.
private let releaseRepeaterSourceBox: ActionUIWinUICallback = { context in
    guard let context else { return }
    Unmanaged<RepeaterSourceBox>.fromOpaque(context).release()
}
