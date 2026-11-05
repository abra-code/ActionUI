// Add-ons/ActionUIDiff/Tests/DiffElementGtkTests.swift
//
// The element on Linux, in a real application window: how the properties reach the diff view, the note for a file
// that cannot be read, and live property changes. An application runs once in a process and an add-on sees no render
// tree of its own, so this is one scripted test, whose steps run on the application's main loop, with Diff under a
// wrapper that keeps each node. The view's own tests live in the DiffView repo.

#if os(Linux)

import XCTest
import ActionUI
import CAdwaita
import DiffView
import Dispatch
import FoundationEssentials
@testable import ActionUIDiff

/// Diff with its nodes kept by element id.
private struct KeptDiff: ActionUIAdwaitaElement {
    static var nodes: [Int: RenderNode] = [:]

    static var valueType: Any.Type { Diff.valueType }
    static var initialValue: (ViewModel) -> Any? { Diff.initialValue }
    static var initialStates: (ViewModel) -> [String: Any] { Diff.initialStates }
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? { nil }
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? { nil }
    static var insertableContainers: [String: ContainerShape]? { nil }

    static func makeWidget(_ node: RenderNode) -> OpaquePointer {
        nodes[node.element.id] = node
        return Diff.makeWidget(node)
    }

    static func update(_ widget: OpaquePointer, _ node: RenderNode) {
        Diff.update(widget, node)
    }
}

@MainActor
final class DiffElementGtkTests: XCTestCase {
    private let windowUUID = "diff-element"
    private var stepsRun = false
    private let missing = "/nonexistent-actionui-diff-\(UUID().uuidString).txt"

    private var document: String { """
        {"type": "VStack", "properties": {"frame": {"width": 500}}, "children": [
            {"type": "Diff", "id": 1, "properties": {"oldText": "a\\nb\\nc\\n", "newText": "a\\nB\\nc\\n", "contextLines": 0}},
            {"type": "Diff", "id": 2, "properties": {"oldFile": "\(missing)", "newText": "x\\n"}},
            {"type": "Diff", "id": 3, "properties": {"oldText": "same", "newText": "same", "maxRenderedLines": "many"}}
        ]}
        """
    }

    private func state(_ id: Int) -> DiffElementState? {
        KeptDiff.nodes[id]?.state as? DiffElementState
    }

    private func setProperty(_ id: Int, _ name: String, _ value: Any) {
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: id, propertyName: name, value: value)
    }

    /// The diff view's rows (or notes), each as its labels' texts joined by "|".
    private func rows(_ id: Int) -> [String] {
        guard let view = state(id)?.view else { return [] }
        var result: [String] = []
        var row = gtk_widget_get_first_child(UnsafeMutablePointer<GtkWidget>(view.widget))
        while let current = row {
            var texts: [String] = []
            if gtk_widget_get_first_child(current) == nil {
                texts.append(String(cString: gtk_label_get_text(OpaquePointer(current))))
            }
            var label = gtk_widget_get_first_child(current)
            while let each = label {
                texts.append(String(cString: gtk_label_get_text(OpaquePointer(each))))
                label = gtk_widget_get_next_sibling(each)
            }
            result.append(texts.joined(separator: "|"))
            row = gtk_widget_get_next_sibling(current)
        }
        return result
    }

    private func isVisible(_ widget: UnsafeMutablePointer<GtkWidget>?) -> Bool {
        widget.map { gtk_widget_get_visible($0) != 0 } ?? false
    }

    private func noteText(_ id: Int) -> String? {
        guard let note = state(id)?.note, let label = gtk_widget_get_first_child(note) else { return nil }
        return String(cString: gtk_label_get_text(OpaquePointer(label)))
    }

    func testTheElementInAWindow() throws {
        try XCTSkipUnless(gtk_init_check() != 0, "needs a display")
        // The C entry point, on the thread the application runs on: it holds on the main actor there too.
        ActionUIDiff_register()
        ActionUIRegistry.shared.register(KeptDiff.self, as: "Diff")

        // Each step runs after the updates of the one before it, on the main loop.
        let steps: [() -> Void] = [
            { [self] in
                XCTAssertEqual(rows(1), ["\u{22EF} 1 unchanged line", "2||-|b", "|2|+|B", "\u{22EF} 1 unchanged line"],
                               "the properties reach the view")
                let box = UnsafeMutableRawPointer(state(1)!.box).assumingMemoryBound(to: GtkWidget.self)
                XCTAssertGreaterThanOrEqual(gtk_widget_get_width(box), 490, "the diff takes the width it is offered")
                XCTAssertNil(state(2)?.view, "an unreadable file shows no diff")
                XCTAssertEqual(noteText(2), "Cannot read \(missing)")
                XCTAssertTrue(isVisible(state(2)?.note))
                XCTAssertEqual(rows(3), ["No changes"], "an ill-typed cap falls back to the default")
                setProperty(1, "newText", "a\nb\nC\n")
                setProperty(2, "oldText", "w\n")
            },
            { [self] in
                XCTAssertEqual(rows(1), ["\u{22EF} 2 unchanged lines", "3||-|c", "|3|+|C"], "a property set later shows")
                XCTAssertEqual(rows(2), ["1||-|w", "|1|+|x"], "the text wins over the unreadable file")
                XCTAssertTrue(isVisible(state(2)?.view.map { UnsafeMutablePointer<GtkWidget>($0.widget) }))
                XCTAssertFalse(isVisible(state(2)?.note), "the note goes")
                // No way to remove a property: a text of another type is no text, so the file is read again.
                setProperty(2, "oldText", 0)
            },
            { [self] in
                XCTAssertTrue(isVisible(state(2)?.note), "the unreadable file is back")
                XCTAssertFalse(isVisible(state(2)?.view.map { UnsafeMutablePointer<GtkWidget>($0.widget) }), "and the diff hides")
                stepsRun = true
            },
        ]

        let app = AdwaitaApplication.shared
        app.applicationID = "com.abracode.actionui.diff.tests"
        app.handlers.windowWillPresent = { _ in
            Self.run(steps[...]) {
                app.terminate()
            }
        }
        app.presentWindow(json: Data(document.utf8), windowUUID: windowUUID, title: nil)
        XCTAssertEqual(app.run(), 0)
        XCTAssertEqual(KeptDiff.nodes.count, 3)
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
}

#endif
