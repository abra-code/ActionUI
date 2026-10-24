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
final class CustomLogger: ActionUI.ActionUILogger {
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
        // The action handlers, shared with the Linux demo.
        DemoHandlers.register(resourceURL: { Bundle.main.url(forResource: $0, withExtension: $1) })

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
        .commands {
            SidebarCommands()
        }
        
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

    // Set by the -openResource test hook below; shared across selector windows. @MainActor
    // rather than nonisolated(unsafe) - every access is from an .onAppear closure formed in
    // View.body, which is already MainActor-isolated, so this is a checked guarantee instead
    // of the compiler being told to look away.
    @MainActor private static var didAutoOpenResource = false

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
                // Test hook: the multi-window twin of the single-window `-openResource`
                // hook below, so a document can be opened on launch without driving the
                // selector.
                //
                // Why it is needed: `.accessibilityElement(children: .combine)` above
                // collapses this List into ONE element, so the per-resource Buttons are not
                // exposed to assistive technology or to XCUITest. ActionUITestAppTests.swift
                // does try to tap them (`jsonList.buttons[name]`), and those three tests are
                // FAILING as of 2026-08-08 - 12 failures across the 4 UI configurations -
                // which is consistent with this being the cause. Unrelated to this hook and
                // not fixed here, but worth knowing before trusting that path.
                //
                // Fires ONCE per launch, not once per selector window. macOS restores
                // previously-open selector windows, so an un-guarded hook opened one
                // document window per restored selector and left several identical
                // windows on screen - which XCUITest then refuses to act on, because
                // "the PUSH button" no longer identifies a single element.
                //
                // windowUUID is the resource name rather than a fresh UUID (unlike the
                // manual Button above) so that re-opening the same resource focuses the
                // existing window instead of stacking another. One window, one
                // ActionUIModel.windowModels entry, one set of view models - intentional.
                .onAppear {
                    guard !Self.didAutoOpenResource,
                          let idx = CommandLine.arguments.firstIndex(of: "-openResource"),
                          idx + 1 < CommandLine.arguments.count else { return }
                    let name = CommandLine.arguments[idx + 1]
                    guard jsonFiles.contains(name) else { return }
                    Self.didAutoOpenResource = true
                    openWindow(value: WindowIdentifier(resourceName: name, windowUUID: name))
                }
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
                // Test hook: `-openResource <Name>` opens that document's fullScreenCover on launch,
                // so a document can be screenshotted edge-to-edge without GUI navigation.
                .onAppear {
                    if let idx = CommandLine.arguments.firstIndex(of: "-openResource"),
                       idx + 1 < CommandLine.arguments.count {
                        selectedResource = CommandLine.arguments[idx + 1]
                    }
                }
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
