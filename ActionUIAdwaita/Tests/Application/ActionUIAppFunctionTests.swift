// Tests/Application/ActionUIAppFunctionTests.swift
/*
 Tests for the actionUIApp* C functions on Linux, called as a C host calls them, with C function
 pointers as handlers: a window presented before actionUIAppRun opens at the start, its handlers
 fire in order, and closing it ends the run; a run off the main thread, and a setter from another
 thread before the run, are refused and return; a refused nested run leaves other threads able to
 call; a host sets the resource folder (NULL: none); the remote server, not on Linux yet, answers
 as a failure. The alert and the file panels: AppPanelsTests.
*/

import XCTest
import CAdwaita
import Dispatch
@testable import ActionUI
import ActionUIAdwaitaApplication

/// What the C handlers record; C function pointers cannot capture, so they write here.
nonisolated(unsafe) private var events: [String] = []

@MainActor
final class ActionUIAppFunctionTests: XCTestCase {
    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
        ActionUIRegistry.shared.loadBuiltIns()
        events = []
    }

    override func tearDown() async throws {
        for handler in [actionUIAppSetWillFinishLaunchingHandler, actionUIAppSetDidFinishLaunchingHandler, actionUIAppSetWillTerminateHandler] {
            handler(nil)
        }
        actionUIAppSetWindowWillPresentHandler(nil)
        actionUIAppSetWindowWillCloseHandler(nil)
        ActionUIModel.shared.windowModels["c-app-w1"] = nil
        AdwaitaApplication.shared.name = nil
        AdwaitaApplication.shared.applicationID = nil
        AdwaitaTestHost.drainMainLoop()
    }

    func testAHostRunsTheApplicationThroughTheCFunctions() throws {
        actionUIAppSetName("C Host Test")
        actionUIAppSetApplicationID("org.example.CHostTest")
        actionUIAppSetWillFinishLaunchingHandler { events.append("willFinishLaunching") }
        actionUIAppSetWindowWillPresentHandler { uuid in events.append("present \(uuid.map { String(cString: $0) } ?? "")") }
        actionUIAppSetWindowWillCloseHandler { uuid in events.append("close \(uuid.map { String(cString: $0) } ?? "")") }
        actionUIAppSetDidFinishLaunchingHandler {
            events.append("didFinishLaunching")
            actionUIAppCloseWindow("c-app-w1")
            actionUIAppTerminate()
        }
        actionUIAppSetWillTerminateHandler { events.append("willTerminate") }
        actionUIAppLoadAndPresentWindowFromJSON(#"{"type": "Text", "id": 1, "properties": {"text": "From C"}}"#, "c-app-w1", nil)
        actionUIAppRun()
        XCTAssertEqual(events, ["willFinishLaunching", "present c-app-w1", "didFinishLaunching", "close c-app-w1", "willTerminate"])
    }

    func testARunOffTheMainThreadIsRefusedAndReturns() {
        let returned = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            actionUIAppRun()
            returned.signal()
        }
        XCTAssertEqual(returned.wait(timeout: .now() + 10), .success, "actionUIAppRun on another thread returns at once")
    }

    func testASetterFromAnotherThreadBeforeTheRunIsRefusedAndReturns() {
        // Waiting for the main thread would never end: it runs no main queue before the run (here
        // it waits on the semaphore).
        let returned = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            actionUIAppSetName("From a worker")
            returned.signal()
        }
        XCTAssertEqual(returned.wait(timeout: .now() + 10), .success, "refused, not waiting for the run")
        XCTAssertNotEqual(AdwaitaApplication.shared.name, "From a worker")
    }

    func testARefusedNestedRunLeavesTheRunOpenToOtherThreads() {
        actionUIAppSetDidFinishLaunchingHandler {
            actionUIAppRun()  // refused: the application runs already
            DispatchQueue.global().async {
                actionUIAppSetName("From a worker during the run")
                actionUIAppCloseWindow("c-app-w1")
                actionUIAppTerminate()
            }
        }
        actionUIAppLoadAndPresentWindowFromJSON(#"{"type": "Text", "id": 1, "properties": {"text": "Nested"}}"#, "c-app-w1", nil)
        actionUIAppRun()
        XCTAssertEqual(AdwaitaApplication.shared.name, "From a worker during the run", "the setter waited for the main thread, not refused")
    }

    func testAHostSetsTheResourceFolder() {
        defer { AdwaitaApplication.shared.resourceFolder = nil }
        actionUIAppSetResourceFolder("/opt/example/app")
        XCTAssertEqual(AdwaitaApplication.shared.resourceFolder, "/opt/example/app")
        actionUIAppSetResourceFolder(nil)
        XCTAssertEqual(AdwaitaApplication.shared.resourceFolder, AppBundle.defaultFolder(), "NULL: back to the program's folder")
    }

    func testTheFunctionsNotOnLinuxYetAnswerAsFailures() {
        XCTAssertFalse(actionUIAppStartRemoteServer(nil))
        XCTAssertNil(actionUIAppRemoteServerToken())
        XCTAssertNil(actionUIAppRemoteServerEndpoint())
        var token = [CChar](repeating: 0, count: 64)
        XCTAssertFalse(actionUIAppRemoteCopyServerToken(&token, token.count))
    }
}
