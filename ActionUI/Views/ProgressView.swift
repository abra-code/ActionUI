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
    
    static var validateProperties: ([String: Any]) -> [String: Any] = { properties in
        var validatedProperties = properties
        
        if let value = validatedProperties["value"] as? Double, value >= 0 {
            validatedProperties["value"] = value
        } else if validatedProperties["value"] != nil {
            print("Warning: ProgressView value must be a non-negative Double; defaulting to nil")
            validatedProperties["value"] = nil
        }
        
        if let total = validatedProperties["total"] as? Double, total > 0 {
            validatedProperties["total"] = total
        } else if validatedProperties["value"] != nil {
            validatedProperties["total"] = 1.0
        } else if validatedProperties["total"] != nil {
            print("Warning: ProgressView total must be a positive Double; defaulting to nil")
            validatedProperties["total"] = nil
        }
        
        if validatedProperties["label"] != nil, !(validatedProperties["label"] is String) {
            print("Warning: ProgressView label must be a String; defaulting to nil")
            validatedProperties["label"] = nil
        }
        
        return validatedProperties
    }
    
    static var buildView: (any ActionUIElement, Binding<[Int: Any]>, String, [String: Any]) -> any SwiftUI.View = { (element: any ActionUIElement, state: Binding<[Int: Any]>, windowUUID: String, properties: [String: Any]) -> any SwiftUI.View in
        let value: Double? = properties["value"] as? Double
        let total: Double? = properties["total"] as? Double
        let label: String? = properties["label"] as? String
        let actionID: String? = properties["actionID"] as? String
        
        var newState: [String: Any] = (state.wrappedValue[element.id] as? [String: Any]) ?? [:]
        var viewSpecificState: [String: Any] = [:]
        if newState["value"] == nil, let value = value {
            viewSpecificState["value"] = value
        }
        if !viewSpecificState.isEmpty {
            state.wrappedValue[element.id] = newState.merging(viewSpecificState, uniquingKeysWith: { _, new in new })
        }
        
        let currentValue: Double? = (state.wrappedValue[element.id] as? [String: Any])?["value"] as? Double ?? value
        
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
    
    static var applyModifiers: (any SwiftUI.View, [String: Any]) -> AnyView = { view, properties in
        var modifiedView = view
        #if canImport(UIKit)
        if properties["value"] == nil || properties["total"] == nil {
            modifiedView = modifiedView.progressViewStyle(.circular)
        }
        #endif
        return AnyView(modifiedView)
    }
}
