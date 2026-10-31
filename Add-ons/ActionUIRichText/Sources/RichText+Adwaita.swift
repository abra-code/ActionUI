// Add-ons/ActionUIRichText/Sources/RichText+Adwaita.swift
/*
 The RichText element on Linux, the counterpart of RichText.swift and RichTextElementView.swift: the same
 JSON (the sample and the properties are in RichText.swift) over the RichText package's GTK view.

 The element's widget is a column: the find bar, while it is open, above the text view. The text view keeps
 its own scrolling off: ActionUI's stacks and ScrollView place it like any other view, and GtkTextView lays its
 text out for the width it is given.

 Differences from Apple, by what GTK offers:
 - Ctrl+F, Ctrl+G and Shift+Ctrl+G work while the focus is inside the element, not in the whole window.
 - A document in a ScrollView has its height one layout after a new width, as GtkTextView has no height for
   a width it is only measured for.
*/

#if os(Linux)

import ActionUI
import CAdwaita
import FoundationEssentials
import RichText

/// What an element instance keeps (RenderNode.state): the view, its find layers, and what it last applied.
@MainActor
final class RichTextElementState {
    let view: RichTextGtkView
    let find = RichTextGtkFindController()
    /// The column holding the view, and the bar above it once "showFindBar" has been on.
    let column: UnsafeMutablePointer<GtkBox>
    private(set) var bar: RichTextGtkFindBar?
    /// The GBinding that shows the bar while it is open; nil while "showFindBar" is off.
    private var barVisibility: OpaquePointer?
    /// The Markdown the view shows.
    var markdown = ""
    /// Whether "showFindBar" is on, as the last update found it.
    var showsBar = false
    /// Delivers each change of the states, so "" and then a term in one go still count as two.
    var statesObservation: ActionUIObservation?
    /// The last states["search"] applied, so a states change that re-delivers it does not re-open a bar the
    /// reader closed; and the last value refused, so a host's mistake is said once.
    private var lastAppliedSearch: String?
    private var lastRejectedSearch: String?

    init(view: RichTextGtkView, column: UnsafeMutablePointer<GtkBox>) {
        self.view = view
        self.column = column
        find.bind(view: view)
    }

    /// The bar above the view, made the first time it is asked for. Closed, a GtkSearchBar is still as wide as what
    /// it holds, and expands: it would widen a "hug" element and floor every other one, so it hides while closed.
    func showBar() {
        guard barVisibility == nil else { return }
        let bar = self.bar ?? makeBar()
        barVisibility = g_object_bind_property(UnsafeMutableRawPointer(bar.widget), "search-mode-enabled",
                                               UnsafeMutableRawPointer(bar.widget), "visible", G_BINDING_SYNC_CREATE)
    }

    private func makeBar() -> RichTextGtkFindBar {
        let bar = RichTextGtkFindBar(find)
        gtk_box_prepend(column, UnsafeMutablePointer<GtkWidget>(bar.widget))
        bar.installShortcuts(on: OpaquePointer(column))
        self.bar = bar
        return bar
    }

    /// Takes the bar away and leaves the search, as Apple's element does: its highlights stay, and turning
    /// "showFindBar" on again shows the bar as it was.
    func hideBar() {
        guard let barVisibility, let bar else { return }
        g_binding_unbind(barVisibility)
        self.barVisibility = nil
        gtk_widget_set_visible(UnsafeMutablePointer<GtkWidget>(bar.widget), 0)
    }

    /// Applies a value of states["search"].
    func applySearch(_ value: Any?) {
        // nil: the key was never set - no opinion.
        guard let value else { return }
        guard let query = value as? String else {
            let description = String(describing: value)
            if description != lastRejectedSearch {
                lastRejectedSearch = description
                ActionUIModel.shared.logger.log("RichText search state must be a String; ignoring", .warning)
            }
            return
        }
        guard query != lastAppliedSearch else { return }
        lastAppliedSearch = query
        // What Apple's element trims, whitespacesAndNewlines: U+200B counts, and a space with a mark on it does not.
        if query.unicodeScalars.allSatisfy({ $0.properties.isWhitespace || $0 == "\u{200B}" }) {
            if find.isPresented || !find.query.isEmpty {
                find.dismiss()
            }
            return
        }
        find.query = query
        if showsBar {
            // Without the focus: the reader is typing in the host's field, which is what sent this.
            find.present(focus: false)
        }
    }
}

/// The class that lets the window's background show through, as the Apple view does; once per process.
@MainActor private let transparentClass: String = {
    let name = "actionui-richtext"
    if let display = gdk_display_get_default(), let provider = gtk_css_provider_new() {
        gtk_css_provider_load_from_string(provider, ".\(name), .\(name) > text { background: none; }")
        gtk_style_context_add_provider_for_display(display, OpaquePointer(provider),
                                                   guint(GTK_STYLE_PROVIDER_PRIORITY_APPLICATION))
        g_object_unref(UnsafeMutableRawPointer(provider))
    }
    return name
}()

struct RichTextView: ActionUIAdwaitaElement {
    // The element's runtime value is the Markdown source string.
    static var valueType: Any.Type { String.self }

    // "" (not nil) when no value is set yet, so the String valueType has an initial value; an empty string
    // means "no runtime source", and update then falls back to the "markdown" property.
    static var initialValue: (ViewModel) -> Any? { { model in (model.value as? String) ?? "" } }

    // Seeded as an empty String: a state key's first write fixes its type, and these terms are typed by people.
    static var initialStates: (ViewModel) -> [String: Any] {
        { model in
            var states = model.states
            if states["search"] == nil {
                states["search"] = ""
            }
            return states
        }
    }

    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? { nil }
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? { nil }
    static var insertableContainers: [String: ContainerShape]? { nil }

    static func makeWidget(_ node: RenderNode) -> OpaquePointer {
        let widget = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
        let column = UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GtkBox.self)
        let view = RichTextGtkView(markdown: "")
        let text = UnsafeMutablePointer<GtkWidget>(view.widget)
        gtk_widget_add_css_class(text, transparentClass)
        gtk_box_append(column, text)
        node.state = RichTextElementState(view: view, column: column)
        return OpaquePointer(widget)
    }

    static func update(_ widget: OpaquePointer, _ node: RenderNode) {
        guard let state = node.state as? RichTextElementState else { return }
        let properties = node.properties

        // Before the document, so its images load (or wait) as asked.
        let remoteImages = effectiveRemoteImagesPolicy(properties["remoteImages"])
        if state.view.remoteImages != remoteImages {
            state.view.remoteImages = remoteImages
        }
        let theme = theme(properties)
        if state.view.theme != theme {
            state.view.theme = theme
        }
        // The runtime value wins, else the "markdown" property.
        let runtime = (node.model.value as? String).flatMap { $0.isEmpty ? nil : $0 }
        let markdown = runtime ?? (properties["markdown"] as? String) ?? ""
        if markdown != state.markdown {
            state.markdown = markdown
            state.view.setMarkdown(markdown)
        }

        // "fill" (default) takes the width it is offered, at the left; "hug" takes its content's, wrapping only
        // at what it is offered.
        let hugs = properties["widthBehavior"] as? String == "hug"
        let text = UnsafeMutablePointer<GtkWidget>(state.view.widget)
        gtk_widget_set_hexpand(text, hugs ? 0 : 1)
        gtk_widget_set_halign(UnsafeMutablePointer<GtkWidget>(widget), hugs ? GTK_ALIGN_START : GTK_ALIGN_FILL)

        state.showsBar = properties["showFindBar"] as? Bool ?? false
        if state.showsBar {
            state.showBar()
        } else {
            state.hideBar()
        }
        // In the first update, not makeWidget: it delivers the current states at once. Not by reading the states
        // here: updates coalesce, and a host's "" and then the same term must reach the element as two changes.
        if state.statesObservation == nil {
            state.statesObservation = node.model.observeStates { [weak state] states in
                state?.applySearch(states["search"])
            }
        }
    }

    // Starts from the package's default theme, overriding what the document gives.
    private static func theme(_ properties: [String: Any]) -> RichTextTheme {
        var theme = RichTextTheme.default
        switch properties["baseFontSize"] {
        // Double, Float and a host's CGFloat, a type only full Foundation has here.
        case let size as any BinaryFloatingPoint: theme.baseFontSize = Double(size)
        case let size as Int: theme.baseFontSize = Double(size)
        default: break
        }
        if let highlighting = properties["syntaxHighlighting"] as? Bool {
            theme.syntaxHighlighting = highlighting
        }
        return theme
    }
}

#endif
