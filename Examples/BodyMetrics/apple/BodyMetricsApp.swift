//  BodyMetrics (BMI) - ActionUI Example, Level 1
//
//  Two Sliders (height, weight) and a metric/imperial Toggle feed a live BMI
//  readout: a circular Gauge whose value AND color track BMI, plus a numeric
//  Text and a category Text that recolor by health zone. A host does the same
//  three things on every platform, and this file does only those three:
//    (1) load + present the shared JSON (shared/BodyMetrics.json),
//    (2) register the one actionID the inputs fire ("bmi.recompute"),
//    (3) read inputs by id, compute, write outputs (values + colors) by id.
//
//  Slider values are always stored in metric (cm, kg) regardless of the toggle;
//  the toggle only changes how the read-out labels are formatted (ft/in, lb).
//  BMI is unit-agnostic, computed from the metric values.
//
//  id map (keep in sync with shared/BodyMetrics.json):
//    10  Toggle  imperial units on/off (fires actionID)
//    20  Slider  height, 100-220 cm    (fires valueChangeActionID)
//    21  Text    height read-out
//    30  Slider  weight, 30-200 kg     (fires valueChangeActionID)
//    31  Text    weight read-out
//    40  Gauge   BMI 10-40 (value + foregroundStyle set at runtime)
//    50  Text    BMI numeric
//    60  Text    category (foregroundStyle set at runtime)

import SwiftUI
import ActionUI
import ActionUISwiftAdapter

private enum ID {
    static let imperial = 10
    static let heightSlider = 20
    static let heightLabel = 21
    static let weightSlider = 30
    static let weightLabel = 31
    static let gauge = 40
    static let bmiText = 50
    static let category = 60
}

@main
struct BodyMetricsApp: App {

    init() {
        // (2) The Toggle and both Sliders all fire "bmi.recompute", so a single
        // handler covers the whole screen. The closure is handed (actionID,
        // windowUUID, viewID, viewPartID, context); we only need windowUUID.
        ActionUISwift.registerActionHandler(actionID: "bmi.recompute") { _, windowUUID, _, _, _ in
            // Callbacks arrive on the main thread but the closure is non-isolated;
            // assumeIsolated bridges to the main actor so we can touch the value bridge.
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
        if let url = Bundle.main.url(forResource: "BodyMetrics", withExtension: "json") {
            AnyView(ActionUISwift.loadView(from: url, windowUUID: windowUUID, isContentView: true))
        } else {
            Text("BodyMetrics.json missing from the app bundle")
        }
    }
}

// (3) The logic - plain Swift apart from the read/write calls. @MainActor because
// the value bridge is main-actor isolated (it reads and writes live UI state).
@MainActor
private func recompute(_ windowUUID: String) {
    // Read the toggle (Bool) and both Sliders (Double, always metric: cm / kg).
    let imperial = ActionUISwift.getElementValue(windowUUID: windowUUID, viewID: ID.imperial) as? Bool ?? false
    let cm = ActionUISwift.getElementValue(windowUUID: windowUUID, viewID: ID.heightSlider) as? Double ?? 170
    let kg = ActionUISwift.getElementValue(windowUUID: windowUUID, viewID: ID.weightSlider) as? Double ?? 70

    // BMI = kg / m^2 (unit-agnostic; always from the metric slider values).
    let meters = cm / 100.0
    let bmi = meters > 0 ? kg / (meters * meters) : 0

    // Unit-aware read-out labels.
    ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: ID.heightLabel, value: formatHeight(cm, imperial: imperial))
    ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: ID.weightLabel, value: formatWeight(kg, imperial: imperial))

    // Gauge value tracks BMI; clamp into the gauge's 10-40 range.
    let gaugeValue = min(max(bmi, 10), 40)
    ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: ID.gauge, value: gaugeValue)

    // BMI numeric text.
    ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: ID.bmiText, value: String(format: "%.1f", bmi))

    // Category name + matching color, applied to both the Gauge and the category Text.
    // Gauge accessoryCircularCapacity on iOS tints via `tint`; `foregroundStyle` alone
    // can leave the ring in the system primary (black/white). Set both for all hosts.
    let (name, color) = category(bmi)
    ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: ID.category, value: name)
    ActionUISwift.setElementProperty(windowUUID: windowUUID, viewID: ID.category, propertyName: "foregroundStyle", value: color)
    ActionUISwift.setElementProperty(windowUUID: windowUUID, viewID: ID.gauge, propertyName: "foregroundStyle", value: color)
    ActionUISwift.setElementProperty(windowUUID: windowUUID, viewID: ID.gauge, propertyName: "tint", value: color)
}

// Map BMI to a (label, color-name) pair. Colors are named ActionUI colors that
// resolve on all three platforms.
private func category(_ bmi: Double) -> (String, String) {
    switch bmi {
    case ..<18.5: return ("Underweight", "cyan")
    case ..<25.0: return ("Normal", "green")
    case ..<30.0: return ("Overweight", "orange")
    default:      return ("Obese", "red")
    }
}

private func formatHeight(_ cm: Double, imperial: Bool) -> String {
    if !imperial { return String(format: "%.0f cm", cm) }
    let totalInches = cm / 2.54
    var feet = Int(totalInches / 12.0)
    var inches = Int((totalInches - Double(feet) * 12.0).rounded())
    if inches == 12 { feet += 1; inches = 0 }
    return "\(feet) ft \(inches) in"
}

private func formatWeight(_ kg: Double, imperial: Bool) -> String {
    if !imperial { return String(format: "%.0f kg", kg) }
    return String(format: "%.0f lb", kg * 2.2046226218)
}
