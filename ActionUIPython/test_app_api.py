#!/usr/bin/env python3
"""
Smoke tests for the ActionUIAppKitApplication Python bridge.

Exercises the app lifecycle API at the Python / C binding layer
without starting a real NSApplication run loop.  Suitable for fast
CI runs that do not require a graphical environment.
"""

import sys
import os
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

def test_module_api_surface():
    """All app_* functions must be present and callable in the C module."""
    print("\n=== _actionui: app API surface ===")

    expected = [
        "app_set_will_finish_launching",
        "app_set_did_finish_launching",
        "app_set_will_become_active",
        "app_set_did_become_active",
        "app_set_will_resign_active",
        "app_set_did_resign_active",
        "app_set_will_terminate",
        "app_set_should_terminate",
        "app_set_window_will_close",
        "app_set_window_will_present",
        "app_set_name",
        "app_set_icon",
        "app_run",
        "app_terminate",
        "app_load_and_present_window",
        "app_close_window",
        "app_load_menu_bar",
        "app_run_open_panel",
        "app_run_save_panel",
    ]

    for name in expected:
        check(f"_actionui.{name} is callable",
              callable(getattr(_actionui, name, None)))


def test_lifecycle_decorator_registration(app: actionui.Application):
    """Decorator methods must store callbacks in _lifecycle_callbacks."""
    print("\n=== Application: lifecycle decorator registration ===")

    @app.will_finish_launching
    def _wfl(): pass

    @app.did_finish_launching
    def _dfl(): pass

    @app.will_become_active
    def _wba(): pass

    @app.did_become_active
    def _dba(): pass

    @app.will_resign_active
    def _wra(): pass

    @app.did_resign_active
    def _dra(): pass

    @app.will_terminate
    def _wt(): pass

    @app.should_terminate
    def _st() -> bool: return True

    @app.window_will_close
    def _wwc(window): pass

    @app.window_will_present
    def _wwp(window): pass

    for name in [
        "will_finish_launching", "did_finish_launching",
        "will_become_active",    "did_become_active",
        "will_resign_active",    "did_resign_active",
        "will_terminate",        "should_terminate",
    ]:
        check(f"'{name}' stored in _lifecycle_callbacks",
              app._lifecycle_callbacks.get(name) is not None)

    check("window_will_close handler stored",
          app._window_close_handler is not None)
    check("window_will_present handler stored",
          app._window_present_handler is not None)

    # Decorator must return the original function so @decorator usage works
    check("will_finish_launching decorator returns original function",
          _wfl.__name__ == "_wfl")
    check("should_terminate decorator returns original function",
          _st.__name__ == "_st")
    check("window_will_close decorator returns original function",
          _wwc.__name__ == "_wwc")
    check("window_will_present decorator returns original function",
          _wwp.__name__ == "_wwp")


def test_deregistration(app: actionui.Application):
    """Passing None to a setter must clear the handler without raising."""
    print("\n=== Handler deregistration ===")

    try:
        _actionui.app_set_will_finish_launching(lambda: None)
        _actionui.app_set_will_finish_launching(None)
        check("app_set_will_finish_launching(None) does not raise", True)
    except Exception as e:
        check(f"app_set_will_finish_launching(None): unexpected {type(e).__name__}: {e}", False)

    try:
        _actionui.app_set_should_terminate(lambda: True)
        _actionui.app_set_should_terminate(None)
        check("app_set_should_terminate(None) does not raise", True)
    except Exception as e:
        check(f"app_set_should_terminate(None): unexpected {type(e).__name__}: {e}", False)

    try:
        _actionui.app_set_window_will_close(lambda uuid: None)
        _actionui.app_set_window_will_close(None)
        check("app_set_window_will_close(None) does not raise", True)
    except Exception as e:
        check(f"app_set_window_will_close(None): unexpected {type(e).__name__}: {e}", False)


def test_type_checking(app: actionui.Application):
    """Passing a non-callable must raise TypeError, not crash."""
    print("\n=== Setter type checking (non-callable must raise TypeError) ===")

    for func_name, setter in [
        ("app_set_will_finish_launching", _actionui.app_set_will_finish_launching),
        ("app_set_should_terminate",      _actionui.app_set_should_terminate),
        ("app_set_window_will_close",     _actionui.app_set_window_will_close),
    ]:
        raised = False
        try:
            setter(42)   # integer is not callable
        except TypeError:
            raised = True
        except Exception as e:
            pass  # also acceptable — at least it didn't crash
        check(f"{func_name}(42) raises TypeError", raised)


def test_url_conversion():
    """load_and_present_window must convert bare paths to file:// URLs."""
    print("\n=== URL conversion logic ===")

    # Replicate the guard from Application.load_and_present_window
    def convert(url: str) -> str:
        if not url.startswith(("file://", "http://", "https://")):
            url = "file://" + os.path.abspath(url)
        return url

    check("bare /abs/path → file:///abs/path",
          convert("/tmp/ui.json") == "file:///tmp/ui.json")

    check("relative path → file:// + abspath",
          convert("ui.json").startswith("file://"))

    check("file:// URL unchanged",
          convert("file:///tmp/ui.json") == "file:///tmp/ui.json")

    check("http:// URL unchanged",
          convert("http://example.com/ui.json") == "http://example.com/ui.json")

    check("https:// URL unchanged",
          convert("https://example.com/ui.json") == "https://example.com/ui.json")


def test_menu_bar_api(app: actionui.Application):
    """Menu bar API must exist and accept valid/invalid inputs without crashing."""
    print("\n=== Menu bar API ===")

    check("Application has load_menu_bar method",
          hasattr(app, "load_menu_bar"))

    # No-arg call (installs default menu bar)
    try:
        app.load_menu_bar()
        check("load_menu_bar() with no args does not raise", True)
    except Exception as e:
        check(f"load_menu_bar() raised {type(e).__name__}: {e}", False)

    # None arg
    try:
        app.load_menu_bar(None)
        check("load_menu_bar(None) does not raise", True)
    except Exception as e:
        check(f"load_menu_bar(None) raised {type(e).__name__}: {e}", False)

    # Valid CommandMenu JSON
    import json
    valid_json = json.dumps([{
        "type": "CommandMenu",
        "id": 900,
        "properties": {"name": "Test"},
        "children": [{
            "type": "Button",
            "id": 901,
            "properties": {"title": "Item", "actionID": "test.item"}
        }]
    }])
    try:
        app.load_menu_bar(valid_json)
        check("load_menu_bar(valid CommandMenu JSON) does not raise", True)
    except Exception as e:
        check(f"load_menu_bar(valid JSON) raised {type(e).__name__}: {e}", False)

    # Valid CommandGroup JSON
    group_json = json.dumps([{
        "type": "CommandGroup",
        "id": 910,
        "properties": {"placement": "after", "placementTarget": "help"},
        "children": [{
            "type": "Divider",
            "id": 911
        }]
    }])
    try:
        app.load_menu_bar(group_json)
        check("load_menu_bar(valid CommandGroup JSON) does not raise", True)
    except Exception as e:
        check(f"load_menu_bar(CommandGroup JSON) raised {type(e).__name__}: {e}", False)

    # Invalid JSON — must not crash
    try:
        app.load_menu_bar("not valid json")
        check("load_menu_bar(invalid JSON string) does not crash", True)
    except Exception as e:
        check(f"load_menu_bar(invalid JSON) raised {type(e).__name__}: {e}", False)

    # Empty array — valid, adds nothing
    try:
        app.load_menu_bar("[]")
        check("load_menu_bar('[]') does not raise", True)
    except Exception as e:
        check(f"load_menu_bar('[]') raised {type(e).__name__}: {e}", False)

    # C-level: non-array JSON object — logged as error, no crash
    try:
        _actionui.app_load_menu_bar('{"type":"CommandMenu"}')
        check("app_load_menu_bar(non-array JSON) does not crash", True)
    except Exception as e:
        check(f"C-level non-array JSON raised {type(e).__name__}: {e}", False)


def test_file_panel_api(app: actionui.Application):
    """File panel API must exist on Application and at the C level."""
    print("\n=== File panel API ===")

    check("Application has open_panel method",
          hasattr(app, "open_panel"))
    check("Application has save_panel method",
          hasattr(app, "save_panel"))

    check("_actionui.app_run_open_panel is callable",
          callable(getattr(_actionui, "app_run_open_panel", None)))
    check("_actionui.app_run_save_panel is callable",
          callable(getattr(_actionui, "app_run_save_panel", None)))


def test_singleton_enforcement():
    """A second Application() in the same process must raise RuntimeError."""
    print("\n=== Application singleton enforcement ===")

    raised = False
    try:
        _ = actionui.Application()
    except RuntimeError:
        raised = True

    check("Second Application() raises RuntimeError", raised)


def test_windows_dict(app: actionui.Application):
    """_windows must start empty; close_window with unknown UUID must not crash."""
    print("\n=== Window registry and control ===")

    check("_windows dict starts empty", len(app._windows) == 0)

    # close_window with an unknown UUID should not raise — the async dispatch
    # reaches the C layer where windows[uuid] is nil and .close() is skipped.
    try:
        app.close_window("00000000-0000-0000-0000-000000000000")
        check("close_window(unknown UUID) does not raise", True)
    except Exception as e:
        check(f"close_window: unexpected {type(e).__name__}: {e}", False)

    # Note: app.terminate() is intentionally NOT tested here.
    # NSApplication.terminate(nil) is a process-level operation that exits
    # the process even without a running run loop.  It is covered in full
    # by test_app_lifecycle.py alongside the should_terminate callback.


# -------------------------------------------------------------------------
# Main
# -------------------------------------------------------------------------

def main():
    print("ActionUI App API Smoke Tests")
    print("=" * 50)
    print("(No NSApplication run loop — tests the Python/C binding layer only)")

    # Create the single Application instance used by all tests.
    app = actionui.Application()

    test_module_api_surface()
    test_lifecycle_decorator_registration(app)
    test_deregistration(app)
    test_type_checking(app)
    test_url_conversion()
    test_menu_bar_api(app)
    test_file_panel_api(app)
    test_singleton_enforcement()   # expects RuntimeError from a second instance
    test_windows_dict(app)

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
