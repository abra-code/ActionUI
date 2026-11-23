// Sources/Runtime/LinkTrust.swift
/*
 What a part of a window may do by the host's trust policy (ActionUIModel.allows), as on Linux
 (LinkTrust.swift there): Link asks it before opening an address; Image, List and Table image cells,
 Canvas images, AsyncImage and VideoPlayer before reading a local file. The element asked about is the
 node's own; a template row's elements are blueprints with view models of their own, not the
 window's, and take their container's origin. A node whose view model is not the window's one for
 its id (a template's id that matches another element's, a node about to be replaced) counts as less
 trusted.

 The app's own resources, whose ActionUI JSON is trusted: the folder the host names
 (ActionUIResourceFolder), else the running program's folder, which an installed Windows app's
 files ship in (resourceFolders).
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import CWinUI

@MainActor
enum LinkTrust {
    /// Whether the node's content may open `uri`; a refusal is logged. An address that does not
    /// parse opens only from trusted content.
    static func allows(_ uri: String, _ node: RenderNode) -> Bool {
        let viewID = originElementID(node)
        let windowUUID = node.windowModel.windowUUID
        let allowed: Bool
        if let url = URL(string: uri) {
            if let viewID {
                allowed = ActionUIModel.shared.allows(.openLink(url), windowUUID: windowUUID, viewID: viewID)
            } else {
                allowed = ActionUIModel.shared.trustPolicy.allows(.openLink(url), for: unknownOrigin)
            }
        } else {
            allowed = viewID.flatMap { ActionUIModel.shared.origin(windowUUID: windowUUID, viewID: $0) }?.trust == .trusted
        }
        if !allowed {
            ActionUIModel.shared.logger.log("Not opening \(uri) from element \(viewID ?? node.element.id) of window \(windowUUID): the trust policy refuses it", .warning)
        }
        return allowed
    }

    /// The text to hand to Windows for `uri` when the node's content may open it (nil, and logged, when
    /// not): the URL the trust policy was asked about, as Foundation writes it, so Windows opens that
    /// address. Read as written, "https://a.example\@b.example/" is a.example to Windows and b.example to
    /// Foundation and the policy; written by Foundation it is "https://a.example%5C@b.example/", whose
    /// escaped backslash is no longer a separator Windows can read differently. An address that does not
    /// parse opens only from trusted content, as written.
    static func judgedText(_ uri: String, _ node: RenderNode) -> String? {
        guard allows(uri, node) else { return nil }
        return URL(string: uri)?.absoluteString ?? uri
    }

    /// Whether the node's content may do `capability` (not logged): asked for its element, or as
    /// content of unknown origin when its element cannot be told (originElementID).
    static func allows(_ capability: ActionUICapability, _ node: RenderNode) -> Bool {
        guard let viewID = originElementID(node) else {
            return ActionUIModel.shared.trustPolicy.allows(capability, for: unknownOrigin)
        }
        return ActionUIModel.shared.allows(capability, windowUUID: node.windowModel.windowUUID, viewID: viewID)
    }

    /// Whether the node's content may do `capability`, with a refusal logged once per element
    /// (ActionUIModel.allowsLoggingOnce), or once per window when its element cannot be told; for checks
    /// made each time a node syncs.
    static func allowsLoggingOnce(_ capability: ActionUICapability, what: String, _ node: RenderNode) -> Bool {
        if let viewID = originElementID(node) {
            return ActionUIModel.shared.allowsLoggingOnce(capability, what: what, windowUUID: node.windowModel.windowUUID, viewID: viewID)
        }
        return ActionUIModel.shared.allowsLoggingOnceForUnknownOrigin(capability, what: what, windowUUID: node.windowModel.windowUUID)
    }

    /// Whether the node's content may read the local file at `path` (an image, a canvas image, a
    /// video): trusted content reads anything without asking; other content asks the trust policy
    /// (.readLocalFile), and a refusal is logged. Without a node, the content's origin is unknown.
    /// Asked before the path is touched at all: on Windows even testing a file on a share
    /// (\\server\share) sends the user's credentials to that server.
    static func readsLocalFile(_ path: String, _ node: RenderNode?) -> Bool {
        reads(.readLocalFile(path), path: path, node)
    }

    /// Whether the node's content may load `text` when it is a file: URL (readsLocalFile on its
    /// path); any other text is not a local file and is not asked about.
    static func readsFileURL(_ text: String, _ node: RenderNode?) -> Bool {
        guard let url = URL(string: text), url.isFileURL else { return true }
        return readsLocalFile(filePath(of: url), node)
    }

    /// Whether the node's content may load the image address `text` (an AsyncImage, a Table's
    /// AsyncImage cell): trusted content loads any; other content loads only http, https and file:
    /// addresses (file: by readsFileURL), as Apple's loads web and file addresses. WinUI's image also
    /// reads ms-appx:, ms-appdata: and ms-resource: files, and Windows reads a drive path given as
    /// the address ("C:/pics/a.png", the scheme "c" to Apple's URL) as a local file. A refusal is
    /// logged.
    static func readsImageURL(_ text: String, _ node: RenderNode) -> Bool {
        if isTrusted(node) {
            return true
        }
        if let url = URL(string: text) {
            if url.isFileURL {
                return readsFileURL(text, node)
            }
            if ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                return true
            }
        }
        ActionUIModel.shared.logger.log("Not loading \(text) for element \(node.element.id): less-trusted content loads only http, https and file addresses", .warning)
        return false
    }

    /// Whether `path` names a file through the network or a device namespace: it starts with two
    /// slashes or backslashes, in any mix, or with Windows' object-manager prefix \??\ (where
    /// \??\UNC\ names a share). Read by code point, as Windows reads it: a backslash followed by a
    /// combining mark (U+0301) is one Character that is not a backslash, yet Windows reads the backslash.
    static func isNetworkPath(_ path: String) -> Bool {
        let characters = Array(path.unicodeScalars.prefix(4))
        let isSeparator: (Unicode.Scalar) -> Bool = { $0 == "\\" || $0 == "/" }
        if characters.count >= 2, isSeparator(characters[0]), isSeparator(characters[1]) {
            return true
        }
        return characters.count == 4 && isSeparator(characters[0]) && characters[1] == "?" && characters[2] == "?"
            && isSeparator(characters[3])
    }

    /// The path Windows opens for a file: URL, as the shim reads one (filePathOf in Images.cpp): with a
    /// host, a file on that server's share ("file://server/share/a.png" is "\\server\share\a.png"),
    /// which URL.path leaves out ("/share/a.png"), so the policy would be asked about another file;
    /// "file://localhost/C:/a.png" is the local "C:/a.png".
    static func filePath(of url: URL) -> String {
        guard let host = url.host(percentEncoded: false), !host.isEmpty else { return url.path }
        let path = url.path(percentEncoded: false)
        let characters = Array(path)
        let drive = characters.count >= 3 && characters[0] == "/" && characters[1].isLetter && characters[2] == ":"
        if drive, host.lowercased() == "localhost" {
            return url.path
        }
        return "\\\\" + host + String(path.map { $0 == "/" ? "\\" : $0 })
    }

    /// Whether the node's content may do `capability`, a read of the file at `path`, as
    /// readsLocalFile decides.
    static func reads(_ capability: ActionUICapability, path: String, _ node: RenderNode?) -> Bool {
        if let node, isTrusted(node) {
            return true
        }
        // A network path (\\server\share, //server/share, and the \\?\ and \\.\ forms) is refused
        // without asking: the policy's own check of the path (Core's resolvingSymlinksInPath) would
        // already reach the server with the user's credentials.
        if isNetworkPath(path) {
            ActionUIModel.shared.logger.log("Not reading \(path) for element \(node.map { String($0.element.id) } ?? "?"): less-trusted content reads no network or device path", .warning)
            return false
        }
        let allowed = node.map { allows(capability, $0) }
            ?? ActionUIModel.shared.trustPolicy.allows(capability, for: unknownOrigin)
        if !allowed {
            ActionUIModel.shared.logger.log("Not reading \(path) for element \(node.map { String($0.element.id) } ?? "?"): the trust policy refuses it", .warning)
        }
        return allowed
    }

    /// A file URL for `path`, made without asking the file system anything. URL(fileURLWithPath:)
    /// asks whether the path is a folder, which on Windows opens it: for a path on a share
    /// (\\server\share) that sends the user's credentials to the server before anyone decided whether
    /// the path may be read. A relative path is taken from the current folder.
    static func fileURL(path: String) -> URL {
        URL(filePath: path, directoryHint: .notDirectory)
    }

    /// Whether the node's content is trusted: its element's origin (or its template row's
    /// container's) is; content whose element cannot be told is not.
    static func isTrusted(_ node: RenderNode) -> Bool {
        guard let viewID = originElementID(node) else { return false }
        return ActionUIModel.shared.origin(windowUUID: node.windowModel.windowUUID, viewID: viewID)?.trust == .trusted
    }

    /// The origin the node's actions are judged by, as on Linux: its element's, or for a template row's
    /// node the container's around it (originElementID); less trusted when the element cannot be told. A
    /// template element may carry any id its JSON gives it, a trusted element's among them, so its own id
    /// must not decide.
    static func origin(_ node: RenderNode) -> JSONContentOrigin {
        originElementID(node).flatMap { ActionUIModel.shared.origin(windowUUID: node.windowModel.windowUUID, viewID: $0) }
            ?? unknownOrigin
    }

    /// The id of the element whose origin the node's content has: the node's own, or for a template
    /// row's node the nearest container around it; nil when that node's view model is not the
    /// window's one for its id, so the id would name another element's origin.
    static func originElementID(_ node: RenderNode) -> Int? {
        var current = node
        while current.model.templateContext != nil, let parent = current.parent {
            current = parent
        }
        guard current.windowModel.viewModels[current.element.id] === current.model else { return nil }
        return current.element.id
    }

    /// The origin of content whose element cannot be told: less trusted, as ActionUIModel.allows
    /// treats an element with no view model.
    private static let unknownOrigin = JSONContentOrigin(source: .host, trust: .lessTrusted, parentID: nil)

    // MARK: The app's resources

    /// The folders of the app's own resources (ActionUIRendererHooks.resourceFolders): the host's
    /// (ActionUIResourceFolder), else the running program's; none when neither is known.
    static func resourceFolders() -> [String] {
        if let host = ActionUIResourceFolder.path {
            return [host]
        }
        return programFolder.map { [$0] } ?? []
    }

    /// The folder of the running program (nil only when Windows cannot tell it).
    private static let programFolder: String? = {
        guard let copy = actionUIWinUICopyProgramFolder() else {
            ActionUIModel.shared.logger.log("LinkTrust: \(WinUIError.last("finding the program's folder")); only the host's resource folder is trusted", .warning)
            return nil
        }
        defer { actionUIWinUIFreeString(copy) }
        return String(cString: copy)
    }()
}
