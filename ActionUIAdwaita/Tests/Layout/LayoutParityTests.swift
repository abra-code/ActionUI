// Tests/Layout/LayoutParityTests.swift
/*
 The GTK side of the layout parity battery (the LayoutParity folder at the repository root): every
 fixture is laid out by the GTK renderer at its root's size, and each Color's frame is checked
 against LayoutParity/expected/<fixture>.json, which the Apple side recorded from SwiftUI's own
 layout (ActionUITests/Views/LayoutParityTests.swift).

 Only frames are compared, not pixels.
*/

import XCTest
import CAdwaita
@testable import ActionUI

/// One fixture's recorded layout (the Apple side's LayoutParityExpectation).
private struct Expectation: Codable {
    var size: [Double]
    var frames: [String: [Double]]
}

@MainActor
final class LayoutParityTests: XCTestCase {
    /// Fixtures GTK does not match yet, with the reason. A fixture that starts to match fails the
    /// test until it is removed here.
    private static let knownDifferences: [String: String] = [
        "hstack-ideal-exact-width": idealReason,
        "hstack-ideal-slightly-wider": idealReason,
        "ignoressafearea-child-under-inset": ignoredSafeAreaReason,
        "safearea-fixed-filling-bar": insetExpansionReason,
        "safearea-unframed-bar": insetExpansionReason,
    ]

    /// A safe area inset view that expands makes SwiftUI's view of a fixed size expand with it: a
    /// bar that fills across its edge widens the view to the width offered, and one that fills
    /// along it takes the extra length. GTK's box takes its expansion from a fixed frame alone
    /// (ModifierBox.setExpand), and the view keeps its own length along the edge.
    private static let insetExpansionReason = "a safe area inset view that expands widens SwiftUI's view of a fixed size (across its edge to the width offered, along it taking the extra length); GTK's box takes its expansion from a fixed frame alone (ModifierBox.setExpand) and the view keeps its own length along the edge"

    /// Offered its ideal width or a little more, SwiftUI's HStack can leave a child short. GTK
    /// gives a stack whose children all have a largest size no more than their sum, where
    /// SwiftUI's parent usually proposes more, so the stack gives each child that size then
    /// (StackSolver.mainSizes).
    private static let ignoredSafeAreaReason = "a view inside an element's content that ignores the safe area reaches, in SwiftUI, past its parents into the room the element's safe area inset view takes; GTK lets only the element's own background and overlay views reach there"
    private static let idealReason = "offered its ideal width or a little more, SwiftUI's HStack can leave a child short; GTK gives a stack of bounded children no more than its ideal size where SwiftUI's parent usually offers more, so it gives each child its own size then (StackSolver.mainSizes)"

    /// Frames may differ by this much: SwiftUI places at fractions of a point, GTK whole pixels.
    private static let tolerance = 1.0

    /// The LayoutParity folder: this file is ActionUIAdwaita/Tests/Layout/LayoutParityTests.swift.
    private static let folder = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("LayoutParity")

    private var windows: [AdwaitaWindow] = []

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
        ActionUIRegistry.shared.loadBuiltIns()
    }

    override func tearDown() async throws {
        windows = []
        AdwaitaTestHost.drainMainLoop()
        ActionUIRegistry.shared.loadBuiltIns()
    }

    func testTheGTKRendererMatchesSwiftUIsFrames() throws {
        let fixtures = try FileManager.default
            .contentsOfDirectory(atPath: Self.folder.appendingPathComponent("fixtures").path)
            .filter { $0.hasSuffix(".json") }
            .sorted()
        XCTAssertFalse(fixtures.isEmpty, "no fixtures in \(Self.folder.path)/fixtures")
        for file in fixtures {
            let name = String(file.dropLast(".json".count))
            let expected = try JSONDecoder().decode(Expectation.self, from: Data(contentsOf:
                Self.folder.appendingPathComponent("expected").appendingPathComponent(file)))
            let differences = try differences(name, expected)
            if let reason = Self.knownDifferences[name] {
                if differences.isEmpty {
                    XCTFail("\(name) now matches SwiftUI: remove it from knownDifferences")
                } else {
                    print("[layout parity] \(name): known difference (\(reason)): \(differences.joined(separator: "; "))")
                }
            } else {
                for difference in differences {
                    XCTFail("\(name): \(difference)")
                }
            }
        }
    }

    /// Lays the fixture out at its size and lists each Color frame that differs from SwiftUI's.
    private func differences(_ name: String, _ expected: Expectation) throws -> [String] {
        let windowUUID = "layout-parity-\(name)"
        defer { ActionUIModel.shared.windowModels[windowUUID] = nil }
        let data = try Data(contentsOf: Self.folder.appendingPathComponent("fixtures").appendingPathComponent(name + ".json"))
        _ = try ActionUIModel.shared.loadDescription(from: data, format: "json", windowUUID: windowUUID)
        let window = AdwaitaWindow(windowModel: try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID]))
        windows.append(window)
        let root = try XCTUnwrap(window.root)
        gtk_widget_allocate(root.outerWidget, Int32(expected.size[0]), Int32(expected.size[1]), -1, nil)

        var result: [String] = []
        for (id, frame) in expected.frames.sorted(by: { $0.key < $1.key }) {
            guard let elementID = Int(id), let node = Self.node(elementID, in: root) else {
                result.append("element \(id) was not rendered")
                continue
            }
            var bounds = graphene_rect_t()
            _ = gtk_widget_compute_bounds(node.widget, root.outerWidget, &bounds)
            let actual = [Double(bounds.origin.x), Double(bounds.origin.y), Double(bounds.size.width), Double(bounds.size.height)]
            if zip(frame, actual).contains(where: { abs($0 - $1) > Self.tolerance }) {
                result.append("element \(id) is \(actual), SwiftUI's is \(frame)")
            }
        }
        return result
    }

    private static func node(_ id: Int, in node: RenderNode) -> RenderNode? {
        if node.element.id == id { return node }
        // With the background, overlay and safe area inset views, which are not child nodes.
        for child in Array(node.childNodes.values) + (node.decorations?.nodes ?? []) {
            if let found = self.node(id, in: child) { return found }
        }
        return nil
    }
}
