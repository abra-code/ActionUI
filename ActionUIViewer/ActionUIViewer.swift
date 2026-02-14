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

class CustomLogger: ActionUI.ActionUILogger {
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
        
        let args = CommandLine.arguments
        var i = 1
        while i < args.count {
            switch args[i] {
            case "--screenshot":
                i += 1
                if i < args.count {
                    screenshotPath = args[i]
                }
            default:
                if jsonFilePath == nil {
                    jsonFilePath = args[i]
                }
            }
            i += 1
        }
        
        guard let pathOrUrl = jsonFilePath else {
            print("Usage: ActionUIViewer [--screenshot <output.png>] <path/to/input.json|https://url.to/input.json>")
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.takeScreenshot(saveTo: screenshotPath)
            }
        }
    }
    
    func takeScreenshot(saveTo path: String) {
        guard let window = window else {
            print("Error: No window")
            return
        }

        let workItem = DispatchWorkItem {
            let windowNumber = window.windowNumber
            guard windowNumber > 0 else {
                print("Error: Invalid window number")
                return
            }

            let image = CGWindowListCreateImage(CGRect.zero, .optionIncludingWindow, CGWindowID(windowNumber), [])
            guard let cgImage = image else {
                print("Error: Failed to capture window")
                return
            }

            let url = URL(fileURLWithPath: path)
            guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
                print("Error: Failed to create image destination")
                return
            }
            CGImageDestinationAddImage(destination, cgImage, nil)

            guard CGImageDestinationFinalize(destination) else {
                print("Error: Failed to save PNG")
                return
            }

            print("Screenshot saved to: \(path)")
            NSApp.terminate(nil)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: workItem)
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
