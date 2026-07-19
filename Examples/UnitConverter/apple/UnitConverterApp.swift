//  UnitConverter - ActionUI Example (shared-C edition)
//
//  The distinctive thing about this app: the conversion MATH is not in Swift.
//  It lives in one C file, shared/c/convert.c, compiled here as the `ConvertC`
//  Clang module (see apple/ConvertC/) and imported below. The exact same .c is
//  compiled by the Android NDK build, so iOS, macOS, and Android return bit-for-
//  bit identical numbers. The Swift host stays thin: it only loads the JSON,
//  registers handlers, reads inputs, and calls aui_convert.
//
//  A host does the same three things on every platform:
//    (1) load + present the shared JSON (shared/UnitConverter.json),
//    (2) register handlers for the actionIDs the JSON fires,
//    (3) read inputs by id, call the shared C function, write the result by id.

import SwiftUI
import ActionUI
import ActionUISwiftAdapter
import ConvertC   // the shared C brain: provides aui_convert(...) + the unit enums

@main
struct UnitConverterApp: App {

    init() {
        // (2) Two actionIDs. "unit.recompute" fires from the amount field and the
        // from/to pickers; "unit.category" fires from the segmented category picker
        // and additionally snaps both unit pickers to that category's first unit.
        ActionUISwift.registerActionHandler(actionID: "unit.recompute") { _, windowUUID, _, _, _ in
            MainActor.assumeIsolated { recompute(windowUUID) }
        }
        ActionUISwift.registerActionHandler(actionID: "unit.category") { _, windowUUID, _, _, _ in
            MainActor.assumeIsolated { categoryChanged(windowUUID) }
        }
    }

    var body: some Scene {
        WindowGroup { RootView() }
    }
}

private struct RootView: View {
    @State private var windowUUID = UUID().uuidString

    var body: some View {
        // (1) Load the shared JSON from the app bundle and render it natively.
        if let url = Bundle.main.url(forResource: "UnitConverter", withExtension: "json") {
            AnyView(ActionUISwift.loadView(from: url, windowUUID: windowUUID, isContentView: true))
        } else {
            Text("UnitConverter.json missing from the app bundle")
        }
    }
}

// MARK: - Tag <-> C-enum mapping
//
// The from/to picker tags are "L0".."L5" (length), "M0".."M3" (mass),
// "T0".."T2" (temperature). The leading letter is the category; the trailing
// integer is the unit index WITHIN that category - exactly the enum values in
// shared/c/convert.h. So mapping a tag to (category, unit) is pure string work.

private func categoryIndex(forTag tag: String) -> Int32? {
    switch tag.first {
    case "L": return Int32(AUI_CAT_LENGTH.rawValue)
    case "M": return Int32(AUI_CAT_MASS.rawValue)
    case "T": return Int32(AUI_CAT_TEMPERATURE.rawValue)
    default:  return nil
    }
}

private func unitIndex(forTag tag: String) -> Int32? {
    guard tag.count >= 2 else { return nil }
    return Int32(tag.dropFirst())
}

// Each category opens on a sensible, non-trivial conversion rather than unit -> same
// unit: meter -> foot, kilogram -> pound, Celsius -> Fahrenheit. categoryChanged
// applies this pair on every switch, and the category picker's onAppearActionID
// fires categoryChanged once on appear to apply the initial (length) pair too.
private func defaultTags(forCategory category: String) -> (from: String, to: String) {
    switch category {
    case "mass":        return ("M0", "M2")   // kilogram -> pound
    case "temperature": return ("T0", "T1")   // Celsius -> Fahrenheit
    default:            return ("L0", "L4")   // meter -> foot ("length")
    }
}

// The from/to unit menus are populated per category, so a conversion is always
// within one category (no nonsensical length -> temperature). Tags mirror the enum
// indices in shared/c/convert.h. categoryChanged pushes this list into both pickers.
private func unitOptions(forCategory category: String) -> [[String: String]] {
    switch category {
    case "mass":
        return [["title": "kilogram", "tag": "M0"],
                ["title": "gram",     "tag": "M1"],
                ["title": "pound",    "tag": "M2"],
                ["title": "ounce",    "tag": "M3"]]
    case "temperature":
        return [["title": "Celsius",    "tag": "T0"],
                ["title": "Fahrenheit", "tag": "T1"],
                ["title": "Kelvin",     "tag": "T2"]]
    default: // "length"
        return [["title": "meter",      "tag": "L0"],
                ["title": "centimeter", "tag": "L1"],
                ["title": "kilometer",  "tag": "L2"],
                ["title": "inch",       "tag": "L3"],
                ["title": "foot",       "tag": "L4"],
                ["title": "mile",       "tag": "L5"]]
    }
}

// (3) The logic. @MainActor because the value bridge is main-actor isolated. The
// only computation is the single call into the shared C function.
@MainActor
private func recompute(_ windowUUID: String) {
    let raw      = ActionUISwift.getElementValue(windowUUID: windowUUID, viewID: 10) as? String ?? ""
    let fromTag  = ActionUISwift.getElementValue(windowUUID: windowUUID, viewID: 20) as? String ?? "L0"
    let toTag    = ActionUISwift.getElementValue(windowUUID: windowUUID, viewID: 30) as? String ?? "L0"

    guard let n = Double(raw.trimmingCharacters(in: .whitespaces)) else {
        ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 40, value: "")
        return
    }
    // Both units must be in the same category; if not, prompt the user.
    guard let cat = categoryIndex(forTag: fromTag),
          categoryIndex(forTag: toTag) == cat,
          let fromU = unitIndex(forTag: fromTag),
          let toU = unitIndex(forTag: toTag) else {
        ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 40, value: "-")
        return
    }

    // The shared C brain does the actual conversion.
    let out = aui_convert(cat, fromU, toU, n)
    ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 40,
                                  value: trimmed(out))
}

// On category change (and once on appear, via the picker's onAppearActionID):
// repopulate both unit pickers with only that category's units (setElementProperty
// "options" - SwiftUI recomposes the Picker off the mutated property), then select the
// category's default from/to pair (which keeps from/to in the same category so a
// conversion is always valid), then recompute. Setting the options before the values
// keeps the new selections inside the fresh list. Both writes are portable across hosts.
@MainActor
private func categoryChanged(_ windowUUID: String) {
    let category = ActionUISwift.getElementValue(windowUUID: windowUUID, viewID: 5) as? String ?? "length"
    let options = unitOptions(forCategory: category)
    ActionUISwift.setElementProperty(windowUUID: windowUUID, viewID: 20, propertyName: "options", value: options)
    ActionUISwift.setElementProperty(windowUUID: windowUUID, viewID: 30, propertyName: "options", value: options)
    let tags = defaultTags(forCategory: category)
    ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 20, value: tags.from)
    ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 30, value: tags.to)
    recompute(windowUUID)
}

// Show a tidy number: integers print whole; otherwise cap at 2 decimals (enough for
// a readable result, and short enough that the result field never wraps and grows).
private func trimmed(_ value: Double) -> String {
    if value == value.rounded() && abs(value) < 1e15 {
        return String(Int64(value))
    }
    var s = String(format: "%.2f", value)
    while s.hasSuffix("0") { s.removeLast() }
    if s.hasSuffix(".") { s.removeLast() }
    return s
}
