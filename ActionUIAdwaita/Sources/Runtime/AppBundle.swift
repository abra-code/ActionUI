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
 - `Info.plist` describes the app (AppInfo), as on Apple: its application ID, name and icon
   (CFBundleIdentifier, CFBundleDisplayName or CFBundleName, CFBundleIconFile), used where the
   host sets none. It is at the bundle's top level, or in `Contents` when the bundle has the macOS
   layout (the program in `Contents/Linux`, the resources in `Contents/Resources`).
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import CAdwaita
import Glibc

@MainActor
package enum AppBundle {
    /// The folder resources are looked up in: the host's (ActionUIResourceFolder), else the running
    /// program's folder; nil only when neither is known.
    package static var folder: String? { ActionUIResourceFolder.path ?? programFolder }
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
        return g_file_test(path, fileTestIsRegular) != 0 ? path : nil
    }

    /// A resource in the bundle, by its name with its extension.
    static func resource(_ name: String) -> String? {
        file(name, in: folder)
    }

    // MARK: Info.plist

    /// Where an app's `Info.plist` is, and the resources folder its icon is looked up in, for a
    /// bundle folder (AppBundle.folder): `Info.plist` at the folder's top level, the resources
    /// beside it (the flat layout); else, for a folder that is `Contents/Linux` (the program's) or
    /// `Contents/Resources` of the macOS layout, `Contents/Info.plist` and `Contents/Resources`.
    /// nil when there is no `Info.plist` in either place.
    package static func infoLocation(for folder: String?) -> (plist: String, resources: String)? {
        guard let folder else { return nil }
        if let plist = file("Info.plist", in: folder) { return (plist, folder) }
        let url = URL(fileURLWithPath: folder).standardizedFileURL
        let contents = url.deletingLastPathComponent()
        guard ["Linux", "Resources"].contains(url.lastPathComponent), contents.lastPathComponent == "Contents",
              let plist = file("Info.plist", in: contents.path) else { return nil }
        return (plist, contents.appendingPathComponent("Resources").path)
    }

    /// What the app's `Info.plist` says about it (see infoLocation): nil when there is none, or it
    /// is not a property list whose keys read are strings (logged).
    package static func info(in folder: String?) -> AppInfo? {
        guard let location = infoLocation(for: folder) else { return nil }
        guard let data = FileManager.default.contents(atPath: location.plist) else {
            ActionUIModel.shared.logger.log("\(location.plist) could not be read; it is ignored", .warning)
            return nil
        }
        do {
            var info = try PropertyListDecoder().decode(AppInfo.self, from: data)
            info.resources = location.resources
            return info
        } catch {
            ActionUIModel.shared.logger.log("\(location.plist) is not a property list whose CFBundleIdentifier, CFBundleDisplayName, CFBundleName and CFBundleIconFile are strings (\(error)); it is ignored", .warning)
            return nil
        }
    }

    // MARK: Documents

    /// Records the folder of the document a window shows (nil: not from a file).
    package static func setDocumentFolder(_ folder: String?, window windowUUID: String) {
        documentFolders[windowUUID] = folder
    }

    static func documentFolder(window windowUUID: String) -> String? {
        documentFolders[windowUUID]
    }

    /// A document's format by its URL ("json" or "plist"), as Core reads it (ActionUIDocumentLoader),
    /// for the application module: Core is also built for Apple, where it takes no package access.
    package static func documentFormat(of url: URL) -> String {
        ActionUIDocumentLoader.format(of: url)
    }

    // MARK: Icon theme

    /// Puts the bundle on the icon theme's search path, once per folder.
    package static func addToIconTheme() {
        guard let folder, !iconFoldersAdded.contains(folder), let display = gdk_display_get_default() else { return }
        iconFoldersAdded.insert(folder)
        gtk_icon_theme_add_search_path(gtk_icon_theme_get_for_display(display), folder)
    }
}

/// What the runtime reads of an app's `Info.plist`, the same file and keys as on Apple. Other keys
/// are for the tools that install the app (the desktop entry's LinuxDesktopComment and
/// LinuxDesktopCategories, Scripts/linux-app-entry.py); the runtime does not read them.
package struct AppInfo: Decodable, Equatable {
    /// The reverse-DNS application ID: CFBundleIdentifier.
    package var applicationID: String?
    /// The application's name: CFBundleDisplayName, else CFBundleName.
    package var name: String?
    /// CFBundleIconFile: the icon's file name in the resources, its extension optional.
    package var iconFile: String?
    /// The resources folder the icon is looked up in (set by AppBundle.info, not read).
    package var resources: String?

    private enum CodingKeys: String, CodingKey {
        case CFBundleIdentifier, CFBundleDisplayName, CFBundleName, CFBundleIconFile
    }

    /// The icon as AdwaitaApplication takes it, the path of a PNG or SVG file in the resources
    /// (GTK reads no .icns): the file CFBundleIconFile names when it is one, else its name with
    /// the extension .svg, then .png. nil when there is none.
    package func iconValue() -> String? {
        guard let iconFile, let resources, !iconFile.contains("/") else { return nil }
        let named = URL(fileURLWithPath: resources).appendingPathComponent(iconFile)
        let base = named.deletingPathExtension()
        var candidates: [URL] = []
        if ["svg", "png"].contains(named.pathExtension.lowercased()) { candidates.append(named) }
        candidates += [base.appendingPathExtension("svg"), base.appendingPathExtension("png")]
        return candidates.map(\.path).first { g_file_test($0, fileTestIsRegular) != 0 }
    }
}

extension AppInfo {
    /// An empty string counts as a key left out (a template not filled in).
    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func value(_ key: CodingKeys) throws -> String? {
            try container.decodeIfPresent(String.self, forKey: key).flatMap { $0.isEmpty ? nil : $0 }
        }
        // Both names are read, so a wrong type in either fails alike (as in linux-app-entry.py)
        let displayName = try value(.CFBundleDisplayName)
        let bundleName = try value(.CFBundleName)
        self.init(applicationID: try value(.CFBundleIdentifier), name: displayName ?? bundleName,
                  iconFile: try value(.CFBundleIconFile))
    }
}
