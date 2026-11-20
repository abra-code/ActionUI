#!/usr/bin/env python3
"""
A call from a worker thread while the app runs must not deadlock.

The worker asks for a value of a window that does not exist. The library does that work on the
main thread, which logs a warning, and the log reaches Python through the logger bridge, which
needs the interpreter lock (GIL). The extension used to hold the GIL across the wait for the main
thread, so the two waited on each other for good. The child process here must finish within the
timeout.

Needs a graphical login session (it runs the application). Run with: python3 test_worker_thread_calls.py
"""

import os
import subprocess
import sys

CHILD = r"""
import sys, threading
sys.path.insert(0, sys.argv[1])
import _actionui
_actionui.set_logger(lambda message, level: None)

def worker():
    value = _actionui.get_string_value("no-such-window", 1, 0)
    print("worker returned", value, flush=True)
    _actionui.app_terminate()

def did_finish():
    threading.Thread(target=worker, daemon=True).start()

_actionui.app_set_did_finish_launching(did_finish)
_actionui.app_run()
"""


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    try:
        child = subprocess.run([sys.executable, "-c", CHILD, here], capture_output=True, text=True, timeout=30)
    except subprocess.TimeoutExpired:
        print("FAILED: the worker's call deadlocked (no exit within 30 s)")
        sys.exit(1)
    if child.returncode != 0 or "worker returned None" not in child.stdout:
        print("FAILED: status", child.returncode)
        print(child.stdout + child.stderr)
        sys.exit(1)
    print("PASSED: a worker thread's call returned while the app ran")


if __name__ == "__main__":
    main()
