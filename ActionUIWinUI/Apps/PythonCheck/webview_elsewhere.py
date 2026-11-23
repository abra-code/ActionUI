"""A WebView from Python, run as a user runs a script: from a folder other than the extension's, with no
Swift runtime on PATH. Windows looks for a DLL loaded by name later (WebView2's Core DLL, which WinUI
loads when it makes a WebView) beside python.exe, in the system folders, the current folder and PATH,
not beside the extension; the shim loads that DLL from its own folder first. Prints "python-elsewhere:"
lines: where WebView2's Core DLL was loaded from and whether the page loaded (its title). Exit status 0
when the page loaded, the DLL came from the extension's folder, the browser's data folder was not written
into the process's environment and is %LOCALAPPDATA%\\<program name>\\WebView2, and nothing was logged as a
warning or error. With --without-core, run from a copy of the extension's folder without WebView2's Core
DLL, with a copy of that DLL planted in the current folder and on PATH: exit status 0 when no page loaded,
no Core DLL was loaded (the planted copy included), and the log says it is missing. Run by
Scripts/ci-windows.py with the extension's folder on PYTHONPATH.
"""

import ctypes
import json
import os
import sys
import tempfile
import threading
import time

import actionui

TITLE = "Loaded from elsewhere"
# The first WebView2 start on a fresh x64 runner has taken from 6 to more than 20 seconds; a Core DLL
# that cannot be found fails at once with a logged error, so the wait only covers a slow start.
TIMEOUT_SECONDS = 60.0
# With --without-core the extension's folder lacks WebView2's Core DLL: no web view may be made (the shim
# loads that DLL only by its full path, never by a search of the current folder or PATH), and the log must
# say why.
WITHOUT_CORE = "--without-core" in sys.argv[1:]
MISSING_CORE = "Microsoft.Web.WebView2.Core.dll is not beside ActionUIWinUIShim.dll or the program"

app = actionui.Application(name="Python elsewhere")
state = {"window": None, "title": None, "errors": [], "core": None}


def report(message):
    print(f"python-elsewhere: {message}", flush=True)


def on_log(message, level):
    # Until the page has loaded, its title is not there yet: those reads' warnings say nothing. Nor does
    # the notice of a browser still starting after 5 seconds: WebView2's first start on a fresh machine
    # can take longer (x64 runners); a browser that never starts leaves no title, which fails below.
    if (level <= actionui.LogLevel.WARNING and "State key 'title' not found" not in message
            and "the browser has not started after 5 seconds" not in message):
        state["errors"].append(message)
        report(f"logged: {message}")


app.logger.set_callback(on_log)


def loaded_module(name):
    """The path of the loaded DLL `name`, or None when the process has not loaded it."""
    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel32.GetModuleHandleW.restype = ctypes.c_void_p
    kernel32.GetModuleHandleW.argtypes = [ctypes.c_wchar_p]
    kernel32.GetModuleFileNameW.argtypes = [ctypes.c_void_p, ctypes.c_wchar_p, ctypes.c_uint32]
    handle = kernel32.GetModuleHandleW(name)
    if not handle:
        return None
    buffer = ctypes.create_unicode_buffer(1024)
    kernel32.GetModuleFileNameW(handle, buffer, len(buffer))
    return buffer.value


def process_variable(name):
    """The process's own environment variable `name` now, or None (os.environ is a copy made at start)."""
    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel32.GetEnvironmentVariableW.argtypes = [ctypes.c_wchar_p, ctypes.c_wchar_p, ctypes.c_uint32]
    kernel32.GetEnvironmentVariableW.restype = ctypes.c_uint32
    buffer = ctypes.create_unicode_buffer(32768)
    length = kernel32.GetEnvironmentVariableW(name, buffer, len(buffer))
    return buffer.value if 0 < length < len(buffer) else None


def written_since(folder, since):
    """Whether a file under `folder` was modified at or after `since` (seconds since the epoch)."""
    for root, _, files in os.walk(folder):
        for name in files:
            try:
                if os.path.getmtime(os.path.join(root, name)) >= since:
                    return True
            except OSError:
                continue
    return False


def watch():
    """Waits for the page's title, then reports and ends the application."""
    started = time.monotonic()
    while time.monotonic() - started < (10.0 if WITHOUT_CORE else TIMEOUT_SECONDS):
        if WITHOUT_CORE and any(MISSING_CORE in message for message in state["errors"]):
            break
        window = state["window"]
        if window is not None:
            title = window.get_state_string(1, "title")
            if title:
                state["title"] = title
                break
        time.sleep(0.25)
    state["core"] = loaded_module("Microsoft.Web.WebView2.Core.dll")
    # The browser's data folder is passed to WebView2, never written into the process's environment
    # (programs the host starts would inherit it).
    state["data_variable"] = process_variable("WEBVIEW2_USER_DATA_FOLDER")
    report(f"WEBVIEW2_USER_DATA_FOLDER in the process: {state['data_variable'] or 'not set'}")
    report(f"WebView2 Core DLL: {state['core'] or 'not loaded'}")
    report(f"page title: {state['title'] or '(none)'} after {time.monotonic() - started:.2f} s")
    app.terminate()


@app.did_finish_launching
def launched():
    document = {"type": "WebView", "id": 1,
                "properties": {"html": f"<title>{TITLE}</title><p>A page from Python.</p>"}}
    folder = tempfile.mkdtemp(prefix="actionui-elsewhere-")
    path = os.path.join(folder, "WebView.json")
    with open(path, "w", encoding="utf-8") as file:
        json.dump(document, file)
    state["window"] = app.load_and_present_window(path, title="Python elsewhere")
    threading.Thread(target=watch, daemon=True).start()


report(f"mode: {'without the Core DLL' if WITHOUT_CORE else 'normal'}")
report(f"current folder: {os.getcwd()}")
report(f"extension: {actionui._actionui.__file__}")
# The data folder must be written by this run: one left by an earlier run would pass on its own.
run_started = time.time() - 2
app.run()
extension_folder = os.path.normcase(os.path.dirname(os.path.abspath(actionui._actionui.__file__)))
core_folder = os.path.normcase(os.path.dirname(state["core"])) if state["core"] else None
failures = []
if WITHOUT_CORE:
    if state["title"]:
        failures.append("a page loaded without the Core DLL beside the shim")
    if state["core"]:
        failures.append(f"WebView2's Core DLL was loaded from {state['core']}")
    if not any(MISSING_CORE in message for message in state["errors"]):
        failures.append("the missing Core DLL was not logged")
    report("PASSED" if not failures else "FAILED: " + "; ".join(failures))
    sys.exit(0 if not failures else 1)
if state["title"] != TITLE:
    failures.append("the page did not load")
if core_folder != extension_folder:
    failures.append("WebView2's Core DLL did not come from the extension's folder")
if state.get("data_variable"):
    failures.append("WEBVIEW2_USER_DATA_FOLDER was written into the process's environment")
data_folder = os.path.join(os.environ.get("LOCALAPPDATA", ""), os.path.splitext(os.path.basename(sys.executable))[0], "WebView2")
data_written = written_since(data_folder, run_started)
report(f"data folder {data_folder}: "
       f"{'written by this run' if data_written else 'present, not written by this run' if os.path.isdir(data_folder) else 'missing'}")
if state["title"] == TITLE and not data_written:
    failures.append("the browser's data is not in %LOCALAPPDATA%\\<program name>\\WebView2")
if state["errors"]:
    failures.append(f"{len(state['errors'])} warnings or errors logged")
report("PASSED" if not failures else "FAILED: " + "; ".join(failures))
sys.exit(0 if not failures else 1)
