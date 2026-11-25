// Sources/Layout/WindowCommandBar.swift
/*
 A window's command bar on WinUI: the toolbars of the views not in a navigation container, shown in a
 row at the top of the window's content, as Windows apps put their commands below the title bar
 (File Explorer, Photos), and a row at its bottom for bottomBar items. SwiftUI on macOS puts them in
 the window's toolbar; WinUI's title bar holds the window's own title and controls.

 - The top row: leading items from the leading edge, principal items centered (in the room between the
   leading and trailing items when the row's middle would overlap them), trailing items to the
   trailing edge, and a "see more" button (three dots) at the very end when there are overflow items
   (secondaryAction), which opens a flyout holding them, as a command bar shows its secondary
   commands. Items are 8 apart, the row 8 in from the sides and 6 from its top and bottom.
 - The bottom row: its items centered, with the same insets.
 - A row with no items takes no room. The content (the window's root element) fills what the rows
   leave, as it fills the window without them.
 - Several views' toolbars share the rows, in the order their toolbars registered (the order of the ActionUI JSON).

 The window has a command bar only when its ActionUI JSON declares a toolbar outside a navigation
 container (WinUIWindow), so a UI without one lays out as before.
*/

import CWinUI

/// Where a toolbar item goes in a bar.
enum ToolbarSlot {
    case leading, principal, trailing, overflow, bottom
}

/// What shows toolbars' items: a window's command bar, or a NavigationStack screen's header.
@MainActor
protocol ToolbarBar: AnyObject {
    /// Shows `items` as `owner`'s (a toolbar's), replacing what it showed.
    func set(owner: ObjectIdentifier, items: [(slot: ToolbarSlot, view: WinUIObject)])
    /// `owner`'s items leave the bar.
    func remove(owner: ObjectIdentifier)
}

/// A window's command rows around its content.
@MainActor
final class WindowCommandBar: ToolbarBar {
    let panel: LayoutPanel
    private let content: WinUIObject
    private let top: CommandRow
    private let bottom: CommandRow
    /// The overflow items' panel, the flyout's content, and the button that opens it.
    private let overflow: StackLayout
    private var overflowButton: WinUIObject?
    /// Each toolbar's items, in the order the toolbars registered.
    private var owners: [(owner: ObjectIdentifier, items: [(slot: ToolbarSlot, view: WinUIObject)])] = []
    private var measuredTop = ActionUIWinUISize(width: 0, height: 0)
    private var measuredBottom = ActionUIWinUISize(width: 0, height: 0)

    private final class WeakBar {
        weak var bar: WindowCommandBar?
        init(_ bar: WindowCommandBar) { self.bar = bar }
    }

    /// Each window's bar, by window id (WinUIWindow registers it).
    private static var bars: [String: WeakBar] = [:]

    /// The command bar of window `windowUUID`, nil when it has none.
    static func of(windowUUID: String) -> WindowCommandBar? {
        bars[windowUUID]?.bar
    }

    static func register(_ bar: WindowCommandBar?, windowUUID: String) {
        bars[windowUUID] = bar.map(WeakBar.init)
    }

    init(content: WinUIObject) throws(WinUIError) {
        panel = try LayoutPanel()
        self.content = content
        top = try CommandRow()
        bottom = try CommandRow()
        overflow = try StackLayout(axis: .vertical)
        overflow.alignment = .start
        try panel.append(content)
        panel.measure = { [unowned self] available in measure(available) }
        panel.arrange = { [unowned self] finalSize in arrange(finalSize) }
    }

    /// Shows `items` as `owner`'s (a toolbar's), replacing what it showed.
    func set(owner: ObjectIdentifier, items: [(slot: ToolbarSlot, view: WinUIObject)]) {
        if let index = owners.firstIndex(where: { $0.owner == owner }) {
            owners[index].items = items
        } else {
            owners.append((owner, items))
        }
        show()
    }

    /// `owner`'s items leave the bar.
    func remove(owner: ObjectIdentifier) {
        owners.removeAll { $0.owner == owner }
        show()
    }

    private func show() {
        let all = owners.flatMap(\.items)
        let views = { (slot: ToolbarSlot) in all.filter { $0.slot == slot }.map(\.view) }
        let overflowViews = views(.overflow)
        if !overflowViews.isEmpty, overflowButton == nil {
            overflowButton = WinUIObject(adopting: actionUIWinUIOverflowButtonCreate(overflow.panel.object.pointer))
            if overflowButton == nil {
                ActionUIModel.shared.logger.log("WindowCommandBar: \(WinUIError.last("making the overflow button"))", .error)
            }
        }
        let leading = views(.leading)
        let principal = views(.principal)
        let trailing = views(.trailing) + (overflowViews.isEmpty ? [] : overflowButton.map { [$0] } ?? [])
        let bottomViews = views(.bottom)
        // An item whose placement changed moves to another panel, and WinUI refuses an element that
        // is still another panel's child: the panels whose items change are emptied before any is
        // filled.
        if !overflow.items.map(\.view).elementsEqual(overflowViews, by: ===) {
            overflow.setItems([])
        }
        if !top.views.elementsEqual(leading + principal + trailing, by: ===) {
            top.setItems(leading: [], principal: [], trailing: [])
        }
        if !bottom.views.elementsEqual(bottomViews, by: ===) {
            bottom.setItems(leading: [], principal: [], trailing: [])
        }
        overflow.setItems(overflowViews.map { StackLayout.Item(view: $0, spacerMinimum: nil) })
        top.setItems(leading: leading, principal: principal, trailing: trailing)
        bottom.setItems(leading: [], principal: bottomViews, trailing: [])
        do {
            try place(top.panel.object, shown: !top.isEmpty, at: 0)
            try place(bottom.panel.object, shown: !bottom.isEmpty, at: nil)
        } catch {
            ActionUIModel.shared.logger.log("WindowCommandBar: \(error)", .error)
        }
        panel.invalidateLayout()
    }

    /// Puts `row` in the panel (at `index`, or at the end) or takes it out.
    private func place(_ row: WinUIObject, shown: Bool, at index: Int?) throws(WinUIError) {
        let current = panel.children.firstIndex { $0 === row }
        if shown, current == nil {
            if let index {
                try panel.insert(row, at: index)
            } else {
                try panel.append(row)
            }
        } else if !shown, let current {
            try panel.remove(at: current)
        }
    }

    private func shows(_ row: CommandRow) -> Bool {
        panel.children.contains { $0 === row.panel.object }
    }

    private func measure(_ available: ActionUIWinUISize) -> ActionUIWinUISize {
        let rowOffer = ActionUIWinUISize(width: available.width, height: .infinity)
        measuredTop = shows(top) ? top.panel.object.measureRequested(rowOffer) : ActionUIWinUISize(width: 0, height: 0)
        measuredBottom = shows(bottom) ? bottom.panel.object.measureRequested(rowOffer) : ActionUIWinUISize(width: 0, height: 0)
        let rows = measuredTop.height + measuredBottom.height
        let room = ActionUIWinUISize(width: available.width, height: available.height.isFinite ? max(available.height - rows, 0) : .infinity)
        let asked = content.measureRequested(room)
        return ActionUIWinUISize(width: max(asked.width, measuredTop.width, measuredBottom.width), height: asked.height + rows)
    }

    private func arrange(_ finalSize: ActionUIWinUISize) {
        if shows(top) {
            top.panel.object.arrange(ActionUIWinUIRect(x: 0, y: 0, width: finalSize.width, height: measuredTop.height))
        }
        let middle = max(finalSize.height - measuredTop.height - measuredBottom.height, 0)
        content.arrange(ActionUIWinUIRect(x: 0, y: measuredTop.height, width: finalSize.width, height: middle))
        if shows(bottom) {
            bottom.panel.object.arrange(ActionUIWinUIRect(x: 0, y: measuredTop.height + middle, width: finalSize.width,
                                                          height: measuredBottom.height))
        }
    }
}

/// One row of a command bar: leading, centered (principal) and trailing items.
@MainActor
final class CommandRow {
    let panel: LayoutPanel
    private var leading: [WinUIObject] = []
    private var principal: [WinUIObject] = []
    private var trailing: [WinUIObject] = []
    private var sizes: [ObjectIdentifier: ActionUIWinUISize] = [:]

    static let spacing = 8.0
    static let sideInset = 8.0
    static let verticalInset = 6.0

    init() throws(WinUIError) {
        panel = try LayoutPanel()
        panel.measure = { [unowned self] available in measure(available) }
        panel.arrange = { [unowned self] finalSize in arrange(finalSize) }
    }

    var isEmpty: Bool { leading.isEmpty && principal.isEmpty && trailing.isEmpty }

    /// The items, in the panel's order.
    var views: [WinUIObject] { leading + principal + trailing }

    func setItems(leading: [WinUIObject], principal: [WinUIObject], trailing: [WinUIObject]) {
        let wanted = leading + principal + trailing
        let current = self.leading + self.principal + self.trailing
        self.leading = leading
        self.principal = principal
        self.trailing = trailing
        guard !wanted.elementsEqual(current, by: ===) else { return }
        do {
            while !panel.children.isEmpty {
                try panel.remove(at: panel.children.count - 1)
            }
            // In reading order, so keyboard focus moves through them as they are read.
            for view in wanted {
                try panel.append(view)
            }
        } catch {
            ActionUIModel.shared.logger.log("CommandRow: \(error)", .error)
        }
        panel.invalidateLayout()
    }

    private func width(_ views: [WinUIObject]) -> Double {
        views.reduce(0) { $0 + (sizes[ObjectIdentifier($1)]?.width ?? 0) } + Self.spacing * Double(max(views.count - 1, 0))
    }

    private func measure(_ available: ActionUIWinUISize) -> ActionUIWinUISize {
        sizes = [:]
        var height = 0.0
        for view in leading + principal + trailing {
            let size = view.measureRequested(ActionUIWinUISize(width: .infinity, height: .infinity))
            sizes[ObjectIdentifier(view)] = size
            height = max(height, size.height)
        }
        guard !isEmpty else { return ActionUIWinUISize(width: 0, height: 0) }
        let groups = [leading, principal, trailing].filter { !$0.isEmpty }
        let width = groups.reduce(0) { $0 + self.width($1) } + Self.spacing * Double(max(groups.count - 1, 0)) + 2 * Self.sideInset
        return ActionUIWinUISize(width: width, height: height + 2 * Self.verticalInset)
    }

    private func arrange(_ finalSize: ActionUIWinUISize) {
        func place(_ views: [WinUIObject], from start: Double) {
            var x = start
            for view in views {
                let size = sizes[ObjectIdentifier(view)] ?? ActionUIWinUISize(width: 0, height: 0)
                view.arrange(ActionUIWinUIRect(x: x.rounded(.down), y: ((finalSize.height - size.height) / 2).rounded(.down),
                                               width: size.width, height: size.height))
                x += size.width + Self.spacing
            }
        }
        place(leading, from: Self.sideInset)
        let trailingStart = finalSize.width - Self.sideInset - width(trailing)
        place(trailing, from: trailingStart)
        // Centered in the row when that clears the leading and trailing items, else centered in the room
        // between them, else right after the leading ones (it overflows toward the trailing edge).
        let principalWidth = width(principal)
        let lower = Self.sideInset + width(leading) + (leading.isEmpty ? 0 : Self.spacing)
        let upper = trailingStart - (trailing.isEmpty ? 0 : Self.spacing)
        let centered = (finalSize.width - principalWidth) / 2
        let start: Double
        if centered >= lower && centered + principalWidth <= upper {
            start = centered
        } else if upper - lower >= principalWidth {
            start = lower + (upper - lower - principalWidth) / 2
        } else {
            start = lower
        }
        place(principal, from: start)
    }
}
