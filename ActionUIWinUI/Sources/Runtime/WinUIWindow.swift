// Sources/Runtime/WinUIWindow.swift
/*
 The render tree of one ActionUI window on WinUI: the root node built from the window model's
 loaded element (Linux: AdwaitaWindow). `view` is what goes into a WinUI window's content;
 openingSize is the size the application layer (ActionUIWinUIApplication) opens its window at.

 A WindowGroup at the root of the ActionUI JSON (on Apple, the window scene of a SwiftUI app) is read as a
 window, as on Linux: its content is the window's JSON, its title the window's default title
 (groupTitle), and its commands (groupCommands) join the menu bar once per group, by windowGroupID, else
 title (AppCommands). Only the commands of JSON the app owns are kept: the host's (load(json:)), and a
 file in the app's resource folders (LinkTrust.resourceFolders); a file elsewhere and anything from a
 server bring none, logged, as on Apple, where a WindowGroup's commands come only from the app's own
 scenes. One with no content cannot be loaded, as Apple shows "No content provided". Only ActionUI's own
 windows read it (readsWindowGroup); a host's window (HostWindow) takes the JSON as its content, as on
 Linux.
*/

import CWinUI

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

@MainActor
package final class WinUIWindow {
    let windowModel: WindowModel
    /// The root element's node; nil when the window model has no element loaded.
    package private(set) var root: RenderNode?

    package var windowUUID: String { windowModel.windowUUID }

    /// The command rows around the root, when the ActionUI JSON declares a toolbar outside a navigation
    /// container (WindowCommandBar).
    private var commandBar: WindowCommandBar?

    /// The title of the WindowGroup at the JSON's root, when it is one and names a title.
    package private(set) var groupTitle: String?
    /// The commands of the WindowGroup at the JSON's root and the key they join the menu bar under, when
    /// the JSON is the app's own (see the top of this file).
    package private(set) var groupCommands: (json: String, key: String)?

    /// The ActionUI JSON of a window with a WindowGroup at its root unwrapped: its content, its title, its
    /// commands and their key; `error` when it has no content. Any other JSON comes back as it is, and so
    /// does one over the size cap, for the load to refuse.
    struct GroupContent {
        var data: Data
        var title: String?
        var commands: (json: String, key: String)?
        var error: String?
    }

    static func windowGroup(_ data: Data, format: String) -> GroupContent {
        guard format == "json", data.count <= ActionUIConfiguration.current.limits.maximumJSONSize,
              let parsed = (try? ActionUIJSON.value(from: String(decoding: data, as: UTF8.self))) as? [String: Any],
              parsed["type"] as? String == "WindowGroup" else { return GroupContent(data: data) }
        // Its platform overrides ("title:windows" and the like) resolved first, as on Linux.
        let filter = PlatformFilter(active: PlatformFilter.runtimeActiveSet, logger: ActionUIModel.shared.logger)
        let root = filter.filter(parsed) as? [String: Any] ?? parsed
        let properties = root["properties"] as? [String: Any] ?? [:]
        let title = (properties["title"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        var group = GroupContent(data: data, title: title)
        if let commands = root["commands"] as? [Any], let json = try? ActionUIJSON.string(from: commands) {
            let key = (properties["windowGroupID"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? title ?? json
            group.commands = (json, key)
        }
        guard let content = root["content"], let json = try? ActionUIJSON.string(from: content) else {
            group.error = "the WindowGroup has no content"
            return group
        }
        group.data = Data(json.utf8)
        return group
    }

    /// The window's content: the command bar holding the root's box, or the root's box (its WinUI
    /// object with its padding and frame).
    package var view: WinUIObject? { commandBar?.panel.object ?? root?.outerView }

    /// Loads the host's ActionUI JSON into the model of `windowUUID` without making its tree (a prepared
    /// window's); `showing(windowUUID:)` makes it later.
    package static func loadModel(json: Data, windowUUID: String) throws {
        _ = try ActionUIModel.shared.loadDescription(from: json, format: "json", windowUUID: windowUUID)
    }

    /// The tree of the window model `windowUUID` already holds (loaded before, as a prepared window is).
    package static func showing(windowUUID: String) throws -> WinUIWindow {
        guard let windowModel = ActionUIModel.shared.windowModels[windowUUID], windowModel.element != nil else {
            throw ActionUIError("WinUIWindow: no ActionUI JSON is loaded for \(windowUUID)")
        }
        return WinUIWindow(windowModel: windowModel)
    }

    /// Loads `json` (ActionUI JSON) into the window model `windowUUID` and builds its tree.
    package static func load(json: String, windowUUID: String, readsWindowGroup: Bool = false) throws -> WinUIWindow {
        let group = readsWindowGroup ? windowGroup(Data(json.utf8), format: "json") : GroupContent(data: Data(json.utf8))
        if let error = group.error {
            throw ActionUIError(error)
        }
        _ = try ActionUIModel.shared.loadDescription(from: group.data, format: "json", windowUUID: windowUUID)
        guard let windowModel = ActionUIModel.shared.windowModels[windowUUID] else {
            throw ActionUIError("WinUIWindow: no window model for \(windowUUID) after loading")
        }
        let window = WinUIWindow(windowModel: windowModel)
        // The host passed it: its commands are the host's.
        window.groupTitle = group.title
        window.groupCommands = group.commands
        return window
    }

    /// The sentence a window shows when its ActionUI JSON could not be loaded. A file is named by its name
    /// only, and the common failures are said in plain words; the full error goes to the log.
    package static func loadErrorText(_ error: any Error, fileName: String?) -> String {
        let name = fileName.map { "\"\($0)\"" }
        if let cocoa = error as? CocoaError {
            switch cocoa.code {
            case .fileReadNoSuchFile, .fileNoSuchFile:
                return name.map { "The file \($0) was not found." } ?? "The file was not found."
            case .fileReadNoPermission:
                return name.map { "The file \($0) could not be read: access is denied." } ?? "The file could not be read: access is denied."
            default:
                return name.map { "The file \($0) could not be read." } ?? "The file could not be read."
            }
        }
        if error is ActionUIContentLoader.NotARegularFile {
            return name.map { "\($0) is not a file." } ?? "The path is not a file."
        }
        if let failure = error as? JSONParseError {
            // The JSON parser's message and where it stopped, as "Unterminated string at byte 12".
            return "The ActionUI JSON could not be loaded: \(failure)"
        }
        if let failure = error as? ActionUIError {
            // Core's own messages, such as the size limit's and the trust policy's.
            return "The ActionUI JSON could not be loaded: \(failure.message)"
        }
        if let failure = error as? DecodingError {
            // JSON that parses but is not a valid ActionUI element (a missing "type", a wrong value).
            let context: DecodingError.Context
            switch failure {
            case .typeMismatch(_, let found), .valueNotFound(_, let found), .keyNotFound(_, let found), .dataCorrupted(let found):
                context = found
            @unknown default:
                return "The ActionUI JSON could not be loaded."
            }
            return "The ActionUI JSON could not be loaded: \(context.debugDescription)"
        }
        return "The ActionUI JSON could not be loaded."
    }

    /// A window that shows why its ActionUI JSON could not be loaded (loadErrorText), padded.
    package static func loadError(_ error: any Error, fileName: String?, windowUUID: String) -> WinUIWindow? {
        let text = loadErrorText(error, fileName: fileName)
        ActionUIModel.shared.logger.log("Window \(windowUUID) shows: \(text)", .warning)
        let errorJSON = (try? ActionUIJSON.string(from: ["type": "Text", "id": 1,
                                                         "properties": ["text": text, "padding": 20]] as [String: Any]))
            ?? #"{"type": "Text", "id": 1, "properties": {"text": "The ActionUI JSON could not be loaded."}}"#
        return try? load(json: errorJSON, windowUUID: windowUUID)
    }

    /// Loads the ActionUI JSON (or plist, by its extension) in the regular file at `url` into the
    /// window model `windowUUID`, as from that file: it is the app's own when it is in the app's
    /// resources, else less trusted (JSONContentOrigin), and builds its tree.
    package static func load(file url: URL, windowUUID: String, readsWindowGroup: Bool = false) throws -> WinUIWindow {
        let format = ActionUIContentLoader.format(of: url)
        let data = try ActionUIContentLoader.readRegularFile(url)
        let group = readsWindowGroup ? windowGroup(data, format: format) : GroupContent(data: data)
        if let error = group.error {
            throw ActionUIError(error)
        }
        _ = try ActionUIContentLoader.load(data: group.data, format: format, windowUUID: windowUUID,
                                            isContentView: true, parentID: 0, source: .file(url))
        guard let windowModel = ActionUIModel.shared.windowModels[windowUUID] else {
            throw ActionUIError("WinUIWindow: no window model for \(windowUUID) after loading")
        }
        let window = WinUIWindow(windowModel: windowModel)
        window.groupTitle = group.title
        if let commands = group.commands {
            if LinkTrust.resourceFolders().contains(where: { ActionUIResourceFolder.isFile(url, inside: $0) }) {
                window.groupCommands = commands
            } else {
                ActionUIModel.shared.logger.log("WindowGroup commands from \(url.path) are ignored: only JSON in the app's resource folder, or JSON the host passes, adds menu commands", .warning)
            }
        }
        return window
    }

    /// Loads ActionUI JSON (or plist, by the address's extension) fetched from `url` into the window
    /// model `windowUUID`, as from `finalURL` (the address it finally came from after redirects; nil:
    /// `url`), which decides its trust (a trusted origin of the host's configuration, else less trusted),
    /// and builds its tree. A final address Foundation cannot read, or one with a backslash or a user name
    /// (where Windows' and Foundation's readings of the host could differ), is refused.
    package static func load(data: Data, from url: URL, finalURL finalText: String?, windowUUID: String,
                             readsWindowGroup: Bool = false) throws -> WinUIWindow {
        var source = url
        if let finalText {
            guard let read = URL(string: finalText), !finalText.contains("\\"), read.user == nil else {
                throw ActionUIError("\(url.absoluteString) was redirected to an address that cannot be read")
            }
            source = read
        }
        let format = ActionUIContentLoader.format(of: url)
        let group = readsWindowGroup ? windowGroup(data, format: format) : GroupContent(data: data)
        if let error = group.error {
            throw ActionUIError(error)
        }
        _ = try ActionUIContentLoader.load(data: group.data, format: format, windowUUID: windowUUID,
                                            isContentView: true, parentID: 0, source: .remote(source))
        guard let windowModel = ActionUIModel.shared.windowModels[windowUUID] else {
            throw ActionUIError("WinUIWindow: no window model for \(windowUUID) after loading")
        }
        let window = WinUIWindow(windowModel: windowModel)
        window.groupTitle = group.title
        if group.commands != nil {
            // No commands from a server, trusted or not, as on Apple and Linux.
            ActionUIModel.shared.logger.log("WindowGroup commands from \(url.absoluteString) are ignored: only JSON in the app's resource folder, or JSON the host passes, adds menu commands", .warning)
        }
        return window
    }

    /// Builds and syncs the tree for the element loaded into `windowModel`.
    init(windowModel: WindowModel) {
        self.windowModel = windowModel
        guard let element = windowModel.element else {
            ActionUIModel.shared.logger.log("WinUIWindow: window \(windowModel.windowUUID) has no element loaded", .error)
            return
        }
        guard let model = windowModel.viewModels[element.id] else {
            ActionUIModel.shared.logger.log("WinUIWindow: no view model for the root element \(element.id) in window \(windowModel.windowUUID)", .error)
            return
        }
        let root = RenderNode(element: element, model: model, windowModel: windowModel, parent: nil)
        self.root = root
        // Before the first sync, in which the toolbars show their items.
        if Self.declaresWindowToolbar(element), let content = root.outerView {
            do {
                let bar = try WindowCommandBar(content: content)
                commandBar = bar
                WindowCommandBar.register(bar, windowUUID: windowModel.windowUUID)
            } catch {
                ActionUIModel.shared.logger.log("WinUIWindow: \(error); the toolbars are not shown", .error)
            }
        }
        root.sync()
    }

    /// Whether `element` or an element under it, outside a navigation container, declares a toolbar.
    private static func declaresWindowToolbar(_ element: any ActionUIElementBase) -> Bool {
        if !ToolbarHelper.screenToolbarItems(of: element).isEmpty { return true }
        guard !ToolbarHelper.isNavigationContainer(element.type) else { return false }
        for value in (element.subviews ?? [:]).values {
            switch value {
            case let one as any ActionUIElementBase:
                if declaresWindowToolbar(one) { return true }
            case let list as [any ActionUIElementBase]:
                if list.contains(where: declaresWindowToolbar) { return true }
            case let rows as [[any ActionUIElementBase]]:
                if rows.joined().contains(where: declaresWindowToolbar) { return true }
            default:
                break
            }
        }
        return false
    }

    /// The size a window opens at when its content is too small to say: SwiftUI's default (macOS).
    package static let fallbackSize = ActionUIWinUISize(width: 480, height: 320)
    /// The widest a window opens unless its content's minimum needs more: SwiftUI's WindowGroup opens
    /// 900 points wide on macOS (measured on macOS 27, whatever the content), as on Linux.
    package static let openingWidth = 900.0
    /// The least a window opens tall when its content grows vertically (a List, a ScrollView, a Color):
    /// SwiftUI's WindowGroup gives its content 418 points (macOS 27), as on Linux.
    package static let openingHeight = 418.0

    /// The content size the window opens at, as on Linux: the content's size measured in the opening
    /// width (wider only when its minimum needs it), at least openingHeight tall when it grows
    /// vertically; fallbackSize when it measures under 10 by 10.
    package func openingSize() -> ActionUIWinUISize {
        guard let view else { return Self.fallbackSize }
        let measured = actionUIWinUIElementMeasure(view.pointer, ActionUIWinUISize(width: Self.openingWidth, height: .infinity))
        guard measured.width.isFinite, measured.height.isFinite, measured.width >= 10 || measured.height >= 10 else {
            return Self.fallbackSize
        }
        var height = measured.height.rounded(.up)
        if root?.expansion.contains(.vertical) == true {
            height = max(height, Self.openingHeight)
        }
        return ActionUIWinUISize(width: max(measured.width.rounded(.up), 1), height: max(height, 1))
    }

    /// The window is going away: its nodes leave the tree.
    package func detach() {
        root?.detach()
        // Only its own: another window may have taken the id since.
        if let commandBar, WindowCommandBar.of(windowUUID: windowModel.windowUUID) === commandBar {
            WindowCommandBar.register(nil, windowUUID: windowModel.windowUUID)
        }
    }

    isolated deinit {
        root?.detach()
    }
}
