#!/usr/bin/env python3
"""
Smoke tests for NSOpenPanel / NSSavePanel Python bridge.

Exercises the file panel API at the Python / C binding layer without
starting a real NSApplication run loop.  Panels are not displayed —
these tests verify that the functions exist, handle edge cases
gracefully, and don't crash on invalid input.
"""

import sys
import json
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
    """app_run_open_panel and app_run_save_panel must be callable."""
    print("\n=== _actionui: file panel API surface ===")

    check("app_run_open_panel exists and is callable",
          callable(getattr(_actionui, "app_run_open_panel", None)))

    check("app_run_save_panel exists and is callable",
          callable(getattr(_actionui, "app_run_save_panel", None)))


def test_none_config():
    """Passing None (no config) must not crash.

    Without a run loop the panel can't actually display, so the function
    may return None (cancelled) or raise — either is acceptable as long
    as it doesn't segfault.
    """
    print("\n=== None config (no crash) ===")

    try:
        result = _actionui.app_run_open_panel()
        check("app_run_open_panel() with no args does not crash", True)
        check("app_run_open_panel() returns None or str",
              result is None or isinstance(result, str))
    except Exception as e:
        # Some environments may raise; that's fine — no crash is the goal
        check(f"app_run_open_panel() raised {type(e).__name__} (no crash)", True)

    try:
        result = _actionui.app_run_save_panel()
        check("app_run_save_panel() with no args does not crash", True)
        check("app_run_save_panel() returns None or str",
              result is None or isinstance(result, str))
    except Exception as e:
        check(f"app_run_save_panel() raised {type(e).__name__} (no crash)", True)


def test_invalid_json():
    """Invalid JSON config must not crash."""
    print("\n=== Invalid JSON config (no crash) ===")

    try:
        result = _actionui.app_run_open_panel("not valid json")
        check("app_run_open_panel(invalid JSON) does not crash", True)
    except Exception as e:
        check(f"app_run_open_panel(invalid JSON) raised {type(e).__name__} (no crash)", True)

    try:
        result = _actionui.app_run_save_panel("{bad")
        check("app_run_save_panel(invalid JSON) does not crash", True)
    except Exception as e:
        check(f"app_run_save_panel(invalid JSON) raised {type(e).__name__} (no crash)", True)


def test_empty_config():
    """Empty JSON object config must not crash."""
    print("\n=== Empty config object (no crash) ===")

    try:
        result = _actionui.app_run_open_panel("{}")
        check("app_run_open_panel('{}') does not crash", True)
    except Exception as e:
        check(f"app_run_open_panel('{{}}') raised {type(e).__name__} (no crash)", True)

    try:
        result = _actionui.app_run_save_panel("{}")
        check("app_run_save_panel('{}') does not crash", True)
    except Exception as e:
        check(f"app_run_save_panel('{{}}') raised {type(e).__name__} (no crash)", True)


def test_full_config():
    """A fully populated config must not crash."""
    print("\n=== Full config (no crash) ===")

    open_config = json.dumps({
        "title": "Test Open",
        "prompt": "Select",
        "message": "Pick files",
        "identifier": "com.test.open",
        "allowedContentTypes": ["json", "txt", "public.image"],
        "allowsMultipleSelection": True,
        "canChooseDirectories": False,
        "canChooseFiles": True,
        "directoryURL": "/tmp",
        "showsHiddenFiles": True,
        "treatsFilePackagesAsDirectories": False,
        "canCreateDirectories": True,
        "allowsOtherFileTypes": False,
    })

    try:
        result = _actionui.app_run_open_panel(open_config)
        check("app_run_open_panel(full config) does not crash", True)
    except Exception as e:
        check(f"app_run_open_panel(full config) raised {type(e).__name__} (no crash)", True)

    save_config = json.dumps({
        "title": "Test Save",
        "prompt": "Save",
        "message": "Choose location",
        "identifier": "com.test.save",
        "allowedContentTypes": ["json"],
        "nameFieldStringValue": "test.json",
        "directoryURL": "/tmp",
        "showsHiddenFiles": False,
        "treatsFilePackagesAsDirectories": False,
        "canCreateDirectories": True,
        "allowsOtherFileTypes": False,
    })

    try:
        result = _actionui.app_run_save_panel(save_config)
        check("app_run_save_panel(full config) does not crash", True)
    except Exception as e:
        check(f"app_run_save_panel(full config) raised {type(e).__name__} (no crash)", True)


def test_python_api_exists():
    """Application.open_panel and save_panel must exist with correct signatures."""
    print("\n=== Python API surface ===")

    app = actionui.Application.instance()

    check("Application has open_panel method",
          hasattr(app, "open_panel") and callable(app.open_panel))

    check("Application has save_panel method",
          hasattr(app, "save_panel") and callable(app.save_panel))

    # Verify keyword-only arguments via inspect
    import inspect
    open_sig = inspect.signature(app.open_panel)
    save_sig = inspect.signature(app.save_panel)

    open_params = list(open_sig.parameters.keys())
    save_params = list(save_sig.parameters.keys())

    check("open_panel has 'title' parameter",
          "title" in open_params)
    check("open_panel has 'allowed_types' parameter",
          "allowed_types" in open_params)
    check("open_panel has 'allows_multiple' parameter",
          "allows_multiple" in open_params)
    check("open_panel has 'can_choose_directories' parameter",
          "can_choose_directories" in open_params)

    check("save_panel has 'title' parameter",
          "title" in save_params)
    check("save_panel has 'filename' parameter",
          "filename" in save_params)
    check("save_panel has 'allowed_types' parameter",
          "allowed_types" in save_params)

    # All parameters must be keyword-only
    for name, param in open_sig.parameters.items():
        check(f"open_panel.{name} is keyword-only",
              param.kind == inspect.Parameter.KEYWORD_ONLY)

    for name, param in save_sig.parameters.items():
        check(f"save_panel.{name} is keyword-only",
              param.kind == inspect.Parameter.KEYWORD_ONLY)


def test_build_panel_config():
    """_build_panel_config must produce correct JSON config dicts."""
    print("\n=== _build_panel_config helper ===")

    build = actionui.Application._build_panel_config

    # Empty call → empty dict
    check("no args → empty dict", build() == {})

    # Title only
    cfg = build(title="Hello")
    check("title='Hello' → {'title': 'Hello'}",
          cfg == {"title": "Hello"})

    # allowed_types
    cfg = build(allowed_types=["json", "txt"])
    check("allowed_types maps to allowedContentTypes",
          cfg.get("allowedContentTypes") == ["json", "txt"])

    # directory
    cfg = build(directory="/tmp")
    check("directory maps to directoryURL",
          cfg.get("directoryURL") == "/tmp")

    # Boolean flags — only non-default values should appear
    cfg = build(shows_hidden_files=True)
    check("shows_hidden_files=True → showsHiddenFiles: true",
          cfg.get("showsHiddenFiles") is True)

    cfg = build(shows_hidden_files=False)
    check("shows_hidden_files=False → key absent",
          "showsHiddenFiles" not in cfg)

    cfg = build(can_create_directories=False)
    check("can_create_directories=False → canCreateDirectories: false",
          cfg.get("canCreateDirectories") is False)

    cfg = build(can_create_directories=True)
    check("can_create_directories=True (default) → key absent",
          "canCreateDirectories" not in cfg)


# -------------------------------------------------------------------------
# Main
# -------------------------------------------------------------------------

def main():
    print("ActionUI File Panel Smoke Tests")
    print("=" * 50)
    print("(No panel display — tests the API surface and edge cases only)")

    # Ensure an Application exists (may already exist from prior import)
    if actionui.Application.instance() is None:
        actionui.Application()

    test_c_api_surface()
    test_none_config()
    test_invalid_json()
    test_empty_config()
    test_full_config()
    test_python_api_exists()
    test_build_panel_config()

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
