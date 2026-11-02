// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

// AdwaitaPlatform.swift - the windows on Linux, through ActionUI's GTK application. The runtime sizes
// each window and shows the provenance line in it. A window takes the keyboard focus when it opens,
// whatever `activate` says: Wayland has no request to leave the focus where it was.

#if os(Linux)
import FoundationEssentials
import ActionUI
import ActionUICachedImage
import ActionUIRichText
import MCPStdio

@MainActor
final class AdwaitaPlatform: WindowPlatform {
    typealias Content = AdwaitaApplication.PreparedWindow
    typealias FileType = String

    nonisolated static let systemName = "Linux"
    nonisolated static let shownContent = "report, image, video, web page, table, or chart"
    nonisolated static let noticeDescription = """
        Show a short desktop notification, for example that a long job finished. Returns {shown} \
        once the desktop took it. It does not take focus; the desktop places and styles it, may \
        hide it sooner than duration_s, and holds it back in do-not-disturb mode. Markdown keeps \
        bold and italic only. It is gone after duration_s; nothing comes back from it.
        """
    nonisolated static let verifierPlatform = "linux"
    nonisolated static let keepsWindows = false
    /// The runtime removes a closed window's model itself, after the disappear actions that read it.
    nonisolated static let removesClosedWindowModels = true
    /// How long a capture waits for a window that just opened to be drawn, in tries of 50 ms.
    private static let captureTries = 40

    weak var host: WindowHost?
    private let application = AdwaitaApplication.shared

    init() {
        application.handlers.windowWillClose = { [weak self] windowID in
            self?.host?.windowClosed(windowID)
        }
    }

    static func registerAddOns() {
        ActionUICachedImage.register()
        ActionUIRichText.register()
    }

    /// A server runs with no window much of the time, and over SSH with no display at all. Ctrl+Q
    /// goes, as the server has no Quit on macOS: it would end the client's server, and closing the
    /// windows is enough.
    static func prepareApplication(isKeeper: Bool) {
        AdwaitaApplication.shared.name = "ActionUI"
        AdwaitaApplication.shared.keepsRunningWithoutWindows = true
        AdwaitaApplication.shared.runsWithoutDisplay = true
        AdwaitaApplication.shared.loadMenuBar(json: #"[{"type": "CommandGroup", "properties": {"placementTarget": "appTermination", "placement": "replacing"}}]"#)
    }

    static func runApplication() {
        AdwaitaApplication.shared.run()
    }

    /// Notices end with the session, as on macOS: the desktop would otherwise show the ones still
    /// queued after the server is gone.
    static func terminateApplication() {
        DesktopNotifications.closeAll()
        AdwaitaApplication.shared.terminate()
    }

    var hasGraphicalSession: Bool {
        application.hasDisplay
    }

    /// Only loads: building the widgets starts a WebView's page and an AsyncImage's fetch, which a
    /// document that is only checked, or is refused, must not do. So the renderer's warnings come
    /// from `present`, and validate_document does not see them.
    func loadContent(file: URL, windowID: String) -> Content {
        application.prepareWindow(json: (try? Data(contentsOf: file)) ?? Data(), windowUUID: windowID)
    }

    func present(_ content: Content, windowID: String, title: String, subtitle: String, sizing: WindowHost.Sizing, activate: Bool) {
        var options = AdwaitaApplication.WindowOptions(subtitle: subtitle)
        switch sizing {
        case .fitting(let resizable):
            options.isResizable = resizable
        case .fixed(let size):
            options.contentSize = (Int(size.width), Int(size.height))
        }
        application.presentWindow(prepared: content, title: title, options: options)
    }

    func close(_ windowID: String) {
        application.closeWindow(windowID)
    }

    /// Linux has no Dock icon or menu bar to bring and take away.
    func setShowsInterface(_ shows: Bool) {}

    func capture(_ windowID: String) async throws -> CapturedImage {
        let file = HostSupport.sessionFolder.appendingPathComponent("capture-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: file) }
        for _ in 0..<Self.captureTries {
            if let size = application.capturePNG(windowUUID: windowID, path: file.path, maxPixels: WindowHost.maxScreenshotPixels) {
                return CapturedImage(png: try Data(contentsOf: file), pixelWidth: size.width, pixelHeight: size.height)
            }
            try await Task.sleep(nanoseconds: 50_000_000)
            guard host?.windows.contains(windowID) == true else {
                throw MCPToolError("window \(windowID) was closed before it could be captured")
            }
        }
        throw MCPToolError("the window was not drawn in time to be captured")
    }

    /// In a window that is never presented, so the compositor never hears of it and the focus
    /// stays with the user (OffscreenWindow). The widgets are built here, so what the renderers log
    /// is captured here, as `present` does for a shown window. Titled "Preview", as on macOS.
    func renderOffscreen(_ content: Content, size: ContentSize?, delay: Double) async throws -> (image: CapturedImage, warnings: [String]) {
        var options = AdwaitaApplication.WindowOptions()
        if let size {
            options.contentSize = (Int(size.width), Int(size.height))
        }
        let built: (result: AdwaitaApplication.OffscreenWindow?, entries: [HostLogger.Entry])
        if let logger = host?.logger {
            built = logger.capture { application.renderOffscreen(prepared: content, title: "Preview", options: options) }
        } else {
            built = (application.renderOffscreen(prepared: content, title: "Preview", options: options), [])
        }
        var warnings = built.entries.filter { $0.level == .warning || $0.level == .error }.map(\.message)
        guard let render = built.result else {
            throw MCPToolError("the document could not be rendered" + (warnings.isEmpty ? "" : ":\n" + warnings.prefix(20).joined(separator: "\n")))
        }
        defer { render.close() }
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        if render.showsWebView {
            warnings.append("A WebView's page is not drawn in a document rendered without showing it on Linux; open the document with show_document and screenshot that window to see the page")
        }
        let file = HostSupport.sessionFolder.appendingPathComponent("render-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: file) }
        guard let pixels = render.capturePNG(path: file.path, maxPixels: WindowHost.maxScreenshotPixels) else {
            throw MCPToolError("the document could not be drawn")
        }
        return (CapturedImage(png: try Data(contentsOf: file), pixelWidth: pixels.width, pixelHeight: pixels.height), warnings)
    }

    /// A desktop notification from "ActionUI" with the provenance line as its summary, then the
    /// title and the message. GNOME's banner shows the summary first and cuts the body to one
    /// line, so a long message or title cannot push the provenance line out of view.
    func showNotice(title: String?, message: String, subtitle: String, duration: Double) async throws {
        let error: String? = await withCheckedContinuation { continuation in
            DesktopNotifications.show(appName: "ActionUI", summary: subtitle, heading: title, markdown: message,
                                      seconds: duration) { error in
                continuation.resume(returning: error)
            }
        }
        if let error {
            throw MCPToolError("the notice could not be shown: \(error)")
        }
    }

    nonisolated static func fileType(named name: String) -> String? {
        AppPanels.knowsFileType(name) ? name : nil
    }

    func beginPanel(_ spec: PanelSpec, completion: @escaping @MainActor ([String]?) -> Void) -> @MainActor () -> Void {
        var settings: [String: JSONValue] = [:]
        // A GTK file dialog has a title and no message.
        let heading = [spec.title, spec.message].compactMap { $0 }.joined(separator: " - ")
        if !heading.isEmpty { settings["title"] = .string(heading) }
        if let directory = spec.directory { settings["directoryURL"] = .string(directory.path) }
        if !spec.allowedTypes.isEmpty && spec.kind != .folder {
            settings["allowedContentTypes"] = .array(spec.allowedTypes.map { .string($0) })
        }
        if spec.kind == .save {
            if let name = spec.defaultName { settings["nameFieldStringValue"] = .string(name) }
            let panel = AppPanels.beginSavePanel(json: JSONValue.object(settings).serialized()) { path in
                completion(path.map { [$0] })
            }
            return { panel.cancel() }
        }
        settings["canChooseFiles"] = .bool(spec.kind == .file)
        settings["canChooseDirectories"] = .bool(spec.kind == .folder)
        settings["allowsMultipleSelection"] = .bool(spec.multiple)
        let panel = AppPanels.beginOpenPanel(json: JSONValue.object(settings).serialized()) { paths in
            completion(paths)
        }
        return { panel.cancel() }
    }

    func keptWindowStates(_ ids: [String]) -> [KeptWindowState] {
        []
    }
}
#endif
