// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

//
//  ActionUIViewer.swift
//  ActionUIViewer
//
//  A command-line tool to view ActionUI JSON files in a window.
//

import SwiftUI
import AppKit
import ActionUI
import ActionUISwiftAdapter
import CoreServices
import UniformTypeIdentifiers
import CoreGraphics
import ScreenCaptureKit

// Optional ActionUI add-ons. This viewer is a separate package that links core ActionUI AND the
// add-ons, so it can preview documents that use add-on element types. Each add-on's register() must
// be called once at launch (see handleApplicationLaunch). Add an import + register() line per add-on.
import ActionUIQuickLook
import ActionUIChat
import ActionUIDiff
import ActionUICachedImage
import ActionUIRichText

final class CustomLogger: ActionUI.ActionUILogger {
    func log(_ message: String, _ level: ActionUI.LoggerLevel) {
        print("[ActionUI][\(level)] \(message)")
    }
}

struct ErrorView: View {
    let message: String

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text(message)
                .font(.headline)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Screenshot capture

/// How `--screenshot` grabs the window image. `legacy` and `screenCaptureKit` read the
/// window-server composite; `offscreen` draws the window in-process and never asks the window
/// server, so it also works while the screen is locked or the window is kept off screen.
enum ScreenshotMethod {
    /// CGWindowListCreateImage. Deprecated in macOS 14.0, but it captures this app's own window
    /// WITHOUT Screen Recording permission, so it works out of the box - convenient for automated
    /// / AI-agent screenshots. This is the default. Falls back to `offscreen` when the screen is
    /// locked or the window server returns no image.
    case legacy
    /// ScreenCaptureKit (SCScreenshotManager). The supported, non-deprecated API and the long-term
    /// path, but it requires Screen Recording permission (TCC) even for the app's own window.
    /// Falls back to `offscreen` the same way `legacy` does.
    case screenCaptureKit
    /// NSView.cacheDisplay(in:to:) on the window's frame view (title bar + content). AppKit and
    /// CoreAnimation draw the view tree into a bitmap in-process, so no Screen Recording permission,
    /// no dependency on the compositor, and it works with the screen locked. Verified against the
    /// window-server capture on the sample set: pixel-for-pixel the same layout, including AppKit-
    /// backed controls, List/Table, TextEditor, DatePicker and WKWebView content. Known gaps: the
    /// window shadow is not part of the image, and the selected segment of a tab-style segmented
    /// control (TabView tabs) draws as a solid block. Rejected alternatives, measured on the same
    /// samples: SwiftUI ImageRenderer draws every AppKit-backed control (Toggle, Slider, Picker,
    /// TextField, List...) as a placeholder, and CALayer.render(in:) drops most text and controls.
    case offscreen
}

// CGWindowListCreateImage is deprecated since macOS 14.0. We keep it as the no-permission option
// while keeping the project warning-free. A deprecation warning is suppressed inside a declaration
// that is itself @available(deprecated:), but marking the call site that way only pushes the same
// warning onto *its* caller, and so on up the chain. To confine the suppression to one spot, the
// deprecated call lives in a witness method behind a non-deprecated protocol requirement: callers
// go through the requirement (no warning) and only the witness body touches the deprecated symbol.
private protocol LegacyWindowCapturer {
    func captureImage(of windowID: CGWindowID) -> CGImage?
}

private struct CGWindowListCapturer: LegacyWindowCapturer {
    @available(macOS, deprecated: 14.0)
    func captureImage(of windowID: CGWindowID) -> CGImage? {
        CGWindowListCreateImage(CGRect.zero, .optionIncludingWindow, windowID, [])
    }
}

/// A window the user never sees (`--hide-window`). It is ordered front at a far off-screen origin,
/// so it is a real key window whose controls draw in the active appearance (accent-colored
/// toggles, sliders, checkboxes), yet it appears on no display. A window that is never ordered
/// front cannot become key, and its controls come out gray, so this is the only way to get the
/// active look without showing anything.
final class OffscreenCaptureWindow: NSWindow {
    /// AppKit drags titled windows back onto a screen when they are ordered front; keep the
    /// off-screen origin instead.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

func printUsage() {
    print("""
    ActionUIViewer - render an ActionUI JSON layout in a window, optionally capturing a screenshot.

    Usage:
      ActionUIViewer <path/to/input.json | https://url.to/input.json> [options]

    Options:
      --screenshot <output.png>     Capture the rendered window to a PNG, then exit.
      --method <legacy|sck|offscreen>
                                    Screenshot capture method (default: legacy).
                                      legacy     CGWindowListCreateImage; captures this app's own
                                                 window without Screen Recording permission, so
                                                 it works out of the box.
                                      sck        ScreenCaptureKit; the non-deprecated API, but it
                                                 requires Screen Recording permission.
                                      offscreen  Draws the window in-process (NSView.cacheDisplay)
                                                 instead of reading the window server. Works with
                                                 the screen locked; no window shadow in the image.
                                    legacy and sck fall back to offscreen automatically when the
                                    screen is locked or the window server returns no image.
      --hide-window                 Keep the window off every screen (nothing flashes on the
                                      desktop). Implies --method offscreen.
      --screenshot-delay <seconds>  Seconds to wait for the window to render before capturing
                                      (default: 1.5). Increase for WebView / VideoPlayer content,
                                      which needs longer to load (e.g. 5).
      -h, --help                    Show this help and exit.

    Without --screenshot the window stays open until it is closed.
    """)
}

class ActionUIViewerAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow!
    var screenshotPath: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            await handleApplicationLaunch()
        }
    }
    
    @MainActor
    func handleApplicationLaunch() async {
        // Register optional add-on element types before any document is loaded, so a JSON file that
        // uses an add-on element (e.g. "QuickLook") renders instead of erroring as an unknown type.
        // Built-in element types self-register inside core on first registry access.
        ActionUIQuickLook.register()
        ActionUIChat.register()
        ActionUIDiff.register()
        ActionUICachedImage.register()
        ActionUIRichText.register()
        // The viewer is a pure viewer: it renders documents but never injects a runtime transport. A
        // Chat element takes its protocol/transport only from a host-injected states["config"], so in
        // the viewer (which injects nothing) a Chat stays INERT - composer disabled, no transport. A
        // real app supplies the transport itself at runtime via setElementState("config", ...) after
        // the view is built.

        var jsonFilePath: String?
        var screenshotPath: String?
        var screenshotMethod: ScreenshotMethod = .legacy
        var methodWasGiven = false
        var screenshotDelay: Double = 1.5
        var hideWindow = false

        let args = CommandLine.arguments
        var i = 1
        while i < args.count {
            switch args[i] {
            case "-h", "--help":
                printUsage()
                NSApp.terminate(nil)
                return
            case "--screenshot":
                i += 1
                if i < args.count {
                    screenshotPath = args[i]
                }
            case "--method":
                i += 1
                if i < args.count {
                    methodWasGiven = true
                    switch args[i].lowercased() {
                    case "legacy", "cg":
                        screenshotMethod = .legacy
                    case "sck", "screencapturekit":
                        screenshotMethod = .screenCaptureKit
                    case "offscreen", "cachedisplay":
                        screenshotMethod = .offscreen
                    default:
                        print("Error: Unknown --method '\(args[i])' (use 'legacy', 'sck' or 'offscreen')")
                        NSApp.terminate(nil)
                        return
                    }
                }
            case "--hide-window":
                hideWindow = true
            case "--screenshot-delay":
                i += 1
                if i < args.count {
                    guard let seconds = Double(args[i]), seconds >= 0 else {
                        print("Error: Invalid --screenshot-delay '\(args[i])' (expected a non-negative number of seconds)")
                        NSApp.terminate(nil)
                        return
                    }
                    screenshotDelay = seconds
                }
            default:
                if jsonFilePath == nil {
                    jsonFilePath = args[i]
                }
            }
            i += 1
        }
        if hideWindow && !methodWasGiven {
            // --hide-window can only be captured in-process; only an explicit conflicting
            // --method is worth a note (see takeScreenshot).
            screenshotMethod = .offscreen
        }

        guard let pathOrUrl = jsonFilePath else {
            printUsage()
            NSApp.terminate(nil)
            return
        }
        
        var url: URL
        var displayTitle: String
        
        if pathOrUrl.hasPrefix("http://") || pathOrUrl.hasPrefix("https://") {
            guard let parsedUrl = URL(string: pathOrUrl) else {
                print("Error: Invalid URL: \(pathOrUrl)")
                NSApp.terminate(nil)
                return
            }
            url = parsedUrl
            displayTitle = parsedUrl.lastPathComponent.isEmpty ? parsedUrl.host ?? parsedUrl.absoluteString : parsedUrl.lastPathComponent
            
            print("Fetching remote JSON...")
            
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    print("Error: Failed to fetch remote JSON")
                    NSApp.terminate(nil)
                    return
                }
                
                let tempDir = FileManager.default.temporaryDirectory
                let tempFile = tempDir.appendingPathComponent("remote_\(UUID().uuidString).json")
                try data.write(to: tempFile)
                url = tempFile
                print("Saved remote JSON to temp file: \(tempFile.path)")
            } catch {
                print("Error fetching remote JSON: \(error)")
                NSApp.terminate(nil)
                return
            }
        } else {
            url = URL(fileURLWithPath: pathOrUrl)
            displayTitle = url.lastPathComponent
            
            guard FileManager.default.fileExists(atPath: pathOrUrl) else {
                print("Error: File not found at path: \(pathOrUrl)")
                window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
                                styleMask: [.titled, .closable], backing: .buffered, defer: false)
                window.contentView = NSHostingView(rootView: ErrorView(message: "File not found:\n\(pathOrUrl)"))
                window.delegate = self
                window.center()
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                return
            }
        }
        
        self.screenshotPath = screenshotPath
        
        let windowUUID = UUID().uuidString
        let logger = CustomLogger()
        ActionUISwift.setLogger(logger)
        ActionUISwift.setDefaultActionHandler({ actionID, windowUUID, viewID, viewPartID, context in
            print("Action: actionID=\(actionID), windowUUID=\(windowUUID), viewID=\(viewID), viewPartID=\(viewPartID), context=\(String(describing: context))")
        })
        
        let windowClass: NSWindow.Type = hideWindow ? OffscreenCaptureWindow.self : NSWindow.self
        // .fullSizeContentView is required, not cosmetic. On macOS 27 a root NavigationSplitView
        // has to reach the top of the window, or AppKit paints its per-column titlebar bands over
        // the detail column's first ~52 points (see View.windowRootSafeArea in ActionUI). Any
        // other root is still inset below the titlebar by SwiftUI, so its layout does not change.
        let layoutSize = NSSize(width: 800, height: 600)
        window = windowClass.init(contentRect: NSRect(origin: NSPoint(x: 100, y: 100), size: layoutSize),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
        window.title = "ActionUI Viewer - \(displayTitle)"
        window.delegate = self
        
        let hostingController = ActionUISwift.loadHostingController(from: url, windowUUID: windowUUID, isContentView: true)
        window.contentView = hostingController.view
        // layoutSize is the area the document lays out in. The content view spans the titlebar,
        // so add the titlebar's height; the layout pass first, so that a SwiftUI toolbar, which
        // makes the titlebar taller, is in place before measuring.
        window.layoutIfNeeded()
        let titlebarHeight = max(0, window.frame.height - window.contentLayoutRect.height)
        window.setContentSize(NSSize(width: layoutSize.width, height: layoutSize.height + titlebarHeight))
        window.center()
        if hideWindow {
            // Order the window front far outside every screen (see OffscreenCaptureWindow): it
            // becomes a real key window, so controls draw in the active appearance, yet nothing
            // shows on the desktop. Activation is asynchronous; takeScreenshot re-asserts key
            // status right before capturing.
            window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
            if screenshotPath == nil {
                // Without --screenshot nothing is ever drawn on a display and there is no window to
                // close, so the run would otherwise sit there with no clue about how to end it.
                print("Note: --hide-window without --screenshot displays nothing and does not exit on its own; press Ctrl-C to quit.")
                // This run never terminates, so nothing would flush a redirected stdout.
                fflush(stdout)
            }
        }
        window.makeKeyAndOrderFront(nil)
        // Also with --hide-window: the app must be active for its key window to draw controls in
        // the active appearance (measured: without activate the hidden capture has gray toggles).
        // The cost is a brief focus switch away from the user's foreground app for the length of
        // the run; focus returns when the viewer terminates after the capture.
        NSApp.activate(ignoringOtherApps: true)

        if let screenshotPath = screenshotPath {
            // Give the window time to finish rendering before capturing. Awaiting Task.sleep here
            // suspends this task so the main run loop keeps drawing the window in the meantime.
            // WebView / VideoPlayer content needs longer to load, hence the configurable delay.
            try? await Task.sleep(for: .seconds(screenshotDelay))
            await takeScreenshot(saveTo: screenshotPath, method: screenshotMethod)
        }
    }

    @MainActor
    func takeScreenshot(saveTo path: String, method requestedMethod: ScreenshotMethod) async {
        // Always terminate after the attempt so an automated `--screenshot` run never hangs.
        defer { NSApp.terminate(nil) }

        guard let window = window, window.windowNumber > 0 else {
            print("Error: No window to capture")
            return
        }

        var method = requestedMethod
        if window is OffscreenCaptureWindow {
            // Off-screen windows are not in the window server's on-screen list, so only the
            // in-process capture can see them.
            if method != .offscreen {
                print("Note: --hide-window implies --method offscreen")
                method = .offscreen
            }
        } else if method != .offscreen && isScreenLocked() {
            // The window server composites nothing for a locked session: CGWindowListCreateImage
            // returns a fully transparent image and ScreenCaptureKit fails to start its stream.
            // Draw in-process instead.
            print("Note: the screen is locked; capturing offscreen (in-process) instead")
            method = .offscreen
        }

        var captured: CGImage?
        switch method {
        case .legacy:
            captured = captureLegacy(window: window)
        case .screenCaptureKit:
            captured = await captureWithScreenCaptureKit(window: window)
        case .offscreen:
            captured = captureOffscreen(window: window)
        }
        if method != .offscreen, captured == nil || isFullyTransparent(captured!) {
            print("Note: window-server capture returned no image; retrying offscreen (in-process)")
            captured = captureOffscreen(window: window)
        }
        guard let cgImage = captured else {
            print("Error: Failed to capture the window")
            return
        }
        savePNG(cgImage, to: path)
    }

    /// Whether the login session's screen is locked (login window up), as reported by the window
    /// server. While locked, CGWindowListCreateImage and ScreenCaptureKit cannot capture the window.
    private func isScreenLocked() -> Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (session["CGSSessionScreenIsLocked"] as? Bool) ?? false
    }

    /// CGWindowListCreateImage reports success but hands back a fully transparent image when the
    /// window server has nothing composited for the window (locked screen, display asleep).
    /// Scaling the whole image into one premultiplied pixel leaves alpha 0 exactly in that case.
    private func isFullyTransparent(_ image: CGImage) -> Bool {
        guard image.alphaInfo != .none, image.alphaInfo != .noneSkipFirst, image.alphaInfo != .noneSkipLast else {
            return false
        }
        var pixel: [UInt8] = [0, 0, 0, 0]
        // The context writes into this buffer during draw(), i.e. after CGContext(data:) returns.
        // An inout `&pixel` pointer is only guaranteed for the duration of that one call, so keep
        // the buffer explicitly borrowed across the whole context lifetime instead.
        return pixel.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(data: raw.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                                          bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                return false
            }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return raw[3] == 0
        }
    }

    // In-process capture through AppKit: NSView.cacheDisplay draws the view tree into a bitmap at
    // the window's backing scale. Captures the window's frame view (the content view's superview),
    // so the title bar and the window background color are included; only the window-server
    // shadow is missing compared with the legacy capture.
    @MainActor
    private func captureOffscreen(window: NSWindow) -> CGImage? {
        guard let view = window.contentView?.superview ?? window.contentView else {
            print("Error: No content view to capture")
            return nil
        }
        // Re-assert key status: the activate() at launch is asynchronous, and an inactive window
        // draws its controls gray. (With the screen locked the app cannot become active, so the
        // image then shows the inactive tint; the layout is unaffected.)
        window.makeKey()
        view.layoutSubtreeIfNeeded()
        let bounds = view.bounds
        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else {
            print("Error: Could not create a bitmap for the window")
            return nil
        }
        rep.size = bounds.size
        view.cacheDisplay(in: bounds, to: rep)
        guard let cgImage = rep.cgImage else {
            print("Error: cacheDisplay produced no image")
            return nil
        }
        return cgImage
    }

    // CGWindowListCreateImage path: no Screen Recording permission needed for the app's own window.
    @MainActor
    private func captureLegacy(window: NSWindow) -> CGImage? {
        let windowID = CGWindowID(window.windowNumber)
        // Call through the non-deprecated protocol requirement so the deprecation stays confined
        // to the witness body (see LegacyWindowCapturer); a direct concrete call would warn here.
        let capturer: LegacyWindowCapturer = CGWindowListCapturer()
        guard let cgImage = capturer.captureImage(of: windowID) else {
            print("Error: Failed to capture window (legacy)")
            return nil
        }
        return cgImage
    }

    // ScreenCaptureKit path: the supported API, but requires Screen Recording permission (TCC).
    @MainActor
    private func captureWithScreenCaptureKit(window: NSWindow) async -> CGImage? {
        let targetWindowID = CGWindowID(window.windowNumber)
        let scale = window.backingScaleFactor

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let scWindow = content.windows.first(where: { $0.windowID == targetWindowID }) else {
                print("Error: Could not find the viewer window to capture")
                return nil
            }

            let filter = SCContentFilter(desktopIndependentWindow: scWindow)
            let config = SCStreamConfiguration()
            config.width = Int(scWindow.frame.width * scale)
            config.height = Int(scWindow.frame.height * scale)
            config.showsCursor = false

            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        } catch {
            print("Error capturing screenshot: \(error)")
            print("Hint: grant Screen Recording permission in System Settings > Privacy & Security > Screen Recording, or use --method legacy (no permission required).")
            return nil
        }
    }

    @discardableResult
    @MainActor
    private func savePNG(_ cgImage: CGImage, to path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            print("Error: Failed to create image destination")
            return false
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            print("Error: Failed to save PNG")
            return false
        }

        print("Screenshot saved to: \(path)")
        return true
    }
    
    func windowWillClose(_ notification: Notification) {
        NSApp.terminate(nil)
    }
}

@main
struct ActionUIViewerApp {
    static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.regular)
        let delegate = ActionUIViewerAppDelegate()
        NSApplication.shared.delegate = delegate
        let _ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
    }
}
