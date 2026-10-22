// Views/HiddenRenderTests.swift
/*
 A hidden element hides whole, as on Web, Android and Linux: its background, border, overlay and
 shadow draw nothing, and its space stays reserved. Rendered with the SwiftUI renderer into a
 bitmap and checked by pixels.
*/

#if os(macOS)
import XCTest
import SwiftUI
import AppKit
@testable import ActionUI

@MainActor
final class HiddenRenderTests: XCTestCase {
    private var logger: XCTestLogger!

    override func setUp() async throws {
        try await super.setUp()
        logger = XCTestLogger(maxLevel: .warning)
        ActionUIModel.shared.logger = logger
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
    }

    override func tearDown() async throws {
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        logger = nil
        try await super.tearDown()
    }

    /// A 200 x 100 white window: a decorated 80 x 40 VStack (blue background, green border, red
    /// overlay Color, shadow), hidden or not, above a 20 x 20 black Color.
    private func render(hidden: Bool) throws -> NSBitmapImageRep {
        let document: [String: Any] = [
            "type": "VStack", "id": 1,
            "properties": ["spacing": 0, "background": "#FFFFFF", "frame": ["width": 200, "height": 100]],
            "children": [
                ["type": "VStack", "id": 2,
                 "properties": ["hidden": hidden, "background": "#0000FF", "border": ["color": "#00FF00", "width": 4],
                                "shadow": ["radius": 0, "x": 6, "y": 6, "color": "#FF00FF"],
                                "frame": ["width": 80, "height": 40]],
                 "overlay": ["type": "Color", "id": 3, "properties": ["color": "#FF0000", "frame": ["width": 10, "height": 10]]]],
                ["type": "Color", "id": 4, "properties": ["color": "#000000", "frame": ["width": 20, "height": 20]]],
            ],
        ]
        let model = ActionUIModel.shared
        ActionUIModel.resetForTesting()
        let windowUUID = UUID().uuidString
        let element = try model.loadDescription(from: document, windowUUID: windowUUID)
        let viewModel = try XCTUnwrap(model.windowModels[windowUUID]?.viewModels[element.id])
        let host = NSHostingView(rootView: ActionUIView(element: element, model: viewModel, windowUUID: windowUUID))
        host.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        return bitmap
    }

    /// How many pixels are close to the sRGB color.
    private func count(_ bitmap: NSBitmapImageRep, red: CGFloat, green: CGFloat, blue: CGFloat) -> Int {
        guard let target = NSColor(srgbRed: red, green: green, blue: blue, alpha: 1).usingColorSpace(bitmap.colorSpace) else { return -1 }
        var matches = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let pixel = bitmap.colorAt(x: x, y: y) else { continue }
                if abs(pixel.redComponent - target.redComponent) < 0.06, abs(pixel.greenComponent - target.greenComponent) < 0.06,
                   abs(pixel.blueComponent - target.blueComponent) < 0.06 {
                    matches += 1
                }
            }
        }
        return matches
    }

    /// The top row (in points) of the black Color, which sits below the decorated element.
    private func blackTop(_ bitmap: NSBitmapImageRep) -> Double? {
        let scale = Double(bitmap.pixelsWide) / 200
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                if let pixel = bitmap.colorAt(x: x, y: y), pixel.redComponent < 0.05, pixel.greenComponent < 0.05,
                   pixel.blueComponent < 0.05, pixel.alphaComponent > 0.9 {
                    return Double(y) / scale
                }
            }
        }
        return nil
    }

    func testAHiddenElementDrawsNoDecorationAndKeepsItsSpace() throws {
        let shown = try render(hidden: false)
        XCTAssertGreaterThan(count(shown, red: 0, green: 0, blue: 1), 0, "the background draws when shown")
        XCTAssertGreaterThan(count(shown, red: 0, green: 1, blue: 0), 0, "the border draws when shown")
        XCTAssertGreaterThan(count(shown, red: 1, green: 0, blue: 0), 0, "the overlay draws when shown")
        XCTAssertGreaterThan(count(shown, red: 1, green: 0, blue: 1), 0, "the shadow draws when shown")

        let hidden = try render(hidden: true)
        XCTAssertEqual(count(hidden, red: 0, green: 0, blue: 1), 0, "background")
        XCTAssertEqual(count(hidden, red: 0, green: 1, blue: 0), 0, "border")
        XCTAssertEqual(count(hidden, red: 1, green: 0, blue: 0), 0, "overlay")
        XCTAssertEqual(count(hidden, red: 1, green: 0, blue: 1), 0, "shadow")

        // The space stays: the Color below is where it was.
        let shownTop = try XCTUnwrap(blackTop(shown))
        let hiddenTop = try XCTUnwrap(blackTop(hidden))
        XCTAssertEqual(shownTop, hiddenTop, accuracy: 0.5)
    }
}
#endif
