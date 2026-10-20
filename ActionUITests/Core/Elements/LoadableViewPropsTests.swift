// Core/Elements/LoadableViewPropsTests.swift
/*
 Tests for LoadableView.Props: the three sources (url, filePath, name), of which one is kept when
 several are given, and the action fired after a sub-view is loaded.
*/

import XCTest
@testable import ActionUI

final class LoadableViewPropsTests: XCTestCase {

    func testDefaults() {
        let props = LoadableView.Props([:])
        XCTAssertNil(props.url)
        XCTAssertNil(props.filePath)
        XCTAssertNil(props.name)
        XCTAssertNil(props.viewDidLoadActionID)
    }

    func testEachSourceAlone() {
        XCTAssertEqual(LoadableView.Props(["url": "https://example.com/v.json"]).url, "https://example.com/v.json")
        XCTAssertEqual(LoadableView.Props(["filePath": "/tmp/v.json"]).filePath, "/tmp/v.json")
        XCTAssertEqual(LoadableView.Props(["name": "Hello.json"]).name, "Hello.json")
    }

    func testViewDidLoadActionID() {
        XCTAssertEqual(LoadableView.Props(["name": "a", "viewDidLoadActionID": "loaded"]).viewDidLoadActionID, "loaded")
        XCTAssertNil(LoadableView.Props(["viewDidLoadActionID": 5]).viewDidLoadActionID)
    }

    func testUrlWinsOverTheOtherSources() {
        let props = LoadableView.Props(["url": "https://a", "filePath": "/b", "name": "c"])
        XCTAssertEqual(props.url, "https://a")
        XCTAssertNil(props.filePath)
        XCTAssertNil(props.name)
    }

    func testFilePathWinsOverName() {
        let props = LoadableView.Props(["filePath": "/b", "name": "c"])
        XCTAssertNil(props.url)
        XCTAssertEqual(props.filePath, "/b")
        XCTAssertNil(props.name)
    }

    func testAnEmptySourceStillCounts() {
        let props = LoadableView.Props(["url": "", "filePath": "/b"])
        XCTAssertEqual(props.url, "")
        XCTAssertNil(props.filePath)
    }

    func testASourceThatIsNotAStringDoesNotCount() {
        let props = LoadableView.Props(["url": 5, "filePath": "/b", "name": "c"])
        XCTAssertNil(props.url)
        XCTAssertEqual(props.filePath, "/b")
        XCTAssertNil(props.name)

        let onlyName = LoadableView.Props(["url": 5, "filePath": 6, "name": "c"])
        XCTAssertNil(onlyName.url)
        XCTAssertNil(onlyName.filePath)
        XCTAssertEqual(onlyName.name, "c")
    }
}
