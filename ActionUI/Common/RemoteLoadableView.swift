//
//  RemoteLoadableView.swift
//  ActionUI
//

import SwiftUI

// View for remote asynchronous loading
@MainActor
public struct RemoteLoadableView: SwiftUI.View {
    let url: URL
    let windowUUID: String
    let isContentView: Bool
    let parentID: Int
    let logger: any ActionUILogger

    @State private var element: ActionUIElement?
    @State private var error: Error?

    public init(url: URL, windowUUID: String, isContentView: Bool, parentID: Int = 0, logger: any ActionUILogger) {
        self.url = url
        self.windowUUID = windowUUID
        self.isContentView = isContentView
        self.parentID = parentID
        self.logger = logger
    }
    
    public var body: some SwiftUI.View {
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
                            var request = URLRequest(url: url)
                            request.cachePolicy = .reloadRevalidatingCacheData // Balances freshness and performance
                            let (data, _) = try await URLSession.shared.data(for: request)
                            
                            // Determine format based on URL extension
                            let format = url.pathExtension.lowercased() == "plist" ? "plist" : "json"
                            logger.log("Determined format '\(format)' for remote URL \(url)", .debug)
                            if isContentView {
                                element = try ActionUIModel.shared.loadDescription(from: data, format: format, windowUUID: windowUUID)
                            } else {
                                element = try ActionUIModel.shared.loadSubViewDescription(from: data, format: format, windowUUID: windowUUID, parentID: parentID)
                            }
                            logger.log("Successfully loaded \(format) for LoadableView from remote \(url)", .debug)
                        } catch {
                            self.error = error
                            logger.log("Failed to load remote description for LoadableView from \(url): \(error)", .error)
                        }
                    }
                }
        }
    }
}
