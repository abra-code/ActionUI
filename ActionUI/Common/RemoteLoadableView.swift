//
//  RemoteLoadableView.swift
//  ActionUI
//

import SwiftUI

/// Fetches remote ActionUI JSON with limits, as the Linux loader does: the body is read as
/// it arrives and refused once it grows past `limit` bytes (the JSON size cap: larger ActionUI JSON is
/// refused when it loads anyway), and the whole fetch is given up after `timeout` seconds (the
/// configuration's maximumDownloadTime; nil: no limit), however slowly the server sends.
/// URLSession's own timeout only covers a pause between pieces. A status
/// outside 200-299 is refused before the body is read, as on Linux and Android: an error page is
/// not ActionUI JSON. Gives the address the body finally came from too, after redirects, which
/// decides how far it is trusted.
enum RemoteJSONFetch {
    /// The session for an address less-trusted content names: none of the app's cookies, stored
    /// credentials or cache (an ephemeral session that stores and sends no cookies, has no
    /// credential store, and keeps only its own cache in memory), and the server's sign-in
    /// challenges declined, so the system's single sign-on cannot answer one either: a server the
    /// content picks learns nothing of the app's or the user's sessions.
    static let privateSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        return URLSession(configuration: configuration, delegate: NoSignIn(), delegateQueue: nil)
    }()

    /// Declines the server's authentication challenges, so the fetch goes on without credentials (a
    /// server that only asks for a client certificate still answers; one that needs a sign-in
    /// answers 401, which the fetch refuses). The check of the server's own certificate and a
    /// proxy's sign-in (the network's, not the server's) are left to the system.
    final class NoSignIn: NSObject, URLSessionTaskDelegate, Sendable {
        func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge)
            async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
            Self.answer(challenge)
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge)
            async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
            Self.answer(challenge)
        }

        static func answer(_ challenge: URLAuthenticationChallenge) -> (URLSession.AuthChallengeDisposition, URLCredential?) {
            let space = challenge.protectionSpace
            if space.authenticationMethod == NSURLAuthenticationMethodServerTrust || space.isProxy() {
                return (.performDefaultHandling, nil)
            }
            return (.rejectProtectionSpace, nil)
        }
    }

    /// Refuses a redirect that lowers https to plain http or leaves http and https. Each hop is
    /// judged by the address it is redirected from, so http to https to http is refused at the last
    /// hop (Linux's loader judges by the address first asked for and follows that one). The refused
    /// address is kept for the error. One per request.
    final class RedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        private let lock = NSLock()
        private var refusedTarget: URL?

        var refused: URL? {
            lock.withLock { refusedTarget }
        }

        // The completion-handler form, not the async one: Swift 6.4.2 crashes generating the
        // Objective-C entry point of the async form when Xcode builds the module interface.
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
            let from = response.url?.scheme?.lowercased() ?? task.originalRequest?.url?.scheme?.lowercased()
            let to = request.url?.scheme?.lowercased()
            guard let to, to == "https" || (to == "http" && from != "https") else {
                lock.withLock { refusedTarget = request.url }
                completionHandler(nil)
                return
            }
            completionHandler(request)
        }
    }

    /// `what`: what the body is, for the error when it is too large.
    static func data(for request: URLRequest, limit: Int,
                     timeout: Double? = ActionUIConfiguration.current.limits.maximumDownloadTime,
                     session: URLSession = .shared, what: String = "the ActionUI JSON") async throws -> (data: Data, finalURL: URL) {
        try await withThrowingTaskGroup(of: (data: Data, finalURL: URL)?.self) { group in
            group.addTask {
                let redirects = RedirectGuard()
                func refusal(_ refused: URL) -> ActionUIError {
                    ActionUIError("the server redirected it to \(refused.absoluteString), which is not loaded: an https address is not followed to plain http, nor to another scheme")
                }
                let bytes: URLSession.AsyncBytes
                let response: URLResponse
                do {
                    (bytes, response) = try await session.bytes(for: request, delegate: redirects)
                } catch {
                    if let refused = redirects.refused { throw refusal(refused) }
                    throw error
                }
                if let refused = redirects.refused { throw refusal(refused) }
                if let status = (response as? HTTPURLResponse)?.statusCode, !(200...299).contains(status) {
                    throw ActionUIError("the server answered with HTTP status \(status)")
                }
                // Not the requested address when the response names none: after a redirect that
                // would pass another server's JSON for the requested server's.
                guard let finalURL = response.url else { throw ActionUIError("the response names no address") }
                // Refused at once when the server says how long the body is.
                guard response.expectedContentLength <= Int64(limit) else { throw tooLarge(limit, what) }
                var data = Data()
                if response.expectedContentLength > 0 { data.reserveCapacity(Int(response.expectedContentLength)) }
                for try await byte in bytes {
                    guard data.count < limit else { throw tooLarge(limit, what) }
                    data.append(byte)
                }
                return (data, finalURL)
            }
            if let timeout {
                group.addTask {
                    // Clamped: UInt64 nanoseconds end past 584 years.
                    try await Task.sleep(nanoseconds: UInt64(min(timeout, 1e9) * 1_000_000_000))
                    return nil
                }
            }
            defer { group.cancelAll() }
            guard let first = try await group.next(), let result = first else {
                throw ActionUIError("loading it took longer than \(Self.seconds(timeout ?? 0)) seconds")
            }
            return result
        }
    }

    /// `seconds` as a whole number when it is one ("120"), else as it is ("0.5").
    static func seconds(_ seconds: Double) -> String {
        seconds == seconds.rounded() && abs(seconds) < 1e15 ? String(Int64(seconds)) : String(seconds)
    }

    private static func tooLarge(_ limit: Int, _ what: String) -> ActionUIError {
        ActionUIError("\(what) is larger than \(limit / (1024 * 1024)) MB")
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
    /// The origin of the content a LoadableView is in, when its renderer knows it; nil: by `parentID`.
    let around: JSONContentOrigin?
    let viewDidLoadActionID: String?
    let logger: any ActionUILogger

    @State private var element: ActionUIElement?
    @State private var error: Error?

    public init(url: URL, windowUUID: String, isContentView: Bool, parentID: Int = 0, around: JSONContentOrigin? = nil,
                viewDidLoadActionID: String? = nil, logger: any ActionUILogger) {
        self.around = around
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
                        let limit = WindowModel.maximumJSONSize
                        // An address the host named keeps the app's session (a server of its own may
                        // need its cookies); one less-trusted content named gets a private one.
                        let session = ActionUIDocumentLoader.isNamedByLessTrustedContent(
                            windowUUID: windowUUID, isContentView: isContentView, parentID: parentID, around: around)
                            ? RemoteJSONFetch.privateSession : URLSession.shared
                        do {
                            element = try await ActionUIDocumentLoader.loadRemote(
                                url: url, windowUUID: windowUUID, isContentView: isContentView, parentID: parentID, around: around, logger: logger
                            ) { url in
                                var request = URLRequest(url: url)
                                request.cachePolicy = .reloadRevalidatingCacheData // Balances freshness and performance
                                return try await RemoteJSONFetch.data(for: request, limit: limit, session: session)
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
