#!/usr/bin/env python3
"""
Tests for scalar action context handling.

Verifies that the Python action bridge correctly receives and parses
scalar JSON fragments (strings, integers, floats, booleans) that
ActionUI views pass as action context.  These context values are
serialised by safeJSONString() in the Swift C adapter layer.

Before the fix in ActionUIC.swift, bare scalars passed to
JSONSerialization.data(withJSONObject:) caused an ObjC NSException
(not a Swift Error), crashing the host process.  The fix routes
scalars through manual serialisation so they arrive at Python as
valid JSON fragments.

Context types triggered by ActionUI views:
  - Picker actionID:          String  (selected tag)
  - Table button "title":     String  (cell text)
  - Table button "rowIndex":  Int     (row number)
  - Table button "columnIndex": Int   (column number)
  - List button default:      String  (item text)
  - List button "rowIndex":   Int     (row index)
  - Table/List doubleClick:   String or Int
  - View openURLActionID:     String  (URL as string after fix)
"""

import sys
import actionui

# -------------------------------------------------------------------------
# Simple pass/fail harness (matches test_app_api.py style)
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

def test_action_bridge_string_context(app: actionui.Application):
    """Picker and Table/List pass String context (e.g. selected tag)."""
    print("\n=== Action bridge: String context ===")

    received = {}

    @app.action("test.string.ctx")
    def handler(ctx: actionui.ActionContext):
        received["ctx"] = ctx

    # Simulate what safeJSONString produces for a String: a JSON string
    # e.g. "\"option_1\""
    app._action_bridge("test.string.ctx", "test-window", 1, 0, '"option_1"')
    check("String context received", "ctx" in received)
    check("String context value is 'option_1'",
          received.get("ctx") and received["ctx"].context == "option_1")
    check("String context type is str",
          isinstance(received.get("ctx", None) and received["ctx"].context, str))


def test_action_bridge_int_context(app: actionui.Application):
    """Table/List button with rowIndex passes Int context."""
    print("\n=== Action bridge: Int context ===")

    received = {}

    @app.action("test.int.ctx")
    def handler(ctx: actionui.ActionContext):
        received["ctx"] = ctx

    # safeJSONString produces bare "42" for Int
    app._action_bridge("test.int.ctx", "test-window", 10, 0, "42")
    check("Int context received", "ctx" in received)
    check("Int context value is 42",
          received.get("ctx") and received["ctx"].context == 42)
    check("Int context type is int",
          isinstance(received.get("ctx", None) and received["ctx"].context, int))


def test_action_bridge_float_context(app: actionui.Application):
    """Double/Float scalar context (e.g. from a custom view)."""
    print("\n=== Action bridge: Float context ===")

    received = {}

    @app.action("test.float.ctx")
    def handler(ctx: actionui.ActionContext):
        received["ctx"] = ctx

    # safeJSONString produces bare "3.14" for Double
    app._action_bridge("test.float.ctx", "test-window", 10, 0, "3.14")
    check("Float context received", "ctx" in received)
    check("Float context value is 3.14",
          received.get("ctx") and received["ctx"].context == 3.14)


def test_action_bridge_bool_context(app: actionui.Application):
    """Boolean scalar context."""
    print("\n=== Action bridge: Bool context ===")

    received = {}

    @app.action("test.bool.true.ctx")
    def handler_true(ctx: actionui.ActionContext):
        received["true"] = ctx

    @app.action("test.bool.false.ctx")
    def handler_false(ctx: actionui.ActionContext):
        received["false"] = ctx

    # safeJSONString produces "true" / "false" for Bool
    app._action_bridge("test.bool.true.ctx", "test-window", 10, 0, "true")
    app._action_bridge("test.bool.false.ctx", "test-window", 10, 0, "false")
    check("Bool true context received", "true" in received)
    check("Bool true context value is True",
          received.get("true") and received["true"].context is True)
    check("Bool false context received", "false" in received)
    check("Bool false context value is False",
          received.get("false") and received["false"].context is False)


def test_action_bridge_null_context(app: actionui.Application):
    """Slider/Toggle valueChangeActionID passes no context (None)."""
    print("\n=== Action bridge: None context ===")

    received = {}

    @app.action("test.null.ctx")
    def handler(ctx: actionui.ActionContext):
        received["ctx"] = ctx

    app._action_bridge("test.null.ctx", "test-window", 71, 0, None)
    check("None context received", "ctx" in received)
    check("None context value is None",
          received.get("ctx") and received["ctx"].context is None)


def test_action_bridge_dict_context(app: actionui.Application):
    """Table button with rowColumnIndex passes a dict context."""
    print("\n=== Action bridge: Dict context ===")

    received = {}

    @app.action("test.dict.ctx")
    def handler(ctx: actionui.ActionContext):
        received["ctx"] = ctx

    # safeJSONString passes dicts through JSONSerialization normally
    app._action_bridge("test.dict.ctx", "test-window", 10, 0,
                       '{"row":2,"column":1}')
    check("Dict context received", "ctx" in received)
    ctx = received.get("ctx")
    check("Dict context has row=2",
          ctx and isinstance(ctx.context, dict) and ctx.context.get("row") == 2)
    check("Dict context has column=1",
          ctx and isinstance(ctx.context, dict) and ctx.context.get("column") == 1)


def test_action_bridge_array_context(app: actionui.Application):
    """Array context (e.g. Table selected row value)."""
    print("\n=== Action bridge: Array context ===")

    received = {}

    @app.action("test.array.ctx")
    def handler(ctx: actionui.ActionContext):
        received["ctx"] = ctx

    app._action_bridge("test.array.ctx", "test-window", 10, 0,
                       '["cell1","cell2","cell3"]')
    check("Array context received", "ctx" in received)
    ctx = received.get("ctx")
    check("Array context is list",
          ctx and isinstance(ctx.context, list))
    check("Array context has 3 elements",
          ctx and len(ctx.context) == 3)
    check("Array context values correct",
          ctx and ctx.context == ["cell1", "cell2", "cell3"])


def test_action_bridge_string_with_special_chars(app: actionui.Application):
    """String context with characters that need JSON escaping."""
    print("\n=== Action bridge: String with special characters ===")

    received = {}

    @app.action("test.special.ctx")
    def handler(ctx: actionui.ActionContext):
        received["ctx"] = ctx

    # JSON-escaped string with quotes and backslash
    app._action_bridge("test.special.ctx", "test-window", 1, 0,
                       '"hello \\"world\\" \\\\path"')
    check("Special char context received", "ctx" in received)
    ctx = received.get("ctx")
    check("Special char context correctly unescaped",
          ctx and ctx.context == 'hello "world" \\path')


def test_action_bridge_invalid_json_context(app: actionui.Application):
    """If safeJSONString somehow produces invalid JSON, Python must not crash."""
    print("\n=== Action bridge: Invalid JSON fallback ===")

    received = {}

    @app.action("test.invalid.ctx")
    def handler(ctx: actionui.ActionContext):
        received["ctx"] = ctx

    # Pass something that's not valid JSON — _action_bridge falls back to
    # storing the raw string (see actionui.py line 123-124)
    app._action_bridge("test.invalid.ctx", "test-window", 1, 0,
                       "not valid json {{{")
    check("Invalid JSON context received without crash", "ctx" in received)
    ctx = received.get("ctx")
    check("Invalid JSON stored as raw string",
          ctx and ctx.context == "not valid json {{{")


def test_action_bridge_preserves_metadata(app: actionui.Application):
    """Verify view_id and view_part_id are forwarded correctly."""
    print("\n=== Action bridge: metadata forwarding ===")

    received = {}

    @app.action("test.meta.ctx")
    def handler(ctx: actionui.ActionContext):
        received["ctx"] = ctx

    app._action_bridge("test.meta.ctx", "window-ABC", 42, 3, '"tag"')
    ctx = received.get("ctx")
    check("action_id forwarded", ctx and ctx.action_id == "test.meta.ctx")
    check("window_uuid forwarded", ctx and ctx.window_uuid == "window-ABC")
    check("view_id forwarded", ctx and ctx.view_id == 42)
    check("view_part_id forwarded", ctx and ctx.view_part_id == 3)
    check("context forwarded", ctx and ctx.context == "tag")


# -------------------------------------------------------------------------
# Main
# -------------------------------------------------------------------------

def main():
    print("ActionUI Scalar Context Handling Tests")
    print("=" * 50)
    print("Tests that scalar JSON fragments from Picker, Table, List, etc.")
    print("are correctly handled by the Python action bridge.")

    app = actionui.Application()

    test_action_bridge_string_context(app)
    test_action_bridge_int_context(app)
    test_action_bridge_float_context(app)
    test_action_bridge_bool_context(app)
    test_action_bridge_null_context(app)
    test_action_bridge_dict_context(app)
    test_action_bridge_array_context(app)
    test_action_bridge_string_with_special_chars(app)
    test_action_bridge_invalid_json_context(app)
    test_action_bridge_preserves_metadata(app)

    print()
    print("=" * 50)
    if _failures:
        print(f"FAILED — {len(_failures)} assertion(s):")
        for f in _failures:
            print(f"  - {f}")
        sys.exit(1)
    else:
        count = sum(1 for line in open(__file__) if "check(" in line
                    and not line.strip().startswith(("#", "def")))
        print(f"All {count} checks PASSED.")


if __name__ == "__main__":
    main()
