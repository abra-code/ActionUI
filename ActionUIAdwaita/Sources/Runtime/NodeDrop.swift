// Sources/Runtime/NodeDrop.swift
/*
 onDropActionID on GTK: the element's frame takes drops of the kinds its onDropTypes name (Apple's
 uniform type identifiers), as SwiftUI's onDrop(of:isTargeted:perform:) does.

 - Text types (public.text, public.plain-text, public.utf8-plain-text, public.utf16-plain-text)
   take dropped text; file types (public.file-url, public.folder, public.directory) take dropped
   files and folders, reported by their paths, as the SwiftUI renderer reads a provider (text, else
   a file URL's path). public.url takes a URI list: files by their paths, other URIs as they are
   (on Apple a file URL is a URL, and text is not); public.item takes both kinds. Other types are
   logged once and take nothing.
 - Files are asked for before text: a GTK file drag also offers its paths as one text, which would
   otherwise give one item for all the files.
 - A drop fires onDropActionID with {"items": [String], "location": {"x", "y"}}, the point in the
   element's frame, as SwiftUI reports it.
 - A drag of a kind the element takes entering the frame fires onDropTargetedActionID with
   {"isTargeted": true}, leaving it (or dropping) with false, as SwiftUI's isTargeted binding
   changes.
 - As on Apple (a Task), the actions fire on the main queue's next turn.
 - The frame is the box's content group, as for onHover: not the space a parent gives the box
   beyond it.

 Only an element declaring onDropActionID and onDropTypes when its node is made takes drops; the
 kinds are the ones it declared then. The action ids are read at the drop.
*/

import CAdwaita
import Dispatch

@MainActor
enum NodeDrop {
    /// What a type identifier takes on Linux.
    enum Kind {
        case text, files
    }

    private static var reportedTypes: Set<String> = []

    /// The kinds of drop Apple's type identifier `type` names on Linux, none for one Linux does not
    /// take yet.
    static func kinds(_ type: String) -> [Kind] {
        switch type {
        case "public.text", "public.plain-text", "public.utf8-plain-text", "public.utf16-plain-text":
            return [.text]
        case "public.file-url", "public.folder", "public.directory", "public.url":
            return [.files]
        case "public.item":
            return [.files, .text]
        default:
            return []
        }
    }

    /// Makes `node`'s frame take drops when its element declares a drop. Called while the node is
    /// made, which may be in its parent's sync: the read is untracked.
    static func watch(_ node: RenderNode) {
        guard let drop = UntrackedReads.perform({ BaseModifiers(node.properties).drop }) else { return }
        var kinds: Set<Kind> = []
        for type in drop.types {
            let taken = Self.kinds(type)
            if taken.isEmpty, reportedTypes.insert(type).inserted {
                ActionUIModel.shared.logger.log("onDrop: \(type) is not taken on Linux yet", .warning)
            }
            kinds.formUnion(taken)
        }
        guard !kinds.isEmpty else { return }
        let target = gtk_drop_target_new(GType(0), GDK_ACTION_COPY)!
        // GTK reads the first of these the drag offers: files before text (see above).
        var gtypes: [GType] = []
        if kinds.contains(.files) {
            gtypes.append(gdk_file_list_get_type())
        }
        if kinds.contains(.text) {
            gtypes.append(g_type_from_name("gchararray"))
        }
        gtk_drop_target_set_gtypes(target, &gtypes, gsize(gtypes.count))
        // Entering sets the current drop, leaving or dropping clears it.
        connectSignal(UnsafeMutableRawPointer(target), "notify::current-drop", .instanceAndArgument) { [weak node] in
            guard let node, node.isAttached else { return }
            let targeted = gtk_drop_target_get_current_drop(target) != nil
            guard let actionID = UntrackedReads.perform({ BaseModifiers(node.properties).drop?.targetedActionID }) else { return }
            fire(node, actionID) { ["isTargeted": targeted] }
        }
        connectDrop(UnsafeMutableRawPointer(target)) { [weak node] value, x, y in
            guard let node, node.isAttached,
                  let actionID = UntrackedReads.perform({ BaseModifiers(node.properties).drop?.actionID }) else { return false }
            // Read now: the value is GTK's only during the signal.
            let items = Self.items(value)
            fire(node, actionID) { ["items": items, "location": ["x": x, "y": y]] }
            return true
        }
        gtk_widget_add_controller(ModifierBox.content(of: node.outerWidget) ?? node.outerWidget, target)
    }

    /// Fires `actionID` on the main queue's next turn, as SwiftUI's Task does; GTK is then out of
    /// the drag.
    private static func fire(_ node: RenderNode, _ actionID: String, _ context: @escaping @Sendable () -> [String: Any]) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                node.fire(actionID, context: context())
            }
        }
    }

    /// The dropped text, or the dropped files' paths (a file without a local path by its URI).
    static func items(_ value: UnsafePointer<GValue>) -> [String] {
        let type = value.pointee.g_type
        if type == g_type_from_name("gchararray") {
            return g_value_get_string(value).map { [String(cString: $0)] } ?? []
        }
        guard type == gdk_file_list_get_type(), let boxed = g_value_get_boxed(value) else { return [] }
        var items: [String] = []
        var link: UnsafeMutablePointer<GSList>? = boxed.assumingMemoryBound(to: GSList.self)
        while let current = link {
            if let file = current.pointee.data {
                let path = takeGString(g_file_get_path(OpaquePointer(file))) ?? takeGString(g_file_get_uri(OpaquePointer(file)))
                if let path {
                    items.append(path)
                }
            }
            link = current.pointee.next
        }
        return items
    }
}
