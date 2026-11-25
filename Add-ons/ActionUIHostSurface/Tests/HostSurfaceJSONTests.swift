// Add-ons/ActionUIHostSurface/Tests/HostSurfaceJSONTests.swift
//
// The element inside real ActionUI documents, hosted by SwiftUI, driven through ActionUIModel like a
// host app: the event sequence for hidden, padding (whose first use rebuilds the SwiftUI view),
// opacity, a resize, element removal and window close. This is the self-test sequence the spikes ran.

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import XCTest
import SwiftUI
import ActionUI
@testable import ActionUIHostSurface

@MainActor
final class HostSurfaceJSONTests: XCTestCase {
    private var window: TestWindow!
    private var windowUUID = ""
    private let client = RecordingClient()
    private let model = ActionUIModel.shared

    private let document = """
        { "type": "VStack", "id": 1, "children": [
            { "type": "Text", "id": 2, "properties": { "text": "above" } },
            { "type": "HostSurface", "id": 5, "properties": {
                "surfaceName": "document", "idealWidth": 200, "idealHeight": 120 } }
        ] }
        """

    override func setUp() async throws {
        HostSurfaceView.ignoresWindowOcclusionForTesting = true
        HostSurfaceRegistry.shared.resetForTesting()
        ActionUIHostSurface.register()
        ActionUIHostSurface.setDelegate(client, forSurfaceName: "document")
        windowUUID = UUID().uuidString
        let root = FileLoadableView(data: Data(document.utf8), sourceName: "HostSurfaceJSONTests.json",
                                    windowUUID: windowUUID, isContentView: true,
                                    logger: ConsoleLogger(maxLevel: .warning))
        window = TestHost.makeWindow(width: 400, height: 300)
        #if os(macOS)
        window.contentView = NSHostingView(rootView: root.frame(width: 400, height: 300))
        #else
        window.rootViewController = UIHostingController(rootView: root.frame(width: 400, height: 300))
        #endif
        settle()
    }

    override func tearDown() async throws {
        ActionUIHostSurface.setDelegate(nil, forSurfaceName: "document")
        HostSurfaceRegistry.shared.resetForTesting()
        TestHost.close(window)
        window = nil
        model.removeWindow(windowUUID)
        TestHost.pump()
    }

    /// Lets SwiftUI apply pending changes and lay out, then the add-on decide pending teardowns.
    private func settle(_ seconds: TimeInterval = 0.3) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            #if os(macOS)
            window.contentView?.layoutSubtreeIfNeeded()
            #else
            window.layoutIfNeeded()
            #endif
            TestHost.pump(0.02)
        }
    }

    private func set(_ property: String, _ value: Any) {
        model.setElementProperty(windowUUID: windowUUID, viewID: 5, propertyName: property, value: value)
        settle()
    }

    func testTheDocumentSequence() throws {
        XCTAssertEqual(client.events, [.created], "the surface appears with the document")
        let surfaceID = try XCTUnwrap(client.received.first?.surfaceID)
        let created = try XCTUnwrap(client.received.first)
        XCTAssertGreaterThan(created.widthPixels, 0)

        set("hidden", true)
        set("hidden", false)
        XCTAssertEqual(client.events, [.created, .suspended, .resumed], "hiding keeps the surface")

        client.clear()
        let containersBefore = HostSurfaceContainer.madeCount
        set("padding", 20)   // the first padding changes the SwiftUI view's identity
        XCTAssertGreaterThan(HostSurfaceContainer.madeCount, containersBefore,
                             "SwiftUI rebuilt the element, so the test covers the container move")
        XCTAssertFalse(client.events.contains(.destroyed), "a SwiftUI rebuild keeps the surface: \(client.received)")
        XCTAssertFalse(client.events.contains(.created), "\(client.received)")
        set("opacity", 0.5)
        set("padding", 0)
        XCTAssertFalse(client.events.contains(.destroyed), "\(client.received)")
        XCTAssertTrue(client.received.allSatisfy { $0.surfaceID == surfaceID })

        let size = try XCTUnwrap(model.getElementState(windowUUID: windowUUID, viewID: 5, key: "size") as? [Double])
        XCTAssertEqual(size.count, 2)
        XCTAssertGreaterThan(size[0], 0)

        client.clear()
        try model.removeElement(windowUUID: windowUUID, viewID: 5)
        settle(0.8)
        XCTAssertEqual(client.events.last, .destroyed, "removing the element destroys the surface: \(client.received)")
        XCTAssertEqual(client.events.filter { $0 == .destroyed }.count, 1)
        XCTAssertEqual(HostSurfaceRegistry.shared.liveSurfaceCount, 0)
    }

    #if os(macOS)
    func testClosingTheWindowDestroysTheSurface() {
        XCTAssertEqual(client.events, [.created])
        window.close()
        XCTAssertEqual(client.events, [.created, .destroyed])
        settle()
        XCTAssertEqual(client.events, [.created, .destroyed])
    }
    #endif

    /// Content the trust policy does not let show a host surface gets the placeholder: its client hears nothing.
    func testASurfaceThePolicyRefusesIsNeverAnnounced() throws {
        let refused = RecordingClient()
        ActionUIHostSurface.setDelegate(refused, forSurfaceName: "refused")
        let saved = model.trustPolicy
        model.trustPolicy = RefusingHostSurface(name: "refused")
        let otherUUID = UUID().uuidString
        let other = TestHost.makeWindow(width: 300, height: 200)
        defer {
            ActionUIHostSurface.setDelegate(nil, forSurfaceName: "refused")
            TestHost.close(other)
            model.removeWindow(otherUUID)
            model.trustPolicy = saved
        }
        let json = """
            { "type": "HostSurface", "id": 3, "properties": { "surfaceName": "refused" } }
            """
        let root = FileLoadableView(data: Data(json.utf8), sourceName: "HostSurfaceRefused.json",
                                    windowUUID: otherUUID, isContentView: true,
                                    logger: ConsoleLogger(maxLevel: .warning))
        #if os(macOS)
        other.contentView = NSHostingView(rootView: root.frame(width: 300, height: 200))
        #else
        other.rootViewController = UIHostingController(rootView: root.frame(width: 300, height: 200))
        #endif
        settle()
        XCTAssertEqual(refused.events, [], "the refused element's client is never told of it")
        XCTAssertEqual(HostSurfaceRegistry.shared.liveSurfaceCount, 1, "only the first window's surface is live")
        XCTAssertEqual(client.events, [.created], "the allowed surface is unaffected")
    }

    func testAClientBoundAfterLoadGetsTheLiveSurface() {
        let late = RecordingClient()
        ActionUIHostSurface.setDelegate(late, forSurfaceName: "document")
        XCTAssertEqual(client.events, [.created, .destroyed], "the replaced client is told first")
        XCTAssertEqual(late.events, [.created])
        ActionUIHostSurface.setDelegate(client, forSurfaceName: "document")
    }
}

/// A trust policy that refuses one surface name and keeps ActionUI's decisions otherwise.
private struct RefusingHostSurface: ActionUITrustPolicy {
    let name: String

    func allows(_ capability: ActionUICapability, for origin: JSONContentOrigin) -> Bool {
        capability == .hostSurface(name) ? false : DefaultTrustPolicy.allowsByDefault(capability, for: origin)
    }
}
