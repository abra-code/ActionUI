// Core/Common/DocumentLoader.swift
/*
 Loading a description into a window, without the views: where a LoadableView's text points (a
 remote URL, a file, a bundled resource), the format of a file or URL, loading the data as the
 window's content or as a sub-view of a LoadableView, and firing a LoadableView's viewDidLoadActionID
 once per source.

 (The SwiftUI views are FileLoadableView and RemoteLoadableView, in Common/.)
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

@MainActor
enum ActionUIDocumentLoader {

    /// Where a LoadableView's text points.
    enum Source: Equatable {
        case remote(URL)
        case file(URL)
    }

    /// The source a LoadableView's text names, or the message to show when it names none:
    ///  - "http://" or "https://" (any case): a remote URL;
    ///  - "file://" (any case): that file URL, which must have a path;
    ///  - a text with "/": a file path;
    ///  - anything else: a resource bundled with the program, by name with its extension, else with
    ///    ".json", else ".plist" (".json" when the name ends in ".plist"). `bundleURL(name, extension)`
    ///    finds a bundled resource.
    static func source(
        for value: String,
        bundleURL: (String, String) -> URL?,
        logger: any ActionUILogger
    ) -> Result<Source, SourceError> {
        if value.lowercased().hasPrefix("http://") || value.lowercased().hasPrefix("https://") {
            guard let url = URL(string: value) else {
                logger.log("Invalid URL: \(value)", .warning)
                return .failure(SourceError(message: "Invalid URL: \(value)"))
            }
            logger.log("Interpreting value as remote URL: \(value)", .debug)
            return .success(.remote(url))
        }
        if value.lowercased().hasPrefix("file://") {
            guard let url = URL(string: value), !url.path.isEmpty else {
                logger.log("Invalid file URL: \(value)", .warning)
                return .failure(SourceError(message: "Invalid file URL: \(value)"))
            }
            logger.log("Interpreting value as file URL: \(value)", .debug)
            return .success(.file(url))
        }
        if value.contains("/") {
            logger.log("Interpreting value as filePath: \(value)", .debug)
            return .success(.file(URL(fileURLWithPath: value)))
        }
        let ext = URL(fileURLWithPath: value).pathExtension.lowercased()
#if canImport(FoundationEssentials)
        let resourceName = ext.isEmpty ? value : value.replacing(".\(ext)", with: "")
#else
        // Foundation's replace, as before: `replacing` matches by Character and misses ".json"
        // next to a prepended, spacing or joining mark ("a\u{600}.json", "a.json\u{93E}.json").
        let resourceName = ext.isEmpty ? value : value.replacingOccurrences(of: ".\(ext)", with: "")
#endif
        let bundleExt = ext.isEmpty ? "json" : ext
        guard let url = bundleURL(resourceName, bundleExt) ??
                        bundleURL(resourceName, bundleExt == "json" ? "plist" : "json") else {
            logger.log("Bundle resource '\(value)' not found with .json or .plist", .warning)
            return .failure(SourceError(message: "Bundle resource '\(value)' not found"))
        }
        logger.log("Interpreting value as bundle name: \(value)", .debug)
        return .success(.file(url))
    }

    /// Why a LoadableView's text names no source, as the text to show in its place.
    struct SourceError: Error, Equatable {
        let message: String
    }

    /// "plist" for a file or URL whose name ends in ".plist" (any case), else "json".
    static func format(of url: URL) -> String {
        url.pathExtension.lowercased() == "plist" ? "plist" : "json"
    }

    /// Loads `data` as the window's content (`isContentView`) or as the sub-view of the LoadableView
    /// `parentID`, and returns its root element.
    static func load(
        data: Data,
        format: String,
        windowUUID: String,
        isContentView: Bool,
        parentID: Int
    ) throws -> ActionUIElement {
        if isContentView {
            return try ActionUIModel.shared.loadDescription(from: data, format: format, windowUUID: windowUUID)
        }
        return try ActionUIModel.shared.loadSubViewDescription(from: data, format: format, windowUUID: windowUUID, parentID: parentID)
    }

    /// Fetches `url` with `fetch`, then loads it as `load` does, with the format of the URL.
    static func loadRemote(
        url: URL,
        windowUUID: String,
        isContentView: Bool,
        parentID: Int,
        logger: any ActionUILogger,
        fetch: (URL) async throws -> Data
    ) async throws -> ActionUIElement {
        let data = try await fetch(url)
        let format = format(of: url)
        logger.log("Determined format '\(format)' for remote URL \(url)", .debug)
        let element = try load(data: data, format: format, windowUUID: windowUUID, isContentView: isContentView, parentID: parentID)
        logger.log("Successfully loaded \(format) for LoadableView from remote \(url)", .debug)
        return element
    }

    /// Fires a LoadableView's viewDidLoadActionID once per source: again only when the LoadableView
    /// `parentID` of the window loads a different source. Kept outside the view models, whose
    /// observed states would render the view again.
    @MainActor
    final class ViewDidLoad {
        private var loadedSources: [String: String] = [:]

        /// Fires `actionID` (viewID `parentID`, viewPartID 0) unless there is none, the window has no
        /// such element, or this source was the last one fired for it.
        func fire(source: String, windowUUID: String, parentID: Int, actionID: String?) {
            guard let actionID else { return }
            guard ActionUIModel.shared.windowModels[windowUUID]?.viewModels[parentID] != nil else { return }

            let key = "\(windowUUID)_\(parentID)"
            guard loadedSources[key] != source else { return }
            loadedSources[key] = source
            ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: parentID, viewPartID: 0)
        }
    }
}
