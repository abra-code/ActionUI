/*
 Sample JSON for ProgressView:
 {
   "type": "ProgressView",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "value": 0.5,       // Optional: Double for current progress (0.0 to total), defaults to nil for indeterminate
     "total": 1.0,       // Optional: Double for maximum progress, defaults to 1.0 if value is set
     "title": "Loading", // Optional: String for title, defaults to nil
     "actionID": "progress.tap" // Optional: String for action triggered on tap
   }
   // Note: The ProgressView shows an indeterminate spinner if "value" or "total" is missing/invalid, or a determinate bar if both are valid. Platform-specific styling (e.g., .progressViewStyle(.circular) on iOS for indeterminate) is applied in applyModifiers. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties).
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
        
        return validatedProperties
    }
    
    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        // TODO: that logic is somewhat faulty in case of indeterminate progress where value is expected to be nil
        let initialValue = Self.initialValue(model) as? Double
        let total: Double? = properties.double(forKey: "total")
        let title: String? = properties["title"] as? String
        let actionID: String? = properties["actionID"] as? String
        
        let currentValue: Double? = model.states.double(forKey: "value") ?? initialValue
        
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
#if canImport(UIKit)
        if properties["value"] == nil || properties["total"] == nil {
            modifiedView = modifiedView.progressViewStyle(.circular)
        }
#endif
        return modifiedView
    }
    
    static var initialValue: (ViewModel) -> Any? = { model in
        if let initialValue = model.value as? Double {
            return initialValue
        }
        return model.validatedProperties.double(forKey: "value")
    }
}
