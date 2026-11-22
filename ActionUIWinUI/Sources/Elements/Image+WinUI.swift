// Sources/Elements/Image+WinUI.swift
/*
 Image on WinUI. What it shows is chosen as on Apple and Linux: the value set at run time (a String,
 read with ImageSource's "mixed" rules) over the properties, of which the first that can be shown
 wins (filePath, resourceName, assetName, systemName; a filePath whose extension is not an image's is
 skipped, one without an extension shows the photo symbol).

 - A symbol (an SF Symbol name) is the Material Symbols outline the shim has for it (compiled in by
   Scripts/prepare-windows-symbols.py from the SF -> Material map, at the row's fill and weight as on
   Linux and Android, but at most weight 300, Windows' own thinner look; no font ships), drawn in the text color in a square of the font size times
   1.18, SwiftUI's symbol box (measured on macOS; Android uses the same factor). Small and large
   image scales are 0.8 and 1.28 times that. A name the Material map lacks is the Microsoft Fluent
   System Icons outline of the SF -> Fluent map, as Fluent draws it (Windows' own thinner look), its
   em box the same square (where a Fluent glyph has its Material counterpart's size). A name neither map has shows nothing, as
   SwiftUI's does (logged once per name).
 - A resizable symbol (resizable with a contentMode) scales to its frame: the largest square it is
   offered, its own size when offered unbounded room.
 - A file is WinUI's Image: an .svg file as a vector image, others through the system's bitmap
   decoders, at its own size, never scaled up; resizable with a contentMode it scales to its frame
   keeping its aspect ratio (fit: contained; fill: covered, clipped to the frame, where SwiftUI draws
   past it, as on Linux). A file that does not exist, or that is no regular file (a folder, a device
   such as NUL or COM1, a pipe: never opened), shows the photo symbol, as on Apple; one that cannot be
   decoded shows nothing. A bitmap file is read again when the value or a property is set
   again, so a host that rewrites an image under the same name and sets it again sees the new image.
 - Less-trusted content (ActionUI JSON from a server or from a file outside the app's resources) reads
   a local file only inside the app's resources (the trust policy's .readLocalFile, asked before the
   file is touched), as on Apple and Linux: another file shows the photo symbol. List and Table image
   cells and Canvas images follow the same rule.

 Not yet: assetName (Windows apps have no asset catalogs; shows the photo symbol) and resourceName
 (no app bundle on Windows yet; the photo symbol); the SF Symbols that neither map has; an SVG
 file rewritten under the same name may show the cached picture; an SVG with a viewBox but no width
 or height, not resizable, may have no size; an image larger than its frame, not resizable, is
 cropped inside the frame where SwiftUI and Linux let it overflow, centered (WinUI's Image reports
 its size capped at the room offered).
*/

import CWinUI

/// What an Image shows, resolved from its value and properties.
enum ImageContent: Equatable {
    case file(String)
    case symbol(String)
}

/// An Image's panel: its one child (a WinUI Image or a symbol's icon) at the image's size, centered in
/// the room it is given. An AsyncImage's also holds the image it is loading, behind the child.
@MainActor
final class ImageLayout {
    /// SwiftUI's symbol box over its font size (measured on macOS; ActionUIAndroid's factor).
    static let symbolFontFactor = 1.18

    let panel: LayoutPanel
    private(set) var child: WinUIObject?
    private(set) var content: ImageContent?
    /// A WinUI Image loading a URL (AsyncImage's) while the child shows its placeholder: in the panel,
    /// as WinUI loads only an image in the window, laid out as a file's child but not counted in the
    /// panel's size (it has none until it has loaded).
    private(set) var loading: WinUIObject?
    private var loadingMeasured = ActionUIWinUISize(width: 0, height: 0)
    /// The mutation token the file was last loaded at (a file is read again when it changes).
    var loadedToken: Int?
    /// Whether a symbol scales to its frame, and how a file does.
    var resizable = false
    var stretch = ActionUIWinUIImageStretchNone
    /// A symbol's side when it does not scale to its frame.
    var symbolSide = 14.0 * ImageLayout.symbolFontFactor
    /// The side the symbol's outline was last scaled to.
    private var appliedSide = -1.0
    /// The child's size from the last measure pass, for arrange (which must not measure it with
    /// another size).
    private var measured = ActionUIWinUISize(width: 0, height: 0)

    init() throws(WinUIError) {
        panel = try LayoutPanel()
        panel.measure = { [unowned self] available in measure(available) }
        panel.arrange = { [unowned self] finalSize in arrange(finalSize) }
    }

    /// A symbol's side for `node`'s font: the font size (the theme's body size when none) times
    /// SwiftUI's symbol box factor, times the image scale's factor ("small", "medium", "large"; nil:
    /// medium). Image, Label and Button's symbols; `appearance` in place of the node's (a control's,
    /// ControlSizing).
    static func symbolSide(_ node: RenderNode, scale: String?, appearance: TextAppearance? = nil) -> Double {
        let fontSize = TextAppearance.winUIFont((appearance ?? node.textAppearance).font).size
        let base = (fontSize > 0 ? fontSize : 14) * symbolFontFactor
        switch scale {
        case "small": return (base * 0.8).rounded()
        case "large": return (base * 1.28).rounded()
        default: return base.rounded()
        }
    }

    /// A new symbol icon for `name`, nil (logged once per name) when the shim has no outline for it.
    static func makeSymbol(_ name: String) -> WinUIObject? {
        guard actionUIWinUISymbolExists(name) else {
            if reportedMissing.insert(name).inserted {
                let why = actionUIWinUISymbolsAvailable() ? "neither the Material nor the Fluent SF Symbols map has it"
                                                          : "ActionUI's shim was built without its symbols (Scripts/prepare-windows-symbols.py)"
                ActionUIModel.shared.logger.log("No Windows symbol for \"\(name)\": \(why); showing nothing", .warning)
            }
            return nil
        }
        let symbol = WinUIObject(adopting: actionUIWinUISymbolCreate(name))
        if symbol == nil {
            ActionUIModel.shared.logger.log("Image: \(WinUIError.last("drawing the symbol \(name)"))", .error)
        }
        return symbol
    }

    private static var reportedMissing: Set<String> = []

    /// Shows `newChild` for `newContent`, replacing the child shown before. The loading image stays,
    /// unless it is `newChild` (it has loaded), which is then shown where it is.
    func show(_ newChild: WinUIObject?, for newContent: ImageContent) {
        if let newChild, newChild === loading {
            loading = nil
        }
        do {
            for index in panel.children.indices.reversed() {
                let kept = panel.children[index]
                if kept !== newChild, kept !== loading {
                    try panel.remove(at: index)
                }
            }
            if let newChild, !panel.children.contains(where: { $0 === newChild }) {
                try panel.append(newChild)
            }
        } catch {
            ActionUIModel.shared.logger.log("Image: \(error)", .error)
        }
        child = newChild
        content = newContent
        appliedSide = -1
        panel.invalidateLayout()
    }

    /// Holds `image` (nil: none) as the image loading behind the child, replacing the one before.
    func setLoading(_ image: WinUIObject?) {
        guard image !== loading else { return }
        do {
            if let old = loading, old !== child, let index = panel.children.firstIndex(where: { $0 === old }) {
                try panel.remove(at: index)
            }
            if let image, image !== child {
                try panel.insert(image, at: 0)
            }
        } catch {
            ActionUIModel.shared.logger.log("Image: \(error)", .error)
        }
        loading = image
        loadingMeasured = ActionUIWinUISize(width: 0, height: 0)
        panel.invalidateLayout()
    }

    /// A symbol's side for the room offered: the largest square of it when it scales to its frame.
    private func side(for available: ActionUIWinUISize) -> Double {
        guard resizable else { return symbolSide }
        switch (available.width.isFinite, available.height.isFinite) {
        case (true, true): return min(available.width, available.height)
        case (true, false): return available.width
        case (false, true): return available.height
        case (false, false): return symbolSide
        }
    }

    private func measure(_ available: ActionUIWinUISize) -> ActionUIWinUISize {
        if let loading {
            loadingMeasured = loading.measure(available)
        }
        guard let child, let content else {
            measured = ActionUIWinUISize(width: 0, height: 0)
            return measured
        }
        switch content {
        case .symbol:
            let side = max(side(for: available), 0)
            if side != appliedSide {
                appliedSide = side
                if !actionUIWinUISymbolSetSize(child.pointer, side) {
                    ActionUIModel.shared.logger.log("Image: \(WinUIError.last("sizing a symbol"))", .error)
                }
            }
            _ = child.measure(ActionUIWinUISize(width: side, height: side))
            measured = ActionUIWinUISize(width: side, height: side)
        case .file:
            measured = child.measure(available)
        }
        return measured
    }

    private func arrange(_ finalSize: ActionUIWinUISize) {
        if let loading {
            // Where it will show once loaded: as a file's child (below).
            let fills = stretch == ActionUIWinUIImageStretchFill
            let width = fills ? finalSize.width : loadingMeasured.width
            let height = fills ? finalSize.height : loadingMeasured.height
            loading.arrange(ActionUIWinUIRect(x: (finalSize.width - width) / 2, y: (finalSize.height - height) / 2,
                                              width: width, height: height))
        }
        guard let child else { return }
        // Centered at its measured size; a covering image fills the whole room (clipped to it).
        let fills = content.map { if case .file = $0 { return stretch == ActionUIWinUIImageStretchFill } else { return false } } ?? false
        let width = fills ? finalSize.width : measured.width
        let height = fills ? finalSize.height : measured.height
        child.arrange(ActionUIWinUIRect(x: (finalSize.width - width) / 2, y: (finalSize.height - height) / 2,
                                        width: width, height: height))
    }
}

extension Image: ActionUIWinUIRenderer {
    /// File name extensions of images WinUI decodes (some need a codec installed).
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "bmp", "tif", "tiff", "ico", "svg",
                                               "webp", "jxr", "wdp", "heic", "heif", "avif"]

    static func makeView(_ node: RenderNode) throws(WinUIError) -> WinUIObject {
        let layout = try ImageLayout()
        node.state = layout
        return layout.panel.object
    }

    static func update(_ view: WinUIObject, _ node: RenderNode) {
        guard let layout = node.state as? ImageLayout else { return }
        let props = Props(node.properties)
        let content = content(node, props)
        let token = node.model.mutationToken
        var changed = false
        if content != layout.content {
            layout.show(makeChild(content), for: content)
            layout.loadedToken = nil
            changed = true
        }
        if case .file(let path) = content, let child = layout.child, layout.loadedToken != token {
            layout.loadedToken = token
            if !actionUIWinUIImageSetFile(child.pointer, path) {
                ActionUIModel.shared.logger.log("Image: \(WinUIError.last("loading \(path)"))", .error)
            }
            changed = true
        }
        let resizable = props.resizable
        let stretch: ActionUIWinUIImageStretch = resizable ? (props.contentMode == .fill ? ActionUIWinUIImageStretchFill : ActionUIWinUIImageStretchFit)
                                                           : ActionUIWinUIImageStretchNone
        if resizable != layout.resizable || stretch != layout.stretch {
            layout.resizable = resizable
            layout.stretch = stretch
            changed = true
        }
        switch content {
        case .file:
            if let child = layout.child, !actionUIWinUIImageSetStretch(child.pointer, stretch) {
                ActionUIModel.shared.logger.log("Image: \(WinUIError.last("scaling an image"))", .error)
            }
        case .symbol:
            let side = symbolSide(node, props)
            if side != layout.symbolSide {
                layout.symbolSide = side
                changed = true
            }
            if let child = layout.child {
                // The foregroundStyle in effect, else the inherited text color (a button's follows its state).
                Paint.apply(Paint.parse(node.textAppearance.foreground, role: .foreground, tint: node.textAppearance.tint), ActionUIWinUIBrushForeground,
                            to: child, what: "a symbol")
            }
        }
        if let child = layout.child {
            // The image or icon itself: hiding the Image's panel from accessibility tools does not hide it.
            node.applyAccessibilityHidden(to: child)
        }
        if changed {
            layout.panel.invalidateLayout()
        }
    }

    /// The child for `content`: a WinUI Image for a file, the symbol's icon (nil when the shim has no
    /// outline for the name).
    static func makeChild(_ content: ImageContent) -> WinUIObject? {
        switch content {
        case .file:
            let image = WinUIObject(adopting: actionUIWinUIImageCreate())
            if image == nil {
                ActionUIModel.shared.logger.log("Image: \(WinUIError.last("creating an image"))", .error)
            }
            return image
        case .symbol(let name):
            return ImageLayout.makeSymbol(name)
        }
    }

    static func symbolSide(_ node: RenderNode, _ props: Props) -> Double {
        ImageLayout.symbolSide(node, scale: props.imageScale?.rawValue)
    }

    // MARK: What to show

    /// What the image shows: the runtime value when it is a non-empty String, else the first source
    /// that can be shown, else the photo symbol. Tracked reads of the value and properties.
    static func content(_ node: RenderNode, _ props: Props) -> ImageContent {
        let readsFile: (String) -> Bool = { LinkTrust.readsLocalFile($0, node) }
        if let value = node.model.value as? String, !value.isEmpty {
            // The "mixed" rules take a path by its "/"; a Windows path has backslashes ("C:\pics\a.png").
            let interpretation = value.contains("\\") ? "path" : "mixed"
            return content(ImageSource.resolve(value, interpretation: interpretation, lookup: lookup), readsFile: readsFile)
        }
        let source = props.sources.first { source in
            if case .filePath(let path) = source { return !hasExtension(path) || isImageFile(path) }
            return true
        }
        switch source {
        case .filePath(let path)?:
            return content(ImageSource.resolve(path, interpretation: "path", lookup: lookup), readsFile: readsFile)
        case .resourceName(let name)?:
            return content(ImageSource.resolve(name, interpretation: "resourceName", lookup: lookup), readsFile: readsFile)
        case .assetName?:
            return .symbol(ImageSource.placeholderSymbol)
        case .systemName(let name)?:
            return .symbol(name)
        case nil:
            return .symbol(ImageSource.placeholderSymbol)
        }
    }

    /// What a resolved source shows: a file the element may not read (`readsFile`:
    /// LinkTrust.readsLocalFile for its node, asked before the file is touched), that does not exist,
    /// or that is no regular file, is the photo symbol.
    static func content(_ source: ImageSource, readsFile: (String) -> Bool) -> ImageContent {
        switch source {
        case .filePath(let path):
            return readsFile(path) && isRegularFile(path) ? .file(path) : .symbol(ImageSource.placeholderSymbol)
        case .systemName(let name):
            return .symbol(name)
        case .assetName:
            return .symbol(ImageSource.placeholderSymbol)
        }
    }

    /// ImageSource's platform checks on Windows: image files by extension; no resources or assets yet.
    static var lookup: ImageSource.Lookup {
        ImageSource.Lookup(
            isImageFile: { isImageFile($0) },
            resourcePath: { _ in nil },
            assetExists: { _ in false }
        )
    }

    static func isImageFile(_ path: String) -> Bool {
        pathExtension(path).map { imageExtensions.contains($0.lowercased()) } ?? false
    }

    static func hasExtension(_ path: String) -> Bool {
        pathExtension(path) != nil
    }

    /// The extension of the path's last component, nil when it has none.
    static func pathExtension(_ path: String) -> String? {
        let name = path.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? path
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return nil }
        let ext = String(name[name.index(after: dot)...])
        return ext.isEmpty ? nil : ext
    }

    /// Whether `path` names a regular file (not a folder, a device such as NUL or COM1, or a pipe),
    /// links followed: a document names the path, and WinUI would read a device or a pipe forever.
    static func isRegularFile(_ path: String) -> Bool {
        actionUIWinUIIsRegularFile(path)
    }
}
