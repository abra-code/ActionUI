// Tests/Support/AdwaitaTestHost.swift
/*
 What the renderer tests share: GTK and libadwaita initialized once per process (or a reason to
 skip, when there is no display), and the GLib main loop run by hand, since no application runs it
 in a test.
*/

import XCTest
import CAdwaita
@testable import ActionUI

@MainActor
enum AdwaitaTestHost {
    private static var initialized: Bool?

    /// Initializes GTK, libadwaita and MainLoopBridge, once. Throws XCTSkip when GTK cannot open a
    /// display: the renderer tests then skip, and the Core tests in the same run still pass.
    static func initialize() throws {
        if initialized == nil {
            let opened = gtk_init_check() != 0
            if opened {
                adw_init()
                MainLoopBridge.install()
            }
            initialized = opened
        }
        if initialized != true {
            throw XCTSkip("GTK could not open a display; renderer tests run in the desktop session")
        }
    }

    /// Runs the default main context until nothing is ready to run. This also runs libdispatch's
    /// main queue, through MainLoopBridge.
    static func drainMainLoop() {
        var iterations = 0
        while g_main_context_iteration(nil, 0) != 0 && iterations < 10_000 {
            iterations += 1
        }
    }

    /// Emits a signal that takes no arguments and returns nothing ("clicked", "activate"), as the
    /// user's input would, synchronously. (gtk_widget_activate on a button only starts its press
    /// animation, and g_signal_emit_by_name is variadic, which Swift cannot call.)
    static func emit(_ signal: String, on instance: UnsafeMutableRawPointer) {
        let type = instance.assumingMemoryBound(to: GTypeInstance.self).pointee.g_class.pointee.g_type
        let id = g_signal_lookup(signal, type)
        precondition(id != 0, "\(signal) is not a signal of this object")
        var target = GValue()
        g_value_init(&target, type)
        g_value_set_object(&target, instance)
        g_signal_emitv(&target, id, 0, nil)
        g_value_unset(&target)
    }

    /// Runs the default main context until `condition` holds, waiting for sources such as timers,
    /// for at most `timeoutMilliseconds`. Returns whether the condition held.
    static func runMainLoop(until condition: () -> Bool, timeoutMilliseconds: Int = 2000) -> Bool {
        let deadline = g_get_monotonic_time() + timeoutMilliseconds * 1000
        while !condition() {
            if g_get_monotonic_time() >= deadline {
                return false
            }
            // Non-blocking, so the deadline is checked even when nothing ever becomes ready.
            if g_main_context_iteration(nil, 0) == 0 {
                g_usleep(1000)
            }
        }
        return true
    }

    /// What `widget` draws at its allocated size, after `root` (the widget or an ancestor of it) is
    /// shown in a window and mapped, with that size; nil if it drew nothing. The caller unrefs the
    /// node. (A window is at least as wide as GTK's minimum, so a root drawn whole would be scaled
    /// to the size asked for.)
    static func drawing(of widget: WidgetPointer, shownIn root: WidgetPointer) -> (node: OpaquePointer, width: Int32, height: Int32)? {
        let window = gtk_window_new()!
        defer { gtk_window_destroy(typed(window)) }
        gtk_window_set_child(typed(window), root)
        gtk_window_present(typed(window))
        defer { gtk_window_set_child(typed(window), nil) }
        guard runMainLoop(until: { gtk_widget_get_mapped(widget) != 0 }) else { return nil }
        drainMainLoop()
        let width = gtk_widget_get_width(widget)
        let height = gtk_widget_get_height(widget)
        let paintable = gtk_widget_paintable_new(widget)!
        defer { g_object_unref(UnsafeMutableRawPointer(paintable)) }
        let snapshot = gtk_snapshot_new()!
        gdk_paintable_snapshot(paintable, snapshot, Double(width), Double(height))
        guard let node = gtk_snapshot_free_to_node(snapshot) else { return nil }
        return (node, width, height)
    }

    /// The pixels `node` paints in a `width` x `height` area, rendered with GTK's cairo renderer:
    /// 4 bytes per pixel, red, green, blue, alpha (not premultiplied), rows top to bottom.
    static func pixels(of node: OpaquePointer, width: Int32, height: Int32) -> [UInt8]? {
        guard let display = gdk_display_get_default() else { return nil }
        let renderer = gsk_cairo_renderer_new()!
        defer { g_object_unref(UnsafeMutableRawPointer(renderer)) }
        guard gsk_renderer_realize_for_display(renderer, display, nil) != 0 else { return nil }
        defer { gsk_renderer_unrealize(renderer) }
        var viewport = graphene_rect_t(origin: graphene_point_t(x: 0, y: 0),
                                       size: graphene_size_t(width: Float(width), height: Float(height)))
        let texture = gsk_renderer_render_texture(renderer, node, &viewport)!
        defer { g_object_unref(UnsafeMutableRawPointer(texture)) }
        let downloader = gdk_texture_downloader_new(texture)!
        defer { gdk_texture_downloader_free(downloader) }
        gdk_texture_downloader_set_format(downloader, GDK_MEMORY_R8G8B8A8)
        let stride = Int(width) * 4
        var bytes = [UInt8](repeating: 0, count: stride * Int(height))
        gdk_texture_downloader_download_into(downloader, &bytes, gsize(stride))
        return bytes
    }

    /// Whether `node` or a node inside it is of `type`.
    static func contains(_ node: OpaquePointer, _ type: GskRenderNodeType) -> Bool {
        let own = gsk_render_node_get_node_type(node)
        if own == type { return true }
        switch own {
        case GSK_CONTAINER_NODE:
            for index in 0..<gsk_container_node_get_n_children(node) {
                if let child = gsk_container_node_get_child(node, index), contains(child, type) { return true }
            }
            return false
        case GSK_TRANSFORM_NODE: return gsk_transform_node_get_child(node).map { contains($0, type) } ?? false
        case GSK_OPACITY_NODE: return gsk_opacity_node_get_child(node).map { contains($0, type) } ?? false
        case GSK_CLIP_NODE: return gsk_clip_node_get_child(node).map { contains($0, type) } ?? false
        case GSK_ROUNDED_CLIP_NODE: return gsk_rounded_clip_node_get_child(node).map { contains($0, type) } ?? false
        case GSK_DEBUG_NODE: return gsk_debug_node_get_child(node).map { contains($0, type) } ?? false
        case GSK_COLOR_MATRIX_NODE: return gsk_color_matrix_node_get_child(node).map { contains($0, type) } ?? false
        default: return false
        }
    }
}

/// A counter the main-actor closures under test can change.
@MainActor
final class CallCounter {
    var count = 0
}
