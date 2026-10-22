// Views/LayoutParityTests.swift
/*
 The Apple side of the layout parity battery (the LayoutParity folder at the repository root).
 Each fixture is an ActionUI document whose root has a fixed frame and whose leaves are Colors,
 each its own color. This test renders a fixture with the SwiftUI renderer, draws it into a bitmap
 and reads each Color's frame from its pixels, so it measures SwiftUI's own layout with no hook in
 the renderer.

 - Normally it checks the measured frames against LayoutParity/expected/<fixture>.json.
 - With ACTIONUI_LAYOUT_RECORD=1 in the environment it writes those files instead (the
   reference every other renderer's parity test checks against).
*/

#if os(macOS)
import XCTest
import SwiftUI
import AppKit
@testable import ActionUI

/// One fixture's recorded layout: the root's size and each Color's frame, [x, y, width, height]
/// in points from the root's top leading corner, keyed by element id.
struct LayoutParityExpectation: Codable, Equatable {
    var size: [Double]
    var frames: [String: [Double]]
}

@MainActor
final class LayoutParityTests: XCTestCase {
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

    /// The LayoutParity folder: this file is ActionUITests/Views/LayoutParityTests.swift.
    private static let folder = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("LayoutParity")

    /// Frames may differ by this much: SwiftUI places at fractions of a point, the bitmap has two
    /// pixels per point, and GTK places whole pixels.
    static let tolerance = 1.0

    func testTheSwiftUIRendererMatchesTheRecordedFrames() throws {
        let record = ProcessInfo.processInfo.environment["ACTIONUI_LAYOUT_RECORD"] == "1"
        let fixtures = try FileManager.default
            .contentsOfDirectory(at: Self.folder.appendingPathComponent("fixtures"), includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        XCTAssertFalse(fixtures.isEmpty, "no fixtures in \(Self.folder.path)/fixtures")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        for fixture in fixtures {
            let name = fixture.deletingPathExtension().lastPathComponent
            let measured = try measure(fixture)
            let expectedURL = Self.folder.appendingPathComponent("expected").appendingPathComponent(name + ".json")
            if record {
                try (encoder.encode(measured) + Data("\n".utf8)).write(to: expectedURL)
                continue
            }
            let expected = try JSONDecoder().decode(LayoutParityExpectation.self, from: Data(contentsOf: expectedURL))
            Self.compare(fixture: name, expected: expected, measured: measured)
        }
    }

    /// Reports each frame that differs by more than the tolerance.
    static func compare(fixture: String, expected: LayoutParityExpectation, measured: LayoutParityExpectation,
                        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(Set(measured.frames.keys), Set(expected.frames.keys), "\(fixture): the measured elements", file: file, line: line)
        for (id, frame) in expected.frames.sorted(by: { $0.key < $1.key }) {
            guard let actual = measured.frames[id] else { continue }
            let differs = zip(frame, actual).contains { abs($0 - $1) > tolerance }
            if differs {
                XCTFail("\(fixture): element \(id) is \(actual), SwiftUI's is \(frame)", file: file, line: line)
            }
        }
    }

    // MARK: Measuring

    private struct Leaf {
        let id: Int
        /// sRGB components 0...1.
        let red: Double, green: Double, blue: Double
    }

    /// The Colors of a document (id and "#RRGGBB" color) and its root's frame size.
    private func leaves(of document: Any) -> [Leaf] {
        var result: [Leaf] = []
        func walk(_ value: Any) {
            if let object = value as? [String: Any] {
                if object["type"] as? String == "Color", let id = object["id"] as? Int,
                   let hex = (object["properties"] as? [String: Any])?["color"] as? String,
                   hex.count == 7, hex.hasPrefix("#"), let rgb = Int(hex.dropFirst(), radix: 16) {
                    result.append(Leaf(id: id, red: Double((rgb >> 16) & 0xFF) / 255,
                                       green: Double((rgb >> 8) & 0xFF) / 255, blue: Double(rgb & 0xFF) / 255))
                }
                object.values.forEach(walk)
            } else if let array = value as? [Any] {
                array.forEach(walk)
            }
        }
        walk(document)
        return result
    }

    private func measure(_ fixture: URL) throws -> LayoutParityExpectation {
        let data = try Data(contentsOf: fixture)
        let document = try JSONSerialization.jsonObject(with: data)
        let frame = try XCTUnwrap(((document as? [String: Any])?["properties"] as? [String: Any])?["frame"] as? [String: Any],
                                  "\(fixture.lastPathComponent): the root needs a fixed frame")
        let width = try XCTUnwrap(frame["width"] as? Double ?? (frame["width"] as? Int).map(Double.init))
        let height = try XCTUnwrap(frame["height"] as? Double ?? (frame["height"] as? Int).map(Double.init))
        let leaves = leaves(of: document)

        ActionUIModel.resetForTesting()
        let windowUUID = UUID().uuidString
        let model = ActionUIModel.shared
        let element = try model.loadDescription(from: data, format: "json", windowUUID: windowUUID)
        let viewModel = try XCTUnwrap(model.windowModels[windowUUID]?.viewModels[element.id])
        let host = NSHostingView(rootView: ActionUIView(element: element, model: viewModel, windowUUID: windowUUID))
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)

        // Each leaf's color as the bitmap stores it (its color space may be Display P3, not sRGB).
        let targets: [(id: Int, components: [Double])] = leaves.compactMap { leaf in
            let color = NSColor(srgbRed: leaf.red, green: leaf.green, blue: leaf.blue, alpha: 1)
            guard let converted = color.usingColorSpace(bitmap.colorSpace) else { return nil }
            return (leaf.id, [converted.redComponent, converted.greenComponent, converted.blueComponent])
        }
        XCTAssertEqual(targets.count, leaves.count, "\(fixture.lastPathComponent): a color could not be converted")

        let pixelsWide = bitmap.pixelsWide
        let pixelsHigh = bitmap.pixelsHigh
        let scale = Double(pixelsWide) / width
        var bounds: [Int: (minX: Int, minY: Int, maxX: Int, maxY: Int)] = [:]
        for y in 0..<pixelsHigh {
            for x in 0..<pixelsWide {
                guard let pixel = bitmap.colorAt(x: x, y: y), pixel.alphaComponent > 0.9 else { continue }
                let components = [pixel.redComponent, pixel.greenComponent, pixel.blueComponent]
                // Blended edge pixels match no color closely and are left out.
                guard let match = targets.first(where: { target in
                    zip(target.components, components).allSatisfy { abs($0 - $1) < 0.06 }
                }) else { continue }
                let box = bounds[match.id] ?? (x, y, x, y)
                bounds[match.id] = (min(box.minX, x), min(box.minY, y), max(box.maxX, x), max(box.maxY, y))
            }
        }
        var frames: [String: [Double]] = [:]
        for (id, box) in bounds {
            let half = { (value: Double) in (value * 2).rounded() / 2 }
            frames[String(id)] = [half(Double(box.minX) / scale), half(Double(box.minY) / scale),
                                  half(Double(box.maxX - box.minX + 1) / scale), half(Double(box.maxY - box.minY + 1) / scale)]
        }
        return LayoutParityExpectation(size: [width, height], frames: frames)
    }
}
#endif
