// PrivateAsyncImage.swift - the remote image of less-trusted content, for AsyncImage and the
// asyncImage cells of List and Table. SwiftUI's AsyncImage fetches with URLSession.shared (the
// app's cookies and stored credentials) and reads and decodes any size; for an address that content
// not the app's own names, this view fetches with the private session RemoteJSONFetch uses, reads
// at most maximumBytes, and decodes only an image whose header declares no more pixels than
// ImageSource.maximumPixelCount. Trusted content keeps SwiftUI's AsyncImage.

import SwiftUI
import ImageIO

/// Shows `content` with the image at `url` once it has loaded, `placeholder` while it loads and
/// when it cannot be shown, as SwiftUI's AsyncImage(url:content:placeholder:) does.
struct PrivateAsyncImage<Content: SwiftUI.View, Placeholder: SwiftUI.View>: SwiftUI.View {
    let url: URL
    let logger: any ActionUILogger
    @ViewBuilder let content: (SwiftUI.Image) -> Content
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var image: SwiftUI.Image?
    @State private var loadedURL: URL?

    var body: some SwiftUI.View {
        SwiftUI.Group {
            if let image, loadedURL == url {
                content(image)
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            let requested = url
            do {
                let picture = try await PrivateImageLoad.load(requested)
                guard !Task.isCancelled else { return }
                image = SwiftUI.Image(decorative: picture, scale: 1)
                loadedURL = requested
            } catch is CancellationError {
                return
            } catch {
                // Canceled (a new url, or the view went away): URLSession throws URLError.cancelled,
                // not CancellationError. Nothing to log, and the newer task owns the state.
                guard !Task.isCancelled else { return }
                logger.log("AsyncImage not shown: \(requested.absoluteString): \(error.localizedDescription)", .warning)
                image = nil
                loadedURL = nil
            }
        }
    }
}

/// The fetch and decode behind PrivateAsyncImage, off the main actor.
enum PrivateImageLoad {
    /// The most bytes one image may have (Linux's URLLoader.maximumSize and Android's remote image
    /// limit: 32 MB).
    nonisolated(unsafe) static var maximumBytes = 32 * 1024 * 1024

    /// The image at `url`, oriented as its EXIF data says. A file: URL is read only when it names a
    /// regular file (the caller has asked the trust policy); anything else is fetched with
    /// RemoteJSONFetch's private session, its size limit and its time limit.
    /// @concurrent: with NonisolatedNonsendingByDefault (the Xcode project's Approachable
    /// Concurrency) a plain nonisolated async function runs on its caller's actor, here the main one.
    @concurrent nonisolated static func load(_ url: URL) async throws -> CGImage {
        let data: Data
        if url.isFileURL {
            data = try readFile(url)
        } else {
            data = try await RemoteJSONFetch.data(for: URLRequest(url: url), limit: maximumBytes,
                                                  session: RemoteJSONFetch.privateSession, what: "the image").data
        }
        try Task.checkCancellation()
        return try decode(data)
    }

    /// The bytes of the regular file at `url` when it holds at most maximumBytes. The file may have
    /// been replaced since it was checked: it is opened without waiting (a named pipe put in its
    /// place does not block), checked again to be a regular file, and read for at most maximumBytes
    /// + 1 bytes.
    nonisolated static func readFile(_ url: URL) throws -> Data {
        guard let path = ActionUIContentLoader.regularFilePath(url) else {
            throw ActionUIError("it names no regular file")
        }
        let descriptor = open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { throw ActionUIError("it cannot be opened") }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var information = stat()
        guard fstat(descriptor, &information) == 0, information.st_mode & S_IFMT == S_IFREG else {
            throw ActionUIError("it names no regular file")
        }
        guard Int64(information.st_size) <= Int64(maximumBytes) else { throw tooLarge() }
        let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
        guard data.count <= maximumBytes else { throw tooLarge() }
        return data
    }

    /// The image `data` holds, when its header declares no more than ImageSource.maximumPixelCount
    /// pixels (read before anything is decoded), with its EXIF orientation applied.
    nonisolated static func decode(_ data: Data) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0, height > 0 else {
            throw ActionUIError("it is not an image ImageIO can read")
        }
        guard !ImageSource.isTooLarge(width: width, height: height) else {
            throw ActionUIError("it is \(width) x \(height) pixels, more than \(ImageSource.maximumPixelCount)")
        }
        // Upright already (most images): decoded as it is. The full-size thumbnail below needs about
        // half as much memory again at its peak (747 rather than 501 MB for 64 megapixels).
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        if orientation == 1 {
            guard let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else {
                throw ActionUIError("it could not be decoded")
            }
            return image
        }
        // A thumbnail as large as the image itself: the one ImageIO call that applies the orientation.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width, height),
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ActionUIError("it could not be decoded")
        }
        return image
    }

    private nonisolated static func tooLarge() -> ActionUIError {
        ActionUIError("it is larger than \(maximumBytes / (1024 * 1024)) MB")
    }
}
