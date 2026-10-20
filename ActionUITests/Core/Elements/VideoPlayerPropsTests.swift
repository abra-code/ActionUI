// Core/Elements/VideoPlayerPropsTests.swift
/*
 Tests for VideoPlayer.Props: the URL string and the autoplay flag (absent is not the same as false).
*/

import XCTest
@testable import ActionUI

final class VideoPlayerPropsTests: XCTestCase {
    func testDefaults() {
        let props = VideoPlayer.Props([:])
        XCTAssertNil(props.url)
        XCTAssertNil(props.autoplay)
    }

    func testValidValues() {
        let props = VideoPlayer.Props(["url": "https://example.com/video.mp4", "autoplay": false])
        XCTAssertEqual(props.url, "https://example.com/video.mp4")
        XCTAssertEqual(props.autoplay, false)
        XCTAssertEqual(VideoPlayer.Props(["autoplay": true]).autoplay, true)
    }

    func testWrongTypesAreNone() {
        let props = VideoPlayer.Props(["url": 5, "autoplay": "true"])
        XCTAssertNil(props.url)
        XCTAssertNil(props.autoplay)
        XCTAssertNil(VideoPlayer.Props(["autoplay": 1]).autoplay)
    }
}
