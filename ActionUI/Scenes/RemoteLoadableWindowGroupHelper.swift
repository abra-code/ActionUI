// Sources/Scenes/RemoteLoadableWindowGroupHelper.swift
import SwiftUI

// View for remote asynchronous loading of WindowGroup content
@MainActor
struct RemoteLoadableWindowGroupHelper: SwiftUI.View {
    let url: URL
    let windowUUID: String
    let logger: any ActionUILogger
    
    @State private var element: (any ActionUIElementBase)?
    @State private var error: Error?
    
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
            SwiftUI.ProgressView()
                .onAppear {
                    Task { @MainActor in
                        do {
                            var request = URLRequest(url: url)
                            request.cachePolicy = .reloadRevalidatingCacheData
                            let (data, _) = try await URLSession.shared.data(for: request)
                            
                            let format = url.pathExtension.lowercased() == "plist" ? "plist" : "json"
                            logger.log("Determined format '\(format)' for remote URL \(url)", .debug)
                            element = try ActionUIModel.shared.loadSubViewDescription(from: data, format: format, windowUUID: windowUUID)
                            logger.log("Successfully loaded \(format) for LoadableWindowGroup from remote \(url)", .debug)
                        } catch {
                            self.error = error
                            logger.log("Failed to load remote description for LoadableWindowGroup from \(url): \(error)", .error)
                        }
                    }
                }
        }
    }
}
