// Core/ImageSourceTests.swift
/*
 Tests for ImageSource.resolve: what an image string names under each interpretation, with the
 platform checks stubbed (image files end in ".png", one bundled resource, one asset).
*/

import XCTest
@testable import ActionUI

final class ImageSourceTests: XCTestCase {

    private let lookup = ImageSource.Lookup(
        isImageFile: { $0.hasSuffix(".png") },
        resourcePath: { $0 == "logo.png" || $0 == "notes.txt" ? "/bundle/" + $0 : nil },
        assetExists: { $0 == "Brand" }
    )

    private func resolve(_ text: String, _ interpretation: String) -> ImageSource {
        ImageSource.resolve(text, interpretation: interpretation, lookup: lookup)
    }

    func testSystemNameAndAssetNameTakeTheTextAsGiven() {
        XCTAssertEqual(resolve("star.fill", "systemName"), .systemName("star.fill"))
        XCTAssertEqual(resolve("/a/b.png", "systemName"), .systemName("/a/b.png"))
        XCTAssertEqual(resolve("Missing", "assetName"), .assetName("Missing"), "not checked")
    }

    func testResourceNameIsTheBundledFileElseAnAsset() {
        XCTAssertEqual(resolve("logo.png", "resourceName"), .filePath("/bundle/logo.png"))
        XCTAssertEqual(resolve("notes.txt", "resourceName"), .filePath("/bundle/notes.txt"), "the file type is not checked")
        XCTAssertEqual(resolve("other.png", "resourceName"), .assetName("other.png"))
    }

    func testPathIsTheFileWhenItIsAnImageElseThePlaceholder() {
        XCTAssertEqual(resolve("/a/b.png", "path"), .filePath("/a/b.png"))
        XCTAssertEqual(resolve("b.png", "path"), .filePath("b.png"))
        XCTAssertEqual(resolve("/a/b.txt", "path"), .systemName(ImageSource.placeholderSymbol))
    }

    func testMixed() {
        // A "/" makes it a path.
        XCTAssertEqual(resolve("/a/b.png", "mixed"), .filePath("/a/b.png"))
        XCTAssertEqual(resolve("/a/b.txt", "mixed"), .systemName("photo"))
        XCTAssertEqual(resolve("a/logo.png", "mixed"), .filePath("a/logo.png"), "a path, not looked up as a resource")
        // An image file name that is bundled.
        XCTAssertEqual(resolve("logo.png", "mixed"), .filePath("/bundle/logo.png"))
        // A bundled resource that is no image file is not used; neither is an image name not bundled.
        XCTAssertEqual(resolve("notes.txt", "mixed"), .systemName("notes.txt"))
        XCTAssertEqual(resolve("other.png", "mixed"), .systemName("other.png"))
        // An asset, else a symbol.
        XCTAssertEqual(resolve("Brand", "mixed"), .assetName("Brand"))
        XCTAssertEqual(resolve("star.fill", "mixed"), .systemName("star.fill"))
    }

    func testAnUnknownInterpretationIsMixed() {
        for text in ["/a/b.png", "/a/b.txt", "logo.png", "Brand", "star.fill", ""] {
            XCTAssertEqual(resolve(text, "bogus"), resolve(text, "mixed"), text)
            XCTAssertEqual(resolve(text, ""), resolve(text, "mixed"), text)
        }
    }
}
