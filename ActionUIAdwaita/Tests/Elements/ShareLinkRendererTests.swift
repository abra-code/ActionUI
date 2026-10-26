// Tests/Elements/ShareLinkRendererTests.swift
/*
 Tests for the ShareLink renderer on GTK: a menu button with the share icon and "Share...", named
 so, whose menu offers Copy Link and Send by Email...; without a valid item its box is hidden;
 Copy Link puts the URL on the clipboard; Send by Email... drafts the subject and the message, a
 blank line and the URL; the mailto: fallback is percent-encoded with CRLF line breaks; the
 Email portal's answer: a failure shows an alert in the button's window, no portal opens the
 mailto: link, success and cancel show nothing.
*/

import XCTest
import CAdwaita
@testable import ActionUI

@MainActor
final class ShareLinkRendererTests: XCTestCase {
    private var windowUUID = ""
    private var windows: [AdwaitaWindow] = []
    private var savedComposeEmail: (@MainActor (ShareLink.EmailDraft, WidgetPointer) -> Void)?
    private var savedCopyToClipboard: (@MainActor (String, WidgetPointer) -> Void)?

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
        ActionUIRegistry.shared.loadBuiltIns()
        windowUUID = "share-link-\(name)"
        savedComposeEmail = ShareLink.composeEmail
        savedCopyToClipboard = ShareLink.copyToClipboard
    }

    override func tearDown() async throws {
        if let savedComposeEmail { ShareLink.composeEmail = savedComposeEmail }
        if let savedCopyToClipboard { ShareLink.copyToClipboard = savedCopyToClipboard }
        windows = []
        AdwaitaTestHost.drainMainLoop()
        ActionUIModel.shared.windowModels[windowUUID] = nil
        ActionUIRegistry.shared.loadBuiltIns()
    }

    private func render(_ json: String) throws -> RenderNode {
        _ = try ActionUIModel.shared.loadDescription(from: Data(json.utf8), format: "json", windowUUID: windowUUID)
        let window = AdwaitaWindow(windowModel: try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID]))
        windows.append(window)
        return try XCTUnwrap(window.root)
    }

    /// The labels of the button's menu items, in order.
    private func menuLabels(_ button: WidgetPointer) throws -> [String] {
        let model = try XCTUnwrap(gtk_menu_button_get_menu_model(OpaquePointer(button)))
        return (0..<g_menu_model_get_n_items(model)).compactMap { index in
            guard let value = g_menu_model_get_item_attribute_value(model, index, "label", nil) else { return nil }
            defer { g_variant_unref(value) }
            return swiftString(g_variant_get_string(value, nil))
        }
    }

    func testAShareButtonWithACopyAndAnEmailItem() throws {
        let node = try render(#"{"type": "ShareLink", "id": 1, "properties": {"item": "https://example.com"}}"#)
        XCTAssertEqual(swiftString(G_OBJECT_TYPE_NAME_of(node.widget)), "GtkMenuButton")
        let content = try XCTUnwrap(gtk_menu_button_get_child(OpaquePointer(node.widget)))
        XCTAssertEqual(swiftString(adw_button_content_get_label(OpaquePointer(content))), "Share\u{2026}")
        XCTAssertEqual(swiftString(adw_button_content_get_icon_name(OpaquePointer(content))), Image.iconName(.symbol("square.and.arrow.up")))
        XCTAssertEqual(try menuLabels(node.widget), ["Copy Link", "Send by Email\u{2026}"])
        XCTAssertNotEqual(gtk_test_accessible_has_property(OpaquePointer(node.widget), GTK_ACCESSIBLE_PROPERTY_LABEL), 0, "named Share...")
    }

    func testWithoutAValidItemItTakesNoPlace() throws {
        let root = try render(#"""
            {"type": "VStack", "id": 1, "children": [
              {"type": "ShareLink", "id": 2, "properties": {"subject": "Nothing"}},
              {"type": "ShareLink", "id": 3, "properties": {"item": "https://example.com"}}]}
            """#)
        XCTAssertEqual(gtk_widget_get_visible(try XCTUnwrap(root.childNodes[2]).outerWidget), 0, "no item: nothing, as SwiftUI's EmptyView")
        XCTAssertNotEqual(gtk_widget_get_visible(try XCTUnwrap(root.childNodes[3]).outerWidget), 0)
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 2, propertyName: "item", value: "https://example.com/found")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertNotEqual(gtk_widget_get_visible(try XCTUnwrap(root.childNodes[2]).outerWidget), 0, "an item set later shows it")
    }

    func testCopyLinkPutsTheURLOnTheClipboard() throws {
        // GTK's own clipboard is not used here: on Wayland it is taken only after a user's input
        // (checked with real clicks: GTK owns the clipboard and serves text/plain).
        var copied: [String] = []
        ShareLink.copyToClipboard = { text, _ in copied.append(text) }
        let node = try render(#"{"type": "ShareLink", "id": 1, "properties": {"item": "https://example.com/page?a=1", "message": "Look"}}"#)
        XCTAssertNotEqual(gtk_widget_activate_action_variant(node.widget, "share.copy", nil), 0)
        XCTAssertEqual(copied, ["https://example.com/page?a=1"], "the URL alone")
    }

    func testSendByEmailDraftsTheSubjectMessageAndURL() throws {
        var drafts: [ShareLink.EmailDraft] = []
        ShareLink.composeEmail = { draft, _ in drafts.append(draft) }
        let root = try render(#"""
            {"type": "VStack", "id": 1, "children": [
              {"type": "ShareLink", "id": 2, "properties": {"item": "https://example.com", "subject": "Check this out", "message": "Look at this link!"}},
              {"type": "ShareLink", "id": 3, "properties": {"item": "https://example.org"}}]}
            """#)
        XCTAssertNotEqual(gtk_widget_activate_action_variant(try XCTUnwrap(root.childNodes[2]).widget, "share.email", nil), 0)
        XCTAssertNotEqual(gtk_widget_activate_action_variant(try XCTUnwrap(root.childNodes[3]).widget, "share.email", nil), 0)
        XCTAssertEqual(drafts, [
            ShareLink.EmailDraft(subject: "Check this out", body: "Look at this link!\n\nhttps://example.com"),
            ShareLink.EmailDraft(subject: "", body: "https://example.org"),
        ])
    }

    func testThePortalsResponseCodesAreOutcomes() {
        XCTAssertEqual(ShareLink.emailOutcome(responseCode: 0), .opened)
        XCTAssertEqual(ShareLink.emailOutcome(responseCode: 1), .canceled)
        XCTAssertEqual(ShareLink.emailOutcome(responseCode: 2), .failed)
        XCTAssertEqual(ShareLink.emailOutcome(responseCode: 7), .failed, "any other code is a failure")
    }

    func testAPortalFailureShowsAnAlertAndNoPortalOpensMailto() throws {
        let saved = TextEditor.openURI
        defer { TextEditor.openURI = saved }
        var opened: [String] = []
        TextEditor.openURI = { uri, _ in opened.append(uri) }
        let node = try render(#"{"type": "ShareLink", "id": 1, "properties": {"item": "https://example.com"}}"#)
        let window = adw_window_new()!
        adw_window_set_content(typed(window), node.outerWidget)
        gtk_window_present(typed(window))
        defer {
            adw_window_set_content(typed(window), nil)
            gtk_window_destroy(typed(window))
        }
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { gtk_widget_get_mapped(node.widget) != 0 }))
        let draft = ShareLink.draft(item: "https://example.com", subject: "S", message: nil)

        for outcome in [ShareLink.EmailOutcome.opened, .canceled] {
            ShareLink.handle(outcome, draft, node.widget)
            AdwaitaTestHost.drainMainLoop()
            XCTAssertNil(adw_window_get_visible_dialog(typed(window)), "\(outcome): nothing shown")
        }
        XCTAssertEqual(opened, [])

        ShareLink.handle(.noPortal, draft, node.widget)
        XCTAssertEqual(opened, [ShareLink.mailtoURI(draft)], "no portal: the mailto: link")
        XCTAssertNil(adw_window_get_visible_dialog(typed(window)))

        ShareLink.handle(.failed, draft, node.widget)
        AdwaitaTestHost.drainMainLoop()
        let dialog = try XCTUnwrap(adw_window_get_visible_dialog(typed(window)), "a failure: an alert")
        XCTAssertEqual(swiftString(adw_alert_dialog_get_heading(typed(dialog))), ShareLink.emailFailureHeading)
        XCTAssertEqual(swiftString(adw_alert_dialog_get_body(typed(dialog))), ShareLink.emailFailureBody)
        adw_dialog_force_close(dialog)
    }

    func testTheMailtoFallbackIsPercentEncodedWithCRLFLineBreaks() {
        let draft = ShareLink.draft(item: "https://x.y/?a=b&c=d", subject: "Hi & bye", message: "Line one\nZ\u{00FC}rich")
        XCTAssertEqual(ShareLink.mailtoURI(draft),
                       "mailto:?subject=Hi%20%26%20bye&body=Line%20one%0D%0AZ%C3%BCrich%0D%0A%0D%0Ahttps%3A%2F%2Fx.y%2F%3Fa%3Db%26c%3Dd")
        XCTAssertEqual(ShareLink.mailtoURI(ShareLink.draft(item: "https://x.y", subject: nil, message: nil)),
                       "mailto:?body=https%3A%2F%2Fx.y", "no subject field without a subject")
    }
}
