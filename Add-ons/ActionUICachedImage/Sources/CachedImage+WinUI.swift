// Add-ons/ActionUICachedImage/Sources/CachedImage+WinUI.swift
/*
 The CachedImage element on Windows, the counterpart of CachedImage.swift and CachedImage+Adwaita.swift: the same
 JSON (the sample and the properties are in CachedImage.swift) over AsyncImageCache's ImageStore.

 What the element is for is a box reserved before the pixels arrive. As on Apple and Linux:
 - The box has the aspect of the intrinsicSize hint, else of the size the cache knows, else 4:3. It takes the width it
   is offered and from that its height (a SwiftUI aspectRatio with .fit, measured, which a stack packs against), and
   is fitted and centered in what it is given.
 - While loading, the box shows the image's placeholder grid, stretched into a soft preview, else a light gray.
 - The image draws in the box, "fill" covering it and "fit" inside it, clipped to the box's rounded corners
   ("cornerRadius", here on the box: the renderer's own clip of the element is the same shape, or rounds only the
   empty space around a box fitted in a taller slot).
 The image is the store's PlatformImage.imageSource, a WinUI image source the store made once and every element showing
 that image shares (a BitmapImage WinUI decodes at the width the store asks for, since AsyncImageCache 0.2.8): its
 pixels are in memory once. The store is asked for no corners; this element rounds them with its box.

 Built only from ActionUI's interface for add-ons (ActionUIWinUIElement, RenderNode) and the shim's C functions
 (CWinUI): a panel with its own layout, a rounded box, an Image.
*/

#if os(Windows)

import ActionUI
import AsyncImageCache
import CWinUI
import FoundationEssentials

/// One reference to a WinUI object of the shim's, given back when this goes.
final class ShimObject {
    let pointer: OpaquePointer

    init?(adopting pointer: OpaquePointer?) {
        guard let pointer else { return nil }
        self.pointer = pointer
    }

    deinit {
        actionUIWinUIRelease(pointer)
    }
}

/// The shim's last error on this thread, for the log.
private func lastShimError() -> String {
    var buffer = [CChar](repeating: 0, count: 1024)
    let copied = buffer.withUnsafeMutableBufferPointer { actionUIWinUICopyLastError($0.baseAddress, $0.count) }
    let message = copied ? String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self) : ""
    return message.isEmpty ? "(no message)" : message
}

/// What an element instance keeps (RenderNode.state): its WinUI objects, what to show, and what it asked the store for.
@MainActor
final class CachedImageState {
    /// The element's object: a panel that lays out the box (measureLayout, arrangeLayout).
    let panel: ShimObject
    private let box: ShimObject
    private let picture: ShimObject
    private(set) var request: ImageRequest?
    /// What `picture` shows, kept while it does: the image source it was given is borrowed from it.
    private var shown: PlatformImage?
    private var showsPlaceholder = false
    /// The source's natural size: the hint, else what the cache knows, else nil.
    private var hint: ImageSize?
    private var known: ImageSize?
    private var fills = true
    private var cornerRadius = 0.0
    let store: ImageStore

    /// The light gray of a box with nothing to show yet (the Linux element's).
    private static let empty = ActionUIWinUIColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 0.12)

    init?(store: ImageStore = .shared, logger: any ActionUILogger) {
        guard let picture = ShimObject(adopting: actionUIWinUIImageCreate()),
              let box = ShimObject(adopting: actionUIWinUIRoundedBoxCreate(picture.pointer)) else {
            logger.log("CachedImage: making its image failed: \(lastShimError())", .error)
            return nil
        }
        self.picture = picture
        self.box = box
        self.store = store
        let context = Unmanaged.passRetained(WeakCachedImageState()).toOpaque()
        guard let panel = ShimObject(adopting: actionUIWinUIPanelCreate(measureCachedImage, arrangeCachedImage, context,
                                                                        releaseCachedImageContext)) else {
            logger.log("CachedImage: making its panel failed: \(lastShimError())", .error)
            return nil
        }
        self.panel = panel
        Unmanaged<WeakCachedImageState>.fromOpaque(context).takeUnretainedValue().state = self
        guard actionUIWinUIPanelInsertChild(panel.pointer, 0, box.pointer) else {
            logger.log("CachedImage: placing its image failed: \(lastShimError())", .error)
            return nil
        }
        showNothing()
    }

    /// The width to the box's height, from the hint, else the known size, else a neutral 4:3.
    var aspect: Double {
        guard let size = hint ?? known, size.width > 0, size.height > 0 else {
            return 4.0 / 3.0
        }
        return size.width / size.height
    }

    /// The width the element asks for when it is offered any: the source's, else a width to reserve until it is
    /// known.
    var naturalWidth: Double {
        (hint ?? known)?.width ?? 320
    }

    func apply(hint: ImageSize?, fills: Bool, cornerRadius: Double) {
        let changed = hint != self.hint || fills != self.fills || max(0, cornerRadius) != self.cornerRadius
        let restretch = fills != self.fills
        self.hint = hint
        self.fills = fills
        self.cornerRadius = max(0, cornerRadius)
        if restretch, shown != nil, !showsPlaceholder {
            _ = actionUIWinUIImageSetStretch(picture.pointer, fills ? ActionUIWinUIImageStretchFill : ActionUIWinUIImageStretchFit)
        }
        // A new aspect or width is measured; the corners are set as the box is placed, which a measure brings.
        if changed {
            _ = actionUIWinUIElementInvalidateMeasure(panel.pointer)
        }
    }

    /// Shows `newRequest`'s image: at once if the cache has it, else the placeholder until it has loaded. A URL that
    /// gave no image is not asked for again until the request changes.
    func load(_ newRequest: ImageRequest?) {
        guard newRequest != request else { return }
        request = newRequest
        known = nil
        defer {
            _ = actionUIWinUIElementInvalidateMeasure(panel.pointer)
        }
        guard let newRequest else {
            showNothing()
            return
        }
        known = store.cachedPixelSize(for: newRequest.url)
        if let cached = store.cachedImage(for: newRequest) {
            show(cached, placeholder: false)
            return
        }
        if let placeholder = store.placeholderImage(for: newRequest.url) {
            show(placeholder, placeholder: true)
        } else {
            showNothing()
        }
        store.load(newRequest) { [weak self] image in
            // Completions run on the main dispatch queue, which the WinUI renderer drains on its UI thread.
            MainActor.assumeIsolated {
                // The element may have moved on to another URL while this one loaded.
                guard let self, self.request == newRequest else { return }
                self.known = self.store.cachedPixelSize(for: newRequest.url) ?? self.known
                if let image {
                    self.show(image, placeholder: false)
                }
                _ = actionUIWinUIElementInvalidateMeasure(self.panel.pointer)
            }
        }
    }

    private func show(_ image: PlatformImage, placeholder: Bool) {
        guard let source = image.imageSource else {
            ActionUIModel.shared.logger.log("CachedImage: no WinUI image source could be made for the image", .warning)
            showNothing()
            return
        }
        guard actionUIWinUIImageSetSource(picture.pointer, source) else {
            ActionUIModel.shared.logger.log("CachedImage: WinUI cannot show the image: \(lastShimError())", .warning)
            showNothing()
            return
        }
        shown = image
        showsPlaceholder = placeholder
        // The grid was sampled by squishing the whole image into a square, so stretching it gives back its proportions.
        let stretch = placeholder ? ActionUIWinUIImageStretchToSize : (fills ? ActionUIWinUIImageStretchFill : ActionUIWinUIImageStretchFit)
        _ = actionUIWinUIImageSetStretch(picture.pointer, stretch)
        _ = actionUIWinUIElementSetBrush(box.pointer, ActionUIWinUIBrushBackground, nil, nil)
    }

    private func showNothing() {
        _ = actionUIWinUIImageSetSource(picture.pointer, nil)
        shown = nil
        showsPlaceholder = false
        var gray = Self.empty
        _ = actionUIWinUIElementSetBrush(box.pointer, ActionUIWinUIBrushBackground, &gray, nil)
    }

    // MARK: - Layout

    func measure(_ available: ActionUIWinUISize) -> ActionUIWinUISize {
        let width = available.width.isFinite ? available.width : naturalWidth
        var size = ActionUIWinUISize(width: width, height: width / aspect)
        if size.height.isNaN || !size.height.isFinite {
            size.height = 0
        }
        let box = Self.fitted(aspect: aspect, in: size)
        _ = actionUIWinUIElementMeasure(self.box.pointer, ActionUIWinUISize(width: box.width, height: box.height))
        return size
    }

    func arrange(_ size: ActionUIWinUISize) {
        let frame = Self.fitted(aspect: aspect, in: size)
        _ = actionUIWinUIRoundedBoxSetCornerRadius(box.pointer, min(cornerRadius, min(frame.width, frame.height) / 2))
        _ = actionUIWinUIElementArrange(box.pointer, frame)
    }

    /// The largest box of `aspect` inside `space`, centered: SwiftUI's aspectRatio with .fit.
    static func fitted(aspect: Double, in space: ActionUIWinUISize) -> ActionUIWinUIRect {
        guard aspect > 0, aspect.isFinite, space.width >= 0, space.height >= 0 else {
            return ActionUIWinUIRect(x: 0, y: 0, width: 0, height: 0)
        }
        let width = min(space.width, space.height * aspect)
        let height = width / aspect
        return ActionUIWinUIRect(x: (space.width - width) / 2, y: (space.height - height) / 2, width: width, height: height)
    }
}

/// The panel callbacks' context: the state, not kept alive by it (the node keeps the state).
@MainActor
private final class WeakCachedImageState {
    weak var state: CachedImageState?
}

private let measureCachedImage: ActionUIWinUIMeasureCallback = { context, _, available in
    let weak = context.map { Unmanaged<WeakCachedImageState>.fromOpaque($0).takeUnretainedValue() }
    return MainActor.assumeIsolated {
        guard let size = weak?.state?.measure(available) else { return ActionUIWinUISize(width: 0, height: 0) }
        // WinUI gets no more than it offered.
        return ActionUIWinUISize(width: min(size.width, available.width), height: min(size.height, available.height))
    }
}

private let arrangeCachedImage: ActionUIWinUIArrangeCallback = { context, _, finalSize in
    let weak = context.map { Unmanaged<WeakCachedImageState>.fromOpaque($0).takeUnretainedValue() }
    MainActor.assumeIsolated {
        weak?.state?.arrange(finalSize)
    }
}

private let releaseCachedImageContext: ActionUIWinUICallback = { context in
    guard let context else { return }
    Unmanaged<WeakCachedImageState>.fromOpaque(context).release()
}

struct CachedImage: ActionUIWinUIElement {
    // The element's runtime value is the image URL string (like the core AsyncImage element).
    static var valueType: Any.Type { String.self }

    // "" (not nil) when no value is set yet, so the String valueType has an initial value; an empty string means
    // "no runtime source", and update then falls back to the "url" property.
    static var initialValue: (ViewModel) -> Any? { { model in (model.value as? String) ?? "" } }
    static var initialStates: (ViewModel) -> [String: Any] { { model in model.states } }
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? { nil }
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? { nil }
    static var insertableContainers: [String: ContainerShape]? { nil }

    static func makeView(_ node: RenderNode) -> OpaquePointer? {
        guard let state = CachedImageState(logger: ActionUIModel.shared.logger) else { return nil }
        node.state = state
        // The node takes over a reference of its own; the state keeps its own.
        return actionUIWinUIRetain(state.panel.pointer)
    }

    static func update(_ view: OpaquePointer, _ node: RenderNode) {
        guard let state = node.state as? CachedImageState else { return }
        let properties = node.properties
        state.apply(hint: intrinsicSize(properties["intrinsicSize"]),
                    fills: properties["contentMode"] as? String != "fit",
                    cornerRadius: number(properties["cornerRadius"]) ?? 0)
        // The runtime value wins, else the "url" property; nil or not a URL shows the light gray box.
        let runtime = (node.model.value as? String).flatMap { $0.isEmpty ? nil : $0 }
        // A file: URL only when the content may read the file Windows opens for it (a host is a share), as for the
        // built-in Image's file; asked before the store touches the path.
        let url = (runtime ?? (properties["url"] as? String)).flatMap { $0.isEmpty ? nil : URL(string: $0) }
            .flatMap { $0.isFileURL && !node.readsFileURL($0) ? nil : $0 }
        state.load(url.map { ImageRequest(url: $0, targetWidth: number(properties["maxPixelWidth"])) })
    }

    /// The width it is offered, as the SwiftUI view takes it; its height follows.
    static func expansion(_ node: RenderNode) -> ActionUIExpansion {
        .horizontal
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
