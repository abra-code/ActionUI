// Core/Common/ResourceFolder+POSIX.swift
/*
 ActionUIResourceFolder's file lookups on Apple platforms and Linux, where "/" is the one separator
 and a path has one form. Windows, where a name has more separators and a path more forms, has its
 own (ResourceFolder+Windows.swift).
*/

#if !os(Windows)

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension ActionUIResourceFolder {
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
}

#endif
