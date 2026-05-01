#!/usr/bin/env python3
"""
Smoke tests for the runtime structural mutations Python bridge.

Exercises insert_element, insert_row, remove_element at both the C extension
(_actionui) and high-level (actionui.Window) layers without a live NSApplication
run loop. No UI is displayed — these tests verify API surface, type correctness,
and that unknown UUIDs produce the expected errors without crashing.

Run: python3 test_insert_api.py
"""

import sys
import json
import inspect
import _actionui
import actionui

# ---------------------------------------------------------------------------
# Simple pass/fail harness
# ---------------------------------------------------------------------------

_failures = []

def check(label: str, condition: bool) -> bool:
    status = "PASS" if condition else "FAIL"
    print(f"  [{status}] {label}")
    if not condition:
        _failures.append(label)
    return condition


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

_FAKE_UUID = "00000000-0000-0000-0000-000000000000"
_VALID_ELEMENT_JSON = '{"type":"Text","properties":{"text":"hello"}}'
_VALID_CELLS_JSON   = '[{"type":"Text","properties":{"text":"C0"}},{"type":"Text","properties":{"text":"C1"}}]'


def test_c_api_surface():
    """All three mutation functions must be present and callable in _actionui."""
    print("\n=== _actionui: structural mutation API surface ===")

    for name in ("insert_element", "insert_row", "remove_element"):
        check(f"_actionui.{name} is callable",
              callable(getattr(_actionui, name, None)))


def test_window_method_surface():
    """Window must expose insert_element, insert_row, remove_element."""
    print("\n=== Window: structural mutation method surface ===")

    W = actionui.Window
    for name in ("insert_element", "insert_row", "remove_element"):
        check(f"Window has method '{name}'",
              callable(getattr(W, name, None)))


def test_insert_element_signatures():
    """insert_element / insert_row / remove_element must have the expected parameters."""
    print("\n=== Window: method signatures ===")

    W = actionui.Window

    sig = inspect.signature(W.insert_element)
    params = list(sig.parameters.keys())
    check("insert_element has 'parent_id'",       "parent_id" in params)
    check("insert_element has 'element'",         "element" in params)
    check("insert_element has 'container'",            "container" in params)
    check("insert_element has 'position'",        "position" in params)
    check("insert_element has 'position_param'",  "position_param" in params)

    sig = inspect.signature(W.insert_row)
    params = list(sig.parameters.keys())
    check("insert_row has 'parent_id'",        "parent_id" in params)
    check("insert_row has 'cells'",            "cells" in params)
    check("insert_row has 'container'",             "container" in params)
    check("insert_row has 'position'",         "position" in params)
    check("insert_row has 'position_index'",   "position_index" in params)

    sig = inspect.signature(W.remove_element)
    params = list(sig.parameters.keys())
    check("remove_element has 'view_id'",  "view_id" in params)


def test_insert_element_unknown_uuid():
    """insert_element on an unknown UUID must raise RuntimeError."""
    print("\n=== insert_element: unknown UUID raises RuntimeError ===")

    # C layer
    try:
        _actionui.insert_element(_FAKE_UUID, 1, _VALID_ELEMENT_JSON)
        check("_actionui.insert_element(unknown UUID) raised RuntimeError", False)
    except RuntimeError:
        check("_actionui.insert_element(unknown UUID) raises RuntimeError", True)
    except Exception as e:
        check(f"_actionui.insert_element raised unexpected {type(e).__name__}: {e}", False)

    # Python wrapper
    win = actionui.Window(_FAKE_UUID)
    try:
        win.insert_element(1, _VALID_ELEMENT_JSON)
        check("Window.insert_element(unknown UUID) raised RuntimeError", False)
    except RuntimeError:
        check("Window.insert_element(unknown UUID) raises RuntimeError", True)
    except Exception as e:
        check(f"Window.insert_element raised unexpected {type(e).__name__}: {e}", False)


def test_insert_element_dict_input():
    """Window.insert_element must accept a dict and convert it to JSON."""
    print("\n=== insert_element: dict input coerced to JSON ===")

    win = actionui.Window(_FAKE_UUID)
    element_dict = {"type": "Text", "properties": {"text": "hello"}}

    try:
        win.insert_element(1, element_dict)
        # On unknown UUID this raises RuntimeError — the dict path still ran
        check("insert_element(dict) coerced to JSON (RuntimeError from unknown UUID)", False)
    except RuntimeError:
        check("insert_element(dict) coerced to JSON (RuntimeError from unknown UUID)", True)
    except TypeError as e:
        check(f"insert_element(dict) raised TypeError (dict not serialised): {e}", False)


def test_insert_row_unknown_uuid():
    """insert_row on an unknown UUID must raise RuntimeError."""
    print("\n=== insert_row: unknown UUID raises RuntimeError ===")

    # C layer
    try:
        _actionui.insert_row(_FAKE_UUID, 2, _VALID_CELLS_JSON)
        check("_actionui.insert_row(unknown UUID) raised RuntimeError", False)
    except RuntimeError:
        check("_actionui.insert_row(unknown UUID) raises RuntimeError", True)
    except Exception as e:
        check(f"_actionui.insert_row raised unexpected {type(e).__name__}: {e}", False)

    # Python wrapper
    win = actionui.Window(_FAKE_UUID)
    try:
        win.insert_row(2, _VALID_CELLS_JSON)
        check("Window.insert_row(unknown UUID) raised RuntimeError", False)
    except RuntimeError:
        check("Window.insert_row(unknown UUID) raises RuntimeError", True)
    except Exception as e:
        check(f"Window.insert_row raised unexpected {type(e).__name__}: {e}", False)


def test_insert_row_list_input():
    """Window.insert_row must accept a list of dicts and convert to JSON."""
    print("\n=== insert_row: list input coerced to JSON ===")

    win = actionui.Window(_FAKE_UUID)
    cells = [
        {"type": "Text", "properties": {"text": "C0"}},
        {"type": "Text", "properties": {"text": "C1"}},
    ]

    try:
        win.insert_row(2, cells)
        check("insert_row(list) coerced to JSON (RuntimeError from unknown UUID)", False)
    except RuntimeError:
        check("insert_row(list) coerced to JSON (RuntimeError from unknown UUID)", True)
    except TypeError as e:
        check(f"insert_row(list) raised TypeError (list not serialised): {e}", False)


def test_remove_element_unknown_uuid():
    """remove_element on an unknown UUID must raise RuntimeError."""
    print("\n=== remove_element: unknown UUID raises RuntimeError ===")

    # C layer
    try:
        _actionui.remove_element(_FAKE_UUID, 10)
        check("_actionui.remove_element(unknown UUID) raised RuntimeError", False)
    except RuntimeError:
        check("_actionui.remove_element(unknown UUID) raises RuntimeError", True)
    except Exception as e:
        check(f"_actionui.remove_element raised unexpected {type(e).__name__}: {e}", False)

    # Python wrapper
    win = actionui.Window(_FAKE_UUID)
    try:
        win.remove_element(10)
        check("Window.remove_element(unknown UUID) raised RuntimeError", False)
    except RuntimeError:
        check("Window.remove_element(unknown UUID) raises RuntimeError", True)
    except Exception as e:
        check(f"Window.remove_element raised unexpected {type(e).__name__}: {e}", False)


def test_position_defaults():
    """Position defaults (append=0) must flow through without TypeError."""
    print("\n=== insert_element: optional args default to 0/None ===")

    win = actionui.Window(_FAKE_UUID)

    # All optional args omitted — must not raise TypeError, only RuntimeError (unknown UUID)
    for call_desc, kwargs in [
        ("no container/position",          {}),
        ("container=None",                 {"container": None}),
        ("container='children'",           {"container": "children"}),
        ("position=PREPEND",      {"position": actionui.InsertPosition.PREPEND}),
        ("position=AT, param=0",  {"position": actionui.InsertPosition.AT, "position_param": 0}),
        ("position=BEFORE, param=9", {"position": actionui.InsertPosition.BEFORE, "position_param": 9}),
        ("position=AFTER, param=9",  {"position": actionui.InsertPosition.AFTER, "position_param": 9}),
    ]:
        try:
            win.insert_element(1, _VALID_ELEMENT_JSON, **kwargs)
            check(f"insert_element({call_desc}) raised RuntimeError", False)
        except RuntimeError:
            check(f"insert_element({call_desc}) raises RuntimeError (not TypeError)", True)
        except TypeError as e:
            check(f"insert_element({call_desc}) raised TypeError (bad default): {e}", False)


def test_insert_row_position_defaults():
    """insert_row position defaults must flow through without TypeError."""
    print("\n=== insert_row: optional args default to 0/None ===")

    win = actionui.Window(_FAKE_UUID)

    for call_desc, kwargs in [
        ("no container/position",       {}),
        ("position=PREPEND",   {"position": actionui.InsertPosition.PREPEND}),
        ("position=AT, index=0",    {"position": actionui.InsertPosition.AT, "position_index": 0}),
    ]:
        try:
            win.insert_row(2, _VALID_CELLS_JSON, **kwargs)
            check(f"insert_row({call_desc}) raised RuntimeError", False)
        except RuntimeError:
            check(f"insert_row({call_desc}) raises RuntimeError (not TypeError)", True)
        except TypeError as e:
            check(f"insert_row({call_desc}) raised TypeError (bad default): {e}", False)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    print("ActionUI Structural Mutation API Smoke Tests")
    print("=" * 55)
    print("(No NSApplication run loop — tests the C extension binding layer only)")

    # Ensure an Application instance exists (required by Window constructor path)
    if actionui.Application.instance() is None:
        actionui.Application()

    test_c_api_surface()
    test_window_method_surface()
    test_insert_element_signatures()
    test_insert_element_unknown_uuid()
    test_insert_element_dict_input()
    test_insert_row_unknown_uuid()
    test_insert_row_list_input()
    test_remove_element_unknown_uuid()
    test_position_defaults()
    test_insert_row_position_defaults()

    print("\n" + "=" * 55)
    if not _failures:
        print("All checks PASSED.")
        sys.exit(0)
    else:
        print(f"FAILED — {len(_failures)} check(s):")
        for f in _failures:
            print(f"  - {f}")
        sys.exit(1)
