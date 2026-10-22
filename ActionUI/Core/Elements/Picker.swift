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
   // Baseline View properties (padding, hidden, foregroundStyle, font, background, frame, opacity,
   // cornerRadius, disabled, etc.) are inherited and applied via ActionUIRegistry.shared.applyModifiers.
 }
 */

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension Picker {
    /// Picker's properties, parsed from the raw dictionary. Built at the start of every render.
    struct Props: Sendable {
        /// "wheel" exists off macOS and "radioGroup" on macOS only; elsewhere the renderer applies
        /// no style for them.
        enum Style: String, Sendable, CaseIterable {
            case menu, segmented, radioGroup, wheel
        }

        struct OptionItem: Identifiable, Equatable, Sendable {
            let title: String
            let tag: String
            var id: String { tag }
        }

        struct OptionSection: Identifiable, Equatable, Sendable {
            let title: String?
            let items: [OptionItem]
            let index: Int
            var id: String { title ?? "_section_\(index)" }
        }

        var title = ""
        /// The options in display order, grouped. A plain list is one section without a title.
        var sections: [OptionSection] = []
        var style: Style?
        var horizontalRadioGroupLayout = false
        var actionID: String?

        /// Every option, whatever its section.
        var options: [OptionItem] {
            sections.flatMap { $0.items }
        }

        init(_ properties: [String: Any]) {
            title = properties["title"] as? String ?? ""
            sections = Self.parseSections(properties["options"])
            style = (properties["pickerStyle"] as? String).flatMap(Style.init(rawValue:))
            horizontalRadioGroupLayout = properties["horizontalRadioGroupLayout"] as? Bool == true
            actionID = properties["actionID"] as? String
        }

        // Dividers inside a SwiftUI Picker content builder are silently ignored (only tagged views are kept).
        // To render a visual separator, we convert {"divider": true} into a Section with nil title.
        // Section { items } (no header) produces a divider line between groups without empty header space.

        private static func parseSections(_ raw: Any?) -> [OptionSection] {
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

                for dict in dicts {
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

                    // Regular option item; one without a title and a tag is skipped
                    guard let title = dict["title"] as? String, !title.isEmpty else { continue }
                    guard let tag = dict["tag"] as? String, !tag.isEmpty else { continue }
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

            // Not [String] or [[String: Any]]: no options
            return []
        }
    }
}

extension Picker {
    /// The user chose an option: stores its tag as the value and fires actionID with the tag as
    /// context, only when it differs from the value.
    @MainActor
    static func userSelected(_ tag: String, element: any ActionUIElementBase, model: ViewModel, windowUUID: String, props: Props) {
        guard model.value as? String != tag else { return }
        model.value = tag
        if let actionID = props.actionID {
            ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0, context: tag)
        }
    }
}

struct Picker: ActionUIElementSpec {
    static var initialStates: (ViewModel) -> [String: Any] = { model in model.states }
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = nil
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = nil
    static var insertableContainers: [String: ContainerShape]? = nil

    static var valueType: Any.Type = String.self

    static var initialValue: (ViewModel) -> Any? = { model in
        if let initialValue = model.value as? String {
            return initialValue
        }
        // Fall back to the first option's tag from the current properties
        return Props(model.properties).options.first?.tag
    }
}
