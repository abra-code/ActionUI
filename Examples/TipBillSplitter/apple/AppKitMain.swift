//  TipBillSplitter - ActionUI Example (macOS host, AppKit lifecycle)
//
//  DISTINCTIVE: this app's foundation is AppKit (NSApplication + AppDelegate +
//  NSWindow), NOT the SwiftUI App lifecycle. ActionUI still renders SwiftUI
//  views; we host the rendered tree via NSHostingController in an NSWindow. The
//  point is to prove ActionUI drops cleanly into a non-SwiftUI macOS shell.
//
//  The recompute logic lives in TipLogic.swift and is shared verbatim with the
//  UIKit (iOS) host.

import AppKit
import SwiftUI
import ActionUI
import ActionUISwiftAdapter

@main
struct TipBillSplitterMacApp {
    static func main() {
        // Bring up NSApplication explicitly (no @NSApplicationMain, no MainMenu.nib).
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.regular)
        let delegate = AppKitAppDelegate()
        NSApp.delegate = delegate
        _ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
    }
}

final class AppKitAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    // Strongly held: closing/releasing this window with the default
    // isReleasedWhenClosed == true SIGSEGVs because we also retain it here.
    var window: NSWindow!

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Unbundled/code-built hosts have no MainMenu.nib, so build a minimal
        // menu bar in code (App menu with Quit, plus a Window menu).
        installMenuBar(appName: "Tip & Bill Splitter")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // (windowUUID, viewID) addresses every element. Mint one per window.
        let windowUUID = UUID().uuidString

        // (2) Register the single recompute handler. Closure args are
        // (actionID, windowUUID, viewID, viewPartID, context). Callbacks arrive
        // on the main thread; assumeIsolated bridges to the main actor so we can
        // touch the value bridge synchronously.
        ActionUISwift.registerActionHandler(actionID: "tip.recompute") { _, win, _, _, _ in
            MainActor.assumeIsolated { TipBillSplitter.recompute(win) }
        }

        // (1) Load the bundled shared JSON and host it via NSHostingController.
        guard let url = Bundle.main.url(forResource: "TipBillSplitter", withExtension: "json") else {
            presentError("TipBillSplitter.json missing from the app bundle")
            return
        }
        let hosting = ActionUISwift.loadHostingController(from: url, windowUUID: windowUUID, isContentView: true)

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 520),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "Tip & Bill Splitter"
        window.isReleasedWhenClosed = false   // GOTCHA: we retain `window`; default true SIGSEGVs on close.
        window.contentViewController = hosting
        window.center()
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Seed the outputs from the JSON's initial input values.
        TipBillSplitter.recompute(windowUUID)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.terminate(nil)
    }

    private func presentError(_ message: String) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: Text(message).padding())
        window.center()
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // A minimal code-built menu bar: App menu (Quit) + a standard Window menu.
    private func installMenuBar(appName: String) {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About \(appName)", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide \(appName)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit \(appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu

        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenuItem.submenu = windowMenu

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }
}
