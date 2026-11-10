// ActionUIAdwaitaApplication/OffscreenWindow.swift
/*
 A document's window drawn where the user never sees it (AdwaitaApplication.renderOffscreen), for a
 host that shows an agent or a test what a document looks like before, or instead of, showing it.

 - The window is realized and never presented: it gets a renderer, and the compositor is never
   asked for a window (no xdg_toplevel), so nothing shows and the focus stays where it is. Its
   content is mapped and allocated by hand at the window's opening size, as GTK maps nothing in a
   window that is not shown.
 - A capture draws the content with the window's renderer, as capturePNG draws a window on screen,
   and with the same bars. What differs from a shown window: no rounded corners or shadow, no focus
   ring, controls in the inactive style (as on Apple), and the window background on the content (the
   window itself never draws). A WebView's page is not drawn (WebKit draws only in a window on
   screen); showsWebView says when one is there.
 - Nothing on it is clickable, and its document's modals, dialogs and toasts do not show; nor do an
   element's sheet or popover. Its size is fixed when it is built: content that grows later is
   clipped, where a shown window would grow. Its model stays the host's to remove, as for a
   prepared window.
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import CAdwaita
import ActionUI

extension AdwaitaApplication {
    @MainActor
    public final class OffscreenWindow {
        private let window: UnsafeMutablePointer<GtkWindow>
        private let toolbar: WidgetPointer
        private let renderTree: AdwaitaWindow
        private var allocation: GtkAllocation
        private var isClosed = false

        /// The window's size in pixels, bars included.
        public var width: Int { Int(allocation.width) }
        public var height: Int { Int(allocation.height) }
        /// The window's content: its bars and the document.
        var rootWidget: WidgetPointer { toolbar }

        init(window: UnsafeMutablePointer<GtkWindow>, toolbar: WidgetPointer, renderTree: AdwaitaWindow, width: Int32, height: Int32) {
            self.window = window
            self.toolbar = toolbar
            self.renderTree = renderTree
            // No smaller than GTK holds a shown window to: the window's own minimum (libadwaita's
            // windows are at least 360 wide) and its content's, the height at that width.
            var requestWidth: Int32 = 0
            var requestHeight: Int32 = 0
            gtk_widget_get_size_request(typed(window), &requestWidth, &requestHeight)
            let contentWidth = Int32(clamping: Gtk.Widget(toolbar).measure(GTK_ORIENTATION_HORIZONTAL).minimum)
            let finalWidth = max(width, requestWidth, contentWidth, 1)
            let contentHeight = Int32(clamping: Gtk.Widget(toolbar).measure(GTK_ORIENTATION_VERTICAL, forSize: Int(finalWidth)).minimum)
            allocation = GtkAllocation(x: 0, y: 0, width: finalWidth, height: max(height, requestHeight, contentHeight, 1))
            // The window's background, which the window would draw.
            gtk_widget_add_css_class(toolbar, "background")
            gtk_widget_realize(typed(window))
            gtk_widget_map(toolbar)
            gtk_widget_size_allocate(toolbar, &allocation, -1)
        }

        /// Saves what the window draws as a PNG file at `path`, scaled down to `maxPixels` on its
        /// longest side, redrawn at that size. Returns the image's size in pixels; nil when the
        /// window is closed or the file cannot be written.
        public func capturePNG(path: String, maxPixels: Int? = nil) -> (width: Int, height: Int)? {
            guard !isClosed, let renderer = gtk_native_get_renderer(OpaquePointer(window)),
                  let parent = gtk_widget_get_parent(toolbar) else { return nil }
            // Laid out again: content that loaded since (an image) has its place.
            gtk_widget_size_allocate(toolbar, &allocation, -1)
            let width = Double(allocation.width)
            let height = Double(allocation.height)
            let scale = maxPixels.map { min(1, Double(max($0, 1)) / max(width, height)) } ?? 1
            let snapshot = gtk_snapshot_new()!
            if scale < 1 {
                gtk_snapshot_scale(snapshot, Float(scale), Float(scale))
            }
            // From its parent (inside AdwWindow, not the window itself): a widget is drawn only
            // through its parent's snapshot.
            gtk_widget_snapshot_child(parent, toolbar, snapshot)
            guard let node = gtk_snapshot_free_to_node(snapshot) else { return nil }
            defer { gsk_render_node_unref(node) }
            var viewport = graphene_rect_t(origin: graphene_point_t(x: 0, y: 0),
                                           size: graphene_size_t(width: Float((width * scale).rounded()),
                                                                 height: Float((height * scale).rounded())))
            guard let rendered = gsk_renderer_render_texture(renderer, node, &viewport) else { return nil }
            let texture = OwnedObject(adopting: rendered)
            guard gdk_texture_save_to_png(texture.opaquePointer, path) != 0 else { return nil }
            return (Int(gdk_texture_get_width(texture.opaquePointer)), Int(gdk_texture_get_height(texture.opaquePointer)))
        }

        /// Whether the window holds a WebView, whose page a capture does not draw.
        public var showsWebView: Bool {
            func holdsWebView(_ widget: WidgetPointer) -> Bool {
                let instance = UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GTypeInstance.self)
                if let typeName = swiftString(g_type_name(instance.pointee.g_class.pointee.g_type)), typeName.hasPrefix("WebKitWebView") {
                    return true
                }
                var child = gtk_widget_get_first_child(widget)
                while let current = child {
                    if holdsWebView(current) { return true }
                    child = gtk_widget_get_next_sibling(current)
                }
                return false
            }
            return !isClosed && holdsWebView(toolbar)
        }

        /// Takes the window down: its nodes leave the tree, as for a closed window. A capture after
        /// it is nil.
        public func close() {
            guard !isClosed else { return }
            isClosed = true
            gtk_widget_unmap(toolbar)
            renderTree.detach()
            gtk_window_destroy(window)
        }

        isolated deinit {
            close()
        }
    }
}
