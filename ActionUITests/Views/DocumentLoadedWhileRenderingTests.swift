// Views/DocumentLoadedWhileRenderingTests.swift
/*
 A description can load while a view renders: a host builds FileLoadableView in a window's
 content (ActionUISwift.loadView), and a LoadableView element loads its file from buildView.
 Rows the host sets afterwards must stay: the load must not make the rendering view depend on
 the new view models, or the write renders it again, which loads the description again and
 replaces the models. Each test hosts the view in a window, sets List rows from the host, and
 checks that the List's model is the same one and that AppKit's table shows the rows.
*/

#if os(macOS)
import XCTest
import SwiftUI
import AppKit
@testable import ActionUI

@MainActor
final class DocumentLoadedWhileRenderingTests: XCTestCase {
    private var windowUUID: String!

    override func setUp() async throws {
        try await super.setUp()
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        ActionUIModel.shared.logger = XCTestLogger(maxLevel: .warning)
        windowUUID = UUID().uuidString
    }

    override func tearDown() async throws {
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        windowUUID = nil
        try await super.tearDown()
    }

    private static let listID = 920

    private static let document: [String: Any] = [
        "type": "VStack", "id": 1,
        "children": [[
            "type": "List", "id": listID, "properties": ["frame": ["height": 150]],
            "template": ["type": "Text", "properties": ["text": "Row $1"]],
        ]],
    ]

    /// Builds FileLoadableView in its body, as a host's window content does.
    private struct HostContent: SwiftUI.View {
        let data: Data
        let windowUUID: String
        let isContentView: Bool
        var body: some SwiftUI.View {
            FileLoadableView(data: data, sourceName: "document", windowUUID: windowUUID,
                             isContentView: isContentView, logger: ActionUIModel.shared.logger)
        }
    }

    private func tableRowCounts(in view: NSView) -> [Int] {
        var counts: [Int] = []
        if let table = view as? NSTableView { counts.append(table.numberOfRows) }
        for sub in view.subviews { counts += tableRowCounts(in: sub) }
        return counts
    }

    private func spin(_ seconds: Double) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    private func checkRowsSurvive(isContentView: Bool) throws {
        if !isContentView {
            // A sub-view load joins a window that already exists.
            _ = try ActionUIModel.shared.loadDescription(from: ["type": "VStack", "id": 500], windowUUID: windowUUID)
        }
        let data = try JSONSerialization.data(withJSONObject: Self.document)
        let host = NSHostingView(rootView: HostContent(data: data, windowUUID: windowUUID, isContentView: isContentView)
            .frame(width: 400, height: 400))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 400), styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        spin(0.3)

        let listModel = try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID]?.viewModels[Self.listID])
        ActionUIModel.shared.setElementRows(windowUUID: windowUUID, viewID: Self.listID, rows: [["One"], ["Two"], ["Three"]])
        spin(0.5)
        host.layoutSubtreeIfNeeded()
        spin(0.3)

        let laterModel = ActionUIModel.shared.windowModels[windowUUID]?.viewModels[Self.listID]
        XCTAssertTrue(laterModel === listModel, "the description was loaded again, replacing the List's model")
        XCTAssertEqual((laterModel?.states["content"] as? [[String]])?.count, 3)
        XCTAssertEqual(tableRowCounts(in: host), [3])
    }

    func testRowsSurviveWhenTheHostLoadsTheDocumentInItsWindowContent() throws {
        try checkRowsSurvive(isContentView: true)
    }

    func testRowsSurviveWhenASubViewLoadsWhileRendering() throws {
        try checkRowsSurvive(isContentView: false)
    }
}
#endif
