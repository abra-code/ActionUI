// Sources/Runtime/ImagePixels.swift
/*
 The image decode cap on Linux: an image file or downloaded image that declares more pixels than
 ImageSource.maximumPixelCount is not decoded, so a small file declaring a huge image cannot take
 gigabytes. The size comes from the image's header, read by a gdk-pixbuf loader fed a few kilobytes
 at a time until it reports the size, the file's or the downloaded bytes. An image gdk-pixbuf cannot
 size goes on to GTK's decoder, which decides.

 Not gdk_pixbuf_get_file_info: it has its loader make the image at the size it declares, so an SVG
 of a hundred bytes declaring 20000 x 20000 is drawn whole (3 GB and over a second, measured with
 gdk-pixbuf 2.44 and librsvg 2.61). The loader here is told to make it 1 x 1.

 Some gdk-pixbuf builds (2.44, whose loaders hand most formats to glycin) report the size only once
 the loader is closed, after reading every byte; sizing then takes time with the image's size (tens
 of milliseconds for a large photo), so callers on the main thread keep the answer (Image.content).
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
#if canImport(Glibc)
import Glibc
#endif
import CAdwaita

enum ImagePixels {
    /// The piece of an image a loader is fed at a time.
    nonisolated private static let piece = 4096

    /// Whether the image file at `path` declares more pixels than the cap.
    nonisolated static func fileIsTooLarge(_ path: String) -> Bool {
        size(ofFile: path).map { ImageSource.isTooLarge(width: $0.width, height: $0.height) } ?? false
    }

    /// Whether the image bytes (a GBytes) declare more pixels than the cap. Safe off the main thread.
    nonisolated static func bytesAreTooLarge(_ bytes: OpaquePointer) -> Bool {
        size(of: bytes).map { ImageSource.isTooLarge(width: $0.width, height: $0.height) } ?? false
    }

    /// The pixel size the image file declares, nil when it cannot be read or gdk-pixbuf cannot tell.
    nonisolated static func size(ofFile path: String) -> (width: Int, height: Int)? {
        guard let file = fopen(path, "rb") else { return nil }
        defer { fclose(file) }
        var buffer = [UInt8](repeating: 0, count: piece)
        return size { write in
            buffer.withUnsafeMutableBytes { buffer in
                while true {
                    let count = fread(buffer.baseAddress, 1, piece, file)
                    guard count > 0, write(UnsafeRawPointer(buffer.baseAddress!), count) else { return }
                }
            }
        }
    }

    /// The pixel size the image bytes declare, nil when gdk-pixbuf cannot tell.
    nonisolated static func size(of bytes: OpaquePointer) -> (width: Int, height: Int)? {
        var length: gsize = 0
        guard let start = g_bytes_get_data(bytes, &length), length > 0 else { return nil }
        return size { write in
            var offset = 0
            while offset < Int(length) {
                let count = min(piece, Int(length) - offset)
                guard write(start.advanced(by: offset), count) else { return }
                offset += count
            }
        }
    }

    /// The pixel size a loader reports for what `feed` gives it. `feed` passes each piece to the
    /// function it is given, which returns false once no more is wanted.
    private nonisolated static func size(_ feed: ((UnsafeRawPointer, Int) -> Bool) -> Void) -> (width: Int, height: Int)? {
        let loader = gdk_pixbuf_loader_new()!
        // Width and height, -1 until "size-prepared" reports them.
        let found = UnsafeMutablePointer<Int32>.allocate(capacity: 2)
        found.initialize(repeating: -1, count: 2)
        defer { found.deallocate() }
        g_signal_connect_data(UnsafeMutableRawPointer(loader), "size-prepared",
                              unsafeBitCast(sizePrepared, to: GCallback.self), UnsafeMutableRawPointer(found), nil,
                              GConnectFlags(rawValue: 0))
        feed { start, count in
            var error: UnsafeMutablePointer<GError>?
            let written = gdk_pixbuf_loader_write(loader, start.assumingMemoryBound(to: guchar.self), gsize(count), &error)
            if let error { g_error_free(error) }
            return written != 0 && found[0] < 0
        }
        // Closing a loader fed part of an image reports an error, which is expected here.
        var closeError: UnsafeMutablePointer<GError>?
        _ = gdk_pixbuf_loader_close(loader, &closeError)
        if let closeError { g_error_free(closeError) }
        g_object_unref(UnsafeMutableRawPointer(loader))
        guard found[0] >= 0, found[1] >= 0 else { return nil }
        return (Int(found[0]), Int(found[1]))
    }
}

/// "size-prepared": keeps the size and has the loader scale to 1 x 1, so it never makes the full
/// image if it goes on decoding what it was given. (Not 0 x 0, which librsvg reads as the size the
/// SVG declares.)
private let sizePrepared: @convention(c) (UnsafeMutableRawPointer?, Int32, Int32, UnsafeMutableRawPointer?) -> Void = { loader, width, height, data in
    guard let data else { return }
    let found = data.assumingMemoryBound(to: Int32.self)
    found[0] = width
    found[1] = height
    if let loader {
        gdk_pixbuf_loader_set_size(loader.assumingMemoryBound(to: GdkPixbufLoader.self), 1, 1)
    }
}
