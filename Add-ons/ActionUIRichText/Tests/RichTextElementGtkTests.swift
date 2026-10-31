// Add-ons/ActionUIRichText/Tests/RichTextElementGtkTests.swift
//
// The element on Linux, in a real application window: how properties, the value and the "search" state reach
// the view and the find bar. An application runs once in a process and an add-on sees no render tree of its own,
// so this is one scripted test, whose steps run on the application's main loop, with RichTextView under a
// wrapper that keeps each node. The view's own tests live in the RichText repo.

#if os(Linux)

import XCTest
import ActionUI
import CAdwaita
import Dispatch
import FoundationEssentials
import Glibc
import RichText
@testable import ActionUIRichText

/// A loopback port that shows whether anything connected to it. Nothing answers there.
private final class ConnectionWitness {
    private let listener: Int32
    private(set) var port: UInt16 = 0

    init() {
        listener = socket(AF_INET, Int32(SOCK_STREAM.rawValue | SOCK_NONBLOCK.rawValue), 0)
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = in_addr_t(0x7F00_0001).bigEndian
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { bound in
                _ = bind(listener, bound, length)
                _ = listen(listener, 4)
                _ = getsockname(listener, bound, &length)
            }
        }
        port = UInt16(bigEndian: address.sin_port)
    }

    /// True once something has connected.
    func wasContacted() -> Bool {
        accept(listener, nil, nil) >= 0
    }

    deinit {
        close(listener)
    }
}

/// RichTextView with its nodes kept by element id.
private struct KeptRichText: ActionUIAdwaitaElement {
    static var nodes: [Int: RenderNode] = [:]

    static var valueType: Any.Type { RichTextView.valueType }
    static var initialValue: (ViewModel) -> Any? { RichTextView.initialValue }
    static var initialStates: (ViewModel) -> [String: Any] { RichTextView.initialStates }
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? { nil }
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? { nil }
    static var insertableContainers: [String: ContainerShape]? { nil }

    static func makeWidget(_ node: RenderNode) -> OpaquePointer {
        nodes[node.element.id] = node
        return RichTextView.makeWidget(node)
    }

    static func update(_ widget: OpaquePointer, _ node: RenderNode) {
        RichTextView.update(widget, node)
    }
}

@MainActor
final class RichTextElementGtkTests: XCTestCase {
    private let windowUUID = "richtext-element"
    private var stepsRun = false
    private let heldImage = ConnectionWitness()
    private let fetchedImage = ConnectionWitness()

    private var document: String { """
        {"type": "VStack", "children": [
            {"type": "TextField", "id": 1, "properties": {"title": "Search"}},
            {"type": "RichText", "id": 2, "properties": {"markdown": "One two two."}},
            {"type": "RichText", "id": 3, "properties": {
                "markdown": "Three three.", "showFindBar": true, "baseFontSize": 20,
                "syntaxHighlighting": false, "remoteImages": "misspelled"}},
            {"type": "RichText", "id": 4, "properties": {
                "markdown": "Hug.", "widthBehavior": "hug", "baseFontSize": 18.5, "remoteImages": "never"}},
            {"type": "RichText", "id": 5, "properties": {
                "markdown": "Hug.", "widthBehavior": "hug", "baseFontSize": 18.5, "showFindBar": true}},
            {"type": "RichText", "id": 6, "properties": {
                "markdown": "![held](http://127.0.0.1:\(heldImage.port)/a.png)", "remoteImages": "never"}},
            {"type": "RichText", "id": 7, "properties": {"markdown": "![fetched](http://127.0.0.1:\(fetchedImage.port)/a.png)"}}
        ]}
        """
    }

    private func state(_ id: Int) -> RichTextElementState? {
        KeptRichText.nodes[id]?.state as? RichTextElementState
    }

    private func setValue(_ id: Int, _ value: String) {
        ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: id, value: value)
    }

    private func search(_ id: Int, _ term: String) {
        ActionUIModel.shared.setElementState(windowUUID: windowUUID, viewID: id, key: "search", value: term)
    }

    func testTheElementInAWindow() throws {
        try XCTSkipUnless(gtk_init_check() != 0, "needs a display")
        // The C entry point, on the thread the application runs on: it holds on the main actor there too.
        ActionUIRichText_register()
        ActionUIRegistry.shared.register(KeptRichText.self, as: "RichText")

        // Each step runs after the updates of the one before it, on the main loop.
        let steps: [() -> Void] = [
            { [self] in checkTheFirstRender() },
            { [self] in
                setValue(2, "A new document.")
            },
            { [self] in
                XCTAssertEqual(state(2)?.markdown, "A new document.", "the runtime value wins")
                setValue(2, "")
            },
            { [self] in
                XCTAssertEqual(state(2)?.markdown, "One two two.", "an empty value falls back to the property")
                search(2, "two")
            },
            { [self] in
                XCTAssertEqual(state(2)?.find.ranges.count, 2, "the search highlights without a bar")
                XCTAssertNil(state(2)?.bar, "no bar was asked for")
                search(2, " ")
            },
            { [self] in
                XCTAssertEqual(state(2)?.find.ranges.count, 0, "a blank search clears")
                search(3, "\u{200B}")
            },
            { [self] in
                XCTAssertEqual(state(3)?.find.isPresented, false, "a zero-width space is blank too, as on Apple")
                ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 3, propertyName: "baseFontSize", value: CGFloat(21))
                search(3, "three")
            },
            { [self] in
                XCTAssertEqual(state(3)?.view.theme.baseFontSize, 21, "any number Apple's element takes")
                assertTheBarTakesRoom(state(3), true, "an open bar shows")
                XCTAssertEqual(state(3)?.find.isPresented, true, "the search presents the bar")
                XCTAssertEqual(state(3)?.find.ranges.count, 2)
                assertTheFocusIsInTheHostsField()
                // The reader closes the bar; a later states change delivers the same term.
                state(3)?.find.dismiss()
                ActionUIModel.shared.setElementState(windowUUID: windowUUID, viewID: 3, key: "other", value: "x")
            },
            { [self] in
                XCTAssertEqual(state(3)?.find.isPresented, false, "the same term does not bring the bar back")
                assertTheBarTakesRoom(state(3), false, "a closed bar takes no room")
                search(3, "")
                search(3, "three")
            },
            { [self] in
                XCTAssertEqual(state(3)?.find.isPresented, true, "clearing and setting the term opens it again")
                ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 3, propertyName: "showFindBar", value: false)
            },
            { [self] in
                assertTheBarTakesRoom(state(3), false, "turning the bar off takes it away")
                XCTAssertEqual(state(3)?.find.query, "three", "and leaves the search, as Apple's element does")
                XCTAssertEqual(state(3)?.find.ranges.count, 2, "its highlights stay")
                ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 3, propertyName: "showFindBar", value: true)
            },
            { [self] in
                assertTheBarTakesRoom(state(3), true, "turned back on, the bar is as it was")
                ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 3, propertyName: "showFindBar", value: false)
            },
            { [self] in
                search(3, "")
                search(3, "three")
            },
            { [self] in
                XCTAssertEqual(state(3)?.find.ranges.count, 2, "with the bar off a search still highlights")
                XCTAssertEqual(state(3)?.find.isPresented, false, "without bringing it back")
                setValue(3, "three, three and three.")
            },
            { [self] in
                XCTAssertEqual(state(3)?.find.ranges.count, 3, "a later update keeps the search, on the new text")
                ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 3, propertyName: "showFindBar", value: true)
            },
            { [self] in
                assertTheBarTakesRoom(state(3), false, "turned back on, the bar stays closed")
                state(3)?.find.present()
            },
            { [self] in
                assertTheBarTakesRoom(state(3), true, "Ctrl+F's call shows it again")
                assertTheFocusIsInTheBar()
                state(3)?.find.dismiss()
            },
            { [self] in
                assertTheBarTakesRoom(state(3), false, "and closing it takes it away")
                state(3)?.find.present(focus: false)
            },
            { [self] in
                assertTheBarTakesRoom(state(3), true, "it opens each time")
                XCTAssertTrue(fetchedImage.wasContacted(), "an automatic image is fetched, so the witness sees a fetch")
                XCTAssertFalse(heldImage.wasContacted(), "the policy holds from the first render")
                stepsRun = true
            },
        ]

        let app = AdwaitaApplication.shared
        app.applicationID = "com.abracode.actionui.richtext.tests"
        app.handlers.windowWillPresent = { _ in
            Self.run(steps[...]) {
                app.terminate()
            }
        }
        app.presentWindow(json: Data(document.utf8), windowUUID: windowUUID, title: nil)
        XCTAssertEqual(app.run(), 0)
        XCTAssertEqual(KeptRichText.nodes.count, 6)
        XCTAssertTrue(stepsRun, "every step ran")
    }

    private static func run(_ steps: ArraySlice<() -> Void>, then finish: @escaping @MainActor () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(150)) {
            MainActor.assumeIsolated {
                guard let step = steps.first else {
                    finish()
                    return
                }
                step()
                run(steps.dropFirst(), then: finish)
            }
        }
    }

    private func checkTheFirstRender() {
        guard let plain = state(2), let styled = state(3), let hugging = state(4), let huggingBar = state(5) else {
            XCTFail("the elements were not made")
            return
        }
        XCTAssertEqual(plain.markdown, "One two two.")
        XCTAssertEqual(plain.view.theme, .default, "no property keeps the package's theme")
        XCTAssertEqual(plain.view.remoteImages, .automatic)
        XCTAssertEqual(styled.view.theme.baseFontSize, 20)
        XCTAssertEqual(hugging.view.theme.baseFontSize, 18.5)
        XCTAssertEqual(styled.view.theme.syntaxHighlighting, false)
        XCTAssertEqual(styled.view.remoteImages, .onClick, "a misspelled policy fails closed")
        XCTAssertEqual(hugging.view.remoteImages, .never)
        XCTAssertNotNil(styled.bar)

        let fills = UnsafeMutablePointer<GtkWidget>(plain.view.widget)
        let hugs = UnsafeMutablePointer<GtkWidget>(hugging.view.widget)
        XCTAssertEqual(gtk_widget_get_hexpand(fills), 1, "fill takes the width it is offered")
        XCTAssertEqual(gtk_widget_get_hexpand(hugs), 0, "hug does not")
        XCTAssertLessThan(gtk_widget_get_width(hugs), gtk_widget_get_width(fills) / 2, "hug is as wide as its text")
        XCTAssertGreaterThan(gtk_widget_get_height(fills), 10, "a line of text has its height")
        XCTAssertEqual(gtk_widget_has_css_class(fills, "actionui-richtext"), 1, "the window's background shows through")
        // Closed, the bar leaves the element as it would be without one.
        XCTAssertEqual(gtk_widget_get_width(UnsafeMutablePointer<GtkWidget>(huggingBar.view.widget)), gtk_widget_get_width(hugs),
                       "a closed bar does not widen a hug")
        assertTheBarTakesRoom(styled, false, "a closed bar takes no room")
    }

    private func assertTheBarTakesRoom(_ element: RichTextElementState?, _ open: Bool, _ message: String,
                                       file: StaticString = #filePath, line: UInt = #line) {
        guard let element, let bar = element.bar else {
            XCTFail("no bar", file: file, line: line)
            return
        }
        let widget = UnsafeMutablePointer<GtkWidget>(bar.widget)
        XCTAssertEqual(gtk_widget_get_visible(widget) != 0, open, message, file: file, line: line)
        if open {
            XCTAssertGreaterThan(gtk_widget_get_height(widget), 0, message, file: file, line: line)
        }
        var minimum: Int32 = 0
        gtk_widget_measure(UnsafeMutableRawPointer(element.column).assumingMemoryBound(to: GtkWidget.self),
                           GTK_ORIENTATION_HORIZONTAL, -1, &minimum, nil, nil, nil)
        XCTAssertEqual(minimum > 0, open, message, file: file, line: line)
    }

    // Ctrl+F's way: the reader goes on to type the term.
    private func assertTheFocusIsInTheBar() {
        guard let element = state(3), let bar = element.bar,
              let root = gtk_widget_get_root(UnsafeMutablePointer<GtkWidget>(element.view.widget)),
              let focus = gtk_root_get_focus(root) else {
            XCTFail("no focus")
            return
        }
        XCTAssertEqual(gtk_widget_is_ancestor(focus, UnsafeMutablePointer<GtkWidget>(bar.widget)), 1)
    }

    // The term came from the host's field: presenting the bar must leave the keyboard there.
    private func assertTheFocusIsInTheHostsField() {
        guard let element = state(3), let bar = element.bar,
              let root = gtk_widget_get_root(UnsafeMutablePointer<GtkWidget>(element.view.widget)) else {
            XCTFail("no window")
            return
        }
        let focus = gtk_root_get_focus(root)
        XCTAssertTrue(focus == nil || gtk_widget_is_ancestor(focus, UnsafeMutablePointer<GtkWidget>(bar.widget)) == 0,
                      "the bar did not take the focus")
    }
}

#endif
