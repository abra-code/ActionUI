// Core/Common/ResourceFolder+WindowsPaths.swift
/*
 How ActionUIResourceFolder.isFile reads a Windows path (ResourceFolder+Windows.swift uses it). Plain
 string rules, compiled on every system so their tests run everywhere.
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension ActionUIResourceFolder {
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
}
