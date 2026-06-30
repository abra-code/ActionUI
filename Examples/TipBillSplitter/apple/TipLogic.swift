//  TipBillSplitter - ActionUI Example (shared host logic)
//
//  The recompute is identical on every platform and across BOTH Apple app
//  shells (AppKit on macOS, UIKit on iOS). Both hosts register the single
//  actionID "tip.recompute" and route it here. A host does the same three
//  things everywhere: (1) load + present the shared JSON, (2) register a
//  handler for the actionID the inputs fire, (3) read inputs by integer id,
//  compute, and write the result Texts back by id.
//
//  The id map matches shared/TipBillSplitter.json exactly:
//    10  TextField  bill amount (currency-formatted, fires valueChangeActionID)
//    20  Slider     tip %, 0-30 step 1 (fires valueChangeActionID)
//    30  Stepper    party size, 1-20 step 1 (fires actionID)
//    40  Text       tip amount     (output)
//    50  Text       total          (output)
//    60  Text       per person     (output)
//    80  Text       "Tip: N%"      (output, slider read-out)

import Foundation
import ActionUI
import ActionUISwiftAdapter

// (3) The recompute. @MainActor because it touches the value bridge.
// Both the AppKit and UIKit hosts call this from their action handler.
@MainActor
enum TipBillSplitter {

    // Element ids (keep in sync with shared/TipBillSplitter.json).
    static let billFieldID = 10
    static let tipSliderID = 20
    static let partyStepperID = 30
    static let tipOutID = 40
    static let totalOutID = 50
    static let perPersonOutID = 60
    static let tipLabelID = 80

    static func recompute(_ windowUUID: String) {
        // Bill: the currency TextField stores a String (may carry "$", commas,
        // spaces). Strip everything but digits and the decimal point, then parse.
        let billRaw = ActionUISwift.getElementValue(windowUUID: windowUUID, viewID: billFieldID) as? String ?? ""
        let bill = parseAmount(billRaw)

        // Tip %: the Slider value is a Double.
        let pct = ActionUISwift.getElementValue(windowUUID: windowUUID, viewID: tipSliderID) as? Double ?? 0

        // Party size: the Stepper value is a Double; guard people >= 1.
        let peopleRaw = ActionUISwift.getElementValue(windowUUID: windowUUID, viewID: partyStepperID) as? Double ?? 1
        let people = max(1, Int(peopleRaw.rounded()))

        let tip = bill * pct / 100.0
        let total = bill + tip
        let perPerson = total / Double(people)

        ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: tipOutID, value: currency(tip))
        ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: totalOutID, value: currency(total))
        ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: perPersonOutID, value: currency(perPerson))

        // Mirror the tip % into the read-out label.
        ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: tipLabelID, value: "Tip: \(Int(pct.rounded()))%")
    }

    // Pull a Double out of whatever string the currency field hands back.
    private static func parseAmount(_ raw: String) -> Double {
        let filtered = raw.filter { $0.isNumber || $0 == "." }
        return Double(filtered) ?? 0
    }

    // Format as currency with 2 decimals (e.g. "$12.50").
    private static func currency(_ value: Double) -> String {
        String(format: "$%.2f", value.isFinite ? value : 0)
    }
}
