// ActionUITests/Core/ResourceFolderWindowsTests.swift
/*
 Tests for the Windows forms of ActionUIResourceFolder.isFile: how a path is compared (windowsKey,
 holdsFiles: run on every system), and, on Windows, files inside and outside a resource folder named
 in each of Windows' path forms.
*/

import XCTest
@testable import ActionUI
import Foundation

final class ResourceFolderWindowsTests: XCTestCase {
    func testAWindowsPathIsComparedWithSlashesAndWithoutTheCaseOfASCIILetters() {
        XCTAssertEqual(ActionUIResourceFolder.windowsKey("C:\\App\\Res"), "c:/app/res")
        XCTAssertEqual(ActionUIResourceFolder.windowsKey("C:/App/Res/"), "c:/app/res")
        XCTAssertEqual(ActionUIResourceFolder.windowsKey("/C:/App/Res/x.json"), "c:/app/res/x.json", "a file URL's path")
        XCTAssertEqual(ActionUIResourceFolder.windowsKey("\\\\Server\\Share\\x.json"), "//server/share/x.json")
        XCTAssertEqual(ActionUIResourceFolder.windowsKey("C:/\u{00DC}ber/X"), "c:/\u{00DC}ber/x", "only ASCII letters are folded")
    }

    func testOtherWindowsPathFormsAreNoFileUnderADriveOrAShare() {
        let refused = [
            "\\\\?\\C:\\App\\x.json",           // the \\?\ namespace (not normalized by Windows)
            "\\\\.\\COM1",                       // a device
            "\\??\\UNC\\server\\share\\x.json",  // the object manager's namespace
            "C:x.json",                          // drive-relative: the drive's own current folder
            "C:",
            "C:/App/Res/x.json:stream",          // an alternate data stream
            "D:/docs/C:x.json",                  // a drive-relative path put under a folder
            "///server/x.json",
            "Images/x.json",                     // relative
            "/usr/x.json",                       // no drive
            "",
            "C:/App/Res/COM1",                   // devices, whatever their extension or case
            "C:/App/Res/nul.json",
            "C:/App/Res/Lpt\u{00B9}.png",
            "C:/App/CON /x.json",
        ]
        for path in refused {
            XCTAssertNil(ActionUIResourceFolder.windowsKey(path), path)
        }
    }

    func testNamesThatOnlyStartLikeADeviceAreFiles() {
        XCTAssertEqual(ActionUIResourceFolder.windowsKey("C:/App/Res/COM10.json"), "c:/app/res/com10.json")
        XCTAssertEqual(ActionUIResourceFolder.windowsKey("C:/App/Res/console.json"), "c:/app/res/console.json")
        XCTAssertEqual(ActionUIResourceFolder.windowsKey("C:/App/Res/nullable.png"), "c:/app/res/nullable.png")
    }

    func testADrivesRootOrAShareRootHoldsNoFiles() {
        XCTAssertFalse(ActionUIResourceFolder.holdsFiles("c:"))
        XCTAssertFalse(ActionUIResourceFolder.holdsFiles("//server/share"))
        XCTAssertTrue(ActionUIResourceFolder.holdsFiles("c:/app"))
        XCTAssertTrue(ActionUIResourceFolder.holdsFiles("//server/share/app"))
        XCTAssertEqual(ActionUIResourceFolder.windowsKey("C:\\"), "c:", "a drive's root has no trailing slash to keep")
    }

    #if os(Windows)
    /// A new folder with a "resources" folder (holding "inside.json"), an "outside.json" beside it
    /// and a sibling folder named "resources2".
    private func folders() throws -> (root: URL, resources: URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("actionui-windows-\(UUID().uuidString)")
        let resources = root.appendingPathComponent("resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("resources2"), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: resources.appendingPathComponent("inside.json"))
        try Data("{}".utf8).write(to: root.appendingPathComponent("outside.json"))
        try Data("{}".utf8).write(to: root.appendingPathComponent("resources2/sibling.json"))
        return (root, resources)
    }

    /// The folder's path in Windows' own form ("C:\Users\...").
    private func windowsPath(_ url: URL) -> String {
        url.withUnsafeFileSystemRepresentation { $0.map { String(cString: $0) } } ?? url.path
    }

    func testAFileInsideTheResourcesIsInsideInEachSpelling() throws {
        let (root, resources) = try folders()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = windowsPath(resources)
        let inside = folder + "\\inside.json"
        XCTAssertTrue(ActionUIResourceFolder.isFile(URL(fileURLWithPath: inside), inside: folder))
        XCTAssertTrue(ActionUIResourceFolder.isFile(URL(fileURLWithPath: inside.uppercased()), inside: folder), "another case")
        XCTAssertTrue(ActionUIResourceFolder.isFile(URL(fileURLWithPath: inside), inside: folder.uppercased()), "the folder in another case")
        XCTAssertTrue(ActionUIResourceFolder.isFile(URL(fileURLWithPath: inside.replacingOccurrences(of: "\\", with: "/")), inside: folder),
                      "forward slashes")
        XCTAssertTrue(ActionUIResourceFolder.isFile(resources.appendingPathComponent("inside.json"), inside: folder), "a file URL")
        // Windows drops a name's final dot ("resources." is "resources"), so this is the inside file.
        XCTAssertTrue(ActionUIResourceFolder.isFile(URL(fileURLWithPath: windowsPath(root) + "\\resources.\\inside.json"), inside: folder),
                      "a folder name with a final dot")
    }

    func testAFileOutsideTheResourcesOrInAnotherFormIsOutside() throws {
        let (root, resources) = try folders()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = windowsPath(resources)
        let inside = folder + "\\inside.json"
        let outside = [
            windowsPath(root) + "\\outside.json",
            windowsPath(root) + "\\resources2\\sibling.json",
            folder + "\\..\\outside.json",
            "\\\\?\\" + inside,
            inside + ":stream",
            String(inside.prefix(2)) + "inside.json",  // drive-relative ("C:inside.json")
        ]
        for path in outside {
            XCTAssertFalse(ActionUIResourceFolder.isFile(URL(fileURLWithPath: path), inside: folder), path)
        }
        let drive = String(folder.prefix(3))  // "C:\"
        XCTAssertFalse(ActionUIResourceFolder.isFile(URL(fileURLWithPath: inside), inside: drive), "a drive's root holds nothing")
    }
    #endif
}
