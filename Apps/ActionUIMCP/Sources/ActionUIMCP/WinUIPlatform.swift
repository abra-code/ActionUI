// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

// WinUIPlatform.swift - the windows on Windows, through ActionUI's WinUI application. A window's subtitle
// (the provenance line) shows before its title in the title bar, which has one line and cuts a long one at
// its end: the agent's title can neither push it out of view nor come first. A kept window opens again
// in the keeper at its content's size, where Windows puts it (KeptWindowKeeper+Windows.swift). Not yet
// on Windows: notices, which answer that they are not available here.

#if os(Windows)
import FoundationEssentials
import ActionUI
import ActionUIWinUIApplication
import ActionUICachedImage
import ActionUIDiff
import ActionUIRichText
import MCPStdio

@MainActor
final class WinUIPlatform: WindowPlatform {
    typealias Content = WinUIApplication.PreparedWindow
    typealias FileType = String

    nonisolated static let systemName = "Windows"
    nonisolated static let shownContent = "report, file, image, video, web page, diff, table, or chart"
    nonisolated static let noticeDescription = """
        Show a short notice, for example that a long job finished. Not available on Windows yet: the call \
        answers with an error. Nothing comes back from it.
        """
    nonisolated static let verifierPlatform = "windows"
    nonisolated static let keepsWindows = true
    /// KeptWindowState.styleMask bits the keeper reads back: the window is resizable; its frame's x and y
    /// are where it was (else 0: its place could not be read).
    nonisolated static let resizableStyle: UInt = 1
    nonisolated static let positionedStyle: UInt = 2
    /// The application removes a closed window's model itself, after its disappear actions.
    nonisolated static let removesClosedWindowModels = true

    weak var host: WindowHost?
    private let application = WinUIApplication.shared
    /// Each open window's title, provenance line and whether it is resizable, for keptWindowStates.
    private var shown: [String: (title: String, subtitle: String, isResizable: Bool)] = [:]

    init() {
        application.handlers.windowWillClose = { [weak self] windowID in
            self?.shown[windowID] = nil
            self?.host?.windowClosed(windowID)
        }
    }

    static func registerAddOns() {
        ActionUICachedImage.register()
        ActionUIDiff.register()
        ActionUIRichText.register()
    }

    /// A server runs with no window much of the time. Its windows have no menu bar: the host loads no
    /// commands, so there is no Exit that would end the client's server, as on macOS and Linux.
    static func prepareApplication(isKeeper: Bool) {
        WinUIApplication.shared.name = "ActionUI MCP"
        WinUIApplication.shared.keepsRunningWithoutWindows = !isKeeper
    }

    static func runApplication() {
        WinUIApplication.shared.run()
    }

    static func terminateApplication() {
        WinUIApplication.shared.terminate()
    }

    var hasGraphicalSession: Bool {
        application.hasDisplay
    }

    /// Only loads: no WinUI object is made, so a WebView's page and an image's fetch do not start for a
    /// window that is only checked or refused.
    func loadContent(file: URL, windowID: String) -> Content {
        application.prepareWindow(json: (try? Data(contentsOf: file)) ?? Data(), windowUUID: windowID)
    }

    func present(_ content: Content, windowID: String, title: String, subtitle: String, sizing: WindowHost.Sizing,
                 activate: Bool, mark: WindowMark, footer: ShowFooter?) {
        var options = WinUIApplication.WindowOptions(subtitle: subtitle)
        switch sizing {
        case .fitting(let resizable):
            options.isResizable = resizable
        case .fixed(let size):
            options.contentSize = (Int(size.width), Int(size.height))
        }
        application.presentWindow(prepared: content, title: title, options: options)
        shown[windowID] = (title, subtitle, options.isResizable)
    }

    func close(_ windowID: String) {
        application.closeWindow(windowID)
    }

    /// Windows has no Dock icon or menu bar to bring and take away.
    func setShowsInterface(_ shows: Bool) {}

    /// The window drawn to a PNG no larger than WindowHost.maxScreenshotPixels on its longest side. A
    /// window that opened a moment ago may not be drawn yet: tried again for up to two seconds.
    func capture(_ windowID: String) async throws -> CapturedImage {
        let file = HostSupport.sessionFolder.appendingPathComponent("capture-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: file) }
        for _ in 0..<40 {
            let written: Bool = await withCheckedContinuation { continuation in
                application.capturePNG(windowUUID: windowID, path: file.path, maxPixels: WindowHost.maxScreenshotPixels) {
                    continuation.resume(returning: $0)
                }
            }
            if written, let png = try? Data(contentsOf: file), let size = Self.pngSize(png) {
                return CapturedImage(png: png, pixelWidth: size.width, pixelHeight: size.height)
            }
            try await Task.sleep(nanoseconds: 50_000_000)
            guard host?.windows.contains(windowID) == true else {
                throw MCPToolError("window \(windowID) was closed before it could be captured")
            }
        }
        throw MCPToolError("the window was not drawn in time to be captured")
    }

    /// A PNG's width and height, from its header (IHDR); nil for anything else.
    static func pngSize(_ png: Data) -> (width: Int, height: Int)? {
        let bytes = [UInt8](png.prefix(24))
        guard bytes.count == 24, bytes[0] == 0x89, bytes[1] == 0x50, bytes[12...15].elementsEqual(Array("IHDR".utf8)) else {
            return nil
        }
        func number(_ offset: Int) -> Int {
            bytes[offset..<offset + 4].reduce(0) { $0 << 8 | Int($1) }
        }
        return (number(16), number(20))
    }

    /// In a window shown without activation past every monitor's edge, out of the taskbar
    /// (OffscreenWindow): the focus stays with the user. The tree is built here, so what the renderers log
    /// is captured here, as `present` does for a shown window. Titled "Preview", as on macOS.
    func renderOffscreen(_ content: Content, size: ContentSize?, delay: Double) async throws -> (image: CapturedImage, warnings: [String]) {
        var options = WinUIApplication.WindowOptions()
        if let size {
            options.contentSize = (Int(size.width), Int(size.height))
        }
        let built: (result: WinUIApplication.OffscreenWindow?, entries: [HostLogger.Entry])
        if let logger = host?.logger {
            built = logger.capture { application.renderOffscreen(prepared: content, title: "Preview", options: options) }
        } else {
            built = (application.renderOffscreen(prepared: content, title: "Preview", options: options), [])
        }
        let warnings = built.entries.filter { $0.level == .warning || $0.level == .error }.map(\.message)
        guard let render = built.result else {
            throw MCPToolError("the ActionUI JSON could not be rendered" + (warnings.isEmpty ? "" : ":\n" + warnings.prefix(20).joined(separator: "\n")))
        }
        defer { render.close() }
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        let file = HostSupport.sessionFolder.appendingPathComponent("render-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: file) }
        // A window shown a moment ago may not be drawn yet: tried again for up to two seconds.
        for _ in 0..<40 {
            let written: Bool = await withCheckedContinuation { continuation in
                render.capturePNG(path: file.path, maxPixels: WindowHost.maxScreenshotPixels) {
                    continuation.resume(returning: $0)
                }
            }
            if written, let png = try? Data(contentsOf: file), let size = Self.pngSize(png) {
                return (CapturedImage(png: png, pixelWidth: size.width, pixelHeight: size.height), warnings)
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        throw MCPToolError("the ActionUI JSON was not drawn in time to be captured")
    }

    func showNotice(title: String?, message: String, subtitle: String, duration: Double) async throws {
        throw MCPToolError("notices are not available on Windows yet")
    }

    nonisolated static func fileType(named name: String) -> String? {
        AppPanels.knowsFileType(name) ? name : nil
    }

    /// The system's file dialog, on a thread of its own: other tool calls are served meanwhile, and several
    /// panels can be up at a time.
    func beginPanel(_ spec: PanelSpec, completion: @escaping @MainActor ([String]?) -> Void) -> @MainActor () -> Void {
        var settings: [String: JSONValue] = [:]
        // A Windows file dialog has a title and no message. The provenance first: the title bar has one
        // line, and the agent's text after it can neither push it out of view nor come first.
        let message = spec.message.map { oneLine($0, limit: maxAgentTitleLength) }
        let heading = [spec.provenance, spec.title, message].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " - ")
        if !heading.isEmpty { settings["title"] = .string(heading) }
        // As a file URL, which the panel turns into the system's own path.
        if let directory = spec.directory { settings["directoryURL"] = .string(directory.absoluteString) }
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

    /// Where each window's frame is (its top-left corner in screen pixels) and its content's size as laid out
    /// now (the user may have moved or resized the window): the keeper opens each window there at that size.
    /// Only this layer's keeper reads the frame, so it mixes units: x and y in pixels, the size in effective
    /// pixels (at 200%, two pixels each). A window not laid out yet (the session ended right
    /// after it opened) is kept too, at size 0: the keeper then sizes it to fit, as on Linux.
    func keptWindowStates(_ ids: [String]) -> [KeptWindowState] {
        ids.compactMap { id in
            guard let window = shown[id] else { return nil }
            let size = application.contentSize(windowUUID: id) ?? (0, 0)
            let position = application.position(windowUUID: id)
            let style = (window.isResizable ? Self.resizableStyle : 0) | (position != nil ? Self.positionedStyle : 0)
            return KeptWindowState(id: id, title: window.title, subtitle: window.subtitle,
                                   frame: [Double(position?.x ?? 0), Double(position?.y ?? 0),
                                           size.width.rounded(), size.height.rounded()],
                                   styleMask: style)
        }
    }
}
#endif
