// Add-ons/ActionUIAddOnTestApp/Sources/ActionUIAddOnTestApp.swift
//
// Runtime host for ActionUI add-ons (the add-on analogue of ActionUISwiftTestApp), macOS + iOS.
// Links ActionUI core + ActionUISwiftAdapter + linked add-on packages, registers their element
// types at launch, and presents a picker over the bundled add-on demo documents.

import SwiftUI
import ActionUI
import ActionUISwiftAdapter
import ActionUIQuickLook

@main
struct ActionUIAddOnTestApp: App {

    init() {
        ActionUISwift.setLogger(ConsoleLogger(maxLevel: .info))

        // Register every linked add-on's element types BEFORE any window that uses them is built.
        // Add a line here per add-on.
        ActionUIQuickLook.register()

        ActionUISwift.setDefaultActionHandler { actionID, windowUUID, viewID, viewPartID, _ in
            print("[action] \(actionID) window:\(windowUUID) view:\(viewID).\(viewPartID)")
        }
        ActionUISwift.registerActionHandler(actionID: "ql.changed") { _, _, viewID, _, _ in
            print("[QuickLook] preview reloaded for element \(viewID)")
        }
    }

    var body: some Scene {
        WindowGroup("ActionUI Add-on Demos") {
            AddOnPickerView()
        }
    }
}

/// A picker over the add-on demo documents bundled in `Resources/`. Each `*.json` is a demo that
/// uses one or more add-on element types; selecting one loads it into the detail pane. A new add-on
/// adds its demo JSON to `Resources/` (and a `DemoSetup` case if the demo needs runtime data) and it
/// appears here automatically. QuickLook is the first; it will not be the last.
struct AddOnPickerView: View {
    @State private var selected: String?

    private var demos: [String] {
        Bundle.main.paths(forResourcesOfType: "json", inDirectory: nil)
            .map { URL(filePath: $0).deletingPathExtension().lastPathComponent }
            .sorted()
    }

    var body: some View {
        NavigationSplitView {
            List(demos, id: \.self, selection: $selected) { name in
                Text(name)
            }
            .navigationTitle("Add-ons")
        } detail: {
            if let name = selected, let url = Bundle.main.url(forResource: name, withExtension: "json") {
                AnyView(ActionUISwift.loadView(from: url, windowUUID: name, isContentView: true))
                    .id(name)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // .task(id:) re-runs whenever `name` changes - unlike .onAppear, which does not
                    // reliably re-fire on a NavigationSplitView selection switch on macOS.
                    .task(id: name) { DemoSetup.run(resource: name, windowUUID: name) }
            } else {
                ContentUnavailableView("Select an add-on demo", systemImage: "square.dashed")
            }
        }
        .onAppear { if selected == nil { selected = demos.first } }
    }
}

/// Per-demo runtime setup. Most demos are self-contained JSON; some (like QuickLook, which previews
/// a file by path) need a value seeded at runtime from a bundled resource.
enum DemoSetup {
    // Each demo .json is a separate window, so DemoSetup must dispatch on the resource actually being
    // shown (the picker passes the selected file's name). Map each QuickLook demo to the element id
    // in THAT document. A single hardcoded resource/id left the other demo blank on switch.
    private static let quickLookDemoElementID: [String: Int] = [
        "QuickLook": 70,                 // QuickLook.json (normal style, no chrome)
        "QuickLook.showsChrome": 71,     // QuickLook.showsChrome.json
        "QuickLook.compact": 72,         // QuickLook.compact.json (previewStyle: compact)
    ]

    @MainActor
    static func run(resource: String, windowUUID: String) {
        // Drive the demo's QuickLook element with the bundled multi-page Sample.pdf at runtime (not a
        // hardcoded JSON path) so it works on macOS and iOS, where the file lives in the app bundle.
        // A multi-page PDF exercises Quick Look's embedded page scroller. Regenerate the PDF with
        // Scripts/generate_sample_pdf.swift.
        if let viewID = quickLookDemoElementID[resource],
           let sample = Bundle.main.url(forResource: "Sample", withExtension: "pdf") {
            ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: viewID, value: sample.path)
        }
    }
}
