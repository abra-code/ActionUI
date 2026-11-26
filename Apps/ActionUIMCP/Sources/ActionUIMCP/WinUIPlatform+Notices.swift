// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

// WinUIPlatform+Notices.swift - notify on Windows: a short notice in a small window of its own at the bottom
// right of the work area, where Windows shows its notifications, with earlier ones above it (macOS puts the
// newest at the top right, earlier ones below it). It has no title bar, stays on top, is out of the taskbar
// and Alt+Tab, never takes the focus, and goes away after its duration or when clicked. Not a Windows
// notification (AppNotificationManager): those need an app identity an unzipped program does not have,
// and Focus Assist can hold them back.

#if os(Windows)
import FoundationEssentials
import ActionUIWinUIApplication
import MCPStdio

@MainActor
final class WinUINotice {
    let window: WinUIApplication.NoticeWindow
    /// The ActionUI window the notice's JSON was loaded for, whose model goes with the notice.
    let windowID: String
    var dismissTask: Task<Void, Never>?

    init(window: WinUIApplication.NoticeWindow, windowID: String) {
        self.window = window
        self.windowID = windowID
    }
}

extension WinUIPlatform {
    static let maxNotices = 4
    static let noticeWidth = 340.0
    /// Effective pixels from the work area's edges, and between notices.
    private static let noticeMargin = 12.0
    private static let noticeGap = 8.0

    /// The oldest notice goes when more than `maxNotices` would be on screen, or when they would not fit.
    func showNotice(title: String?, message: String, subtitle: String, duration: Double) async throws {
        guard let host else { return }
        var children: [[String: Any]] = []
        if let title, !title.isEmpty {
            children.append(["type": "Text", "properties": ["text": title, "font": "headline"]])
        }
        children.append(["type": "Text", "properties": ["markdown": message, "font": ["size": 13],
                                                       "frame": ["maxWidth": "infinity", "alignment": "leading"]]])
        children.append(["type": "Text", "properties": ["text": subtitle, "font": "caption", "foregroundStyle": "secondary"]])
        let ui: [String: Any] = [
            "type": "VStack",
            "properties": ["alignment": "leading", "spacing": 4, "padding": 14, "frame": ["width": Self.noticeWidth]],
            "children": children,
        ]
        let windowID = UUID().uuidString
        let loaded = try host.load(ui: ui, windowID: windowID)
        let errors = loaded.entries.filter { $0.level == .error }.map(\.message)
        guard errors.isEmpty, loaded.content.error == nil,
              let window = WinUIApplication.shared.makeNotice(prepared: loaded.content, title: "ActionUI MCP notice") else {
            host.forgetModel(windowID)
            let reasons = errors.isEmpty ? [loaded.content.error ?? "the notice's window could not be made"] : errors
            throw MCPToolError("the notice could not be shown:\n" + reasons.prefix(5).joined(separator: "\n"))
        }
        let notice = WinUINotice(window: window, windowID: windowID)
        notices.append(notice)
        // Older notices past the top of the work area would never be seen.
        while notices.count > Self.maxNotices || (notices.count > 1 && !noticesFit) {
            dismiss(notices[0])
        }
        // Placed at its first size, then again once it has its content's size (before it shows).
        layOutNotices()
        window.show { [weak self] in
            guard let self else { return }
            while self.notices.count > 1 && !self.noticesFit {
                self.dismiss(self.notices[0])
            }
            self.layOutNotices()
        }
        window.onTapped { [weak self, weak notice] in
            guard let notice else { return }
            self?.dismiss(notice)
        }
        notice.dismissTask = Task { @MainActor [weak self, weak notice] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled, let notice else { return }
            self?.dismiss(notice)
        }
    }

    private func dismiss(_ notice: WinUINotice) {
        guard let index = notices.firstIndex(where: { $0 === notice }) else { return }
        notices.remove(at: index)
        notice.dismissTask?.cancel()
        notice.window.close()
        host?.forgetModel(notice.windowID)
        layOutNotices()
    }

    /// The work area of the newest notice's monitor, and its pixels per effective pixel (from the notice's
    /// width, which is noticeWidth wide plus a border of a pixel or two).
    private var noticeArea: (area: WinUIApplication.NoticeWindow.Frame, scale: Double)? {
        guard let newest = notices.last, let area = newest.window.workArea, let frame = newest.window.frame,
              frame.width > 0 else { return nil }
        return (area, max(1, Double(frame.width) / Self.noticeWidth))
    }

    private var noticesFit: Bool {
        guard let (area, scale) = noticeArea else { return true }
        let heights = notices.compactMap { $0.window.frame.map { Double($0.height) } }
        let needed = heights.reduce(Self.noticeMargin * scale) { $0 + $1 + Self.noticeGap * scale }
        return needed <= Double(area.height)
    }

    /// Newest at the bottom right of the work area, older ones above it.
    private func layOutNotices() {
        guard let (area, scale) = noticeArea else { return }
        let margin = Int32((Self.noticeMargin * scale).rounded())
        let gap = Int32((Self.noticeGap * scale).rounded())
        var bottom = area.y + area.height - margin
        for notice in notices.reversed() {
            guard let frame = notice.window.frame else { continue }
            notice.window.move(x: area.x + area.width - margin - frame.width, y: bottom - frame.height)
            bottom -= frame.height + gap
        }
    }
}
#endif
