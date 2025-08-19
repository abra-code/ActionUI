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
    // - interpretation: "path", "systemName", "assetName", or "mixed"
    init(from text: String, interpretation: String) {
        var systemName: String?
        var filePath: String?
        
        switch interpretation {
        case "systemName":
            systemName = text
        case "assetName":
            break // assetName = text
        case "path":
            filePath = ImageHelper.validateImageFilePath(text)
            if filePath == nil {
                systemName = "photo"
            }
        case "mixed": // mixed on unspecified/unknown inpterpreation falls to check all possibilities
            fallthrough
        default:
            if text.contains("/") {
                filePath = ImageHelper.validateImageFilePath(text)
                if filePath == nil {
                    systemName = "photo"
                }
            }
            
            if filePath == nil, systemName == nil { // try if we can find bundled asset of that name
#if canImport(UIKit)
                if UIImage(named: text) != nil {
                    // assetName = text
                } else {
                    systemName = text
                }
#elseif canImport(AppKit)
                if NSImage(named: text) != nil {
                    // assetName = text
                } else {
                    systemName = text
                }
#endif
            }
        }
        
        if let filePath = filePath {
            self.init(contentsOfFile: filePath)
        }
        else if let systemName = systemName {
            self.init(systemName: systemName)
        }
        else {
            self.init(text)
        }
    }
}

class ImageHelper {
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
