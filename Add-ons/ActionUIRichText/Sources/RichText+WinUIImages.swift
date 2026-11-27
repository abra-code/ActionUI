// Add-ons/ActionUIRichText/Sources/RichText+WinUIImages.swift
/*
 One image in the RichText element's text on Windows, as RichTextGtkImageSlot is in the RichText package's GTK view:
 a panel at the image's place in its paragraph (an inline element of the RichTextBlock), showing a placeholder (a
 rounded box with the alt text, or for a held remote image the host a click would contact) until the image loads
 through AsyncImageCache, then the image at its own size, capped at the same width as on Apple platforms and Linux.

 - Loading follows the element's "remoteImages": an http or https image loads at once ("automatic"), on a click on its
   placeholder ("on-click"), or never ("never"); data: and local file: images always load (a file: image the trust
   policy refused has lost its address and shows as an image that cannot load, RichText+LocalImages.swift), and an
   image whose scheme is not allowed (javascript:, a relative path) never does (RichTextURLPolicy).
 - The placeholder's text is the package's (RichTextImagePlaceholder), the same on every renderer. While it waits for
   a click it also takes keyboard focus (Tab, with the system's focus rectangle), and Enter or Space loads it as a click
   does; the GTK view's placeholder takes no keys. Not yet: the placeholder is the shim's panel, which has no UI
   Automation peer, so a screen reader reads its text but may announce nothing while the panel itself has focus.
 - An image copies as nothing, as an inline element of the text.
*/

#if os(Windows)

import ActionUI
import AsyncImageCache
import CWinUI
import FoundationEssentials
import RichText

@MainActor
final class RichTextWinUIImageSlot {
    /// The width cap in points, and the decode width in pixels (as RichTextImageLoading on Apple platforms and
    /// RichTextGtkImageSlot on Linux).
    static let maxWidth = 320.0
    static let placeholderSize = ActionUIWinUISize(width: 240, height: 120)
    static let placeholderCornerRadius = 6.0
    static let placeholderInset = 8.0

    /// The panel placed in the text, holding the placeholder or the image.
    let panel: ShimObject
    let alt: String
    let url: URL?
    private(set) var hold: RichTextImageHold = .none
    private(set) var failed = false
    private(set) var loaded: PlatformImage?
    private var approved = false
    private var loading = false
    /// The size the panel takes: the placeholder's, then the image's.
    private var size = RichTextWinUIImageSlot.placeholderSize
    /// What the panel shows: the placeholder's box and text, or the image.
    private var box: ShimObject?
    private var label: ShimObject?
    private var picture: ShimObject?
    /// Runs when the slot's size changes (its image arrived): the element lays its text out again.
    var sizeChanged: (() -> Void)?

    init?(alt: String, url: URL?) {
        self.alt = alt
        self.url = url
        let context = Unmanaged.passRetained(WeakImageSlot()).toOpaque()
        guard let panel = ShimObject(adopting: actionUIWinUIPanelCreate(measureImageSlot, arrangeImageSlot, context,
                                                                        releaseWeakImageSlot)) else {
            return nil
        }
        self.panel = panel
        Unmanaged<WeakImageSlot>.fromOpaque(context).takeUnretainedValue().slot = self
        if let box = ShimObject(adopting: actionUIWinUIShapeCreate(ActionUIWinUIShapeRoundedRectangle)) {
            _ = actionUIWinUIElementSetBrush(box.pointer, ActionUIWinUIBrushFill, nil, RichTextWinUIState.codeFillBrush)
            _ = actionUIWinUIShapeSetCornerRadius(box.pointer, Self.placeholderCornerRadius)
            _ = actionUIWinUIPanelInsertChild(panel.pointer, 0, box.pointer)
            self.box = box
        }
        if let label = ShimObject(adopting: actionUIWinUITextBlockCreate()) {
            // Wrapped, never trimmed: the box grows to the whole text (measure). Trimmed, a long alt text would push
            // out the last line, the host a click contacts, and could show a host of its own in its place.
            _ = actionUIWinUITextBlockSetWraps(label.pointer, true)
            _ = actionUIWinUITextBlockSetAlignment(label.pointer, ActionUIWinUITextCenter)
            _ = actionUIWinUIElementSetBrush(label.pointer, ActionUIWinUIBrushForeground, nil, RichTextWinUIState.secondaryBrush)
            _ = actionUIWinUIPanelInsertChild(panel.pointer, Int32(actionUIWinUIPanelChildCount(panel.pointer)), label.pointer)
            self.label = label
        }
        let tapContext = Unmanaged.passRetained(WeakImageSlot(self)).toOpaque()
        _ = actionUIWinUIElementOnTapped(panel.pointer, imageSlotTapped, tapContext, releaseWeakImageSlot)
        // The keyboard's click: focusable only while it waits for one (refresh).
        let keyContext = Unmanaged.passRetained(WeakImageSlot(self)).toOpaque()
        _ = actionUIWinUIElementOnKeyEvents(panel.pointer, imageSlotKey, keyContext, releaseWeakImageSlot)
        _ = actionUIWinUIElementSetSystemFocusVisuals(panel.pointer, true)
        refresh()
    }

    /// The request every lookup and load of this image uses, so they share one cache variant.
    var request: ImageRequest? {
        url.map { ImageRequest(url: $0, targetWidth: Self.maxWidth) }
    }

    /// Shows the image if it is cached, else loads it or holds it as `policy` says. Called again when the
    /// element's "remoteImages" changes.
    func start(policy: RichTextRemoteImages) {
        guard loaded == nil, !loading else { return }
        guard let url, let request, RichTextURLPolicy.allowsImage(url) else {
            // Not an allowed scheme (javascript:, a relative path, a malformed or refused address): never read.
            failed = true
            refresh()
            return
        }
        if let cached = ImageStore.shared.cachedImage(for: request) {
            show(cached)
            return
        }
        // A click approves the image under "on-click" only; it does not outlive a switch to "never", as on Apple
        // platforms and Linux.
        if RichTextURLPolicy.isRemoteImage(url) {
            switch policy {
            case .never:
                setHold(.off)
                return
            case .onClick:
                if !approved {
                    setHold(.awaitingClick)
                    return
                }
            case .automatic:
                break
            }
        }
        setHold(.none)
        loading = true
        ImageStore.shared.load(request) { [weak self] image in
            // Completions run on the main dispatch queue, which the WinUI program drains on its UI thread.
            MainActor.assumeIsolated {
                guard let self else { return }
                self.loading = false
                if let image {
                    self.show(image)
                } else {
                    self.failed = true
                    self.refresh()
                }
            }
        }
    }

    /// The placeholder's text now.
    var placeholderText: String {
        RichTextImagePlaceholder.label(alt: alt, url: url, failed: failed, hold: hold, action: "Click")
    }

    /// A click (a tap) on the placeholder: loads a held remote image under "on-click". True when it did.
    @discardableResult
    func placeholderClicked() -> Bool {
        guard hold == .awaitingClick else { return false }
        approved = true
        start(policy: .automatic)
        return true
    }

    /// A key while the placeholder has focus (`down`, its virtual-key code, whether it repeats, the modifiers held):
    /// Enter or Space, with no modifier, clicks it.
    fileprivate func keyPressed(down: Bool, virtualKey: Int32, repeats: Bool, modifiers: UInt32) -> Bool {
        // VK_RETURN, VK_SPACE. Caps Lock on is no modifier held.
        let held = modifiers & ~UInt32(ActionUIWinUIModifierCapsLock)
        guard down, !repeats, held == 0, virtualKey == 0x0D || virtualKey == 0x20 else {
            return false
        }
        return placeholderClicked()
    }

    private func setHold(_ newHold: RichTextImageHold) {
        hold = newHold
        refresh()
    }

    private func refresh() {
        guard loaded == nil else { return }
        if let label {
            _ = actionUIWinUITextBlockSetText(label.pointer, placeholderText)
        }
        _ = actionUIWinUIPanelSetCursor(panel.pointer, hold == .awaitingClick ? ActionUIWinUICursorHand : ActionUIWinUICursorDefault)
        _ = actionUIWinUIElementSetFocusable(panel.pointer, hold == .awaitingClick)
        _ = actionUIWinUIElementInvalidateMeasure(panel.pointer)
    }

    // The image in place of the placeholder, at its own size up to the width cap (the store decodes it at most
    // maxWidth pixels wide; shown a point a pixel, as on Apple platforms and Linux).
    private func show(_ image: PlatformImage) {
        guard loaded == nil else { return }
        // No WinUI source (or no Image): shown as an image that cannot load, not as one still loading.
        guard let source = image.imageSource, let picture = ShimObject(adopting: actionUIWinUIImageCreate()) else {
            failed = true
            refresh()
            return
        }
        loaded = image
        hold = .none
        failed = false
        _ = actionUIWinUIImageSetSource(picture.pointer, source)
        _ = actionUIWinUIImageSetStretch(picture.pointer, ActionUIWinUIImageStretchFill)
        if !alt.isEmpty {
            _ = actionUIWinUIElementSetAccessibleName(picture.pointer, alt)
        }
        while actionUIWinUIPanelChildCount(panel.pointer) > 0 {
            guard actionUIWinUIPanelRemoveChild(panel.pointer, 0) else { break }
        }
        box = nil
        label = nil
        _ = actionUIWinUIPanelInsertChild(panel.pointer, 0, picture.pointer)
        self.picture = picture
        _ = actionUIWinUIPanelSetCursor(panel.pointer, ActionUIWinUICursorDefault)
        // The image takes no keys: the focus a key gave the placeholder moves on, as Tab would move it.
        if actionUIWinUIElementHasFocus(panel.pointer) {
            _ = actionUIWinUIElementGiveUpFocus(panel.pointer)
        }
        _ = actionUIWinUIElementSetFocusable(panel.pointer, false)
        let width = Double(image.pixelWidth)
        let height = Double(image.pixelHeight)
        let scale = width > Self.maxWidth ? Self.maxWidth / width : 1
        size = ActionUIWinUISize(width: (width * scale).rounded(), height: (height * scale).rounded())
        _ = actionUIWinUIElementInvalidateMeasure(panel.pointer)
        sizeChanged?()
    }

    // MARK: - Layout

    fileprivate func measure(_ available: ActionUIWinUISize) -> ActionUIWinUISize {
        var size = self.size
        // A paragraph narrower than the image: the image scales down to its width, keeping its shape, and the
        // placeholder narrows, as on Apple platforms (WinUI offers an inline element its paragraph's width).
        if available.width.isFinite, available.width > 0, available.width < size.width {
            if picture != nil {
                size.height = (size.height * available.width / size.width).rounded()
            }
            size.width = available.width.rounded(.down)
        }
        if let label {
            // The placeholder is as tall as its whole text needs, at least its own height.
            let inset = Self.placeholderInset
            let wanted = actionUIWinUIElementMeasure(label.pointer, ActionUIWinUISize(width: max(0, size.width - 2 * inset),
                                                                                      height: .infinity))
            size.height = max(size.height, (wanted.height + 2 * inset).rounded(.up))
        }
        if let picture {
            _ = actionUIWinUIElementMeasure(picture.pointer, size)
        }
        if let box {
            _ = actionUIWinUIElementMeasure(box.pointer, size)
        }
        return size
    }

    fileprivate func arrange(_ final: ActionUIWinUISize) {
        let whole = ActionUIWinUIRect(x: 0, y: 0, width: final.width, height: final.height)
        if let picture {
            _ = actionUIWinUIElementArrange(picture.pointer, whole)
        }
        if let box {
            _ = actionUIWinUIElementArrange(box.pointer, whole)
        }
        if let label {
            // The text in the middle of the box.
            let inset = Self.placeholderInset
            let width = max(0, final.width - 2 * inset)
            let wanted = actionUIWinUIElementMeasure(label.pointer, ActionUIWinUISize(width: width, height: .infinity))
            let height = min(wanted.height, max(0, final.height - 2 * inset))
            _ = actionUIWinUIElementArrange(label.pointer, ActionUIWinUIRect(x: inset, y: ((final.height - height) / 2).rounded(),
                                                                             width: width, height: height))
        }
    }
}

/// The panel callbacks' context: the slot, not kept alive by it (the element's state keeps the slots).
@MainActor
private final class WeakImageSlot {
    weak var slot: RichTextWinUIImageSlot?

    init(_ slot: RichTextWinUIImageSlot? = nil) {
        self.slot = slot
    }
}

private let measureImageSlot: ActionUIWinUIMeasureCallback = { context, _, available in
    let weak = context.map { Unmanaged<WeakImageSlot>.fromOpaque($0).takeUnretainedValue() }
    return MainActor.assumeIsolated {
        weak?.slot?.measure(available) ?? ActionUIWinUISize(width: 0, height: 0)
    }
}

private let arrangeImageSlot: ActionUIWinUIArrangeCallback = { context, _, finalSize in
    let weak = context.map { Unmanaged<WeakImageSlot>.fromOpaque($0).takeUnretainedValue() }
    MainActor.assumeIsolated {
        weak?.slot?.arrange(finalSize)
    }
}

private let imageSlotTapped: ActionUIWinUICallback = { context in
    let weak = context.map { Unmanaged<WeakImageSlot>.fromOpaque($0).takeUnretainedValue() }
    MainActor.assumeIsolated {
        _ = weak?.slot?.placeholderClicked()
    }
}

private let imageSlotKey: ActionUIWinUIKeyEventCallback = { context, event in
    guard let context, let event else { return false }
    let weak = Unmanaged<WeakImageSlot>.fromOpaque(context).takeUnretainedValue()
    // The plain fields, not the event (it holds a pointer to its text, valid during the call only).
    let down = event.pointee.type == ActionUIWinUIKeyDown
    let virtualKey = event.pointee.virtualKey
    let repeats = event.pointee.repeat
    let modifiers = event.pointee.modifiers
    return MainActor.assumeIsolated {
        weak.slot?.keyPressed(down: down, virtualKey: virtualKey, repeats: repeats, modifiers: modifiers) ?? false
    }
}

private let releaseWeakImageSlot: ActionUIWinUICallback = { context in
    guard let context else { return }
    Unmanaged<WeakImageSlot>.fromOpaque(context).release()
}

#endif
