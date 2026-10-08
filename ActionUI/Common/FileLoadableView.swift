//
//  FileLoadableView.swift
//  ActionUI
//

import SwiftUI

// View for synchronous loading: a local file, a bundle resource, or a description already in memory
@MainActor
public struct FileLoadableView: SwiftUI.View {
    // Static dedup tracking — avoids using @Published ViewModel.states which would trigger re-renders
    private static var loadedSources: [String: String] = [:]

    // Where the description came from, for log messages and viewDidLoad dedup: the file URL, or the
    // name the caller gave to in-memory data.
    let source: String
    let windowUUID: String
    let isContentView: Bool
    let parentID: Int
    let viewDidLoadActionID: String?
    let logger: any ActionUILogger

    private let element: ActionUIElement?
    private let error: Error?

    public init(fileURL: URL, windowUUID: String, isContentView: Bool, parentID: Int = 0, viewDidLoadActionID: String? = nil, logger: any ActionUILogger) {
        let format = fileURL.pathExtension.lowercased() == "plist" ? "plist" : "json"
        logger.log("Determined format '\(format)' for file URL \(fileURL)", .debug)
        self.init(source: fileURL.absoluteString, format: format, windowUUID: windowUUID, isContentView: isContentView, parentID: parentID, viewDidLoadActionID: viewDidLoadActionID, logger: logger) {
            try Data(contentsOf: fileURL)
        }
    }

    /// Loads a description the caller already holds in memory, for example one compiled into the
    /// program. `sourceName` identifies the data in log messages and must differ between different
    /// descriptions loaded into the same window element. `format` is "json" or "plist".
    public init(data: Data, format: String = "json", sourceName: String, windowUUID: String, isContentView: Bool, parentID: Int = 0, viewDidLoadActionID: String? = nil, logger: any ActionUILogger) {
        self.init(source: sourceName, format: format, windowUUID: windowUUID, isContentView: isContentView, parentID: parentID, viewDidLoadActionID: viewDidLoadActionID, logger: logger) {
            data
        }
    }

    private init(source: String, format: String, windowUUID: String, isContentView: Bool, parentID: Int, viewDidLoadActionID: String?, logger: any ActionUILogger, loadData: () throws -> Data) {
        self.source = source
        self.windowUUID = windowUUID
        self.isContentView = isContentView
        self.parentID = parentID
        self.viewDidLoadActionID = viewDidLoadActionID
        self.logger = logger

        // Perform synchronous loading in init
        do {
            let data = try loadData()
            if isContentView {
                self.element = try ActionUIModel.shared.loadDescription(from: data, format: format, windowUUID: windowUUID)
            } else {
                self.element = try ActionUIModel.shared.loadSubViewDescription(from: data, format: format, windowUUID: windowUUID, parentID: parentID)
            }
            logger.log("Successfully loaded \(format) for LoadableView from \(source)", .debug)
            self.error = nil
            // Defer fireViewDidLoad to after current body evaluation completes
            // Uses static dedup so it only fires once per unique source
            let capturedSource = source
            let capturedWindowUUID = windowUUID
            let capturedParentID = parentID
            let capturedActionID = viewDidLoadActionID
            Task { @MainActor in
                Self.fireViewDidLoad(source: capturedSource, windowUUID: capturedWindowUUID, parentID: capturedParentID, viewDidLoadActionID: capturedActionID)
            }
        } catch {
            self.element = nil
            self.error = error
            logger.log("Failed to load description for LoadableView from \(source): \(error)", .error)
        }
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
                // Window root: attach window-level sheet/fullScreenCover/alert/confirmationDialog.
                // windowRootSafeArea goes on the root CONTENT, not around WindowModalView: the
                // toast overlay in there must stay inside the safe area, below the titlebar.
                WindowModalView(windowModel: windowModel, content: AnyView(coreView.windowRootSafeArea(rootElementType: element.type)), windowUUID: windowUUID)
            } else {
                // Sub-view instance (tab pane, detail view, etc.) — no window-level modifiers
                coreView
            }
        } else {
            SwiftUI.Text("No content loaded")
        }
    }

    private static func fireViewDidLoad(source: String, windowUUID: String, parentID: Int, viewDidLoadActionID: String?) {
        guard let actionID = viewDidLoadActionID else { return }
        guard ActionUIModel.shared.windowModels[windowUUID]?.viewModels[parentID] != nil else { return }

        let key = "\(windowUUID)_\(parentID)"
        guard loadedSources[key] != source else { return }
        loadedSources[key] = source
        ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: parentID, viewPartID: 0)
    }
}
