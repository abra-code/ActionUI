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
        ActionUISwift.registerActionHandler(actionID: "table.demo.selection.changed") { _, windowUUID, _, _, _ in
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
        ActionUISwift.registerActionHandler(actionID: "list.demo.selection.changed") { _, windowUUID, _, _, _ in
            let selected = ActionUISwift.getElementValue(windowUUID: windowUUID, viewID: 1) as? [String]
            let label = selected?.first.map { "Selected: \($0)" } ?? "Selected: <none>"
            ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 2, value: label)
        }

        // VStack template demo handlers (VStack.template.json)
        // IDs: 10 = VStack+Label, 20 = VStack+HStack, 30 = HStack chips, 99 = status label
        let vstackTemplateRows: [[String]] = [
            ["star.fill",       "Favorites"],
            ["heart.fill",      "Liked"],
            ["clock",           "Recent"],
            ["bookmark.fill",   "Saved"],
            ["bell.fill",       "Notifications"]
        ]
        var vstackTemplateAppendIndex = 0
        let vstackTemplateExtraRows: [[String]] = [
            ["archivebox.fill", "Archive"],
            ["trash.fill",      "Trash"],
            ["folder.fill",     "Folder"]
        ]
        let vstackChipRows: [[String]] = [
            ["Swift"], ["Python"], ["Kotlin"], ["TypeScript"], ["Rust"]
        ]

        ActionUISwift.registerActionHandler(actionID: "vstack.template.demo.load") { _, windowUUID, _, _, _ in
            ActionUISwift.setElementRows(windowUUID: windowUUID, viewID: 10, rows: vstackTemplateRows)
            ActionUISwift.setElementRows(windowUUID: windowUUID, viewID: 20, rows: vstackTemplateRows)
            ActionUISwift.setElementRows(windowUUID: windowUUID, viewID: 30, rows: vstackChipRows)
            ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 99, value: "Tap a row or chip to see the action here.")
        }
        ActionUISwift.registerActionHandler(actionID: "vstack.template.demo.append") { _, windowUUID, _, _, _ in
            let row = vstackTemplateExtraRows[vstackTemplateAppendIndex % vstackTemplateExtraRows.count]
            vstackTemplateAppendIndex += 1
            ActionUISwift.appendElementRows(windowUUID: windowUUID, viewID: 10, rows: [row])
            ActionUISwift.appendElementRows(windowUUID: windowUUID, viewID: 20, rows: [row])
            ActionUISwift.appendElementRows(windowUUID: windowUUID, viewID: 30, rows: [[row[1]]])
        }
        ActionUISwift.registerActionHandler(actionID: "vstack.template.demo.clear") { _, windowUUID, _, _, _ in
            ActionUISwift.clearElementRows(windowUUID: windowUUID, viewID: 10)
            ActionUISwift.clearElementRows(windowUUID: windowUUID, viewID: 20)
            ActionUISwift.clearElementRows(windowUUID: windowUUID, viewID: 30)
            ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 99, value: "Cleared.")
        }
        ActionUISwift.registerActionHandler(actionID: "vstack.template.demo.select") { _, windowUUID, viewID, viewPartID, _ in
            if let rows = ActionUISwift.getElementRows(windowUUID: windowUUID, viewID: viewID),
               rows.indices.contains(viewPartID) {
                let row = rows[viewPartID]
                ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 99,
                    value: "Selected row \(viewPartID): \(row.joined(separator: " / "))")
            }
        }
        ActionUISwift.registerActionHandler(actionID: "vstack.template.demo.chip") { _, windowUUID, viewID, viewPartID, _ in
            if let rows = ActionUISwift.getElementRows(windowUUID: windowUUID, viewID: viewID),
               rows.indices.contains(viewPartID) {
                let chip = rows[viewPartID].first ?? "?"
                ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 99,
                    value: "Chip tapped: \(chip) (row \(viewPartID))")
            }
        }

        // List template demo handlers (List.template.json)
        // IDs: 11 = List+Label, 21 = List+HStack, 31 = List+Button, 99 = status label
        let listTemplateRows: [[String]] = [
            ["star.fill",       "Favorites"],
            ["heart.fill",      "Liked"],
            ["clock",           "Recent"],
            ["bookmark.fill",   "Saved"],
            ["bell.fill",       "Notifications"]
        ]
        var listTemplateAppendIndex = 0
        let listTemplateExtraRows: [[String]] = [
            ["archivebox.fill", "Archive"],
            ["trash.fill",      "Trash"],
            ["folder.fill",     "Folder"]
        ]
        let listChipRows: [[String]] = [
            ["Swift"], ["Python"], ["Kotlin"], ["TypeScript"], ["Rust"]
        ]

        ActionUISwift.registerActionHandler(actionID: "list.template.demo.load") { _, windowUUID, _, _, _ in
            ActionUISwift.setElementRows(windowUUID: windowUUID, viewID: 11, rows: listTemplateRows)
            ActionUISwift.setElementRows(windowUUID: windowUUID, viewID: 21, rows: listTemplateRows)
            ActionUISwift.setElementRows(windowUUID: windowUUID, viewID: 31, rows: listChipRows)
            ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 99, value: "Tap a row or button to see the action here.")
        }
        ActionUISwift.registerActionHandler(actionID: "list.template.demo.append") { _, windowUUID, _, _, _ in
            let row = listTemplateExtraRows[listTemplateAppendIndex % listTemplateExtraRows.count]
            listTemplateAppendIndex += 1
            ActionUISwift.appendElementRows(windowUUID: windowUUID, viewID: 11, rows: [row])
            ActionUISwift.appendElementRows(windowUUID: windowUUID, viewID: 21, rows: [row])
            ActionUISwift.appendElementRows(windowUUID: windowUUID, viewID: 31, rows: [[row[1]]])
        }
        ActionUISwift.registerActionHandler(actionID: "list.template.demo.clear") { _, windowUUID, _, _, _ in
            ActionUISwift.clearElementRows(windowUUID: windowUUID, viewID: 11)
            ActionUISwift.clearElementRows(windowUUID: windowUUID, viewID: 21)
            ActionUISwift.clearElementRows(windowUUID: windowUUID, viewID: 31)
            ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 99, value: "Cleared.")
        }
        ActionUISwift.registerActionHandler(actionID: "list.template.demo.select") { _, windowUUID, viewID, viewPartID, _ in
            if let rows = ActionUISwift.getElementRows(windowUUID: windowUUID, viewID: viewID),
               rows.indices.contains(viewPartID) {
                let row = rows[viewPartID]
                ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 99,
                    value: "Selected row \(viewPartID): \(row.joined(separator: " / "))")
            }
        }
        ActionUISwift.registerActionHandler(actionID: "list.template.demo.chip") { _, windowUUID, viewID, viewPartID, _ in
            if let rows = ActionUISwift.getElementRows(windowUUID: windowUUID, viewID: viewID),
               rows.indices.contains(viewPartID) {
                let chip = rows[viewPartID].first ?? "?"
                ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 99,
                    value: "Chip tapped: \(chip) (row \(viewPartID))")
            }
        }

        // Sheet demo handlers
        ActionUISwift.registerActionHandler(actionID: "sheet.dismissed") { _, windowUUID, _, _, _ in
            ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 99, value: "Sheet dismissed.")
        }
        ActionUISwift.registerActionHandler(actionID: "cover.dismissed") { _, windowUUID, _, _, _ in
            ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 99, value: "Full screen cover dismissed.")
        }
        ActionUISwift.registerActionHandler(actionID: "sheet.demo.presentModal.sheet") { _, windowUUID, _, _, _ in
            guard let url = Bundle.main.url(forResource: "Sheet.modal", withExtension: "json"),
                  let data = try? Data(contentsOf: url) else { return }
            try? ActionUISwift.presentModal(
                windowUUID: windowUUID, data: data, format: "json",
                style: .sheet, onDismissActionID: "sheet.demo.tier2.dismissed"
            )
        }
        ActionUISwift.registerActionHandler(actionID: "sheet.demo.presentModal.cover") { _, windowUUID, _, _, _ in
            guard let url = Bundle.main.url(forResource: "Sheet.modal", withExtension: "json"),
                  let data = try? Data(contentsOf: url) else { return }
            try? ActionUISwift.presentModal(
                windowUUID: windowUUID, data: data, format: "json",
                style: .fullScreenCover, onDismissActionID: "sheet.demo.tier2.dismissed"
            )
        }
        ActionUISwift.registerActionHandler(actionID: "sheet.demo.tier2.dismissed") { _, windowUUID, _, _, _ in
            ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 99, value: "Window-level modal dismissed.")
        }
        ActionUISwift.registerActionHandler(actionID: "modal.dismiss") { _, windowUUID, _, _, _ in
            ActionUISwift.dismissModal(windowUUID: windowUUID)
        }

        // Alert demo handlers
        ActionUISwift.registerActionHandler(actionID: "demo.showAlert") { _, windowUUID, _, _, _ in
            ActionUISwift.presentAlert(
                windowUUID: windowUUID,
                title: "Hello",
                message: "This is a window-level alert."
            )
        }
        ActionUISwift.registerActionHandler(actionID: "demo.showAlertCustom") { _, windowUUID, _, _, _ in
            let buttons: [ActionUI.DialogButton] = [
                .init(title: "Delete", role: .destructive, actionID: "demo.delete.confirmed"),
                .init(title: "Cancel", role: .cancel, actionID: nil)
            ]
            ActionUISwift.presentAlert(
                windowUUID: windowUUID,
                title: "Delete Item?",
                message: "This action cannot be undone.",
                buttons: buttons
            )
        }
        ActionUISwift.registerActionHandler(actionID: "demo.showConfirmation") { _, windowUUID, _, _, _ in
            let buttons: [ActionUI.DialogButton] = [
                .init(title: "Save", role: nil, actionID: "demo.save.confirmed"),
                .init(title: "Don't Save", role: .destructive, actionID: "demo.discard.confirmed"),
                .init(title: "Cancel", role: .cancel, actionID: nil)
            ]
            ActionUISwift.presentConfirmationDialog(
                windowUUID: windowUUID,
                title: "Save changes?",
                message: "Your changes will be lost if you don't save.",
                buttons: buttons
            )
        }
        ActionUISwift.registerActionHandler(actionID: "demo.delete.confirmed") { _, windowUUID, _, _, _ in
            ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 99, value: "Deleted!")
        }
        ActionUISwift.registerActionHandler(actionID: "demo.save.confirmed") { _, windowUUID, _, _, _ in
            ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 99, value: "Saved!")
        }
        ActionUISwift.registerActionHandler(actionID: "demo.discard.confirmed") { _, windowUUID, _, _, _ in
            ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 99, value: "Discarded.")
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
            
            TextEditingCommands()
            
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
    @State private var selectedResource: String?
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
            }
            else {
            #if canImport(UIKit)
            
                // Single-window mode (iOS without multi-scene support):
                // use fullScreenCover to avoid nesting NavigationStacks.
                // JSON views like NavigationStack.json create their own NavigationStack,
                // so embedding them inside the outer NavigationStack causes broken navigation on iOS.
                List(jsonFiles, id: \.self) { name in
                    Button(name) {
                        selectedResource = name
                    }
                }
                .navigationTitle("JSON Selector")
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("json_selector_list")
                .fullScreenCover(isPresented: Binding(
                    get: { selectedResource != nil },
                    set: { if !$0 { selectedResource = nil } }
                )) {
                    GeometryReader { _ in
                        if let resourceName = selectedResource,
                           let url = Bundle.main.url(forResource: resourceName, withExtension: ".json") {
                            AnyView(ActionUISwift.loadView(from: url, windowUUID: resourceName, isContentView: true))
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        Button {
                            selectedResource = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.secondary)
                                .padding()
                        }
                    }
                }
            #endif // canImport(UIKit)
            }
        }
    }
}

#Preview {
    NavigationStack {
        JSONSelectorView(logger: ConsoleLogger(maxLevel: .verbose))
    }
}
