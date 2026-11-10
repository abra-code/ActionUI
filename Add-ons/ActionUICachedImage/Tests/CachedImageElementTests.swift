// Add-ons/ActionUICachedImage/Tests/CachedImageElementTests.swift
//
// The element on Linux. The geometry is plain arithmetic; the rest runs in a real application window, one scripted
// test as an application runs once in a process, with CachedImage under a wrapper that keeps each node.

#if os(Linux)

import XCTest
import ActionUI
import ActionUIAdwaitaApplication
import AsyncImageCache
import CAdwaita
import Dispatch
import FoundationEssentials
@testable import ActionUICachedImage

// 4 x 2 pixels, as a data: URL, which the store decodes without a network.
private let wideImage = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAQAAAACCAIAAADwyuo0AAAAEklEQVR4nGP4zwAE/yEkAzIHAGeyB/kJEgKyAAAAAElFTkSuQmCC"

/// CachedImage with its nodes kept by element id.
private struct KeptCachedImage: ActionUIAdwaitaElement {
    static var nodes: [Int: RenderNode] = [:]

    static var valueType: Any.Type { CachedImage.valueType }
    static var initialValue: (ViewModel) -> Any? { CachedImage.initialValue }
    static var initialStates: (ViewModel) -> [String: Any] { CachedImage.initialStates }
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? { nil }
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? { nil }
    static var insertableContainers: [String: ContainerShape]? { nil }
    static var handledBaseModifiers: Set<String> { CachedImage.handledBaseModifiers }

    static func makeWidget(_ node: RenderNode) -> OpaquePointer {
        nodes[node.element.id] = node
        return CachedImage.makeWidget(node)
    }

    static func update(_ widget: OpaquePointer, _ node: RenderNode) {
        CachedImage.update(widget, node)
    }
}

@MainActor
final class CachedImageElementTests: XCTestCase {
    private let windowUUID = "cached-image-element"
    private var stepsRun = false
    private var staleCompletionRan = false
    private weak var keptState: CachedImageState?
    private weak var keptNode: RenderNode?
    private var keptWidget: UnsafeMutablePointer<GtkWidget>?

    // MARK: Geometry, as SwiftUI's aspectRatio and contentMode

    func testTheBoxFitsCenteredInTheSpace() {
        let wide = CachedImageState.fitted(aspect: 2, in: (100, 100))
        XCTAssertEqual(wide.width, 100)
        XCTAssertEqual(wide.height, 50)
        XCTAssertEqual(wide.y, 25, "centered across")
        let tall = CachedImageState.fitted(aspect: 0.5, in: (100, 100))
        XCTAssertEqual(tall.width, 50)
        XCTAssertEqual(tall.x, 25)
    }

    func testFitStaysInsideTheBoxAndFillCoversIt() {
        let box: CachedImageState.Rectangle = (0, 0, 100, 100)
        let fit = CachedImageState.fitting((200, 100), box)
        XCTAssertEqual(fit.width, 100)
        XCTAssertEqual(fit.height, 50)
        XCTAssertEqual(fit.y, 25)
        let fill = CachedImageState.covering((200, 100), box)
        XCTAssertEqual(fill.width, 200)
        XCTAssertEqual(fill.height, 100)
        XCTAssertEqual(fill.x, -50, "centered on the box; the clip cuts the rest")
    }

    func testIntrinsicSizeNeedsTwoPositiveNumbers() {
        XCTAssertEqual(CachedImage.intrinsicSize(["width": 4, "height": 2.5])?.height, 2.5)
        XCTAssertNil(CachedImage.intrinsicSize(["width": 4]))
        XCTAssertNil(CachedImage.intrinsicSize(["width": 0, "height": 2]), "the aspect divides by it")
        XCTAssertNil(CachedImage.intrinsicSize(["width": -1, "height": 2]))
        XCTAssertNil(CachedImage.intrinsicSize(["width": true, "height": 2]))
        XCTAssertNil(CachedImage.intrinsicSize("4x2"))
    }

    // MARK: In a window

    /// A step of the scripted test: `body` runs once `ready` holds.
    private struct Step {
        var ready: () -> Bool = { true }
        let body: () -> Void
    }

    private func state(_ id: Int) -> CachedImageState? {
        KeptCachedImage.nodes[id]?.state as? CachedImageState
    }

    private func height(_ id: Int, forWidth width: Int32) -> Int32 {
        state(id).map { height(of: $0.widget, forWidth: width) } ?? -1
    }

    private func height(of widget: UnsafeMutablePointer<GtkWidget>, forWidth width: Int32) -> Int32 {
        var natural: Int32 = 0
        gtk_widget_measure(widget, GTK_ORIENTATION_VERTICAL, width, nil, &natural, nil, nil)
        return natural
    }

    /// The first node of `type` in what the element draws in `width` x `height`, for `check`.
    private func withDrawn(_ id: Int, _ type: GskRenderNodeType, width: Double = 100, height: Double = 100,
                           check: (OpaquePointer) -> Void) {
        let snapshot = gtk_snapshot_new()!
        state(id)?.draw(snapshot, width: width, height: height)
        guard let root = gtk_snapshot_free_to_node(snapshot) else {
            XCTFail("element \(id) drew nothing")
            return
        }
        defer { gsk_render_node_unref(root) }
        guard let node = Self.first(type, in: root) else {
            XCTFail("element \(id) drew no node of type \(type.rawValue)")
            return
        }
        check(node)
    }

    private static func first(_ type: GskRenderNodeType, in node: OpaquePointer) -> OpaquePointer? {
        let own = gsk_render_node_get_node_type(node)
        if own == type { return node }
        switch own {
        case GSK_CONTAINER_NODE:
            for index in 0..<gsk_container_node_get_n_children(node) {
                if let child = gsk_container_node_get_child(node, index), let found = first(type, in: child) { return found }
            }
            return nil
        case GSK_CLIP_NODE: return gsk_clip_node_get_child(node).flatMap { first(type, in: $0) }
        case GSK_ROUNDED_CLIP_NODE: return gsk_rounded_clip_node_get_child(node).flatMap { first(type, in: $0) }
        default: return nil
        }
    }

    private func assertBounds(_ node: OpaquePointer, _ expected: CachedImageState.Rectangle,
                              _ message: String, line: UInt = #line) {
        var bounds = graphene_rect_t()
        gsk_render_node_get_bounds(node, &bounds)
        XCTAssertEqual(Double(bounds.origin.x), expected.x, accuracy: 0.01, "x, \(message)", line: line)
        XCTAssertEqual(Double(bounds.origin.y), expected.y, accuracy: 0.01, "y, \(message)", line: line)
        XCTAssertEqual(Double(bounds.size.width), expected.width, accuracy: 0.01, "width, \(message)", line: line)
        XCTAssertEqual(Double(bounds.size.height), expected.height, accuracy: 0.01, "height, \(message)", line: line)
    }

    func testTheElementInAWindow() throws {
        try XCTSkipUnless(gtk_init_check() != 0, "needs a display")
        ActionUICachedImage_register()
        ActionUIRegistry.shared.register(KeptCachedImage.self, as: "CachedImage")

        let document = """
            {"type": "VStack", "children": [
                {"type": "CachedImage", "id": 1, "properties": {
                    "url": "\(wideImage)", "cornerRadius": 12, "frame": {"width": 100, "height": 100}}},
                {"type": "CachedImage", "id": 2, "properties": {
                    "intrinsicSize": {"width": 300, "height": 100}, "contentMode": "fit", "frame": {"width": 100, "height": 100}}},
                {"type": "CachedImage", "id": 3, "properties": {"url": "no scheme", "frame": {"width": 100, "height": 100}}},
                {"type": "CachedImage", "id": 4, "properties": {
                    "url": "\(wideImage)", "intrinsicSize": {"width": 300, "height": 100}, "frame": {"width": 100, "height": 100}}}
            ]}
            """
        let app = AdwaitaApplication.shared
        let another = ImageRequest(url: URL(string: wideImage)!, targetWidth: 2)

        let steps: [Step] = [
            Step(ready: { [self] in state(1)?.image != nil && state(4)?.image != nil }) { [self] in
                XCTAssertEqual(state(1)?.image?.pixelWidth, 4, "a data: image loads")
                XCTAssertEqual(state(1)?.aspect, 2, "once loaded, the box has the image's aspect")
                XCTAssertEqual(height(1, forWidth: 200), 100)
                XCTAssertEqual(gtk_accessible_get_accessible_role(OpaquePointer(state(1)?.widget)), GTK_ACCESSIBLE_ROLE_IMG)

                XCTAssertEqual(gtk_widget_get_overflow(gtk_widget_get_parent(state(1)?.widget)), GTK_OVERFLOW_VISIBLE,
                               "the box around the widget does not round: cornerRadius is the element's")
                withDrawn(1, GSK_ROUNDED_CLIP_NODE) { node in
                    assertBounds(node, (0, 25, 100, 50), "the clip is the box, not the widget")
                    XCTAssertEqual(gsk_rounded_clip_node_get_clip(node).pointee.corner.0.width, 12, "the box's corners")
                }
                withDrawn(1, GSK_TEXTURE_SCALE_NODE) { node in
                    assertBounds(node, (0, 25, 100, 50), "the image in its box")
                    XCTAssertEqual(gsk_texture_scale_node_get_filter(node), GSK_SCALING_FILTER_TRILINEAR)
                }

                XCTAssertNil(state(2)?.request, "no URL shows the placeholder")
                XCTAssertEqual(state(2)?.aspect, 3, "and the hint reserves the box before any image")
                XCTAssertEqual(height(2, forWidth: 300), 100)
                withDrawn(2, GSK_COLOR_NODE) { node in
                    assertBounds(node, (0, 100.0 / 3, 100, 100.0 / 3), "a gray box when nothing is known of the image")
                }

                withDrawn(4, GSK_CLIP_NODE) { node in
                    assertBounds(node, (0, 100.0 / 3, 100, 100.0 / 3), "the box has the hint's aspect")
                }
                withDrawn(4, GSK_TEXTURE_SCALE_NODE) { node in
                    assertBounds(node, (0, 25, 100, 50), "fill, the default, covers the box; the clip cuts the rest")
                }

                XCTAssertNil(state(3)?.image, "a URL that loads nothing leaves the placeholder")
                XCTAssertEqual(state(3)?.aspect, 4.0 / 3, "at a neutral aspect")
                XCTAssertEqual(height(3, forWidth: 200), 150)

                ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: 2, value: wideImage)
                ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: 3, value: wideImage)
            },
            Step(ready: { [self] in state(2)?.image != nil && state(3)?.image != nil }) { [self] in
                XCTAssertEqual(state(2)?.aspect, 3, "the runtime value wins over the property; the hint still sets the box")
                withDrawn(2, GSK_TEXTURE_SCALE_NODE) { node in
                    assertBounds(node, (50.0 / 3, 100.0 / 3, 200.0 / 3, 100.0 / 3), "fit stays inside the box")
                }
                XCTAssertEqual(height(3, forWidth: 200), 100, "without a hint the box follows the image that arrives")

                // The store has the original, not this size of it: the grid shows while it is made.
                state(3)?.load(another)
                XCTAssertNil(state(3)?.image, "a new request does not keep the old image")
                XCTAssertNotNil(state(3)?.placeholder)
                withDrawn(3, GSK_TEXTURE_SCALE_NODE) { node in
                    assertBounds(node, (0, 25, 100, 50), "the grid is stretched into the box")
                    XCTAssertEqual(gsk_texture_scale_node_get_filter(node), GSK_SCALING_FILTER_LINEAR)
                }
                // The element moves on while it loads. The store answers in the order it was asked.
                state(3)?.load(nil)
                ImageStore.shared.load(another) { [self] _ in
                    MainActor.assumeIsolated { staleCompletionRan = true }
                }
                ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: 2, value: "")
            },
            Step(ready: { [self] in staleCompletionRan && state(2)?.request == nil }) { [self] in
                XCTAssertNil(state(3)?.image, "a completion for a request the element left does not show")
                XCTAssertNil(state(2)?.request, "an empty value falls back to the property, here none")
                XCTAssertNil(state(2)?.image, "and the old image does not stay")

                state(2)?.apply(hint: ImageSize(width: 1e300, height: 1e-300), fills: false, cornerRadius: 0)
                XCTAssertEqual(height(2, forWidth: 0), 0, "a hint that overflows every size does not trap")

                keptState = state(1)
                keptNode = KeptCachedImage.nodes[1]
                keptWidget = state(1)?.widget
                g_object_ref(UnsafeMutableRawPointer(keptWidget))
                KeptCachedImage.nodes.removeAll()
                app.closeWindow(windowUUID)
            },
            Step(ready: { [self] in keptNode == nil }) { [self] in
                XCTAssertNotNil(keptState, "GTK can keep a widget after its node: the widget keeps what it draws")
                if let keptWidget {
                    XCTAssertEqual(height(of: keptWidget, forWidth: 200), 100)
                    g_object_unref(UnsafeMutableRawPointer(keptWidget))
                }
            },
            Step(ready: { [self] in keptState == nil }) { [self] in
                stepsRun = true
            },
        ]

        app.applicationID = "com.abracode.actionui.cachedimage.tests"
        app.handlers.windowWillPresent = { _ in
            Self.run(steps[...]) {
                app.terminate()
            }
        }
        app.presentWindow(json: Data(document.utf8), windowUUID: windowUUID, title: nil)
        XCTAssertEqual(app.run(), 0)
        XCTAssertTrue(stepsRun, "every step ran")
    }

    private static func run(_ steps: ArraySlice<Step>, polls: Int = 0, then finish: @escaping @MainActor () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(20)) {
            MainActor.assumeIsolated {
                guard let step = steps.first else {
                    finish()
                    return
                }
                guard step.ready() else {
                    if polls < 500 {
                        run(steps, polls: polls + 1, then: finish)
                    } else {
                        XCTFail("step \(steps.startIndex) was not ready in 10 seconds")
                        finish()
                    }
                    return
                }
                step.body()
                run(steps.dropFirst(), then: finish)
            }
        }
    }
}

#endif
