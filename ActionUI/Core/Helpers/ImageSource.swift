// Core/Helpers/ImageSource.swift
/*
 What an image string names: a file to load, a symbol, or a named (asset) image. Image's runtime
 value, a List row and a Table cell give an image as text with an interpretation ("path",
 "systemName", "assetName", "resourceName" or "mixed"); resolve decides what the text names. The
 checks that need the platform (is this an image file, where is a bundled resource, is there an
 asset of that name) come from the renderer in a Lookup.

 (The SwiftUI images are made in Helpers/ImageHelper.swift.)
*/

enum ImageSource: Equatable, Sendable {
    case filePath(String)
    case systemName(String)
    case assetName(String)

    /// The platform checks `resolve` needs.
    struct Lookup {
        /// Whether a file at this path, judged by its name, holds an image or a PDF.
        var isImageFile: (String) -> Bool
        /// The path of a resource of this name (with its extension) bundled with the program.
        var resourcePath: (String) -> String?
        /// Whether a named image (an asset) of this name exists.
        var assetExists: (String) -> Bool
    }

    /// The symbol shown for a path that is not an image file.
    static let placeholderSymbol = "photo"

    /// What `text` names under `interpretation`:
    ///  - "systemName": the symbol `text`;
    ///  - "assetName": the asset `text`;
    ///  - "resourceName": the bundled resource `text`, else the asset `text`;
    ///  - "path": the file `text` when it is an image file, else the placeholder symbol;
    ///  - "mixed" and anything else: a text with a "/" is a path as above; else a bundled resource
    ///    when the name is that of an image file; else the asset `text` when one exists; else the
    ///    symbol `text`.
    static func resolve(_ text: String, interpretation: String, lookup: Lookup) -> ImageSource {
        switch interpretation {
        case "systemName":
            return .systemName(text)
        case "assetName":
            return .assetName(text)
        case "resourceName":
            return lookup.resourcePath(text).map(ImageSource.filePath) ?? .assetName(text)
        case "path":
            return lookup.isImageFile(text) ? .filePath(text) : .systemName(placeholderSymbol)
        default:
            if text.contains("/") {
                return lookup.isImageFile(text) ? .filePath(text) : .systemName(placeholderSymbol)
            }
            if lookup.isImageFile(text), let resourcePath = lookup.resourcePath(text) {
                return .filePath(resourcePath)
            }
            return lookup.assetExists(text) ? .assetName(text) : .systemName(text)
        }
    }
}
