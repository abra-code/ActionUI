#!/usr/bin/env python3
"""
Integration test for the host's trust policy (set_trust_policy) and element origins
(Window.get_element_origin).

Starts a real NSApplication run loop with one window loaded from a temporary folder, outside
the app's resources (its subfolder "res", named explicitly):
- root.json, the window's own document, is made trusted by the trust callback, as a host trusts
  a document it chose itself;
- less.json, in its first LoadableView, keeps ActionUI's own decision, less trusted; its Image
  reads a file there, which reaches the allows callback with ActionUI's refusal as the default;
- trusted.json, in the second, is made trusted by the trust callback;
- res/raises.json, in the third, is trusted by default (a resource inside trusted content), but
  the trust callback raises for it, so it is less trusted (fails closed; the traceback printed
  for it is expected).
The origins are read in window_will_close, on the main thread, and checked from will_terminate.

Requirements: a graphical macOS session; the _actionui extension built (pip install . or
build_ext --inplace).

Usage: python3 test_trust_policy.py
"""

import os
import sys
import json
import tempfile
import threading
import actionui

SAFETY_TIMEOUT_SEC = 15.0
WINDOW_DISPLAY_SEC = 1.5



def _png():
    """A valid 1x1 RGBA PNG."""
    import struct
    import zlib
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xffffffff)
    header = struct.pack(">IIBBBBB", 1, 1, 8, 6, 0, 0, 0)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header)
            + chunk(b"IDAT", zlib.compress(b"\x00\xff\x00\x00\xff")) + chunk(b"IEND", b""))


PNG = _png()

folder = tempfile.mkdtemp(prefix="actionui-trust-")
picture = os.path.join(folder, "pic.png")
with open(picture, "wb") as f:
    f.write(PNG)
with open(os.path.join(folder, "less.json"), "w") as f:
    json.dump({"type": "VStack", "id": 20, "children": [
        {"type": "Image", "id": 21, "properties": {"filePath": picture}}]}, f)
with open(os.path.join(folder, "trusted.json"), "w") as f:
    json.dump({"type": "Text", "id": 30, "properties": {"text": "Trusted by the host"}}, f)
resources = os.path.join(folder, "res")
os.mkdir(resources)
with open(os.path.join(resources, "raises.json"), "w") as f:
    json.dump({"type": "Text", "id": 50, "properties": {"text": "The trust callback raises"}}, f)
root = os.path.join(folder, "root.json")
with open(root, "w") as f:
    json.dump({"type": "VStack", "id": 1, "children": [
        {"type": "LoadableView", "id": 3, "properties": {"filePath": os.path.join(folder, "less.json")}},
        {"type": "LoadableView", "id": 4, "properties": {"filePath": os.path.join(folder, "trusted.json")}},
        {"type": "LoadableView", "id": 5, "properties": {"filePath": os.path.join(resources, "raises.json")}}]}, f)

state = {"trust_calls": [], "allows_calls": [], "origins": {}, "errors": [], "closed": False}
_failures = []


def check(label, condition):
    print(f"  [{'PASS' if condition else 'FAIL'}] {label}", flush=True)
    if not condition:
        _failures.append(label)


def trust(source, parent, by_default):
    state["trust_calls"].append((source, parent, by_default))
    if source.get("path", "").endswith("raises.json"):
        raise RuntimeError("expected: the trust callback raises for raises.json")
    if source.get("path", "").endswith(("root.json", "trusted.json")):
        return actionui.Trust.TRUSTED
    return by_default


def allows(capability, origin, by_default):
    state["allows_calls"].append((capability, origin, by_default))
    return by_default


def _report():
    print("\nChecks:", flush=True)
    for error in state["errors"]:
        check(error, False)
    check("the window closed", state["closed"])
    origins = state["origins"]
    root_origin = origins.get(1) or {}
    check("the window's own document is a file, trusted by the trust callback, with no parent",
          root_origin.get("source") == "file" and root_origin.get("path", "").endswith("root.json")
          and root_origin.get("trust") == "trusted" and "parentID" not in root_origin)
    less = origins.get(20) or {}
    check("less.json is a file, less trusted, inside LoadableView 3",
          less.get("source") == "file" and less.get("path", "").endswith("less.json")
          and less.get("trust") == "lessTrusted" and less.get("parentID") == 3)
    made = origins.get(30) or {}
    check("trusted.json is trusted by the trust callback",
          made.get("trust") == "trusted" and made.get("parentID") == 4)
    raised = origins.get(50) or {}
    check("res/raises.json is a resource, less trusted because the trust callback raised",
          raised.get("source") == "resource" and raised.get("trust") == "lessTrusted" and raised.get("parentID") == 5)
    check("an element the window does not have has no origin", origins.get(999, "missing") is None)
    sources = [call[0].get("path", "") for call in state["trust_calls"]]
    check("the trust callback was asked for both documents",
          any(p.endswith("less.json") for p in sources) and any(p.endswith("trusted.json") for p in sources))
    check("every call had less trusted as the default but raises.json's (outside the resources)",
          bool(state["trust_calls"]) and all((call[2] == actionui.Trust.TRUSTED) == call[0].get("path", "").endswith("raises.json")
                                              for call in state["trust_calls"])
          and any(p.endswith("raises.json") for p in sources))
    check("the window's document had no parent, the LoadableViews' the trusted root",
          all((call[1] is None) == call[0].get("path", "").endswith("root.json")
              and (call[1] is None or call[1] == root_origin) for call in state["trust_calls"]))
    reads = [call for call in state["allows_calls"]
             if call[0].get("capability") == "readLocalFile" and call[0].get("path", "").endswith("pic.png")]
    check("the allows callback was asked about less.json's picture, refused by default",
          bool(reads) and all(call[1].get("trust") == "lessTrusted" and call[2] is False for call in reads))
    print("=" * 50, flush=True)
    if _failures:
        print(f"FAILED - {len(_failures)} issue(s)", flush=True)
        os._exit(1)
    print("All trust policy checks PASSED.", flush=True)


# Only the subfolder is the app's resources, wherever this script is run from.
app = actionui.Application(resource_folder=resources)

# Wrong arguments are refused and change nothing.
try:
    actionui.set_trust_policy(trust="not callable")
    state["errors"].append("a trust argument that is not callable was accepted")
except TypeError:
    pass
actionui.set_trust_policy(trust=trust, allows=allows)


@app.did_finish_launching
def _did_finish():
    window = app.load_and_present_window(root, title="ActionUI Trust Policy Test")

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
    for view_id in (1, 20, 30, 50, 999):
        state["origins"][view_id] = window.get_element_origin(view_id)


@app.should_terminate
def _should_terminate():
    return True


@app.will_terminate
def _will_terminate():
    actionui.set_trust_policy()
    _report()


def _safety_timeout():
    state["errors"].append(f"Safety timeout ({SAFETY_TIMEOUT_SEC}s): app did not terminate")
    _report()
    os._exit(1)


timer = threading.Timer(SAFETY_TIMEOUT_SEC, _safety_timeout)
timer.daemon = True
timer.start()
app.run()
