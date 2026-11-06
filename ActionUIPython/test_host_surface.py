#!/usr/bin/env python3
"""
Integration test of the HostSurface API (actionui.SurfaceDelegate, set_surface_delegate, present_pixels).

Starts a real application run loop with a window that holds HostSurface elements, and checks:
- a bound delegate gets "created" with the platform's kind (a Metal layer on macOS, a frame sink on Linux);
- a delegate bound inside a callback takes over after it: the old one gets "destroyed" first, the new one
  "created" with a new surface ID;
- present_pixels from another thread (True on Linux; False on macOS, whose surfaces are Metal layers), and the
  argument checks;
- on Linux, a "gl" element's render callback;
- window close sends "destroyed".

Requirements: a graphical session (macOS window server, or a Wayland/X11 display on Linux), and the _actionui
extension built. Usage: python3 test_host_surface.py

The report runs from will_terminate (the run loop ends the process with exit()).
"""

import json
import os
import sys
import tempfile
import threading
import time

import actionui

SAFETY_TIMEOUT_SEC = 20.0
IS_LINUX = sys.platform.startswith("linux")

DOCUMENT = {
    "type": "VStack", "properties": {"frame": {"width": 300}}, "children": [
        {"type": "HostSurface", "id": 5,
         "properties": {"surfaceName": "py.canvas", "frame": {"width": 200, "height": 120}}},
    ] + ([
        {"type": "HostSurface", "id": 6,
         "properties": {"surfaceName": "py.gl", "kind": "gl", "frame": {"width": 80, "height": 60}}},
    ] if IS_LINUX else []),
}

state = {
    "first": [],
    "second": [],
    "gl_events": [],
    "gl_renders": 0,
    "frames": 0,
    "present_on_thread": None,
    "present_errors": [],
    "cursor_set": None,
    "errors": [],
}


class First(actionui.SurfaceDelegate):
    def created(self, info):
        state["first"].append(("created", info))
        # Rebinding inside a callback: the change waits until this returns.
        actionui.set_surface_delegate("py.canvas", second)
        state["first"].append(("rebound", None))

    def destroyed(self, info):
        state["first"].append(("destroyed", info))


class Second(actionui.SurfaceDelegate):
    def created(self, info):
        state["second"].append(("created", info))
        state["cursor_set"] = actionui.set_cursor(info.surface_id, actionui.Cursor.CROSSHAIR)
        actionui.request_frame(info.surface_id)
        width, height = info.width_pixels, info.height_pixels
        pixels = bytearray([0x30, 0x60, 0x90, 0xFF]) * (width * height)

        def present():
            state["present_on_thread"] = actionui.present_pixels(info.surface_id, pixels, width, height)

        threading.Thread(target=present).start()
        # The argument checks.
        for bad in (lambda: actionui.present_pixels(info.surface_id, b"\x00" * 7, 2, 1),
                    lambda: actionui.present_pixels(info.surface_id, pixels, 0, 1),
                    lambda: actionui.present_pixels(info.surface_id, pixels)):
            try:
                bad()
                state["present_errors"].append("no error")
            except ValueError:
                state["present_errors"].append("ValueError")

    def suspended(self, info):
        state["second"].append(("suspended", info))

    def resumed(self, info):
        state["second"].append(("resumed", info))

    def frame(self, surface_id, timestamp):
        state["frames"] += 1

    def destroyed(self, info):
        state["second"].append(("destroyed", info))


class GLClient(actionui.SurfaceDelegate):
    def created(self, info):
        state["gl_events"].append(("created", info.kind))
        actionui.request_frame(info.surface_id)

    def render(self, surface_id):
        state["gl_renders"] += 1

    def destroyed(self, info):
        state["gl_events"].append(("destroyed", info.kind))


second = Second()

failures = []


def check(what, passed):
    print(f"  {'ok  ' if passed else 'FAIL'} {what}", flush=True)
    if not passed:
        failures.append(what)


def _report():
    print("\nResults", flush=True)
    first_kinds = [kind for kind, _ in state["first"]]
    second_kinds = [kind for kind, _ in state["second"]]
    check(f"the first delegate got created, rebound, then destroyed ({first_kinds})",
          first_kinds == ["created", "rebound", "destroyed"])
    first_info = state["first"][0][1] if state["first"] else None
    expected_kind = actionui.SurfaceKind.FRAME_SINK if IS_LINUX else actionui.SurfaceKind.METAL_LAYER
    check(f"created with the platform's kind ({first_info.kind if first_info else None})",
          first_info is not None and first_info.kind == expected_kind)
    if first_info is not None:
        check(f"the size of the frame, 200 x 120 points ({first_info.width_points} x {first_info.height_points})",
              first_info.width_points == 200 and first_info.height_points == 120)
        check("a nonzero pixel size", first_info.width_pixels > 0 and first_info.height_pixels > 0)
        check("a Metal layer handle on macOS, none for a frame sink",
              (first_info.handle is None) if IS_LINUX else (isinstance(first_info.handle, int) and first_info.handle != 0))
    second_created = [info for kind, info in state["second"] if kind == "created"]
    check("the second delegate got created", len(second_created) == 1)
    if second_created and first_info is not None:
        check("with a new surface ID", second_created[0].surface_id != first_info.surface_id)
    check(f"the second delegate got destroyed at window close ({second_kinds})", second_kinds[-1:] == ["destroyed"])
    expected_present = True if IS_LINUX else False
    check(f"present_pixels from another thread returned {expected_present} ({state['present_on_thread']})",
          state["present_on_thread"] is expected_present)
    check(f"present_pixels refuses a short buffer, a zero width, and a missing size ({state['present_errors']})",
          state["present_errors"] == ["ValueError"] * 3)
    check(f"set_cursor on a live surface returned True ({state['cursor_set']})", state["cursor_set"] is True)
    if "suspended" not in second_kinds:
        check(f"a requested frame came ({state['frames']})", state["frames"] >= 1)
    else:
        print("  (the window was not visible, so no frame was expected)", flush=True)
    if IS_LINUX:
        check(f"the GL client got created and destroyed ({state['gl_events']})",
              state["gl_events"] == [("created", actionui.SurfaceKind.GL_AREA), ("destroyed", actionui.SurfaceKind.GL_AREA)])
        check(f"the GL client's render was called ({state['gl_renders']})", state["gl_renders"] >= 1)
    for error in state["errors"]:
        check(error, False)
    print(f"\n{'PASSED' if not failures else 'FAILED'}: {len(failures)} failure(s)", flush=True)
    sys.stdout.flush()
    if failures:
        os._exit(1)


print("ActionUI HostSurface Integration Test", flush=True)
app = actionui.Application()
actionui.set_surface_delegate("py.canvas", First())
if IS_LINUX:
    app.set_surface_delegate("py.gl", GLClient())

folder = tempfile.mkdtemp(prefix="actionui-hostsurface-test-")
document_path = os.path.join(folder, "HostSurface.json")
with open(document_path, "w") as file:
    json.dump(DOCUMENT, file)


@app.did_finish_launching
def _did_finish():
    window = app.load_and_present_window(document_path, title="HostSurface Test")

    def _sequence():
        time.sleep(2.0)
        app.close_window(window.uuid)
        time.sleep(0.5)
        app.terminate()

    threading.Thread(target=_sequence, daemon=True).start()


@app.will_terminate
def _will_terminate():
    try:
        os.remove(document_path)
        os.rmdir(folder)
    except OSError:
        pass
    _report()


def _safety_timeout():
    state["errors"].append(f"safety timeout ({SAFETY_TIMEOUT_SEC}s): the app did not terminate")
    import _actionui
    _actionui.app_terminate()


timer = threading.Timer(SAFETY_TIMEOUT_SEC, _safety_timeout)
timer.daemon = True
timer.start()
app.run()
