//
//  ActionUIViewer main.swift
//  ActionUIViewer
//
//  A command-line tool to view ActionUI JSON files in a window.
//  Usage: ActionUIViewer <path-to-json-file>
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
        
        guard let path = jsonFilePath else {
            print("Usage: ActionUIViewer [--screenshot <output.png>] <input.json>")
            NSApp.terminate(nil)
            return
        }
        
        let url = URL(fileURLWithPath: path)
        self.screenshotPath = screenshotPath
        
        guard FileManager.default.fileExists(atPath: path) else {
            print("Error: File not found at path: \(path)")
            window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
                            styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.contentView = NSHostingView(rootView: ErrorView(message: "File not found:\n\(path)"))
            window.delegate = self
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let windowUUID = UUID().uuidString
        let logger = CustomLogger()
        ActionUISwift.setLogger(logger)
        ActionUISwift.setDefaultActionHandler({ actionID, windowUUID, viewID, viewPartID, context in
            print("Action: actionID=\(actionID), windowUUID=\(windowUUID), viewID=\(viewID), viewPartID=\(viewPartID), context=\(String(describing: context))")
        })
        
        window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 800, height: 600),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable],
                         backing: .buffered, defer: false)
        window.title = "ActionUI Viewer - \(url.lastPathComponent)"
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
            
            let image = CGWindowListCreateImage(.zero, .optionIncludingWindow, CGWindowID(windowNumber), [])
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
