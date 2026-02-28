#!/usr/bin/env python3
"""
Integration tests for ActionUIAppKitApplication lifecycle callbacks.

Starts a real NSApplication run loop, exercises all major lifecycle and window
management callbacks, and terminates automatically.

Requirements
------------
- Must run in a graphical macOS environment (attached screen / window server).
- The Python process must start on the main thread (standard script entry).
- The _actionui extension must be built and installed (pip install .).

Usage
-----
    python3 test_app_lifecycle.py

Design note
-----------
NSApplication.terminate() calls C exit() directly — app.run() never returns.
All assertions are therefore registered via Python's atexit module, which
fires its callbacks even during a C-level exit().  If any assertion fails,
the atexit handler calls os._exit(1) to override the exit code.
"""

import sys
import os
import atexit
import threading
import actionui

# ---------------------------------------------------------------------------
# Fixture
# ---------------------------------------------------------------------------

_HERE = os.path.dirname(os.path.abspath(__file__))
FIXTURE_JSON = os.path.normpath(os.path.join(
    _HERE, "..", "ActionUIObjCTestApp", "DefaultWindowContentView.json"
))

SAFETY_TIMEOUT_SEC = 15.0
WINDOW_DISPLAY_SEC = 1.0

# ---------------------------------------------------------------------------
# Shared state — written from callbacks, read in the atexit handler
# ---------------------------------------------------------------------------

state = {
    "will_finish_launching":    False,
    "did_finish_launching":     False,
    "will_become_active":       False,
    "did_become_active":        False,
    "will_terminate":           False,
    "should_terminate_called":  False,
    "should_terminate_result":  None,
    "window_opened_uuid":       None,
    "window_present_uuid":      None,
    "window_closed_uuid":       None,
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

    print("Lifecycle callbacks:", flush=True)
    check("will_finish_launching fired",    state["will_finish_launching"])
    check("did_finish_launching fired",     state["did_finish_launching"])
    check("will_become_active fired",       state["will_become_active"])
    check("did_become_active fired",        state["did_become_active"])
    check("should_terminate was called",    state["should_terminate_called"])
    check("should_terminate returned True", state["should_terminate_result"] is True)
    check("will_terminate fired",           state["will_terminate"])

    print(flush=True)
    print("Window lifecycle:", flush=True)
    check("window was opened (UUID recorded)",
          state["window_opened_uuid"] is not None)
    check("window_will_present fired",
          state["window_present_uuid"] is not None)
    if state["window_present_uuid"] and state["window_opened_uuid"]:
        check("window_will_present UUID matches opened UUID",
              state["window_present_uuid"] == state["window_opened_uuid"])
    check("window_will_close fired",
          state["window_closed_uuid"] is not None)
    if state["window_opened_uuid"] and state["window_closed_uuid"]:
        check("window_will_close UUID matches opened UUID",
              state["window_closed_uuid"] == state["window_opened_uuid"])


    print(flush=True)
    print("Window registry cleanup:", flush=True)
    check("_windows dict is empty after window closes",
          len(app._windows) == 0)

    print(flush=True)
    print("=" * 50, flush=True)
    all_bad = _failures + state["errors"]
    if all_bad:
        print(f"FAILED — {len(all_bad)} issue(s):", flush=True)
        for item in all_bad:
            print(f"  - {item}", flush=True)
        os._exit(1)   # override the exit(0) from NSApplication.terminate()
    else:
        print(f"All {_check_count} lifecycle integration checks PASSED.", flush=True)


# ---------------------------------------------------------------------------
# Application + lifecycle handlers
# ---------------------------------------------------------------------------

print("ActionUI App Lifecycle Integration Test", flush=True)
print("=" * 50, flush=True)

if not os.path.exists(FIXTURE_JSON):
    print(f"ERROR: fixture not found: {FIXTURE_JSON}", file=sys.stderr)
    sys.exit(1)

print(f"Fixture : {FIXTURE_JSON}", flush=True)
print(f"Timeout : {SAFETY_TIMEOUT_SEC}s", flush=True)
print(flush=True)

app = actionui.Application()


@app.will_finish_launching
def _will_finish():
    state["will_finish_launching"] = True
    print("  [CB] will_finish_launching", flush=True)


@app.did_finish_launching
def _did_finish():
    state["did_finish_launching"] = True
    print("  [CB] did_finish_launching", flush=True)

    if not os.path.exists(FIXTURE_JSON):
        state["errors"].append(f"Fixture disappeared: {FIXTURE_JSON}")
        app.terminate()
        return

    window = app.load_and_present_window(FIXTURE_JSON, title="ActionUI Lifecycle Test")
    state["window_opened_uuid"] = window.uuid
    print(f"  [CB] window opened: {window.uuid}", flush=True)

    def _bg_sequence():
        import time
        time.sleep(WINDOW_DISPLAY_SEC)
        print("  [BG] closing window …", flush=True)
        app.close_window(window.uuid)
        time.sleep(0.5)
        print("  [BG] requesting termination …", flush=True)
        app.terminate()

    threading.Thread(target=_bg_sequence, daemon=True).start()


@app.will_become_active
def _will_become_active():
    state["will_become_active"] = True
    print("  [CB] will_become_active", flush=True)


@app.did_become_active
def _did_become_active():
    state["did_become_active"] = True
    print("  [CB] did_become_active", flush=True)


@app.window_will_present
def _window_will_present(window: actionui.Window):
    state["window_present_uuid"] = window.uuid
    print(f"  [CB] window_will_present: {window.uuid}", flush=True)
    window.set_string(1, "Hello from Python!")
    print("  [CB] view 1 ← 'Hello from Python!'", flush=True)


@app.window_will_close
def _window_will_close(window: actionui.Window):
    state["window_closed_uuid"] = window.uuid
    print(f"  [CB] window_will_close: {window.uuid}", flush=True)


@app.should_terminate
def _should_terminate() -> bool:
    state["should_terminate_called"] = True
    state["should_terminate_result"] = True
    print("  [CB] should_terminate → True", flush=True)
    return True


@app.will_terminate
def _will_terminate():
    state["will_terminate"] = True
    print("  [CB] will_terminate", flush=True)


# ---------------------------------------------------------------------------
# Safety timer
# ---------------------------------------------------------------------------

def _safety_timeout():
    state["errors"].append(
        f"Safety timeout ({SAFETY_TIMEOUT_SEC}s): app did not terminate"
    )
    import _actionui
    _actionui.app_terminate()

safety_timer = threading.Timer(SAFETY_TIMEOUT_SEC, _safety_timeout)
safety_timer.daemon = True

# ---------------------------------------------------------------------------
# Run — NSApplication.terminate() will call exit(); atexit handler reports
# ---------------------------------------------------------------------------

safety_timer.start()
print("Starting NSApplication run loop …", flush=True)
app.run()
# This line is never reached — NSApplication.terminate() calls exit() directly.
