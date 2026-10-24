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

    func testAResourceInTheHostsResourceFolderIsFound() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("image-helper-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer {
            ActionUIResourceFolder.path = nil
            try? FileManager.default.removeItem(at: folder)
        }
        let file = folder.appendingPathComponent("photo.png").path
        XCTAssertTrue(FileManager.default.createFile(atPath: file, contents: Data([0x89, 0x50, 0x4E, 0x47])))
        XCTAssertNil(ImageHelper.lookup.resourcePath("photo.png"))
        ActionUIResourceFolder.path = folder.path
        XCTAssertEqual(ImageHelper.lookup.resourcePath("photo.png"), file)
        XCTAssertEqual(ImageSource.resolve("photo.png", interpretation: "resourceName", lookup: ImageHelper.lookup), .filePath(file))
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
