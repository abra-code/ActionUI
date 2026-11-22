// Core/Common/ResourceFolder+Windows.swift
/*
 ActionUIResourceFolder's file lookups on Windows, where a name has more separators and a path more
 forms (ResourceFolder+WindowsPaths.swift). ResourceFolder.swift has them on Apple and Linux.
*/

#if os(Windows)

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension ActionUIResourceFolder {
    /// The path of the file `name` (with its extension) in the folder, when there is a regular file
    /// there. A name with "/", "\" or ":" (a drive, or an alternate data stream) is refused, so a
    /// lookup stays in the folder.
    public static func file(_ name: String) -> String? {
        guard let path, !name.isEmpty, !name.contains("/"), !name.contains("\\"), !name.contains(":") else { return nil }
        let file = URL(fileURLWithPath: path).appendingPathComponent(name).path
        // FoundationEssentials takes a Bool here, not an ObjCBool (which it does not have).
        var isFolder = false
        let exists = FileManager.default.fileExists(atPath: file, isDirectory: &isFolder)
        return exists && !isFolder ? file : nil
    }

    /// Whether `url` names a file inside `folder` (at any depth), compared as isFileOnWindows
    /// compares Windows paths. A drive's or a share's root holds nothing: it would trust every file.
    /// The test JSONContentOrigin uses for the app's resources, for a host's own folders too.
    public static func isFile(_ url: URL, inside folder: String) -> Bool {
        guard !folder.isEmpty else { return false }
        return isFileOnWindows(url, inside: folder)
    }
}

#endif
