// Tests/Runtime/ImagePixelsTests.swift
/*
 Tests for the image decode cap on Linux: an image file or downloaded image whose header declares
 more pixels than ImageSource.maximumPixelCount is not decoded; a file shows the placeholder.
*/

#if canImport(Glibc)
import Glibc
#endif
import XCTest
import CAdwaita
@testable import ActionUI

@MainActor
final class ImagePixelsTests: XCTestCase {
    private var files: [String] = []

    override func setUp() async throws {
        // No super.setUp(): see URLLoaderTests.
        try AdwaitaTestHost.initialize()
    }

    override func tearDown() async throws {
        for path in files {
            try? FileManager.default.removeItem(atPath: path)
        }
        files = []
    }

    /// A PNG that declares `width` x `height` pixels but holds almost no image data: its header and
    /// the start of its data, which is what a decoder reads to size it.
    private static func pngHeader(width: UInt32, height: UInt32) -> [UInt8] {
        func crc32(_ bytes: [UInt8]) -> UInt32 {
            var crc: UInt32 = 0xFFFF_FFFF
            for byte in bytes {
                crc ^= UInt32(byte)
                for _ in 0..<8 { crc = (crc >> 1) ^ (0xEDB8_8320 & (0 &- (crc & 1))) }
            }
            return ~crc
        }
        func bigEndian(_ value: UInt32) -> [UInt8] {
            [UInt8(value >> 24), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
        }
        func chunk(_ type: String, _ body: [UInt8]) -> [UInt8] {
            let typed = Array(type.utf8) + body
            return bigEndian(UInt32(body.count)) + typed + bigEndian(crc32(typed))
        }
        return [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
            + chunk("IHDR", bigEndian(width) + bigEndian(height) + [8, 6, 0, 0, 0])
            + chunk("IDAT", [0x78, 0x9C, 0x03, 0x00, 0x00, 0x00, 0x00, 0x01]) + chunk("IEND", [])
    }

    private func bytes(_ array: [UInt8]) -> OpaquePointer {
        g_bytes_new(array, gsize(array.count))!
    }

    func testAFileThatDeclaresTooManyPixelsShowsThePlaceholder() throws {
        let huge = try TestImages.file(Self.pngHeader(width: 10000, height: 10000), name: "pixels-huge.png")
        let edge = try TestImages.file(Self.pngHeader(width: 8192, height: 8192), name: "pixels-edge.png")
        let small = try TestImages.file(TestImages.png(width: 20, height: 10), name: "pixels-small.png")
        files += [huge, edge, small]
        XCTAssertTrue(ImagePixels.fileIsTooLarge(huge), "100 megapixels, from a file of a few bytes")
        XCTAssertFalse(ImagePixels.fileIsTooLarge(edge), "8192 x 8192 is the most")
        XCTAssertFalse(ImagePixels.fileIsTooLarge(small))
        XCTAssertEqual(Image.content(.filePath(huge)), .symbol(ImageSource.placeholderSymbol))
        XCTAssertEqual(Image.content(.filePath(huge)), .symbol(ImageSource.placeholderSymbol), "kept")
        XCTAssertEqual(Image.content(.filePath(small)), .file(small))
        // Rewritten with a small image (a new version): sized again.
        _ = try TestImages.file(TestImages.png(width: 20, height: 10), name: "pixels-huge.png")
        XCTAssertEqual(Image.content(.filePath(huge)), .file(huge))
    }

    /// A short SVG that declares a huge size is sized without being drawn at that size.
    func testAnSVGThatDeclaresTooManyPixelsIsNotDrawnToBeSized() throws {
        let svg = Array("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"20000\" height=\"20000\"><rect width=\"10\" height=\"10\"/></svg>".utf8)
        let path = try TestImages.file(svg, name: "pixels-huge.svg")
        files.append(path)
        var before = rusage()
        getrusage(Int32(RUSAGE_SELF.rawValue), &before)
        let size = ImagePixels.size(ofFile: path)
        var after = rusage()
        getrusage(Int32(RUSAGE_SELF.rawValue), &after)
        guard let size else { throw XCTSkip("gdk-pixbuf has no SVG loader here") }
        XCTAssertEqual([size.width, size.height], [20000, 20000])
        XCTAssertTrue(ImagePixels.fileIsTooLarge(path))
        // Drawn whole, 20000 x 20000 takes 1.6 GB or more; maxrss is in kilobytes.
        XCTAssertLessThan(after.ru_maxrss - before.ru_maxrss, 200 * 1024, "the peak grew by \(after.ru_maxrss - before.ru_maxrss) KB")
    }

    func testDownloadedBytesThatDeclareTooManyPixelsAreRefused() throws {
        let huge = bytes(Self.pngHeader(width: 10000, height: 10000))
        let small = bytes(TestImages.png(width: 20, height: 10))
        defer {
            g_bytes_unref(huge)
            g_bytes_unref(small)
        }
        XCTAssertEqual(ImagePixels.size(of: huge).map { [$0.width, $0.height] }, [10000, 10000])
        XCTAssertTrue(ImagePixels.bytesAreTooLarge(huge))
        XCTAssertEqual(ImagePixels.size(of: small).map { [$0.width, $0.height] }, [20, 10])
        XCTAssertFalse(ImagePixels.bytesAreTooLarge(small))
        let text = bytes(Array("not an image".utf8))
        defer { g_bytes_unref(text) }
        XCTAssertNil(ImagePixels.size(of: text), "no size: GTK's decoder decides")
    }
}
