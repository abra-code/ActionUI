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
}

class ImageHelper {
    // Creates a SwiftUI Image from a string and interpretation mode
    // Parameters:
    // - text: The string to interpret (e.g., SF Symbol name, asset name, file path)
    // - interpretation: "path", "systemName", "assetName", or "mixed"
    // Returns: A SwiftUI View (Image or fallback)
    // Design decision: Aligns with Image.swift, using SwiftUI.Image initializers and UTType for path validation
    static func makeImage(from text: String, interpretation: String) -> SwiftUI.Image {
        switch interpretation {
        case "systemName":
            return SwiftUI.Image(systemName: text)
        case "assetName":
            return SwiftUI.Image(text)
        case "path":
            if let filePath = validateFilePath(text) {
                return SwiftUI.Image(contentsOfFile: filePath)
            }
            return SwiftUI.Image(systemName: "photo")
        case "mixed":
            if text.contains("/") {
                if let filePath = validateFilePath(text) {
                    return SwiftUI.Image(contentsOfFile: filePath)
                }
            }
            #if canImport(UIKit)
            if UIImage(named: text) != nil {
                return SwiftUI.Image(text)
            }
            #elseif canImport(AppKit)
            if NSImage(named: text) != nil {
                return SwiftUI.Image(text)
            }
            #endif
            return SwiftUI.Image(systemName: text)
        default:
            return SwiftUI.Image(systemName: text)
        }
    }
    
    // Validates a file path for image or PDF content
    // Returns the file path if valid, nil otherwise
    // Design decision: Reuses Image.swift's UTType logic for consistency
    private static func validateFilePath(_ filePath: String) -> String? {
        let pathExtension = URL(fileURLWithPath: filePath).pathExtension
        if let uti = UTType(filenameExtension: pathExtension),
           uti.conforms(to: .image) || uti.conforms(to: .pdf) {
            return filePath
        }
        print("Warning: Image filePath '\(filePath)' is not an image or PDF; ignoring")
        return nil
    }
}
