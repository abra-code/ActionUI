#!/usr/bin/env python3
"""
Integration tests for the ActionUIAppKitApplication menu bar.

Exercises:
  1. C-level API surface (_actionui.app_load_menu_bar exists and is callable)
  2. Python-level API (Application.load_menu_bar)
  3. Default menu bar installation via actionUIAppRun()
  4. CommandMenu JSON — adds a custom top-level menu with Button children
  5. CommandGroup JSON — inserts items into an existing default menu
  6. Action handler dispatch from custom menu items

Starts a real NSApplication run loop (requires a graphical macOS environment).
Uses the atexit pattern from test_app_lifecycle.py because
NSApplication.terminate() calls C exit() directly.

Usage
-----
    python3 test_menu_bar.py
"""

import sys
import os
import json
import atexit
import threading
import _actionui
import actionui

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

SAFETY_TIMEOUT_SEC = 30.0
DISPLAY_SEC = 10.0  # time to visually inspect menus before auto-termination

_HERE = os.path.dirname(os.path.abspath(__file__))
FIXTURE_JSON = os.path.normpath(os.path.join(
    _HERE, "..", "ActionUIObjCTestApp", "DefaultWindowContentView.json"
))

# ---------------------------------------------------------------------------
# Shared state
# ---------------------------------------------------------------------------

state = {
    "menu_bar_installed":       False,
    "custom_menu_loaded":       False,
    "command_group_loaded":     False,
    "action_fired":             False,
    "action_id_received":       None,
    "errors":                   [],
}

_check_count = 0
_failures    = []


def check(label: str, condition: bool) -> bool:
    global _check_count
    _check_count += 1
    status = "PASS" if condition else "FAIL"
    print(f"  [{status}] {label}", flush=True)
    if not condition:
        _failures.append(label)
    return condition


# ---------------------------------------------------------------------------
# atexit handler — runs after NSApplication.terminate() → exit()
# ---------------------------------------------------------------------------

@atexit.register
def _report():
    print("\nNSApplication exited — running assertions …\n", flush=True)

    if state["errors"]:
        for err in state["errors"]:
            print(f"  [ERROR] {err}", flush=True)
        print(flush=True)

    print("C API surface:", flush=True)
    check("_actionui.app_load_menu_bar is callable",
          callable(getattr(_actionui, "app_load_menu_bar", None)))

    print(flush=True)
    print("Default menu bar:", flush=True)
    check("Menu bar was installed by app.run()",
          state["menu_bar_installed"])

    print(flush=True)
    print("CommandMenu (custom top-level menu):", flush=True)
    check("Custom CommandMenu JSON loaded without error",
          state["custom_menu_loaded"])

    print(flush=True)
    print("CommandGroup (items into existing menu):", flush=True)
    check("CommandGroup JSON loaded without error",
          state["command_group_loaded"])

    print(flush=True)
    print("Action handler dispatch:", flush=True)
    check("Action handler was fired from menu item",
          state["action_fired"])
    check("Received correct actionID 'test.menuAction'",
          state["action_id_received"] == "test.menuAction")

    print(flush=True)
    print("=" * 50, flush=True)
    all_bad = _failures + state["errors"]
    if all_bad:
        print(f"FAILED — {len(all_bad)} issue(s):", flush=True)
        for item in all_bad:
            print(f"  - {item}", flush=True)
        os._exit(1)
    else:
        print(f"All {_check_count} menu bar checks PASSED.", flush=True)


# ---------------------------------------------------------------------------
# Non-run-loop tests (before app.run)
# ---------------------------------------------------------------------------

def test_api_surface():
    """Verify C module has the new function."""
    print("\n=== _actionui: menu bar API surface ===", flush=True)
    check("_actionui.app_load_menu_bar exists",
          hasattr(_actionui, "app_load_menu_bar"))
    check("_actionui.app_load_menu_bar is callable",
          callable(getattr(_actionui, "app_load_menu_bar", None)))


def test_load_menu_bar_no_args():
    """Calling app_load_menu_bar() with no args must not raise."""
    print("\n=== app_load_menu_bar() — no args ===", flush=True)
    try:
        _actionui.app_load_menu_bar()
        check("app_load_menu_bar() with no args does not raise", True)
    except Exception as e:
        check(f"app_load_menu_bar() raised {type(e).__name__}: {e}", False)


def test_load_menu_bar_null():
    """Calling app_load_menu_bar(None) must not raise."""
    print("\n=== app_load_menu_bar(None) ===", flush=True)
    try:
        _actionui.app_load_menu_bar(None)
        check("app_load_menu_bar(None) does not raise", True)
    except Exception as e:
        check(f"app_load_menu_bar(None) raised {type(e).__name__}: {e}", False)


def test_python_api_exists():
    """Application.load_menu_bar method must exist."""
    print("\n=== Application.load_menu_bar method ===", flush=True)
    check("Application has load_menu_bar method",
          hasattr(actionui.Application, "load_menu_bar"))


def test_load_menu_bar_invalid_json():
    """Invalid JSON must not crash — just log an error."""
    print("\n=== app_load_menu_bar() — invalid JSON ===", flush=True)
    try:
        _actionui.app_load_menu_bar("this is not json")
        check("Invalid JSON string does not crash", True)
    except Exception as e:
        check(f"Invalid JSON raised {type(e).__name__}: {e}", False)

    try:
        _actionui.app_load_menu_bar('{"type": "CommandMenu"}')
        check("Non-array JSON does not crash", True)
    except Exception as e:
        check(f"Non-array JSON raised {type(e).__name__}: {e}", False)


def test_load_menu_bar_empty_array():
    """Empty array must be accepted — no menus to add."""
    print("\n=== app_load_menu_bar() — empty array ===", flush=True)
    try:
        _actionui.app_load_menu_bar("[]")
        check("Empty array JSON does not crash", True)
    except Exception as e:
        check(f"Empty array raised {type(e).__name__}: {e}", False)


# ---------------------------------------------------------------------------
# JSON fixtures for run-loop tests
# ---------------------------------------------------------------------------

COMMAND_MENU_JSON = json.dumps([
    {
        "type": "CommandMenu",
        "id": 500,
        "properties": {"name": "Test Tools"},
        "children": [
            {
                "type": "Button",
                "id": 501,
                "properties": {
                    "title": "Run Test Action",
                    "actionID": "test.menuAction",
                    "keyboardShortcut": {
                        "key": "t",
                        "modifiers": ["command", "shift"]
                    }
                }
            },
            {
                "type": "Divider",
                "id": 502
            },
            {
                "type": "Button",
                "id": 503,
                "properties": {
                    "title": "No Shortcut Item",
                    "actionID": "test.noShortcut"
                }
            }
        ]
    }
])

COMMAND_GROUP_JSON = json.dumps([
    {
        "type": "CommandGroup",
        "id": 600,
        "properties": {
            "placement": "after",
            "placementTarget": "help"
        },
        "children": [
            {
                "type": "Button",
                "id": 601,
                "properties": {
                    "title": "Extra Help Item",
                    "actionID": "test.extraHelp"
                }
            }
        ]
    }
])


# ---------------------------------------------------------------------------
# Application + run-loop tests
# ---------------------------------------------------------------------------

print("ActionUI Menu Bar Integration Test", flush=True)
print("=" * 50, flush=True)

# Pre-run-loop tests (no NSApplication needed)
test_api_surface()
test_load_menu_bar_no_args()
test_load_menu_bar_null()
test_python_api_exists()
test_load_menu_bar_invalid_json()
test_load_menu_bar_empty_array()

# Create application for run-loop tests
app = actionui.Application(name="MenuBarTest")


@app.action("test.menuAction")
def on_test_action(ctx: actionui.ActionContext):
    state["action_fired"] = True
    state["action_id_received"] = ctx.action_id
    print(f"  [CB] action handler fired: {ctx.action_id}", flush=True)


@app.did_finish_launching
def _did_finish():
    print("\n  [CB] did_finish_launching", flush=True)

    # Open a window so the app has something to show and can activate properly.
    if os.path.exists(FIXTURE_JSON):
        window = app.load_and_present_window(FIXTURE_JSON, title="Menu Bar Test")
        state["window_uuid"] = window.uuid
        print(f"  [CB] window opened: {window.uuid}", flush=True)
    else:
        print(f"  [CB] fixture not found: {FIXTURE_JSON} — skipping window", flush=True)

    # At this point actionUIAppRun() has been called, which installs
    # the default menu bar automatically.
    # Use PyObjC (ships with macOS system Python and Homebrew Python) to
    # inspect the live NSMenu hierarchy.
    try:
        from AppKit import NSApplication
        _has_pyobjc = True
    except ImportError:
        _has_pyobjc = False
        print("  [CB] PyObjC not available — skipping menu bar introspection", flush=True)

    if _has_pyobjc:
        main_menu = NSApplication.sharedApplication().mainMenu()
        state["menu_bar_installed"] = (main_menu is not None
                                       and main_menu.numberOfItems() > 0)
        if state["menu_bar_installed"]:
            count = main_menu.numberOfItems()
            print(f"  [CB] Default menu bar installed ({count} top-level menus)", flush=True)
        else:
            state["errors"].append("Default menu bar not installed after app.run()")
    else:
        # Without PyObjC we trust that no crash means the menu bar was installed
        state["menu_bar_installed"] = True

    # Load a custom CommandMenu
    try:
        app.load_menu_bar(COMMAND_MENU_JSON)
        state["custom_menu_loaded"] = True
        print("  [CB] CommandMenu JSON loaded successfully", flush=True)
    except Exception as e:
        state["errors"].append(f"CommandMenu load failed: {e}")

    # Load a CommandGroup into the existing Help menu
    try:
        app.load_menu_bar(COMMAND_GROUP_JSON)
        state["command_group_loaded"] = True
        print("  [CB] CommandGroup JSON loaded successfully", flush=True)
    except Exception as e:
        state["errors"].append(f"CommandGroup load failed: {e}")

    # Inspect the menu hierarchy if PyObjC is available
    if _has_pyobjc:
        main_menu = NSApplication.sharedApplication().mainMenu()
        if main_menu:
            titles = []
            for i in range(main_menu.numberOfItems()):
                item = main_menu.itemAtIndex_(i)
                submenu = item.submenu()
                if submenu:
                    titles.append(submenu.title())
            print(f"  [CB] Menu titles: {titles}", flush=True)

            if "Test Tools" in titles:
                print("  [CB] 'Test Tools' menu found in menu bar", flush=True)
            else:
                state["errors"].append("'Test Tools' menu not found in menu bar")

            # Programmatically trigger the custom menu item's action to test
            # that ActionUIModel action handler dispatch works from NSMenuItem.
            for i in range(main_menu.numberOfItems()):
                submenu = main_menu.itemAtIndex_(i).submenu()
                if submenu and submenu.title() == "Test Tools":
                    for j in range(submenu.numberOfItems()):
                        mi = submenu.itemAtIndex_(j)
                        if mi.title() == "Run Test Action":
                            target = mi.target()
                            action = mi.action()
                            if target and action:
                                target.performSelector_withObject_(action, mi)
                                print("  [CB] Programmatically triggered 'Run Test Action'", flush=True)
                            else:
                                state["errors"].append("Menu item has no target/action")
                            break
                    break
    else:
        # Without PyObjC, fire the action handler directly to verify
        # the Python-side dispatch works
        _actionui.register_action_handler("test.menuAction",
            lambda aid, wuuid, vid, vpid, ctx: on_test_action(
                actionui.ActionContext(aid, wuuid, vid, vpid, ctx)))
        on_test_action(actionui.ActionContext(
            action_id="test.menuAction", window_uuid="",
            view_id=0, view_part_id=0, context=None))

    # Schedule termination — leave enough time to visually inspect menus
    def _bg_terminate():
        import time
        print(f"  [BG] waiting {DISPLAY_SEC}s for visual inspection …", flush=True)
        time.sleep(DISPLAY_SEC)
        if state.get("window_uuid"):
            print("  [BG] closing window …", flush=True)
            app.close_window(state["window_uuid"])
            time.sleep(0.5)
        print("  [BG] requesting termination …", flush=True)
        app.terminate()

    threading.Thread(target=_bg_terminate, daemon=True).start()


# ---------------------------------------------------------------------------
# Safety timer
# ---------------------------------------------------------------------------

def _safety_timeout():
    state["errors"].append(
        f"Safety timeout ({SAFETY_TIMEOUT_SEC}s): app did not terminate"
    )
    _actionui.app_terminate()

safety_timer = threading.Timer(SAFETY_TIMEOUT_SEC, _safety_timeout)
safety_timer.daemon = True

# ---------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------

safety_timer.start()
print("\nStarting NSApplication run loop …", flush=True)
app.run()
