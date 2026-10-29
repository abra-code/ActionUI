// Tests/Application/ContentSizeLimitsTests.swift
/*
 ActionUIModel.contentSizeLimits on Linux (Sources/Runtime/ContentSizeLimits+Adwaita.swift), for
 windows on screen: a fixed frame gives the same minimum and maximum, as SwiftUI reports it; a
 flexible frame its minimum and maximum; a Color and a frame to maxWidth infinity are unbounded
 (Double.greatestFiniteMagnitude, Apple's value) in the axes they expand in; a Text is bounded by
 its natural size, and its minimum height is not above its maximum, though it wraps taller at its
 minimum width. A window that is only in the model, and an unknown one, have none. The windows
 are presented before the run and measured once it has started, through the C functions, as a
 host would.
*/

import XCTest
import CAdwaita
import Glibc
@testable import ActionUI
import ActionUIAdwaitaApplication

/// What the did-finish-launching handler measured, by window; a C function pointer cannot capture.
nonisolated(unsafe) private var measured: [String: ContentSizeLimits?] = [:]

private let documents: [String: String] = [
    "csl-fixed": #"{"type": "Text", "id": 1, "properties": {"text": "Fixed", "frame": {"width": 300, "height": 200}}}"#,
    "csl-flexible": #"{"type": "Color", "id": 1, "properties": {"color": "red", "frame": {"minWidth": 100, "maxWidth": 400, "minHeight": 50, "maxHeight": 300}}}"#,
    "csl-color": #"{"type": "Color", "id": 1, "properties": {"color": "blue"}}"#,
    "csl-text": #"{"type": "Text", "id": 1, "properties": {"text": "Hello world"}}"#,
    "csl-wide": #"{"type": "VStack", "id": 1, "children": [{"type": "Text", "id": 2, "properties": {"text": "Wide", "frame": {"maxWidth": "infinity"}}}]}"#,
]

@MainActor
final class ContentSizeLimitsTests: XCTestCase {
    override func setUp() async throws {
        // No super.setUp(): see ActionUIAppFunctionTests.
        try AdwaitaTestHost.initialize()
        ActionUIRegistry.shared.loadBuiltIns()
        measured = [:]
    }

    override func tearDown() async throws {
        actionUIAppSetDidFinishLaunchingHandler(nil)
        for windowUUID in documents.keys {
            ActionUIModel.shared.windowModels[windowUUID] = nil
        }
        ActionUIModel.shared.windowModels["csl-model-only"] = nil
        AdwaitaTestHost.drainMainLoop()
    }

    func testWindowsOnScreenReportTheirContentsLimits() throws {
        for (windowUUID, json) in documents {
            actionUIAppLoadAndPresentWindowFromJSON(json, windowUUID, nil)
        }
        actionUIAppSetDidFinishLaunchingHandler {
            MainActor.assumeIsolated {
                for windowUUID in documents.keys {
                    measured[windowUUID] = ActionUIModel.shared.contentSizeLimits(windowUUID: windowUUID)
                }
                measured["csl-unknown"] = ActionUIModel.shared.contentSizeLimits(windowUUID: "csl-unknown")
                for windowUUID in documents.keys {
                    actionUIAppCloseWindow(windowUUID)
                }
            }
            actionUIAppTerminate()
        }
        actionUIAppRun()

        let unbounded = Double.greatestFiniteMagnitude
        let fixed = try XCTUnwrap(measured["csl-fixed"] ?? nil)
        XCTAssertEqual(fixed.minSize, .init(width: 300, height: 200))
        XCTAssertEqual(fixed.maxSize, fixed.minSize, "a fixed frame: the minimum is the maximum, a fixed-size window")

        let flexible = try XCTUnwrap(measured["csl-flexible"] ?? nil)
        XCTAssertEqual(flexible.minSize, .init(width: 100, height: 50))
        XCTAssertEqual(flexible.maxSize, .init(width: 400, height: 300))

        let color = try XCTUnwrap(measured["csl-color"] ?? nil)
        XCTAssertEqual(color.maxSize, .init(width: unbounded, height: unbounded), "a Color fills any space")

        let text = try XCTUnwrap(measured["csl-text"] ?? nil)
        XCTAssertGreaterThan(text.maxSize.width, 0)
        XCTAssertLessThan(text.maxSize.width, 1000, "a Text is as wide as its text")
        XCTAssertLessThan(text.maxSize.height, 100)
        XCTAssertLessThanOrEqual(text.minSize.width, text.maxSize.width)
        XCTAssertGreaterThan(text.minSize.height, 0, "GTK does not compress a label to nothing, as SwiftUI's zero proposal does")

        let wide = try XCTUnwrap(measured["csl-wide"] ?? nil)
        XCTAssertEqual(wide.maxSize.width, unbounded, "a frame to maxWidth infinity")
        XCTAssertLessThan(wide.maxSize.height, 100, "and its height bounded by the text")

        XCTAssertEqual(measured["csl-unknown"], .some(nil), "an unknown window has none")

        // As on Apple, the minimum is never above the maximum, text that wraps included.
        for windowUUID in documents.keys {
            let limits = try XCTUnwrap(measured[windowUUID] ?? nil, windowUUID)
            XCTAssertLessThanOrEqual(limits.minSize.width, limits.maxSize.width, windowUUID)
            XCTAssertLessThanOrEqual(limits.minSize.height, limits.maxSize.height, windowUUID)
        }
    }

    func testAWindowOnlyInTheModelHasNone() throws {
        _ = try ActionUIModel.shared.loadDescription(from: Data(#"{"type": "Text", "id": 1}"#.utf8), format: "json", windowUUID: "csl-model-only")
        XCTAssertNil(ActionUIModel.shared.contentSizeLimits(windowUUID: "csl-model-only"),
                     "GTK measures a window on screen; this one is loaded but not shown")
    }
}
