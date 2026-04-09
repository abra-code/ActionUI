#!/usr/bin/env python3
"""
Smoke tests for the modal/alert/dialog Python bridge.

Exercises present_modal, dismiss_modal, present_alert,
present_confirmation_dialog, and dismiss_dialog at the
Python / C binding layer without starting a real NSApplication
run loop.  No UI is displayed — these tests verify API surface,
type correctness, serialisation, and that unknown UUIDs do not crash.
"""

import sys
import json
import inspect
import _actionui
import actionui

# -------------------------------------------------------------------------
# Simple pass/fail harness
# -------------------------------------------------------------------------

_failures = []

def check(label: str, condition: bool) -> bool:
    status = "PASS" if condition else "FAIL"
    print(f"  [{status}] {label}")
    if not condition:
        _failures.append(label)
    return condition


# -------------------------------------------------------------------------
# Tests
# -------------------------------------------------------------------------

def test_c_api_surface():
    """All modal functions must be present and callable in the C module."""
    print("\n=== _actionui: modal API surface ===")

    expected = [
        "present_modal",
        "dismiss_modal",
        "present_alert",
        "present_confirmation_dialog",
        "dismiss_dialog",
    ]

    for name in expected:
        check(f"_actionui.{name} is callable",
              callable(getattr(_actionui, name, None)))


def test_modal_style_enum():
    """ModalStyle enum must have the correct string values."""
    print("\n=== ModalStyle enum values ===")

    check("ModalStyle is exported from actionui",
          hasattr(actionui, "ModalStyle"))
    check("ModalStyle in __all__",
          "ModalStyle" in actionui.__all__)

    MS = actionui.ModalStyle
    check("ModalStyle.SHEET == 'sheet'",           MS.SHEET.value == "sheet")
    check("ModalStyle.FULL_SCREEN_COVER == 'fullScreenCover'",
          MS.FULL_SCREEN_COVER.value == "fullScreenCover")


def test_button_role_enum():
    """ButtonRole enum must have the correct string values."""
    print("\n=== ButtonRole enum values ===")

    check("ButtonRole is exported from actionui",
          hasattr(actionui, "ButtonRole"))
    check("ButtonRole in __all__",
          "ButtonRole" in actionui.__all__)

    BR = actionui.ButtonRole
    check("ButtonRole.DEFAULT == 'default'",           BR.DEFAULT.value == "default")
    check("ButtonRole.CANCEL == 'cancel'",             BR.CANCEL.value == "cancel")
    check("ButtonRole.DESTRUCTIVE == 'destructive'",   BR.DESTRUCTIVE.value == "destructive")


def test_dialog_button_construction():
    """DialogButton dataclass must construct correctly and serialise via _to_dict."""
    print("\n=== DialogButton construction and serialisation ===")

    check("DialogButton is exported from actionui",
          hasattr(actionui, "DialogButton"))
    check("DialogButton in __all__",
          "DialogButton" in actionui.__all__)

    DB = actionui.DialogButton
    BR = actionui.ButtonRole

    # Minimal — title only
    btn = DB(title="OK")
    d = btn._to_dict()
    check("title-only: 'title' key present",   d.get("title") == "OK")
    check("title-only: 'role' key absent",      "role" not in d)
    check("title-only: 'actionID' key absent",  "actionID" not in d)

    # DEFAULT role → no 'role' key (same as omitting)
    btn = DB(title="OK", role=BR.DEFAULT)
    d = btn._to_dict()
    check("role=DEFAULT: 'role' key absent", "role" not in d)

    # CANCEL role
    btn = DB(title="Cancel", role=BR.CANCEL, action_id=None)
    d = btn._to_dict()
    check("role=CANCEL: role value correct", d.get("role") == "cancel")
    check("role=CANCEL: 'actionID' key absent", "actionID" not in d)

    # DESTRUCTIVE role + action_id
    btn = DB(title="Delete", role=BR.DESTRUCTIVE, action_id="demo.delete.confirmed")
    d = btn._to_dict()
    check("role=DESTRUCTIVE: role value correct", d.get("role") == "destructive")
    check("action_id set: 'actionID' key present", d.get("actionID") == "demo.delete.confirmed")

    # List → JSON round-trip
    buttons = [
        DB(title="Delete", role=BR.DESTRUCTIVE, action_id="demo.delete"),
        DB(title="Cancel", role=BR.CANCEL),
    ]
    payload = json.loads(json.dumps([b._to_dict() for b in buttons]))
    check("JSON round-trip: two buttons", len(payload) == 2)
    check("JSON round-trip: first title", payload[0]["title"] == "Delete")
    check("JSON round-trip: first role",  payload[0]["role"] == "destructive")
    check("JSON round-trip: second title", payload[1]["title"] == "Cancel")
    check("JSON round-trip: second role",  payload[1]["role"] == "cancel")


def test_window_modal_api_exists():
    """Window must expose all five modal methods with the expected signatures."""
    print("\n=== Window modal API surface ===")

    # Create an Application (may already exist)
    if actionui.Application.instance() is None:
        actionui.Application()

    # Build a stub Window using a dummy UUID — we never call present on it
    app = actionui.Application.instance()
    # Access Window class directly rather than constructing through app
    # (constructing through app would try to call C layer).
    # Inspect the class itself.
    W = actionui.Window

    for method_name in ("present_modal", "dismiss_modal",
                        "present_alert", "present_confirmation_dialog",
                        "dismiss_dialog"):
        check(f"Window has method '{method_name}'",
              callable(getattr(W, method_name, None)))

    # Verify parameter names for present_modal
    sig = inspect.signature(W.present_modal)
    params = list(sig.parameters.keys())
    check("present_modal has 'source' param",   "source" in params)
    check("present_modal has 'format' param",   "format" in params)
    check("present_modal has 'style' param",    "style" in params)
    check("present_modal has 'on_dismiss_action_id' param",
          "on_dismiss_action_id" in params)

    # Verify parameter names for present_alert
    sig = inspect.signature(W.present_alert)
    params = list(sig.parameters.keys())
    check("present_alert has 'title' param",   "title" in params)
    check("present_alert has 'message' param", "message" in params)
    check("present_alert has 'buttons' param", "buttons" in params)

    # Verify parameter names for present_confirmation_dialog
    sig = inspect.signature(W.present_confirmation_dialog)
    params = list(sig.parameters.keys())
    check("present_confirmation_dialog has 'title' param",   "title" in params)
    check("present_confirmation_dialog has 'message' param", "message" in params)
    check("present_confirmation_dialog has 'buttons' param", "buttons" in params)


_FAKE_UUID = "00000000-0000-0000-0000-000000000000"


def test_present_modal_unknown_uuid():
    """present_modal on an unknown UUID must raise RuntimeError (no window found)."""
    print("\n=== present_modal: unknown UUID raises RuntimeError ===")

    try:
        _actionui.present_modal(_FAKE_UUID, '{"type":"VStack"}', "json", "sheet", None)
        check("present_modal(unknown UUID) raised RuntimeError", False)
    except RuntimeError:
        check("present_modal(unknown UUID) raises RuntimeError", True)
    except Exception as e:
        check(f"present_modal(unknown UUID) raised unexpected {type(e).__name__}: {e}", False)


def test_dismiss_modal_unknown_uuid():
    """dismiss_modal on an unknown UUID must not crash."""
    print("\n=== dismiss_modal: unknown UUID does not crash ===")

    try:
        _actionui.dismiss_modal(_FAKE_UUID)
        check("dismiss_modal(unknown UUID) does not crash", True)
    except Exception as e:
        check(f"dismiss_modal(unknown UUID) raised {type(e).__name__}: {e}", False)


def test_present_alert_variants():
    """present_alert must not crash for any combination of optional args."""
    print("\n=== present_alert: variant signatures (unknown UUID) ===")

    # Title only
    try:
        _actionui.present_alert(_FAKE_UUID, "Test Alert", None, None)
        check("present_alert(title only) does not crash", True)
    except Exception as e:
        check(f"present_alert(title only) raised {type(e).__name__}: {e}", False)

    # Title + message
    try:
        _actionui.present_alert(_FAKE_UUID, "Test Alert", "Body text", None)
        check("present_alert(title + message) does not crash", True)
    except Exception as e:
        check(f"present_alert(title+message) raised {type(e).__name__}: {e}", False)

    # Title + buttons JSON
    buttons_json = json.dumps([
        {"title": "OK"},
        {"title": "Cancel", "role": "cancel"},
    ])
    try:
        _actionui.present_alert(_FAKE_UUID, "Test Alert", None, buttons_json)
        check("present_alert(title + buttons JSON) does not crash", True)
    except Exception as e:
        check(f"present_alert(title+buttons) raised {type(e).__name__}: {e}", False)


def test_present_confirmation_dialog_variants():
    """present_confirmation_dialog must not crash for valid and edge-case inputs."""
    print("\n=== present_confirmation_dialog: variant signatures (unknown UUID) ===")

    # Minimal — title + empty buttons array
    try:
        _actionui.present_confirmation_dialog(_FAKE_UUID, "Confirm?", None, "[]")
        check("present_confirmation_dialog(empty buttons) does not crash", True)
    except Exception as e:
        check(f"present_confirmation_dialog(empty) raised {type(e).__name__}: {e}", False)

    # With full buttons
    buttons_json = json.dumps([
        {"title": "Delete", "role": "destructive", "actionID": "demo.delete"},
        {"title": "Cancel", "role": "cancel"},
    ])
    try:
        _actionui.present_confirmation_dialog(_FAKE_UUID, "Delete Item?", "Cannot undo.", buttons_json)
        check("present_confirmation_dialog(full) does not crash", True)
    except Exception as e:
        check(f"present_confirmation_dialog(full) raised {type(e).__name__}: {e}", False)


def test_dismiss_dialog_unknown_uuid():
    """dismiss_dialog on an unknown UUID must not crash."""
    print("\n=== dismiss_dialog: unknown UUID does not crash ===")

    try:
        _actionui.dismiss_dialog(_FAKE_UUID)
        check("dismiss_dialog(unknown UUID) does not crash", True)
    except Exception as e:
        check(f"dismiss_dialog(unknown UUID) raised {type(e).__name__}: {e}", False)


def test_window_present_alert_none_buttons():
    """Window.present_alert with buttons=None must not crash on unknown UUID."""
    print("\n=== Window.present_alert / present_confirmation_dialog: None buttons ===")

    # Window(uuid) constructs a lightweight object with only .uuid and ._view_ptr.
    # No NSApplication or C call is made during construction.
    win = actionui.Window(_FAKE_UUID)

    try:
        win.present_alert(title="Hi")
        check("Window.present_alert(title only) does not crash", True)
    except Exception as e:
        check(f"Window.present_alert(title only) raised {type(e).__name__}: {e}", False)

    try:
        win.present_alert(title="Hi",
                          message="msg",
                          buttons=[actionui.DialogButton(title="OK")])
        check("Window.present_alert(with buttons) does not crash", True)
    except Exception as e:
        check(f"Window.present_alert(with buttons) raised {type(e).__name__}: {e}", False)

    try:
        win.present_confirmation_dialog(
            title="Sure?",
            buttons=[actionui.DialogButton(title="Yes", role=actionui.ButtonRole.DESTRUCTIVE,
                                           action_id="confirm"),
                     actionui.DialogButton(title="No",  role=actionui.ButtonRole.CANCEL)])
        check("Window.present_confirmation_dialog(with buttons) does not crash", True)
    except Exception as e:
        check(f"Window.present_confirmation_dialog raised {type(e).__name__}: {e}", False)

    try:
        win.dismiss_modal()
        check("Window.dismiss_modal(unknown UUID) does not crash", True)
    except Exception as e:
        check(f"Window.dismiss_modal raised {type(e).__name__}: {e}", False)

    try:
        win.dismiss_dialog()
        check("Window.dismiss_dialog(unknown UUID) does not crash", True)
    except Exception as e:
        check(f"Window.dismiss_dialog raised {type(e).__name__}: {e}", False)


# -------------------------------------------------------------------------
# Main
# -------------------------------------------------------------------------

def main():
    print("ActionUI Modal/Alert/Dialog API Smoke Tests")
    print("=" * 50)
    print("(No NSApplication run loop — tests the Python/C binding layer only)")

    if actionui.Application.instance() is None:
        actionui.Application()

    test_c_api_surface()
    test_modal_style_enum()
    test_button_role_enum()
    test_dialog_button_construction()
    test_window_modal_api_exists()
    test_present_modal_unknown_uuid()
    test_dismiss_modal_unknown_uuid()
    test_present_alert_variants()
    test_present_confirmation_dialog_variants()
    test_dismiss_dialog_unknown_uuid()
    test_window_present_alert_none_buttons()

    print()
    print("=" * 50)
    if _failures:
        print(f"FAILED — {len(_failures)} assertion(s):")
        for f in _failures:
            print(f"  - {f}")
        sys.exit(1)
    else:
        print(f"All {sum(1 for line in open(__file__) if 'check(' in line)} checks PASSED.")


if __name__ == "__main__":
    main()
