// Sources/Elements/AsyncImage+Adwaita.swift
/*
 AsyncImage on GTK: the image a URL names (the value set at run time, else the url property, as on
 Apple), loaded without blocking the window (RemoteImages: libsoup for http and https, GIO for file
 URLs) and shown in a GtkPicture. Until it has loaded, and when it cannot be loaded, the
 placeholder symbol shows, at Image's medium size, as SwiftUI shows Image(systemName:) in the
 empty and failure phases.

 - resizable (true unless set false) scales the image to its frame keeping its aspect ratio, fit
   (contain) or fill (cover, clipped to the frame where SwiftUI draws past it), as a resizable
   Image file does; not resizable, it shows at its own size, never scaled up.
 - A URL that failed is not loaded again until the URL changes; the same URL shown in several
   places, or shown again while it is kept, loads once.
 - The placeholder and the picture are two widget types, so the image arriving replaces the
   widget (widgetKind).
*/

import CAdwaita

private let asyncImageStateKey = AttachKey<AsyncImageState>("actionui-async-image-state")

/// What the widget shows and asked for, kept on it.
@MainActor private final class AsyncImageState {
    let kind: AsyncImage.Kind
    /// The URL this widget is waiting for, so an update asks for it once.
    var requestedURL: String?
    /// The last URL that gave no image: the placeholder stays until the URL changes.
    var failedURL: String?
    /// The texture a picture shows, and its URL: still shown when RemoteImages drops it.
    var texture: LoadedTexture?
    var textureURL: String?

    init(kind: AsyncImage.Kind) {
        self.kind = kind
    }
}

extension AsyncImage: ActionUIAdwaitaRenderer {
    enum Kind: Int {
        case placeholder = 0, picture
    }

    static func widgetKind(_ node: RenderNode) -> Int {
        (texture(url(node), node) != nil ? Kind.picture : Kind.placeholder).rawValue
    }

    static func makeWidget(_ node: RenderNode) -> WidgetPointer {
        let kind = Kind(rawValue: node.widgetKind) ?? .placeholder
        let widget = kind == .picture ? gtk_picture_new()! : gtk_image_new()!
        attach(AsyncImageState(kind: kind), to: widget, key: asyncImageStateKey)
        return widget
    }

    static func update(_ widget: WidgetPointer, _ node: RenderNode) {
        guard let state = attached(on: widget, key: asyncImageStateKey) else { return }
        let props = Props(node.properties)
        let url = url(node)
        let texture = texture(url, node)
        // The image arrived (or went from the cache): the next sync makes the other widget.
        guard (texture != nil ? Kind.picture : Kind.placeholder) == state.kind else {
            SyncScheduler.shared.markDirty(node)
            return
        }
        if let texture {
            let picture = opaque(widget)
            if state.texture !== texture {
                state.texture = texture
                state.textureURL = url
                gtk_picture_set_paintable(picture, texture.pointer)
            }
            let canShrink: gboolean = props.resizable ? 1 : 0
            if gtk_picture_get_can_shrink(picture) != canShrink {
                gtk_picture_set_can_shrink(picture, canShrink)
            }
            // Not resizable: its own size, never scaled up when given more room, as on Apple.
            let fit = !props.resizable ? GTK_CONTENT_FIT_SCALE_DOWN : props.contentMode == .fill ? GTK_CONTENT_FIT_COVER : GTK_CONTENT_FIT_CONTAIN
            if gtk_picture_get_content_fit(picture) != fit {
                gtk_picture_set_content_fit(picture, fit)
            }
            setExpands(widget, props.resizable)
            return
        }
        let icon = Image.iconName(.symbol(props.placeholder))
        if swiftString(gtk_image_get_icon_name(opaque(widget))) != icon {
            gtk_image_set_from_icon_name(opaque(widget), icon)
        }
        StyleSheet.shared.apply(["-gtk-icon-size: \(Image.iconSize(nil))em;"], to: widget, slot: "iconSize")
        guard let url else {
            ActionUIModel.shared.logger.log("AsyncImage missing valid url, using placeholder '\(props.placeholder)'", .warning)
            return
        }
        guard url != state.failedURL, url != state.requestedURL else { return }
        state.requestedURL = url
        RemoteImages.shared.load(url) { [weak node, weak state] loaded in
            guard let state, state.requestedURL == url else { return }
            state.requestedURL = nil
            if !loaded {
                state.failedURL = url
            }
            if let node {
                SyncScheduler.shared.markDirty(node)
            }
        }
    }

    /// The URL shown: the runtime value when it is a non-empty String, else the url property.
    static func url(_ node: RenderNode) -> String? {
        if let value = node.model.value as? String, !value.isEmpty {
            return value
        }
        return Props(node.properties).url.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// The texture for `url`: the one RemoteImages keeps, else the one the node's picture shows for
    /// it, so a texture the cache dropped does not turn back into the placeholder and load again.
    private static func texture(_ url: String?, _ node: RenderNode) -> LoadedTexture? {
        guard let url else { return nil }
        if let kept = RemoteImages.shared.texture(url) { return kept }
        // No widget yet while the node is being made.
        guard let widget = node.widget, let state = attached(on: widget, key: asyncImageStateKey),
              state.textureURL == url else { return nil }
        return state.texture
    }

    private static func setExpands(_ widget: WidgetPointer, _ expands: Bool) {
        let value: gboolean = expands ? 1 : 0
        if gtk_widget_get_hexpand(widget) != value { gtk_widget_set_hexpand(widget, value) }
        if gtk_widget_get_vexpand(widget) != value { gtk_widget_set_vexpand(widget, value) }
    }
}
