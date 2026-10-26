// Sources/Elements/ShareLink+Adwaita.swift
/*
 ShareLink on GTK: a button with the share icon and "Share...", as SwiftUI's ShareLink shows on
 macOS (measured on macOS 27: a bordered button like a Button's, the square.and.arrow.up symbol and
 "Share" with an ellipsis), which opens a menu of the ways a GNOME desktop shares a link, as macOS
 opens its sharing services. Linux has no share sheet (no desktop portal for it), so the menu is:
 - Copy Link: the item's URL on the clipboard.
 - Send by Email...: the user's mail program with a new message, through the desktop's Email portal
   (org.freedesktop.portal.Email), else a mailto: link opened by GTK: the subject property as its
   subject, and the message property, a blank line and the URL as its body (the URL alone without
   a message), as Mail shares a link on macOS. When the portal answers that it could open no mail
   program (none installed, measured in the box: response 2 with no reason given), an alert says
   so; a canceled request shows nothing.

 - The item is a URL string (ShareLink.Props); without one its box is hidden and takes no space or
   spacing, as SwiftUI shows an EmptyView (logged once).
 - Its accessible name is accessibilityLabel, else "Share...".
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import CAdwaita
import Dispatch

@MainActor private var reportedMissingItem = false
private let shareLinkStateKey = AttachKey<ShareLinkState>("actionui-share-link")

/// What a ShareLink's menu items share, kept on its button.
@MainActor private final class ShareLinkState {
    var item: String?
    var subject: String?
    var message: String?
    private var ownedActions: OwnedObject?
    var actions: OpaquePointer { (ownedActions?.opaquePointer)! }

    init() {
        ownedActions = OwnedObject(adopting: OpaquePointer(g_simple_action_group_new()!))
    }

    isolated deinit {
        // Released here, on the main actor (GTK's thread).
        ownedActions = nil
    }
}

extension ShareLink: ActionUIAdwaitaRenderer {
    /// The button's text, as SwiftUI's ShareLink shows it.
    static let title = "Share\u{2026}"
    /// The prefix of the menu items' actions (the button's action group).
    static let actionPrefix = "share"

    /// A new message for the user's mail program.
    struct EmailDraft: Equatable {
        var subject: String
        var body: String
    }

    /// Puts text on the clipboard; replaced in tests (on Wayland GTK takes the clipboard only
    /// after a user's input, which a test has none of).
    static var copyToClipboard: @MainActor (String, WidgetPointer) -> Void = { text, widget in
        gdk_clipboard_set_text(gtk_widget_get_clipboard(widget), text)
    }

    /// Sends a draft to the user's mail program; replaced in tests.
    static var composeEmail: @MainActor (EmailDraft, WidgetPointer) -> Void = { draft, widget in
        // Held until the portal answered (it may wait for the user): the node can drop the
        // button before then (a window closed), and a freed address must not be read.
        g_object_ref(UnsafeMutableRawPointer(widget))
        PortalEmailRequest.send(draft) { outcome in
            defer { g_object_unref(UnsafeMutableRawPointer(widget)) }
            handle(outcome, draft, widget)
        }
    }

    /// How the Email portal answered a request.
    enum EmailOutcome: Equatable {
        /// The mail program opened (the portal's response 0).
        case opened
        /// The user canceled (response 1).
        case canceled
        /// The portal could not open a mail program (response 2; it gives no reason).
        case failed
        /// No portal answered the call (no session bus, or no Email portal).
        case noPortal
    }

    /// The portal's response code as an outcome (org.freedesktop.portal.Request.Response).
    static func emailOutcome(responseCode: UInt32) -> EmailOutcome {
        switch responseCode {
        case 0: return .opened
        case 1: return .canceled
        default: return .failed
        }
    }

    /// What follows a request: without a portal, a mailto: link; when the portal could open no mail
    /// program, an alert saying so (the portal gives no reason to show).
    static func handle(_ outcome: EmailOutcome, _ draft: EmailDraft, _ widget: WidgetPointer) {
        switch outcome {
        case .opened, .canceled:
            break
        case .noPortal:
            TextEditor.openURI(mailtoURI(draft), widget)
        case .failed:
            ActionUIModel.shared.logger.log("ShareLink: the Email portal could not open an email app", .warning)
            showEmailFailure(widget)
        }
    }

    static let emailFailureHeading = "Could Not Send by Email"
    static let emailFailureBody = "No email app could be opened. Install or set up an email app, or copy the link instead."

    /// An alert on the button's window saying no email app could be opened.
    static func showEmailFailure(_ widget: WidgetPointer) {
        // A button no longer in a window (it closed while the portal worked) has nowhere to show it.
        guard gtk_widget_get_root(widget) != nil else { return }
        let alert: UnsafeMutablePointer<AdwAlertDialog> = typed(adw_alert_dialog_new(emailFailureHeading, emailFailureBody)!)
        adw_alert_dialog_add_response(alert, "ok", "OK")
        adw_alert_dialog_set_default_response(alert, "ok")
        adw_alert_dialog_set_close_response(alert, "ok")
        adw_dialog_present(typed(alert), widget)
    }

    static func makeWidget(_ node: RenderNode) -> WidgetPointer {
        let button = gtk_menu_button_new()!
        let content = adw_button_content_new()!
        adw_button_content_set_icon_name(opaque(content), Image.iconName(.symbol("square.and.arrow.up")))
        adw_button_content_set_label(opaque(content), title)
        gtk_menu_button_set_child(OpaquePointer(button), content)

        let state = ShareLinkState()
        attach(state, to: button, key: shareLinkStateKey)
        addAction("copy", to: state) { [weak state] in
            guard let item = state?.item else { return }
            copyToClipboard(item, button)
        }
        addAction("email", to: state) { [weak state] in
            guard let state, let item = state.item else { return }
            composeEmail(draft(item: item, subject: state.subject, message: state.message), button)
        }
        gtk_widget_insert_action_group(button, actionPrefix, state.actions)

        let menu = OwnedObject(adopting: g_menu_new()!)
        g_menu_append(menu.opaquePointer, "Copy Link", "\(actionPrefix).copy")
        g_menu_append(menu.opaquePointer, "Send by Email\u{2026}", "\(actionPrefix).email")
        gtk_menu_button_set_menu_model(OpaquePointer(button), typed(menu.opaquePointer))
        return button
    }

    static func update(_ widget: WidgetPointer, _ node: RenderNode) {
        guard let state = attached(on: widget, key: shareLinkStateKey) else { return }
        let props = Props(node.properties)
        state.item = props.item.map { URL(string: $0)?.absoluteString ?? $0 }
        state.subject = props.subject
        state.message = props.message
        // The box is what the parent lays out: hidden, it gets no place and no spacing (as EmptyView).
        Gtk.Widget(node.outerWidget).isVisible = state.item != nil
        if state.item == nil, !reportedMissingItem {
            reportedMissingItem = true
            ActionUIModel.shared.logger.log("ShareLink missing valid URL, showing nothing", .warning)
        }
    }

    /// Named after its text, as SwiftUI names the share button.
    static func defaultAccessibleLabel(_ node: RenderNode) -> String? {
        title
    }

    private static func addAction(_ name: String, to state: ShareLinkState, _ run: @escaping @MainActor () -> Void) {
        let action = OwnedObject(adopting: g_simple_action_new(name, nil)!)
        connectSignal(action.pointer, "activate", .instanceAndArgument, run)
        g_action_map_add_action(state.actions, action.opaquePointer)
    }

    // MARK: Email

    /// The message for `item`: the subject (empty when none), and the message, a blank line and
    /// the URL as the body, or the URL alone.
    static func draft(item: String, subject: String?, message: String?) -> EmailDraft {
        let body = (message ?? "").isEmpty ? item : message! + "\n\n" + item
        return EmailDraft(subject: subject ?? "", body: body)
    }

    /// The draft as a mailto: URI (RFC 6068): no address, the subject and body percent-encoded,
    /// line breaks as CRLF.
    static func mailtoURI(_ draft: EmailDraft) -> String {
        var fields: [String] = []
        if !draft.subject.isEmpty {
            fields.append("subject=" + percentEncoded(draft.subject))
        }
        let body = draft.body.replacing("\r\n", with: "\n").replacing("\n", with: "\r\n")
        fields.append("body=" + percentEncoded(body))
        return "mailto:?" + fields.joined(separator: "&")
    }

    /// Every byte but RFC 3986's unreserved characters as %XX.
    private static func percentEncoded(_ text: String) -> String {
        let hex = Array("0123456789ABCDEF")
        var encoded = ""
        for byte in text.utf8 {
            switch byte {
            case UInt8(ascii: "A")...UInt8(ascii: "Z"), UInt8(ascii: "a")...UInt8(ascii: "z"),
                 UInt8(ascii: "0")...UInt8(ascii: "9"), UInt8(ascii: "-"), UInt8(ascii: "."),
                 UInt8(ascii: "_"), UInt8(ascii: "~"):
                encoded.append(Character(Unicode.Scalar(byte)))
            default:
                encoded.append("%")
                encoded.append(hex[Int(byte >> 4)])
                encoded.append(hex[Int(byte & 0x0F)])
            }
        }
        return encoded
    }
}

/// One ComposeEmail request to the desktop's Email portal and its answer: the portal returns a
/// request handle at once and answers with org.freedesktop.portal.Request.Response on it later
/// (after the mail program opened, or failed to). The handle's path is made known before the call
/// with a handle_token, as the portal's documentation asks, so the answer cannot be missed.
@MainActor private final class PortalEmailRequest {
    private let bus: OpaquePointer
    private let completion: @MainActor (ShareLink.EmailOutcome) -> Void
    private var subscription: guint = 0
    private var finished = false

    private init(bus: OpaquePointer, completion: @escaping @MainActor (ShareLink.EmailOutcome) -> Void) {
        self.bus = bus
        self.completion = completion
    }

    static func send(_ draft: ShareLink.EmailDraft, _ completion: @escaping @MainActor (ShareLink.EmailOutcome) -> Void) {
        guard let bus = g_bus_get_sync(G_BUS_TYPE_SESSION, nil, nil) else {
            completion(.noPortal)
            return
        }
        let request = PortalEmailRequest(bus: bus, completion: completion)
        // Kept alive by its own reference until it finished; GDBus calls back on this main context.
        let data = Unmanaged.passRetained(request).toOpaque()
        let token = "actionui\(UInt32.random(in: 0...UInt32.max))"
        let sender = (swiftString(g_dbus_connection_get_unique_name(bus)) ?? "").dropFirst().replacing(".", with: "_")
        let path = "/org/freedesktop/portal/desktop/request/\(sender)/\(token)"
        request.subscription = g_dbus_connection_signal_subscribe(bus, "org.freedesktop.portal.Desktop", "org.freedesktop.portal.Request",
                                                                  "Response", path, nil, G_DBUS_SIGNAL_FLAGS_NONE,
                                                                  portalResponseTrampoline, data, nil)

        let entryType = g_variant_type_new("{sv}")!
        var entries: [OpaquePointer?] = [
            g_variant_new_dict_entry(g_variant_new_string("handle_token"), g_variant_new_variant(g_variant_new_string(token))),
            g_variant_new_dict_entry(g_variant_new_string("subject"), g_variant_new_variant(g_variant_new_string(draft.subject))),
            g_variant_new_dict_entry(g_variant_new_string("body"), g_variant_new_variant(g_variant_new_string(draft.body))),
        ]
        let options = g_variant_new_array(entryType, &entries, gsize(entries.count))
        g_variant_type_free(entryType)
        // The parent window identifier is empty: the portal places its dialog on its own.
        var arguments: [OpaquePointer?] = [g_variant_new_string(""), options]
        let parameters = g_variant_new_tuple(&arguments, gsize(arguments.count))
        let run: ReadyRun = { result in
            var error: UnsafeMutablePointer<GError>?
            let reply = g_dbus_connection_call_finish(bus, result, &error)
            if let reply { g_variant_unref(reply) }
            if let error {
                ActionUIModel.shared.logger.log("ShareLink: the Email portal did not answer (\(swiftString(error.pointee.message) ?? "")); opening a mailto: link", .info)
                g_error_free(error)
                request.finish(.noPortal)
            }
        }
        g_dbus_connection_call(bus, "org.freedesktop.portal.Desktop", "/org/freedesktop/portal/desktop",
                               "org.freedesktop.portal.Email", "ComposeEmail", parameters, nil,
                               G_DBUS_CALL_FLAGS_NONE, -1, nil, readyTrampoline, Unmanaged.passRetained(CallbackBox(run)).toOpaque())
    }

    /// The portal's Response: its code is the first value of (ua{sv}).
    fileprivate func received(_ parameters: OpaquePointer?) {
        guard let parameters, let code = g_variant_get_child_value(parameters, 0) else { return }
        defer { g_variant_unref(code) }
        // Anything but a uint32 there is no answer the portal documents: a failure, not code 0.
        guard g_variant_classify(code) == G_VARIANT_CLASS_UINT32 else { return finish(.failed) }
        finish(ShareLink.emailOutcome(responseCode: g_variant_get_uint32(code)))
    }

    /// Answers once, then stops listening and lets go of the request, after this callback.
    private func finish(_ outcome: ShareLink.EmailOutcome) {
        guard !finished else { return }
        finished = true
        g_dbus_connection_signal_unsubscribe(bus, subscription)
        completion(outcome)
        DispatchQueue.main.async { [self] in
            g_object_unref(UnsafeMutableRawPointer(bus))
            // The reference send took for GDBus's callback.
            Unmanaged.passUnretained(self).release()
        }
    }
}

/// GDBus's signal callback for a request's Response; its user data is the PortalEmailRequest.
private let portalResponseTrampoline: @convention(c) (OpaquePointer?, UnsafePointer<CChar>?, UnsafePointer<CChar>?, UnsafePointer<CChar>?,
                                                      UnsafePointer<CChar>?, OpaquePointer?, gpointer?) -> Void = { _, _, _, _, _, parameters, data in
    guard let data else { return }
    // Pointers are not Sendable; their addresses are. GDBus calls back on the main thread.
    let requestAddress = Int(bitPattern: data)
    let address = parameters.map { Int(bitPattern: UnsafeRawPointer($0)) }
    MainActor.assumeIsolated {
        guard let pointer = UnsafeRawPointer(bitPattern: requestAddress) else { return }
        let request = Unmanaged<PortalEmailRequest>.fromOpaque(pointer).takeUnretainedValue()
        request.received(address.flatMap { OpaquePointer(bitPattern: $0) })
    }
}
