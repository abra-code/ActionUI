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

/// How `--screenshot` grabs the window image. Both capture the window-server composite, so
/// out-of-process content (WebView / VideoPlayer) is included either way; they differ only in
/// the OS permission they need.
enum ScreenshotMethod {
    /// CGWindowListCreateImage. Deprecated in macOS 14.0, but it captures this app's own window
    /// WITHOUT Screen Recording permission, so it works out of the box - convenient for automated
    /// / AI-agent screenshots. This is the default.
    case legacy
    /// ScreenCaptureKit (SCScreenshotManager). The supported, non-deprecated API and the long-term
    /// path, but it requires Screen Recording permission (TCC) even for the app's own window.
    case screenCaptureKit
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

func printUsage() {
    print("""
    ActionUIViewer - render an ActionUI JSON layout in a window, optionally capturing a screenshot.

    Usage:
      ActionUIViewer <path/to/input.json | https://url.to/input.json> [options]

    Options:
      --screenshot <output.png>     Capture the rendered window to a PNG, then exit.
      --method <legacy|sck>         Screenshot capture method (default: legacy).
                                      legacy  CGWindowListCreateImage; captures this app's own
                                              window without Screen Recording permission, so it
                                              works out of the box.
                                      sck     ScreenCaptureKit; the non-deprecated API, but it
                                              requires Screen Recording permission.
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
        var jsonFilePath: String?
        var screenshotPath: String?
        var screenshotMethod: ScreenshotMethod = .legacy
        var screenshotDelay: Double = 1.5

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
                    switch args[i].lowercased() {
                    case "legacy", "cg":
                        screenshotMethod = .legacy
                    case "sck", "screencapturekit":
                        screenshotMethod = .screenCaptureKit
                    default:
                        print("Error: Unknown --method '\(args[i])' (use 'legacy' or 'sck')")
                        NSApp.terminate(nil)
                        return
                    }
                }
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
        
        window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 800, height: 600),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable],
                         backing: .buffered, defer: false)
        window.title = "ActionUI Viewer - \(displayTitle)"
        window.center()
        window.delegate = self
        
        let hostingController = ActionUISwift.loadHostingController(from: url, windowUUID: windowUUID, isContentView: true)
        window.contentView = hostingController.view
        window.makeKeyAndOrderFront(nil)
        
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
    func takeScreenshot(saveTo path: String, method: ScreenshotMethod) async {
        // Always terminate after the attempt so an automated `--screenshot` run never hangs.
        defer { NSApp.terminate(nil) }

        guard let window = window, window.windowNumber > 0 else {
            print("Error: No window to capture")
            return
        }

        switch method {
        case .legacy:
            captureLegacy(window: window, saveTo: path)
        case .screenCaptureKit:
            await captureWithScreenCaptureKit(window: window, saveTo: path)
        }
    }

    // CGWindowListCreateImage path: no Screen Recording permission needed for the app's own window.
    @MainActor
    private func captureLegacy(window: NSWindow, saveTo path: String) {
        let windowID = CGWindowID(window.windowNumber)
        // Call through the non-deprecated protocol requirement so the deprecation stays confined
        // to the witness body (see LegacyWindowCapturer); a direct concrete call would warn here.
        let capturer: LegacyWindowCapturer = CGWindowListCapturer()
        guard let cgImage = capturer.captureImage(of: windowID) else {
            print("Error: Failed to capture window (legacy)")
            return
        }
        savePNG(cgImage, to: path)
    }

    // ScreenCaptureKit path: the supported API, but requires Screen Recording permission (TCC).
    @MainActor
    private func captureWithScreenCaptureKit(window: NSWindow, saveTo path: String) async {
        let targetWindowID = CGWindowID(window.windowNumber)
        let scale = window.backingScaleFactor

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let scWindow = content.windows.first(where: { $0.windowID == targetWindowID }) else {
                print("Error: Could not find the viewer window to capture")
                return
            }

            let filter = SCContentFilter(desktopIndependentWindow: scWindow)
            let config = SCStreamConfiguration()
            config.width = Int(scWindow.frame.width * scale)
            config.height = Int(scWindow.frame.height * scale)
            config.showsCursor = false

            let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            savePNG(cgImage, to: path)
        } catch {
            print("Error capturing screenshot: \(error)")
            print("Hint: grant Screen Recording permission in System Settings > Privacy & Security > Screen Recording, or use --method legacy (no permission required).")
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
