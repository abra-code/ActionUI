// Sources/Views/LoadableView.swift
/*
 Sample JSON for LoadableView:
 {
   "type": "LoadableView",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "url": "https://example.com/view.json" // Required: String URL to JSON description, shows ProgressView while loading, error SwiftUI.Text on failure
   }
   // Note: Loads JSON from URL, parses into ActionUIElement using ActionUIModel.loadDescription, and renders ActionUIView. Assumes unique IDs in loaded JSON to avoid conflicts with existing windowModels. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
   // Note: Invalid URLs (e.g., "invalid-url") will result in error display after failed load attempt.
   // Note: The 'url' property is the designated value (valueType: String.self), settable via ActionUIModel.setElementValue.
 }
*/

import SwiftUI
import Foundation

struct LoadableView: ActionUIViewConstruction {
    static var valueType: Any.Type { String.self } // Non-optional String for URL
    
    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        var validatedProperties = properties
        
        // Validate url
        if properties["url"] != nil && !(properties["url"] is String) {
            logger.log("LoadableView url must be a String; ignoring", .error)
            validatedProperties["url"] = nil
        }
        
        return validatedProperties
    }
    
    static var buildView: (any ActionUIElement, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        // Use viewModel.value if set, otherwise use initialValue
        let urlString = Self.initialValue(model) as? String ?? ""
        
        guard let url = URL(string: urlString) else {
            logger.log("LoadableView missing or invalid URL, displaying error SwiftUI.Text", .warning)
            return SwiftUI.Text("Missing or invalid URL")
        }
        
        return LoadableContentView(url: url, windowUUID: windowUUID, logger: logger)
    }
    
    static var initialValue: (ViewModel) -> Any? = { model in
        if let initialValue = model.value as? String {
            return initialValue
        }
        let initialValue = model.validatedProperties["url"] as? String ?? ""
        return initialValue
    }
    
    // Inner view to handle asynchronous loading
    private struct LoadableContentView: SwiftUI.View {
        let url: URL
        let windowUUID: String
        let logger: any ActionUILogger
        
        @State private var element: ViewElement?
        @State private var error: Error?
        
        var body: some SwiftUI.View {
            if let error = error {
                SwiftUI.Text("Failed to load view: \(error.localizedDescription)")
                    .foregroundStyle(.red)
            } else if let element = element,
                      let windowModel = ActionUIModel.shared.windowModels[windowUUID],
                      let viewModel = windowModel.viewModels[element.id] {
                ActionUIView(element: element, model: viewModel, windowUUID: windowUUID)
            } else {
                SwiftUI.ProgressView()
                    .onAppear {
                        Task { @MainActor in
                            do {
                                let (data, _) = try await URLSession.shared.data(from: url)
                                let loadedElement = try ActionUIModel.shared.loadDescription(from: data, format: "json", windowUUID: windowUUID)
                                element = loadedElement
                                logger.log("Successfully loaded JSON for LoadableView from \(url)", .debug)
                            } catch {
                                self.error = error
                                logger.log("Failed to load JSON for LoadableView from \(url): \(error)", .error)
                            }
                        }
                    }
            }
        }
        
        init(url: URL, windowUUID: String, logger: any ActionUILogger) {
            self.url = url
            self.windowUUID = windowUUID
            self.logger = logger
        }
    }
}
