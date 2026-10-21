// Helpers/ImageHelperTests.swift
/*
 Tests for ImageHelper.lookup, the Apple checks behind ImageSource.resolve: image files by UTType
 (images and PDF), resources in the main bundle, assets by name.
*/

import XCTest
@testable import ActionUI

final class ImageHelperTests: XCTestCase {

    func testImageFilesAreImagesAndPDFsByTheirExtension() {
        let lookup = ImageHelper.lookup
        for path in ["/a/b.png", "b.JPG", "c.jpeg", "d.heic", "e.gif", "f.tiff", "g.pdf"] {
            XCTAssertTrue(lookup.isImageFile(path), path)
        }
        for path in ["/a/b.txt", "b.json", "c", "d.", "/a/b.png/"] {
            XCTAssertEqual(lookup.isImageFile(path), ImageHelper.validateImageFilePath(path) != nil, path)
        }
        XCTAssertFalse(lookup.isImageFile("/a/b.txt"))
        XCTAssertFalse(lookup.isImageFile("c"))
    }

    func testNoResourceOrAssetOfAnUnknownName() {
        let lookup = ImageHelper.lookup
        XCTAssertNil(lookup.resourcePath("no-such-resource-\(UUID().uuidString).png"))
        XCTAssertFalse(lookup.assetExists("no-such-asset-\(UUID().uuidString)"))
    }

    func testAPathOfAnImageResolvesToTheFileAndOtherwiseToThePlaceholder() {
        XCTAssertEqual(ImageSource.resolve("/tmp/x.png", interpretation: "mixed", lookup: ImageHelper.lookup),
                       .filePath("/tmp/x.png"))
        XCTAssertEqual(ImageSource.resolve("/tmp/x.txt", interpretation: "path", lookup: ImageHelper.lookup),
                       .systemName("photo"))
        XCTAssertEqual(ImageSource.resolve("star.fill", interpretation: "mixed", lookup: ImageHelper.lookup),
                       .systemName("star.fill"))
    }
}
