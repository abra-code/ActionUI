// Add-ons/ActionUIDiff/Sources/ActionUIDiff/Diff+Adwaita.swift
/*
 The Diff element on Linux, the counterpart of Diff.swift: the same JSON (the sample and the properties are in
 Diff.swift) over the DiffView package's GTK view, DiffGtkView, which draws what the SwiftUI DiffView draws.

 As on Apple: display-only (no value), every property live, text winning over file per side (DiffInput.swift), and
 a file that cannot be read shown as a "Cannot read <path>" note instead of a diff. The element takes the width it
 is offered, as the SwiftUI view does, and is as tall as its rows; a long diff goes in a ScrollView.

 The element's widget is a box holding the diff view, or the note in its place.
*/

#if os(Linux)

import ActionUI
import CAdwaita
import DiffView
import FoundationEssentials

/// What an element instance keeps (RenderNode.state): the box, and the diff view or the note in it.
@MainActor
final class DiffElementState {
    let box: UnsafeMutablePointer<GtkBox>
    /// The diff, once a diff has been shown; kept while a note shows, for when the files can be read again.
    private(set) var view: DiffGtkView?
    /// The note for files that cannot be read, once one has been shown.
    private(set) var note: UnsafeMutablePointer<GtkWidget>?

    init(box: UnsafeMutablePointer<GtkBox>) {
        self.box = box
    }

    /// Shows the diff of the two texts.
    func showDiff(oldText: String, newText: String, contextLines: Int, maxRenderedLines: Int) {
        if let view {
            view.show(oldText: oldText, newText: newText, contextLines: contextLines, maxRenderedLines: maxRenderedLines)
        } else {
            let made = DiffGtkView(oldText: oldText, newText: newText, contextLines: contextLines, maxRenderedLines: maxRenderedLines)
            gtk_box_append(box, UnsafeMutablePointer<GtkWidget>(made.widget))
            view = made
        }
        show(diff: true)
    }

    /// Shows the note naming the paths that cannot be read, one to a line.
    func showUnreadable(_ paths: [String]) {
        let note = self.note ?? makeNote()
        let text = paths.map { "Cannot read \($0)" }.joined(separator: "\n")
        let label = OpaquePointer(gtk_widget_get_first_child(note))
        if String(cString: gtk_label_get_text(label)) != text {
            gtk_label_set_text(label, text)
        }
        show(diff: false)
    }

    private func show(diff: Bool) {
        if let view {
            gtk_widget_set_visible(UnsafeMutablePointer<GtkWidget>(view.widget), diff ? 1 : 0)
        }
        if let note {
            gtk_widget_set_visible(note, diff ? 0 : 1)
        }
    }

    /// The note as the SwiftUI element draws it: small secondary monospaced text with 6 points around it, on the
    /// diff's faint rounded background, as wide as it is offered, not selectable (Apple's note has no textSelection).
    /// The background is on a box of its own, so the label's secondary color does not dim it.
    private func makeNote() -> UnsafeMutablePointer<GtkWidget> {
        installNoteStyle()
        let note = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
        gtk_widget_add_css_class(note, noteClass)
        let label = gtk_label_new(nil)!
        gtk_widget_add_css_class(label, noteTextClass)
        gtk_widget_add_css_class(label, "monospace")
        gtk_label_set_xalign(OpaquePointer(label), 0)
        gtk_label_set_wrap(OpaquePointer(label), 1)
        gtk_label_set_wrap_mode(OpaquePointer(label), PANGO_WRAP_WORD_CHAR)
        gtk_widget_set_hexpand(label, 1)
        gtk_box_append(UnsafeMutableRawPointer(note).assumingMemoryBound(to: GtkBox.self), label)
        gtk_box_append(box, note)
        self.note = note
        return note
    }
}

private let noteClass = "actionui-diff-note"
private let noteTextClass = "actionui-diff-note-text"

/// The note's style, as DiffView's GTK view draws its own notes and background; once per process.
@MainActor private var noteStyleInstalled = false

@MainActor private func installNoteStyle() {
    guard !noteStyleInstalled, let display = gdk_display_get_default(), let provider = gtk_css_provider_new() else {
        return
    }
    noteStyleInstalled = true
    gtk_css_provider_load_from_string(provider, """
        .\(noteClass) { background-color: alpha(alpha(currentColor, 0.55), 0.05); border-radius: 6px; }
        .\(noteTextClass) { font-family: monospace; font-size: 82%; color: alpha(currentColor, 0.55); padding: 6px; }
        """)
    gtk_style_context_add_provider_for_display(display, OpaquePointer(provider),
                                               guint(GTK_STYLE_PROVIDER_PRIORITY_APPLICATION))
    g_object_unref(UnsafeMutableRawPointer(provider))
}

struct Diff: ActionUIAdwaitaElement {
    // Display-only element: no observable runtime value.
    static var valueType: Any.Type { Void.self }
    static var initialValue: (ViewModel) -> Any? { { model in model.value } }
    static var initialStates: (ViewModel) -> [String: Any] { { model in model.states } }
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? { nil }
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? { nil }
    static var insertableContainers: [String: ContainerShape]? { nil }

    static func makeWidget(_ node: RenderNode) -> OpaquePointer {
        let widget = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
        node.state = DiffElementState(box: UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GtkBox.self))
        return OpaquePointer(widget)
    }

    static func update(_ widget: OpaquePointer, _ node: RenderNode) {
        guard let state = node.state as? DiffElementState else { return }
        let properties = node.properties
        let logger = ActionUIModel.shared.logger
        let oldInput = resolveInput(text: properties["oldText"], file: properties["oldFile"], side: "old", logger: logger)
        let newInput = resolveInput(text: properties["newText"], file: properties["newFile"], side: "new", logger: logger)

        // A file that could not be read is a note listing the path(s), not a diff against an empty side, which
        // would look like a whole file removed or added.
        var unreadablePaths: [String] = []
        if case .unreadable(let path) = oldInput {
            unreadablePaths.append(path)
        }
        if case .unreadable(let path) = newInput {
            unreadablePaths.append(path)
        }
        guard unreadablePaths.isEmpty, case .text(let oldText) = oldInput, case .text(let newText) = newInput else {
            state.showUnreadable(unreadablePaths)
            return
        }

        let contextLines = intProperty(properties, key: "contextLines", default: 3, minimum: 0, logger: logger)
        let maxRenderedLines = intProperty(properties, key: "maxRenderedLines", default: 300, minimum: 1, logger: logger)
        state.showDiff(oldText: oldText, newText: newText, contextLines: contextLines, maxRenderedLines: maxRenderedLines)
    }
}

#endif
