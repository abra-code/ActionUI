//
//  FileLoadableView.swift
//  ActionUI
//

import SwiftUI

// View for synchronous loading: a local file, a bundle resource, or a description already in memory
@MainActor
public struct FileLoadableView: SwiftUI.View {
    // viewDidLoadActionID once per source (Core/Common/DocumentLoader.swift)
    private static let viewDidLoad = ActionUIDocumentLoader.ViewDidLoad()

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

    /// `around`: the origin of the content a LoadableView is in, when its renderer knows it (a
    /// template row's); nil: looked up by `parentID`.
    public init(fileURL: URL, windowUUID: String, isContentView: Bool, parentID: Int = 0, around: JSONContentOrigin? = nil,
                viewDidLoadActionID: String? = nil, logger: any ActionUILogger) {
        let format = ActionUIDocumentLoader.format(of: fileURL)
        logger.log("Determined format '\(format)' for file URL \(fileURL)", .debug)
        self.init(source: fileURL.absoluteString, origin: .file(fileURL), format: format, windowUUID: windowUUID, isContentView: isContentView, parentID: parentID, around: around, viewDidLoadActionID: viewDidLoadActionID, logger: logger) {
            try ActionUIDocumentLoader.readRegularFile(fileURL)
        }
    }

    /// Loads a description the caller already holds in memory, for example one compiled into the
    /// program. `sourceName` identifies the data in log messages and must differ between different
    /// descriptions loaded into the same window element. `format` is "json" or "plist".
    public init(data: Data, format: String = "json", sourceName: String, windowUUID: String, isContentView: Bool, parentID: Int = 0, viewDidLoadActionID: String? = nil, logger: any ActionUILogger) {
        self.init(source: sourceName, origin: nil, format: format, windowUUID: windowUUID, isContentView: isContentView, parentID: parentID, around: nil, viewDidLoadActionID: viewDidLoadActionID, logger: logger) {
            data
        }
    }

    // `origin`: where the data is read from (JSONContentOrigin), nil for data the host holds.
    private init(source: String, origin: ActionUIDocumentLoader.Source?, format: String, windowUUID: String, isContentView: Bool, parentID: Int, around: JSONContentOrigin?, viewDidLoadActionID: String?, logger: any ActionUILogger, loadData: () throws -> Data) {
        self.source = source
        self.windowUUID = windowUUID
        self.isContentView = isContentView
        self.parentID = parentID
        self.viewDidLoadActionID = viewDidLoadActionID
        self.logger = logger

        // Perform synchronous loading in init
        do {
            let data = try loadData()
            self.element = try ActionUIDocumentLoader.load(data: data, format: format, windowUUID: windowUUID, isContentView: isContentView, parentID: parentID, source: origin, around: around)
            logger.log("Successfully loaded \(format) for LoadableView from \(source)", .debug)
            self.error = nil
            // Defer fireViewDidLoad to after current body evaluation completes
            // Uses static dedup so it only fires once per unique source
            let capturedSource = source
            let capturedWindowUUID = windowUUID
            let capturedParentID = parentID
            let capturedActionID = viewDidLoadActionID
            Task { @MainActor in
                Self.viewDidLoad.fire(source: capturedSource, windowUUID: capturedWindowUUID, parentID: capturedParentID, actionID: capturedActionID)
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
}

// MARK: - Nesting

private struct ActionUILoadableSourcesKey: EnvironmentKey {
    static let defaultValue: [String] = []
}

extension EnvironmentValues {
    /// The sources of the LoadableViews this view is inside, outermost first.
    var actionUILoadableSources: [String] {
        get { self[ActionUILoadableSourcesKey.self] }
        set { self[ActionUILoadableSourcesKey.self] = newValue }
    }
}

/// Shows a LoadableView's content unless its source is already being shown by a LoadableView
/// around it (a document that loads itself, directly or through others, would load without end)
/// or the LoadableViews are nested too deep (the rule is Core's `ActionUIDocumentLoader.nestingRefusal`).
/// The content view is made only when it may show, so a refused file is never read.
@MainActor
struct LoadableNestingGuard<Content: SwiftUI.View>: SwiftUI.View {
    @Environment(\.actionUILoadableSources) private var sources
    let source: String
    let logger: any ActionUILogger
    let content: () -> Content

    init(source: String, logger: any ActionUILogger, @ViewBuilder content: @escaping () -> Content) {
        self.source = source
        self.logger = logger
        self.content = content
    }

    var body: some SwiftUI.View {
        if let refusal = ActionUIDocumentLoader.nestingRefusal(source, inside: sources) {
            SwiftUI.Text("Failed to load view: \(refusal)")
                .foregroundStyle(.red)
                .onAppear { logger.log("LoadableView: not loading \(source): \(refusal)", .error) }
        } else {
            content().environment(\.actionUILoadableSources, sources + [source])
        }
    }
}
