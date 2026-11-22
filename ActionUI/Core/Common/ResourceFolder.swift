// Core/Common/ResourceFolder.swift
/*
 The folder of an app's resources as its host names it (actionUIAppSetResourceFolder). A host whose
 program is an interpreter (a Python or Node script, unbundled) has no bundle of its own: on Apple
 Bundle.main is the interpreter's, on Linux the program's folder is the interpreter's, so the host
 names its script's folder. It is looked up before the platform's own place:
 - Apple: LoadableView names, Image resourceName and WebView userScript resourceName are found here
   first, then in Bundle.main; a name with "/" is found in neither.
 - Linux: the app's bundle is this folder when set, else the running program's folder (AppBundle).
 nil (the default) leaves only the platform's own place.

 It is the configuration's resourceFolder (ActionUIConfiguration): setting it here is the same,
 and fixed with the rest of the configuration once a window has loaded its ActionUI JSON.
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

public enum ActionUIResourceFolder {
    /// The folder the host named; nil: none (the platform's own place only). Setting it once the
    /// configuration is fixed, or to "", is refused and logged (ActionUIConfiguration.update).
    public static var path: String? {
        get { ActionUIConfiguration.current.resourceFolder }
        set {
            do {
                try ActionUIConfiguration.update { $0.resourceFolder = newValue }
            } catch {
                let message = "The resource folder was not set to \(newValue ?? "none"): \(error)"
                Task { @MainActor in ActionUIModel.shared.logger.log(message, .error) }
            }
        }
    }

    #if !os(Windows) // Windows: ResourceFolder+Windows.swift
    /// The path of the file `name` (with its extension) in the folder, when there is a regular file
    /// there. A name with "/" is refused, so a lookup stays in the folder.
    public static func file(_ name: String) -> String? {
        guard let path, !name.isEmpty, !name.contains("/") else { return nil }
        let file = URL(fileURLWithPath: path).appendingPathComponent(name).path
        #if canImport(Darwin)
        var isFolder: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: file, isDirectory: &isFolder)
        return exists && !isFolder.boolValue ? file : nil
        #else
        var isFolder = false
        let exists = FileManager.default.fileExists(atPath: file, isDirectory: &isFolder)
        return exists && !isFolder ? file : nil
        #endif
    }

    /// Whether `url` names a file inside `folder` (at any depth), both with symbolic links followed
    /// and standardized. A folder that is the root of the file system holds nothing: it would trust
    /// every file. The test JSONContentOrigin uses for the app's resources, for a host's own folders too.
    public static func isFile(_ url: URL, inside folder: String) -> Bool {
        guard !folder.isEmpty else { return false }
        let root = URL(fileURLWithPath: folder).resolvingSymlinksInPath().standardizedFileURL.path
        guard root != "/" else { return false }
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        let prefix = root.hasSuffix("/") ? root : root + "/"
        // By bytes, as the file system compares names: String's hasPrefix takes an accented letter
        // and the same letter followed by a combining accent as equal, so a sibling folder spelled
        // the other way would pass.
        return path.utf8.starts(with: prefix.utf8)
    }
    #endif

    #if !canImport(FoundationEssentials)
    /// The path of the resource `name` (with `type` as its extension, or none) in the main bundle,
    /// refused for a name with "/" as file(_:) refuses one: it is a name, not a path, and
    /// Bundle.main.path(forResource:) keeps a name's "..", so a document could reach any file.
    static func bundlePath(forResource name: String, ofType type: String?) -> String? {
        guard !name.contains("/") else { return nil }
        return Bundle.main.path(forResource: name, ofType: type)
    }
    #endif
}
