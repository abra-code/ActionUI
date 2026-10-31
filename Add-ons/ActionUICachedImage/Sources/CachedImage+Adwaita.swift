// Add-ons/ActionUICachedImage/Sources/CachedImage+Adwaita.swift
/*
 The CachedImage element on Linux, the counterpart of CachedImage.swift and of AsyncImageCache's SwiftUI view,
 which has no Linux version: the same JSON (the sample and the properties are in CachedImage.swift) over
 AsyncImageCache's ImageStore.

 What the element is for is a box reserved before the pixels arrive, so a small widget of its own draws it. GTK's
 own widgets cannot: a GtkAspectFrame has no height for a width, and a GtkPicture is as big as what it shows,
 which is the tiny placeholder until the image loads. As the SwiftUI view does:
 - The box has the aspect of the intrinsicSize hint, else of the size the cache knows, else 4:3. It is fitted in
   what the widget is given, centered. It takes the width it is offered, and from that the height of its box:
   a SwiftUI aspectRatio with .fit, measured, which a stack packs against, not the greedy view it wraps.
 - While loading, the box shows the image's placeholder grid, stretched into a soft preview, else a light gray.
 - The image draws in the box, "fill" covering it and "fit" inside it, clipped to the box's rounded corners. The
   base View modifier could only round the widget, around the box: so "cornerRadius" is handled here.
*/

#if os(Linux)

import ActionUI
import AsyncImageCache
import CAdwaita
import FoundationEssentials

/// What an element instance keeps (RenderNode.state): what to draw, and what it has asked the store for.
@MainActor
final class CachedImageState {
    let widget: UnsafeMutablePointer<GtkWidget>
    private(set) var image: PlatformImage?
    private(set) var placeholder: PlatformImage?
    private(set) var request: ImageRequest?
    /// The source's natural size: the hint, else what the cache knows, else nil.
    private var hint: ImageSize?
    private var known: ImageSize?
    private var fills = true
    private var cornerRadius = 0.0
    let store: ImageStore

    init(widget: UnsafeMutablePointer<GtkWidget>, store: ImageStore = .shared) {
        self.widget = widget
        self.store = store
    }

    /// The width to box's height, from the hint, else the known size, else a neutral 4:3.
    var aspect: Double {
        guard let size = hint ?? known, size.width > 0, size.height > 0 else {
            return 4.0 / 3.0
        }
        return size.width / size.height
    }

    /// The width the widget asks for: the source's, else a width to reserve until it is known.
    var naturalWidth: Double {
        (hint ?? known)?.width ?? 320
    }

    func apply(hint: ImageSize?, fills: Bool, cornerRadius: Double) {
        let oldAspect = aspect
        let oldWidth = naturalWidth
        let changed = fills != self.fills || cornerRadius != self.cornerRadius
        self.hint = hint
        self.fills = fills
        self.cornerRadius = cornerRadius
        if aspect != oldAspect || naturalWidth != oldWidth {
            gtk_widget_queue_resize(widget)
        } else if changed {
            gtk_widget_queue_draw(widget)
        }
    }

    /// Shows `newRequest`'s image: at once if the cache has it, else the placeholder until it has loaded. A URL that
    /// gave no image is not asked for again until the request changes.
    func load(_ newRequest: ImageRequest?) {
        guard newRequest != request else { return }
        request = newRequest
        image = nil
        placeholder = nil
        known = nil
        defer { imageChanged() }
        guard let newRequest else { return }
        known = store.cachedPixelSize(for: newRequest.url)
        if let cached = store.cachedImage(for: newRequest) {
            image = cached
            return
        }
        placeholder = store.placeholderImage(for: newRequest.url)
        store.load(newRequest) { [weak self] image in
            // Completions run on the GLib main context's thread, the main thread.
            MainActor.assumeIsolated {
                // The element may have moved on to another URL while this one loaded.
                guard let self, self.request == newRequest else { return }
                self.image = image
                self.known = self.store.cachedPixelSize(for: newRequest.url) ?? self.known
                self.imageChanged()
            }
        }
    }

    // A new size is possible; a new picture is certain, and a resize to the same size draws nothing.
    private func imageChanged() {
        gtk_widget_queue_resize(widget)
        gtk_widget_queue_draw(widget)
    }

    /// Draws the box in the widget's `width` and `height`.
    func draw(_ snapshot: OpaquePointer, width: Double, height: Double) {
        let box = Self.fitted(aspect: aspect, in: (width, height))
        guard box.width > 0, box.height > 0 else { return }
        var bounds = rect(box.x, box.y, box.width, box.height)
        var rounded = GskRoundedRect()
        gsk_rounded_rect_init_from_rect(&rounded, &bounds, Float(cornerRadius))
        gtk_snapshot_push_rounded_clip(snapshot, &rounded)
        if let image {
            let source = (Double(image.pixelWidth), Double(image.pixelHeight))
            let place = fills ? Self.covering(source, box) : Self.fitting(source, box)
            var drawn = rect(place.x, place.y, place.width, place.height)
            gtk_snapshot_append_scaled_texture(snapshot, image.texture, GSK_SCALING_FILTER_TRILINEAR, &drawn)
        } else if let placeholder {
            // Stretched: the grid was sampled by squishing the whole image, so this gives back its proportions.
            gtk_snapshot_append_scaled_texture(snapshot, placeholder.texture, GSK_SCALING_FILTER_LINEAR, &bounds)
        } else {
            var gray = GdkRGBA(red: 0.5, green: 0.5, blue: 0.5, alpha: 0.12)
            gtk_snapshot_append_color(snapshot, &gray, &bounds)
        }
        gtk_snapshot_pop(snapshot)
    }

    private func rect(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> graphene_rect_t {
        graphene_rect_t(origin: graphene_point_t(x: Float(x), y: Float(y)),
                        size: graphene_size_t(width: Float(width), height: Float(height)))
    }

    typealias Rectangle = (x: Double, y: Double, width: Double, height: Double)

    /// The largest box of `aspect` inside `space`, centered: SwiftUI's aspectRatio with .fit.
    static func fitted(aspect: Double, in space: (width: Double, height: Double)) -> Rectangle {
        let width = min(space.width, space.height * aspect)
        let height = width / aspect
        return ((space.width - width) / 2, (space.height - height) / 2, width, height)
    }

    /// A `source` size scaled to fit inside `box`, centered in it.
    static func fitting(_ source: (Double, Double), _ box: Rectangle) -> Rectangle {
        place(source, box, scale: min(box.width / source.0, box.height / source.1))
    }

    /// A `source` size scaled to cover `box`, centered on it; the clip cuts what falls outside.
    static func covering(_ source: (Double, Double), _ box: Rectangle) -> Rectangle {
        place(source, box, scale: max(box.width / source.0, box.height / source.1))
    }

    private static func place(_ source: (Double, Double), _ box: Rectangle, scale: Double) -> Rectangle {
        let width = source.0 * scale
        let height = source.1 * scale
        return (box.x + (box.width - width) / 2, box.y + (box.height - height) / 2, width, height)
    }
}

/// The widget that reserves and draws the box: a GtkWidget subclass with height for width.
private enum CachedImageWidget {
    private static let stateKey = "actionui-cached-image-state"
    /// More than any screen, with room for what GTK and the containers add to it.
    private static let longestNaturalSize = 16_777_216.0

    @MainActor private static let type: GType = {
        var info = GTypeInfo()
        info.class_size = guint16(MemoryLayout<GtkWidgetClass>.size)
        info.class_init = { klass, _ in
            guard let klass else { return }
            let widgetClass = klass.assumingMemoryBound(to: GtkWidgetClass.self)
            widgetClass.pointee.get_request_mode = { _ in GTK_SIZE_REQUEST_HEIGHT_FOR_WIDTH }
            widgetClass.pointee.measure = measure
            widgetClass.pointee.snapshot = snapshot
            gtk_widget_class_set_accessible_role(widgetClass, GTK_ACCESSIBLE_ROLE_IMG)
            gtk_widget_class_set_css_name(widgetClass, "actionui-cached-image")
        }
        info.instance_size = guint16(MemoryLayout<GtkWidget>.size)
        return g_type_register_static(gtk_widget_get_type(), "ActionUICachedImageWidget", &info, GTypeFlags(0))
    }()

    /// A new widget, floating, and the element's state. The widget owns the state, which it reads while it measures
    /// and draws: GTK can keep a widget for a moment after its node has gone. The state's pointer back is not a
    /// reference, and the state goes with the widget, so it never outlives it.
    @MainActor static func make() -> (widget: UnsafeMutablePointer<GtkWidget>, state: CachedImageState) {
        let object = g_object_new_with_properties(type, 0, nil, nil)!
        let widget = UnsafeMutableRawPointer(object).assumingMemoryBound(to: GtkWidget.self)
        let state = CachedImageState(widget: widget)
        g_object_set_data_full(object, stateKey,
                               Unmanaged.passRetained(state).toOpaque()) { data in
            if let data {
                Unmanaged<CachedImageState>.fromOpaque(data).release()
            }
        }
        return (widget, state)
    }

    private static func state(of widget: UnsafeMutablePointer<GtkWidget>?) -> CachedImageState? {
        guard let widget,
              let data = g_object_get_data(UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GObject.self), stateKey) else {
            return nil
        }
        return Unmanaged<CachedImageState>.fromOpaque(data).takeUnretainedValue()
    }

    private static let measure: @convention(c) (UnsafeMutablePointer<GtkWidget>?, GtkOrientation, Int32,
                                                UnsafeMutablePointer<Int32>?, UnsafeMutablePointer<Int32>?,
                                                UnsafeMutablePointer<Int32>?, UnsafeMutablePointer<Int32>?) -> Void = {
        widget, orientation, forSize, minimum, natural, minimumBaseline, naturalBaseline in
        minimum?.pointee = 0
        natural?.pointee = 0
        minimumBaseline?.pointee = -1
        naturalBaseline?.pointee = -1
        // GTK measures on its main thread, the main actor's.
        nonisolated(unsafe) let target = widget
        let size = MainActor.assumeIsolated { () -> Double in
            guard let state = state(of: target) else { return 0 }
            if orientation == GTK_ORIENTATION_HORIZONTAL {
                return forSize >= 0 ? Double(forSize) * state.aspect : state.naturalWidth
            }
            return (forSize >= 0 ? Double(forSize) : state.naturalWidth) / state.aspect
        }
        // A hint may be any positive number, and Int32() traps on what does not fit. NaN is 0 x an endless aspect.
        natural?.pointee = size.isNaN ? 0 : Int32(min(size.rounded(.up), longestNaturalSize))
    }

    private static let snapshot: @convention(c) (UnsafeMutablePointer<GtkWidget>?, OpaquePointer?) -> Void = { widget, snapshot in
        guard let widget, let snapshot else { return }
        // GTK draws on its main thread, the main actor's.
        nonisolated(unsafe) let target = (widget, snapshot)
        MainActor.assumeIsolated {
            state(of: target.0)?.draw(target.1, width: Double(gtk_widget_get_width(target.0)),
                                      height: Double(gtk_widget_get_height(target.0)))
        }
    }
}

struct CachedImage: ActionUIAdwaitaElement {
    // The element's runtime value is the image URL string (like the core AsyncImage element).
    static var valueType: Any.Type { String.self }

    // "" (not nil) when no value is set yet, so the String valueType has an initial value; an empty string means
    // "no runtime source", and update then falls back to the "url" property.
    static var initialValue: (ViewModel) -> Any? { { model in (model.value as? String) ?? "" } }
    static var initialStates: (ViewModel) -> [String: Any] { { model in model.states } }
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? { nil }
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? { nil }
    static var insertableContainers: [String: ContainerShape]? { nil }

    // The base modifier would round the widget, around the box: the element rounds the box itself.
    static var handledBaseModifiers: Set<String> { ["cornerRadius"] }

    static func makeWidget(_ node: RenderNode) -> OpaquePointer {
        let made = CachedImageWidget.make()
        // The width it is offered; the height follows from it (measure). Not vexpand: a stack would then give it
        // the whole slot and leave gaps around the box, where SwiftUI packs against the box.
        gtk_widget_set_hexpand(made.widget, 1)
        node.state = made.state
        return OpaquePointer(made.widget)
    }

    static func update(_ widget: OpaquePointer, _ node: RenderNode) {
        guard let state = node.state as? CachedImageState else { return }
        let properties = node.properties
        state.apply(hint: intrinsicSize(properties["intrinsicSize"]),
                    fills: properties["contentMode"] as? String != "fit",
                    cornerRadius: number(properties["cornerRadius"]) ?? 0)
        // The runtime value wins, else the "url" property; nil or not a URL shows the placeholder.
        let runtime = (node.model.value as? String).flatMap { $0.isEmpty ? nil : $0 }
        let url = (runtime ?? (properties["url"] as? String)).flatMap { $0.isEmpty ? nil : URL(string: $0) }
        state.load(url.map { ImageRequest(url: $0, targetWidth: number(properties["maxPixelWidth"])) })
    }

    // A number as ActionUI's decoder or a host gives it. A JSON boolean is neither of these.
    static func number(_ value: Any?) -> Double? {
        switch value {
        case let number as any BinaryFloatingPoint: return Double(number)
        case let number as Int: return Double(number)
        default: return nil
        }
    }

    // { "width": Number, "height": Number }, both positive: the box's aspect divides by them.
    static func intrinsicSize(_ value: Any?) -> ImageSize? {
        guard let size = value as? [String: Any], let width = number(size["width"]), let height = number(size["height"]),
              width > 0, height > 0 else {
            return nil
        }
        return ImageSize(width: width, height: height)
    }
}

#endif
