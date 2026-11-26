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
 - resizable and contentMode size it as SwiftUI's .resizable() and .aspectRatio(contentMode:) do (as on
   Apple and Linux): not resizable, it keeps its own size whatever the contentMode; resizable with no
   contentMode, it is stretched to its frame on both axes (its own size on an axis offered unbounded
   room); resizable with "fit" or "fill", it keeps its aspect ratio.
 - A resizable symbol with no contentMode is its outline stretched to the frame on each axis (the
   outline is a path, not a font glyph, so it stretches as SwiftUI's does); with a contentMode, the
   largest square it is offered.
 - A file is WinUI's Image: an .svg file as a vector image, others through the system's bitmap
   decoders, at its own size, never scaled up. Resizable, it is stretched to its frame; with a
   contentMode too, it is scaled keeping its aspect ratio (fit: contained; fill: covered, clipped to
   the frame, where SwiftUI draws past it, as on Linux). A file that does not exist, or that is no regular file (a folder, a device
   such as NUL or COM1, a pipe: never opened), shows the photo symbol, as on Apple; one that cannot be
   decoded shows nothing. A bitmap file is read again when the value or a property is set
   again, so a host that rewrites an image under the same name and sets it again sees the new image.
 - A file that declares more pixels than 64 megapixels (8192 x 8192: ImageSource.maximumPixelCount)
   shows the photo symbol and is logged, as on Apple and Linux: its size is read from its header by
   Windows' image decoders (WIC), never decoded. List and Table image cells, Canvas images and
   AsyncImage's file URLs follow the same rule.
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

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
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
    /// The box the symbol's outline was last scaled to.
    private var appliedBox = ActionUIWinUISize(width: -1, height: -1)
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
        appliedBox = ActionUIWinUISize(width: -1, height: -1)
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

    /// A symbol's box for the room offered: its own square when it does not scale to its frame;
    /// stretched to the room (resizable with no contentMode, as SwiftUI's .resizable()), each side its
    /// own on an unbounded axis; else the largest square of the room.
    private func box(for available: ActionUIWinUISize) -> ActionUIWinUISize {
        guard resizable else { return ActionUIWinUISize(width: symbolSide, height: symbolSide) }
        let width = available.width.isFinite ? max(available.width, 0) : nil
        let height = available.height.isFinite ? max(available.height, 0) : nil
        if stretch == ActionUIWinUIImageStretchToSize {
            return ActionUIWinUISize(width: width ?? symbolSide, height: height ?? symbolSide)
        }
        let side: Double
        switch (width, height) {
        case let (width?, height?): side = min(width, height)
        case let (width?, nil): side = width
        case let (nil, height?): side = height
        case (nil, nil): side = symbolSide
        }
        return ActionUIWinUISize(width: side, height: side)
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
            let box = box(for: available)
            if box.width != appliedBox.width || box.height != appliedBox.height {
                appliedBox = box
                if !actionUIWinUISymbolSetFrameSize(child.pointer, box.width, box.height) {
                    ActionUIModel.shared.logger.log("Image: \(WinUIError.last("sizing a symbol"))", .error)
                }
            }
            _ = child.measure(box)
            measured = box
        case .file:
            // WinUI's Fill keeps the aspect ratio when one axis is unbounded (it scales both by the bounded
            // one); a stretched image takes its own size there, as SwiftUI's .resizable() does.
            var room = available
            if stretch == ActionUIWinUIImageStretchToSize, room.width.isFinite != room.height.isFinite {
                let natural = child.measure(ActionUIWinUISize(width: .infinity, height: .infinity))
                if room.width.isFinite {
                    room.height = natural.height
                } else {
                    room.width = natural.width
                }
            }
            measured = child.measure(room)
        }
        return measured
    }

    private func arrange(_ finalSize: ActionUIWinUISize) {
        if let loading {
            // Where it will show once loaded: as a file's child (below).
            let fills = stretch == ActionUIWinUIImageStretchFill || stretch == ActionUIWinUIImageStretchToSize
            let width = fills ? finalSize.width : loadingMeasured.width
            let height = fills ? finalSize.height : loadingMeasured.height
            loading.arrange(ActionUIWinUIRect(x: (finalSize.width - width) / 2, y: (finalSize.height - height) / 2,
                                              width: width, height: height))
        }
        guard let child else { return }
        // Centered at its measured size; a covering or stretched image fills the whole room (a covering
        // one clipped to it).
        let fills = content.map { content -> Bool in
            guard case .file = content else { return false }
            return stretch == ActionUIWinUIImageStretchFill || stretch == ActionUIWinUIImageStretchToSize
        } ?? false
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
        // As SwiftUI: not resizable, its own size whatever the contentMode; resizable, stretched to its frame
        // on both axes, or with a contentMode keeping its aspect ratio (fit: inside it; fill: covering it).
        let resizable = props.resizable
        let stretch: ActionUIWinUIImageStretch
        switch (resizable, props.contentMode) {
        case (false, _): stretch = ActionUIWinUIImageStretchNone
        case (true, nil): stretch = ActionUIWinUIImageStretchToSize
        case (true, .fit?): stretch = ActionUIWinUIImageStretchFit
        case (true, .fill?): stretch = ActionUIWinUIImageStretchFill
        }
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
    /// that is no regular file, or that declares more pixels than the decode cap, is the photo symbol.
    static func content(_ source: ImageSource, readsFile: (String) -> Bool) -> ImageContent {
        switch source {
        case .filePath(let path):
            guard readsFile(path), isRegularFile(path), !fileIsTooLarge(path) else { return .symbol(ImageSource.placeholderSymbol) }
            return .file(path)
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

    /// The image files sized: the file's version when sized (its modification date and length) and the
    /// size it declares (nil: unknown). content runs on every sync and canvas draw.
    private static var sizedFiles: [String: (version: String, size: (width: Int, height: Int)?)] = [:]

    /// Whether the image file declares more pixels than the decode cap (ImageSource.maximumPixelCount,
    /// 8192 x 8192), as on Apple and Linux: its size read from its header (WIC), never decoded; sized
    /// again only when the file changes. Logged when it is sized. A file WIC cannot size (an SVG) goes
    /// on to WinUI, which decides. `path` names a regular file (isRegularFile, asked first): sizing
    /// opens and reads it.
    static func fileIsTooLarge(_ path: String) -> Bool {
        let version = fileVersion(path)
        let size: (width: Int, height: Int)?
        if let version, let sized = sizedFiles[path], sized.version == version {
            size = sized.size
        } else {
            var width: UInt32 = 0
            var height: UInt32 = 0
            size = actionUIWinUIImageFileGetSize(path, &width, &height) ? (Int(width), Int(height)) : nil
            if let size, ImageSource.isTooLarge(width: size.width, height: size.height) {
                ActionUIModel.shared.logger.log("Image not shown: \(path) is \(size.width) x \(size.height) pixels, more than \(ImageSource.maximumPixelCount)", .warning)
            }
            if let version {
                // A bound, for a host that shows a new file each time.
                if sizedFiles.count >= 1024 { sizedFiles = [:] }
                sizedFiles[path] = (version, size)
            }
        }
        return size.map { ImageSource.isTooLarge(width: $0.width, height: $0.height) } ?? false
    }

    /// Whether `text` is a file: URL whose file declares more pixels than the decode cap (an
    /// AsyncImage's); false for any other address, whose image WinUI decodes at the size it is drawn.
    /// False for a path that names no regular file: sizing opens and reads the file, and a device or a
    /// pipe is never opened (the shim refuses such a URL when it is loaded).
    static func fileURLIsTooLarge(_ text: String) -> Bool {
        guard let url = URL(string: text), url.isFileURL else { return false }
        let path = LinkTrust.filePath(of: url)
        guard isRegularFile(path) else { return false }
        return fileIsTooLarge(path)
    }

    /// The file's version for sizedFiles: its modification date and length; nil when unknown.
    private static func fileVersion(_ path: String) -> String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let date = attributes[.modificationDate] as? Date else { return nil }
        // The length as the platform's Foundation gives it (NSNumber or an integer): only compared.
        let length = attributes[.size].map { "\($0)" } ?? "?"
        return "\(date.timeIntervalSinceReferenceDate)|\(length)"
    }

    /// Whether `path` names a regular file (not a folder, a device such as NUL or COM1, or a pipe),
    /// links followed: ActionUI JSON names the path, and WinUI would read a device or a pipe forever.
    static func isRegularFile(_ path: String) -> Bool {
        actionUIWinUIIsRegularFile(path)
    }
}
