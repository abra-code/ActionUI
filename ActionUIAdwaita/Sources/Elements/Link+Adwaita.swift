// Sources/Elements/Link+Adwaita.swift
/*
 Link on GTK: a GtkLinkButton showing the title without a button's padding, so it lines up with
 the text around it, as SwiftUI's Link shows only its text. It opens the URL in the user's browser
 (GTK's own handler, through GtkUriLauncher), as SwiftUI's Link opens it with the system.

 - The URL is the url property; without one, or with one that is no URL, its box is hidden and
   takes no space or spacing, as SwiftUI shows an EmptyView (logged once). A URL without a scheme
   ("example.com") shows a link that opens nothing, as on Apple (Link.destination).
 - Its accessible name is accessibilityLabel, else the title: the labelled-by relation GTK gives a
   button to its label is reset, as on Button.
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import CAdwaita

@MainActor private var reportedMissingURL = false

extension Link: ActionUIAdwaitaRenderer {
    static func makeWidget(_ node: RenderNode) -> WidgetPointer {
        let button = gtk_link_button_new("about:blank")!
        // Just its text, as SwiftUI's Link is: no button padding or minimum size, so it lines up
        // with the text around it.
        StyleSheet.shared.apply(["padding: 0;", "min-width: 0;", "min-height: 0;"], to: button, slot: "link")
        return button
    }

    static func update(_ widget: WidgetPointer, _ node: RenderNode) {
        let props = Props(node.properties)
        let button = OpaquePointer(widget)
        if swiftString(gtk_button_get_label(typed(widget))) != props.title {
            gtk_button_set_label(typed(widget), props.title)
        }
        Button.clearLabelledBy(widget)
        // Read as Apple's URL(string:) reads it, which Linux's Foundation does not always do. A URL
        // without a scheme is shown and opens nothing, as on Apple (GTK finds no handler).
        let uri: String? = Link.destination(props.url) == .none ? nil
            : props.url.map { URL(string: $0)?.absoluteString ?? $0 }
        if let uri, swiftString(gtk_link_button_get_uri(button)) != uri {
            gtk_link_button_set_uri(button, uri)
        }
        // The box is what the parent lays out: hidden, it gets no place and no spacing (as EmptyView).
        let visible: gboolean = uri == nil ? 0 : 1
        if gtk_widget_get_visible(node.outerWidget) != visible {
            gtk_widget_set_visible(node.outerWidget, visible)
        }
        if uri == nil, !reportedMissingURL {
            reportedMissingURL = true
            ActionUIModel.shared.logger.log("Link missing valid URL, showing nothing", .warning)
        }
    }

    /// Named after its title, as SwiftUI names a link.
    static func defaultAccessibleLabel(_ node: RenderNode) -> String? {
        Props(node.properties).title
    }
}
