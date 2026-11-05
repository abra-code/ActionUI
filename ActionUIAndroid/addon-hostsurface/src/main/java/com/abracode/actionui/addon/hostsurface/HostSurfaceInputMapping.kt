package com.abracode.actionui.addon.hostsurface

import android.view.KeyEvent
import android.view.MotionEvent
import kotlin.math.cos
import kotlin.math.sin

/*
 Android input to HostSurfaceInput: one event per pointer that changed, in points (dp) from the top-left corner;
 keys with their W3C UI Events code. The tables are pure, for unit tests.
*/
internal object HostSurfaceInputMapping {

    /** [previousButtonState]: the button state of the view's previous touch event, for the button of an up. */
    fun pointerEvents(event: MotionEvent, density: Float, previousButtonState: Int = 0): List<HostSurfaceInput> {
        val indices: IntRange
        val kind: HostInputKind
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN, MotionEvent.ACTION_POINTER_DOWN -> {
                kind = HostInputKind.POINTER_DOWN
                indices = event.actionIndex..event.actionIndex
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_POINTER_UP -> {
                kind = HostInputKind.POINTER_UP
                indices = event.actionIndex..event.actionIndex
            }
            MotionEvent.ACTION_MOVE -> {
                kind = HostInputKind.POINTER_DRAG
                indices = 0 until event.pointerCount
            }
            MotionEvent.ACTION_CANCEL -> {
                kind = HostInputKind.POINTER_CANCEL
                indices = 0 until event.pointerCount
            }
            MotionEvent.ACTION_HOVER_MOVE -> {
                kind = HostInputKind.POINTER_MOVE
                indices = 0 until event.pointerCount
            }
            MotionEvent.ACTION_HOVER_ENTER -> {
                kind = HostInputKind.POINTER_ENTER
                indices = 0 until event.pointerCount
            }
            MotionEvent.ACTION_HOVER_EXIT -> {
                kind = HostInputKind.POINTER_EXIT
                indices = 0 until event.pointerCount
            }
            else -> return emptyList()
        }
        val buttonState = if (kind == HostInputKind.POINTER_UP) {
            upButtonState(previousButtonState, event.buttonState)
        } else {
            event.buttonState
        }
        return indices.map { index ->
            val toolType = event.getToolType(index)
            val pointerType = pointerType(toolType)
            val pressing = kind == HostInputKind.POINTER_DOWN || kind == HostInputKind.POINTER_DRAG
            val tilt = if (pointerType == HostPointerType.PEN) {
                tiltComponents(event.getAxisValue(MotionEvent.AXIS_TILT, index), event.getOrientation(index))
            } else {
                0.0 to 0.0
            }
            HostSurfaceInput(
                kind = kind,
                pointerType = pointerType,
                button = button(buttonState),
                // The mouse is pointer 0, as on the other platforms.
                pointerID = if (pointerType == HostPointerType.MOUSE) 0 else event.getPointerId(index).toLong(),
                modifiers = modifiers(event.metaState),
                clickCount = if (kind == HostInputKind.POINTER_DOWN || kind == HostInputKind.POINTER_UP) 1 else 0,
                x = (event.getX(index) / density).toDouble(),
                y = (event.getY(index) / density).toDouble(),
                pressure = if (pressing) event.getPressure(index).toDouble().coerceIn(0.0, 1.0) else 0.0,
                tiltX = tilt.first,
                tiltY = tilt.second,
                timestampSeconds = event.eventTime / 1000.0,
            )
        }
    }

    fun keyEvent(event: KeyEvent): HostSurfaceInput? {
        val kind = when (event.action) {
            KeyEvent.ACTION_DOWN -> HostInputKind.KEY_DOWN
            KeyEvent.ACTION_UP -> HostInputKind.KEY_UP
            else -> return null
        }
        val text = if (kind == HostInputKind.KEY_DOWN) insertableText(event.unicodeChar) else null
        return HostSurfaceInput(
            kind = kind,
            pointerType = HostPointerType.MOUSE,
            modifiers = modifiers(event.metaState),
            keyCode = event.keyCode,
            code = code(event.keyCode),
            text = text,
            timestampSeconds = event.eventTime / 1000.0,
        )
    }

    fun pointerType(toolType: Int): HostPointerType = when (toolType) {
        MotionEvent.TOOL_TYPE_MOUSE -> HostPointerType.MOUSE
        MotionEvent.TOOL_TYPE_STYLUS, MotionEvent.TOOL_TYPE_ERASER -> HostPointerType.PEN
        else -> HostPointerType.TOUCH
    }

    /** 0 primary, 1 secondary, 2 middle, from MotionEvent.getButtonState. */
    fun button(buttonState: Int): Int = when {
        buttonState and (MotionEvent.BUTTON_SECONDARY or MotionEvent.BUTTON_STYLUS_SECONDARY) != 0 -> 1
        buttonState and MotionEvent.BUTTON_TERTIARY != 0 -> 2
        else -> 0
    }

    /**
     * The buttons an ACTION_UP released. Its own button state holds only the buttons still down (a right
     * click: DOWN 0x2, UP 0x0), so the released ones are those of the previous event that are gone.
     */
    fun upButtonState(previous: Int, current: Int): Int {
        val released = previous and current.inv()
        return if (released != 0) released else current
    }

    fun modifiers(metaState: Int): Int {
        var bits = 0
        if (metaState and KeyEvent.META_SHIFT_ON != 0) bits = bits or HostModifiers.SHIFT
        if (metaState and KeyEvent.META_CTRL_ON != 0) bits = bits or HostModifiers.CONTROL
        if (metaState and KeyEvent.META_ALT_ON != 0) bits = bits or HostModifiers.ALT
        if (metaState and KeyEvent.META_META_ON != 0) bits = bits or HostModifiers.META
        if (metaState and KeyEvent.META_CAPS_LOCK_ON != 0) bits = bits or HostModifiers.CAPS_LOCK
        return bits
    }

    /**
     * Pen tilt as x and y components in -1...1, from Android's tilt (radians from the perpendicular) and
     * orientation (radians clockwise from up).
     */
    fun tiltComponents(tilt: Float, orientation: Float): Pair<Double, Double> {
        val lean = sin(tilt.toDouble())
        return lean * sin(orientation.toDouble()) to -lean * cos(orientation.toDouble())
    }

    /** The character a key produced, or null for none and for control characters. */
    fun insertableText(codePoint: Int): String? {
        if (codePoint < 0x20 || codePoint == 0x7F || codePoint and KeyCharacterMapCombining != 0) {
            return null
        }
        return String(Character.toChars(codePoint))
    }

    // KeyCharacterMap.COMBINING_ACCENT: a dead key, not text yet.
    private const val KeyCharacterMapCombining = 0x80000000.toInt()

    /** The W3C UI Events code for an Android key code, or "" when it has none. */
    fun code(keyCode: Int): String = codes[keyCode] ?: ""

    private val codes: Map<Int, String> = buildMap {
        for (index in 0 until 26) {
            put(KeyEvent.KEYCODE_A + index, "Key${'A' + index}")
        }
        for (digit in 0..9) {
            put(KeyEvent.KEYCODE_0 + digit, "Digit$digit")
            put(KeyEvent.KEYCODE_NUMPAD_0 + digit, "Numpad$digit")
        }
        for (number in 1..12) {
            put(KeyEvent.KEYCODE_F1 + number - 1, "F$number")
        }
        putAll(
            mapOf(
                KeyEvent.KEYCODE_DPAD_UP to "ArrowUp", KeyEvent.KEYCODE_DPAD_DOWN to "ArrowDown",
                KeyEvent.KEYCODE_DPAD_LEFT to "ArrowLeft", KeyEvent.KEYCODE_DPAD_RIGHT to "ArrowRight",
                KeyEvent.KEYCODE_ENTER to "Enter", KeyEvent.KEYCODE_ESCAPE to "Escape",
                KeyEvent.KEYCODE_DEL to "Backspace", KeyEvent.KEYCODE_FORWARD_DEL to "Delete",
                KeyEvent.KEYCODE_TAB to "Tab", KeyEvent.KEYCODE_SPACE to "Space",
                KeyEvent.KEYCODE_SHIFT_LEFT to "ShiftLeft", KeyEvent.KEYCODE_SHIFT_RIGHT to "ShiftRight",
                KeyEvent.KEYCODE_CTRL_LEFT to "ControlLeft", KeyEvent.KEYCODE_CTRL_RIGHT to "ControlRight",
                KeyEvent.KEYCODE_ALT_LEFT to "AltLeft", KeyEvent.KEYCODE_ALT_RIGHT to "AltRight",
                KeyEvent.KEYCODE_META_LEFT to "MetaLeft", KeyEvent.KEYCODE_META_RIGHT to "MetaRight",
                KeyEvent.KEYCODE_CAPS_LOCK to "CapsLock", KeyEvent.KEYCODE_MINUS to "Minus",
                KeyEvent.KEYCODE_EQUALS to "Equal", KeyEvent.KEYCODE_LEFT_BRACKET to "BracketLeft",
                KeyEvent.KEYCODE_RIGHT_BRACKET to "BracketRight", KeyEvent.KEYCODE_BACKSLASH to "Backslash",
                KeyEvent.KEYCODE_SEMICOLON to "Semicolon", KeyEvent.KEYCODE_APOSTROPHE to "Quote",
                KeyEvent.KEYCODE_GRAVE to "Backquote", KeyEvent.KEYCODE_COMMA to "Comma",
                KeyEvent.KEYCODE_PERIOD to "Period", KeyEvent.KEYCODE_SLASH to "Slash",
                KeyEvent.KEYCODE_PAGE_UP to "PageUp", KeyEvent.KEYCODE_PAGE_DOWN to "PageDown",
                KeyEvent.KEYCODE_MOVE_HOME to "Home", KeyEvent.KEYCODE_MOVE_END to "End",
                KeyEvent.KEYCODE_INSERT to "Insert", KeyEvent.KEYCODE_NUMPAD_DIVIDE to "NumpadDivide",
                KeyEvent.KEYCODE_NUMPAD_MULTIPLY to "NumpadMultiply", KeyEvent.KEYCODE_NUMPAD_SUBTRACT to "NumpadSubtract",
                KeyEvent.KEYCODE_NUMPAD_ADD to "NumpadAdd", KeyEvent.KEYCODE_NUMPAD_DOT to "NumpadDecimal",
                KeyEvent.KEYCODE_NUMPAD_COMMA to "NumpadComma", KeyEvent.KEYCODE_NUMPAD_ENTER to "NumpadEnter",
                KeyEvent.KEYCODE_NUMPAD_EQUALS to "NumpadEqual", KeyEvent.KEYCODE_NUM_LOCK to "NumLock",
                KeyEvent.KEYCODE_SCROLL_LOCK to "ScrollLock", KeyEvent.KEYCODE_SYSRQ to "PrintScreen",
                KeyEvent.KEYCODE_BREAK to "Pause", KeyEvent.KEYCODE_MENU to "ContextMenu",
            ),
        )
    }
}
