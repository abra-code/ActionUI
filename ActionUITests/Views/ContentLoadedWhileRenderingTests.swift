// Views/ContentLoadedWhileRenderingTests.swift
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
final class ContentLoadedWhileRenderingTests: XCTestCase {
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

    private static let json: [String: Any] = [
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
        let data = try JSONSerialization.data(withJSONObject: Self.json)
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

    /// Keeps every message, so a test can look for the refusal (XCTestLogger fails on errors).
    private final class CapturingLogger: ActionUILogger, @unchecked Sendable {
        var messages: [String] = []
        func log(_ message: String, _ level: LoggerLevel) { messages.append(message) }
    }

    func testAJSONFileThatLoadsItselfIsRefusedAtTheRepeat() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("self-loading-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        // The app's own resources: less-trusted content (a file elsewhere) loads no local files.
        let savedFolders = ActionUIRendererHooks.resourceFolders
        defer { ActionUIRendererHooks.resourceFolders = savedFolders }
        ActionUIRendererHooks.resourceFolders = { [folder.path] }
        let file = folder.appendingPathComponent("Self.json")
        let document: [String: Any] = [
            "type": "VStack", "id": 1,
            "children": [["type": "LoadableView", "id": 2, "properties": ["filePath": file.path]]],
        ]
        try JSONSerialization.data(withJSONObject: document).write(to: file)
        let logger = CapturingLogger()
        ActionUIModel.shared.logger = logger

        let content = FileLoadableView(fileURL: file, windowUUID: windowUUID, isContentView: true, logger: logger)
        let host = NSHostingView(rootView: content.frame(width: 300, height: 300))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 300), styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        spin(0.5)

        XCTAssertTrue(logger.messages.contains { $0.contains("it includes itself") }, "\(logger.messages.suffix(5))")
        let loads = logger.messages.filter { $0.hasPrefix("Successfully loaded json for LoadableView from") }.count
        XCTAssertLessThanOrEqual(loads, 4, "the document loaded \(loads) times")
    }

    /// Documents that each list all the others multiply their loads past the depth limit (about 2000
    /// loads in 4 seconds before the load budget); the budget stops them at its count.
    func testJSONFilesThatListEachOtherStopAtTheLoadBudget() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("measure-loop-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        // The app's own resources: less-trusted content (a file elsewhere) loads no local files.
        let savedFolders = ActionUIRendererHooks.resourceFolders
        defer { ActionUIRendererHooks.resourceFolders = savedFolders }
        ActionUIRendererHooks.resourceFolders = { [folder.path] }
        let count = 7
        let files = (0..<count).map { folder.appendingPathComponent("D\($0).json") }
        for (index, file) in files.enumerated() {
            let children: [[String: Any]] = files.enumerated().filter { $0.offset != index }.map { other in
                ["type": "LoadableView", "id": 1000 * (index + 1) + other.offset, "properties": ["filePath": other.element.path]]
            }
            try JSONSerialization.data(withJSONObject: ["type": "VStack", "id": 100 + index, "children": children]).write(to: file)
        }
        let logger = CapturingLogger()
        ActionUIModel.shared.logger = logger
        let start = Date()
        let content = FileLoadableView(fileURL: files[0], windowUUID: windowUUID, isContentView: true, logger: logger)
        let host = NSHostingView(rootView: content.frame(width: 300, height: 300))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 300), styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        // Until the first refusal (a slow machine may take longer), then a little more for any load after it.
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline, !logger.messages.contains(where: { $0.contains("loads in 60 s already") }) { spin(0.1) }
        spin(0.5)
        let loads = logger.messages.filter { $0.hasPrefix("Successfully loaded json for LoadableView from") }.count
        let refused = logger.messages.filter { $0.contains("loads in 60 s already") }.count
        XCTAssertLessThanOrEqual(loads, ActionUIConfiguration.current.limits.loadBudget.loads + 1, "the window's root and the budget's loads")
        XCTAssertGreaterThan(refused, 0, "the rest is refused")
        XCTAssertLessThan(Date().timeIntervalSince(start), 10)
    }

    func testRowsSurviveWhenTheHostLoadsTheJSONInItsWindowContent() throws {
        try checkRowsSurvive(isContentView: true)
    }

    func testRowsSurviveWhenASubViewLoadsWhileRendering() throws {
        try checkRowsSurvive(isContentView: false)
    }

    /// A LoadableView in a List's template row, drawn in a window: it is judged by the List's
    /// content (the host's here), not by the id it carries, and it loads nothing, and fires no
    /// viewDidLoadActionID, when that id is another element's in the window.
    func testATemplateRowsLoadableViewIsJudgedByItsRowAndCannotTakeAnotherElementsPlace() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("template-loadable-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("Row.json")
        try JSONSerialization.data(withJSONObject: ["type": "Text", "id": 800, "properties": ["text": "Row"]]).write(to: file)
        let savedFolders = ActionUIRendererHooks.resourceFolders
        defer { ActionUIRendererHooks.resourceFolders = savedFolders }
        ActionUIRendererHooks.resourceFolders = { [folder.path] }
        let logger = CapturingLogger()
        ActionUIModel.shared.logger = logger
        var fired: [Int] = []
        ActionUIModel.shared.registerActionHandler(for: "row.loaded") { _, _, viewID, _, _ in fired.append(viewID) }

        func show(templateID: Int) throws {
            windowUUID = UUID().uuidString
            let document: [String: Any] = [
                "type": "VStack", "id": 1,
                "children": [
                    ["type": "LoadableView", "id": 100],
                    ["type": "List", "id": Self.listID, "properties": ["frame": ["height": 150]],
                     "template": ["type": "LoadableView", "id": templateID,
                                  "properties": ["filePath": file.path, "viewDidLoadActionID": "row.loaded"]]],
                ],
            ]
            let data = try JSONSerialization.data(withJSONObject: document)
            let host = NSHostingView(rootView: HostContent(data: data, windowUUID: windowUUID, isContentView: true)
                .frame(width: 400, height: 400))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 400), styleMask: [.titled],
                                  backing: .buffered, defer: false)
            window.contentView = host
            window.orderFrontRegardless()
            defer { window.orderOut(nil) }
            spin(0.3)
            ActionUIModel.shared.setElementRows(windowUUID: windowUUID, viewID: Self.listID, rows: [["One"]])
            spin(0.5)
            host.layoutSubtreeIfNeeded()
            spin(0.3)
        }

        // The id of the host's LoadableView 100: refused, so nothing loads into its place.
        try show(templateID: 100)
        XCTAssertTrue(logger.messages.contains { $0.contains("id 100 is another element's in the window") }, "\(logger.messages.suffix(5))")
        XCTAssertNil(ActionUIModel.shared.windowModels[windowUUID]?.viewModels[800])
        XCTAssertEqual(fired, [])

        // An id nothing has: the app's own file in a row of the host's List is as trusted as the List.
        try show(templateID: 555)
        let origin = try XCTUnwrap(ActionUIModel.shared.origin(windowUUID: windowUUID, viewID: 800), "\(logger.messages.suffix(5))")
        XCTAssertEqual(origin.trust, .trusted)
        XCTAssertEqual(fired, [], "a template row's LoadableView has no view model of its own to fire for")
    }
}
#endif
