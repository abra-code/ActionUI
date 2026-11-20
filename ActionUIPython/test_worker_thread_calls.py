#!/usr/bin/env python3
"""
Calls from a worker thread while the app runs.

1. A call must not deadlock. The worker asks for a value of a window that does not exist. The
   library does that work on the main thread, which logs a warning, and the log reaches Python
   through the logger bridge, which needs the interpreter lock (GIL). The extension used to hold
   the GIL across the wait for the main thread, so the two waited on each other for good. The
   child process here must finish within the timeout.
2. Calls that store a callback (handlers, the logger, lifecycle setters) are refused with
   RuntimeError off the main thread, as in the Node and Rust bindings: the C handler tables are
   read on the main thread without a lock.
3. insert_row from the worker returns the cells' ids with their sign: a cell without an id of its
   own gets an automatic negative one, which the parser used to return as positive.

Needs a graphical login session (it runs the application). Run with: python3 test_worker_thread_calls.py
"""

import json
import os
import subprocess
import sys
import tempfile

CHILD = r"""
import sys, threading
sys.path.insert(0, sys.argv[1])
import _actionui
_actionui.set_logger(lambda message, level: None)
GRID_URL = sys.argv[2]

def handler(*args):
    pass

GUARDED = [
    ("set_logger", (handler,)),
    ("register_action_handler", ("worker.action", handler)),
    ("unregister_action_handler", ("worker.action",)),
    ("set_default_action_handler", (handler,)),
    ("app_set_will_finish_launching", (handler,)),
    ("app_set_did_finish_launching", (handler,)),
    ("app_set_will_become_active", (handler,)),
    ("app_set_did_become_active", (handler,)),
    ("app_set_will_resign_active", (handler,)),
    ("app_set_did_resign_active", (handler,)),
    ("app_set_will_terminate", (handler,)),
    ("app_set_should_terminate", (handler,)),
    ("app_set_window_will_close", (handler,)),
    ("app_set_window_will_present", (handler,)),
]

def worker():
    # Ends the app whatever happens, so a failure here is not reported as a deadlock.
    try:
        checks()
    finally:
        _actionui.app_terminate()

def checks():
    value = _actionui.get_string_value("no-such-window", 1, 0)
    print("worker returned", value, flush=True)
    for name, args in GUARDED:
        try:
            getattr(_actionui, name)(*args)
            print("NOT REFUSED", name, flush=True)
        except RuntimeError as error:
            if "main thread" not in str(error):
                print("WRONG ERROR", name, error, flush=True)
    print("guards checked", flush=True)
    cells = '[{"type": "Text", "properties": {"text": "x"}}, {"type": "Text", "id": 7, "properties": {"text": "y"}}]'
    ids = _actionui.insert_row("worker-window", 2, cells)
    print("inserted ids", ids, flush=True)

def did_finish():
    _actionui.app_load_and_present_window(GRID_URL, "worker-window", "Worker test")
    threading.Timer(0.5, worker).start()

_actionui.app_set_did_finish_launching(did_finish)
_actionui.app_run()
"""

GRID = {"type": "Grid", "id": 2,
        "properties": {"rows": [[{"type": "Text", "id": 10, "properties": {"text": "a"}}]]}}


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    with tempfile.TemporaryDirectory() as folder:
        grid_path = os.path.join(folder, "grid.json")
        with open(grid_path, "w") as f:
            json.dump(GRID, f)
        grid_url = "file://" + grid_path
        try:
            child = subprocess.run([sys.executable, "-c", CHILD, here, grid_url],
                                   capture_output=True, text=True, timeout=30)
        except subprocess.TimeoutExpired:
            print("FAILED: the worker's call deadlocked (no exit within 30 s)")
            sys.exit(1)
    output = child.stdout
    failures = []
    if child.returncode != 0:
        failures.append(f"status {child.returncode}")
    if "worker returned None" not in output:
        failures.append("the worker's value call did not return")
    if "guards checked" not in output or "NOT REFUSED" in output or "WRONG ERROR" in output:
        failures.append("a call that stores a callback was not refused off the main thread")
    ids_lines = [line for line in output.splitlines() if line.startswith("inserted ids ")]
    if not ids_lines:
        failures.append("insert_row returned no ids")
    else:
        ids = json.loads(ids_lines[0][len("inserted ids "):])
        if len(ids) != 2 or ids[0] >= 0 or ids[1] != 7:
            failures.append(f"insert_row ids {ids}: expected an automatic negative id, then 7")
    if failures:
        print("FAILED: " + "; ".join(failures))
        print(child.stdout + child.stderr)
        sys.exit(1)
    print("PASSED: a worker's calls returned, callback setters were refused, insert_row ids kept their sign")


if __name__ == "__main__":
    main()
