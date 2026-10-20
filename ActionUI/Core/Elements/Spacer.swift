/*
 Sample JSON for Spacer:
 {
   "type": "Spacer",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "minLength": 20.0    // Optional: CGFloat for minimum length
   }
   // Note: These properties are specific to Spacer. Baseline View properties (padding, hidden, foregroundStyle, font, background, frame, opacity, cornerRadius, actionID) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties).
 }
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension Spacer {
    /// Spacer's properties, parsed from the raw dictionary. Built at the start of every render.
    struct Props: Sendable {
        var minLength: Double?

        init(_ properties: [String: Any]) {
            minLength = properties.double(forKey: "minLength")
        }
    }
}

struct Spacer: ActionUIElementSpec {
    static var valueType: Any.Type = Void.self
    static var initialValue: (ViewModel) -> Any? = { model in model.value }
    static var initialStates: (ViewModel) -> [String: Any] = { model in model.states }
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = nil
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = nil
    static var insertableContainers: [String: ContainerShape]? = nil
}
