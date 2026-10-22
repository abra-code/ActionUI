/*
 Sample JSON for ProgressView:
 {
   "type": "ProgressView",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "value": 0.5,       // Optional: Double for current progress (0.0 to total), defaults to nil for indeterminate
     "total": 1.0,       // Optional: Double for maximum progress, defaults to 1.0 if value is set
     "title": "Loading", // Optional: String for title, defaults to nil
     "progressViewStyle": "linear", // Optional: String ("automatic", "linear", "circular"), defaults to "automatic"
     "actionID": "progress.tap" // Optional: String for action triggered on tap
   }
   // Note: The ProgressView shows an indeterminate spinner if "value" or "total" is missing/invalid, or a determinate bar if both are valid. "progressViewStyle" overrides that: "linear" gives a bar in either state - which is the only way to ask for an indeterminate LINEAR bar - and "circular" gives a spinner or a circular gauge. Platform-specific styling (e.g., .progressViewStyle(.circular) on iOS for indeterminate) is applied in applyModifiers. Baseline View properties (padding, hidden, foregroundStyle, font, background, frame, opacity, cornerRadius, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties).
 }

 Observable state (via getElementState / setElementState):
   states["progress"] Double?         Current progress (0.0 – total). Overrides the initial JSON "value"
                                      property at runtime. Set to nil to revert to indeterminate.
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension ProgressView {
    /// ProgressView's properties, parsed from the raw dictionary. Built at the start of every render.
    struct Props: Sendable {
        enum Style: String, Sendable, CaseIterable {
            case automatic, linear, circular
        }

        /// The progress; nil when absent, not a number or negative (indeterminate).
        var value: Double?
        /// The full amount; nil when absent, not a number or not positive. The renderer uses 1.0
        /// when it is nil and there is a progress value.
        var total: Double?
        var title: String?
        var style: Style?
        var actionID: String?

        init(_ properties: [String: Any]) {
            value = properties.double(forKey: "value").flatMap { $0 >= 0 ? $0 : nil }
            total = properties.double(forKey: "total").flatMap { $0 > 0 ? $0 : nil }
            title = properties["title"] as? String
            style = (properties["progressViewStyle"] as? String).flatMap(Style.init(rawValue:))
            actionID = properties["actionID"] as? String
        }
    }

    /// The progress shown with its total, nil when indeterminate: states["progress"], which a host
    /// sets at run time, else the value; the total is 1.0 when not given. A progress above the total
    /// is indeterminate too.
    static func determinateProgress(_ model: ViewModel, _ props: Props) -> (value: Double, total: Double)? {
        guard let value = model.states.double(forKey: "progress") ?? initialValue(model) as? Double else { return nil }
        let total = props.total ?? 1.0
        return value <= total ? (value, total) : nil
    }

    /// The user tapped the progress view: fires actionID.
    @MainActor
    static func userTapped(element: any ActionUIElementBase, windowUUID: String, props: Props) {
        guard let actionID = props.actionID else { return }
        ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0)
    }
}

struct ProgressView: ActionUIElementSpec {
    static var initialStates: (ViewModel) -> [String: Any] = { model in model.states }
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = nil
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = nil
    static var insertableContainers: [String: ContainerShape]? = nil

    static var valueType: Any.Type = Double?.self

    static var initialValue: (ViewModel) -> Any? = { model in
        if let initialValue = model.value as? Double {
            return initialValue
        }
        return Props(model.properties).value
    }
}
