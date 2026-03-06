//
//  FileLoadableView.swift
//  ActionUI
//

import SwiftUI

// View for synchronous file-based loading (local file or bundle resource)
@MainActor
public struct FileLoadableView: SwiftUI.View {
    // Static dedup tracking — avoids using @Published ViewModel.states which would trigger re-renders
    private static var loadedSources: [String: String] = [:]

    let fileURL: URL
    let windowUUID: String
    let isContentView: Bool
    let parentID: Int
    let viewDidLoadActionID: String?
    let logger: any ActionUILogger

    private let element: ActionUIElement?
    private let error: Error?

    public init(fileURL: URL, windowUUID: String, isContentView: Bool, parentID: Int = 0, viewDidLoadActionID: String? = nil, logger: any ActionUILogger) {
        self.fileURL = fileURL
        self.windowUUID = windowUUID
        self.isContentView = isContentView
        self.parentID = parentID
        self.viewDidLoadActionID = viewDidLoadActionID
        self.logger = logger

        // Perform synchronous loading in init
        do {
            let data = try Data(contentsOf: fileURL)
            let format = fileURL.pathExtension.lowercased() == "plist" ? "plist" : "json"
            logger.log("Determined format '\(format)' for file URL \(fileURL)", .debug)
            if isContentView {
                self.element = try ActionUIModel.shared.loadDescription(from: data, format: format, windowUUID: windowUUID)
            } else {
                self.element = try ActionUIModel.shared.loadSubViewDescription(from: data, format: format, windowUUID: windowUUID, parentID: parentID)
            }
            logger.log("Successfully loaded \(format) for LoadableView from file \(fileURL)", .debug)
            self.error = nil
            // Defer fireViewDidLoad to after current body evaluation completes
            // Uses static dedup so it only fires once per unique source
            let capturedFileURL = fileURL
            let capturedWindowUUID = windowUUID
            let capturedParentID = parentID
            let capturedActionID = viewDidLoadActionID
            Task { @MainActor in
                Self.fireViewDidLoad(fileURL: capturedFileURL, windowUUID: capturedWindowUUID, parentID: capturedParentID, viewDidLoadActionID: capturedActionID)
            }
        } catch {
            self.element = nil
            self.error = error
            logger.log("Failed to load description for LoadableView from file \(fileURL): \(error)", .error)
        }
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
            SwiftUI.Text("No content loaded")
        }
    }

    private static func fireViewDidLoad(fileURL: URL, windowUUID: String, parentID: Int, viewDidLoadActionID: String?) {
        guard let actionID = viewDidLoadActionID else { return }
        guard ActionUIModel.shared.windowModels[windowUUID]?.viewModels[parentID] != nil else { return }

        let key = "\(windowUUID)_\(parentID)"
        let source = fileURL.absoluteString
        guard loadedSources[key] != source else { return }
        loadedSources[key] = source
        ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: parentID, viewPartID: 0)
    }
}
