// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

// AppKitPlatform+ShowFooter.swift - the row in the yellow bar of a `show` window, under the bar's
// notches (AppKitPlatform+HazardStrip.swift): where the content came from (a file, with a button
// that shows it in the Finder, or a web address), when the window was shown, and a Save button (Copy
// URL for content from the network). It is AppKit, outside the ActionUI JSON, so the agent can
// neither change it nor press its buttons; it keeps working in a kept window after the session ends.

#if canImport(AppKit)
import AppKit
import MCPStdio

final class ShowFooterView: NSView {
    private let path: String?
    private let url: String?
    private let save: ShowSave?
    private let windowID: String
    /// The view showing the ActionUI content, drawn for a chart's PNG.
    private weak var content: NSView?

    init(footer: ShowFooter, windowID: String, content: NSView) {
        path = footer.path
        url = footer.url
        save = footer.save
        self.windowID = windowID
        self.content = content
        super.init(frame: .zero)
        // The yellow is the same in dark mode, so the text and buttons on it are drawn light.
        appearance = NSAppearance(named: .aqua)

        var items: [NSView] = []
        if let source = footer.path ?? footer.url {
            let label = Self.label(ShowFooter.shownSource(source))
            label.lineBreakMode = .byTruncatingMiddle
            label.isSelectable = true
            label.toolTip = source
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            label.setContentHuggingPriority(.defaultLow, for: .horizontal)
            items.append(label)
        }
        if footer.path != nil {
            let reveal = NSButton(image: NSImage(systemSymbolName: "folder", accessibilityDescription: "Show in Finder") ?? NSImage(),
                                  target: self, action: #selector(revealInFinder))
            reveal.isBordered = false
            reveal.contentTintColor = NSColor(white: 0.15, alpha: 1)
            reveal.imageScaling = .scaleProportionallyDown
            reveal.toolTip = "Show in Finder"
            reveal.setAccessibilityLabel("Show in Finder")
            items.append(reveal)
        }
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        items.append(spacer)
        let shown = Self.label(footer.shownAt.formatted(date: .abbreviated, time: .shortened))
        shown.toolTip = "When the window was shown"
        shown.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        items.append(shown)
        if let save {
            items.append(Self.button("Save\u{2026}", help: "Save a copy of what the window shows", target: self, action: #selector(saveCopy)))
            #if DEBUG
            scheduleTestSave(save)
            #endif
        } else if url != nil {
            items.append(Self.button("Copy URL", help: "Copy the web address", target: self, action: #selector(copyURL)))
        }

        let row = NSStackView(views: items)
        row.orientation = .horizontal
        row.spacing = 6
        row.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    private static func button(_ title: String, help: String, target: AnyObject, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: target, action: action)
        button.controlSize = .small
        button.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        button.toolTip = help
        button.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        return button
    }

    private static func label(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = NSColor(white: 0.15, alpha: 1)
        return label
    }

    /// Selects the file in a Finder window; never opens it. A file that is gone gets a beep.
    @objc private func revealInFinder() {
        guard let path, FileManager.default.fileExists(atPath: path) else {
            NSSound.beep()
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    @objc private func copyURL() {
        guard let url else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)
    }

    /// Asks where with a save panel on the window, then writes there; the panel confirms replacing
    /// a file. Nothing is written anywhere else.
    @objc private func saveCopy() {
        guard let save, let window else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = save.suggestedName
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let destination = panel.url, let self else { return }
            do {
                try self.write(save.content, to: destination)
            } catch {
                let alert = NSAlert()
                alert.messageText = "The copy could not be saved."
                alert.informativeText = error.localizedDescription
                alert.beginSheetModal(for: window)
            }
        }
    }

    private func write(_ content: ShowSave.Content, to destination: URL) throws {
        switch content {
        case .file(let path):
            let source = URL(fileURLWithPath: path)
            // Saving a file onto itself: it is already there, and removing it first would lose it.
            if source.resolvingSymlinksInPath().standardizedFileURL == destination.resolvingSymlinksInPath().standardizedFileURL { return }
            let staged = destination.deletingLastPathComponent()
                .appendingPathComponent(".\(destination.lastPathComponent).\(UUID().uuidString)")
            do {
                try FileManager.default.copyItem(at: source, to: staged)
                // replaceItemAt fails on a symbolic link ("doesn't exist"); replace the link itself,
                // as the atomic writes below do.
                let isLink = (try? destination.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true
                if isLink {
                    guard rename(staged.path, destination.path) == 0 else {
                        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
                    }
                } else {
                    _ = try FileManager.default.replaceItemAt(destination, withItemAt: staged)
                }
            } catch {
                try? FileManager.default.removeItem(at: staged)
                throw error
            }
        default:
            try ShowSave.bytes(of: content, windowID: windowID, chartPNG: chartPNG)?.write(to: destination, options: .atomic)
        }
    }

    #if DEBUG
    /// ACTIONUI_MCP_TEST_SAVE_DIR=<folder>: for the live test, 1.5 seconds after the window opens,
    /// save as the Save button does, into that folder under the offered name, with no panel.
    private func scheduleTestSave(_ save: ShowSave) {
        guard let folder = ProcessInfo.processInfo.environment["ACTIONUI_MCP_TEST_SAVE_DIR"] else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            let destination = URL(fileURLWithPath: folder).appendingPathComponent(save.suggestedName)
            do {
                try self?.write(save.content, to: destination)
            } catch {
                HostSupport.logLine("[actionui-mcp] test save failed: \(error)")
            }
        }
    }
    #endif

    /// The content view drawn into a bitmap at the screen's scale, as a PNG.
    private func chartPNG() throws -> Data {
        guard let content, let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) else {
            throw MCPToolError("the chart could not be drawn")
        }
        content.cacheDisplay(in: content.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { throw MCPToolError("the chart could not be encoded") }
        return png
    }
}
#endif
