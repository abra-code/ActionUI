// Tests/Views/ScrollViewReaderScrollingTests.swift
// ScrollViewReader scrolling in a real window (an offscreen render runs no onAppear): the reader
// brings its scrollTo element to its anchor when it appears, and again after a write to the
// reader, also of the same id once the user scrolled away. Read from the NSScrollView SwiftUI's
// ScrollView is drawn with. Scrolls after a write are not animated here (scrollAnimation nil).

#if os(macOS)
import XCTest
import SwiftUI
import AppKit
@testable import ActionUI

@MainActor
final class ScrollViewReaderScrollingTests: XCTestCase {
    private var windowUUID: String!
    private var window: NSWindow?

    override func setUp() async throws {
        try await super.setUp()
        ActionUIModel.shared.logger = XCTestLogger(maxLevel: .warning)
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        windowUUID = UUID().uuidString
        // An XCTest window runs no animations: scrolls after a write jump instead.
        ScrollViewReader.scrollAnimation = nil
    }

    override func tearDown() async throws {
        window?.orderOut(nil)
        window = nil
        ScrollViewReader.scrollAnimation = .default
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        windowUUID = nil
        try await super.tearDown()
    }

    /// A reader around twelve rows 100 high (ids 2...13), in a window 300 high.
    private func show(scrollTo: Int, anchor: String) throws -> NSScrollView {
        let rows = (2...13).map { id in
            #"{"type": "Color", "id": \#(id), "properties": {"color": "\#(id % 2 == 0 ? "#FF0000" : "#0000FF")", "frame": {"width": 200, "height": 100}}}"#
        }
        let json = #"{"type": "ScrollViewReader", "id": 1, "properties": {"scrollTo": \#(scrollTo), "anchor": "\#(anchor)"}, "content": {"type": "ScrollView", "id": 20, "content": {"type": "VStack", "id": 21, "properties": {"spacing": 0}, "children": [\#(rows.joined(separator: ","))]}}}"#
        let element = try ActionUIModel.shared.loadDescription(from: Data(json.utf8), format: "json", windowUUID: windowUUID)
        let model = try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID]?.viewModels[element.id])
        let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 300, height: 300), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: ActionUIView(element: element, model: model, windowUUID: windowUUID)
            .frame(width: 300, height: 300))
        window.orderFrontRegardless()
        self.window = window
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        return try XCTUnwrap(Self.scrollView(in: try XCTUnwrap(window.contentView)), "SwiftUI's ScrollView draws in an NSScrollView")
    }

    private static func scrollView(in view: NSView) -> NSScrollView? {
        if let scrollView = view as? NSScrollView { return scrollView }
        for child in view.subviews {
            if let found = scrollView(in: child) { return found }
        }
        return nil
    }

    /// The top of the visible part of the content, once it settles at `expected` (or the timeout).
    private func offset(of scrollView: NSScrollView, settlingAt expected: CGFloat) -> CGFloat {
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline, abs(scrollView.documentVisibleRect.minY - expected) > 0.5 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        return scrollView.documentVisibleRect.minY
    }

    func testTheTargetIsAtTheTopWhenTheReaderAppears() throws {
        let scrollView = try show(scrollTo: 5, anchor: "top")
        // Row id 5 is the fourth row: its top is 300 down the content.
        XCTAssertEqual(offset(of: scrollView, settlingAt: 300), 300, accuracy: 0.5)
    }

    func testTheCenterAnchorCentersTheTarget() throws {
        let scrollView = try show(scrollTo: 7, anchor: "center")
        // Row id 7 spans 500...600: its middle, 550, at the middle of 300.
        XCTAssertEqual(offset(of: scrollView, settlingAt: 400), 400, accuracy: 0.5)
    }

    func testWritingTheSameTargetAgainBringsItBack() throws {
        let scrollView = try show(scrollTo: 5, anchor: "top")
        XCTAssertEqual(offset(of: scrollView, settlingAt: 300), 300, accuracy: 0.5)
        // The user scrolls back to the top.
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        XCTAssertEqual(scrollView.documentVisibleRect.minY, 0, accuracy: 0.5)
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "scrollTo", value: 5)
        XCTAssertEqual(offset(of: scrollView, settlingAt: 300), 300, accuracy: 0.5)
    }

    func testANewTargetScrollsToIt() throws {
        let scrollView = try show(scrollTo: 5, anchor: "top")
        XCTAssertEqual(offset(of: scrollView, settlingAt: 300), 300, accuracy: 0.5)
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "scrollTo", value: 3)
        XCTAssertEqual(offset(of: scrollView, settlingAt: 100), 100, accuracy: 0.5)
    }
}
#endif
