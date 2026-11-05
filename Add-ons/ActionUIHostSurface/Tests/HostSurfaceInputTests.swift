// Add-ons/ActionUIHostSurface/Tests/HostSurfaceInputTests.swift
//
// Input on the surface: what reaches the client and when (announced, enabled, not hidden), the focus
// rules (never at load, a click focuses, Tab moves on), key names, modifier keys, scroll, the cursor,
// and the pure conversions. macOS drives the view with NSEvents; iOS cannot make touches or presses, so
// it checks the focus gates and the conversions.

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import XCTest
import ActionUI
@testable import ActionUIHostSurface
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor
final class HostSurfaceInputTests: XCTestCase {
    private var window: TestWindow!
    private var windowUUID = ""
    /// C clients stay alive until tearDown has unbound them: the registry keeps only their userData.
    private var cClients: [RecordingCClient] = []

    override func setUp() async throws {
        HostSurfaceView.ignoresWindowOcclusionForTesting = true
        HostSurfaceRegistry.shared.resetForTesting()
        window = TestHost.makeWindow()
        windowUUID = UUID().uuidString
    }

    override func tearDown() async throws {
        HostSurfaceRegistry.shared.resetForTesting()
        cClients = []
        TestHost.close(window)
        window = nil
        TestHost.pump()
    }

    private func bindCClient() -> RecordingCClient {
        let client = RecordingCClient()
        cClients.append(client)
        var delegate = client.delegate
        XCTAssertTrue(actionUIHostSurfaceSetDelegate("viewport", &delegate, client.userData))
        return client
    }

    private func placedSurface(focusable: Bool = true) -> HostSurfaceView {
        let container = TestHost.makeContainer(
            windowUUID: windowUUID, viewID: 5,
            properties: HostSurfaceProperties(surfaceName: "viewport", focusable: focusable))
        TestHost.place(container, in: window)
        return container.surface
    }

    // MARK: pure conversions

    func testKeyNames() {
        XCTAssertEqual(HostSurfaceKeyCodes.code(macKeyCode: 0x00), "KeyA")
        XCTAssertEqual(HostSurfaceKeyCodes.code(macKeyCode: 0x1D), "Digit0")
        XCTAssertEqual(HostSurfaceKeyCodes.code(macKeyCode: 0x7B), "ArrowLeft")
        XCTAssertEqual(HostSurfaceKeyCodes.code(macKeyCode: 0x3C), "ShiftRight")
        XCTAssertEqual(HostSurfaceKeyCodes.code(macKeyCode: 0x34), "", "an unused code has no name")
        XCTAssertEqual(HostSurfaceKeyCodes.code(hidUsage: 0x04), "KeyA")
        XCTAssertEqual(HostSurfaceKeyCodes.code(hidUsage: 0x1D), "KeyZ")
        XCTAssertEqual(HostSurfaceKeyCodes.code(hidUsage: 0x1E), "Digit1")
        XCTAssertEqual(HostSurfaceKeyCodes.code(hidUsage: 0x27), "Digit0")
        XCTAssertEqual(HostSurfaceKeyCodes.code(hidUsage: 0x3A), "F1")
        XCTAssertEqual(HostSurfaceKeyCodes.code(hidUsage: 0x45), "F12")
        XCTAssertEqual(HostSurfaceKeyCodes.code(hidUsage: 0x68), "F13")
        XCTAssertEqual(HostSurfaceKeyCodes.code(hidUsage: 0x59), "Numpad1")
        XCTAssertEqual(HostSurfaceKeyCodes.code(hidUsage: 0x62), "Numpad0")
        XCTAssertEqual(HostSurfaceKeyCodes.code(hidUsage: 0x50), "ArrowLeft")
        XCTAssertEqual(HostSurfaceKeyCodes.code(hidUsage: 0xE5), "ShiftRight")
        XCTAssertEqual(HostSurfaceKeyCodes.code(hidUsage: 0x03), "")
    }

    func testOnlyInsertableTextIsGiven() {
        XCTAssertEqual(HostSurfaceView.insertableText("a"), "a")
        XCTAssertEqual(HostSurfaceView.insertableText("\u{E9}"), "\u{E9}")
        XCTAssertNil(HostSurfaceView.insertableText(nil))
        XCTAssertNil(HostSurfaceView.insertableText(""))
        XCTAssertNil(HostSurfaceView.insertableText("\u{1B}"), "Escape")
        XCTAssertNil(HostSurfaceView.insertableText("\r"), "Return")
        XCTAssertNil(HostSurfaceView.insertableText("\u{7F}"), "Backspace")
        XCTAssertNil(HostSurfaceView.insertableText("\u{F702}"), "AppKit's left arrow")
        XCTAssertNil(HostSurfaceView.insertableText("UIKeyInputLeftArrow"), "UIKit's left arrow")
        XCTAssertEqual(HostSurfaceKeyCodes.code(hidUsage: 0x32), "Backslash")
        XCTAssertEqual(HostSurfaceKeyCodes.code(hidUsage: 0x80), "AudioVolumeUp")
    }

    func testCursorValues() {
        XCTAssertTrue(HostSurfaceView.isKnownCursor(Int32(AUIHostCursorArrow.rawValue)))
        XCTAssertTrue(HostSurfaceView.isKnownCursor(Int32(AUIHostCursorHidden.rawValue)))
        XCTAssertFalse(HostSurfaceView.isKnownCursor(-1))
        XCTAssertFalse(HostSurfaceView.isKnownCursor(Int32(AUIHostCursorHidden.rawValue) + 1))
    }

    func testSetCursorNeedsALiveSurfaceAndAKnownValue() {
        let client = RecordingClient()
        ActionUIHostSurface.setDelegate(client, forSurfaceName: "viewport")
        let surface = placedSurface()
        let surfaceID = client.received[0].surfaceID
        XCTAssertTrue(actionUIHostSurfaceSetCursor(surfaceID, Int32(AUIHostCursorCrosshair.rawValue)))
        XCTAssertEqual(surface.cursor, Int32(AUIHostCursorCrosshair.rawValue))
        XCTAssertFalse(actionUIHostSurfaceSetCursor(surfaceID, 42))
        XCTAssertFalse(actionUIHostSurfaceSetCursor(surfaceID + 1000, 0))
        let offMain = expectation(description: "off the main thread")
        DispatchQueue.global().async {
            XCTAssertFalse(actionUIHostSurfaceSetCursor(surfaceID, 0))
            offMain.fulfill()
        }
        wait(for: [offMain], timeout: 2)
    }

    #if os(macOS)

    func testScrollPhases() {
        XCTAssertEqual(HostSurfaceView.scrollPhase(phase: [], momentumPhase: []), AUIHostScrollPhaseNone)
        XCTAssertEqual(HostSurfaceView.scrollPhase(phase: .began, momentumPhase: []), AUIHostScrollPhaseBegan)
        XCTAssertEqual(HostSurfaceView.scrollPhase(phase: .changed, momentumPhase: []), AUIHostScrollPhaseChanged)
        XCTAssertEqual(HostSurfaceView.scrollPhase(phase: .ended, momentumPhase: []), AUIHostScrollPhaseEnded)
        XCTAssertEqual(HostSurfaceView.scrollPhase(phase: [], momentumPhase: .changed), AUIHostScrollPhaseMomentum)
        XCTAssertEqual(HostSurfaceView.scrollPhase(phase: [], momentumPhase: .ended), AUIHostScrollPhaseMomentumEnded)
    }

    func testModifierKeysTellLeftFromRight() {
        let leftShift = NSEvent.ModifierFlags(rawValue: NSEvent.ModifierFlags.shift.rawValue | 0x0002)
        XCTAssertEqual(HostSurfaceView.modifierKeyIsDown(keyCode: 0x38, flags: leftShift), true)
        XCTAssertEqual(HostSurfaceView.modifierKeyIsDown(keyCode: 0x3C, flags: leftShift), false,
                       "right shift is up while only the left one is down")
        XCTAssertEqual(HostSurfaceView.modifierKeyIsDown(keyCode: 0x38, flags: []), false)
        XCTAssertNil(HostSurfaceView.modifierKeyIsDown(keyCode: 0x00, flags: leftShift), "not a modifier key")
        XCTAssertEqual(HostSurfaceView.modifiers([.shift, .command]),
                       UInt32(AUIHostModifierShift) | UInt32(AUIHostModifierMeta))
    }

    // MARK: events on macOS

    private func mouse(_ type: NSEvent.EventType, at point: NSPoint, flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: point, modifierFlags: flags, timestamp: 1,
                           windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
                           pressure: 1)!
    }

    private func key(_ type: NSEvent.EventType, keyCode: UInt16, characters: String,
                     flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: 1,
                         windowNumber: window.windowNumber, context: nil, characters: characters,
                         charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode)!
    }

    func testTheSurfaceDoesNotTakeFocusUnasked() {
        let client = RecordingClient()
        ActionUIHostSurface.setDelegate(client, forSurfaceName: "viewport")
        let surface = placedSurface()
        // AppKit makes the window first responder when the view refuses, and still returns true.
        window.makeFirstResponder(surface)
        XCTAssertFalse(window.firstResponder === surface, "no focus before the window was key for a turn")
        XCTAssertEqual(client.inputKinds, [])
    }

    func testAClickFocusesAndDeliversThePointerInPoints() throws {
        let client = bindCClient()
        let surface = placedSurface()
        let inWindow = surface.convert(NSPoint(x: 30, y: 20), to: nil)
        surface.mouseDown(with: mouse(.leftMouseDown, at: inWindow, flags: [.shift]))
        XCTAssertTrue(window.firstResponder === surface)
        XCTAssertEqual(client.inputs.map(\.kind), [Int32(AUIHostInputFocusIn.rawValue), Int32(AUIHostInputPointerDown.rawValue)])
        XCTAssertEqual(client.inputs.last?.structSize, UInt32(MemoryLayout<AUIHostInputEvent>.size))
        XCTAssertEqual(client.inputs.last?.code, "", "a pointer event has an empty code, not NULL")
        XCTAssertNil(client.inputs.last?.text)
    }

    func testPointerPositionsAreTopLeftPoints() {
        let client = RecordingClient()
        ActionUIHostSurface.setDelegate(client, forSurfaceName: "viewport")
        let surface = placedSurface(focusable: false)
        let inWindow = surface.convert(NSPoint(x: 30, y: 20), to: nil)
        surface.mouseDown(with: mouse(.leftMouseDown, at: inWindow, flags: [.shift]))
        surface.mouseDragged(with: mouse(.leftMouseDragged, at: inWindow))
        surface.mouseUp(with: mouse(.leftMouseUp, at: inWindow))
        XCTAssertEqual(client.inputKinds, [AUIHostInputPointerDown, AUIHostInputPointerDrag, AUIHostInputPointerUp],
                       "a surface that is not focusable takes no focus")
        let down = client.inputs[0].event
        XCTAssertEqual(down.x, 30, accuracy: 0.001)
        XCTAssertEqual(down.y, 20, accuracy: 0.001, "y grows downward from the top edge")
        XCTAssertEqual(down.modifiers, UInt32(AUIHostModifierShift))
        XCTAssertEqual(down.clickCount, 1)
        XCTAssertEqual(down.pressure, 1)
        XCTAssertEqual(client.inputs[2].event.pressure, 0)
    }

    func testKeysCarryTheirNameAndTextAndTabMovesFocus() {
        let client = bindCClient()
        let surface = placedSurface()
        let field = NSTextField(frame: NSRect(x: 250, y: 10, width: 100, height: 22))
        TestHost.contentView(of: window).addSubview(field)
        window.recalculateKeyViewLoop()
        surface.mouseDown(with: mouse(.leftMouseDown, at: surface.convert(NSPoint(x: 5, y: 5), to: nil)))
        surface.keyDown(with: key(.keyDown, keyCode: 0x00, characters: "a"))
        surface.keyUp(with: key(.keyUp, keyCode: 0x00, characters: "a"))
        let keyEvents = client.inputs.filter {
            $0.kind == Int32(AUIHostInputKeyDown.rawValue) || $0.kind == Int32(AUIHostInputKeyUp.rawValue)
        }
        XCTAssertEqual(keyEvents.map(\.code), ["KeyA", "KeyA"])
        XCTAssertEqual(keyEvents.map(\.text), ["a", nil], "text comes with KeyDown only")
        surface.keyDown(with: key(.keyDown, keyCode: 0x30, characters: "\t"))
        XCTAssertFalse(window.firstResponder === surface, "Tab moved focus on")
        XCTAssertEqual(client.inputs.last?.kind, Int32(AUIHostInputFocusOut.rawValue))
        XCTAssertFalse(client.inputs.contains { $0.code == "Tab" }, "Tab is not delivered")
    }

    func testAFocusedSurfaceHearsWhenItsWindowStopsAndStartsBeingKey() {
        let client = RecordingClient()
        ActionUIHostSurface.setDelegate(client, forSurfaceName: "viewport")
        let surface = placedSurface()
        surface.mouseDown(with: mouse(.leftMouseDown, at: surface.convert(NSPoint(x: 5, y: 5), to: nil)))
        client.clear()
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
        XCTAssertEqual(client.inputKinds, [AUIHostInputFocusOut, AUIHostInputFocusIn])
        window.makeFirstResponder(nil)
        client.clear()
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        XCTAssertEqual(client.inputKinds, [], "an unfocused surface hears nothing")
    }

    func testModifierKeyPressAndRelease() {
        let client = RecordingClient()
        ActionUIHostSurface.setDelegate(client, forSurfaceName: "viewport")
        let surface = placedSurface()
        let leftShift = NSEvent.ModifierFlags(rawValue: NSEvent.ModifierFlags.shift.rawValue | 0x0002)
        surface.flagsChanged(with: key(.flagsChanged, keyCode: 0x38, characters: "", flags: leftShift))
        surface.flagsChanged(with: key(.flagsChanged, keyCode: 0x38, characters: "", flags: []))
        XCTAssertEqual(client.inputKinds, [AUIHostInputKeyDown, AUIHostInputKeyUp])
        XCTAssertEqual(client.inputs.map(\.code), ["ShiftLeft", "ShiftLeft"])
    }

    func testScrollIsTakenWithItsUnit() throws {
        let client = RecordingClient()
        ActionUIHostSurface.setDelegate(client, forSurfaceName: "viewport")
        let surface = placedSurface()
        let cgEvent = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                                            wheel1: 7, wheel2: -3, wheel3: 0))
        let scroll = try XCTUnwrap(NSEvent(cgEvent: cgEvent))
        surface.scrollWheel(with: scroll)
        XCTAssertEqual(client.inputKinds, [AUIHostInputScroll])
        let event = client.inputs[0].event
        XCTAssertEqual(event.scrollUnit, Int32(AUIHostScrollPoints.rawValue))
        XCTAssertEqual(event.deltaY, Double(scroll.scrollingDeltaY))
        XCTAssertEqual(event.deltaX, Double(scroll.scrollingDeltaX))
        XCTAssertNotEqual(event.deltaY, 0)
    }

    func testDisabledOrHiddenTakesNoInputAndGivesUpFocus() {
        let client = RecordingClient()
        ActionUIHostSurface.setDelegate(client, forSurfaceName: "viewport")
        let surface = placedSurface()
        let point = surface.convert(NSPoint(x: 5, y: 5), to: nil)
        surface.mouseDown(with: mouse(.leftMouseDown, at: point))
        XCTAssertTrue(window.firstResponder === surface)
        client.clear()
        surface.update(HostSurfaceProperties(surfaceName: "viewport"), enabled: false)
        XCTAssertFalse(window.firstResponder === surface, "a disabled surface gives up focus")
        XCTAssertEqual(client.inputKinds, [AUIHostInputFocusOut])
        surface.mouseDown(with: mouse(.leftMouseDown, at: point))
        surface.keyDown(with: key(.keyDown, keyCode: 0x00, characters: "a"))
        XCTAssertEqual(client.inputKinds, [AUIHostInputFocusOut], "nothing while disabled")
        surface.update(HostSurfaceProperties(surfaceName: "viewport", hidden: true), enabled: true)
        surface.mouseDown(with: mouse(.leftMouseDown, at: point))
        XCTAssertEqual(client.inputKinds, [AUIHostInputFocusOut], "nothing while hidden")
        surface.update(HostSurfaceProperties(surfaceName: "viewport"), enabled: true)
        surface.mouseDown(with: mouse(.leftMouseDown, at: point))
        XCTAssertEqual(client.inputKinds, [AUIHostInputFocusOut, AUIHostInputFocusIn, AUIHostInputPointerDown])
    }

    /// Enter and exit events have no subtype (AppKit raises on reading it).
    func testPointerEnterAndExit() throws {
        let client = RecordingClient()
        ActionUIHostSurface.setDelegate(client, forSurfaceName: "viewport")
        let surface = placedSurface()
        let point = surface.convert(NSPoint(x: 5, y: 5), to: nil)
        for type in [NSEvent.EventType.mouseEntered, .mouseExited] {
            let event = try XCTUnwrap(NSEvent.enterExitEvent(
                with: type, location: point, modifierFlags: [], timestamp: 1, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, trackingNumber: 0, userData: nil))
            if type == .mouseEntered {
                surface.mouseEntered(with: event)
            } else {
                surface.mouseExited(with: event)
            }
        }
        XCTAssertEqual(client.inputKinds, [AUIHostInputPointerEnter, AUIHostInputPointerExit])
        XCTAssertEqual(client.inputs[0].event.pointerType, Int32(AUIHostPointerMouse.rawValue))
    }

    func testUnbindingGivesUpFocusBeforeDestroyed() {
        let client = RecordingClient()
        ActionUIHostSurface.setDelegate(client, forSurfaceName: "viewport")
        let surface = placedSurface()
        surface.mouseDown(with: mouse(.leftMouseDown, at: surface.convert(NSPoint(x: 5, y: 5), to: nil)))
        XCTAssertTrue(window.firstResponder === surface)
        client.clear()
        ActionUIHostSurface.setDelegate(nil, forSurfaceName: "viewport")
        XCTAssertFalse(window.firstResponder === surface, "a surface with no client does not keep the keys")
        XCTAssertEqual(client.inputKinds, [AUIHostInputFocusOut])
        XCTAssertEqual(client.events, [.destroyed])
    }

    func testControlTabIsDeliveredDownAndUp() {
        let client = RecordingClient()
        ActionUIHostSurface.setDelegate(client, forSurfaceName: "viewport")
        let surface = placedSurface()
        surface.keyDown(with: key(.keyDown, keyCode: 0x30, characters: "\t", flags: [.control]))
        surface.keyUp(with: key(.keyUp, keyCode: 0x30, characters: "\t"))
        XCTAssertEqual(client.inputKinds, [AUIHostInputKeyDown, AUIHostInputKeyUp],
                       "the key up comes even when Control was released first")
    }

    func testDisabledSurfacePassesTheWheelOn() throws {
        let client = RecordingClient()
        ActionUIHostSurface.setDelegate(client, forSurfaceName: "viewport")
        let surface = placedSurface()
        let spy = ScrollSpy()
        spy.nextResponder = surface.nextResponder
        surface.nextResponder = spy
        let cgEvent = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                                            wheel1: 7, wheel2: 0, wheel3: 0))
        let scroll = try XCTUnwrap(NSEvent(cgEvent: cgEvent))
        surface.scrollWheel(with: scroll)
        XCTAssertEqual(spy.scrolls, 0, "an enabled surface takes the wheel")
        surface.update(HostSurfaceProperties(surfaceName: "viewport"), enabled: false)
        surface.scrollWheel(with: scroll)
        XCTAssertEqual(spy.scrolls, 1, "a disabled surface lets an enclosing scroll view scroll")
        XCTAssertEqual(client.inputKinds, [AUIHostInputScroll])
    }

    #else

    func testTiltAndModifiers() {
        let upright = HostSurfaceView.tilt(altitude: Double.pi / 2, azimuth: 0)
        XCTAssertEqual(upright.x, 0, accuracy: 1e-9)
        XCTAssertEqual(upright.y, 0, accuracy: 1e-9)
        let flatRight = HostSurfaceView.tilt(altitude: 0, azimuth: 0)
        XCTAssertEqual(flatRight.x, 1, accuracy: 1e-9)
        XCTAssertEqual(HostSurfaceView.modifiers([.shift, .command]),
                       UInt32(AUIHostModifierShift) | UInt32(AUIHostModifierMeta))
    }

    func testFocusGates() {
        let client = RecordingClient()
        ActionUIHostSurface.setDelegate(client, forSurfaceName: "viewport")
        let surface = placedSurface()
        XCTAssertTrue(surface.canBecomeFirstResponder)
        surface.update(HostSurfaceProperties(surfaceName: "viewport"), enabled: false)
        XCTAssertFalse(surface.canBecomeFirstResponder, "not while disabled")
        surface.update(HostSurfaceProperties(surfaceName: "viewport", hidden: true), enabled: true)
        XCTAssertFalse(surface.canBecomeFirstResponder, "not while hidden")
        surface.update(HostSurfaceProperties(surfaceName: "viewport", focusable: false), enabled: true)
        XCTAssertFalse(surface.canBecomeFirstResponder, "not when focusable is false")
    }

    func testUnbindingGivesUpFocusBeforeDestroyed() throws {
        let client = RecordingClient()
        ActionUIHostSurface.setDelegate(client, forSurfaceName: "viewport")
        let surface = placedSurface()
        try XCTSkipUnless(surface.becomeFirstResponder(), "this window cannot hold a first responder")
        client.clear()
        ActionUIHostSurface.setDelegate(nil, forSurfaceName: "viewport")
        XCTAssertFalse(surface.isFirstResponder, "a surface with no client does not keep the keys")
        XCTAssertEqual(client.inputKinds, [AUIHostInputFocusOut])
        XCTAssertEqual(client.events, [.destroyed])
    }

    #endif
}

#if os(macOS)
/// Counts the scroll events that reach it as a next responder.
private final class ScrollSpy: NSResponder {
    private(set) var scrolls = 0

    override func scrollWheel(with event: NSEvent) {
        scrolls += 1
    }
}
#endif
