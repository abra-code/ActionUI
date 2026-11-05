// Add-ons/ActionUIHostSurface/Sources/ActionUIHostSurface/HostSurfaceView+Input.swift
//
// Input on the surface view: pointer, touch, pen, scroll, magnify, rotate, keys and focus, turned into
// AUIHostInputEvent (include/ActionUIHostSurface.h) and delivered to the client that got "created".
//
// Rules:
// - Input comes only while the surface is announced, not hidden, and its element is enabled (SwiftUI's
//   isEnabled, from the disabled modifier).
// - Positions are in points from the top-left corner of the surface.
// - Scroll deltas are how far the content should move, positive to the right and down. The surface
//   takes the wheel: an enclosing scroll view does not scroll as well.
// - Focus is never taken unasked. A click or tap focuses the surface when "focusable" is true; Tab and
//   Shift-Tab move focus in and out and are not delivered. On macOS the surface refuses focus until its
//   window has been key for a main-loop turn, because AppKit picks an initial first responder when a
//   window first becomes key.

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import CActionUIHostSurface
#if os(macOS)
import AppKit
#else
import UIKit
#endif

extension HostSurfaceView {

    /// Input reaches the client: announced, enabled and not hidden. Not tied to suspension: an occluded
    /// window gets no input anyway, and the surface keeps its focus while the window is covered.
    var inputAllowed: Bool {
        surfaceID != 0 && inputEnabled && !properties.hidden
    }

    /// The surface may hold keyboard focus.
    var canTakeFocus: Bool {
        inputAllowed && properties.focusable
    }

    static func isKnownCursor(_ cursor: Int32) -> Bool {
        cursor >= Int32(AUIHostCursorArrow.rawValue) && cursor <= Int32(AUIHostCursorHidden.rawValue)
    }

    func makeEvent(_ kind: AUIHostInputKind) -> AUIHostInputEvent {
        var event = AUIHostInputEvent()
        event.structSize = UInt32(MemoryLayout<AUIHostInputEvent>.size)
        event.kind = Int32(kind.rawValue)
        return event
    }

    func sendFocus(_ kind: AUIHostInputKind) {
        deliverInput(makeEvent(kind))
    }

    /// The text a key produced, or nil when it is not text a client would insert: control characters
    /// (Escape, Return, Backspace), the private-use characters AppKit gives arrows and function keys
    /// (U+F700...U+F8FF), and the key names UIKit gives them ("UIKeyInputLeftArrow").
    static func insertableText(_ characters: String?) -> String? {
        guard let characters, !characters.isEmpty, !characters.hasPrefix("UIKeyInput") else {
            return nil
        }
        let insertable = characters.unicodeScalars.allSatisfy { scalar in
            !(scalar.value < 0x20 || scalar.value == 0x7F || (0xF700...0xF8FF).contains(scalar.value))
        }
        return insertable ? characters : nil
    }
}

// MARK: - macOS

#if os(macOS)
extension HostSurfaceView {

    func installInputHandlers() {}

    /// Arms focus one main-loop turn after the window is key; see the file note.
    func armFocusIfKey() {
        guard let window, window.isKeyWindow else {
            return
        }
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.window?.isKeyWindow == true else {
                    return
                }
                self.focusArmed = true
            }
        }
    }

    func giveUpFocus() {
        if let window, window.firstResponder === self {
            window.makeFirstResponder(nil)
        }
    }

    /// Keys stop coming when the window stops being key (another window or app took them), and come
    /// again when it is key, so a focused surface reports focus out and in, as a browser does: a client
    /// can let go of keys held down, whose key up will not come.
    func windowKeyChanged(isKey: Bool) {
        guard let window, window.firstResponder === self, inputAllowed else {
            return
        }
        sendFocus(isKey ? AUIHostInputFocusIn : AUIHostInputFocusOut)
    }

    func setCursor(_ cursor: Int32) {
        self.cursor = cursor
        window?.invalidateCursorRects(for: self)
    }

    override var acceptsFirstResponder: Bool {
        canTakeFocus && focusArmed
    }

    override var canBecomeKeyView: Bool {
        acceptsFirstResponder && !isHiddenOrHasHiddenAncestor
    }

    /// The first click on an inactive window reaches the surface too, as on a canvas.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func becomeFirstResponder() -> Bool {
        guard acceptsFirstResponder else {
            return false
        }
        tabKeyDownDelivered = false
        sendFocus(AUIHostInputFocusIn)
        return true
    }

    override func resignFirstResponder() -> Bool {
        sendFocus(AUIHostInputFocusOut)
        return true
    }

    override func resetCursorRects() {
        guard let shape = Self.nsCursor(cursor) else {
            return
        }
        addCursorRect(bounds, cursor: shape)
    }

    private static let hiddenCursor = NSCursor(image: NSImage(size: NSSize(width: 1, height: 1)), hotSpot: .zero)

    /// nil for the arrow: no cursor rect, so the window's own cursor shows.
    static func nsCursor(_ cursor: Int32) -> NSCursor? {
        switch UInt32(bitPattern: cursor) {
        case AUIHostCursorIBeam.rawValue: return .iBeam
        case AUIHostCursorCrosshair.rawValue: return .crosshair
        case AUIHostCursorPointingHand.rawValue: return .pointingHand
        case AUIHostCursorOpenHand.rawValue: return .openHand
        case AUIHostCursorClosedHand.rawValue: return .closedHand
        case AUIHostCursorResizeLeftRight.rawValue: return .resizeLeftRight
        case AUIHostCursorResizeUpDown.rawValue: return .resizeUpDown
        case AUIHostCursorNotAllowed.rawValue: return .operationNotAllowed
        case AUIHostCursorHidden.rawValue: return hiddenCursor
        default: return nil
        }
    }

    // MARK: pointer

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    static func modifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var bits: UInt32 = 0
        if flags.contains(.shift) {
            bits |= UInt32(AUIHostModifierShift)
        }
        if flags.contains(.control) {
            bits |= UInt32(AUIHostModifierControl)
        }
        if flags.contains(.option) {
            bits |= UInt32(AUIHostModifierAlt)
        }
        if flags.contains(.command) {
            bits |= UInt32(AUIHostModifierMeta)
        }
        if flags.contains(.capsLock) {
            bits |= UInt32(AUIHostModifierCapsLock)
        }
        return bits
    }

    private func pointer(_ kind: AUIHostInputKind, _ nsEvent: NSEvent, button: Int32) {
        guard inputAllowed else {
            return
        }
        let location = convert(nsEvent.locationInWindow, from: nil)
        var event = makeEvent(kind)
        // Enter and exit events have no subtype: AppKit raises on reading it.
        let isTracking = kind == AUIHostInputPointerEnter || kind == AUIHostInputPointerExit
        let isPen = !isTracking && nsEvent.subtype == .tabletPoint
        event.pointerType = Int32(isPen ? AUIHostPointerPen.rawValue : AUIHostPointerMouse.rawValue)
        event.button = button
        event.modifiers = Self.modifiers(nsEvent.modifierFlags)
        event.x = Double(location.x)
        event.y = Double(location.y)
        event.timestampSeconds = nsEvent.timestamp
        switch kind {
        case AUIHostInputPointerDown, AUIHostInputPointerUp:
            event.clickCount = Int32(nsEvent.clickCount)
        default:
            break
        }
        switch kind {
        case AUIHostInputPointerDown, AUIHostInputPointerDrag:
            event.pressure = isPen ? Double(nsEvent.pressure) : 1
        default:
            event.pressure = 0
        }
        if isPen {
            event.tiltX = Double(nsEvent.tilt.x)
            event.tiltY = Double(nsEvent.tilt.y)
        }
        deliverInput(event)
    }

    private func pointerDown(_ nsEvent: NSEvent, button: Int32) {
        guard inputAllowed else {
            return
        }
        if properties.focusable, window?.firstResponder !== self {
            // A click is the user asking: arm focus now, even in a window that just became key.
            focusArmed = true
            window?.makeFirstResponder(self)
        }
        pointer(AUIHostInputPointerDown, nsEvent, button: button)
    }

    override func mouseDown(with event: NSEvent) { pointerDown(event, button: 0) }
    override func mouseUp(with event: NSEvent) { pointer(AUIHostInputPointerUp, event, button: 0) }
    override func mouseDragged(with event: NSEvent) { pointer(AUIHostInputPointerDrag, event, button: 0) }
    override func rightMouseDown(with event: NSEvent) { pointerDown(event, button: 1) }
    override func rightMouseUp(with event: NSEvent) { pointer(AUIHostInputPointerUp, event, button: 1) }
    override func rightMouseDragged(with event: NSEvent) { pointer(AUIHostInputPointerDrag, event, button: 1) }
    override func otherMouseDown(with event: NSEvent) { pointerDown(event, button: 2) }
    override func otherMouseUp(with event: NSEvent) { pointer(AUIHostInputPointerUp, event, button: 2) }
    override func otherMouseDragged(with event: NSEvent) { pointer(AUIHostInputPointerDrag, event, button: 2) }
    override func mouseMoved(with event: NSEvent) { pointer(AUIHostInputPointerMove, event, button: 0) }
    override func mouseEntered(with event: NSEvent) { pointer(AUIHostInputPointerEnter, event, button: 0) }
    override func mouseExited(with event: NSEvent) { pointer(AUIHostInputPointerExit, event, button: 0) }

    // MARK: scroll and gestures

    static func scrollPhase(phase: NSEvent.Phase, momentumPhase: NSEvent.Phase) -> AUIHostScrollPhase {
        if !momentumPhase.isEmpty {
            return momentumPhase.contains(.ended) || momentumPhase.contains(.cancelled)
                ? AUIHostScrollPhaseMomentumEnded : AUIHostScrollPhaseMomentum
        }
        if phase.contains(.began) || phase.contains(.mayBegin) {
            return AUIHostScrollPhaseBegan
        }
        if phase.contains(.changed) || phase.contains(.stationary) {
            return AUIHostScrollPhaseChanged
        }
        if phase.contains(.ended) || phase.contains(.cancelled) {
            return AUIHostScrollPhaseEnded
        }
        return AUIHostScrollPhaseNone
    }

    /// Taken, never passed on: an enclosing scroll view must not scroll too. AppKit's scrolling deltas
    /// already follow the user's direction setting and move content down for a positive deltaY, which
    /// is the header's convention.
    override func scrollWheel(with nsEvent: NSEvent) {
        guard inputAllowed else {
            // Disabled or not announced: an enclosing scroll view scrolls as usual.
            super.scrollWheel(with: nsEvent)
            return
        }
        let location = convert(nsEvent.locationInWindow, from: nil)
        var event = makeEvent(AUIHostInputScroll)
        event.x = Double(location.x)
        event.y = Double(location.y)
        event.deltaX = Double(nsEvent.scrollingDeltaX)
        event.deltaY = Double(nsEvent.scrollingDeltaY)
        event.scrollUnit = Int32((nsEvent.hasPreciseScrollingDeltas ? AUIHostScrollPoints : AUIHostScrollSteps).rawValue)
        event.scrollPhase = Int32(Self.scrollPhase(phase: nsEvent.phase, momentumPhase: nsEvent.momentumPhase).rawValue)
        event.modifiers = Self.modifiers(nsEvent.modifierFlags)
        event.timestampSeconds = nsEvent.timestamp
        deliverInput(event)
    }

    /// false when input is not allowed, so the caller passes the gesture on.
    private func gesture(_ kind: AUIHostInputKind, _ nsEvent: NSEvent, delta: Double) -> Bool {
        guard inputAllowed else {
            return false
        }
        let location = convert(nsEvent.locationInWindow, from: nil)
        var event = makeEvent(kind)
        event.x = Double(location.x)
        event.y = Double(location.y)
        event.deltaX = delta
        event.modifiers = Self.modifiers(nsEvent.modifierFlags)
        event.timestampSeconds = nsEvent.timestamp
        deliverInput(event)
        return true
    }

    override func magnify(with event: NSEvent) {
        if !gesture(AUIHostInputMagnify, event, delta: Double(event.magnification)) {
            super.magnify(with: event)
        }
    }

    /// AppKit's rotation is in degrees, counterclockwise positive, as the header's.
    override func rotate(with event: NSEvent) {
        if !gesture(AUIHostInputRotate, event, delta: Double(event.rotation)) {
            super.rotate(with: event)
        }
    }

    // MARK: keys

    private static let tabKeyCode: UInt16 = 0x30

    private func key(_ kind: AUIHostInputKind, _ nsEvent: NSEvent, text: String?) {
        guard inputAllowed else {
            return
        }
        var event = makeEvent(kind)
        event.keyCode = UInt32(nsEvent.keyCode)
        event.modifiers = Self.modifiers(nsEvent.modifierFlags)
        event.timestampSeconds = nsEvent.timestamp
        deliverInput(event, code: HostSurfaceKeyCodes.code(macKeyCode: nsEvent.keyCode), text: text)
    }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.keyCode == Self.tabKeyCode {
            tabKeyDownDelivered = !flags.isDisjoint(with: [.control, .option, .command])
        }
        if event.keyCode == Self.tabKeyCode, !tabKeyDownDelivered {
            if flags.contains(.shift) {
                window?.selectPreviousKeyView(self)
            } else {
                window?.selectNextKeyView(self)
            }
            return
        }
        key(AUIHostInputKeyDown, event, text: Self.insertableText(event.characters))
    }

    override func keyUp(with event: NSEvent) {
        // A Tab that moved focus here, or one that moved focus on, is not delivered.
        if event.keyCode == Self.tabKeyCode {
            guard tabKeyDownDelivered else {
                return
            }
            tabKeyDownDelivered = false
        }
        key(AUIHostInputKeyUp, event, text: nil)
    }

    /// A modifier key's own press and release, as KeyDown and KeyUp. The device bits tell the left
    /// and right keys apart (NX_DEVICE...KEYMASK in IOKit's IOLLEvent.h).
    static func modifierKeyIsDown(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> Bool? {
        let raw = flags.rawValue
        switch keyCode {
        case 0x3B: return raw & 0x0001 != 0                                  // ControlLeft
        case 0x38: return raw & 0x0002 != 0                                  // ShiftLeft
        case 0x3C: return raw & 0x0004 != 0                                  // ShiftRight
        case 0x37: return raw & 0x0008 != 0                                  // MetaLeft
        case 0x36: return raw & 0x0010 != 0                                  // MetaRight
        case 0x3A: return raw & 0x0020 != 0                                  // AltLeft
        case 0x3D: return raw & 0x0040 != 0                                  // AltRight
        case 0x3E: return raw & 0x2000 != 0                                  // ControlRight
        case 0x39: return flags.contains(.capsLock)                          // CapsLock (its lock state)
        case 0x3F: return flags.contains(.function)                          // Fn
        default: return nil
        }
    }

    override func flagsChanged(with event: NSEvent) {
        guard let down = Self.modifierKeyIsDown(keyCode: event.keyCode, flags: event.modifierFlags) else {
            super.flagsChanged(with: event)
            return
        }
        key(down ? AUIHostInputKeyDown : AUIHostInputKeyUp, event, text: nil)
    }
}
#endif

// MARK: - iOS

#if os(iOS)
extension HostSurfaceView: UIGestureRecognizerDelegate, UIPointerInteractionDelegate {

    func installInputHandlers() {
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        let rotation = UIRotationGestureRecognizer(target: self, action: #selector(handleRotation(_:)))
        let hover = UIHoverGestureRecognizer(target: self, action: #selector(handleHover(_:)))
        // Two-finger scrolling on a trackpad and the wheel of a mouse, not touches.
        let scroll = UIPanGestureRecognizer(target: self, action: #selector(handleScroll(_:)))
        scroll.allowedScrollTypesMask = .all
        scroll.allowedTouchTypes = []
        for recognizer in [pinch, rotation, hover, scroll] as [UIGestureRecognizer] {
            // The client gets the touches too, and the gestures run together.
            recognizer.cancelsTouchesInView = false
            recognizer.delegate = self
            addGestureRecognizer(recognizer)
        }
        let interaction = UIPointerInteraction(delegate: self)
        addInteraction(interaction)
        pointerInteraction = interaction
    }

    func giveUpFocus() {
        if isFirstResponder {
            _ = resignFirstResponder()
        }
    }

    func setCursor(_ cursor: Int32) {
        self.cursor = cursor
        pointerInteraction?.invalidate()
    }

    nonisolated func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                                       shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }

    func pointerInteraction(_ interaction: UIPointerInteraction, styleFor region: UIPointerRegion) -> UIPointerStyle? {
        switch UInt32(bitPattern: cursor) {
        case AUIHostCursorHidden.rawValue: return .hidden()
        case AUIHostCursorIBeam.rawValue: return UIPointerStyle(shape: .verticalBeam(length: 20), constrainedAxes: [])
        default: return nil
        }
    }

    override var canBecomeFirstResponder: Bool {
        canTakeFocus
    }

    override func becomeFirstResponder() -> Bool {
        guard canTakeFocus, super.becomeFirstResponder() else {
            return false
        }
        sendFocus(AUIHostInputFocusIn)
        return true
    }

    override func resignFirstResponder() -> Bool {
        let wasFocused = isFirstResponder
        let resigned = super.resignFirstResponder()
        if resigned, wasFocused {
            sendFocus(AUIHostInputFocusOut)
        }
        return resigned
    }

    static func modifiers(_ flags: UIKeyModifierFlags) -> UInt32 {
        var bits: UInt32 = 0
        if flags.contains(.shift) {
            bits |= UInt32(AUIHostModifierShift)
        }
        if flags.contains(.control) {
            bits |= UInt32(AUIHostModifierControl)
        }
        if flags.contains(.alternate) {
            bits |= UInt32(AUIHostModifierAlt)
        }
        if flags.contains(.command) {
            bits |= UInt32(AUIHostModifierMeta)
        }
        if flags.contains(.alphaShift) {
            bits |= UInt32(AUIHostModifierCapsLock)
        }
        return bits
    }

    /// Pen tilt as x and y components in -1...1 from UIKit's altitude and azimuth.
    static func tilt(altitude: Double, azimuth: Double) -> (x: Double, y: Double) {
        let lean = cos(altitude)
        return (lean * cos(azimuth), lean * sin(azimuth))
    }

    // MARK: touches

    private func touches(_ kind: AUIHostInputKind, _ touches: Set<UITouch>, _ uiEvent: UIEvent?) {
        guard inputAllowed else {
            return
        }
        for touch in touches {
            let location = touch.location(in: self)
            var event = makeEvent(kind)
            switch touch.type {
            case .pencil:
                event.pointerType = Int32(AUIHostPointerPen.rawValue)
                let tilt = Self.tilt(altitude: Double(touch.altitudeAngle), azimuth: Double(touch.azimuthAngle(in: self)))
                event.tiltX = tilt.x
                event.tiltY = tilt.y
            case .indirectPointer:
                event.pointerType = Int32(AUIHostPointerMouse.rawValue)
                if uiEvent?.buttonMask.contains(.secondary) == true {
                    event.button = 1
                }
            default:
                event.pointerType = Int32(AUIHostPointerTouch.rawValue)
            }
            // 0 for the mouse (the header's rule, and what hover events carry).
            if touch.type != .indirectPointer {
                event.pointerID = Int64(truncatingIfNeeded: ObjectIdentifier(touch).hashValue)
            }
            event.x = Double(location.x)
            event.y = Double(location.y)
            event.clickCount = Int32(touch.tapCount)
            switch kind {
            case AUIHostInputPointerDown, AUIHostInputPointerDrag:
                event.pressure = touch.maximumPossibleForce > 0 ? Double(touch.force / touch.maximumPossibleForce) : 1
            default:
                event.pressure = 0
            }
            event.modifiers = Self.modifiers(uiEvent?.modifierFlags ?? [])
            event.timestampSeconds = touch.timestamp
            deliverInput(event)
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if properties.focusable, inputAllowed, !isFirstResponder {
            _ = becomeFirstResponder()
        }
        self.touches(AUIHostInputPointerDown, touches, event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        self.touches(AUIHostInputPointerDrag, touches, event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        self.touches(AUIHostInputPointerUp, touches, event)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        self.touches(AUIHostInputPointerCancel, touches, event)
    }

    // MARK: gestures

    private func gestureEvent(_ kind: AUIHostInputKind, _ recognizer: UIGestureRecognizer) -> AUIHostInputEvent {
        let location = recognizer.location(in: self)
        var event = makeEvent(kind)
        event.x = Double(location.x)
        event.y = Double(location.y)
        event.modifiers = Self.modifiers(recognizer.modifierFlags)
        event.timestampSeconds = ProcessInfo.processInfo.systemUptime
        return event
    }

    /// The change in scale since the last callback, as a magnification increment like AppKit's.
    @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
        if recognizer.state == .began {
            lastPinchScale = 1
        }
        guard inputAllowed, recognizer.state == .began || recognizer.state == .changed else {
            return
        }
        var event = gestureEvent(AUIHostInputMagnify, recognizer)
        event.deltaX = Double(recognizer.scale - lastPinchScale)
        lastPinchScale = recognizer.scale
        deliverInput(event)
    }

    /// UIKit's rotation is in radians, clockwise positive on screen; the header's is degrees,
    /// counterclockwise positive.
    @objc private func handleRotation(_ recognizer: UIRotationGestureRecognizer) {
        if recognizer.state == .began {
            lastRotation = 0
        }
        guard inputAllowed, recognizer.state == .began || recognizer.state == .changed else {
            return
        }
        var event = gestureEvent(AUIHostInputRotate, recognizer)
        event.deltaX = -Double(recognizer.rotation - lastRotation) * 180 / Double.pi
        lastRotation = recognizer.rotation
        deliverInput(event)
    }

    @objc private func handleHover(_ recognizer: UIHoverGestureRecognizer) {
        guard inputAllowed else {
            return
        }
        let kind: AUIHostInputKind
        switch recognizer.state {
        case .began: kind = AUIHostInputPointerEnter
        case .changed: kind = AUIHostInputPointerMove
        case .ended, .cancelled: kind = AUIHostInputPointerExit
        default: return
        }
        var event = gestureEvent(kind, recognizer)
        event.pointerType = Int32(AUIHostPointerMouse.rawValue)
        deliverInput(event)
    }

    /// Trackpad and wheel scrolling. The translation grows as the content should move (down for a
    /// positive y), which is the header's convention; each event carries the change since the last.
    @objc private func handleScroll(_ recognizer: UIPanGestureRecognizer) {
        if recognizer.state == .began {
            lastScrollTranslation = .zero
        }
        guard inputAllowed else {
            return
        }
        let phase: AUIHostScrollPhase
        switch recognizer.state {
        case .began: phase = AUIHostScrollPhaseBegan
        case .changed: phase = AUIHostScrollPhaseChanged
        case .ended, .cancelled: phase = AUIHostScrollPhaseEnded
        default: return
        }
        let translation = recognizer.translation(in: self)
        var event = gestureEvent(AUIHostInputScroll, recognizer)
        event.deltaX = Double(translation.x - lastScrollTranslation.x)
        event.deltaY = Double(translation.y - lastScrollTranslation.y)
        event.scrollUnit = Int32(AUIHostScrollPoints.rawValue)
        event.scrollPhase = Int32(phase.rawValue)
        lastScrollTranslation = translation
        deliverInput(event)
    }

    // MARK: keys

    private func presses(_ kind: AUIHostInputKind, _ presses: Set<UIPress>) -> Bool {
        var handled = false
        for press in presses {
            guard let key = press.key, key.keyCode != .keyboardTab else {
                continue
            }
            handled = true
            guard inputAllowed else {
                continue
            }
            var event = makeEvent(kind)
            event.keyCode = UInt32(key.keyCode.rawValue)
            event.modifiers = Self.modifiers(key.modifierFlags)
            event.timestampSeconds = press.timestamp
            let text = kind == AUIHostInputKeyDown ? Self.insertableText(key.characters) : nil
            deliverInput(event, code: HostSurfaceKeyCodes.code(hidUsage: key.keyCode.rawValue), text: text)
        }
        return handled
    }

    /// Keys come here while the surface is first responder. Tab is left to UIKit, which moves focus.
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if !self.presses(AUIHostInputKeyDown, presses) {
            super.pressesBegan(presses, with: event)
        }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if !self.presses(AUIHostInputKeyUp, presses) {
            super.pressesEnded(presses, with: event)
        }
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if !self.presses(AUIHostInputKeyUp, presses) {
            super.pressesCancelled(presses, with: event)
        }
    }
}
#endif
