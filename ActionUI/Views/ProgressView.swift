/*
 Sample JSON for ProgressView:
 {
   "type": "ProgressView",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "value": 0.5,       // Optional: Double for current progress (0.0 to total), defaults to nil for indeterminate
     "total": 1.0,       // Optional: Double for maximum progress, defaults to 1.0 if value is set
     "label": "Loading", // Optional: String for label, defaults to nil
     "actionID": "progress.tap" // Optional: String for action triggered on tap
   }
   // Note: The ProgressView shows an indeterminate spinner if "value" or "total" is missing/invalid, or a determinate bar if both are valid. Platform-specific styling (e.g., .progressViewStyle(.circular) on iOS for indeterminate) is applied in applyModifiers. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ProgressView: ActionUIViewConstruction {
    static var valueType: Any.Type { Double?.self }
    
    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        var validatedProperties = properties
        
        if let value = validatedProperties.double(forKey: "value"), value >= 0 {
           //
        } else if validatedProperties["value"] != nil {
            logger.log("ProgressView value must be a non-negative Double; defaulting to nil", .warning)
            validatedProperties["value"] = nil
        }
        
        if let total = validatedProperties.double(forKey: "total"), total > 0 {
            //
        } else if validatedProperties["value"] != nil {
            validatedProperties["total"] = 1.0
        } else if validatedProperties["total"] != nil {
            logger.log("ProgressView total must be a positive Double; defaulting to nil", .warning)
            validatedProperties["total"] = nil
        }
        
        if validatedProperties["label"] != nil, !(validatedProperties["label"] is String) {
            logger.log("ProgressView label must be a String; defaulting to nil", .warning)
            validatedProperties["label"] = nil
        }
        
        return validatedProperties
    }
    
    static var buildView: (any ActionUIElement, Binding<[Int: Any]>, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, state, windowUUID, properties, logger in
        let value: Double? = properties.double(forKey: "value")
        let total: Double? = properties.double(forKey: "total")
        let label: String? = properties["label"] as? String
        let actionID: String? = properties["actionID"] as? String
        
        var newState: [String: Any] = (state.wrappedValue[element.id] as? [String: Any]) ?? [:]
        if newState["value"] == nil, let value = value {
            newState["value"] = value
            state.wrappedValue[element.id] = newState
        }
        
        let currentValue: Double? = newState.double(forKey: "value") ?? value
        
        let progressView: any SwiftUI.View
        if let value = currentValue, let total = total, value <= total {
            progressView = label != nil ?
                SwiftUI.ProgressView(label!, value: value, total: total) :
                SwiftUI.ProgressView(value: value, total: total)
        } else {
            progressView = label != nil ?
                SwiftUI.ProgressView(label!) :
                SwiftUI.ProgressView()
        }
        
        return progressView
            .onTapGesture {
                if let actionID = actionID {
                    Task { @MainActor in
                        ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0)
                    }
                }
            }
    }
    
    static var applyModifiers: (any SwiftUI.View, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, properties, logger in
        var modifiedView = view
        #if canImport(UIKit)
        if properties["value"] == nil || properties["total"] == nil {
            modifiedView = modifiedView.progressViewStyle(.circular)
        }
        #endif
        return modifiedView
    }
}
