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
import Dispatch

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
    /// The window-level presentations the host asks for (modals, alerts, confirmation dialogs).
    private var presenter: WindowPresenter?

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
        if let view {
            presenter = WindowPresenter(windowModel: windowModel, anchor: view, toastAnchor: root.outerView ?? view)
        }
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

    /// The size a window takes for this content once it has loaded: openingSize, `wanted`'s positive
    /// sides in its place, grown to what the content asks for at that size when it needs more (its
    /// padding, its frame's minimum, a stack's children at their smallest: WinUIObject.measureRequested,
    /// read past WinUI's cap at the size offered). Smaller, the content is cut at both ends, as the root
    /// is centered in the window.
    package func fittingSize(wanted: (width: Int, height: Int)?) -> ActionUIWinUISize {
        var size: ActionUIWinUISize
        if let wanted, wanted.width > 0, wanted.height > 0 {
            size = ActionUIWinUISize(width: Double(wanted.width), height: Double(wanted.height))
        } else {
            size = openingSize(wanted: wanted)
        }
        guard let view else { return size }
        // Less than a pixel more is rounding (a header's fractional height beside a stack's whole
        // pixels: NavigationStack, WindowCommandBar), not content: growing for it would make a kept
        // window a pixel larger each time it reopens.
        var needed = view.measureRequested(size)
        if needed.width.isFinite, needed.width - size.width >= 1 {
            size.width = needed.width.rounded(.up)
            // Text wraps less at the wider width: what the height needs is measured there.
            needed = view.measureRequested(size)
        }
        if needed.height.isFinite, needed.height - size.height >= 1 { size.height = needed.height.rounded(.up) }
        return size
    }

    /// openingSize with `wanted`'s positive sides in place of the content's own.
    package func openingSize(wanted: (width: Int, height: Int)?) -> ActionUIWinUISize {
        var size = openingSize()
        if let wanted {
            if wanted.width > 0 { size.width = Double(wanted.width) }
            if wanted.height > 0 { size.height = Double(wanted.height) }
        }
        return size
    }

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

    /// How long a cloaked window waits for its content to load before it shows anyway, at the size it
    /// has: a window whose content never loads is not left invisible.
    package static let fittingTimeoutNanoseconds: UInt64 = 2_000_000_000

    /// Sizes `window` to this content (fittingSize, `wanted`'s positive sides kept) once the content has
    /// loaded in it. Only then do WinUI's controls have their styles: measured before, a TextField is as
    /// little as 1 effective pixel tall instead of 32, and a window sized from that is too small for its
    /// controls. With `cloaks`, the window is kept off the screen (cloaked) until it is sized, so the user
    /// never sees it at its first size; it shows after fittingTimeoutNanoseconds if its content has not
    /// loaded by then. `extraHeight` is added to the content's height (a menu bar, a host's mark above it);
    /// the window is at least `minimumWidth` wide (what the mark's row needs), and the user cannot resize
    /// it narrower, nor smaller than its content's minimum (ContentSizeLimits.measured) unless `setsMinimum` is
    /// false (a host's window, whose limits are the host's); `fitted`
    /// runs once the window is sized. Call it with the content in the window, before the window shows.
    /// A window is never smaller than its content needs (fittingSize), even when `wanted` gives both
    /// sides, as on macOS, where a window is at least its content's minimum size; it keeps growing
    /// when its content comes to need more later.
    package func fit(_ window: WinUIObject, wanted: (width: Int, height: Int)?, cloaks: Bool,
                     extraHeight: @escaping @MainActor (WinUIObject) -> Double = { _ in 0 },
                     minimumWidth: @escaping @MainActor (WinUIObject) -> Double = { _ in 0 },
                     setsMinimum: Bool = true,
                     fitted: @escaping @MainActor () -> Void = {}) {
        guard let view else {
            fitted()
            return
        }
        let logger = ActionUIModel.shared.logger
        var cloaked = false
        if cloaks {
            cloaked = actionUIWinUIWindowSetCloaked(window.pointer, true)
            if !cloaked {
                logger.log("WinUIWindow: \(WinUIError.last("cloaking a window until it is sized")); it may show at its first size", .warning)
            }
        }
        let fitting = WindowFitting(window: window, isCloaked: cloaked)
        // The content's Loaded comes again each time it is taken out and put back: only the first sizes.
        // The handler keeps the fitting (it holds the window weakly) as long as the content lives.
        let connected = WinUIEvents.connect(view, actionUIWinUIElementOnLoaded, "a window's content loading") { [weak self, weak view] in
            guard let self, let view, !fitting.isSized, let window = fitting.window else { return }
            fitting.isSized = true
            var size = self.fittingSize(wanted: wanted)
            let leastWidth = minimumWidth(window).rounded(.up)
            size.width = max(size.width, leastWidth)
            if !actionUIWinUIWindowSetContentSize(window.pointer, size.width, size.height + max(extraHeight(window), 0)) {
                logger.log("WinUIWindow: \(WinUIError.last("sizing a window to its loaded content"))", .warning)
            }
            // The user cannot make it smaller than its content's minimum either (its toolbar's rows added), as a macOS
            // window keeps its content's minimum size, nor narrower than `minimumWidth`.
            let least = setsMinimum ? self.root.map { root -> ContentSizeLimits.Size in
                let limits = ContentSizeLimits.measured(view, expansion: root.expansion, compression: root.compression, caps: root.caps).minSize
                // A toolbar's items that do not fit move to its "see more" flyout, as a macOS window's to its
                // toolbar's overflow menu: the width is the content's own minimum and the command rows' least.
                guard let commandBar = self.commandBar, let content = root.outerView, content !== view else { return limits }
                let contentWidth = ContentSizeLimits.measured(content, expansion: root.expansion, compression: root.compression,
                                                              caps: root.caps).minSize.width
                return .init(width: max(contentWidth, commandBar.leastWidth), height: limits.height)
            } : nil
            let leastSize = ActionUIWinUISize(width: max(leastWidth, (least?.width ?? 0).rounded(.up)),
                                              height: least.map { ($0.height + max(extraHeight(window), 0)).rounded(.up) } ?? 0)
            if leastSize.width > 0 || leastSize.height > 0,
               !actionUIWinUIWindowSetMinimumContentSize(window.pointer, leastSize.width, leastSize.height) {
                logger.log("WinUIWindow: \(WinUIError.last("setting a window's least size"))", .warning)
            }
            // Laid out at the new size now, and shown on the next turn of the loop: the first frame the
            // user sees has the content at its size, not at the first one.
            if !actionUIWinUIElementUpdateLayout(view.pointer) {
                logger.log("WinUIWindow: \(WinUIError.last("laying out a window's content at its size"))", .warning)
            }
            fitted()
            Task { @MainActor in
                fitting.reveal()
            }
            // From now on the window grows when its content comes to need more than the window gives it
            // (a LoadableView's ActionUI JSON arriving, rows added), as a macOS window grows to its
            // content's minimum. Only a side whose answer grew for the same size counts: a window the
            // user made smaller neither grows back as they resize it nor at a later change that does
            // not need more on that side (a label's text changing).
            view.layoutPanel?.requestedChangedAtRoot = { [weak self] offered, before, requested in
                // Only from a window's size: not from an unbounded offer (openingSize measures one, and
                // Int() of infinity in grow traps) or an empty one (nothing to grow from).
                guard offered.width.isFinite, offered.height.isFinite, offered.width >= 1, offered.height >= 1 else { return }
                let wider = requested.width - before.width >= 1 && requested.width - offered.width >= 1
                let taller = requested.height - before.height >= 1 && requested.height - offered.height >= 1
                guard wider || taller else { return }
                fitting.growsWidth = fitting.growsWidth || wider
                fitting.growsHeight = fitting.growsHeight || taller
                guard !fitting.isGrowing else { return }
                fitting.isGrowing = true
                // After the layout pass: measuring and resizing inside it would change what WinUI walks.
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        fitting.isGrowing = false
                        self?.grow(fitting, from: offered, extraHeight: extraHeight)
                    }
                }
            }
        }
        // Refused, the handler (and with it the fitting the timeout holds weakly) is gone: the window keeps
        // its first size and shows now, rather than staying cloaked.
        guard connected else {
            fitting.reveal()
            fitted()
            return
        }
        if cloaked {
            Task { @MainActor [weak fitting] in
                try? await Task.sleep(nanoseconds: Self.fittingTimeoutNanoseconds)
                fitting?.reveal()
            }
        }
        // A presentation shown inside it (a sheet) can grow it too (growForPresentation).
        Self.growers[windowModel.windowUUID] = WindowGrower(owner: self, window: window, extraHeight: extraHeight, fitting: fitting)
    }

    /// The windows fit sized, by window UUID: their window and menu bar height, for growForPresentation.
    private static var growers: [String: WindowGrower] = [:]

    /// Makes the content of the window showing `windowUUID` at least `size`, for a presentation shown
    /// inside it that needs that room (a sheet: WinUI's dialog is drawn within its window, where a macOS
    /// sheet can reach past it). Returns the content size the window had and the size it got, for
    /// shrinkAfterPresentation; nil when it was large enough, or it is no window fit sized.
    package static func growForPresentation(windowUUID: String, to size: ActionUIWinUISize)
        -> (before: ActionUIWinUISize, after: ActionUIWinUISize)? {
        guard let grower = growers[windowUUID], let window = grower.window else { return nil }
        var width = 0.0
        var height = 0.0
        guard actionUIWinUIWindowContentSize(window.pointer, &width, &height) else { return nil }
        let before = ActionUIWinUISize(width: width, height: height)
        let after = ActionUIWinUISize(width: max(width, size.width.rounded(.up)), height: max(height, size.height.rounded(.up)))
        guard after.width - width >= 1 || after.height - height >= 1 else { return nil }
        if !actionUIWinUIWindowSetContentSize(window.pointer, after.width, after.height + max(grower.extraHeight(window), 0)) {
            ActionUIModel.shared.logger.log("WinUIWindow: \(WinUIError.last("growing a window for a sheet"))", .warning)
            return nil
        }
        return (before, after)
    }

    /// The root element of the window showing `windowUUID`, while that window is open and fit sized (an
    /// application's or a host's) and sized to its loaded content, whose controls then have their styles: for
    /// contentSizeLimits.
    package static func shownRoot(windowUUID: String) -> RenderNode? {
        guard let grower = growers[windowUUID], grower.window != nil, grower.fitting.isSized else { return nil }
        return grower.owner?.root
    }

    /// The content size of the window showing `windowUUID` as last laid out, if it is fit sized.
    package static func presentedContentSize(windowUUID: String) -> ActionUIWinUISize? {
        guard let grower = growers[windowUUID], let window = grower.window else { return nil }
        var width = 0.0
        var height = 0.0
        guard actionUIWinUIWindowContentSize(window.pointer, &width, &height) else { return nil }
        return ActionUIWinUISize(width: width, height: height)
    }

    /// Gives the window showing `windowUUID` back the content size it had before growForPresentation,
    /// when it still has the size that gave it (the user did not resize it meanwhile).
    package static func shrinkAfterPresentation(windowUUID: String, from grown: (before: ActionUIWinUISize, after: ActionUIWinUISize)) {
        guard let grower = growers[windowUUID], let window = grower.window else { return }
        var width = 0.0
        var height = 0.0
        guard actionUIWinUIWindowContentSize(window.pointer, &width, &height),
              abs(width - grown.after.width) < 1, abs(height - grown.after.height) < 1 else { return }
        if !actionUIWinUIWindowSetContentSize(window.pointer, grown.before.width, grown.before.height + max(grower.extraHeight(window), 0)) {
            ActionUIModel.shared.logger.log("WinUIWindow: \(WinUIError.last("giving a window back its size after a sheet"))", .warning)
        }
    }

    /// Grows the window of `fitting` from content size `offered` to what its content asks for now
    /// (fittingSize, `offered` kept as the least), on the sides whose answer grew (growsWidth,
    /// growsHeight), when that is larger. Nothing when the window's size changed since `offered` (the
    /// user resized it meanwhile).
    private func grow(_ fitting: WindowFitting, from offered: ActionUIWinUISize,
                      extraHeight: @MainActor (WinUIObject) -> Double) {
        let growsWidth = fitting.growsWidth, growsHeight = fitting.growsHeight
        fitting.growsWidth = false
        fitting.growsHeight = false
        guard let window = fitting.window else { return }
        var now = (width: 0.0, height: 0.0)
        guard actionUIWinUIWindowContentSize(window.pointer, &now.width, &now.height),
              abs(now.width - offered.width) < 1, abs(now.height - offered.height) < 1 else { return }
        var size = fittingSize(wanted: (Int(offered.width.rounded(.up)), Int(offered.height.rounded(.up))))
        if !growsWidth { size.width = offered.width }
        if !growsHeight { size.height = offered.height }
        guard size.width - offered.width >= 1 || size.height - offered.height >= 1 else { return }
        if !actionUIWinUIWindowSetContentSize(window.pointer, size.width, size.height + max(extraHeight(window), 0)) {
            ActionUIModel.shared.logger.log("WinUIWindow: \(WinUIError.last("growing a window to its content"))", .warning)
        }
    }

    /// The window is going away: its nodes leave the tree.
    package func detach() {
        // Before the nodes leave: a sheet coming down with them does not resize a window that is closing
        // or taking other content. Only its own: another window may have taken the id since (a
        // windowWillClose handler presenting the UUID again).
        if Self.growers[windowModel.windowUUID]?.owner === self {
            Self.growers[windowModel.windowUUID] = nil
        }
        presenter?.stop()
        root?.detach()
        // Only its own: another window may have taken the id since.
        if let commandBar, WindowCommandBar.of(windowUUID: windowModel.windowUUID) === commandBar {
            WindowCommandBar.register(nil, windowUUID: windowModel.windowUUID)
        }
    }

    isolated deinit {
        presenter?.stop()
        root?.detach()
    }
}

/// A window waiting to be sized to its loaded content (WinUIWindow.fit): whether it is sized, and
/// whether it is still cloaked.
@MainActor
private final class WindowFitting {
    weak var window: WinUIObject?
    var isSized = false
    /// Whether a growth to the content is asked for, after the current layout pass, and on which
    /// sides (those whose answer grew).
    var isGrowing = false
    var growsWidth = false
    var growsHeight = false
    private var isCloaked: Bool

    init(window: WinUIObject, isCloaked: Bool) {
        self.window = window
        self.isCloaked = isCloaked
    }

    /// Shows the window again, if it is cloaked; once.
    func reveal() {
        guard isCloaked, let window else { return }
        isCloaked = false
        if !actionUIWinUIWindowSetCloaked(window.pointer, false) {
            ActionUIModel.shared.logger.log("WinUIWindow: \(WinUIError.last("showing a cloaked window"))", .error)
        }
    }
}

/// A window fit sized, held weakly, and the height above its content (a menu bar); `owner` is the
/// WinUIWindow that fit it, and `fitting` its sizing (whether it is sized to its loaded content yet).
@MainActor
private struct WindowGrower {
    weak var owner: WinUIWindow?
    weak var window: WinUIObject?
    let extraHeight: @MainActor (WinUIObject) -> Double
    let fitting: WindowFitting
}
