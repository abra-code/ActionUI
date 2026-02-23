// Fixed ActionUISwiftTestApp.swift

#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

import SwiftUI
import ActionUI
import ActionUISwiftAdapter

// Custom logger
class CustomLogger: ActionUI.ActionUILogger {
    func log(_ message: String, _ level: ActionUI.LoggerLevel) {
        print("[ActionUI][\(level)] \(message)")
    }
}

@main
struct ActionUISwiftTestApp: App {
    let logger = CustomLogger()

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
        // Configure logger
        ActionUISwift.setLogger(logger)
        // receiving actionID, windowUUID, viewID, viewPartID, and optional context
        ActionUISwift.setDefaultActionHandler({actionID, windowUUID, viewID, viewPartID, context in
            print("Default action callback for actionID:\(actionID), windowUUID: \(windowUUID), viewID: \(viewID), viewPartID: \(viewPartID), context: \(String(describing: context))")
        })
        
        // Table demo handlers
        var tableAppendIndex = 0
        let tableExtraRows: [[String]] = [
            ["Frank Chen",    "Director",  "Operations"],
            ["Grace Kim",     "Lead",      "Platform"],
            ["Henry Wu",      "Intern",    "Data"]
        ]
        ActionUISwift.registerActionHandler(actionID: "table.demo.load") { _, windowUUID, _, _, _ in
            ActionUISwift.setElementRows(windowUUID: windowUUID, viewID: 1, rows: [
                ["Alice Johnson", "Engineer",  "Platform"],
                ["Bob Smith",     "Designer",  "Product"],
                ["Carol White",   "Manager",   "Engineering"],
                ["David Lee",     "Analyst",   "Data"],
                ["Eva Martinez",  "Engineer",  "Platform"]
            ])
        }
        ActionUISwift.registerActionHandler(actionID: "table.demo.append") { _, windowUUID, _, _, _ in
            let row = tableExtraRows[tableAppendIndex % tableExtraRows.count]
            tableAppendIndex += 1
            ActionUISwift.appendElementRows(windowUUID: windowUUID, viewID: 1, rows: [row])
        }
        ActionUISwift.registerActionHandler(actionID: "table.demo.clear") { _, windowUUID, _, _, _ in
            ActionUISwift.clearElementRows(windowUUID: windowUUID, viewID: 1)
        }
        ActionUISwift.registerActionHandler(actionID: "table.demo.selectionChanged") { _, windowUUID, _, _, _ in
            if let selected = ActionUISwift.getElementValue(windowUUID: windowUUID, viewID: 1) as? [String], !selected.isEmpty {
                print("Table row selected: \(selected)")
            }
        }

        // List demo handlers
        var listAppendIndex = 0
        let listExtraItems = ["Haskell", "Elixir", "Julia", "Zig", "Dart"]
        ActionUISwift.registerActionHandler(actionID: "list.demo.load") { _, windowUUID, _, _, _ in
            ActionUISwift.setElementRows(windowUUID: windowUUID, viewID: 1, rows: [
                ["Swift"], ["Python"], ["Kotlin"], ["TypeScript"], ["Rust"], ["Go"]
            ])
            ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 2, value: "Selected: <none>")
        }
        ActionUISwift.registerActionHandler(actionID: "list.demo.append") { _, windowUUID, _, _, _ in
            let item = listExtraItems[listAppendIndex % listExtraItems.count]
            listAppendIndex += 1
            ActionUISwift.appendElementRows(windowUUID: windowUUID, viewID: 1, rows: [[item]])
        }
        ActionUISwift.registerActionHandler(actionID: "list.demo.clear") { _, windowUUID, _, _, _ in
            ActionUISwift.clearElementRows(windowUUID: windowUUID, viewID: 1)
            ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 2, value: "Selected: <none>")
        }
        ActionUISwift.registerActionHandler(actionID: "list.demo.selectionChanged") { _, windowUUID, _, _, _ in
            let selected = ActionUISwift.getElementValue(windowUUID: windowUUID, viewID: 1) as? [String]
            let label = selected?.first.map { "Selected: \($0)" } ?? "Selected: <none>"
            ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 2, value: label)
        }

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
                    AnyView(ActionUISwift.loadView(from: url, windowUUID: identifier.windowUUID, isContentView: true))
                }
            } else {
                EmptyView()
            }
        }
        .handlesExternalEvents(matching: ["ActionUIContent-*"])
        
        LoadableWindowGroup.load(
            fromResource: "DefaultWindow",
            windowUUID: UUID().uuidString,
            logger: logger
        )
        .handlesExternalEvents(matching: ["DefaultWindow"])
        // TODO: looks like CommandGroup & CommandMenu buttons with shortcuts will require special handling
        // this example command shortcut works but the ones set in base View.applyModifiers do not appear:
        .commands {
            CommandGroup(after: .help) {
                Button("Help from ActionUISwiftTestApp") {
                    // Action for the About command
                    print("Help from ActionUISwiftTestApp triggered")
                }
                .keyboardShortcut("H", modifiers: [.command, .shift]) // Add a keyboard shortcut
            }
        }
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
        Bundle.main.paths(forResourcesOfType: "json", inDirectory: nil)
            .map { URL(filePath: $0).deletingPathExtension().lastPathComponent }
            .sorted()
            .filter { $0 != "DefaultWindow" } // Filter out DefaultWindow to avoid duplication
    }
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            if jsonFiles.isEmpty {
                Text("No JSON files found in the app bundle.")
                    .padding()
                    .accessibilityIdentifier("no_json_files_text")
            } else {
                if supportsMultipleWindows {
                    List {
                        Button("Default Window") {
                            openWindow(id: "WelcomeWindow") // WelcomeWindow is the windowGroupID declared in JSON description
                        }
                        .accessibilityIdentifier("default_window_button")
                        
                        ForEach(jsonFiles, id: \.self) { name in
                            Button(name) {
                                let windowUUID = UUID().uuidString
                                openWindow(value: WindowIdentifier(resourceName: name, windowUUID: windowUUID))
                            }
                        }
                    }
                    .navigationTitle("JSON Selector")
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("json_selector_list")
                } else {
                    List(jsonFiles, id: \.self) { name in
                        NavigationLink(value: name) {
                            Text(name)
                        }
                    }
                    .navigationDestination(for: String.self) { resourceName in
                        if let url = Bundle.main.url(forResource: resourceName, withExtension: ".json") {
                            AnyView(ActionUISwift.loadView(from: url, windowUUID: resourceName, isContentView: true))
                        }
                    }
                    .navigationTitle("JSON Selector")
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("json_selector_list")
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        JSONSelectorView(logger: ConsoleLogger(maxLevel: .verbose))
    }
}
