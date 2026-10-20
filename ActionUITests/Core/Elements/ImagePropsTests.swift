// Core/Elements/ImagePropsTests.swift
/*
 Tests for Image.Props: the sources in priority order (filePath, resourceName, assetName,
 systemName), the content mode with its deprecated alias, the resizable default and the image scale.
 A filePath whose extension is a known non-image type is skipped by the renderer, not by Props (it
 needs the platform's type table), so a filePath is always a source here.
*/

import XCTest
@testable import ActionUI

final class ImagePropsTests: XCTestCase {

    func testDefaults() {
        let props = Image.Props([:])
        XCTAssertEqual(props.sources, [])
        XCTAssertNil(props.contentMode)
        XCTAssertFalse(props.resizable)
        XCTAssertNil(props.imageScale)
    }

    func testValidValues() {
        let props = Image.Props(["systemName": "star", "contentMode": "fill", "resizable": false, "imageScale": "large"])
        XCTAssertEqual(props.sources, [.systemName("star")])
        XCTAssertEqual(props.contentMode, .fill)
        XCTAssertFalse(props.resizable)
        XCTAssertEqual(props.imageScale, .large)
    }

    func testEachSource() {
        XCTAssertEqual(Image.Props(["filePath": "/tmp/a.png"]).sources, [.filePath("/tmp/a.png")])
        XCTAssertEqual(Image.Props(["resourceName": "a.png"]).sources, [.resourceName("a.png")])
        XCTAssertEqual(Image.Props(["assetName": "a"]).sources, [.assetName("a")])
        XCTAssertEqual(Image.Props(["systemName": "a"]).sources, [.systemName("a")])
    }

    func testSourcesAreOrderedMostSpecificFirst() {
        let props = Image.Props(["systemName": "s", "assetName": "a", "resourceName": "r", "filePath": "/tmp/f.png"])
        XCTAssertEqual(props.sources, [.filePath("/tmp/f.png"), .resourceName("r"), .assetName("a"), .systemName("s")])
    }

    func testFilePathIsASourceWhateverItsExtension() {
        // The renderer skips one with a known non-image extension (it needs the platform's type table).
        XCTAssertEqual(Image.Props(["filePath": "/tmp/a.txt", "systemName": "s"]).sources, [.filePath("/tmp/a.txt"), .systemName("s")])
    }

    func testSourceThatIsNotAStringIsLeftOut() {
        let props = Image.Props(["filePath": 5, "systemName": "s"])
        XCTAssertEqual(props.sources, [.systemName("s")])
    }

    func testContentModeImpliesResizable() {
        XCTAssertTrue(Image.Props(["contentMode": "fit"]).resizable)
        XCTAssertTrue(Image.Props(["scaleMode": "fill"]).resizable)
        XCTAssertFalse(Image.Props(["contentMode": "fit", "resizable": false]).resizable)
        XCTAssertTrue(Image.Props(["resizable": true]).resizable)
    }

    func testUnknownContentModeIsNoneAndNotResizable() {
        let props = Image.Props(["contentMode": "stretch"])
        XCTAssertNil(props.contentMode)
        XCTAssertFalse(props.resizable)
        XCTAssertNil(Image.Props(["contentMode": 5]).contentMode)
    }

    func testScaleModeIsADeprecatedAlias() {
        XCTAssertEqual(Image.Props(["scaleMode": "fill"]).contentMode, .fill)
        // contentMode wins when both are valid; an invalid contentMode leaves the alias.
        XCTAssertEqual(Image.Props(["contentMode": "fit", "scaleMode": "fill"]).contentMode, .fit)
        XCTAssertEqual(Image.Props(["contentMode": "stretch", "scaleMode": "fill"]).contentMode, .fill)
        XCTAssertEqual(Image.Props(["contentMode": 5, "scaleMode": "fit"]).contentMode, .fit)
        XCTAssertNil(Image.Props(["scaleMode": "stretch"]).contentMode)
    }

    func testResizableMustBeABool() {
        XCTAssertFalse(Image.Props(["resizable": "true"]).resizable)
        XCTAssertTrue(Image.Props(["resizable": "true", "contentMode": "fit"]).resizable)
    }

    func testImageScaleNames() {
        XCTAssertEqual(Image.Props(["imageScale": "small"]).imageScale, .small)
        XCTAssertEqual(Image.Props(["imageScale": "medium"]).imageScale, .medium)
        // Unknown means no scale modifier (not medium).
        XCTAssertNil(Image.Props(["imageScale": "huge"]).imageScale)
        XCTAssertNil(Image.Props(["imageScale": "Large"]).imageScale)
        XCTAssertNil(Image.Props(["imageScale": 5]).imageScale)
    }
}
