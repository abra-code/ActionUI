// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

// AppKitPlatform+Placement.swift - where a new window opens on macOS, and its name in the Window
// menu.

#if canImport(AppKit)
import AppKit

extension AppKitPlatform {
    /// The step between cascaded windows, right and down, in points: about the height of a title
    /// bar, as Mac applications have long done it.
    nonisolated static let cascadeStep: CGFloat = 22
    /// Window menu names longer than this many characters lose their middle.
    nonisolated static let maxMenuTitleLength = 60

    /// The first window opens centered. Each later one opens a step right of and below the
    /// frontmost window of any actionui-mcp process, this server's or a keeper's, skipping places
    /// where a window already has its top left corner, so a window of the same size never hides
    /// another one completely. Call before the window is on screen.
    static func place(_ window: NSWindow) {
        window.center()
        // A window ordered front reaches the window server's list only when the transaction is
        // committed, at the end of the run loop pass: without this, shows that arrive together
        // (parallel tool calls) all miss each other and open on top of one another (measured).
        CATransaction.flush()
        let others = siblingWindowFrames()
        guard let anchor = others.first,
              let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchor) }) ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = window.frame.size
        var topLeft = NSPoint(x: anchor.minX, y: anchor.maxY)
        // Bounded: on a screen full of windows the last place tried is taken.
        for _ in 0..<64 {
            topLeft = nextCascadePoint(after: topLeft, size: size, in: visible)
            let taken = others.contains { abs($0.minX - topLeft.x) < cascadeStep / 2 && abs($0.maxY - topLeft.y) < cascadeStep / 2 }
            if !taken { break }
        }
        window.setFrameTopLeftPoint(topLeft)
    }

    /// One step right and down from `point`, a window's top left corner. A window that would reach
    /// below the visible frame goes back up to its top, one that would reach past its right edge
    /// goes back to its left edge, as does one after a window the user dragged past that edge, so
    /// the cascade runs in diagonal bands across the screen.
    nonisolated static func nextCascadePoint(after point: NSPoint, size: NSSize, in visible: NSRect) -> NSPoint {
        var next = NSPoint(x: point.x + cascadeStep, y: point.y - cascadeStep)
        if next.y - size.height < visible.minY {
            next.y = visible.maxY
        }
        if next.x + size.width > visible.maxX || next.x < visible.minX {
            next.x = visible.minX
        }
        return next
    }

    /// The frames of the windows on screen of every actionui-mcp process, front to back, in AppKit
    /// screen coordinates, leaving out the window that renders a document off every screen. Kept
    /// windows live on in keeper processes of the same name, one per ended session. The window server tells any process where other processes' windows are; only their
    /// names need the screen recording permission, and they are not read.
    static func siblingWindowFrames() -> [NSRect] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
              let primaryHeight = NSScreen.screens.first?.frame.height else { return [] }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let ownName = ProcessInfo.processInfo.processName
        return list.compactMap { info in
            // Layer 0 holds normal windows; notices float above it.
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? Int32,
                  pid == ownPID || (info[kCGWindowOwnerName as String] as? String) == ownName,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds) else { return nil }
            // The window server measures from the top of the primary screen, AppKit from its bottom.
            // Its bounds follow the opening animation, which scales a window up from about 98% over
            // half a second (measured on macOS 27), so this process's own windows use their frames.
            let own = pid == ownPID ? (info[kCGWindowNumber as String] as? Int).flatMap { NSApp.window(withWindowNumber: $0) } : nil
            let frame = own?.frame ?? NSRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
            return NSScreen.screens.contains { $0.frame.intersects(frame) } ? frame : nil
        }
    }

    /// Lists the window in the Window menu by its title alone, shortened for the menu. AppKit lists
    /// "<title> (<subtitle>)": the subtitle is the provenance line, the same for every window an
    /// agent opens, and agents give long titles ("<repo>: <commit note title>"), so the menu could
    /// grow as wide as the screen. The title bar keeps both in full. Call once the window is on
    /// screen, which is when AppKit adds it to the menu.
    static func listInWindowsMenu(_ window: NSWindow) {
        guard !window.title.isEmpty else { return }
        NSApp.changeWindowsItem(window, title: menuTitle(window.title), filename: false)
    }

    /// `title` with its middle replaced by an ellipsis when longer than maxMenuTitleLength
    /// characters, keeping the start, which says what the window is, and the end, which tells
    /// windows of the same kind apart.
    nonisolated static func menuTitle(_ title: String) -> String {
        guard title.count > maxMenuTitleLength else { return title }
        let kept = maxMenuTitleLength - 1
        let head = title.prefix((kept + 1) / 2).trimmingCharacters(in: .whitespaces)
        let tail = title.suffix(kept / 2).trimmingCharacters(in: .whitespaces)
        return head + "\u{2026}" + tail
    }
}
#endif
