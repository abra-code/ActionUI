// Sources/Scenes/FileLoadableWindowGroupHelper.swift
import SwiftUI

// View for synchronous file-based loading of WindowGroup content
@MainActor
struct FileLoadableWindowGroupHelper: SwiftUI.View {
    let fileURL: URL
    let windowUUID: String
    let logger: any ActionUILogger
    
    private let element: (any ActionUIElementBase)?
    private let error: Error?
    
    init(fileURL: URL, windowUUID: String, logger: any ActionUILogger) {
        self.fileURL = fileURL
        self.windowUUID = windowUUID
        self.logger = logger
        
        do {
            let data = try Data(contentsOf: fileURL)
            let format = fileURL.pathExtension.lowercased() == "plist" ? "plist" : "json"
            logger.log("Determined format '\(format)' for file URL \(fileURL)", .debug)
            self.element = try ActionUIModel.shared.loadSubViewDescription(from: data, format: format, windowUUID: windowUUID)
            logger.log("Successfully loaded \(format) for LoadableWindowGroup from file \(fileURL)", .debug)
            self.error = nil
        } catch {
            self.element = nil
            self.error = error
            logger.log("Failed to load description for LoadableWindowGroup from file \(fileURL): \(error)", .error)
        }
    }
    
    var body: some SwiftUI.View {
        if let error = error {
            SwiftUI.Text("Failed to load window: \(error.localizedDescription)")
                .foregroundStyle(.red)
        } else if let element = element {
            if element.type == "WindowGroup",
               let windowModel = ActionUIModel.shared.windowModels[windowUUID],
               let viewModel = windowModel.viewModels[element.id],
               let contentElement = element.subviews?["content"] as? any ActionUIElementBase,
               let contentViewModel = windowModel.viewModels[contentElement.id] {
                ActionUIView(element: contentElement, model: contentViewModel, windowUUID: windowUUID)
            } else {
                SwiftUI.Text("Invalid element type: \(element.type)")
                    .foregroundStyle(.red)
                    .onAppear {
                        logger.log("Loaded element is not a valid WindowGroup (type: \(element.type), id: \(element.id))", .error)
                    }
            }
        } else {
            SwiftUI.Text("No content loaded").foregroundStyle(.red)
        }
    }
}
