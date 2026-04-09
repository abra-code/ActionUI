//
//  RemoteLoadableView.swift
//  ActionUI
//

import SwiftUI

// View for remote asynchronous loading
@MainActor
public struct RemoteLoadableView: SwiftUI.View {
    // Static dedup tracking — avoids using @Published ViewModel.states which would trigger re-renders
    private static var loadedSources: [String: String] = [:]

    let url: URL
    let windowUUID: String
    let isContentView: Bool
    let parentID: Int
    let viewDidLoadActionID: String?
    let logger: any ActionUILogger

    @State private var element: ActionUIElement?
    @State private var error: Error?

    public init(url: URL, windowUUID: String, isContentView: Bool, parentID: Int = 0, viewDidLoadActionID: String? = nil, logger: any ActionUILogger) {
        self.url = url
        self.windowUUID = windowUUID
        self.isContentView = isContentView
        self.parentID = parentID
        self.viewDidLoadActionID = viewDidLoadActionID
        self.logger = logger
    }

    public var body: some SwiftUI.View {
        if let error = error {
            SwiftUI.Text("Failed to load view: \(error.localizedDescription)")
                .foregroundStyle(.red)
        } else if let element = element,
                  let windowModel = ActionUIModel.shared.windowModels[windowUUID],
                  let viewModel = windowModel.viewModels[element.id] {
            let coreView = ActionUIView(element: element, model: viewModel, windowUUID: windowUUID)
            if isContentView {
                // Window root: attach window-level sheet/fullScreenCover/alert/confirmationDialog
                WindowModalView(windowModel: windowModel, content: AnyView(coreView), windowUUID: windowUUID)
            } else {
                // Sub-view instance (tab pane, detail view, etc.) — no window-level modifiers
                coreView
            }
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
                            fireViewDidLoad()
                        } catch {
                            self.error = error
                            logger.log("Failed to load remote description for LoadableView from \(url): \(error)", .error)
                        }
                    }
                }
        }
    }

    private func fireViewDidLoad() {
        guard let actionID = viewDidLoadActionID else { return }
        guard ActionUIModel.shared.windowModels[windowUUID]?.viewModels[parentID] != nil else { return }

        let key = "\(windowUUID)_\(parentID)"
        let source = url.absoluteString
        guard Self.loadedSources[key] != source else { return }
        Self.loadedSources[key] = source
        ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: parentID, viewPartID: 0)
    }
}
