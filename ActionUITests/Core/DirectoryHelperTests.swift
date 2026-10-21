// Core/DirectoryHelperTests.swift
/*
 Tests for DirectoryHelper.cacheURL: the per-window cache folder under the application support
 directory (Library/Application Support on Apple, the XDG data folder on Linux).
*/

import XCTest
@testable import ActionUI

@MainActor
final class DirectoryHelperTests: XCTestCase {

    func testCacheURLIsInAPerWindowFolderThatExists() throws {
        let windowUUID = UUID().uuidString
        let logger = XCTestLogger(maxLevel: .verbose)
        let url = try XCTUnwrap(DirectoryHelper.cacheURL(
            for: windowUUID, resourceName: "image", resourceExtension: "png", logger: logger))
        let folder = url.deletingLastPathComponent()
        // Remove only the folder this test made.
        defer { try? FileManager.default.removeItem(at: folder) }

        XCTAssertEqual(url.lastPathComponent, "image.png")
        XCTAssertEqual(folder.lastPathComponent, windowUUID)
        XCTAssertEqual(folder.deletingLastPathComponent().lastPathComponent, "ActionUI")
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "only the folder is made")
    }
}
