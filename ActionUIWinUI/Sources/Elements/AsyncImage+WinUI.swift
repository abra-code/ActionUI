// Sources/Elements/AsyncImage+WinUI.swift
/*
 AsyncImage on WinUI: the image a URL names (the value set at run time when it is a non-empty String,
 else the url property, as on Apple and Linux), loaded by WinUI's Image without blocking the window
 (http, https and file URLs; one whose path ends in .svg as a vector image). Until it has loaded, and
 when it cannot be loaded, the placeholder symbol shows at Image's medium size, as SwiftUI shows
 Image(systemName:) in the empty and failure phases.

 - The URL is read as Apple's URL(string:) reads it (Core's Link.destination): with none, or text that
   is no URL, the placeholder shows (logged once per text, as on Apple); a URL without a scheme
   ("photo.png") cannot be loaded, as on Apple. A file URL loads only a regular file: a missing file, a
   folder, a device (NUL, COM1) or a pipe shows the placeholder (logged), and is never opened.
 - resizable (true unless set false) scales the image to its frame keeping its aspect ratio, fit
   (contained) or fill (covered, clipped to the frame where SwiftUI draws past it, as Image and Linux);
   not resizable, it shows at its own size, never scaled up. The placeholder is never scaled.
 - The image loads in its own WinUI Image held behind the placeholder (ImageLayout.setLoading), laid
   out where it will show, and replaces the placeholder once WinUI reports it opened. A URL that failed
   is not loaded again until the URL changes; WinUI's image cache serves a URL shown before. WinUI
   decodes an image at the size it is drawn, so one that is not drawn (in a hidden tab) shows its
   placeholder until it is.

 Not yet: an SVG served from a URL whose path does not end in .svg (read as a bitmap, so it fails); a
 Windows path given as the URL ("C:\pics\a.png") may load where Apple's URL(string:) reads "c" as its
 scheme and loads nothing.
*/

import CWinUI

/// What an AsyncImage keeps: its layout, the image loading or loaded, and the URL it is for.
@MainActor final class AsyncImageState {
    let layout: ImageLayout
    /// The WinUI Image for `imageURL`, loading or loaded.
    var image: WinUIObject?
    var imageURL: String?
    var loaded = false
    /// The last URL that could not be loaded: the placeholder stays until the URL changes.
    var failedURL: String?
    /// The last URL text reported as no URL (logged once per text).
    var reportedText: String??

    init(layout: ImageLayout) {
        self.layout = layout
    }
}

extension AsyncImage: ActionUIWinUIRenderer {
    static func makeView(_ node: RenderNode) throws(WinUIError) -> WinUIObject {
        let layout = try ImageLayout()
        node.state = AsyncImageState(layout: layout)
        return layout.panel.object
    }

    static func update(_ view: WinUIObject, _ node: RenderNode) {
        guard let state = node.state as? AsyncImageState else { return }
        let layout = state.layout
        let props = Props(node.properties)
        let text = url(node)
        if text != state.failedURL {
            state.failedURL = nil
        }
        // The URL to load: an absolute one that has not failed.
        var wanted: String?
        switch Link.destination(text) {
        case .absolute:
            state.reportedText = nil
            wanted = text == state.failedURL ? nil : text
        case .relative:
            report(text, "cannot be loaded (it has no scheme)", state)
        case .none:
            report(text, "is missing or no valid URL", state)
        }
        let stretch: ActionUIWinUIImageStretch = props.resizable ? (props.contentMode == .fill ? ActionUIWinUIImageStretchFill : ActionUIWinUIImageStretchFit)
                                                                 : ActionUIWinUIImageStretchNone
        var changed = false
        if stretch != layout.stretch {
            layout.stretch = stretch
            changed = true
        }
        if wanted != state.imageURL {
            load(wanted, node, state)
            changed = true
        }
        if let image = state.image, !actionUIWinUIImageSetStretch(image.pointer, stretch) {
            ActionUIModel.shared.logger.log("AsyncImage: \(WinUIError.last("scaling an image"))", .error)
        }
        // The loaded image, else the placeholder (never scaled to the frame, as SwiftUI's Image(systemName:)).
        if state.loaded, let image = state.image, let url = state.imageURL {
            if layout.child !== image {
                layout.show(image, for: .file(url))
                changed = true
            }
            if layout.resizable != props.resizable {
                layout.resizable = props.resizable
                changed = true
            }
        } else {
            let placeholder = ImageContent.symbol(props.placeholder)
            if layout.content != placeholder {
                layout.show(ImageLayout.makeSymbol(props.placeholder), for: placeholder)
                changed = true
            }
            if layout.resizable {
                layout.resizable = false
                changed = true
            }
            let side = ImageLayout.symbolSide(node, scale: nil)
            if side != layout.symbolSide {
                layout.symbolSide = side
                changed = true
            }
            if let child = layout.child {
                // The foregroundStyle in effect, else the inherited text color, as Image's symbols.
                Paint.apply(Paint.parse(node.textAppearance.foreground, role: .foreground, tint: node.textAppearance.tint), ActionUIWinUIBrushForeground,
                            to: child, what: "a placeholder symbol")
            }
        }
        if let child = layout.child {
            node.applyAccessibilityHidden(to: child)
        }
        if changed {
            layout.panel.invalidateLayout()
        }
    }

    /// The URL text: the runtime value when it is a non-empty String, else the url property (nil when
    /// empty). A tracked read of the value and properties.
    static func url(_ node: RenderNode) -> String? {
        if let value = node.model.value as? String, !value.isEmpty {
            return value
        }
        return Props(node.properties).url.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Starts loading `url` (nil: none) in a new WinUI Image, dropping the image of the URL before: an
    /// event of a dropped image is ignored.
    private static func load(_ url: String?, _ node: RenderNode, _ state: AsyncImageState) {
        state.layout.setLoading(nil)
        state.image = nil
        state.imageURL = url
        state.loaded = false
        guard let url else { return }
        guard let image = WinUIObject(adopting: actionUIWinUIImageCreate()) else {
            ActionUIModel.shared.logger.log("AsyncImage: \(WinUIError.last("creating an image"))", .error)
            fail(url, state)
            return
        }
        // Not read while it loads behind the placeholder; once it shows, the update applies the node's
        // own setting.
        if !actionUIWinUIElementSetAccessibilityHidden(image.pointer, true) {
            ActionUIModel.shared.logger.log("AsyncImage: \(WinUIError.last("hiding the loading image from accessibility tools"))", .error)
        }
        WinUIEvents.connect(image, actionUIWinUIImageOnOpened, "an AsyncImage's image opening") { [weak node, weak state, weak image] in
            guard let node, let state, let image, state.image === image, !state.loaded, node.isAttached else { return }
            state.loaded = true
            SyncScheduler.shared.markDirty(node)
        }
        WinUIEvents.connect(image, actionUIWinUIImageOnFailed, "an AsyncImage's image failing") { [weak node, weak state, weak image] in
            guard let node, let state, let image, state.image === image, node.isAttached else { return }
            ActionUIModel.shared.logger.log("AsyncImage: \(url) could not be loaded; showing the placeholder", .warning)
            fail(url, state)
            SyncScheduler.shared.markDirty(node)
        }
        state.image = image
        guard actionUIWinUIImageSetURL(image.pointer, url) else {
            // Text Apple's URL(string:) takes that Windows' URI parser refuses, or a file URL that names
            // no regular file (a missing file, a folder, a device, a pipe: never opened), as on Apple.
            ActionUIModel.shared.logger.log("AsyncImage: \(WinUIError.last("loading \(url)")); showing the placeholder", .warning)
            fail(url, state)
            return
        }
        state.layout.setLoading(image)
    }

    /// `url` could not be loaded: the placeholder stays until the URL changes.
    private static func fail(_ url: String, _ state: AsyncImageState) {
        state.failedURL = url
        state.layout.setLoading(nil)
        state.image = nil
        state.loaded = false
        // No image: the update finds the URL failed and loads nothing until the URL changes.
        state.imageURL = nil
    }

    /// Logs once per text that `text` cannot be shown, as Apple logs a missing URL.
    private static func report(_ text: String?, _ why: String, _ state: AsyncImageState) {
        guard state.reportedText != .some(text) else { return }
        state.reportedText = .some(text)
        let what = text.map { "the URL \"\($0)\"" } ?? "the URL"
        ActionUIModel.shared.logger.log("AsyncImage: \(what) \(why); showing the placeholder", .warning)
    }
}
