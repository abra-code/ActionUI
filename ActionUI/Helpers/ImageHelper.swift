/*
 ImageHelper provides utility functions for creating SwiftUI Image views from string data.
 Used by List and Table for rendering Image views, consistent with Image component.
 */

import SwiftUI
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

struct Point: Codable {
    let row: Int
    let column: Int
}

extension SwiftUI.Image {
    // Initializes a SwiftUI Image from a file path
    // Parameters:
    // - contentsOfFile: The file path to the image resource
    // Returns: SwiftUI.Image using UIImage (UIKit) or NSImage (AppKit), or a fallback system image
    // Design decision: Uses canImport for platform portability, with fallback to "photo" SF Symbol
    init(contentsOfFile: String) {
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
    /// The platform checks of ImageSource.resolve: file types by UTType, resources in the main
    /// bundle, assets by UIImage(named:) or NSImage(named:).
    static var lookup: ImageSource.Lookup {
        ImageSource.Lookup(
            isImageFile: { validateImageFilePath($0) != nil },
            resourcePath: { Bundle.main.path(forResource: $0, ofType: nil) },
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
