// Add-ons/ActionUIHostSurface/Sources/ActionUIHostSurface/HostSurfaceView+AdwaitaInput.swift
//
// Input on Linux, as AUIHostInputEvent (the C header): one legacy event controller takes the raw GDK events
// (pointer, touch, pen, scroll, touchpad pinch, keys), a motion controller the pointer's enter and leave, and the
// widget's has-focus keyboard focus. The rules are those of the Apple view:
// - input only while a client is bound and the surface is on screen; otherwise events pass on, so an enclosing
//   scroll view still scrolls;
// - the surface takes the wheel, so an enclosing scroll view does not scroll as well;
// - it never takes focus unasked: a press focuses it when "focusable" is true; Tab moves focus on (not
//   delivered);
// - FocusIn and FocusOut follow keyboard focus and the window's activity, and FocusOut comes before "destroyed".
// Keys with Control, Alt or Super held are delivered and passed on as well, so the window's and the
// application's shortcuts still work. Text comes from the key's character; input methods are not handled.

#if os(Linux)

import FoundationEssentials
import CAdwaita
import CActionUIHostSurface

extension HostSurfaceView {

    func installInputHandlers() {
        let legacy = gtk_event_controller_legacy_new()!
        connect(legacy, "event", unsafeBitCast(legacyEventTrampoline, to: GCallback.self))
        gtk_widget_add_controller(widget, legacy)

        let motion = gtk_event_controller_motion_new()!
        connect(motion, "enter", unsafeBitCast(pointerEnterTrampoline, to: GCallback.self))
        connect(motion, "leave", unsafeBitCast(pointerLeaveTrampoline, to: GCallback.self))
        gtk_widget_add_controller(widget, motion)

        // has-focus, not a focus controller: GtkWindow emits the controller's "enter" before it sets has-focus
        // (gtk_window_root_set_focus), so FocusIn would never come there. has-focus also follows the window's
        // activity.
        connect(UnsafeMutableRawPointer(widget), "notify::has-focus",
                unsafeBitCast(focusChangedTrampoline, to: GCallback.self))
    }

    /// Connects a signal to this view through a weak reference that the signal releases.
    private func connect(_ instance: UnsafeMutableRawPointer, _ signal: String, _ callback: GCallback) {
        let box = Unmanaged.passRetained(WeakHostSurfaceView(self)).toOpaque()
        g_signal_connect_data(instance, signal, callback, box, releaseWeakView, GConnectFlags(rawValue: 0))
    }

    private func connect(_ controller: OpaquePointer, _ signal: String, _ callback: GCallback) {
        connect(UnsafeMutableRawPointer(controller), signal, callback)
    }

    /// Input reaches the client: one is bound, the surface is on screen, and the element is enabled.
    var inputAllowed: Bool {
        surfaceID != 0 && !suspendedSent && gtk_widget_is_sensitive(widget) != 0
    }

    /// The widget may take keyboard focus: "focusable", a client, not hidden.
    var canTakeFocus: Bool {
        properties.focusable && surfaceID != 0 && !properties.hidden
    }

    /// Applies canTakeFocus to the widget, gives focus up when it is lost, and delivers the focus change.
    func updateFocusability() {
        let focusable: gboolean = canTakeFocus ? 1 : 0
        if gtk_widget_get_focusable(widget) != focusable {
            gtk_widget_set_focusable(widget, focusable)
        }
        if !canTakeFocus {
            giveUpFocus()
        }
        updateFocusDelivery()
    }

    /// FocusIn or FocusOut when the surface's keyboard focus changed: focused in an active window, with a client.
    func updateFocusDelivery() {
        let focused = surfaceID != 0 && gtk_widget_has_focus(widget) != 0
        guard focused != focusDelivered else {
            return
        }
        focusDelivered = focused
        var event = AUIHostInputEvent()
        event.kind = Int32(focused ? AUIHostInputFocusIn.rawValue : AUIHostInputFocusOut.rawValue)
        deliverInput(event)
    }

    // MARK: events

    fileprivate func handle(_ event: OpaquePointer) -> Bool {
        let type = gdk_event_get_event_type(event)
        if type == GDK_KEY_PRESS || type == GDK_KEY_RELEASE {
            return handleKey(event, pressed: type == GDK_KEY_PRESS)
        }
        guard inputAllowed else {
            return false
        }
        // GTK 4 makes no pointer events from touch: gdk_event_get_pointer_emulated marks the touch events of the
        // first finger (the one that drives the pointer), which are delivered like the others.
        switch type {
        case GDK_BUTTON_PRESS, GDK_BUTTON_RELEASE:
            handleButton(event, pressed: type == GDK_BUTTON_PRESS)
        case GDK_MOTION_NOTIFY:
            var input = pointerEvent(event)
            let state = gdk_event_get_modifier_state(event).rawValue
            let held = HostSurfaceGtkInput.buttonHeld(state)
            input.kind = Int32(held ? AUIHostInputPointerDrag.rawValue : AUIHostInputPointerMove.rawValue)
            if held {
                // The button that drags, as on Apple platforms.
                input.button = HostSurfaceGtkInput.heldButton(state)
            } else {
                input.pressure = 0
            }
            deliverInput(input)
        case GDK_TOUCH_BEGIN, GDK_TOUCH_UPDATE, GDK_TOUCH_END, GDK_TOUCH_CANCEL:
            handleTouch(event, type: type)
        case GDK_SCROLL:
            handleScroll(event)
        case GDK_TOUCHPAD_PINCH:
            handlePinch(event)
        default:
            return false
        }
        return true
    }

    private func handleButton(_ event: OpaquePointer, pressed: Bool) {
        var input = pointerEvent(event)
        let button = HostSurfaceGtkInput.button(gdk_button_event_get_button(event))
        input.button = button
        if pressed {
            input.kind = Int32(AUIHostInputPointerDown.rawValue)
            let settings = doubleClickSettings()
            input.clickCount = clickCounter.press(button: button, x: input.x, y: input.y,
                                                  timeMilliseconds: gdk_event_get_time(event),
                                                  doubleClickTime: settings.time, doubleClickDistance: settings.distance)
            // A press focuses the surface, as a click does on the other platforms.
            if canTakeFocus, gtk_widget_has_focus(widget) == 0 {
                gtk_widget_grab_focus(widget)
            }
        } else {
            input.kind = Int32(AUIHostInputPointerUp.rawValue)
            input.clickCount = clickCounter.count
            input.pressure = 0
        }
        deliverInput(input)
    }

    private func handleTouch(_ event: OpaquePointer, type: GdkEventType) {
        var input = pointerEvent(event)
        input.pointerType = Int32(AUIHostPointerTouch.rawValue)
        let sequence = UInt(bitPattern: gdk_event_get_event_sequence(event))
        let id: Int64
        if let known = touchIDs[sequence] {
            id = known
        } else {
            lastTouchID += 1
            id = lastTouchID
            touchIDs[sequence] = id
        }
        input.pointerID = id
        switch type {
        case GDK_TOUCH_BEGIN:
            input.kind = Int32(AUIHostInputPointerDown.rawValue)
            input.clickCount = 1
            if canTakeFocus, gtk_widget_has_focus(widget) == 0 {
                gtk_widget_grab_focus(widget)
            }
        case GDK_TOUCH_UPDATE:
            input.kind = Int32(AUIHostInputPointerDrag.rawValue)
        case GDK_TOUCH_END:
            input.kind = Int32(AUIHostInputPointerUp.rawValue)
            input.clickCount = 1
            input.pressure = 0
            touchIDs[sequence] = nil
        default:
            input.kind = Int32(AUIHostInputPointerCancel.rawValue)
            input.pressure = 0
            touchIDs[sequence] = nil
        }
        deliverInput(input)
    }

    private func handleScroll(_ event: OpaquePointer) {
        var input = pointerEvent(event)
        input.kind = Int32(AUIHostInputScroll.rawValue)
        input.pressure = 0
        let direction = gdk_scroll_event_get_direction(event)
        // Every GTK 4 scroll event has deltas; for a wheel they are its steps, fractions for a high-resolution
        // wheel, and right where the direction is not (GDK Wayland names value120 horizontal steps the wrong
        // way round). GtkEventControllerScroll reads the deltas too.
        var dx = 0.0
        var dy = 0.0
        gdk_scroll_event_get_deltas(event, &dx, &dy)
        if direction == GDK_SCROLL_SMOOTH {
            (input.deltaX, input.deltaY) = HostSurfaceGtkInput.contentDelta(dx, dy)
            let wheel = gdk_scroll_event_get_unit(event) == GDK_SCROLL_UNIT_WHEEL
            input.scrollUnit = Int32(wheel ? AUIHostScrollSteps.rawValue : AUIHostScrollPoints.rawValue)
            if wheel {
                input.scrollPhase = Int32(AUIHostScrollPhaseNone.rawValue)
            } else if gdk_scroll_event_is_stop(event) != 0 {
                input.scrollPhase = Int32(AUIHostScrollPhaseEnded.rawValue)
                scrollGestureActive = false
            } else {
                input.scrollPhase = Int32(scrollGestureActive ? AUIHostScrollPhaseChanged.rawValue : AUIHostScrollPhaseBegan.rawValue)
                scrollGestureActive = true
            }
        } else if dx != 0 || dy != 0 {
            (input.deltaX, input.deltaY) = HostSurfaceGtkInput.contentDelta(dx, dy)
            input.scrollUnit = Int32(AUIHostScrollSteps.rawValue)
            input.scrollPhase = Int32(AUIHostScrollPhaseNone.rawValue)
        } else if let step = HostSurfaceGtkInput.stepDelta(direction) {
            (input.deltaX, input.deltaY) = step
            input.scrollUnit = Int32(AUIHostScrollSteps.rawValue)
            input.scrollPhase = Int32(AUIHostScrollPhaseNone.rawValue)
        } else {
            return
        }
        deliverInput(input)
    }

    private func handlePinch(_ event: OpaquePointer) {
        let phase = gdk_touchpad_event_get_gesture_phase(event)
        let scale = gdk_touchpad_event_get_pinch_scale(event)
        if phase == GDK_TOUCHPAD_GESTURE_PHASE_BEGIN {
            lastPinchScale = 1
        }
        // Only updates move: GDK Wayland gives the end and the cancel a scale of 1, which would undo the pinch.
        guard phase == GDK_TOUCHPAD_GESTURE_PHASE_UPDATE else {
            return
        }
        var base = pointerEvent(event)
        base.pressure = 0
        if scale != lastPinchScale, scale > 0 {
            var magnify = base
            magnify.kind = Int32(AUIHostInputMagnify.rawValue)
            magnify.deltaX = scale - lastPinchScale
            lastPinchScale = scale
            deliverInput(magnify)
        }
        let angle = gdk_touchpad_event_get_pinch_angle_delta(event)
        if angle != 0 {
            var rotate = base
            rotate.kind = Int32(AUIHostInputRotate.rawValue)
            // GDK's angle grows clockwise; the header's counterclockwise.
            rotate.deltaX = -angle * 180 / Double.pi
            deliverInput(rotate)
        }
    }

    private func handleKey(_ event: OpaquePointer, pressed: Bool) -> Bool {
        let keyval = gdk_key_event_get_keyval(event)
        let state = gdk_event_get_modifier_state(event).rawValue
        let isTab = keyval == UInt32(GDK_KEY_Tab) || keyval == UInt32(GDK_KEY_ISO_Left_Tab)
        // Tab moves focus on, as for any control; with Control held it is the client's.
        guard inputAllowed, gtk_widget_has_focus(widget) != 0,
              !(isTab && state & GDK_CONTROL_MASK.rawValue == 0) else {
            return false
        }
        let hardware = gdk_key_event_get_keycode(event)
        var input = AUIHostInputEvent()
        input.kind = Int32(pressed ? AUIHostInputKeyDown.rawValue : AUIHostInputKeyUp.rawValue)
        input.modifiers = HostSurfaceGtkInput.modifiers(state)
        input.keyCode = hardware
        input.timestampSeconds = Double(gdk_event_get_time(event)) / 1000
        let text = pressed ? HostSurfaceGtkInput.text(unicode: gdk_keyval_to_unicode(keyval), state: state) : nil
        deliverInput(input, code: HostSurfaceGtkInput.code(hardwareKeycode: hardware), text: text)
        // A possible shortcut goes on to the window and the application too. Not Control-Tab, the client's:
        // GtkWindow binds it to move focus.
        return isTab || !HostSurfaceGtkInput.isShortcutCandidate(state)
    }

    /// The fields every pointer event has: position in points from the widget's top left, pointer type, pen
    /// pressure and tilt, modifiers, time.
    private func pointerEvent(_ event: OpaquePointer) -> AUIHostInputEvent {
        var input = AUIHostInputEvent()
        let point = widgetPoint(event)
        input.x = point.x
        input.y = point.y
        input.modifiers = HostSurfaceGtkInput.modifiers(gdk_event_get_modifier_state(event).rawValue)
        input.timestampSeconds = Double(gdk_event_get_time(event)) / 1000
        input.pointerType = Int32(AUIHostPointerMouse.rawValue)
        input.pressure = 1
        if let tool = gdk_event_get_device_tool(event) {
            let toolType = gdk_device_tool_get_tool_type(tool)
            if toolType == GDK_DEVICE_TOOL_TYPE_PEN || toolType == GDK_DEVICE_TOOL_TYPE_ERASER
                || toolType == GDK_DEVICE_TOOL_TYPE_PENCIL || toolType == GDK_DEVICE_TOOL_TYPE_BRUSH {
                input.pointerType = Int32(AUIHostPointerPen.rawValue)
            }
        } else if let device = gdk_event_get_device(event), gdk_device_get_source(device) == GDK_SOURCE_PEN {
            input.pointerType = Int32(AUIHostPointerPen.rawValue)
        }
        var value = 0.0
        if gdk_event_get_axis(event, GDK_AXIS_PRESSURE, &value) != 0 {
            input.pressure = min(max(value, 0), 1)
        }
        if gdk_event_get_axis(event, GDK_AXIS_XTILT, &value) != 0 {
            input.tiltX = min(max(value, -1), 1)
        }
        if gdk_event_get_axis(event, GDK_AXIS_YTILT, &value) != 0 {
            input.tiltY = min(max(value, -1), 1)
        }
        return input
    }

    /// The event's position (relative to its window's surface) in the widget's coordinates.
    private func widgetPoint(_ event: OpaquePointer) -> (x: Double, y: Double) {
        var x = 0.0
        var y = 0.0
        guard gdk_event_get_position(event, &x, &y) != 0, let native = gtk_widget_get_native(widget) else {
            return (0, 0)
        }
        var offsetX = 0.0
        var offsetY = 0.0
        gtk_native_get_surface_transform(native, &offsetX, &offsetY)
        let nativeWidget = UnsafeMutableRawPointer(native).assumingMemoryBound(to: GtkWidget.self)
        var from = graphene_point_t(x: Float(x - offsetX), y: Float(y - offsetY))
        var to = graphene_point_t()
        guard gtk_widget_compute_point(nativeWidget, widget, &from, &to) != 0 else {
            return (0, 0)
        }
        return (Double(to.x), Double(to.y))
    }

    /// GTK's double-click time (ms) and distance (pixels), from the display's settings.
    private func doubleClickSettings() -> (time: UInt32, distance: Double) {
        guard let settings = gtk_widget_get_settings(widget) else {
            return (400, 5)
        }
        let object = UnsafeMutableRawPointer(settings).assumingMemoryBound(to: GObject.self)
        func integer(_ name: String, _ fallback: Int32) -> Int32 {
            var value = GValue()
            // G_TYPE_INT, a fundamental type number (6) shifted by G_TYPE_FUNDAMENTAL_SHIFT (2).
            g_value_init(&value, GType(6 << 2))
            g_object_get_property(object, name, &value)
            let result = g_value_get_int(&value)
            g_value_unset(&value)
            return result > 0 ? result : fallback
        }
        return (UInt32(integer("gtk-double-click-time", 400)), Double(integer("gtk-double-click-distance", 5)))
    }

    // MARK: pointer enter and exit

    fileprivate func pointerEntered(x: Double, y: Double) {
        guard inputAllowed else {
            return
        }
        var input = AUIHostInputEvent()
        input.kind = Int32(AUIHostInputPointerEnter.rawValue)
        input.x = x
        input.y = y
        deliverInput(input)
    }

    fileprivate func pointerLeft() {
        guard inputAllowed else {
            return
        }
        var input = AUIHostInputEvent()
        input.kind = Int32(AUIHostInputPointerExit.rawValue)
        deliverInput(input)
    }
}

private let legacyEventTrampoline: @convention(c) (gpointer?, OpaquePointer?, gpointer?) -> gboolean = { _, event, data in
    guard let event, let data else {
        return 0
    }
    nonisolated(unsafe) let target = (event, data)
    return MainActor.assumeIsolated {
        guard let view = Unmanaged<WeakHostSurfaceView>.fromOpaque(target.1).takeUnretainedValue().view else {
            return 0
        }
        return view.handle(target.0) ? 1 : 0
    }
}

private let pointerEnterTrampoline: @convention(c) (gpointer?, Double, Double, gpointer?) -> Void = { _, x, y, data in
    guard let data else {
        return
    }
    nonisolated(unsafe) let box = data
    MainActor.assumeIsolated {
        Unmanaged<WeakHostSurfaceView>.fromOpaque(box).takeUnretainedValue().view?.pointerEntered(x: x, y: y)
    }
}

private let pointerLeaveTrampoline: @convention(c) (gpointer?, gpointer?) -> Void = { _, data in
    guard let data else {
        return
    }
    nonisolated(unsafe) let box = data
    MainActor.assumeIsolated {
        Unmanaged<WeakHostSurfaceView>.fromOpaque(box).takeUnretainedValue().view?.pointerLeft()
    }
}

private let focusChangedTrampoline: @convention(c) (gpointer?, gpointer?, gpointer?) -> Void = { _, _, data in
    guard let data else {
        return
    }
    nonisolated(unsafe) let box = data
    MainActor.assumeIsolated {
        Unmanaged<WeakHostSurfaceView>.fromOpaque(box).takeUnretainedValue().view?.updateFocusDelivery()
    }
}

#endif
