// Core/Common/ResourceFolder.swift
/*
 The folder of an app's resources as its host names it (actionUIAppSetResourceFolder). A host whose
 program is an interpreter (a Python or Node script, unbundled) has no bundle of its own: on Apple
 Bundle.main is the interpreter's, on Linux the program's folder is the interpreter's, so the host
 names its script's folder. It is looked up before the platform's own place:
 - Apple: LoadableView names, Image resourceName and WebView userScript resourceName are found here
   first, then in Bundle.main.
 - Linux: the app's bundle is this folder when set, else the running program's folder (AppBundle).
 nil (the default) leaves only the platform's own place.

 Set on the main thread by the host; read while views are built, which for images is not
 main-actor isolated, so the value is behind a lock.
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

public enum ActionUIResourceFolder {
    private static let lock = Lock()
    nonisolated(unsafe) private static var storedPath: String?

    /// The folder the host named; nil: none (the platform's own place only).
    public static var path: String? {
        get { lock.withLock { storedPath } }
        set { lock.withLock { storedPath = newValue } }
    }

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
}
