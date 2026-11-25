// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

// WinUIPlatform.swift - the windows on Windows, through ActionUI's WinUI application. A window's subtitle
// (the provenance line) shows before its title in the title bar, which has one line and cuts a long one at
// its end: the agent's title can neither push it out of view nor come first. Not yet on Windows:
// windows kept after the session, rendering without showing a window, notices and file panels; each
// answers that it is not available here.

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
    nonisolated static let keepsWindows = false
    /// The application removes a closed window's model itself, after its disappear actions.
    nonisolated static let removesClosedWindowModels = true

    weak var host: WindowHost?
    private let application = WinUIApplication.shared

    init() {
        application.handlers.windowWillClose = { [weak self] windowID in
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

    func renderOffscreen(_ content: Content, size: ContentSize?, delay: Double) async throws -> (image: CapturedImage, warnings: [String]) {
        throw MCPToolError("rendering ActionUI JSON without showing it is not available on Windows yet; open it with show_ui and screenshot that window")
    }

    func showNotice(title: String?, message: String, subtitle: String, duration: Double) async throws {
        throw MCPToolError("notices are not available on Windows yet")
    }

    nonisolated static func fileType(named name: String) -> String? {
        name.isEmpty ? nil : name
    }

    /// Not available on Windows yet: answers as a canceled panel, logged.
    func beginPanel(_ spec: PanelSpec, completion: @escaping @MainActor ([String]?) -> Void) -> @MainActor () -> Void {
        host?.logger.log("file panels are not available on Windows yet", .warning)
        completion(nil)
        return {}
    }

    /// No windows are kept on Windows yet (keepsWindows is false).
    func keptWindowStates(_ ids: [String]) -> [KeptWindowState] {
        []
    }
}
#endif
