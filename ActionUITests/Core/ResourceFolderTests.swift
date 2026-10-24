// Core/ResourceFolderTests.swift
/*
 Tests for ActionUIResourceFolder: the folder a host names for its resources, and the files found
 in it (regular files only, never outside the folder).
*/

import XCTest
@testable import ActionUI
import Foundation

final class ResourceFolderTests: XCTestCase {
    private var folder: String!

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("resource-folder-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        ActionUIResourceFolder.path = nil
        try? FileManager.default.removeItem(atPath: folder)
    }

    func testAFileInTheFolderIsFound() throws {
        let file = URL(fileURLWithPath: folder).appendingPathComponent("Panel.json").path
        XCTAssertTrue(FileManager.default.createFile(atPath: file, contents: Data("{}".utf8)))
        XCTAssertNil(ActionUIResourceFolder.file("Panel.json"), "no folder named yet")
        ActionUIResourceFolder.path = folder
        XCTAssertEqual(ActionUIResourceFolder.file("Panel.json"), file)
        XCTAssertNil(ActionUIResourceFolder.file("Missing.json"))
        ActionUIResourceFolder.path = nil
        XCTAssertNil(ActionUIResourceFolder.file("Panel.json"), "none once the folder is cleared")
    }

    func testOnlyRegularFilesDirectlyInTheFolderAreFound() throws {
        let sub = URL(fileURLWithPath: folder).appendingPathComponent("Sub.json").path
        try FileManager.default.createDirectory(atPath: sub, withIntermediateDirectories: true)
        XCTAssertTrue(FileManager.default.createFile(atPath: sub + "/Inner.json", contents: Data("{}".utf8)))
        ActionUIResourceFolder.path = folder
        XCTAssertNil(ActionUIResourceFolder.file("Sub.json"), "a folder is no resource")
        XCTAssertNil(ActionUIResourceFolder.file("Sub.json/Inner.json"), "a name with a path is refused")
        XCTAssertNil(ActionUIResourceFolder.file("../Panel.json"))
        XCTAssertNil(ActionUIResourceFolder.file(""))
    }
}
