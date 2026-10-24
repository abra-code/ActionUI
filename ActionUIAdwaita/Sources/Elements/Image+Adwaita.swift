// Sources/Elements/Image+Adwaita.swift
/*
 Image on GTK. What it shows is chosen as on Apple: the value set at run time (a String, read with
 ImageSource's "mixed" rules) over the properties, of which the first that can be shown wins
 (filePath, resourceName, assetName, systemName; a filePath whose extension is not an image's is
 skipped, one without an extension shows the photo symbol).

 - A symbol (an SF Symbol name) is the Adwaita icon SymbolNames gives, drawn in the text color, in a
   GtkImage sized from the font: 1.1em at medium scale, 16 px at GNOME's default 11 pt. (SwiftUI's
   symbols are 1.25 times the font, measured on macOS, which would give 18 px here, larger than
   GNOME's own icons.) Small is 0.9em and large 1.4em: SwiftUI's small and large are 0.82 and 1.3
   times its medium.
 - A resizable symbol (resizable with a contentMode, as on Apple) scales to its frame: a widget that
   looks the icon up at the size it draws it, fitted or filled, in the text color. Its natural size
   is the symbol's; given a width, it is as tall as wide (height for width), as SwiftUI's fitted
   symbol is.
 - A file is a GtkPicture at the image's own size; resizable with a contentMode, it scales to its
   frame keeping its aspect ratio (fit: contain; fill: cover, clipped to the frame, where SwiftUI
   draws past it). A file that does not exist shows the photo symbol, as on Apple; one GTK cannot
   decode shows nothing (Apple: the photo symbol), since telling would mean decoding it on every
   sync. A PDF is not an image on Linux.
 - An assetName names an icon of the icon theme, where Linux programs install their own images;
   Linux has no asset catalogs. A runtime value is a theme icon only when SymbolNames does not know
   the name: the theme has full-color icons for many symbol names ("folder"). resourceName finds no
   resource: Linux programs have no bundle.

 The three kinds are three widget types, so a value that turns a symbol into a file replaces the
 widget (widgetKind).
*/

import CAdwaita

nonisolated(unsafe) private var scalableIconWidgetType: GType = 0
private let imageStateKey = AttachKey<ImageState>("actionui-image-state")

/// What an Image shows, resolved from its value and properties.
enum ImageContent: Equatable {
    /// An SF Symbol name.
    case symbol(String)
    /// An icon theme name, from assetName.
    case themeIcon(String)
    /// An image file's path.
    case file(String)
}

/// What the widget shows now, kept on it so update changes only what differs, and read by the
/// scalable icon's drawing.
@MainActor private final class ImageState {
    /// The kind of widget it is on.
    let kind: Image.Kind
    var path: String?
    var iconName: String?
    var fill = false
    /// The scalable icon's natural size, in em of the font.
    var em = 1.1

    init(kind: Image.Kind) {
        self.kind = kind
    }
}

extension Image: ActionUIAdwaitaRenderer {
    enum Kind: Int {
        case icon = 0, picture, scalableIcon
    }

    /// Icon sizes, in em of the font, for the image scales (nil: medium).
    static func iconSize(_ scale: Props.ImageScale?) -> Double {
        switch scale {
        case .small: return 0.9
        case .medium, nil: return 1.1
        case .large: return 1.4
        }
    }

    /// File name extensions of images GTK's loaders read (some need a loader installed).
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "svg", "svgz", "webp", "bmp", "tif", "tiff",
                                               "ico", "xpm", "tga", "avif", "heic", "heif", "jxl", "qoi"]

    static func widgetKind(_ node: RenderNode) -> Int {
        let props = Props(node.properties)
        return kind(content(node, props), props).rawValue
    }

    static func kind(_ content: ImageContent, _ props: Props) -> Kind {
        switch content {
        case .file: return .picture
        case .symbol, .themeIcon: return isResizable(props) ? .scalableIcon : .icon
        }
    }

    static func makeWidget(_ node: RenderNode) -> WidgetPointer {
        let widget: WidgetPointer
        // The kind the node recorded, not a second look: if a file appeared or went in between,
        // the widget would be of a kind the node never replaces, and update would mark the node
        // dirty in every flush.
        let kind = Kind(rawValue: node.widgetKind) ?? .icon
        switch kind {
        case .icon:
            widget = gtk_image_new()!
        case .picture:
            widget = gtk_picture_new()!
        case .scalableIcon:
            widget = typed(OpaquePointer(g_object_new_with_properties(scalableIconType(), 0, nil, nil)!))
        }
        attach(ImageState(kind: kind), to: widget, key: imageStateKey)
        return widget
    }

    static func update(_ widget: WidgetPointer, _ node: RenderNode) {
        guard let state = attached(on: widget, key: imageStateKey) else { return }
        let props = Props(node.properties)
        let content = content(node, props)
        let resizable = isResizable(props)
        // A file that appeared or went since widgetKind looked: the next sync makes the right
        // widget. Nothing observes a file, so the node is marked here.
        guard kind(content, props) == state.kind else {
            SyncScheduler.shared.markDirty(node)
            return
        }
        switch content {
        case .file(let path):
            let picture = opaque(widget)
            if state.path != path {
                state.path = path
                gtk_picture_set_filename(picture, path)
            }
            let canShrink: gboolean = resizable ? 1 : 0
            if gtk_picture_get_can_shrink(picture) != canShrink {
                gtk_picture_set_can_shrink(picture, canShrink)
            }
            let fit = resizable && props.contentMode == .fill ? GTK_CONTENT_FIT_COVER : GTK_CONTENT_FIT_CONTAIN
            if gtk_picture_get_content_fit(picture) != fit {
                gtk_picture_set_content_fit(picture, fit)
            }
            setExpands(widget, resizable)
        case .symbol, .themeIcon:
            let name = iconName(content)
            if resizable {
                let fill = props.contentMode == .fill
                let em = iconSize(props.imageScale)
                if state.iconName != name || state.fill != fill || state.em != em {
                    let resize = state.em != em
                    state.iconName = name
                    state.fill = fill
                    state.em = em
                    if resize { gtk_widget_queue_resize(widget) }
                    gtk_widget_queue_draw(widget)
                }
                setExpands(widget, true)
            } else {
                let image = opaque(widget)
                if swiftString(gtk_image_get_icon_name(image)) != name {
                    gtk_image_set_from_icon_name(image, name)
                }
                StyleSheet.shared.apply(["-gtk-icon-size: \(iconSize(props.imageScale))em;"], to: widget, slot: "iconSize")
            }
        }
    }

    /// Resizing applies when a content mode goes with it, as on Apple (resizable alone keeps the
    /// image at its own size).
    static func isResizable(_ props: Props) -> Bool {
        props.resizable && props.contentMode != nil
    }

    private static func setExpands(_ widget: WidgetPointer, _ expands: Bool) {
        let value: gboolean = expands ? 1 : 0
        if gtk_widget_get_hexpand(widget) != value { gtk_widget_set_hexpand(widget, value) }
        if gtk_widget_get_vexpand(widget) != value { gtk_widget_set_vexpand(widget, value) }
    }

    // MARK: What to show

    /// What the image shows: the runtime value when it is a non-empty String, else the first
    /// source that can be shown, else the photo symbol. Tracked reads of the value and properties.
    static func content(_ node: RenderNode, _ props: Props) -> ImageContent {
        if let value = node.model.value as? String, !value.isEmpty {
            return content(ImageSource.resolve(value, interpretation: "mixed", lookup: lookup))
        }
        let source = props.sources.first { source in
            if case .filePath(let path) = source { return !hasExtension(path) || isImageFile(path) }
            return true
        }
        switch source {
        case .filePath(let path)?:
            return content(ImageSource.resolve(path, interpretation: "path", lookup: lookup))
        case .resourceName(let name)?:
            return content(ImageSource.resolve(name, interpretation: "resourceName", lookup: lookup))
        case .assetName(let name)?:
            return .themeIcon(name)
        case .systemName(let name)?:
            return .symbol(name)
        case nil:
            return .symbol(ImageSource.placeholderSymbol)
        }
    }

    /// What a resolved source shows: a file that does not exist is the photo symbol.
    static func content(_ source: ImageSource) -> ImageContent {
        switch source {
        case .filePath(let path):
            return g_file_test(path, G_FILE_TEST_IS_REGULAR) != 0 ? .file(path) : .symbol(ImageSource.placeholderSymbol)
        case .systemName(let name):
            return .symbol(name)
        case .assetName(let name):
            return .themeIcon(name)
        }
    }

    /// ImageSource's platform checks on Linux: image files by extension, no bundled resources,
    /// assets as icons of the icon theme that are not symbol names.
    static var lookup: ImageSource.Lookup {
        ImageSource.Lookup(
            isImageFile: { isImageFile($0) },
            resourcePath: { _ in nil },
            assetExists: { hasThemeIcon($0) && SymbolNames.lookup($0) == nil }
        )
    }

    static func isImageFile(_ path: String) -> Bool {
        pathExtension(path).map { imageExtensions.contains($0.lowercased()) } ?? false
    }

    static func hasExtension(_ path: String) -> Bool {
        pathExtension(path) != nil
    }

    /// The extension of the path's last component, nil when it has none (a leading dot starts a
    /// name, not an extension).
    private static func pathExtension(_ path: String) -> Substring? {
        let name = path.split(separator: "/").last ?? ""
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex, name.index(after: dot) != name.endIndex else { return nil }
        return name[name.index(after: dot)...]
    }

    /// The icon theme name a symbol or theme icon shows.
    static func iconName(_ content: ImageContent) -> String {
        switch content {
        case .symbol(let name): return SymbolNames.iconName(name)
        case .themeIcon(let name): return hasThemeIcon(name) ? name : SymbolNames.missing
        case .file: return SymbolNames.missing
        }
    }

    static func hasThemeIcon(_ name: String) -> Bool {
        guard let display = gdk_display_get_default() else { return false }
        return gtk_icon_theme_has_icon(gtk_icon_theme_get_for_display(display), name) != 0
    }

    // MARK: Scalable icon

    /// A GtkWidget subclass that draws its ImageState's icon at the size it is given, fitted (the
    /// smaller side) or filled (the larger side), centered, recolored with the text color as
    /// GtkImage recolors symbolic icons. Its natural size is the symbol's at the widget's font
    /// (ImageState.em), and given one side, the other is as long (the icon is square); its minimum
    /// is 0.
    static func scalableIconType() -> GType {
        if scalableIconWidgetType != 0 { return scalableIconWidgetType }
        var info = GTypeInfo()
        info.class_size = guint16(MemoryLayout<GtkWidgetClass>.size)
        info.instance_size = guint16(MemoryLayout<GtkWidget>.size)
        info.class_init = { klass, _ in
            guard let klass else { return }
            let widgetClass = klass.assumingMemoryBound(to: GtkWidgetClass.self)
            widgetClass.pointee.get_request_mode = { _ in GTK_SIZE_REQUEST_HEIGHT_FOR_WIDTH }
            widgetClass.pointee.measure = { widget, _, forSize, minimum, natural, minimumBaseline, naturalBaseline in
                let length = forSize >= 0 ? forSize : MainActor.assumeIsolated {
                    widget.map { Image.naturalIconLength($0) } ?? 16
                }
                minimum?.pointee = 0
                natural?.pointee = length
                minimumBaseline?.pointee = -1
                naturalBaseline?.pointee = -1
            }
            widgetClass.pointee.snapshot = { widget, snapshot in
                guard let widget, let snapshot else { return }
                MainActor.assumeIsolated { Image.drawScalableIcon(widget, snapshot) }
            }
            gtk_widget_class_set_css_name(widgetClass, "actionui-icon")
            gtk_widget_class_set_accessible_role(widgetClass, GTK_ACCESSIBLE_ROLE_IMG)
        }
        scalableIconWidgetType = g_type_register_static(gtk_widget_get_type(), "ActionUIScalableIcon", &info, GTypeFlags(0))
        return scalableIconWidgetType
    }

    /// The scalable icon's natural side: its em times the widget's font size in pixels.
    private static func naturalIconLength(_ widget: WidgetPointer) -> Int32 {
        let em = attached(on: widget, key: imageStateKey)?.em ?? iconSize(nil)
        let context = gtk_widget_get_pango_context(widget)
        guard let font = pango_context_get_font_description(context) else { return Int32((16 / iconSize(nil) * em).rounded()) }
        var pixels = Double(pango_font_description_get_size(font)) / Double(PANGO_SCALE)
        if pango_font_description_get_size_is_absolute(font) == 0 {
            // Points: GTK's resolution is in dots per inch, 96 unless the desktop sets another.
            let resolution = pango_cairo_context_get_resolution(context)
            pixels *= (resolution > 0 ? resolution : 96) / 72
        }
        return Int32((pixels * em).rounded())
    }

    private static func drawScalableIcon(_ widget: WidgetPointer, _ snapshot: OpaquePointer) {
        guard let state = attached(on: widget, key: imageStateKey), let name = state.iconName,
              let display = gtk_widget_get_display(widget) else { return }
        let width = Double(gtk_widget_get_width(widget))
        let height = Double(gtk_widget_get_height(widget))
        let side = state.fill ? max(width, height) : min(width, height)
        guard side >= 1 else { return }
        let theme = gtk_icon_theme_get_for_display(display)
        guard let lookedUp = gtk_icon_theme_lookup_icon(theme, name, nil, Int32(side.rounded(.up)),
                                                    gtk_widget_get_scale_factor(widget),
                                                    gtk_widget_get_direction(widget), GtkIconLookupFlags(0)) else { return }
        let icon = OwnedObject(adopting: lookedUp)
        // The text color, then libadwaita's error, warning and success colors, which a symbolic
        // icon's other parts use.
        var colors = [GdkRGBA](repeating: GdkRGBA(), count: 4)
        gtk_widget_get_color(widget, &colors[0])
        colors[1] = GdkRGBA(red: 0.878, green: 0.106, blue: 0.141, alpha: 1)
        colors[2] = GdkRGBA(red: 0.804, green: 0.576, blue: 0.035, alpha: 1)
        colors[3] = GdkRGBA(red: 0.180, green: 0.761, blue: 0.494, alpha: 1)
        gtk_snapshot_save(snapshot)
        var origin = graphene_point_t(x: Float((width - side) / 2), y: Float((height - side) / 2))
        gtk_snapshot_translate(snapshot, &origin)
        gtk_symbolic_paintable_snapshot_symbolic(icon.opaquePointer, snapshot, side, side, colors, 4)
        gtk_snapshot_restore(snapshot)
    }
}
