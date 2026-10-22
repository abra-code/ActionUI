// Tests/Runtime/RenderTreeTests.swift
/*
 Tests for the render tree (RenderNode, SyncScheduler, AdwaitaWindow, the renderer table), with
 test renderers for Text and VStack so they hold no rendering details: a document builds one node
 and widget per element; a model change re-syncs the node that read it, once per flush, and not
 its parent; inserted and removed children are reconciled by id; an element type without a
 renderer shows the placeholder; actions fire only outside renderer updates.
*/

import XCTest
import CAdwaita
@testable import ActionUI

/// How many times each test renderer's update ran, by element id.
@MainActor
enum TestUpdates {
    static var counts: [Int: Int] = [:]
}

/// Text as a label showing the model's value.
@MainActor
enum TestTextRenderer: ActionUIAdwaitaRenderer {
    static func makeWidget(_ node: RenderNode) -> WidgetPointer {
        gtk_label_new(nil)!
    }

    static func update(_ widget: WidgetPointer, _ node: RenderNode) {
        TestUpdates.counts[node.element.id, default: 0] += 1
        let text = node.model.value as? String ?? ""
        if swiftString(gtk_label_get_text(opaque(widget))) != text {
            gtk_label_set_text(opaque(widget), text)
        }
    }
}

/// VStack as a vertical GtkBox of its children.
@MainActor
enum TestStackRenderer: ActionUIAdwaitaRenderer {
    static func makeWidget(_ node: RenderNode) -> WidgetPointer {
        gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
    }

    static func update(_ widget: WidgetPointer, _ node: RenderNode) {
        TestUpdates.counts[node.element.id, default: 0] += 1
        let box: UnsafeMutablePointer<GtkBox> = typed(widget)
        let children = node.effectiveElement.subviews?["children"] as? [any ActionUIElementBase] ?? []
        var previous: WidgetPointer?
        node.syncChildren(children, insert: { child, _ in
            if gtk_widget_get_parent(child.outerWidget) == nil {
                gtk_box_append(box, child.outerWidget)
            }
            gtk_box_reorder_child_after(box, child.outerWidget, previous)
            previous = child.outerWidget
        }, remove: { child in
            gtk_box_remove(box, child.outerWidget)
        })
    }
}

@MainActor
final class RenderTreeTests: XCTestCase {
    private var windowUUID = ""

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
        ActionUIRegistry.shared.loadBuiltIns()
        ActionUIRegistry.shared.renderers["Text"] = TestTextRenderer.self
        ActionUIRegistry.shared.renderers["VStack"] = TestStackRenderer.self
        TestUpdates.counts = [:]
        windowUUID = "render-tree-\(name)"
    }

    override func tearDown() async throws {
        AdwaitaTestHost.drainMainLoop()
        ActionUIModel.shared.windowModels[windowUUID] = nil
        ActionUIRegistry.shared.loadBuiltIns()
    }

    private let document = """
        {"type": "VStack", "id": 1, "children": [
            {"type": "Text", "id": 2, "properties": {"text": "one"}},
            {"type": "Text", "id": 3, "properties": {"text": "two"}}
        ]}
        """

    private func render(_ json: String) throws -> AdwaitaWindow {
        _ = try ActionUIModel.shared.loadDescription(from: Data(json.utf8), format: "json", windowUUID: windowUUID)
        let windowModel = try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID])
        return AdwaitaWindow(windowModel: windowModel)
    }

    /// The texts of a box's labels, in order (each label inside its node's ModifierBox).
    private func labels(_ box: WidgetPointer) -> [String] {
        var texts: [String] = []
        var child = gtk_widget_get_first_child(box)
        while let current = child {
            // The node's box holds a content group, which holds the label.
            let label = gtk_widget_get_first_child(current).flatMap { gtk_widget_get_first_child($0) } ?? current
            texts.append(swiftString(gtk_label_get_text(opaque(label))) ?? "?")
            child = gtk_widget_get_next_sibling(current)
        }
        return texts
    }

    func testADocumentBuildsANodeAndAWidgetPerElement() throws {
        let window = try render(document)
        let root = try XCTUnwrap(window.root)
        XCTAssertEqual(root.depth, 0)
        XCTAssertEqual(Set(root.childNodes.keys), [2, 3])
        XCTAssertEqual(root.childNodes[2]?.depth, 1)
        XCTAssertTrue(root.childNodes[2]?.parent === root)
        XCTAssertEqual(labels(root.widget), ["one", "two"])
        XCTAssertEqual(TestUpdates.counts, [1: 1, 2: 1, 3: 1])
    }

    func testAValueChangeResyncsOnlyTheNodeThatReadIt() throws {
        let window = try render(document)
        let root = try XCTUnwrap(window.root)
        ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: 3, value: "changed")
        XCTAssertEqual(labels(root.widget), ["one", "two"], "the widget changes in the next flush")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(labels(root.widget), ["one", "changed"])
        XCTAssertEqual(TestUpdates.counts, [1: 1, 2: 1, 3: 2], "neither the parent nor the sibling re-synced")
    }

    func testChangesBeforeAFlushCoalesce() throws {
        let window = try render(document)
        let root = try XCTUnwrap(window.root)
        ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: 2, value: "a")
        ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: 2, value: "b")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(labels(root.widget), ["b", "two"])
        XCTAssertEqual(TestUpdates.counts[2], 2, "one sync for both changes")

        // Tracking was registered again by that sync.
        ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: 2, value: "c")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(labels(root.widget), ["c", "two"])
    }

    func testInsertedAndRemovedChildrenAreReconciled() throws {
        let window = try render(document)
        let root = try XCTUnwrap(window.root)
        let newID = try ActionUIModel.shared.insertElement(
            windowUUID: windowUUID, parentID: 1,
            json: #"{"type": "Text", "id": 4, "properties": {"text": "first"}}"#,
            position: .at(0))
        XCTAssertEqual(newID, 4)
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(labels(root.widget), ["first", "one", "two"])
        XCTAssertEqual(TestUpdates.counts[2], 1, "existing children are reused, not rebuilt")

        weak let removed = root.childNodes[2]
        XCTAssertNotNil(removed)
        try ActionUIModel.shared.removeElement(windowUUID: windowUUID, viewID: 2)
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(labels(root.widget), ["first", "two"])
        XCTAssertNil(root.childNodes[2])
        XCTAssertNil(removed, "the removed node was released")
    }

    func testANodeRemovedBeforeItsFlushIsNotSynced() throws {
        let window = try render(document)
        let root = try XCTUnwrap(window.root)
        let child = try XCTUnwrap(root.childNodes[3])
        // Both in one turn: the child's change marks it dirty, then the parent's removes it.
        ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: 3, value: "late")
        try ActionUIModel.shared.removeElement(windowUUID: windowUUID, viewID: 3)
        AdwaitaTestHost.drainMainLoop()
        XCTAssertFalse(child.isAttached)
        XCTAssertEqual(TestUpdates.counts[3], 1, "the detached node was skipped")
        XCTAssertEqual(labels(root.widget), ["one"])
    }

    func testAnElementReplacedUnderTheSameIDGetsANewNode() throws {
        let window = try render(document)
        let root = try XCTUnwrap(window.root)
        let old = try XCTUnwrap(root.childNodes[3])
        // Both in one turn, so one flush sees id 3 still listed, with a new view model.
        try ActionUIModel.shared.removeElement(windowUUID: windowUUID, viewID: 3)
        _ = try ActionUIModel.shared.insertElement(
            windowUUID: windowUUID, parentID: 1,
            json: #"{"type": "Text", "id": 3, "properties": {"text": "new"}}"#,
            position: .at(1))
        AdwaitaTestHost.drainMainLoop()
        let replacement = try XCTUnwrap(root.childNodes[3])
        XCTAssertFalse(replacement === old)
        XCTAssertFalse(old.isAttached)
        XCTAssertTrue(replacement.model === ActionUIModel.shared.windowModels[windowUUID]?.viewModels[3])
        XCTAssertEqual(labels(root.widget), ["one", "new"])

        ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: 3, value: "changed")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(labels(root.widget), ["one", "changed"])
    }

    func testATypeWithoutARendererShowsThePlaceholder() throws {
        let window = try render("""
            {"type": "VStack", "id": 1, "children": [{"type": "Slider", "id": 2}]}
            """)
        let root = try XCTUnwrap(window.root)
        let placeholder = try XCTUnwrap(root.childNodes[2])
        XCTAssertTrue(placeholder.renderer == PlaceholderRenderer.self)
        XCTAssertEqual(labels(root.widget), ["Slider is not available on Linux yet"])
        XCTAssertNotEqual(gtk_widget_has_css_class(placeholder.widget, "dim-label"), 0)
    }

    func testActionsFireOnlyOutsideAnUpdate() throws {
        let window = try render(document)
        let node = try XCTUnwrap(window.root?.childNodes[2])
        let fired = CallCounter()
        ActionUIModel.shared.registerActionHandler(for: "test.tap") { actionID, uuid, viewID, _, _ in
            MainActor.assumeIsolated {
                XCTAssertEqual(viewID, 2)
                fired.count += 1
            }
        }
        defer { ActionUIModel.shared.unregisterActionHandler(for: "test.tap") }

        UpdateGuard.applying { node.fire("test.tap") }
        XCTAssertEqual(fired.count, 0)
        node.fire("test.tap")
        XCTAssertEqual(fired.count, 1)
        node.fire(nil)
        node.fire("")
        XCTAssertEqual(fired.count, 1)
    }

    func testAWindowGoneBeforeItsFlushIsNotSynced() throws {
        weak var gone: RenderNode?
        do {
            let window = try render(document)
            gone = window.root?.childNodes[2]
            ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: 2, value: "late")
        }
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(TestUpdates.counts[2], 1, "the tree of the dropped window was not synced")
        XCTAssertNil(gone, "the flush let go of the node")
    }

    func testAWindowWithoutAnElementHasNoRoot() {
        let window = AdwaitaWindow(windowModel: WindowModel(windowUUID: windowUUID, logger: ConsoleLogger(maxLevel: .warning)))
        XCTAssertNil(window.root)
        XCTAssertNil(window.contentWidget)
    }
}
