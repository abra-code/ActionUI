/*
 Sample JSON for Picker:
 {
   "type": "Picker",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "title": "Select Option",    // Optional: String, no default
     "options": [ "One",  "Two", "Three" ] // Required. Two supported formats:
       // 1. With simple array of strings we have titles only. Tags are automatically "1", "2", "3"... (1-based index as String)
       // 2. With array of dictionaries we have explicit control: [{"title": "Sure Thing", "tag": "yes"}, {"title": "Absolutely Not", "tag": "no"}]
     "pickerStyle": "menu",      // Optional: "menu" (iOS/macOS/visionOS), "segmented" (iOS/macOS/visionOS), "wheel" (iOS/visionOS only), "radioGroup" (macOS only); no default
     "horizontalRadioGroupLayout": false, // Optional: Bool, applies .horizontalRadioGroupLayout() when pickerStyle is "radioGroup" (macOS only); defaults to false
     "actionID": "picker.selection", // Optional: String for action triggered on user-initiated selection change (inherited from View)
   }
   // Note: actionID is triggered via onChange for user-initiated changes. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, disabled, etc.) are inherited and applied via ActionUIRegistry.shared.applyModifiers.
   // The selected tag is passed as `context` (Any?) to actionID handler.
 }
 */

import SwiftUI

struct Picker: ActionUIViewConstruction {
    static var valueType: Any.Type { String.self }
    
    private struct OptionItem: Identifiable {
        let title: String
        let tag: String
        var id: String { tag }
    }
    
    private static func extractOptions(from raw: Any?, logger: (any ActionUILogger)? = nil) -> [OptionItem] {
        guard let raw = raw else { return [] }
        
        // Format 1: with simple array of strings we generate 1-based index tags
        if let titles = raw as? [String] {
            return titles.enumerated().map { index, title in
                OptionItem(title: title, tag: String(index + 1))
            }
        }
        
        // Format 2: explicit title/tag dictionaries
        if let dicts = raw as? [[String: Any]] {
            var items: [OptionItem] = []
            for (idx, dict) in dicts.enumerated() {
                guard let title = dict["title"] as? String, !title.isEmpty else {
                    logger?.log("Picker options[\(idx)] missing valid 'title'; skipping", .warning)
                    continue
                }
                guard let tag = dict["tag"] as? String, !tag.isEmpty else {
                    logger?.log("Picker options[\(idx)] missing valid 'tag'; skipping", .warning)
                    continue
                }
                items.append(OptionItem(title: title, tag: tag))
            }
            return items
        }
        
        logger?.log("Picker 'options' must be [String] or [[\"title\": String, \"tag\": String]]", .warning)
        return []
    }
    
    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        var validatedProperties = properties
        
        // Validate options format and remove if invalid
        if let rawOptions = properties["options"] {
            if rawOptions as? [String] == nil && rawOptions as? [[String: Any]] == nil {
                logger.log("Picker 'options' must be [String] or [[\"title\": String, \"tag\": String]]; setting to nil", .warning)
                validatedProperties["options"] = nil
            }
        }
        
        // Validate pickerStyle
#if os(macOS)
        let validStyles = ["menu", "segmented", "radioGroup"]
#else
        let validStyles = ["menu", "segmented", "wheel"]
#endif
        if let style = properties["pickerStyle"] as? String, !validStyles.contains(style) {
            logger.log("Picker style '\(style)' invalid on this platform; setting to nil", .warning)
            validatedProperties["pickerStyle"] = nil
        }
        
        // Validate title
        if let title = properties["title"], !(title is String) {
            logger.log("Picker 'title' must be String; setting to nil", .warning)
            validatedProperties["title"] = nil
        }
        
        return validatedProperties
    }
    
    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        
        let items = extractOptions(from: properties["options"], logger: logger)
        let initialValue = Self.initialValue(model) as? String ?? items.first?.tag ?? ""
        
        // Create a specific binding for the value to ensure reactivity
        let valueBinding = Binding<String>(
            get: { model.value as? String ?? initialValue },
            set: { newValue in
                guard model.value as? String != newValue else {
                    return
                }
                // Use DispatchQueue.main.async to guarantee deferred execution and avoid
                // "publishing changes from within view updates" warning
                DispatchQueue.main.async {
                    model.value = newValue
                }
            }
        )
        
        let title = properties["title"] as? String ?? ""
        let actionID = properties["actionID"] as? String
        
        // Build the Picker with .onChange chained directly – original reliable pattern
        return SwiftUI.Picker(title, selection: valueBinding) {
            ForEach(items) { item in
                SwiftUI.Text(item.title).tag(item.tag)
            }
        }
        .onChange(of: valueBinding.wrappedValue) { _, newValue in
            if let actionID = actionID {
                logger.log("Executing handler for actionID: \(actionID), viewID: \(element.id)", .debug)
                ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0, context: newValue)
            }
        }
    }
    
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, properties, logger in
        var modifiedView = view
        if let style = properties["pickerStyle"] as? String {
            switch style {
            case "wheel":
#if os(macOS)
                logger.log("wheel PickerStyle unavailable on macOS; ignoring", .warning)
#else
                modifiedView = modifiedView.pickerStyle(.wheel)
#endif
            case "menu":
                modifiedView = modifiedView.pickerStyle(.menu)
            case "segmented":
                modifiedView = modifiedView.pickerStyle(.segmented)
            case "radioGroup":
#if os(macOS)
                modifiedView = modifiedView.pickerStyle(.radioGroup)
                if properties["horizontalRadioGroupLayout"] as? Bool == true {
                    modifiedView = modifiedView.horizontalRadioGroupLayout()
                }
#else
                logger.log("radioGroup PickerStyle unavailable on this platform; ignoring", .warning)
#endif
            default:
                break // Should not reach here due to validateProperties
            }
        }
        return modifiedView
    }
    
    static var initialValue: (ViewModel) -> Any? = { model in
        if let initialValue = model.value as? String {
            return initialValue
        }
        // Fall back to the first option's tag from validated properties
        let items = extractOptions(from: model.validatedProperties["options"])
        return items.first?.tag
    }
}
