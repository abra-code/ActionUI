/*
 ImageHelper provides utility functions for creating SwiftUI Image views from string data.
 Used by List and Table for rendering Image views, consistent with Image component.
 */

import SwiftUI
import UniformTypeIdentifiers
import ImageIO
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

extension SwiftUI.Image {
    // Initializes a SwiftUI Image from a file path
    // Parameters:
    // - contentsOfFile: The file path to the image resource
    // Returns: SwiftUI.Image using UIImage (UIKit) or NSImage (AppKit), or a fallback system image
    // Design decision: Uses canImport for platform portability, with fallback to "photo" SF Symbol
    // Only a regular file is opened (Image and Canvas filePath, resource files): a document names
    // the path, and a device such as /dev/zero or a named pipe would never finish (or never begin)
    // reading on the main thread.
    init(contentsOfFile requestedPath: String) {
        guard let contentsOfFile = ActionUIDocumentLoader.regularFilePath(URL(fileURLWithPath: requestedPath)),
              !ImageHelper.declaresTooManyPixels(contentsOfFile) else {
            self.init(systemName: "photo")
            return
        }
        #if canImport(UIKit)
        if let uiImage = UIImage(contentsOfFile: contentsOfFile) {
            self.init(uiImage: uiImage)
        } else {
            self.init(systemName: "photo")
        }
        #elseif canImport(AppKit)
        if let nsImage = NSImage(contentsOfFile: contentsOfFile) {
            self.init(nsImage: nsImage)
        } else {
            self.init(systemName: "photo")
        }
        #else
        self.init(systemName: "photo")
        #endif
    }
    
    // Initializes a SwiftUI Image from a string and interpretation mode
    // Parameters:
    // - text: The string to interpret (e.g., SF Symbol name, asset name, file path)
    // - interpretation: "path", "systemName", "assetName", "resourceName", or "mixed"
    //   (what the text names is decided by ImageSource.resolve, Core/Helpers/ImageSource.swift)
    init(from text: String, interpretation: String) {
        switch ImageSource.resolve(text, interpretation: interpretation, lookup: ImageHelper.lookup) {
        case .filePath(let filePath):
            self.init(contentsOfFile: filePath)
        case .systemName(let systemName):
            self.init(systemName: systemName)
        case .assetName(let name):
            self.init(name)
        }
    }
}

class ImageHelper {
    /// Whether the image file at `path` declares more pixels than ImageSource.maximumPixelCount, read
    /// from its header without decoding it (ImageIO). A file ImageIO cannot size (a vector PDF, an
    /// unknown format) goes on to the decoder. Logged.
    static func declaresTooManyPixels(_ path: String) -> Bool {
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              ImageSource.isTooLarge(width: width, height: height) else { return false }
        // Once per path: a view body, and a Canvas on every draw, asks again each time.
        guard loggedLock.withLock({ loggedTooLarge.insert(path).inserted }) else { return true }
        // Images are built off the main actor too; the model's logger is the main actor's.
        Task { @MainActor in
            ActionUIModel.shared.logger.log("Image not shown: \(path) is \(width) x \(height) pixels, more than \(ImageSource.maximumPixelCount)", .warning)
        }
        return true
    }

    /// The paths already logged as over the decode cap, behind loggedLock (images are built on
    /// more than one thread).
    nonisolated(unsafe) private static var loggedTooLarge: Set<String> = []
    private static let loggedLock = Lock()

    /// The platform checks of ImageSource.resolve: file types by UTType, resources in the host's
    /// resource folder (ActionUIResourceFolder) then the main bundle, assets by UIImage(named:) or
    /// NSImage(named:).
    static var lookup: ImageSource.Lookup {
        ImageSource.Lookup(
            isImageFile: { validateImageFilePath($0) != nil },
            resourcePath: { ActionUIResourceFolder.file($0) ?? ActionUIResourceFolder.bundlePath(forResource: $0, ofType: nil) },
            assetExists: { name in
#if canImport(UIKit)
                UIImage(named: name) != nil
#elseif canImport(AppKit)
                NSImage(named: name) != nil
#else
                true
#endif
            }
        )
    }

    // Validates a file path for image or PDF content
    // Returns the file path if valid, nil otherwise
    // Design decision: Reuses Image.swift's UTType logic for consistency
    internal static func validateImageFilePath(_ filePath: String) -> String? {
        let pathExtension = URL(fileURLWithPath: filePath).pathExtension
        if let uti = UTType(filenameExtension: pathExtension),
           uti.conforms(to: .image) || uti.conforms(to: .pdf) {
            return filePath
        }
        return nil
    }
}
