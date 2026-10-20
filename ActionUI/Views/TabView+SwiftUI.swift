// SwiftUI rendering of TabView; its portable part is in Core/Elements/TabView.swift.

import SwiftUI

extension TabView: ActionUISwiftUIRenderer {
    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        let props = Props(properties)
        let children = element.subviews?["children"] as? [any ActionUIElementBase] ?? []
        
        // Get initial selection value
        let initialSelection = Self.initialValue(model) as? Int ?? 0
        
        // Create selection binding
        // Hoisted out of the binding: its main-actor closures capture only this Sendable String?,
        // not the non-Sendable [String: Any] properties payload.
        let valueChangeActionID = props.actionID
        let selectionBinding = mainActorBinding(
            get: { model.value as? Int ?? initialSelection },
            set: { newValue in
                guard model.value as? Int != newValue else {
                    return
                }
                // Use DispatchQueue.main.async to guarantee deferred execution and avoid
                // "publishing changes from within view updates" warning
                DispatchQueue.main.async {
                    model.value = newValue
                    if let valueChangeActionID {
                        ActionUIModel.shared.actionHandler(valueChangeActionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0, context: newValue)
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
        let props = Props(properties)

        switch props.style {
        case .tabBarOnly:
            if #available(iOS 18.0, macOS 15.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *) {
                modifiedView = modifiedView.tabViewStyle(.tabBarOnly)
            }
        case .sidebarAdaptable:
            if #available(iOS 18.0, macOS 15.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *) {
                modifiedView = modifiedView.tabViewStyle(.sidebarAdaptable)
            }
        case .page:
            #if !os(macOS)
            modifiedView = modifiedView.tabViewStyle(.page)
            #else
            logger.log("TabView style 'page' is not available on macOS; ignoring", .warning)
            #endif
        case .verticalPage:
            #if os(watchOS)
            modifiedView = modifiedView.tabViewStyle(.verticalPage)
            #else
            logger.log("TabView style 'verticalPage' is only available on watchOS; ignoring", .warning)
            #endif
        case .grouped:
            #if os(macOS)
            if #available(macOS 15.0, *) {
                modifiedView = modifiedView.tabViewStyle(.grouped)
            } else {
                logger.log("TabView style 'grouped' requires macOS 15.0+; ignoring", .warning)
            }
            #else
            logger.log("TabView style 'grouped' is only available on macOS; ignoring", .warning)
            #endif
        case .automatic:
            modifiedView = modifiedView.tabViewStyle(.automatic)
        case nil:
            break
        }

        return modifiedView
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
