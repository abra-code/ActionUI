/*
 RangeInputRenderTests.swift

 Renders elements whose properties would make SwiftUI stop the app if passed through as given: a
 Slider step that makes too many steps (SwiftUI keeps every step in memory), and reversed line
 limit and fraction length ranges (a reversed ClosedRange traps). Each test passes when the window
 content draws.
*/

#if os(macOS)
import XCTest
import SwiftUI
import AppKit
@testable import ActionUI

@MainActor
final class RangeInputRenderTests: XCTestCase {
    private var logger: XCTestLogger!
    private var windowUUID: String!

    override func setUp() async throws {
        try await super.setUp()
        logger = XCTestLogger(maxLevel: .verbose)
        ActionUIModel.shared.logger = logger
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        windowUUID = UUID().uuidString
    }

    override func tearDown() async throws {
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        logger = nil
        windowUUID = nil
        try await super.tearDown()
    }

    /// Loads the element, hosts it in an AppKit view and draws it.
    private func draw(_ elementDict: [String: Any]) throws {
        let model = ActionUIModel.shared
        let element = try model.loadDescription(from: elementDict, windowUUID: windowUUID)
        let viewModel = try XCTUnwrap(model.windowModels[windowUUID]?.viewModels[element.id])
        let host = NSHostingView(rootView: ActionUIView(element: element, model: viewModel, windowUUID: windowUUID)
            .frame(width: 300, height: 120))
        host.frame = NSRect(x: 0, y: 0, width: 300, height: 120)
        host.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
    }

    func testSliderWithTooManyStepsDraws() throws {
        // 1e19 steps: SwiftUI would try to allocate them all.
        try draw(["id": 1, "type": "Slider", "properties": ["range": ["min": 0, "max": 1e19], "step": 1]])
    }

    func testSliderWithAnInfiniteRangeAndAStepDraws() throws {
        try draw(["id": 1, "type": "Slider", "properties": ["range": ["min": 0, "max": Double.infinity], "step": 1]])
    }

    func testTextFieldWithAReversedLineLimitDraws() throws {
        try draw(["id": 1, "type": "TextField", "properties": ["axis": "vertical", "lineLimit": ["min": 5, "max": 2]]])
    }

    func testTextFieldWithAReversedFractionLengthDraws() throws {
        for format in ["decimal", "percent", "currency"] {
            try draw(["id": 1, "type": "TextField", "properties": ["format": format, "fractionLength": ["min": 3, "max": 1]]])
            try draw(["id": 1, "type": "TextField", "properties": ["format": format, "fractionLength": ["max": -1]]])
        }
    }
}
#endif
