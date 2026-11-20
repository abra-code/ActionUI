// Views/NavigationSplitViewNestingTests.swift
/*
 A NavigationSplitView inside another one crashed the host in AppKit during toolbar updates, so a
 document alone could stop its host. The inner one now shows an error and logs it instead. Each test
 hosts the document in a real window, where the crash happened.
*/

#if os(macOS)
import XCTest
import SwiftUI
import AppKit
@testable import ActionUI

private final class RecordingLogger: ActionUILogger, @unchecked Sendable {
    private(set) var errors: [String] = []
    func log(_ message: String, _ level: LoggerLevel) {
        if level == .error { errors.append(message) }
    }
}

@MainActor
final class NavigationSplitViewNestingTests: XCTestCase {
    private var windowUUID: String!
    private var logger: RecordingLogger!
    private var savedLogger: (any ActionUILogger)!

    override func setUp() async throws {
        try await super.setUp()
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        logger = RecordingLogger()
        savedLogger = ActionUIModel.shared.logger
        ActionUIModel.shared.logger = logger
        windowUUID = UUID().uuidString
    }

    override func tearDown() async throws {
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        ActionUIModel.shared.logger = savedLogger
        savedLogger = nil
        windowUUID = nil
        logger = nil
        try await super.tearDown()
    }

    private func splitView(id: Int, detail: [String: Any]) -> [String: Any] {
        return [
            "type": "NavigationSplitView", "id": id,
            "sidebar": ["type": "Text", "id": id * 10 + 1, "properties": ["text": "Sidebar \(id)"]],
            "detail": detail,
        ]
    }

    /// Hosts the document in a window long enough for AppKit to update the toolbar.
    private func host(_ document: [String: Any]) throws {
        let model = ActionUIModel.shared
        let element = try model.loadDescription(from: document, windowUUID: windowUUID)
        let viewModel = try XCTUnwrap(model.windowModels[windowUUID]?.viewModels[element.id])
        let view = ActionUIView(element: element, model: viewModel, windowUUID: windowUUID)
            .frame(width: 600, height: 400)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: view)
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
    }

    func testANestedSplitViewIsRefused() throws {
        let inner = splitView(id: 2, detail: ["type": "Text", "id": 22, "properties": ["text": "Inner detail"]])
        try host(splitView(id: 1, detail: inner))
        XCTAssertEqual(logger.errors.filter { $0.contains(NavigationSplitViewNestingGuard.refusal) }.count, 1,
                       "\(logger.errors)")
        XCTAssertTrue(logger.errors.contains { $0.contains("NavigationSplitView 2") }, "\(logger.errors)")
    }

    /// The shape of the crash report: both split views carry toolbars and titles, and the window
    /// is a titled one whose content view controller hosts the document, so AppKit manages a
    /// window toolbar for them.
    private func toolbarSplitView(id: Int, detail: [String: Any]) -> [String: Any] {
        let item: (Int, String) -> [String: Any] = { itemID, title in
            ["type": "ToolbarItem", "id": itemID, "properties": ["placement": "automatic"],
             "content": ["type": "Button", "id": itemID + 1, "properties": ["title": title, "actionID": "nest.\(itemID)"]]]
        }
        return [
            "type": "NavigationSplitView", "id": id,
            "toolbar": [item(id * 100, "Bar \(id)")],
            "persistentToolbar": [item(id * 100 + 10, "Persist \(id)")],
            "sidebar": ["type": "List", "id": id * 10 + 1, "properties": ["navigationTitle": "Sidebar \(id)"],
                        "children": [["type": "Text", "id": id * 10 + 2, "properties": ["text": "Row \(id)"]]],
                        "toolbar": [item(id * 100 + 20, "New \(id)")]],
            "detail": detail,
        ]
    }

    func testANestedSplitViewWithToolbarsIsRefused() throws {
        let inner = toolbarSplitView(id: 2, detail: ["type": "Text", "id": 29, "properties": ["text": "Inner", "navigationTitle": "Inner"]])
        try hostWithWindowToolbar(toolbarSplitView(id: 1, detail: inner))
        XCTAssertEqual(logger.errors.filter { $0.contains(NavigationSplitViewNestingGuard.refusal) }.count, 1,
                       "\(logger.errors)")
    }

    func testSplitViewsWithToolbarsSideBySideAreNotRefused() throws {
        try hostWithWindowToolbar([
            "type": "HStack", "id": 1,
            "children": [
                toolbarSplitView(id: 2, detail: ["type": "Text", "id": 29, "properties": ["text": "A"]]),
                toolbarSplitView(id: 3, detail: ["type": "Text", "id": 39, "properties": ["text": "B"]]),
            ],
        ])
        XCTAssertFalse(logger.errors.contains { $0.contains(NavigationSplitViewNestingGuard.refusal) },
                       "\(logger.errors)")
    }

    /// Hosts the document as a window's content view controller and resizes the window a few
    /// times, so AppKit builds and updates a window toolbar for it.
    private func hostWithWindowToolbar(_ document: [String: Any]) throws {
        let model = ActionUIModel.shared
        let element = try model.loadDescription(from: document, windowUUID: windowUUID)
        let viewModel = try XCTUnwrap(model.windowModels[windowUUID]?.viewModels[element.id])
        let controller = NSHostingController(rootView: ActionUIView(element: element, model: viewModel, windowUUID: windowUUID)
            .frame(minWidth: 700, minHeight: 450))
        let window = NSWindow(contentViewController: controller)
        window.styleMask.insert([.titled, .resizable, .closable])
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        for width in [700.0, 900.0, 650.0, 1000.0] {
            window.setContentSize(NSSize(width: width, height: 500))
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        }
    }

    func testOneSplitViewIsNotRefused() throws {
        try host(splitView(id: 1, detail: ["type": "Text", "id": 12, "properties": ["text": "Detail"]]))
        XCTAssertFalse(logger.errors.contains { $0.contains(NavigationSplitViewNestingGuard.refusal) },
                       "\(logger.errors)")
    }

    func testSplitViewsSideBySideAreNotNested() throws {
        try host([
            "type": "HStack", "id": 1,
            "children": [
                splitView(id: 2, detail: ["type": "Text", "id": 22, "properties": ["text": "A"]]),
                splitView(id: 3, detail: ["type": "Text", "id": 32, "properties": ["text": "B"]]),
            ],
        ])
        XCTAssertFalse(logger.errors.contains { $0.contains(NavigationSplitViewNestingGuard.refusal) },
                       "\(logger.errors)")
    }
}
#endif
