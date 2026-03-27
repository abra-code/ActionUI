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
       //    Optionally, dictionaries can include {"section": "Group Name"} entries to group items into named sections (works best with "menu" pickerStyle):
       //    [{"section": "Popular"}, {"title": "HTML", "tag": "html"}, {"section": "Other"}, {"title": "XML", "tag": "xml"}]
       //    Items following a section entry belong to that section until the next section entry.
       //    Items before any section entry are placed in an implicit ungrouped section.
       //    A {"divider": true} entry inserts a visual separator line (works best with "menu" pickerStyle).
     "pickerStyle": "menu",      // Optional: "menu" (iOS/macOS/visionOS), "segmented" (iOS/macOS/visionOS), "wheel" (iOS/visionOS only), "radioGroup" (macOS only); no default
     "horizontalRadioGroupLayout": false, // Optional: Bool, applies .horizontalRadioGroupLayout() when pickerStyle is "radioGroup" (macOS only); defaults to false
     "actionID": "picker.selection", // Optional: String for action triggered on user-initiated selection change (inherited from View)
   }
   // Note: actionID is triggered from the binding setter, so it only fires on user-initiated changes
   // (not on programmatic value updates). The selected tag is passed as `context` (Any?) to the handler.
   // Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity,
   // cornerRadius, disabled, etc.) are inherited and applied via ActionUIRegistry.shared.applyModifiers.
 }
 */

import SwiftUI

struct Picker: ActionUIViewConstruction {
    static var initialStates: (ViewModel) -> [String: Any] = { model in model.states }

    static var valueType: Any.Type = String.self
    
    private struct OptionItem: Identifiable {
        let title: String
        let tag: String
        var id: String { tag }
    }

    private struct OptionSection: Identifiable {
        let title: String?
        let items: [OptionItem]
        let index: Int
        var id: String { title ?? "_section_\(index)" }
    }

    // Dividers inside a SwiftUI Picker content builder are silently ignored (only tagged views are kept).
    // To render a visual separator, we convert {"divider": true} into a Section with nil title.
    // Section { items } (no header) produces a divider line between groups without empty header space.

    private static func extractSections(from raw: Any?, logger: (any ActionUILogger)? = nil) -> [OptionSection] {
        guard let raw = raw else { return [] }

        // Format 1: simple array of strings - single ungrouped section
        if let titles = raw as? [String] {
            let items = titles.enumerated().map { index, title in
                OptionItem(title: title, tag: String(index + 1))
            }
            return [OptionSection(title: nil, items: items, index: 0)]
        }

        // Format 2: array of dictionaries, possibly with section/divider entries
        if let dicts = raw as? [[String: Any]] {
            var sections: [OptionSection] = []
            var currentSectionTitle: String? = nil
            var currentItems: [OptionItem] = []
            var hasSections = false

            for (idx, dict) in dicts.enumerated() {
                // Divider entry: flush current items into a section, start a new nil-titled section
                if dict["divider"] as? Bool == true {
                    hasSections = true
                    if !currentItems.isEmpty || !sections.isEmpty {
                        sections.append(OptionSection(title: currentSectionTitle, items: currentItems, index: sections.count))
                        currentItems = []
                    }
                    currentSectionTitle = nil
                    continue
                }

                // Section header entry
                if let sectionTitle = dict["section"] as? String {
                    hasSections = true
                    if !currentItems.isEmpty || !sections.isEmpty {
                        sections.append(OptionSection(title: currentSectionTitle, items: currentItems, index: sections.count))
                        currentItems = []
                    }
                    currentSectionTitle = sectionTitle
                    continue
                }

                // Regular option item
                guard let title = dict["title"] as? String, !title.isEmpty else {
                    logger?.log("Picker options[\(idx)] missing valid 'title'; skipping", .warning)
                    continue
                }
                guard let tag = dict["tag"] as? String, !tag.isEmpty else {
                    logger?.log("Picker options[\(idx)] missing valid 'tag'; skipping", .warning)
                    continue
                }
                currentItems.append(OptionItem(title: title, tag: tag))
            }

            // Flush remaining items
            if hasSections {
                sections.append(OptionSection(title: currentSectionTitle, items: currentItems, index: sections.count))
            } else {
                sections = [OptionSection(title: nil, items: currentItems, index: 0)]
            }

            return sections
        }

        logger?.log("Picker 'options' must be [String] or [[\"title\": String, \"tag\": String]]", .warning)
        return []
    }

    private static func extractOptions(from raw: Any?, logger: (any ActionUILogger)? = nil) -> [OptionItem] {
        return extractSections(from: raw, logger: logger).flatMap { $0.items }
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

        let sections = extractSections(from: properties["options"], logger: logger)
        let allItems = sections.flatMap { $0.items }
        let initialValue = Self.initialValue(model) as? String ?? allItems.first?.tag ?? ""

        // Create a specific binding for the value to ensure reactivity
        let valueBinding = Binding<String>(
            get: { model.value as? String ?? initialValue },
            set: { newValue in
                guard model.value as? String != newValue else {
                    return
                }
                // DispatchQueue.main.async avoids "publishing changes from within view updates" warning.
                // actionID is fired here in the binding setter (not via .onChange) so it only triggers
                // on user interaction. .onChange would also fire on programmatic value changes,
                // which can cause cascading actions and unexpected behavior.
                DispatchQueue.main.async {
                    model.value = newValue
                    if let actionID = properties["actionID"] as? String {
                        ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0, context: newValue)
                    }
                }
            }
        )

        let title = properties["title"] as? String ?? ""
        let useSections = sections.count > 1 || sections.contains { $0.title != nil }

        // Dividers inside a Picker content builder are silently ignored by SwiftUI.
        // Instead, we use Section (with or without a header) to create visual separators.
        // Section { items } with no header renders a divider line without empty header space.
        return SwiftUI.Picker(title, selection: valueBinding) {
            if useSections {
                ForEach(sections) { section in
                    if let sectionTitle = section.title, !sectionTitle.isEmpty {
                        SwiftUI.Section(sectionTitle) {
                            ForEach(section.items) { item in
                                SwiftUI.Text(item.title).tag(item.tag)
                            }
                        }
                    } else {
                        SwiftUI.Section {
                            ForEach(section.items) { item in
                                SwiftUI.Text(item.title).tag(item.tag)
                            }
                        }
                    }
                }
            } else {
                ForEach(allItems) { item in
                    SwiftUI.Text(item.title).tag(item.tag)
                }
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
