// ActionUITestApp.swift
import SwiftUI
import ActionUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

@main
struct ActionUITestApp: App {
    let logger = ConsoleLogger(maxLevel: .verbose)

    // Runtime check for multi-window support
    private var supportsMultipleWindows: Bool {
        #if canImport(UIKit)
        return UIApplication.shared.supportsMultipleScenes
        #else
        return true // macOS supports multiple windows
        #endif
    }
    
    // Check for reset launch argument
    private var shouldResetState: Bool {
        CommandLine.arguments.contains("-resetAppState")
    }
    
    // Environment to manage windows
    @Environment(\.openWindow) private var openWindow
    
    init() {
        if shouldResetState {
            // Clear custom state
            UserDefaults.standard.removeObject(forKey: "openWindows")
        }
    }
    
    var body: some Scene {
        WindowGroup("JSON Selector") {
            NavigationStack {
                JSONSelectorView(logger: logger)
                    .onAppear {
                        if shouldResetState && supportsMultipleWindows {
                            // Ensure JSON Selector window is open
                            openWindow(id: "JSON Selector")
                            // Log open windows/sessions for debugging
                            #if canImport(UIKit)
                            print("Open sessions: \(UIApplication.shared.openSessions.map { $0.persistentIdentifier })")
                            #endif
                            #if canImport(AppKit)
                            print("Open windows: \(NSApplication.shared.windows.map { $0.title })")
                            #endif
                        }
                    }
            }
        }
        .handlesExternalEvents(matching: ["JSON Selector"])
        
        WindowGroup(for: WindowIdentifier.self) { $windowIdentifier in
            if supportsMultipleWindows, let identifier = windowIdentifier, !shouldResetState {
                if let url = Bundle.main.url(forResource: identifier.resourceName, withExtension: ".json") {
                    ActionUI.FileLoadableView(
                        fileURL: url,
                        windowUUID: identifier.windowUUID,
                        isContentView: true,
                        logger: logger)
                }
            } else {
                EmptyView()
            }
        }
        .handlesExternalEvents(matching: ["ActionUIContent-*"])
    }
}

struct WindowIdentifier: Hashable, Codable {
    let resourceName: String
    let windowUUID: String
    
    enum CodingKeys: String, CodingKey {
        case resourceName
        case windowUUID
    }
    
    init(resourceName: String, windowUUID: String) {
        self.resourceName = resourceName
        self.windowUUID = windowUUID
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        resourceName = try container.decode(String.self, forKey: .resourceName)
        windowUUID = try container.decode(String.self, forKey: .windowUUID)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(resourceName, forKey: .resourceName)
        try container.encode(windowUUID, forKey: .windowUUID)
    }
}

struct JSONSelectorView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    @State private var navigationPath = NavigationPath()
    let logger: any ActionUILogger
    
    private var supportsMultipleWindows: Bool {
        #if canImport(UIKit)
        return UIApplication.shared.supportsMultipleScenes
        #else
        return true // macOS supports multiple windows
        #endif
    }
    
    // Compute jsonFiles outside view builder
    private var jsonFiles: [String] {
        let files = Bundle.main.paths(forResourcesOfType: "json", inDirectory: nil)
            .map { URL(filePath: $0).deletingPathExtension().lastPathComponent }
            .sorted()
//        print("JSON files found: \(files)")
        return files
    }
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            if jsonFiles.isEmpty {
                Text("No JSON files found in the app bundle.")
                    .padding()
                    .accessibilityIdentifier("no_json_files_text")
            } else {
                List(jsonFiles, id: \.self) { name in
                    if supportsMultipleWindows {
                        Button(name) {
                            let windowUUID = UUID().uuidString
                            openWindow(value: WindowIdentifier(resourceName: name, windowUUID: windowUUID))
                        }
                    } else {
                        NavigationLink(value: name) {
                            Text(name)
                        }
                        .navigationDestination(for: String.self) { resourceName in
                            if let url = Bundle.main.url(forResource: resourceName, withExtension: ".json") {
                                ActionUI.FileLoadableView(
                                    fileURL: url,
                                    windowUUID: resourceName,
                                    isContentView: true,
                                    logger: logger)
                            }
                        }
                    }
                }
                .navigationTitle("JSON Selector")
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("json_selector_list")
            }
        }
    }
}

#Preview {
    NavigationStack {
        JSONSelectorView(logger: ConsoleLogger(maxLevel: .verbose))
    }
}
