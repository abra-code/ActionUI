//  TemperatureConverter - ActionUI Example, Level 1
//
//  The smallest real ActionUI app. A host does exactly three things on every
//  platform, and this file does only those three:
//    (1) load + present the shared JSON (shared/TemperatureConverter.json),
//    (2) register handlers for the actionIDs the JSON fires,
//    (3) read input values by id, compute, and write the result back by id.

import SwiftUI
import ActionUI
import ActionUISwiftAdapter

@main
struct TemperatureConverterApp: App {

    init() {
        // (2) Wire the one actionID this screen uses. The TextField's
        // valueChangeActionID and both Pickers' actionID all fire
        // "temp.recompute", so a single handler covers the whole screen.
        // The closure is handed (actionID, windowUUID, viewID, viewPartID,
        // context); we only need windowUUID to address this window's elements.
        ActionUISwift.registerActionHandler(actionID: "temp.recompute") { _, windowUUID, _, _, _ in
            // The handler closure is non-isolated, but ActionUI delivers action
            // callbacks on the main thread. assumeIsolated bridges to the main actor
            // so we can touch main-actor UI state (the value bridge) synchronously.
            MainActor.assumeIsolated { recompute(windowUUID) }
        }
    }

    var body: some Scene {
        WindowGroup { RootView() }
    }
}

private struct RootView: View {
    // A window's elements are addressed by (windowUUID, viewID). Mint one id
    // for the lifetime of this presented view.
    @State private var windowUUID = UUID().uuidString

    var body: some View {
        // (1) Load the shared JSON from the app bundle and render it natively.
        if let url = Bundle.main.url(forResource: "TemperatureConverter", withExtension: "json") {
            AnyView(ActionUISwift.loadView(from: url, windowUUID: windowUUID, isContentView: true))
        } else {
            Text("TemperatureConverter.json missing from the app bundle")
        }
    }
}

// (3) The logic - plain Swift apart from the read/write calls. Marked @MainActor
// because the value bridge (get/setElementValue) is main-actor isolated: it reads
// and writes live UI state. Action handlers already run on the main actor, so this
// is just making that explicit (convert/unitName below stay plain, non-isolated).
@MainActor
private func recompute(_ windowUUID: String) {
    // Read the field text and each Picker's selected tag ("C" / "F" / "K").
    let raw  = ActionUISwift.getElementValue(windowUUID: windowUUID, viewID: 10) as? String ?? ""
    let from = ActionUISwift.getElementValue(windowUUID: windowUUID, viewID: 20) as? String ?? "C"
    let to   = ActionUISwift.getElementValue(windowUUID: windowUUID, viewID: 30) as? String ?? "F"

    guard let n = Double(raw.trimmingCharacters(in: .whitespaces)) else {
        // Blank or not a number -> blank result (the "To" picker still shows the unit).
        ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 40, value: "")
        return
    }
    // The result shows just the number; its unit is the adjacent "To" picker.
    let out = convert(n, from: from, to: to)
    ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 40,
                                  value: String(format: "%.2f", out))
}

// Convert through Celsius as the common pivot.
private func convert(_ value: Double, from: String, to: String) -> Double {
    let celsius: Double
    switch from {
    case "F": celsius = (value - 32) * 5 / 9
    case "K": celsius = value - 273.15
    default:  celsius = value            // "C"
    }
    switch to {
    case "F": return celsius * 9 / 5 + 32
    case "K": return celsius + 273.15
    default:  return celsius             // "C"
    }
}
