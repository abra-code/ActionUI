// Common/ViewModelObserversTests.swift
/*
 Tests for ViewModel.observeStates / observeValue (ViewModel+Observers.swift), the Combine
 publishers built on them (ViewModel+Combine.swift), and Lock.
*/

import XCTest
import Combine
@testable import ActionUI

@MainActor
final class ViewModelObserversTests: XCTestCase {

    func testObserveStatesDeliversTheCurrentStatesThenEachChange() {
        let model = ViewModel()
        model.states = ["a": 1]
        var received: [[String: Any]] = []
        let observation = model.observeStates { received.append($0) }
        model.states["b"] = 2
        model.states["c"] = 3
        XCTAssertEqual(received.count, 3)
        XCTAssertEqual(received[0] as? [String: Int], ["a": 1])
        XCTAssertEqual(received[1] as? [String: Int], ["a": 1, "b": 2])
        XCTAssertEqual(received[2] as? [String: Int], ["a": 1, "b": 2, "c": 3])
        observation.cancel()
    }

    func testObserveValueDeliversTheCurrentValueThenEachChange() {
        let model = ViewModel()
        model.value = "first"
        var received: [String?] = []
        let observation = model.observeValue { received.append($0 as? String) }
        model.value = "second"
        model.value = "second"
        model.value = nil
        XCTAssertEqual(received, ["first", "second", "second", nil])
        observation.cancel()
    }

    func testCancelStopsTheDeliveries() {
        let model = ViewModel()
        var count = 0
        let observation = model.observeStates { _ in count += 1 }
        observation.cancel()
        observation.cancel()   // a second cancel does nothing
        model.states["x"] = 1
        XCTAssertEqual(count, 1)
        XCTAssertEqual(model.statesObservers?.count, 0)
    }

    func testReleasingTheObservationStopsTheDeliveries() {
        let model = ViewModel()
        var count = 0
        var observation: ActionUIObservation? = model.observeValue { _ in count += 1 }
        XCTAssertNotNil(observation)
        observation = nil
        model.value = 5
        XCTAssertEqual(count, 1)
        XCTAssertEqual(model.valueObservers?.count, 0)
    }

    func testCancelOnAnotherThreadStopsTheDeliveries() async {
        let model = ViewModel()
        var count = 0
        let observation = model.observeStates { _ in count += 1 }
        await Task.detached { observation.cancel() }.value
        model.states["x"] = 1
        XCTAssertEqual(count, 1)
    }

    func testObserversAreCalledInRegistrationOrder() {
        let model = ViewModel()
        var order: [String] = []
        let first = model.observeStates { _ in order.append("first") }
        let second = model.observeStates { _ in order.append("second") }
        order.removeAll()
        model.states["x"] = 1
        XCTAssertEqual(order, ["first", "second"])
        first.cancel()
        second.cancel()
    }

    func testAHandlerMayCancelItsOwnObservation() {
        let model = ViewModel()
        var count = 0
        var observation: ActionUIObservation?
        observation = model.observeStates { _ in
            count += 1
            if count == 2 {
                observation?.cancel()
            }
        }
        model.states["x"] = 1
        model.states["y"] = 2
        XCTAssertEqual(count, 2)
    }

    func testAHandlerCancelledByAnEarlierOneIsNotCalled() {
        let model = ViewModel()
        var calls = 0
        var second: ActionUIObservation?
        let first = model.observeStates { _ in second?.cancel() }
        second = model.observeStates { _ in calls += 1 }
        calls = 0
        model.states["x"] = 1
        XCTAssertEqual(calls, 0)
        first.cancel()
    }

    func testReleasingAHandlerThatOwnsAnotherObservationOfTheListDoesNotDeadlock() {
        final class Owner {
            var observation: ActionUIObservation?
        }
        let model = ViewModel()
        var owner: Owner? = Owner()
        owner?.observation = model.observeStates { _ in }
        let first = model.observeStates { [owner] _ in _ = owner }
        owner = nil
        XCTAssertEqual(model.statesObservers?.count, 2)
        // Removing first's handler releases the last reference to owner, whose observation then
        // removes itself from the same list.
        first.cancel()
        XCTAssertEqual(model.statesObservers?.count, 0)
    }

    func testAModelThatIsNeverObservedHasNoObserverLists() {
        let model = ViewModel()
        model.states["x"] = 1
        model.value = 2
        XCTAssertNil(model.statesObservers)
        XCTAssertNil(model.valueObservers)
    }

    // MARK: - Combine publishers

    func testStatesPublisherReplaysThenDeliversEachChange() {
        let model = ViewModel()
        model.states = ["a": 1]
        var received: [[String: Any]] = []
        let subscription = model.statesPublisher.sink { received.append($0) }
        model.states["b"] = 2
        model.states["c"] = 3
        XCTAssertEqual(received.count, 3)
        XCTAssertEqual(received.last as? [String: Int], ["a": 1, "b": 2, "c": 3])
        subscription.cancel()
        model.states["d"] = 4
        XCTAssertEqual(received.count, 3)
        XCTAssertEqual(model.statesObservers?.count, 0)
    }

    func testValuePublisherReplaysThenDeliversEachChange() {
        let model = ViewModel()
        model.value = 1
        var received: [Int?] = []
        let subscription = model.valuePublisher.sink { received.append($0 as? Int) }
        model.value = 2
        model.value = 3
        XCTAssertEqual(received, [1, 2, 3])
        subscription.cancel()
        XCTAssertEqual(model.valueObservers?.count, 0)
    }

    func testAPublisherThatIsNeverSubscribedReleasesItsRegistration() {
        let model = ViewModel()
        do {
            let publisher = model.statesPublisher
            XCTAssertEqual(model.statesObservers?.count, 1)
            _ = publisher
        }
        XCTAssertEqual(model.statesObservers?.count, 0)
    }

    func testPublisherDropFirstSkipsTheReplay() {
        let model = ViewModel()
        model.states = ["search": "old"]
        var received: [String?] = []
        let subscription = model.statesPublisher.dropFirst().sink { received.append($0["search"] as? String) }
        model.states["search"] = "new"
        XCTAssertEqual(received, ["new"])
        subscription.cancel()
    }
}
