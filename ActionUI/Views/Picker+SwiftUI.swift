// SwiftUI rendering of Picker; its portable part is in Core/Elements/Picker.swift.

import SwiftUI

extension Picker: ActionUISwiftUIRenderer {
    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        let props = Props(properties)
        let sections = props.sections
        let allItems = props.options
        let initialValue = Self.initialValue(model) as? String ?? allItems.first?.tag ?? ""

        // Create a specific binding for the value to ensure reactivity
        let valueBinding: Binding<String> = mainActorBinding(
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
                    Picker.userSelected(newValue, element: element, model: model, windowUUID: windowUUID, props: props)
                }
            }
        )

        let title = props.title
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
        let props = Props(properties)
        switch props.style {
        case .wheel:
#if os(macOS)
            break // not on this platform: no style, as for an unknown name
#else
            modifiedView = modifiedView.pickerStyle(.wheel)
#endif
        case .menu:
            modifiedView = modifiedView.pickerStyle(.menu)
        case .segmented:
            modifiedView = modifiedView.pickerStyle(.segmented)
        case .radioGroup:
#if os(macOS)
            modifiedView = modifiedView.pickerStyle(.radioGroup)
            if props.horizontalRadioGroupLayout {
                modifiedView = modifiedView.horizontalRadioGroupLayout()
            }
#else
            break // not on this platform: no style, as for an unknown name
#endif
        case nil:
            break
        }
        return modifiedView
    }
}
