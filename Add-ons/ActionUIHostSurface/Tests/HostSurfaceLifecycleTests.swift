// Add-ons/ActionUIHostSurface/Tests/HostSurfaceLifecycleTests.swift
//
// The binding and lifecycle rules of the C interface (include/ActionUIHostSurface.h), driven with the
// add-on's real surface views and containers in windows that are never shown: replay, replacement and
// removal of a client, a delegate change inside a callback, hidden and zero-size suspension, resize,
// the container move a SwiftUI rebuild makes, teardown, window close, and calls on dead surfaces.

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import XCTest
import ActionUI
@testable import ActionUIHostSurface

@MainActor
final class HostSurfaceLifecycleTests: XCTestCase {
    private var window: TestWindow!
    private var windowUUID = ""

    override func setUp() async throws {
        HostSurfaceView.ignoresWindowOcclusionForTesting = true
        HostSurfaceRegistry.shared.resetForTesting()
        window = TestHost.makeWindow()
        windowUUID = UUID().uuidString
    }

    override func tearDown() async throws {
        HostSurfaceRegistry.shared.resetForTesting()
        TestHost.close(window)
        window = nil
        TestHost.pump()
        XCTAssertEqual(HostSurfaceRegistry.shared.liveSurfaceCount, 0, "no surface may outlive a test")
    }

    private func element(_ viewID: Int = 5, name: String = "viewport", hidden: Bool = false)
        -> HostSurfaceContainer {
        TestHost.makeContainer(windowUUID: windowUUID, viewID: viewID,
                               properties: HostSurfaceProperties(surfaceName: name, hidden: hidden))
    }

    // MARK: binding

    func testCreatedWhenWindowSizeAndClientAreThere() {
        let client = RecordingClient()
        ActionUIHostSurface.setDelegate(client, forSurfaceName: "viewport")
        let container = element()
        XCTAssertEqual(client.events, [], "no window yet")
        TestHost.place(container, in: window, width: 0, height: 0)
        XCTAssertEqual(client.events, [], "no pixels yet")
        TestHost.resize(container, width: 200, height: 100)
        let scale = TestHost.scale(of: container)
        XCTAssertEqual(client.events, [.created])
        XCTAssertEqual(client.received.first?.widthPixels, Int((200 * scale).rounded()))
        XCTAssertEqual(client.received.first?.heightPixels, Int((100 * scale).rounded()))
        XCTAssertEqual(client.received.first?.viewID, 5)
        XCTAssertNotEqual(client.received.first?.surfaceID, 0)
    }

    func testClientBoundAfterTheSurfaceAppearedGetsCreatedAtOnce() {
        let container = element()
        TestHost.place(container, in: window)
        let client = RecordingClient()
        ActionUIHostSurface.setDelegate(client, forSurfaceName: "viewport")
        XCTAssertEqual(client.events, [.created], "binding replays live surfaces")
    }

    func testOtherNamesAreNotAnnounced() {
        let client = RecordingClient()
        ActionUIHostSurface.setDelegate(client, forSurfaceName: "other")
        TestHost.place(element(), in: window)
        XCTAssertEqual(client.events, [])
    }

    func testReplacingTheClientDestroysForTheOldOneFirstWithANewSurfaceID() {
        let first = RecordingClient()
        let second = RecordingClient()
        var order: [String] = []
        first.onEvent = { _, event in order.append("first \(event)") }
        second.onEvent = { _, event in order.append("second \(event)") }
        ActionUIHostSurface.setDelegate(first, forSurfaceName: "viewport")
        TestHost.place(element(), in: window)
        ActionUIHostSurface.setDelegate(second, forSurfaceName: "viewport")
        XCTAssertEqual(order, ["first created", "first destroyed", "second created"])
        let firstID = first.received[0].surfaceID
        XCTAssertEqual(first.received[1].surfaceID, firstID, "destroyed names the surface that was created")
        XCTAssertNotEqual(second.received[0].surfaceID, firstID, "every created has a new surfaceID")
    }

    func testRemovingTheClientDestroysAndBindingAgainAnnouncesAgain() {
        let client = RecordingClient()
        ActionUIHostSurface.setDelegate(client, forSurfaceName: "viewport")
        TestHost.place(element(), in: window)
        ActionUIHostSurface.setDelegate(nil, forSurfaceName: "viewport")
        XCTAssertEqual(client.events, [.created, .destroyed])
        XCTAssertEqual(HostSurfaceRegistry.shared.liveSurfaceCount, 0)
        ActionUIHostSurface.setDelegate(client, forSurfaceName: "viewport")
        XCTAssertEqual(client.events, [.created, .destroyed, .created])
    }

    func testDelegateChangeInsideACallbackWaitsForTheCallbackToReturn() {
        let first = RecordingClient()
        let second = RecordingClient()
        var insideCreated = false
        var eventsSeenInside: [HostSurfaceEvent] = []
        first.onEvent = { _, event in
            guard event == .created else {
                return
            }
            insideCreated = true
            ActionUIHostSurface.setDelegate(second, forSurfaceName: "viewport")
            eventsSeenInside = first.events + second.events
            insideCreated = false
        }
        second.onEvent = { _, _ in
            XCTAssertFalse(insideCreated, "the new client must not be called while the old one's callback runs")
        }
        ActionUIHostSurface.setDelegate(first, forSurfaceName: "viewport")
        TestHost.place(element(), in: window)
        XCTAssertEqual(eventsSeenInside, [.created], "nothing ran reentrantly")
        XCTAssertEqual(first.events, [.created, .destroyed])
        XCTAssertEqual(second.events, [.created])
    }

    func testDelegateChangeInsideDestroyedRunsAfterTheReplacementInOrder() {
        let first = RecordingClient()
        let second = RecordingClient()
        first.onEvent = { _, event in
            if event == .destroyed {
                ActionUIHostSurface.setDelegate(nil, forSurfaceName: "viewport")
            }
        }
        ActionUIHostSurface.setDelegate(first, forSurfaceName: "viewport")
        TestHost.place(element(), in: window)
        ActionUIHostSurface.setDelegate(second, forSurfaceName: "viewport")
        XCTAssertEqual(first.events, [.created, .destroyed], "one destroyed per created")
        XCTAssertEqual(second.events, [.created, .destroyed], "the later call (nil) wins")
        XCTAssertNil(HostSurfaceRegistry.shared.binding(for: "viewport"))
        XCTAssertEqual(HostSurfaceRegistry.shared.liveSurfaceCount, 0)
    }

    #if os(macOS)
    func testDelegateChangeInsideDestroyedOfAClosingWindowAnnouncesNothing() {
        let first = RecordingClient()
        let second = RecordingClient()
        first.onEvent = { _, event in
            if event == .destroyed {
                ActionUIHostSurface.setDelegate(second, forSurfaceName: "viewport")
            }
        }
        ActionUIHostSurface.setDelegate(first, forSurfaceName: "viewport")
        TestHost.place(element(), in: window)
        window.close()
        XCTAssertEqual(first.events, [.created, .destroyed], "one destroyed per created")
        XCTAssertEqual(second.events, [], "a torn-down view is not announced again")
        XCTAssertEqual(HostSurfaceRegistry.shared.liveSurfaceCount, 0)
    }
    #endif

    // MARK: suspension and geometry

    func testHiddenSuspendsAndResumesWithoutDestroying() {
        let client = RecordingClient()
        ActionUIHostSurface.setDelegate(client, forSurfaceName: "viewport")
        let container = element()
        TestHost.place(container, in: window)
        container.surface.update(HostSurfaceProperties(surfaceName: "viewport", hidden: true))
        XCTAssertTrue(container.surface.isHidden)
        container.surface.update(HostSurfaceProperties(surfaceName: "viewport", hidden: false))
        XCTAssertEqual(client.events, [.created, .suspended, .resumed])
        XCTAssertEqual(Set(client.received.map(\.surfaceID)).count, 1)
    }

    func testHiddenAtLoadIsCreatedThenSuspended() {
        let client = RecordingClient()
        ActionUIHostSurface.setDelegate(client, forSurfaceName: "viewport")
        TestHost.place(element(hidden: true), in: window)
        XCTAssertEqual(client.events, [.created, .suspended])
    }

    func testResizeSendsChangedAndZeroSizeSuspends() {
        let client = RecordingClient()
        ActionUIHostSurface.setDelegate(client, forSurfaceName: "viewport")
        let container = element()
        TestHost.place(container, in: window)
        TestHost.resize(container, width: 300, height: 150)
        TestHost.resize(container, width: 300, height: 150)
        TestHost.resize(container, width: 0, height: 150)
        TestHost.resize(container, width: 120, height: 150)
        XCTAssertEqual(client.events, [.created, .changed, .suspended, .changed, .resumed])
        let scale = TestHost.scale(of: container)
        XCTAssertEqual(client.received[1].widthPixels, Int((300 * scale).rounded()))
        XCTAssertEqual(client.received[3].widthPixels, Int((120 * scale).rounded()))
        XCTAssertTrue(client.received.allSatisfy { $0.widthPixels > 0 && $0.heightPixels > 0 },
                      "no event carries a zero pixel size")
    }

    // MARK: containers and teardown

    func testARebuildMovesTheSurfaceIntoTheNewContainerWithoutEvents() {
        let client = RecordingClient()
        ActionUIHostSurface.setDelegate(client, forSurfaceName: "viewport")
        let old = element()
        TestHost.place(old, in: window)
        // SwiftUI makes the new container first, then dismantles the old one.
        let new = element()
        XCTAssertTrue(new.surface === old.surface, "one surface view per element")
        TestHost.place(new, in: window)
        old.dismantle()
        old.removeFromSuperview()
        TestHost.pump()
        XCTAssertEqual(client.events, [.created])
        XCTAssertTrue(new.surface.superview === new)
    }

    func testADismantledContainerSuspendsAtOnceAndDestroysOnTheNextTurn() {
        let client = RecordingClient()
        ActionUIHostSurface.setDelegate(client, forSurfaceName: "viewport")
        let container = element()
        TestHost.place(container, in: window)
        container.dismantle()
        XCTAssertEqual(client.events, [.created, .suspended], "suspended at once, so a render thread stops")
        TestHost.pump()
        XCTAssertEqual(client.events, [.created, .suspended, .destroyed])
        XCTAssertEqual(HostSurfaceRegistry.shared.ownedSurfaceCount, 0)
        // The element's next container gets a new surface view.
        let next = element()
        XCTAssertFalse(next.surface === container.surface)
    }

    func testOutOfTheWindowInALiveContainerSuspendsAndComesBack() {
        let client = RecordingClient()
        ActionUIHostSurface.setDelegate(client, forSurfaceName: "viewport")
        let container = element()
        TestHost.place(container, in: window)
        container.removeFromSuperview()
        XCTAssertEqual(client.events, [.created], "the decision waits one turn")
        TestHost.pump()
        XCTAssertEqual(client.events, [.created, .suspended], "a live container keeps the surface")
        TestHost.place(container, in: window)
        TestHost.pump()
        XCTAssertEqual(client.events, [.created, .suspended, .resumed])
    }

    #if os(macOS)
    func testClosingTheWindowDestroysAtOnce() {
        let client = RecordingClient()
        ActionUIHostSurface.setDelegate(client, forSurfaceName: "viewport")
        TestHost.place(element(), in: window)
        window.close()
        XCTAssertEqual(client.events, [.created, .destroyed], "closing a window does not detach its views")
        TestHost.pump()
        XCTAssertEqual(client.events, [.created, .destroyed], "a torn-down view is not announced again")
    }
    #endif

    // MARK: frames and calls from other threads

    func testCallsOnADeadSurfaceAreIgnored() {
        let client = RecordingClient()
        ActionUIHostSurface.setDelegate(client, forSurfaceName: "viewport")
        TestHost.place(element(), in: window)
        let deadID = client.received[0].surfaceID
        ActionUIHostSurface.setDelegate(nil, forSurfaceName: "viewport")
        actionUIHostSurfaceRequestFrame(deadID)
        actionUIHostSurfaceSetContinuous(deadID, true)
        actionUIHostSurfaceRequestFrame(9_999_999)
        TestHost.pump()
        XCTAssertEqual(client.frames, [])
        // Display links do not tick for windows that are never on screen, so the frames check above
        // cannot fail on its own: check that the dead surfaceID reaches no view, and that the view's
        // next announcement is a new surface.
        XCTAssertNil(HostSurfaceRegistry.shared.liveSurface(deadID))
        ActionUIHostSurface.setDelegate(client, forSurfaceName: "viewport")
        let newID = client.received.last?.surfaceID ?? 0
        XCTAssertNotEqual(newID, deadID)
        XCTAssertNotNil(HostSurfaceRegistry.shared.liveSurface(newID))
    }

    func testRequestFrameFromAnotherThreadDoesNotWait() {
        let client = RecordingClient()
        ActionUIHostSurface.setDelegate(client, forSurfaceName: "viewport")
        TestHost.place(element(), in: window)
        let surfaceID = client.received[0].surfaceID
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            actionUIHostSurfaceRequestFrame(surfaceID)
            actionUIHostSurfaceSetContinuous(surfaceID, false)
            done.signal()
        }
        // The main thread blocks here without running its loop, so a call that waited for the main
        // thread would not return before the timeout.
        XCTAssertEqual(done.wait(timeout: .now() + 2), .success)
        TestHost.pump()
    }

    // MARK: the C interface

    func testCDelegateGetsTheMetalLayerAndTheElement() {
        let client = RecordingCClient()
        var delegate = client.delegate
        XCTAssertTrue(actionUIHostSurfaceSetDelegate("viewport", &delegate, client.userData))
        TestHost.place(element(7), in: window)
        XCTAssertEqual(client.events, [Int32(AUIHostSurfaceCreated.rawValue)])
        let entry = client.entries[0]
        XCTAssertEqual(entry.kind, Int32(AUIHostSurfaceMetalLayer.rawValue))
        XCTAssertTrue(entry.hasHandle)
        XCTAssertEqual(entry.windowUUID, windowUUID)
        XCTAssertEqual(entry.viewID, 7)
        XCTAssertTrue(actionUIHostSurfaceSetDelegate("viewport", nil, nil))
        XCTAssertEqual(client.events, [Int32(AUIHostSurfaceCreated.rawValue), Int32(AUIHostSurfaceDestroyed.rawValue)])
    }

    func testSetDelegateRejectsBadArguments() {
        var delegate = RecordingCClient().delegate
        XCTAssertFalse(actionUIHostSurfaceSetDelegate(nil, &delegate, nil))
        XCTAssertFalse(actionUIHostSurfaceSetDelegate("", &delegate, nil))
        delegate.structSize = 2
        XCTAssertFalse(actionUIHostSurfaceSetDelegate("viewport", &delegate, nil), "structSize too small")
        let offMain = expectation(description: "off the main thread")
        DispatchQueue.global().async {
            var delegate = AUIHostSurfaceDelegate()
            delegate.structSize = UInt32(MemoryLayout<AUIHostSurfaceDelegate>.size)
            XCTAssertFalse(actionUIHostSurfaceSetDelegate("viewport", &delegate, nil))
            offMain.fulfill()
        }
        wait(for: [offMain], timeout: 2)
    }

    func testAnOlderShorterDelegateStructGetsNullForTheRest() throws {
        var delegate = RecordingCClient().delegate
        delegate.frame = { _, _, _, _, _ in }
        delegate.render = { _, _, _, _ in }
        delegate.structSize = UInt32(MemoryLayout<AUIHostSurfaceDelegate>.offset(of: \.input)!)
        let copy = try XCTUnwrap(withUnsafePointer(to: &delegate) { copyDelegate($0) })
        XCTAssertNotNil(copy.surface)
        XCTAssertNotNil(copy.frame)
        XCTAssertNil(copy.input)
        XCTAssertNil(copy.render, "a field past the client's structSize is not read")
        XCTAssertEqual(Int(copy.structSize), MemoryLayout<AUIHostSurfaceDelegate>.size)
    }

    func testAStructSizeEndingInsideACallbackStopsBeforeIt() throws {
        var delegate = RecordingCClient().delegate
        delegate.frame = { _, _, _, _, _ in }
        let frameOffset = MemoryLayout<AUIHostSurfaceDelegate>.offset(of: \.frame)!
        delegate.structSize = UInt32(frameOffset + 4)
        let copy = try XCTUnwrap(withUnsafePointer(to: &delegate) { copyDelegate($0) })
        XCTAssertNotNil(copy.surface)
        XCTAssertNil(copy.frame, "half a pointer is not copied")
    }

    func testAReusedIDWithAnotherSurfaceNameGetsANewView() {
        let client = RecordingClient()
        ActionUIHostSurface.setDelegate(client, forSurfaceName: "viewport")
        let old = element(5, name: "viewport")
        TestHost.place(old, in: window)
        // A new document in the same window reuses id 5 for another surface, and SwiftUI makes the new
        // container before it dismantles the old one.
        let new = element(5, name: "other")
        XCTAssertFalse(new.surface === old.surface)
        XCTAssertEqual(new.surface.surfaceName, "other")
        TestHost.place(new, in: window)
        old.dismantle()
        TestHost.pump()
        XCTAssertEqual(client.events, [.created, .suspended, .destroyed], "the old surface ends with its container")
        XCTAssertFalse(new.surface.isTornDown, "the old view's teardown leaves the new one alone")
        XCTAssertEqual(HostSurfaceRegistry.shared.ownedSurfaceCount, 1)
    }

    func testARebindReachesASupersededViewBeforeItsContainerIsDismantled() {
        let client = RecordingClient()
        ActionUIHostSurface.setDelegate(client, forSurfaceName: "viewport")
        let old = element(5, name: "viewport")
        TestHost.place(old, in: window)
        let new = element(5, name: "other")
        TestHost.place(new, in: window)
        // The old container is still live: unbinding must reach its surface now, not at its teardown,
        // because a C client may free its userData once SetDelegate(NULL) returns.
        ActionUIHostSurface.setDelegate(nil, forSurfaceName: "viewport")
        XCTAssertEqual(client.events, [.created, .destroyed])
        old.dismantle()
        TestHost.pump()
        XCTAssertEqual(client.events, [.created, .destroyed], "nothing reaches the unbound client")
        XCTAssertEqual(HostSurfaceRegistry.shared.liveSurfaceCount, 0)
    }
}
