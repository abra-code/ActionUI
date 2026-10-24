// Tests/Runtime/URLLoaderTests.swift
/*
 Tests for URLLoader and RemoteImages: file, http and data URLs load their bytes after fetch
 returns; a missing file, an http error status, a malformed URL and another scheme give nil; an
 image decodes into a texture kept by URL, loaded once for several waiters; bytes that are no image
 give no texture; the textures kept stay within the budget, the least recently used going first.
*/

import XCTest
import CAdwaita
@testable import ActionUI

@MainActor
final class URLLoaderTests: XCTestCase {
    private var files: [String] = []
    private var server: TestImageServer?

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
        RemoteImages.shared.removeAll()
    }

    override func tearDown() async throws {
        server?.stop()
        server = nil
        for path in files {
            try? FileManager.default.removeItem(atPath: path)
        }
        files = []
        RemoteImages.shared.removeAll()
        RemoteImages.shared.budget = 64 << 20
    }

    /// Fetches `url` and waits for the completion; nil when it gave nil.
    private func fetch(_ url: String) throws -> [UInt8]? {
        var result: [UInt8]??
        var returned = false
        URLLoader.fetch(url) { bytes in
            XCTAssertTrue(returned, "the completion runs after fetch returns")
            result = .some(bytes.map { loaded in
                var size: gsize = 0
                let data = g_bytes_get_data(loaded.bytes, &size)
                return data.map { Array(UnsafeRawBufferPointer(start: $0, count: Int(size))) } ?? []
            })
        }
        returned = true
        XCTAssertTrue(AdwaitaTestHost.runMainLoop { result != nil }, "\(url) did not complete")
        return result ?? nil
    }

    private func pngFile(_ name: String, width: Int32 = 20, height: Int32 = 10) throws -> String {
        let path = try TestImages.file(TestImages.png(width: width, height: height), name: name)
        files.append(path)
        return path
    }

    func testAFileURLLoadsItsBytes() throws {
        let png = TestImages.png(width: 4, height: 2)
        let path = try TestImages.file(png, name: "loader.png")
        files.append(path)
        XCTAssertEqual(try fetch(TestImages.fileURL(path)), png)
    }

    func testAMissingFileGivesNil() throws {
        XCTAssertNil(try fetch("file:///no/such/file.png"))
    }

    func testAnHTTPURLLoadsItsBytes() throws {
        let png = TestImages.png(width: 4, height: 2)
        let server = try TestImageServer(png: png)
        self.server = server
        XCTAssertEqual(try fetch(server.base + "/image.png"), png)
    }

    func testAnHTTPErrorStatusGivesNil() throws {
        let server = try TestImageServer(png: [])
        self.server = server
        XCTAssertNil(try fetch(server.base + "/missing.png"))
        XCTAssertEqual(server.requests, 1)
    }

    func testADataURLGivesItsBytes() throws {
        XCTAssertEqual(try fetch("data:text/plain;base64,aGk="), Array("hi".utf8))
        XCTAssertEqual(try fetch("data:,a%20b"), Array("a b".utf8))
    }

    func testOtherSchemesAndMalformedURLsGiveNil() throws {
        XCTAssertNil(try fetch("ftp://example.com/a.png"))
        XCTAssertNil(try fetch("not a url"))
        XCTAssertNil(try fetch("http://"))
    }

    func testAnImageIsDecodedAndKeptLoadingOnceForSeveralWaiters() throws {
        let server = try TestImageServer(png: TestImages.png(width: 20, height: 10))
        self.server = server
        let url = server.base + "/image.png"
        var results: [Bool] = []
        RemoteImages.shared.load(url) { results.append($0) }
        RemoteImages.shared.load(url) { results.append($0) }
        XCTAssertTrue(AdwaitaTestHost.runMainLoop { results.count == 2 })
        XCTAssertEqual(results, [true, true])
        XCTAssertEqual(server.requests, 1, "one request for both")
        let texture = try XCTUnwrap(RemoteImages.shared.texture(url))
        XCTAssertEqual(gdk_texture_get_width(texture.pointer), 20)
        XCTAssertEqual(gdk_texture_get_height(texture.pointer), 10)
        var again: Bool?
        RemoteImages.shared.load(url) { again = $0 }
        XCTAssertTrue(AdwaitaTestHost.runMainLoop { again != nil })
        XCTAssertEqual(again, true)
        XCTAssertEqual(server.requests, 1, "a kept image is not loaded again")
    }

    func testBytesThatAreNoImageGiveNoTexture() throws {
        let server = try TestImageServer(png: [])
        self.server = server
        let url = server.base + "/text.txt"
        var result: Bool?
        RemoteImages.shared.load(url) { result = $0 }
        XCTAssertTrue(AdwaitaTestHost.runMainLoop { result != nil })
        XCTAssertEqual(result, false)
        XCTAssertNil(RemoteImages.shared.texture(url))
    }

    func testTheLeastRecentlyUsedTextureGoesPastTheBudget() throws {
        // Each 20 x 10 image costs 800 bytes; the budget holds two.
        RemoteImages.shared.budget = 1600
        let urls = try ["a.png", "b.png", "c.png"].map { TestImages.fileURL(try pngFile($0)) }
        for url in urls.prefix(2) {
            var done = false
            RemoteImages.shared.load(url) { _ in done = true }
            XCTAssertTrue(AdwaitaTestHost.runMainLoop { done })
        }
        XCTAssertNotNil(RemoteImages.shared.texture(urls[0]), "a is used again, so b is the oldest")
        var done = false
        RemoteImages.shared.load(urls[2]) { _ in done = true }
        XCTAssertTrue(AdwaitaTestHost.runMainLoop { done })
        XCTAssertNotNil(RemoteImages.shared.texture(urls[0]))
        XCTAssertNil(RemoteImages.shared.texture(urls[1]))
        XCTAssertNotNil(RemoteImages.shared.texture(urls[2]))
    }
}
