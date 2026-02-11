// Sources/Views/TabView.swift
/*
 Sample JSON for TabView:
 {
   "type": "TabView",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "selection": 0,     // Optional: Integer for selected tab index (0-based), defaults to 0
     "style": "automatic" // Optional: "automatic" (default), "tabBarOnly", "sidebarAdaptable" (iOS 18+/macOS 15+ only)
   },
   "children": [         // Required: Array of tab configurations with content
     {
       "type": "Tab",
       "properties": {          // Tab configuration (not a view type, just tab metadata)
         "title": "Home",        // Required: String for tab title
         "systemImage": "house", // Optional: String for SF Symbol name
         "assetImage": "myTab",  // Optional: String for asset image name. One of systemImage or assetImage must be provided
         "badge": 5              // Optional: Integer or String for badge display
       },
       "content": {      // Required: Single child view for tab content
         "type": "VStack",
         "properties": { "spacing": 10 },
         "children": [
           { "type": "Text", "properties": { "text": "Home Content" } }
         ]
       }
     },
     {
       "type": "Tab",
       "properties": {
         "title": "Settings",
         "systemImage": "gear",
         "badge": "!"
       },
       "content": {
         "type": "Text",
         "properties": { "text": "Settings Content" }
       }
     }
   ]
   // Note: These properties are specific to TabView. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
   // Note: Each child in "children" is a dictionary with "properties" (tab configuration) and "content" (the actual ActionUIView to display). Tabs are identified by their index (0-based) in the children array.
   // Note: TabView supports "valueChangeActionID" to trigger actions when selection changes programmatically or via user interaction.
   // Note: The "style" property controls the tab view style on iOS 18+/macOS 15+: "automatic" (default platform behavior), "tabBarOnly" (always show tab bar), "sidebarAdaptable" (adaptive sidebar on iPad). On earlier platforms, this property is ignored.
   // Platform compatibility: Uses native SwiftUI.Tab on iOS 18+/macOS 15+, falls back to .tabItem modifier on iOS 17.6/macOS 14.6 for backward compatibility.
 }
*/

import SwiftUI

struct TabView: ActionUIViewConstruction {
    // Design decision: Defines valueType as Int to reflect selected tab index for type-safe state management
    static var valueType: Any.Type { Int.self }
    
    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        var validatedProperties = properties
        
        // Validate selection
        if let selection = properties["selection"] {
            if !(selection is Int) {
                logger.log("TabView selection must be an Integer; defaulting to 0", .warning)
                validatedProperties["selection"] = nil
            }
        }
        
        // Validate style
        if let style = properties["style"] {
            if !(style is String) {
                logger.log("TabView style must be a String; defaulting to 'automatic'", .warning)
                validatedProperties["style"] = nil
            } else if let styleStr = style as? String {
                let validStyles = ["automatic", "tabBarOnly", "sidebarAdaptable"]
                if !validStyles.contains(styleStr) {
                    logger.log("TabView style must be one of \(validStyles); defaulting to 'automatic'", .warning)
                    validatedProperties["style"] = nil
                }
            }
        }
        
        return validatedProperties
    }
    
    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        let children = element.subviews?["children"] as? [any ActionUIElementBase] ?? []
        
        // Get initial selection value
        let initialSelection = Self.initialValue(model) as? Int ?? 0
        
        // Create selection binding
        let selectionBinding = Binding(
            get: { model.value as? Int ?? initialSelection },
            set: { newValue in
                guard model.value as? Int != newValue else {
                    return
                }
                // Use DispatchQueue.main.async to guarantee deferred execution and avoid
                // "publishing changes from within view updates" warning
                DispatchQueue.main.async {
                    model.value = newValue
                    if let valueChangeActionID = properties["valueChangeActionID"] as? String {
                        ActionUIModel.shared.actionHandler(valueChangeActionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0)
                    }
                }
            }
        )
        
        // Use native SwiftUI.Tab on iOS 18+/macOS 15+, fallback to .tabItem on earlier versions
        if #available(iOS 18.0, macOS 15.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *) {
            // Modern TabView with native SwiftUI.Tab
            return SwiftUI.TabView(selection: selectionBinding) {
                let windowModel = ActionUIModel.shared.windowModels[windowUUID]
                
                ForEach(Array(children.enumerated()), id: \.offset) { index, child in
                    // Extract tab metadata
                    let tabConfig = child.properties
                    let title = tabConfig["title"] as? String ?? "Tab \(index + 1)"
                    
                    let assetImage = tabConfig["assetimage"] as? String
                    // one of them is expected to be non-nil. fall back to something
                    let systemImage = tabConfig["systemImage"] as? String ?? ((assetImage == nil) ? "questionmark.square.dashed" : nil)
                    
                    let badge = tabConfig["badge"]
                    
                    // Extract content element
                    if let contentElement = child.subviews?["content"] as? any ActionUIElementBase,
                       let contentModel = windowModel?.viewModels[contentElement.id] {
                        
                        if let systemImage = systemImage {
                            SwiftUI.Tab(title, systemImage: systemImage, value: index) {
                                ActionUIView(element: contentElement, model: contentModel, windowUUID: windowUUID)
                            }
                            .badge(badgeText(badge))
                        } else if let assetImage = assetImage {
                            SwiftUI.Tab(title, image: assetImage, value: index) {
                                ActionUIView(element: contentElement, model: contentModel, windowUUID: windowUUID)
                            }
                            .badge(badgeText(badge))
                        }
                    } else {
                        // Fallback if no content is provided
                        if let systemImage = systemImage {
                            SwiftUI.Tab(title, systemImage: systemImage, value: index) {
                                SwiftUI.EmptyView()
                            }
                            .badge(badgeText(badge))
                        } else if let assetImage = assetImage {
                            SwiftUI.Tab(title, image: assetImage, value: index) {
                                SwiftUI.EmptyView()
                            }
                            .badge(badgeText(badge))
                        }
                    }
                }
            }
        } else {
            // Legacy TabView using .tabItem modifier for iOS 17.6/macOS 14.6 compatibility
            return SwiftUI.TabView(selection: selectionBinding) {
                let windowModel = ActionUIModel.shared.windowModels[windowUUID]
                
                ForEach(Array(children.enumerated()), id: \.offset) { index, child in
                    // Extract tab metadata
                    let tabConfig = child.properties
                    let title = tabConfig["title"] as? String ?? "Tab \(index + 1)"
                    let systemImage = tabConfig["systemImage"] as? String
                    let badge = tabConfig["badge"]
                    
                    // Extract content element
                    if let contentElement = child.subviews?["content"] as? any ActionUIElementBase,
                       let contentModel = windowModel?.viewModels[contentElement.id] {
                        
                        ActionUIView(element: contentElement, model: contentModel, windowUUID: windowUUID)
                            .tabItem {
                                if let systemImage = systemImage {
                                    SwiftUI.Label(title, systemImage: systemImage)
                                } else {
                                    SwiftUI.Text(title)
                                }
                            }
                            .applyBadge(badge)
                            .tag(index)
                    } else {
                        // Fallback if no content is provided
                        SwiftUI.EmptyView()
                            .tabItem {
                                if let systemImage = systemImage {
                                    SwiftUI.Label(title, systemImage: systemImage)
                                } else {
                                    SwiftUI.Text(title)
                                }
                            }
                            .applyBadge(badge)
                            .tag(index)
                    }
                }
            }
        }
    }
    
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, element, windowUUID, properties, logger in
        var modifiedView = view
        
        // Apply tab view style (only available on iOS 18+/macOS 15+)
        if #available(iOS 18.0, macOS 15.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *) {
            if let style = properties["style"] as? String {
                switch style {
                case "tabBarOnly":
                    modifiedView = modifiedView.tabViewStyle(.tabBarOnly)
                case "sidebarAdaptable":
                    modifiedView = modifiedView.tabViewStyle(.sidebarAdaptable)
                default: // "automatic"
                    modifiedView = modifiedView.tabViewStyle(.automatic)
                }
            }
        }
        
        return modifiedView
    }
    
    static var initialValue: (ViewModel) -> Any? = { model in
        if let initialValue = model.value as? Int {
            return initialValue
        }
        return model.validatedProperties["selection"] as? Int ?? 0
    }
}

// MARK: - Badge Helper Extension

private extension SwiftUI.View {
    @ViewBuilder
    func applyBadge(_ badge: Any?) -> some SwiftUI.View {
        if let intBadge = badge as? Int {
            if intBadge > 99 {
                self.badge("99+")
            } else {
                self.badge(intBadge)
            }
        } else if let stringBadge = badge as? String {
            self.badge(stringBadge)
        } else {
            self
        }
    }
}

private func badgeText(_ value: Any?) -> SwiftUI.Text? {
    if let intValue = value as? Int {
        let badgeString = intValue > 99 ? "99+" : "\(intValue)"
        return SwiftUI.Text(badgeString) // Return as Text
    } else if let stringValue = value as? String {
        return !stringValue.isEmpty ? SwiftUI.Text(stringValue) : nil // Return as Text
    }
    return nil // Handle other cases if necessary
}
