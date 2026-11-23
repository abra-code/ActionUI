// Sources/Elements/Link+WinUI.swift
/*
 Link on WinUI: a HyperlinkButton (its text in the accent color, underlined while the pointer is over
 it) without a button's padding, so it lines up with the text around it, as SwiftUI's Link shows only
 its text. A click opens the URL with the system (the user's browser, or the app registered for its
 scheme), as SwiftUI's Link opens it.

 - The URL is the url property, read as Apple's URL(string:) reads it (Core's Link.destination): with
   none, or with text that is no URL, the Link takes no place, no spacing and no row, as SwiftUI shows
   an EmptyView (logged once), and is collapsed wherever it is (nothing drawn, no keyboard focus); a URL without a scheme ("example.com") shows a link that opens nothing,
   as on Apple.
 - A click asks the host's trust policy first (.openLink, LinkTrust), then opens the URL with the
   system: with the default policy, a link in ActionUI JSON from a server or from a file outside the
   app's resources opens only http, https and mailto addresses, as on Apple and Linux, so it cannot
   start another app's protocol, Windows' settings or a file share. A refused click is logged and
   opens nothing. What is allowed opens with the rules WinUI's own HyperlinkButton has: file: and res:
   links never, another app's scheme after Windows' warning.
 - Its text takes the font and foregroundStyle in effect (TextAppearance), as the text around it does;
   without a foregroundStyle it is the link's own accent color.
 - Accessibility tools read it as a hyperlink named after its title (its text).
*/

import CWinUI

@MainActor private var reportedMissingURL = false

/// What a Link shows, kept in its node's state.
@MainActor final class LinkState {
    var title: String?
    /// The URL a click opens (an empty string for none), nil before the first update.
    var url: String?
    /// Whether the link is collapsed (no valid URL), nil before the first update.
    var collapsed: Bool?
}

extension Link: ActionUIWinUIRenderer {
    static func makeView(_ node: RenderNode) throws(WinUIError) -> WinUIObject {
        guard let link = WinUIObject(adopting: actionUIWinUIHyperlinkCreate()) else {
            throw WinUIError.last("creating a Link")
        }
        let state = LinkState()
        node.state = state
        // The link has no NavigateUri, which would open any scheme without asking: its click opens the
        // URL once the trust policy allows it.
        WinUIEvents.connect(link, actionUIWinUIHyperlinkOnClick, "a Link's click") { [weak node, weak state] in
            guard let node, node.isAttached, let url = state?.url, !url.isEmpty else { return }
            open(url, node)
        }
        return link
    }

    static func update(_ view: WinUIObject, _ node: RenderNode) {
        guard let state = node.state as? LinkState else { return }
        node.applyTextAppearance(to: view, what: "a Link")
        let props = Props(node.properties)
        if state.title != props.title {
            if actionUIWinUIHyperlinkSetTitle(view.pointer, props.title) {
                state.title = props.title
            } else {
                ActionUIModel.shared.logger.log("Link: \(WinUIError.last("showing the title"))", .error)
            }
        }
        // Only an absolute URL opens anything; one without a scheme is shown and opens nothing.
        let destination = Link.destination(props.url)
        let url = destination == .absolute ? props.url ?? "" : ""
        state.url = url
        // No valid URL: the link collapses itself, so it shows nothing, takes no keyboard focus and is
        // not read wherever it is (a template row, a ScrollView's content), as Linux hides its widget;
        // the containers that lay out children also give it no place (takesNoPlace).
        let collapsed = destination == .none
        if state.collapsed != collapsed {
            if actionUIWinUIElementSetCollapsed(view.pointer, collapsed) {
                state.collapsed = collapsed
            } else {
                ActionUIModel.shared.logger.log("Link: \(WinUIError.last("hiding a link with no URL"))", .error)
            }
        }
        if destination == .none, !reportedMissingURL {
            reportedMissingURL = true
            ActionUIModel.shared.logger.log("Link missing valid URL, showing nothing", .warning)
        }
    }

    /// Opens `url` from the node's Link when the trust policy allows it (logged either way): the URL the
    /// policy was asked about, as Foundation writes it (LinkTrust.judgedText).
    static func open(_ url: String, _ node: RenderNode) {
        guard let judged = LinkTrust.judgedText(url, node) else { return }
        let logger = ActionUIModel.shared.logger
        logger.log("Link \(node.element.id): opening \(judged)", .debug)
        if !URLLauncher.launch(judged) {
            // Text Apple's URL(string:) takes that Windows cannot read as an absolute URL, or a file:
            // or res: link, which WinUI's rules never open.
            logger.log("Link: \(WinUIError.last("opening \(judged)")); it opens nothing", .warning)
        }
    }

    /// With no URL it takes no place, as SwiftUI shows an EmptyView.
    static func takesNoPlace(_ node: RenderNode) -> Bool {
        Link.destination(Props(node.properties).url) == .none
    }
}
