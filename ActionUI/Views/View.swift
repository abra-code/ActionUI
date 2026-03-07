// Sources/Views/View.swift
/*
 Sample JSON for View (base structure for all views):
 {
   "type": "View",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "padding": 10.0,      // Optional: Double for padding around the view, string "default" or EdgeInsets dictionary {"top": 10, "bottom": 10, "leading": 5, "trailing": 5}
     "hidden": false,      // Optional: Boolean to hide the view
     "foregroundStyle": "blue", // Optional: SwiftUI color (e.g., "red", "blue") or semantic style for text/content tint, resolved via foregroundStyle
     "font": "body",       // Optional: SwiftUI font role (e.g., "title", "body") for text content
     "background": "white", // Optional: SwiftUI color (e.g., "red", "blue"), hex (e.g., "#FF0000"), or semantic style for background, resolved via background
     "frame": {            // Optional: Dictionary defining view size, supports two mutually exclusive forms
       // Fixed Frame Form:
       "width": 100.0,     // Optional: Double for fixed width
       "height": 100.0,    // Optional: Double for fixed height
       "alignment": "center" // Optional: String ("leading", "center", "trailing", "top", "bottom", "topLeading", "topTrailing", "bottomLeading", "bottomTrailing"), defaults to "center"
       // OR Flexible Frame Form:
       "minWidth": 50.0,   // Optional: Double for minimum width
       "idealWidth": 100.0, // Optional: Double for ideal width
       "maxWidth": 200.0,  // Optional: Double for maximum width
       "minHeight": 50.0,  // Optional: Double for minimum height
       "idealHeight": 100.0, // Optional: Double for ideal height
       "maxHeight": 200.0, // Optional: Double for maximum height
       "alignment": "center" // Optional: String ("leading", "center", "trailing", "top", "bottom", "topLeading", "topTrailing", "bottomLeading", "bottomTrailing"), defaults to "center"
     },
     "offset": {           // Optional: Dictionary for relative positioning
       "x": 10.0,          // Optional: Double for horizontal offset
       "y": -5.0           // Optional: Double for vertical offset
     },
     "opacity": 1.0,       // Optional: Double (0.0 to 1.0) for view transparency
     "cornerRadius": 5.0,  // Optional: Double for rounded corners
     "actionID": "view.action", // Optional: String for action identifier
     "valueChangeActionID": "view.valueChanged", // Optional: String for action triggered on any value change initiated by user
     "openURLActionID": "view.openURL", // Optional: String for action identifier triggered on open URL (via .onOpenURL modifier)
     "onAppearActionID": "view.onAppear", // Optional: String for action identifier triggered on view appear (via .onAppear modifier)
     "onDisappearActionID": "view.onDisappear", // Optional: String for action identifier triggered on view disappear (via .onDisappear modifier)
     "keyboardShortcut": { // Optional: Dictionary for keyboard shortcut, supports key with array of modifiers
       "key": "a",         // Required: String for KeyEquivalent (single character like "a" or special key like "return", "space", "upArrow")
       "modifiers": ["command", "shift"] // Optional: Array of strings for modifiers (e.g., ["command", "shift"]), defaults to ["command"], must contain unique elements
     },
     "controlSize": "regular", // Optional: "mini", "small", "regular", "large", "extraLarge"; defaults to none (system default)
     "disabled": false,     // Optional: Boolean to disable user interaction
     "accessibilityLabel": "View", // Optional: Accessibility label for VoiceOver
     "accessibilityHint": "Base view", // Optional: Accessibility hint for VoiceOver
     "accessibilityHidden": false, // Optional: Boolean to hide view from VoiceOver
     "accessibilityIdentifier": "view_1", // Optional: String for UI testing identifier
     "shadow": {           // Optional: Dictionary for shadow styling
       "color": "black",   // Optional: SwiftUI color or hex, defaults to black
       "radius": 5.0,      // Optional: Double for shadow radius
       "x": 0.0,           // Optional: Double for x-offset
       "y": 2.0            // Optional: Double for y-offset
     },
     "border": {           // Optional: Dictionary for border styling
       "color": "blue",   // Optional: SwiftUI color or hex, defaults to black
       "width": 1.0       // Optional: Double for border width, defaults to 1.0
     },
     "navigationSplitViewColumnWidth": {     // Optional – only meaningful when this view is used as sidebar/content/detail in NavigationSplitView
       "ideal": 360.0,                       // Required: preferred column width (Double) – must be provided
       "min": 280.0,                         // Optional: minimum allowed width
       "max": 480.0                          // Optional: maximum allowed width
     },
     "navigationSplitViewColumnWidth": 400.0, // Number – fixed column width
   }
 }

 NOTE:
 Supported semantic styles for foregroundStyle/background:
   - "background", "foreground", "primary", "secondary", "tertiary", "quaternary", "separator", "placeholder"
 Supported named colors:
   - "red", "blue", "green", "yellow", "orange", "purple", "pink", "mint", "teal", "cyan", "indigo", "brown", "gray", "black", "white", "clear", "accentcolor"
 You can also use hex color strings (e.g., "#FF0000", "#FF000080")

 Supported modifiers for keyboardShortcut:
   - "command", "shift", "option", "control", "capsLock"
   - Must be unique within the array; duplicates are ignored with a warning

 Supported keys for keyboardShortcut:
   - Single character (e.g., "a", "1")
   - Special keys: "upArrow", "downArrow", "leftArrow", "rightArrow", "escape", "delete", "deleteForward", "home", "end", "pageUp", "pageDown", "clear", "tab", "space", "return"

 Frame Specification Note:
 The frame dictionary supports two mutually exclusive forms:
 - Fixed Frame: Uses "width" and/or "height" (both optional) with an optional "alignment". At least one of width or height should be specified for the frame to take effect.
 - Flexible Frame: Uses "minWidth", "idealWidth", "maxWidth", "minHeight", "idealHeight", "maxHeight" (at least one required) with an optional "alignment".
 Mixing keys from both forms (e.g., "width" with "minWidth") is invalid and will result in the frame being ignored with a warning.
 Invalid types for any frame dimension will result in the entire frame being ignored.

 navigationSplitViewColumnWidth notes:
 - "ideal" is required in dictionary form to match SwiftUI API.
 - Modifier is ignored unless view is used inside NavigationSplitView column.
 - System tries to respect values, but macOS users can still drag divider beyond min/max in some situations.
*/

import SwiftUI

struct View: ActionUIViewConstruction {
    static var valueType: Any.Type { Void.self }
    
    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        var validatedProperties = properties
        
        // Validate padding
        if let padding = properties["padding"] {
            if properties.cgFloat(forKey: "padding") != nil {
                // Valid numeric value, keep as is
            } else if let paddingDict = padding as? [String: Any] {
                let top = paddingDict.cgFloat(forKey: "top")
                let leading = paddingDict.cgFloat(forKey: "leading")
                let bottom = paddingDict.cgFloat(forKey: "bottom")
                let trailing = paddingDict.cgFloat(forKey: "trailing")
                if top != nil || leading != nil || bottom != nil || trailing != nil {
                    var validPadding: [String: Any] = [:]
                    if let top = top { validPadding["top"] = top }
                    if let leading = leading { validPadding["leading"] = leading }
                    if let bottom = bottom { validPadding["bottom"] = bottom }
                    if let trailing = trailing { validPadding["trailing"] = trailing }
                    validatedProperties["padding"] = validPadding
                } else {
                    logger.log("Invalid padding dictionary: all values must be numeric, ignoring", .warning)
                    validatedProperties["padding"] = nil
                }
            } else if let paddingStr = padding as? String, paddingStr.lowercased() == "default" {
                // Valid string value, keep as is
            } else {
                logger.log("Invalid type for padding: expected numeric, String ('default'), or [String: Any], got \(type(of: padding)), ignoring", .warning)
                validatedProperties["padding"] = nil
            }
        }
        
        // Validate hidden
        if let hidden = properties["hidden"], !(hidden is Bool) {
            logger.log("Invalid type for hidden: expected Bool, got \(type(of: hidden)), ignoring", .warning)
            validatedProperties["hidden"] = nil
        }
        
        // Validate foregroundStyle
        if let foregroundStyle = properties["foregroundStyle"], !(foregroundStyle is String) {
            logger.log("Invalid type for foregroundStyle: expected String, got \(type(of: foregroundStyle)), ignoring", .warning)
            validatedProperties["foregroundStyle"] = nil
        }
        
        // Validate font
        if let font = properties["font"], !(font is String) {
            logger.log("Invalid type for font: expected String, got \(type(of: font)), ignoring", .warning)
            validatedProperties["font"] = nil
        }
        
        // Validate background
        if let background = properties["background"], !(background is String) {
            logger.log("Invalid type for background: expected String, got \(type(of: background)), ignoring", .warning)
            validatedProperties["background"] = nil
        }
        
        // Validate frame
        if let frame = properties["frame"] {
            if let frameDict = frame as? [String: Any] {
                var validFrame: [String: Any] = [:]
                var isFixedFrame = false
                var isFlexibleFrame = false
                
                // Check for fixed frame keys
                let fixedFrameKeys = ["width", "height"]
                let hasFixedFrameKeys = fixedFrameKeys.contains { frameDict[$0] != nil }
                
                // Check for flexible frame keys
                let flexibleFrameKeys = ["minWidth", "idealWidth", "maxWidth", "minHeight", "idealHeight", "maxHeight"]
                let hasFlexibleFrameKeys = flexibleFrameKeys.contains { frameDict[$0] != nil }
                
                // Validate mutual exclusivity
                if hasFixedFrameKeys && hasFlexibleFrameKeys {
                    logger.log("Frame dictionary mixes fixed frame keys (\(fixedFrameKeys)) with flexible frame keys (\(flexibleFrameKeys)), ignoring", .warning)
                    validatedProperties["frame"] = nil
                } else if hasFixedFrameKeys {
                    isFixedFrame = true
                    var isValid = true
                    if let width = frameDict.cgFloat(forKey: "width") {
                        validFrame["width"] = width
                    } else if frameDict["width"] != nil {
                        logger.log("Invalid type for frame.width: expected numeric, got \(type(of: frameDict["width"]!)), ignoring frame", .warning)
                        isValid = false
                    }
                    
                    if let height = frameDict.cgFloat(forKey: "height") {
                        validFrame["height"] = height
                    } else if frameDict["height"] != nil {
                        logger.log("Invalid type for frame.height: expected numeric, got \(type(of: frameDict["height"]!)), ignoring frame", .warning)
                        isValid = false
                    }
                    
                    if !isValid {
                        validatedProperties["frame"] = nil
                    }
                } else if hasFlexibleFrameKeys {
                    isFlexibleFrame = true
                    var isValid = true
                    if let minWidth = frameDict.cgFloat(forKey: "minWidth") {
                        validFrame["minWidth"] = minWidth
                    } else if frameDict["minWidth"] != nil {
                        logger.log("Invalid type for frame.minWidth: expected numeric, got \(type(of: frameDict["minWidth"]!)), ignoring frame", .warning)
                        isValid = false
                    }
                    
                    if let idealWidth = frameDict.cgFloat(forKey: "idealWidth") {
                        validFrame["idealWidth"] = idealWidth
                    } else if frameDict["idealWidth"] != nil {
                        logger.log("Invalid type for frame.idealWidth: expected numeric, got \(type(of: frameDict["idealWidth"]!)), ignoring frame", .warning)
                        isValid = false
                    }
                    
                    if let maxWidth = frameDict.cgFloat(forKey: "maxWidth") {
                        validFrame["maxWidth"] = maxWidth
                    } else if frameDict["maxWidth"] != nil {
                        logger.log("Invalid type for frame.maxWidth: expected numeric, got \(type(of: frameDict["maxWidth"]!)), ignoring frame", .warning)
                        isValid = false
                    }
                    
                    if let minHeight = frameDict.cgFloat(forKey: "minHeight") {
                        validFrame["minHeight"] = minHeight
                    } else if frameDict["minHeight"] != nil {
                        logger.log("Invalid type for frame.minHeight: expected numeric, got \(type(of: frameDict["minHeight"]!)), ignoring frame", .warning)
                        isValid = false
                    }
                    
                    if let idealHeight = frameDict.cgFloat(forKey: "idealHeight") {
                        validFrame["idealHeight"] = idealHeight
                    } else if frameDict["idealHeight"] != nil {
                        logger.log("Invalid type for frame.idealHeight: expected numeric, got \(type(of: frameDict["idealHeight"]!)), ignoring frame", .warning)
                        isValid = false
                    }
                    
                    if let maxHeight = frameDict.cgFloat(forKey: "maxHeight") {
                        validFrame["maxHeight"] = maxHeight
                    } else if frameDict["maxHeight"] != nil {
                        logger.log("Invalid type for frame.maxHeight: expected numeric, got \(type(of: frameDict["maxHeight"]!)), ignoring frame", .warning)
                        isValid = false
                    }
                    
                    if !isValid {
                        validatedProperties["frame"] = nil
                    }
                }
                
                // Validate alignment for either frame type or standalone alignment
                if (isFixedFrame || isFlexibleFrame || frameDict["alignment"] != nil) && validatedProperties["frame"] != nil {
                    if let alignment = frameDict["alignment"] as? String {
                        let validAlignments = ["leading", "center", "trailing", "top", "bottom", "topLeading", "topTrailing", "bottomLeading", "bottomTrailing"]
                        if validAlignments.contains(alignment) {
                            validFrame["alignment"] = alignment
                        } else {
                            logger.log("Invalid value for frame.alignment: expected one of \(validAlignments), got \(alignment), ignoring alignment", .warning)
                        }
                    } else if frameDict["alignment"] != nil {
                        logger.log("Invalid type for frame.alignment: expected String, got \(type(of: frameDict["alignment"]!)), ignoring alignment", .warning)
                    }
                    if !validFrame.isEmpty {
                        validatedProperties["frame"] = validFrame
                    } else if frameDict["alignment"] != nil {
                        // Allow frame with only alignment
                        validatedProperties["frame"] = ["alignment": frameDict["alignment"]!]
                    } else {
                        validatedProperties["frame"] = nil
                    }
                }
            } else {
                logger.log("Invalid type for frame: expected [String: Any], got \(type(of: frame)), ignoring", .warning)
                validatedProperties["frame"] = nil
            }
        }
        
        // Validate offset
        if let offset = properties["offset"] {
            if let offsetDict = offset as? [String: Any] {
                var validOffset: [String: Any] = [:]
                var isValid = true
                
                if let x = offsetDict.cgFloat(forKey: "x") {
                    validOffset["x"] = x
                } else if offsetDict["x"] != nil {
                    logger.log("Invalid type for offset.x: expected numeric, got \(type(of: offsetDict["x"]!)), ignoring offset", .warning)
                    isValid = false
                }
                
                if let y = offsetDict.cgFloat(forKey: "y") {
                    validOffset["y"] = y
                } else if offsetDict["y"] != nil {
                    logger.log("Invalid type for offset.y: expected numeric, got \(type(of: offsetDict["y"]!)), ignoring offset", .warning)
                    isValid = false
                }
                
                if isValid && !validOffset.isEmpty {
                    validatedProperties["offset"] = validOffset
                } else {
                    logger.log("Invalid offset dictionary, ignoring", .warning)
                    validatedProperties["offset"] = nil
                }
            } else {
                logger.log("Invalid type for offset: expected [String: Any], got \(type(of: offset)), ignoring", .warning)
                validatedProperties["offset"] = nil
            }
        }
        
        // Validate opacity
        if let opacity = properties["opacity"] {
            if let value = properties.double(forKey: "opacity"), (0.0...1.0).contains(value) {
                // Valid numeric value in range, keep as is
            } else {
                logger.log("Invalid type or value for opacity: expected numeric between 0.0 and 1.0, got \(type(of: opacity)), ignoring", .warning)
                validatedProperties["opacity"] = nil
            }
        }
        
        // Validate cornerRadius
        if let cornerRadius = properties["cornerRadius"] {
            if properties.cgFloat(forKey: "cornerRadius") == nil {
                logger.log("Invalid type for cornerRadius: expected numeric, got \(type(of: cornerRadius)), ignoring", .warning)
                validatedProperties["cornerRadius"] = nil
            }
        }
        
        // Validate actionID
        if let actionID = properties["actionID"], !(actionID is String) {
            logger.log("Invalid type for actionID: expected String, got \(type(of: actionID)), ignoring", .warning)
            validatedProperties["actionID"] = nil
        }
        
        // Validate valueChangeActionID
        if let valueChangeActionID = properties["valueChangeActionID"], !(valueChangeActionID is String) {
            logger.log("Invalid type for valueChangeActionID: expected String, got \(type(of: valueChangeActionID)), ignoring", .warning)
            validatedProperties["valueChangeActionID"] = nil
        }
        
        // Validate openURLActionID
        if let openURLActionID = properties["openURLActionID"], !(openURLActionID is String) {
            logger.log("Invalid type for openURLActionID: expected String, got \(type(of: openURLActionID)), ignoring", .warning)
            validatedProperties["openURLActionID"] = nil
        }
        
        // Validate onAppearActionID
        if let onAppearActionID = properties["onAppearActionID"], !(onAppearActionID is String) {
            logger.log("Invalid type for onAppearActionID: expected String, got \(type(of: onAppearActionID)), ignoring", .warning)
            validatedProperties["onAppearActionID"] = nil
        }
        
        // Validate onDisappearActionID
        if let onDisappearActionID = properties["onDisappearActionID"], !(onDisappearActionID is String) {
            logger.log("Invalid type for onDisappearActionID: expected String, got \(type(of: onDisappearActionID)), ignoring", .warning)
            validatedProperties["onDisappearActionID"] = nil
        }
        
        // Validate keyboardShortcut
        if let keyboardShortcut = properties["keyboardShortcut"] {
            if let shortcutDict = keyboardShortcut as? [String: Any] {
                var validShortcut: [String: Any] = [:]
                var isValid = false
                
                if let key = shortcutDict["key"] as? String, !key.isEmpty {
                    // Validate key using KeyEquivalentHelper
                    if KeyEquivalentHelper.resolveKeyEquivalent(key, logger: logger) != nil {
                        validShortcut["key"] = key
                        isValid = true
                    } else {
                        logger.log("Invalid key '\(key)' in keyboardShortcut, ignoring keyboardShortcut", .warning)
                    }
                } else {
                    logger.log("Invalid or missing key in keyboardShortcut: expected non-empty String, ignoring keyboardShortcut", .warning)
                }
                
                if let modifiers = shortcutDict["modifiers"] as? [String] {
                    let validModifiers = ["command", "shift", "option", "control", "capsLock"]
                    // Check for uniqueness
                    let uniqueModifiers = Array(Set(modifiers.map { $0.lowercased() }))
                    if uniqueModifiers.count < modifiers.count {
                        logger.log("Duplicate modifiers found in keyboardShortcut.modifiers: \(modifiers), using unique values: \(uniqueModifiers)", .warning)
                    }
                    // Validate each modifier
                    let validModifiersArray = uniqueModifiers.filter { validModifiers.contains($0) }
                    if !validModifiersArray.isEmpty {
                        validShortcut["modifiers"] = validModifiersArray
                    } else {
                        logger.log("Invalid modifiers in keyboardShortcut: expected array of \(validModifiers), got \(modifiers), defaulting to ['command']", .warning)
                        validShortcut["modifiers"] = ["command"]
                    }
                } else if shortcutDict["modifiers"] == nil {
                    // Default to ["command"] if not provided
                    validShortcut["modifiers"] = ["command"]
                } else {
                    logger.log("Invalid type for keyboardShortcut.modifiers: expected [String], got \(type(of: shortcutDict["modifiers"]!)), defaulting to ['command']", .warning)
                    validShortcut["modifiers"] = ["command"]
                }
                
                if isValid {
                    validatedProperties["keyboardShortcut"] = validShortcut
                } else {
                    validatedProperties["keyboardShortcut"] = nil
                }
            } else {
                logger.log("Invalid type for keyboardShortcut: expected [String: Any], got \(type(of: keyboardShortcut)), ignoring", .warning)
                validatedProperties["keyboardShortcut"] = nil
            }
        }
        
        // Validate disabled
        if let disabled = properties["disabled"], !(disabled is Bool) {
            logger.log("Invalid type for disabled: expected Bool, got \(type(of: disabled)), ignoring", .warning)
            validatedProperties["disabled"] = nil
        }
        
        // Validate accessibility properties
        if let accessibilityLabel = properties["accessibilityLabel"], !(accessibilityLabel is String) {
            logger.log("Invalid type for accessibilityLabel: expected String, got \(type(of: accessibilityLabel)), ignoring", .warning)
            validatedProperties["accessibilityLabel"] = nil
        }
        
        if let accessibilityHint = properties["accessibilityHint"], !(accessibilityHint is String) {
            logger.log("Invalid type for accessibilityHint: expected String, got \(type(of: accessibilityHint)), ignoring", .warning)
            validatedProperties["accessibilityHint"] = nil
        }
        
        if let accessibilityHidden = properties["accessibilityHidden"], !(accessibilityHidden is Bool) {
            logger.log("Invalid type for accessibilityHidden: expected Bool, got \(type(of: accessibilityHidden)), ignoring", .warning)
            validatedProperties["accessibilityHidden"] = nil
        }
        
        if let accessibilityIdentifier = properties["accessibilityIdentifier"], !(accessibilityIdentifier is String) {
            logger.log("Invalid type for accessibilityIdentifier: expected String, got \(type(of: accessibilityIdentifier)), ignoring", .warning)
            validatedProperties["accessibilityIdentifier"] = nil
        }
        
        // Validate shadow
        if let shadow = properties["shadow"] {
            if let shadowDict = shadow as? [String: Any] {
                var validShadow: [String: Any] = [:]
                var isValid = true
                
                if let color = shadowDict["color"] as? String {
                    validShadow["color"] = color
                } else if shadowDict["color"] != nil {
                    logger.log("Invalid type for shadow.color: expected String, got \(type(of: shadowDict["color"]!)), ignoring shadow", .warning)
                    isValid = false
                }
                
                if let radius = shadowDict.cgFloat(forKey: "radius") {
                    validShadow["radius"] = radius
                } else if shadowDict["radius"] != nil {
                    logger.log("Invalid type for shadow.radius: expected numeric, got \(type(of: shadowDict["radius"]!)), ignoring shadow", .warning)
                    isValid = false
                }
                
                if let x = shadowDict.cgFloat(forKey: "x") {
                    validShadow["x"] = x
                } else if shadowDict["x"] != nil {
                    logger.log("Invalid type for shadow.x: expected numeric, got \(type(of: shadowDict["x"]!)), ignoring shadow", .warning)
                    isValid = false
                }
                
                if let y = shadowDict.cgFloat(forKey: "y") {
                    validShadow["y"] = y
                } else if shadowDict["y"] != nil {
                    logger.log("Invalid type for shadow.y: expected numeric, got \(type(of: shadowDict["y"]!)), ignoring shadow", .warning)
                    isValid = false
                }
                
                if isValid && !validShadow.isEmpty {
                    validatedProperties["shadow"] = validShadow
                } else {
                    logger.log("Invalid shadow dictionary, ignoring", .warning)
                    validatedProperties["shadow"] = nil
                }
            } else {
                logger.log("Invalid type for shadow: expected [String: Any], got \(type(of: shadow)), ignoring", .warning)
                validatedProperties["shadow"] = nil
            }
        }

        // Validate border
        if let border = properties["border"] {
            if let borderDict = border as? [String: Any] {
                var validBorder: [String: Any] = [:]
                var isValid = true

                if let color = borderDict["color"] as? String {
                    validBorder["color"] = color
                } else if borderDict["color"] != nil {
                    logger.log("Invalid type for border.color: expected String, got \(type(of: borderDict["color"]!)), ignoring border", .warning)
                    isValid = false
                }

                if let width = borderDict.cgFloat(forKey: "width") {
                    validBorder["width"] = width
                } else if borderDict["width"] != nil {
                    logger.log("Invalid type for border.width: expected numeric, got \(type(of: borderDict["width"]!)), ignoring border", .warning)
                    isValid = false
                }

                if isValid && !validBorder.isEmpty {
                    validatedProperties["border"] = validBorder
                } else if isValid {
                    // Empty dict means use defaults
                    validatedProperties["border"] = validBorder
                } else {
                    validatedProperties["border"] = nil
                }
            } else {
                logger.log("Invalid type for border: expected [String: Any], got \(type(of: border)), ignoring", .warning)
                validatedProperties["border"] = nil
            }
        }

        // Validate controlSize
        if let controlSize = properties["controlSize"] {
            if let sizeStr = controlSize as? String {
                let validSizes = ["mini", "small", "regular", "large", "extraLarge"]
                if !validSizes.contains(sizeStr) {
                    logger.log("Invalid controlSize '\(sizeStr)'; expected one of \(validSizes), ignoring", .warning)
                    validatedProperties["controlSize"] = nil
                }
            } else {
                logger.log("Invalid type for controlSize: expected String, got \(type(of: controlSize)), ignoring", .warning)
                validatedProperties["controlSize"] = nil
            }
        }

        if let columnWidthAny = properties["navigationSplitViewColumnWidth"] {
            var validatedValue: Any? = nil
            
            // Case 1: dictionary with explicit range
            if let dict = columnWidthAny as? [String: Any] {
                var temp: [String: Any] = [:]
                var hasIdeal = false
                
                if let ideal = dict.cgFloat(forKey: "ideal"), ideal > 0 {
                    temp["ideal"] = ideal
                    hasIdeal = true
                } else if dict["ideal"] != nil {
                    logger.log("navigationSplitViewColumnWidth.ideal must be positive number", .warning)
                }
                
                if let minVal = dict.cgFloat(forKey: "min"), minVal > 0 {
                    temp["min"] = minVal
                }
                
                if let maxVal = dict.cgFloat(forKey: "max"), maxVal > 0 {
                    temp["max"] = maxVal
                }
                
                if hasIdeal {
                    validatedValue = temp
                } else {
                    logger.log("navigationSplitViewColumnWidth dictionary requires 'ideal' key with positive number", .warning)
                }
            }
            // Case 2: single number: fixed width
            else if let fixed = properties.cgFloat(forKey: "navigationSplitViewColumnWidth"), fixed > 0 {
                validatedValue = fixed
            }

            // Assign only if valid
            if let validatedValue {
                validatedProperties["navigationSplitViewColumnWidth"] = validatedValue
            } else {
                // Explicitly remove / reject invalid value
                validatedProperties["navigationSplitViewColumnWidth"] = nil
                // Optional: log that we discarded it
                logger.log("Discarded invalid navigationSplitViewColumnWidth value", .debug)
            }
        }
        
        return validatedProperties
    }
    
    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        SwiftUI.EmptyView()
    }
    
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, element, windowUUID, properties, logger in
        var modifiedView = view
        
        // Do not handle actionID here; concrete views (e.g., ComboBox, DatePicker) should handle actionID in buildView with specific context (e.g., windowUUID, viewID, viewPartID)
        
        if let padding = properties["padding"] as? [String: Any] {
            modifiedView = modifiedView.padding(EdgeInsets(
                top: padding.cgFloat(forKey: "top") ?? 0.0,
                leading: padding.cgFloat(forKey: "leading") ?? 0.0,
                bottom: padding.cgFloat(forKey: "bottom") ?? 0.0,
                trailing: padding.cgFloat(forKey: "trailing") ?? 0.0
            ))
        } else if let padding = properties.cgFloat(forKey: "padding") {
            modifiedView = modifiedView.padding(padding)
        } else if let padding = properties["padding"] as? String, padding.lowercased() == "default" {
            modifiedView = modifiedView.padding()
        }
        
        if let font = properties["font"] as? String {
            modifiedView = modifiedView.font(FontHelper.resolveFont(font, logger))
        }
        
        // Use foregroundStyle with resolveShapeStyle
        if let foregroundStyle = properties["foregroundStyle"] as? String, let style = ColorHelper.resolveShapeStyle(foregroundStyle) {
            modifiedView = modifiedView.foregroundStyle(style)
        }
        
        if let disabled = properties["disabled"] as? Bool {
            modifiedView = modifiedView.disabled(disabled)
        }
        
        if properties["hidden"] as? Bool == true {
            modifiedView = modifiedView.hidden()
        }
        
        // Use background with resolveShapeStyle
        if let background = properties["background"] as? String, let style = ColorHelper.resolveShapeStyle(background) {
            modifiedView = modifiedView.background(style)
        }
        
        if let frame = properties["frame"] as? [String: Any] {
            let alignment = (frame["alignment"] as? String).flatMap { alignmentString -> Alignment? in
                switch alignmentString {
                case "leading": return .leading
                case "center": return .center
                case "trailing": return .trailing
                case "top": return .top
                case "bottom": return .bottom
                case "topLeading": return .topLeading
                case "topTrailing": return .topTrailing
                case "bottomLeading": return .bottomLeading
                case "bottomTrailing": return .bottomTrailing
                default: return nil
                }
            } ?? .center
            
            // Check for fixed frame keys
            let hasFixedFrameKeys = frame["width"] != nil || frame["height"] != nil
            let hasFlexibleFrameKeys = ["minWidth", "idealWidth", "maxWidth", "minHeight", "idealHeight", "maxHeight"].contains { frame[$0] != nil }
            
            if hasFixedFrameKeys {
                let width = frame.cgFloat(forKey: "width")
                let height = frame.cgFloat(forKey: "height")
                modifiedView = modifiedView.frame(width: width, height: height, alignment: alignment)
            } else if hasFlexibleFrameKeys {
                let minWidth = frame.cgFloat(forKey: "minWidth")
                let idealWidth = frame.cgFloat(forKey: "idealWidth")
                let maxWidth = frame.cgFloat(forKey: "maxWidth")
                let minHeight = frame.cgFloat(forKey: "minHeight")
                let idealHeight = frame.cgFloat(forKey: "idealHeight")
                let maxHeight = frame.cgFloat(forKey: "maxHeight")
                modifiedView = modifiedView.frame(
                    minWidth: minWidth,
                    idealWidth: idealWidth,
                    maxWidth: maxWidth,
                    minHeight: minHeight,
                    idealHeight: idealHeight,
                    maxHeight: maxHeight,
                    alignment: alignment
                )
            } else {
                // Apply frame with only alignment
                modifiedView = modifiedView.frame(alignment: alignment)
            }
        }
        
        if let offset = properties["offset"] as? [String: Any] {
            let x = offset.cgFloat(forKey: "x") ?? 0.0
            let y = offset.cgFloat(forKey: "y") ?? 0.0
            modifiedView = modifiedView.offset(x: x, y: y)
            logger.log("Applied offset: x=\(x), y=\(y)", .debug)
        }
        
        if let opacity = properties.double(forKey: "opacity"), (0.0...1.0).contains(opacity) {
            modifiedView = modifiedView.opacity(opacity)
        }
        
        if let cornerRadius = properties.cgFloat(forKey: "cornerRadius") {
            modifiedView = modifiedView.cornerRadius(cornerRadius)
        }
        
        if let border = properties["border"] as? [String: Any] {
            let color = ColorHelper.resolveColor(border["color"] as? String) ?? .black
            let width = border.cgFloat(forKey: "width") ?? 1.0
            modifiedView = modifiedView.border(color, width: width)
        }

        if let controlSize = properties["controlSize"] as? String {
            switch controlSize {
            case "mini":
                modifiedView = modifiedView.controlSize(.mini)
            case "small":
                modifiedView = modifiedView.controlSize(.small)
            case "regular":
                modifiedView = modifiedView.controlSize(.regular)
            case "large":
                modifiedView = modifiedView.controlSize(.large)
            case "extraLarge":
                modifiedView = modifiedView.controlSize(.extraLarge)
            default:
                break
            }
        }

        if let shadow = properties["shadow"] as? [String: Any] {
            let color = ColorHelper.resolveColor(shadow["color"] as? String) ?? .black
            let radius = shadow.cgFloat(forKey: "radius") ?? 0.0
            let x = shadow.cgFloat(forKey: "x") ?? 0.0
            let y = shadow.cgFloat(forKey: "y") ?? 0.0
            modifiedView = modifiedView.shadow(color: color, radius: radius, x: x, y: y)
        }
        
        // Handle openURLActionID with .onOpenURL modifier
        if let openURLActionID = properties["openURLActionID"] as? String {
            modifiedView = modifiedView.onOpenURL { url in
                Task { @MainActor in
                    ActionUIModel.shared.actionHandler(openURLActionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0, context: url)
                }
            }
        }
        
        // Handle onAppearActionID with .onAppear modifier
        if let onAppearActionID = properties["onAppearActionID"] as? String {
            modifiedView = modifiedView.onAppear {
                Task { @MainActor in
                    ActionUIModel.shared.actionHandler(onAppearActionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0, context: nil)
                }
            }
        }
        
        // Handle onDisappearActionID with .onDisappear modifier
        if let onDisappearActionID = properties["onDisappearActionID"] as? String {
            modifiedView = modifiedView.onDisappear {
                Task { @MainActor in
                    ActionUIModel.shared.actionHandler(onDisappearActionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0, context: nil)
                }
            }
        }
        
        if let columnWidth = properties["navigationSplitViewColumnWidth"] {
            if let dict = columnWidth as? [String: Any],
                let ideal = dict.cgFloat(forKey: "ideal"), ideal > 0 {
                let min = dict.cgFloat(forKey: "min")
                let max = dict.cgFloat(forKey: "max")
                
                modifiedView = modifiedView.navigationSplitViewColumnWidth(
                    min: min,
                    ideal: ideal,
                    max: max
                )
            }
            else if let fixed = properties.cgFloat(forKey: "navigationSplitViewColumnWidth"), fixed > 0 {
                modifiedView = modifiedView.navigationSplitViewColumnWidth(fixed)
            }
        }
        
        // Handle keyboardShortcut
        if let keyboardShortcut = properties["keyboardShortcut"] as? [String: Any] {
            if let keyStr = keyboardShortcut["key"] as? String, !keyStr.isEmpty {
                if let keyEquivalent = KeyEquivalentHelper.resolveKeyEquivalent(keyStr, logger: logger) {
                    let modifiersArray = (keyboardShortcut["modifiers"] as? [String])?.map { $0.lowercased() } ?? ["command"]
                    // Ensure unique modifiers
                    let uniqueModifiers = Array(Set(modifiersArray))
                    if uniqueModifiers.count < modifiersArray.count {
                        logger.log("Duplicate modifiers found in keyboardShortcut.modifiers: \(modifiersArray), using unique values: \(uniqueModifiers)", .warning)
                    }
                    var eventModifiers: EventModifiers = []
                    let validModifiers = ["command", "shift", "option", "control", "capsLock"]
                    for modifier in uniqueModifiers {
                        switch modifier {
                        case "command":
                            eventModifiers.insert(.command)
                        case "shift":
                            eventModifiers.insert(.shift)
                        case "option":
                            eventModifiers.insert(.option)
                        case "control":
                            eventModifiers.insert(.control)
                        case "capsLock":
                            eventModifiers.insert(.capsLock)
                        default:
                            logger.log("Unknown modifier '\(modifier)' in keyboardShortcut.modifiers, ignoring", .warning)
                        }
                    }
                    // Apply keyboard shortcut with computed modifiers
                    modifiedView = modifiedView.keyboardShortcut(keyEquivalent, modifiers: eventModifiers)
                }
            }
        }
        
        if let accessibilityLabel = properties["accessibilityLabel"] as? String {
            modifiedView = AnyView(modifiedView).accessibilityLabel(accessibilityLabel)
        }
        
        if let accessibilityHint = properties["accessibilityHint"] as? String {
            modifiedView = AnyView(modifiedView).accessibilityHint(accessibilityHint)
        }
        
        if let accessibilityHidden = properties["accessibilityHidden"] as? Bool {
            modifiedView = AnyView(modifiedView).accessibilityHidden(accessibilityHidden)
        }
        
        if let accessibilityIdentifier = properties["accessibilityIdentifier"] as? String {
            modifiedView = AnyView(modifiedView).accessibilityIdentifier(accessibilityIdentifier)
        }
        
        return modifiedView
    }
}
