//
//  RemoteLoadableView.swift
//  ActionUI
//

import SwiftUI

/// Fetches a remote document with limits, as the Linux loader does: the body is read as
/// it arrives and refused once it grows past `limit` bytes (the document cap: a larger document is
/// refused when it loads anyway), and the whole fetch is given up after `timeout` seconds, however
/// slowly the server sends. URLSession's own timeout only covers a pause between pieces.
enum RemoteDocumentFetch {
    /// The longest a whole fetch may take, in seconds (the Linux loader's 120 s).
    static let defaultTimeout: Double = 120

    static func data(for request: URLRequest, limit: Int, timeout: Double = defaultTimeout,
                     session: URLSession = .shared) async throws -> Data {
        try await withThrowingTaskGroup(of: Data?.self) { group in
            group.addTask {
                let (bytes, response) = try await session.bytes(for: request)
                // Refused at once when the server says how long the body is.
                guard response.expectedContentLength <= Int64(limit) else { throw tooLarge(limit) }
                var data = Data()
                if response.expectedContentLength > 0 { data.reserveCapacity(Int(response.expectedContentLength)) }
                for try await byte in bytes {
                    guard data.count < limit else { throw tooLarge(limit) }
                    data.append(byte)
                }
                return data
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return nil
            }
            defer { group.cancelAll() }
            guard let first = try await group.next(), let data = first else {
                throw ActionUIError("loading it took longer than \(Int(timeout)) seconds")
            }
            return data
        }
    }

    private static func tooLarge(_ limit: Int) -> ActionUIError {
        ActionUIError("the document is larger than \(limit / (1024 * 1024)) MB")
    }
}

// View for remote asynchronous loading
@MainActor
public struct RemoteLoadableView: SwiftUI.View {
    // viewDidLoadActionID once per source (Core/Common/DocumentLoader.swift)
    private static let viewDidLoad = ActionUIDocumentLoader.ViewDidLoad()

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
                // Window root: attach window-level sheet/fullScreenCover/alert/confirmationDialog.
                // windowRootSafeArea goes on the root CONTENT, not around WindowModalView: the
                // toast overlay in there must stay inside the safe area, below the titlebar.
                WindowModalView(windowModel: windowModel, content: AnyView(coreView.windowRootSafeArea(rootElementType: element.type)), windowUUID: windowUUID)
            } else {
                // Sub-view instance (tab pane, detail view, etc.) — no window-level modifiers
                coreView
            }
        } else {
            SwiftUI.ProgressView()
                .onAppear {
                    Task { @MainActor in
                        let limit = WindowModel.maximumDocumentSize
                        do {
                            element = try await ActionUIDocumentLoader.loadRemote(
                                url: url, windowUUID: windowUUID, isContentView: isContentView, parentID: parentID, logger: logger
                            ) { url in
                                var request = URLRequest(url: url)
                                request.cachePolicy = .reloadRevalidatingCacheData // Balances freshness and performance
                                return try await RemoteDocumentFetch.data(for: request, limit: limit)
                            }
                            Self.viewDidLoad.fire(source: url.absoluteString, windowUUID: windowUUID, parentID: parentID, actionID: viewDidLoadActionID)
                        } catch {
                            self.error = error
                            logger.log("Failed to load remote description for LoadableView from \(url): \(error)", .error)
                        }
                    }
                }
        }
    }
}
