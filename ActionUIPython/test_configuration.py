#!/usr/bin/env python3
"""
Integration test for ActionUI's configuration (actionui.configure, actionui.get_configuration).

Before any window loads:
- Application(resource_folder=) is the configuration's resourceFolder;
- configure changes only the keys it names (the nesting depth to 2, a trusted origin) and keeps
  the rest;
- an unknown key, a wrong type and an origin that is not https are refused with ActionUIError,
  and change nothing.
Then a real NSApplication run loop shows one window whose LoadableViews nest three deep
(a.json, b.json, c.json): with the depth at 2, b.json loads and c.json is refused. Once the
window has loaded, configure is refused: the configuration is fixed.

Requirements: a graphical macOS session; the _actionui extension built (pip install . or
build_ext --inplace).

Usage: python3 test_configuration.py
"""

import os
import json
import tempfile
import threading
import actionui

SAFETY_TIMEOUT_SEC = 15.0
WINDOW_DISPLAY_SEC = 1.5

folder = tempfile.mkdtemp(prefix="actionui-configuration-")


def write(name, value):
    path = os.path.join(folder, name)
    with open(path, "w") as f:
        json.dump(value, f)
    return path


write("c.json", {"type": "Text", "id": 40, "properties": {"text": "Too deep"}})
write("b.json", {"type": "VStack", "id": 30, "children": [
    {"type": "LoadableView", "id": 31, "properties": {"filePath": os.path.join(folder, "c.json")}}]})
write("a.json", {"type": "VStack", "id": 20, "children": [
    {"type": "LoadableView", "id": 21, "properties": {"filePath": os.path.join(folder, "b.json")}}]})
root = write("root.json", {"type": "VStack", "id": 1, "children": [
    {"type": "LoadableView", "id": 3, "properties": {"filePath": os.path.join(folder, "a.json")}}]})

state = {"origins": {}, "late_refusal": None, "late_configuration": None, "closed": False}
_failures = []


def check(label, condition):
    print(f"  [{'PASS' if condition else 'FAIL'}] {label}", flush=True)
    if not condition:
        _failures.append(label)


def refused(settings):
    """The ActionUIError message configure raised for `settings`, or None."""
    try:
        actionui.configure(settings)
    except actionui.ActionUIError as error:
        return str(error)
    return None


app = actionui.Application(resource_folder=folder)

print("Before the first window:", flush=True)
initial = actionui.get_configuration()
check("every key is there", set(initial) == {"limits", "trust", "resourceFolder", "addOns"})
check("the defaults: 16 MB, 256 loads in 60 s, 16 deep, no trusted origins",
      initial["limits"] == {"maximumJSONSize": 16777216, "loadBudget": {"loads": 256, "seconds": 60}, "maximumNestingDepth": 16,
                            "maximumDownloadTime": 120}
      and initial["trust"] == {"trustedOrigins": []})
check("Application(resource_folder=) is the configuration's resource folder",
      os.path.realpath(initial["resourceFolder"] or "") == os.path.realpath(folder))

actionui.configure({"limits": {"maximumNestingDepth": 2}, "trust": {"trustedOrigins": ["https://ui.example.com"]}})
changed = actionui.get_configuration()
check("configure changes only the keys it names",
      changed["limits"]["maximumNestingDepth"] == 2 and changed["limits"]["maximumJSONSize"] == 16777216
      and changed["trust"]["trustedOrigins"] == ["https://ui.example.com"]
      and changed["resourceFolder"] == initial["resourceFolder"])
actionui.configure({"limits": {"maximumDownloadTime": None}})
check("None removes the time limit", actionui.get_configuration()["limits"]["maximumDownloadTime"] is None)
actionui.configure({"limits": {"maximumDownloadTime": 120}})

for settings, expected in [
    ({"limits": {"maximumNestingDepth": 5}, "trustedOrigin": []}, "unknown configuration key trustedOrigin"),
    ({"limits": {"maximumJSONSize": "big"}}, "limits.maximumJSONSize must be a whole number"),
    ({"trust": {"trustedOrigins": ["http://ui.example.com"]}}, "is not an https address"),
]:
    message = refused(settings)
    check(f"refused: {json.dumps(settings)}", message is not None and expected in message)
for bad, error_type in [(None, TypeError), ("limits", TypeError), ([1], TypeError),
                        ({"limits": {"loadBudget": {"seconds": float("nan")}}}, ValueError)]:
    try:
        actionui.configure(bad)
        raised = None
    except Exception as error:
        raised = error
    check(f"a {error_type.__name__} for settings {bad!r}", isinstance(raised, error_type))
check("the refusals changed nothing", actionui.get_configuration() == changed)


@app.did_finish_launching
def _did_finish():
    window = app.load_and_present_window(root, title="ActionUI Configuration Test")

    def _sequence():
        import time
        time.sleep(WINDOW_DISPLAY_SEC)
        app.close_window(window.uuid)
        time.sleep(0.5)
        app.terminate()

    threading.Thread(target=_sequence, daemon=True).start()


@app.window_will_close
def _window_will_close(window):
    state["closed"] = True
    for view_id in (1, 20, 30, 40):
        state["origins"][view_id] = window.get_element_origin(view_id)
    state["late_refusal"] = refused({"limits": {"maximumNestingDepth": 8}})
    state["late_configuration"] = actionui.get_configuration()


@app.should_terminate
def _should_terminate():
    return True


@app.will_terminate
def _will_terminate():
    _report()


def _report():
    print("\nWith a window:", flush=True)
    check("the window closed", state["closed"])
    origins = state["origins"]
    check("the window and the first two nested LoadableViews loaded",
          all(origins.get(view_id) is not None for view_id in (1, 20, 30)))
    check("the third, past the configured depth of 2, was refused", origins.get(40) is None)
    late = state["late_refusal"] or ""
    check("configure is refused once a window has loaded", "fixed" in late)
    check("and the configuration stays as it was", state["late_configuration"] == changed)
    print("=" * 50, flush=True)
    if _failures:
        print(f"FAILED - {len(_failures)} issue(s)", flush=True)
        os._exit(1)
    print("All configuration checks PASSED.", flush=True)


def _safety_timeout():
    check(f"Safety timeout ({SAFETY_TIMEOUT_SEC}s): app did not terminate", False)
    _report()
    os._exit(1)


timer = threading.Timer(SAFETY_TIMEOUT_SEC, _safety_timeout)
timer.daemon = True
timer.start()
app.run()
