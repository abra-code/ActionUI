// Sources/Runtime/AppBundle.swift
/*
 Where an app's resources are on Linux, which has no app bundles. An ActionUI app ships as a
 simplified iOS-style bundle: a folder holding the program and its resources side by side
 (documents, images), named `Name.app` by the convention carried over from Apple, not required.
 The bundle is the folder of the running program, unless the host names another
 (ActionUIResourceFolder: a development build pointing at its sources, a Python host, whose
 program is python3).

 - LoadableView `name`: a file of that name in the folder of the document holding the
   LoadableView (the file an enclosing LoadableView loaded, else the window's document), then in
   the bundle.
 - Image `resourceName`: a file of that name in the bundle.
 - Image `assetName`: the bundle is on the icon theme's search path, so an image file named after
   the asset (Orb.png) at the bundle's top level is found.
 - `Info.json` at the bundle's top level describes the app (AppInfo): its application ID, name and
   icon, used where the host sets none, as Info.plist does on Apple.
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
    /// The folder resources are looked up in: the host's (ActionUIResourceFolder), else the running
    /// program's folder; nil only when neither is known.
    static var folder: String? { ActionUIResourceFolder.path ?? programFolder }
    private static let programFolder = defaultFolder()

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

    // MARK: Info.json

    /// What `Info.json` in `folder` says about the app: nil when there is no such file, or it is
    /// not a JSON object of the expected keys (logged).
    static func info(in folder: String?) -> AppInfo? {
        guard let path = file("Info.json", in: folder) else { return nil }
        guard let data = FileManager.default.contents(atPath: path) else {
            ActionUIModel.shared.logger.log("\(path) could not be read; it is ignored", .warning)
            return nil
        }
        do {
            return try JSONDecoder().decode(AppInfo.self, from: data)
        } catch {
            ActionUIModel.shared.logger.log("\(path) is not a JSON object of strings applicationID, name and icon (\(error)); it is ignored", .warning)
            return nil
        }
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

/// An app's `Info.json`. Other keys (a desktop entry's summary and categories) are for the tools
/// that install the app; the runtime does not read them.
struct AppInfo: Decodable, Equatable {
    /// The reverse-DNS application ID.
    var applicationID: String?
    /// The application's name.
    var name: String?
    /// The windows' icon: a PNG or SVG file in the bundle (a path relative to it), else an icon
    /// theme name or an absolute path.
    var icon: String?

    private enum CodingKeys: String, CodingKey {
        case applicationID, name, icon
    }

    /// The icon as AdwaitaApplication takes it: the path of the file at `icon` relative to
    /// `folder`, else the value itself.
    func iconValue(in folder: String?) -> String? {
        guard let icon else { return nil }
        if let folder, !icon.hasPrefix("/") {
            let path = URL(fileURLWithPath: folder).appendingPathComponent(icon).path
            if g_file_test(path, G_FILE_TEST_IS_REGULAR) != 0 { return path }
        }
        return icon
    }
}

extension AppInfo {
    /// An empty string counts as a key left out (a template not filled in).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func value(_ key: CodingKeys) throws -> String? {
            try container.decodeIfPresent(String.self, forKey: key).flatMap { $0.isEmpty ? nil : $0 }
        }
        self.init(applicationID: try value(.applicationID), name: try value(.name), icon: try value(.icon))
    }
}
