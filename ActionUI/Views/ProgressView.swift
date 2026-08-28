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

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ProgressView: ActionUIViewConstruction {
    static var initialStates: (ViewModel) -> [String: Any] = { model in model.states }
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = nil
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = nil
    static var insertableContainers: [String: ContainerShape]? = nil

    static var valueType: Any.Type = Double?.self
    
    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        var validatedProperties = properties
        
        if let value = validatedProperties.double(forKey: "value"), value >= 0.0 {
            //
        } else if validatedProperties["value"] != nil {
            logger.log("ProgressView value must be a non-negative Double; defaulting to nil", .warning)
            validatedProperties["value"] = nil
        }
        
        if let total = validatedProperties.double(forKey: "total"), total > 0.0 {
            //
        } else if validatedProperties["total"] != nil {
            logger.log("ProgressView total must be a positive Double; defaulting to nil", .warning)
            validatedProperties["total"] = nil
        }
        
        if validatedProperties["title"] != nil, !(validatedProperties["title"] is String) {
            logger.log("ProgressView title must be a String; defaulting to nil", .warning)
            validatedProperties["title"] = nil
        }

        // Validate progressViewStyle. Both SwiftUI styles exist on every platform
        // this builds for, so unlike Picker's there is no platform-conditional set.
        if validatedProperties["progressViewStyle"] != nil {
            let validStyles = ["automatic", "linear", "circular"]
            if let style = validatedProperties["progressViewStyle"] as? String {
                if !validStyles.contains(style) {
                    logger.log("ProgressView progressViewStyle '\(style)' must be one of \(validStyles); defaulting to nil", .warning)
                    validatedProperties["progressViewStyle"] = nil
                }
            } else {
                logger.log("ProgressView progressViewStyle must be a String; defaulting to nil", .warning)
                validatedProperties["progressViewStyle"] = nil
            }
        }

        return validatedProperties
    }
    
    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        let initialValue = Self.initialValue(model) as? Double
        let title: String? = properties["title"] as? String
        let actionID: String? = properties["actionID"] as? String

        // The runtime states["progress"] override wins over the initial JSON value.
        let currentValue: Double? = model.states.double(forKey: "progress") ?? initialValue

        // total defaults to 1.0 when a value is present (matching the documented
        // contract and the Android/Web ports); an explicitly invalid total has
        // already been dropped to nil by validateProperties. With no value at all
        // the progress is indeterminate, so total stays nil.
        let total: Double? = properties.double(forKey: "total") ?? (currentValue != nil ? 1.0 : nil)

        let progressView: any SwiftUI.View
        if let value = currentValue, let total = total, value <= total {
            progressView = title != nil ?
            SwiftUI.ProgressView(title!, value: value, total: total) :
            SwiftUI.ProgressView(value: value, total: total)
        } else {
            progressView = title != nil ?
            SwiftUI.ProgressView(title!) :
            SwiftUI.ProgressView()
        }
        
        return progressView
            .onTapGesture {
                if let actionID = actionID {
                    ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0)
                }
            }
    }
    
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, properties, logger in
        var modifiedView = view
        switch properties["progressViewStyle"] as? String {
        case "linear":
            // The only way to ask for an indeterminate LINEAR bar. SwiftUI has
            // one - an indeterminate ProgressView styled .linear animates as a
            // bar - but with no style applied macOS resolves an indeterminate
            // ProgressView to the circular spinner, so a caller that wants a bar
            // of a known width for a phase it cannot measure had no way to say
            // so.
            modifiedView = modifiedView.progressViewStyle(.linear)
        case "circular":
            modifiedView = modifiedView.progressViewStyle(.circular)
        default:
            // "automatic", or nothing asked for: the platform default, which is
            // what this element has always done.
#if canImport(UIKit)
            // Indeterminate (the circular spinner on iOS) when no value is supplied;
            // a missing total no longer implies indeterminate — it defaults to 1.0 in
            // buildView when a value is present.
            if properties["value"] == nil {
                modifiedView = modifiedView.progressViewStyle(.circular)
            }
#endif
            break
        }
        return modifiedView
    }
    
    static var initialValue: (ViewModel) -> Any? = { model in
        if let initialValue = model.value as? Double {
            return initialValue
        }
        return model.validatedProperties.double(forKey: "value")
    }
}
