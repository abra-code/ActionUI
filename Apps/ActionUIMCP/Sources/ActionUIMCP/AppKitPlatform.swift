// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

// AppKitPlatform.swift - the windows on macOS: an NSWindow around a SwiftUI hosting view. Capture
// is in AppKitPlatform+Capture.swift, notices in AppKitPlatform+Notices.swift, file panels in
// AppKitPlatform+Panels.swift, window placement and Window menu names in AppKitPlatform+Placement.swift.

#if canImport(AppKit)
import AppKit
import SwiftUI
import UniformTypeIdentifiers
import ActionUISwiftAdapter
import ActionUIQuickLook
import ActionUIDiff
import ActionUICachedImage
import ActionUIRichText

@MainActor
final class AppKitPlatform: NSObject, NSWindowDelegate, WindowPlatform {
    typealias FileType = UTType

    nonisolated static let systemName = "macOS"
    nonisolated static let shownContent = "report, image, PDF, video, web page, diff, table, or chart"
    nonisolated static let noticeDescription = """
        Show a short notice in the top right corner of the user's screen, for example that a long \
        job finished. Returns {shown} at once. The notice does not take focus and disappears after \
        duration_s or when clicked; nothing comes back from it.
        """
    nonisolated static let verifierPlatform = "macos"
    nonisolated static let keepsWindows = true
    nonisolated static let removesClosedWindowModels = false

    struct Content {
        /// Owns the SwiftUI tree.
        let controller: NSViewController
        let fitting: NSSize
    }

    weak var host: WindowHost?
    var windows: [String: NSWindow] = [:]
    /// The hosting controllers own the SwiftUI trees; kept for the window's lifetime.
    private var controllers: [String: NSViewController] = [:]
    /// Notices on screen, oldest first (AppKitPlatform+Notices.swift).
    var notices: [Notice] = []

    static func registerAddOns() {
        ActionUIQuickLook.register()
        ActionUIDiff.register()
        ActionUICachedImage.register()
        ActionUIRichText.register()
    }

    static func prepareApplication(isKeeper: Bool) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.mainMenu = makeMainMenu(quitItem: isKeeper)
    }

    /// The ActionUI app icon from the server's resource bundle, loaded once; nil when the bundle is
    /// not next to the executable (the Dock then shows the system's icon for a program).
    static let dockIcon: NSImage? = {
        guard let resources = HostSupport.resourceFolder(ofBundle: "ActionUIMCP_ActionUIMCP") else { return nil }
        return NSImage(contentsOf: resources.appendingPathComponent("ActionUIMCP.icns"))
    }()

    /// Shows the process in the Dock with the ActionUI icon. A bare executable has no icon of its
    /// own, and one set before the process shows in the Dock does not carry over (measured on macOS
    /// 27: the Dock showed the generic program icon), so it is set again each time.
    static func showInDock() {
        NSApp.setActivationPolicy(.regular)
        if let icon = dockIcon {
            NSApp.applicationIconImage = icon
        }
    }

    static func runApplication() {
        NSApplication.shared.run()
    }

    static func terminateApplication() {
        NSApp.terminate(nil)
    }

    /// Edit and Window menus, so text fields get copy, paste, undo and select all, and Cmd-W closes a
    /// window. The Window menu is the application's windows menu, where AppKit lists the open
    /// windows, and the Services submenu its services menu. No Quit item in the server: quitting
    /// would end the client's server; closing windows is enough. The keeper serves no one and gets
    /// one.
    private static func makeMainMenu(quitItem: Bool) -> NSMenu {
        let mainMenu = NSMenu()
        @discardableResult
        func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenu {
            let menu = NSMenu(title: title)
            items.forEach(menu.addItem)
            let holder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            holder.submenu = menu
            mainMenu.addItem(holder)
            return menu
        }
        func item(_ title: String, _ action: Selector, _ key: String, _ modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
            let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: key)
            menuItem.keyEquivalentModifierMask = modifiers
            return menuItem
        }
        // The system fills the Services submenu, for example to send text selected in a window to
        // another application.
        let services = NSMenu(title: "Services")
        let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        servicesItem.submenu = services
        submenu("ActionUI", [servicesItem, .separator(), item("Hide", #selector(NSApplication.hide(_:)), "h")]
                            + (quitItem ? [.separator(), item("Quit", #selector(NSApplication.terminate(_:)), "q")] : []))
        NSApplication.shared.servicesMenu = services
        submenu("Edit", [
            item("Undo", Selector(("undo:")), "z"),
            item("Redo", Selector(("redo:")), "z", [.command, .shift]),
            .separator(),
            item("Cut", #selector(NSText.cut(_:)), "x"),
            item("Copy", #selector(NSText.copy(_:)), "c"),
            item("Paste", #selector(NSText.paste(_:)), "v"),
            item("Select All", #selector(NSText.selectAll(_:)), "a"),
        ])
        // AppKit adds a separator and the list of windows below these.
        NSApplication.shared.windowsMenu = submenu("Window", [
            item("Close", #selector(NSWindow.performClose(_:)), "w"),
            item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
            item("Zoom", #selector(NSWindow.performZoom(_:)), ""),
            .separator(),
            item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:)), ""),
        ])
        return mainMenu
    }

    var hasGraphicalSession: Bool {
        CGSessionCopyCurrentDictionary() != nil
    }

    /// Builds the view and measures it once, so that view construction runs inside the log capture.
    func loadContent(file: URL, windowID: String) -> Content {
        let controller = ActionUISwift.loadHostingController(from: file, windowUUID: windowID, isContentView: true)
        return Content(controller: controller, fitting: controller.view.fittingSize)
    }

    /// Without `activate` the window is only ordered front, so it does not take keyboard focus from
    /// the user.
    func present(_ content: Content, windowID: String, title: String, subtitle: String, sizing: WindowHost.Sizing, activate: Bool) {
        var style: NSWindow.StyleMask = [.titled, .closable]
        switch sizing {
        case .fitting(let resizable) where resizable: style.formUnion([.miniaturizable, .resizable])
        case .fixed: style.formUnion([.miniaturizable, .resizable])
        default: break
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
                              styleMask: style, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = content.controller.view
        // After the content view: installing the SwiftUI hosting view resets the window's title
        // and subtitle, and the subtitle carries the provenance line.
        window.title = title
        window.subtitle = subtitle
        switch sizing {
        case .fixed(let size):
            window.setContentSize(NSSize(width: size.width, height: size.height))
        case .fitting:
            window.setContentSize(Self.clampedToScreen(content.fitting))
        }
        window.delegate = self
        Self.place(window)

        windows[windowID] = window
        controllers[windowID] = content.controller
        if activate {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        } else {
            window.orderFrontRegardless()
        }
        Self.listInWindowsMenu(window)
        #if DEBUG
        writePlacementReport()
        #endif
    }

    #if DEBUG
    /// ACTIONUI_MCP_TEST_PLACEMENT_REPORT=<path>: for the live test, after each window opens, write
    /// every window's title and frame and the names the Window menu lists.
    private func writePlacementReport() {
        guard let path = ProcessInfo.processInfo.environment["ACTIONUI_MCP_TEST_PLACEMENT_REPORT"] else { return }
        let shown: [[String: Any]] = windows.values.map { window in
            let frame = window.frame
            return ["title": window.title, "frame": [frame.origin.x, frame.origin.y, frame.size.width, frame.size.height]]
        }
        let listed = NSApp.windowsMenu?.items.filter { $0.target is NSWindow }.map(\.title) ?? []
        let report: [String: Any] = ["windows": shown, "menu": listed]
        guard let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]) else { return }
        try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }
    #endif

    static func clampedToScreen(_ size: NSSize) -> NSSize {
        let screen = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1440, height: 900)
        let width = size.width > 0 ? size.width : 480
        let height = size.height > 0 ? size.height : 320
        return NSSize(width: min(max(width, 240), screen.width * 0.9),
                      height: min(max(height, 80), screen.height * 0.9))
    }

    func close(_ windowID: String) {
        windows[windowID]?.close()  // windowWillClose does the bookkeeping.
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let windowID = windows.first(where: { $0.value === window })?.key else { return }
        windows[windowID] = nil
        controllers[windowID] = nil
        host?.windowClosed(windowID)
    }

    /// A Dock icon and menu bar only while there is a window or panel to click.
    func setShowsInterface(_ shows: Bool) {
        let wanted: NSApplication.ActivationPolicy = shows ? .regular : .accessory
        guard NSApp.activationPolicy() != wanted else { return }
        if shows {
            Self.showInDock()
        } else {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    func keptWindowStates(_ ids: [String]) -> [KeptWindowState] {
        let order = NSApp.orderedWindows  // front to back
        return ids.compactMap { id in windows[id].map { (id: id, window: $0) } }
            .sorted { (order.firstIndex(of: $0.window) ?? Int.max) > (order.firstIndex(of: $1.window) ?? Int.max) }
            .map { entry in
                let frame = entry.window.frame
                return KeptWindowState(id: entry.id, title: entry.window.title, subtitle: entry.window.subtitle,
                                       frame: [frame.origin.x, frame.origin.y, frame.size.width, frame.size.height],
                                       styleMask: entry.window.styleMask.rawValue)
            }
    }
}
#endif
