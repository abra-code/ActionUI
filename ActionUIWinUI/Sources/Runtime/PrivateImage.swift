// Sources/Runtime/PrivateImage.swift
/*
 Loads http and https images for AsyncImage and Table image cells in less-trusted content (ActionUI JSON
 from a server, or from a file outside the app's resources), as Apple's PrivateAsyncImage does:
 - The download sends no cookies and no Windows sign-in, keeps no cookies and shows no password dialog
   (the shim's private fetch). WinUI's own image loader sends the app's cookies and signs in to a server
   on its own.
 - The download stops at 32 MB (at once when the server announces more) and after 120 seconds.
 - The image is shown only if it is a bitmap whose header declares at most 64 megapixels
   (ImageSource.maximumPixelCount). The header is read before anything is decoded. SVG images are not
   shown, as on Apple: they declare no pixel size, and they can draw embedded bitmaps of any size.
 - Nothing is cached: each load downloads again, and nothing is shared with trusted content's images.
 Trusted content keeps WinUI's image loader and its cache.
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import CWinUI

@MainActor enum PrivateImage {
    /// The most bytes one image may have (Apple's, Linux's and Android's remote image limit).
    static let maximumBytes: Int64 = 32 * 1024 * 1024

    /// Whether `text` is an http or https address (any case), its scheme read by URL(string:) as
    /// LinkTrust.readsImageURL reads it: text it lets through as http or https ("http:\\host\a.png",
    /// "http:host/a.png") must not reach WinUI's own loader, whose parser may read it as a web address too.
    static func isWebAddress(_ text: String) -> Bool {
        guard let scheme = URL(string: text)?.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    /// Starts loading the image at `url` into `image` (a WinUI Image). `failed` runs, on the main thread,
    /// when it cannot be shown before the image gets its bytes (the fetch failed, too many pixels, no
    /// image); after that, the image's own ImageOpened and ImageFailed tell. `what` names the element in
    /// the log ("AsyncImage 12"). False, with `failed` not called, when the fetch could not start.
    static func load(_ url: String, into image: WinUIObject, what: String, failed: @escaping @MainActor () -> Void) -> Bool {
        let box = PrivateImageBox(image: image, url: url, what: what, failed: failed)
        let context = Unmanaged.passRetained(box).toOpaque()
        if !actionUIWinUIFetchURLPrivately(url, maximumBytes, 120, privateImageFetched, context) {
            Unmanaged<PrivateImageBox>.fromOpaque(context).release()
            ActionUIModel.shared.logger.log("\(what): \(WinUIError.last("fetching \(url)"))", .warning)
            return false
        }
        return true
    }

    /// The fetch ended: the bytes shown when they are an image within the pixel cap.
    fileprivate static func finished(_ box: PrivateImageBox, data: Data?, failure: String?) {
        // The element moved on (another address, or gone): nothing to show.
        guard let image = box.image else { return }
        let logger = ActionUIModel.shared.logger
        guard let data, !data.isEmpty else {
            logger.log("\(box.what) not shown: \(box.url): \(failure ?? "no bytes")", .warning)
            box.failed()
            return
        }
        var shown = false
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let bytes = raw.bindMemory(to: UInt8.self).baseAddress else { return }
            var width: UInt32 = 0
            var height: UInt32 = 0
            // An SVG image, or bytes that are no image, give no size: not shown.
            guard actionUIWinUIImageDataGetSize(bytes, raw.count, &width, &height) else {
                logger.log("\(box.what) not shown: \(box.url): it is no bitmap image Windows reads (an SVG image from less-trusted content is not shown)", .warning)
                return
            }
            if ImageSource.isTooLarge(width: Int(width), height: Int(height)) {
                logger.log("\(box.what) not shown: \(box.url) is \(width) x \(height) pixels, more than \(ImageSource.maximumPixelCount)", .warning)
                return
            }
            shown = actionUIWinUIImageSetData(image.pointer, bytes, raw.count)
            if !shown {
                logger.log("\(box.what): \(WinUIError.last("showing \(box.url)"))", .warning)
            }
        }
        if !shown {
            box.failed()
        }
    }
}

/// One private image load: the image it is for (weak: a replaced or dropped image is not shown) and what
/// to do when it cannot be shown.
@MainActor private final class PrivateImageBox {
    weak var image: WinUIObject?
    let url: String
    let what: String
    let failed: @MainActor () -> Void

    init(image: WinUIObject, url: String, what: String, failed: @escaping @MainActor () -> Void) {
        self.image = image
        self.url = url
        self.what = what
        self.failed = failed
    }
}

private let privateImageFetched: ActionUIWinUIDataCompletion = { context, bytes, length, _, error in
    guard let context else { return }
    let data = bytes.map { Data(bytes: $0, count: length) }
    let failure = error.map { String(cString: $0) }
    let address = UInt(bitPattern: context)
    MainActor.assumeIsolated {
        guard let pointer = UnsafeMutableRawPointer(bitPattern: address) else { return }
        let box = Unmanaged<PrivateImageBox>.fromOpaque(pointer).takeRetainedValue()
        PrivateImage.finished(box, data: data, failure: failure)
    }
}
