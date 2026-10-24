// Sources/Runtime/AppBundle.swift
/*
 Where an app's resources are on Linux, which has no app bundles. An ActionUI app ships as a
 simplified iOS-style bundle: a folder holding the program and its resources side by side
 (documents, images), named `Name.app` by the convention carried over from Apple, not required.
 The bundle is the folder of the running program; a host can set another (a development build
 pointing at its sources, a Python host, whose program is python3) or none.

 - LoadableView `name`: a file of that name in the folder of the document holding the
   LoadableView (the file an enclosing LoadableView loaded, else the window's document), then in
   the bundle.
 - Image `resourceName`: a file of that name in the bundle.
 - Image `assetName`: the bundle is on the icon theme's search path, so an image file named after
   the asset (Orb.png) at the bundle's top level is found.
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import CAdwaita
import Glibc

@MainActor
enum AppBundle {
    /// The folder resources are looked up in; nil: none.
    static var folder: String? = defaultFolder()

    /// The folder of each window's document, by window, when it came from a file.
    private static var documentFolders: [String: String] = [:]
    /// The bundle folders put on the icon theme's search path (GTK has no way to take one off).
    private static var iconFoldersAdded: Set<String> = []

    /// The running program's folder (nil only when it cannot be found).
    static func defaultFolder() -> String? {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX) + 1)
        let length = readlink("/proc/self/exe", &buffer, buffer.count - 1)
        guard length > 0 else { return nil }
        let path = String(decoding: buffer[0..<length].map { UInt8(bitPattern: $0) }, as: UTF8.self)
        let folder = URL(fileURLWithPath: path).deletingLastPathComponent()
        return folder.path
    }

    /// The path of the file `name` in `folder`, when there is a regular file there.
    static func file(_ name: String, in folder: String?) -> String? {
        guard let folder, !name.isEmpty, !name.contains("/") else { return nil }
        let path = URL(fileURLWithPath: folder).appendingPathComponent(name).path
        return g_file_test(path, G_FILE_TEST_IS_REGULAR) != 0 ? path : nil
    }

    /// A resource in the bundle, by its name with its extension.
    static func resource(_ name: String) -> String? {
        file(name, in: folder)
    }

    // MARK: Documents

    /// Records the folder of the document a window shows (nil: not from a file).
    static func setDocumentFolder(_ folder: String?, window windowUUID: String) {
        documentFolders[windowUUID] = folder
    }

    static func documentFolder(window windowUUID: String) -> String? {
        documentFolders[windowUUID]
    }

    // MARK: Icon theme

    /// Puts the bundle on the icon theme's search path, once per folder.
    static func addToIconTheme() {
        guard let folder, !iconFoldersAdded.contains(folder), let display = gdk_display_get_default() else { return }
        iconFoldersAdded.insert(folder)
        gtk_icon_theme_add_search_path(gtk_icon_theme_get_for_display(display), folder)
    }
}
