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

    private func measure(_ fixture: URL) throws -> LayoutParityExpectation {
        let data = try Data(contentsOf: fixture)
        let document = try JSONSerialization.jsonObject(with: data)
        let (width, height) = try LayoutParityPixels.rootSize(of: document, fixture: fixture.lastPathComponent)

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
        let frames = LayoutParityPixels.frames(in: bitmap, width: width, leaves: LayoutParityPixels.leaves(of: document),
                                               fixture: fixture.lastPathComponent)
        return LayoutParityExpectation(size: [width, height], frames: frames)
    }
}
#endif
