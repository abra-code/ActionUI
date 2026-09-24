// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

// WindowHost+Notices.swift - notify: a short notice in a small floating panel at the top right of
// the screen, stacked under earlier ones. It never takes focus, adds no Dock icon, and goes away
// after its duration or when clicked. Not a system user notification: those need an app bundle
// and the user's permission, and a toast inside an open window is missed when that window is
// behind others or when there is none.

import AppKit
import MCPStdio

/// A panel that never becomes key or main, so showing it cannot take focus from the user.
private final class NoticePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class Notice {
    let panel: NSPanel
    /// Owns the SwiftUI tree.
    let controller: NSViewController
    var dismissTask: Task<Void, Never>?

    init(panel: NSPanel, controller: NSViewController) {
        self.panel = panel
        self.controller = controller
    }
}

extension WindowHost {
    static let maxNotices = 4
    static let noticeWidth = 340.0
    nonisolated static let maxNoticeLength = 1000
    private static let noticeMargin = 16.0
    private static let noticeGap = 8.0

    /// Shows a notice for `duration` seconds. The oldest notice goes when more than `maxNotices`
    /// would be on screen.
    func showNotice(title: String?, message: String, subtitle: String, duration: Double) throws {
        var children: [[String: Any]] = []
        if let title, !title.isEmpty {
            children.append(["type": "Text", "properties": ["text": title, "font": "headline"]])
        }
        children.append(["type": "Text", "properties": ["markdown": message, "font": ["size": 13],
                                                       "frame": ["maxWidth": "infinity", "alignment": "leading"]]])
        children.append(["type": "Text", "properties": ["text": subtitle, "font": "caption", "foregroundStyle": "secondary"]])
        let document: [String: Any] = [
            "type": "VStack",
            "properties": ["alignment": "leading", "spacing": 4, "padding": 14, "frame": ["width": Self.noticeWidth]],
            "children": children,
        ]
        let loaded = try load(document: document, windowID: UUID().uuidString)
        let errors = loaded.entries.filter { $0.level == .error }.map(\.message)
        guard errors.isEmpty else {
            throw MCPToolError("the notice could not be shown:\n" + errors.prefix(5).joined(separator: "\n"))
        }
        let size = NSSize(width: Self.noticeWidth, height: max(loaded.fitting.height, 40))

        let panel = NoticePanel(contentRect: NSRect(origin: .zero, size: size),
                                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.level = .floating
        // The app is never active while a notice shows; a default panel would hide at once.
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 12
        background.layer?.masksToBounds = true
        let content = loaded.controller.view
        content.frame = background.bounds
        content.autoresizingMask = [.width, .height]
        background.addSubview(content)
        background.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(noticeClicked(_:))))
        panel.contentView = background

        let notice = Notice(panel: panel, controller: loaded.controller)
        notices.append(notice)
        // Older notices below the bottom of the screen would never be seen.
        while notices.count > Self.maxNotices || (notices.count > 1 && !noticesFitOnScreen) {
            dismiss(notices[0])
        }
        layOutNotices()
        panel.orderFrontRegardless()
        notice.dismissTask = Task { @MainActor [weak self, weak notice] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled, let notice else { return }
            self?.dismiss(notice)
        }
        #if DEBUG
        captureNoticeForTest(panel)
        #endif
    }

    @objc private func noticeClicked(_ recognizer: NSClickGestureRecognizer) {
        guard let notice = notices.first(where: { $0.panel === recognizer.view?.window }) else { return }
        dismiss(notice)
    }

    private func dismiss(_ notice: Notice) {
        guard let index = notices.firstIndex(where: { $0 === notice }) else { return }
        notices.remove(at: index)
        notice.dismissTask?.cancel()
        notice.panel.close()
        layOutNotices()
    }

    private var noticesFitOnScreen: Bool {
        guard let screen = NSScreen.main?.visibleFrame else { return true }
        return notices.reduce(Self.noticeMargin) { $0 + $1.panel.frame.height + Self.noticeGap } <= screen.height
    }

    /// Newest at the top right, older ones below it.
    private func layOutNotices() {
        guard let screen = NSScreen.main?.visibleFrame else { return }
        var top = screen.maxY - Self.noticeMargin
        for notice in notices.reversed() {
            let size = notice.panel.frame.size
            notice.panel.setFrameOrigin(NSPoint(x: screen.maxX - Self.noticeMargin - size.width, y: top - size.height))
            top -= size.height + Self.noticeGap
        }
    }

    #if DEBUG
    /// ACTIONUI_MCP_TEST_NOTICE_CAPTURE=1: save a PNG of each notice and log its path, to check the
    /// layout with no one at the screen.
    private func captureNoticeForTest(_ panel: NSPanel) {
        guard ProcessInfo.processInfo.environment["ACTIONUI_MCP_TEST_NOTICE_CAPTURE"] == "1" else { return }
        if let shot = try? screenshot(of: panel, name: "notice") {
            FileHandle.standardError.write(Data("[actionui-mcp] notice captured \(shot.path)\n".utf8))
        }
    }
    #endif
}
