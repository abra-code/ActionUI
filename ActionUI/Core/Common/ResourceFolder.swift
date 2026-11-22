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

    /// The path of the file `name` (with its extension) in the folder, when there is a regular file
    /// there. A name with "/" (or, on Windows, "\" or ":") is refused, so a lookup stays in the
    /// folder.
    public static func file(_ name: String) -> String? {
        guard let path, !name.isEmpty, !name.contains("/") else { return nil }
        #if os(Windows)
        guard !name.contains("\\"), !name.contains(":") else { return nil }
        #endif
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
        #if os(Windows)
        return isFileOnWindows(url, inside: folder)
        #else
        let root = URL(fileURLWithPath: folder).resolvingSymlinksInPath().standardizedFileURL.path
        guard root != "/" else { return false }
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        let prefix = root.hasSuffix("/") ? root : root + "/"
        // By bytes, as the file system compares names: String's hasPrefix takes an accented letter
        // and the same letter followed by a combining accent as equal, so a sibling folder spelled
        // the other way would pass.
        return path.utf8.starts(with: prefix.utf8)
        #endif
    }

    /// isFile on Windows, where a path has more forms (compiled everywhere, so its tests run on every
    /// system; used only on Windows). Compared as windowsKey writes them (separators
    /// as "/", ASCII letters without case, as NTFS compares names); a path or folder in another form
    /// is outside. A drive's root or a share's root holds nothing, as "/" does. A file on a share is
    /// inside only a folder on that share, as written: its path is not resolved otherwise, since
    /// resolving it opens it (CreateFileW), which asks the server, with the user's credentials.
    static func isFileOnWindows(_ url: URL, inside folder: String) -> Bool {
        let folderURL = URL(fileURLWithPath: folder)
        guard let givenPath = windowsKey(url.path), let givenRoot = windowsKey(folderURL.path) else { return false }
        if givenPath.hasPrefix("//"), !givenPath.utf8.starts(with: (givenRoot + "/").utf8) {
            return false
        }
        guard let root = windowsKey(folderURL.resolvingSymlinksInPath().standardizedFileURL.path),
              let path = windowsKey(url.resolvingSymlinksInPath().standardizedFileURL.path),
              holdsFiles(root) else { return false }
        // By bytes, as on other systems (only ASCII letters were folded).
        return path.utf8.starts(with: (root + "/").utf8)
    }

    /// A Windows path as isFile compares it: "\" as "/"; a file URL's "/C:/x" as "C:/x"; the ASCII
    /// letters in lower case (NTFS compares names without case; folding only ASCII never takes two
    /// names Windows tells apart for one); no trailing "/". nil for a form that is not plainly a
    /// file under a drive ("C:/...") or a share ("//server/share/..."): the \\?\, \\.\ and \??\
    /// namespaces (devices, and paths Windows does not normalize), a drive-relative path ("C:x", on
    /// the drive's own current folder), a ":" after the drive (an alternate data stream, or a
    /// drive-relative path that Foundation put under the current folder), and a device name as a
    /// component (isDeviceName).
    static func windowsKey(_ path: String) -> String? {
        var characters = path.map { $0 == "\\" ? "/" : $0 }
        func isDriveLetter(_ character: Character) -> Bool {
            character.isASCII && character.isLetter
        }
        if characters.count >= 3, characters[0] == "/", isDriveLetter(characters[1]), characters[2] == ":" {
            characters.removeFirst()
        }
        let text = String(characters)
        if text.hasPrefix("//?/") || text.hasPrefix("//./") || text.hasPrefix("/??/") {
            return nil
        }
        let isDrive = characters.count >= 3 && isDriveLetter(characters[0]) && characters[1] == ":" && characters[2] == "/"
        let isShare = text.hasPrefix("//") && !text.hasPrefix("///")
        guard isDrive || isShare else { return nil }
        guard !characters.dropFirst(isDrive ? 2 : 0).contains(":") else { return nil }
        // A device name as a component ("C:/app/res/COM1", "NUL.json"): Windows opens the device, and
        // resolving the path (which opens it) would reach the device.
        guard !text.split(separator: "/").contains(where: { isDeviceName(String($0)) }) else { return nil }
        var key = String(characters.map { $0.isASCII ? Character($0.lowercased()) : $0 })
        while key.hasSuffix("/"), key.count > 1 {
            key.removeLast()
        }
        return key
    }

    /// Whether `component` is a name Windows reads as a device (CON, PRN, AUX, NUL, COM1 to COM9, LPT1
    /// to LPT9, with the superscript digits too, CONIN$, CONOUT$), whatever follows its first dot and
    /// in any case.
    static func isDeviceName(_ component: String) -> Bool {
        var name = String(component.prefix { $0 != "." }).uppercased()
        while name.hasSuffix(" ") {
            name.removeLast()
        }
        if ["CON", "PRN", "AUX", "NUL", "CONIN$", "CONOUT$"].contains(name) {
            return true
        }
        guard name.count == 4, name.hasPrefix("COM") || name.hasPrefix("LPT"), let digit = name.last else { return false }
        return "123456789\u{00B9}\u{00B2}\u{00B3}".contains(digit)
    }

    /// Whether a windowsKey names a folder below a drive's or a share's root.
    static func holdsFiles(_ key: String) -> Bool {
        let components = key.split(separator: "/")
        return key.hasPrefix("//") ? components.count >= 3 : components.count >= 2
    }

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
