#!/usr/bin/env python3
"""Live test for actionui-mcp: opens real windows over a stdio session and checks the answers.

Needs a graphical login session (a locked screen is fine) and a DEBUG build, whose
ACTIONUI_MCP_TEST_PRESS hook presses a dialog button without anyone at the screen.
Run with the sandbox off:

    /usr/bin/python3 Tests/live_session.py "$(swift build --show-bin-path)/actionui-mcp"
"""
import json
import os
import queue
import subprocess
import sys
import threading
import time


class Session:
    def __init__(self, binary, press=None, action=None, modern=False):
        env = dict(os.environ)
        if press:
            env["ACTIONUI_MCP_TEST_PRESS"] = press
        if action:
            env["ACTIONUI_MCP_TEST_ACTION"] = action
        self.proc = subprocess.Popen([binary], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                     stderr=sys.stderr, text=True, bufsize=1, env=env)
        self.inbox = queue.Queue()
        self.seen = []
        threading.Thread(target=self._read, daemon=True).start()
        # A modern (2026-07-28) session has no handshake: every request carries its _meta.
        self.meta = {"io.modelcontextprotocol/protocolVersion": "2026-07-28",
                     "io.modelcontextprotocol/clientInfo": {"name": "live-test-modern", "version": "1"},
                     "io.modelcontextprotocol/clientCapabilities": {}} if modern else None
        if not modern:
            self.send({"jsonrpc": "2.0", "id": 0, "method": "initialize",
                       "params": {"protocolVersion": "2025-11-25", "clientInfo": {"name": "live-test"}, "capabilities": {}}})
            self.response(0)

    def _read(self):
        for line in self.proc.stdout:
            self.inbox.put(json.loads(line))

    def send(self, message):
        self.proc.stdin.write(json.dumps(message) + "\n")
        self.proc.stdin.flush()

    def call(self, request_id, name, arguments, meta=None):
        params = {"name": name, "arguments": arguments}
        if meta or self.meta:
            params["_meta"] = dict(self.meta or {}, **(meta or {}))
        self.send({"jsonrpc": "2.0", "id": request_id, "method": "tools/call", "params": params})

    def response(self, request_id, timeout=15):
        end = time.time() + timeout
        while time.time() < end:
            for message in self.seen:
                if message.get("id") == request_id and "method" not in message:
                    return message
            try:
                self.seen.append(self.inbox.get(timeout=0.1))
            except queue.Empty:
                pass
        return None

    def close(self):
        start = time.time()
        self.proc.stdin.close()
        self.proc.wait(timeout=10)
        return time.time() - start


failures = []


def check(label, condition, detail=""):
    print(("ok   " if condition else "FAIL ") + label + ("" if condition else "  " + str(detail)))
    if not condition:
        failures.append(label)


def structured(message):
    return (message or {}).get("result", {}).get("structuredContent")


def is_error(message):
    return (message or {}).get("result", {}).get("isError") is True


binary = sys.argv[1]
FIELDS = [
    {"key": "name", "default": "2.3.1"},
    {"key": "target", "kind": "choice", "options": ["staging", "production"], "default": "production"},
    {"key": "count", "kind": "integer", "default": 3},
    {"key": "ratio", "kind": "number", "default": "1,234.5"},
    {"key": "notify", "kind": "toggle", "default": True},
    {"key": "share", "kind": "slider", "min": 0, "max": 100, "default": 25},
    {"key": "when", "kind": "date", "default": "2026-09-30"},
    {"key": "notes", "kind": "multiline"},
]

# Accept returns every field, typed.
s = Session(binary, press="Deploy")
s.call(1, "ask_user", {"title": "T", "fields": FIELDS, "buttons": ["Cancel", "Deploy"]})
result = structured(s.response(1))
check("accept", result == {"action": "accept", "button": "Deploy", "values": {
    "name": "2.3.1", "target": "production", "count": 3, "ratio": 1234.5, "notify": True,
    "share": 25, "when": "2026-09-30", "notes": ""}}, result)
s.close()

# Cancel button.
s = Session(binary, press="Cancel")
s.call(1, "ask_user", {"title": "T", "fields": FIELDS})
result = structured(s.response(1))
check("cancel button", result == {"action": "cancel", "button": "Cancel"}, result)
s.close()

# A missing required field or a bad number keeps the dialog open: only the timeout ends it.
s = Session(binary, press="OK")
s.call(1, "ask_user", {"title": "T", "fields": [{"key": "n", "required": True}], "timeout_s": 4})
s.call(2, "ask_user", {"title": "T", "fields": [{"key": "n", "kind": "integer", "default": "abc"}], "timeout_s": 4})
for request_id, label in [(1, "required field blocks accept"), (2, "bad number blocks accept")]:
    result = structured(s.response(request_id))
    check(label, result == {"action": "timeout", "button": None}, result)
s.close()

# Viewer: returns at once, close_window closes it, a second close reports false.
s = Session(binary)
s.call(1, "show", {"title": "Report", "kind": "markdown", "text": "# Hello\n\n**bold**", "width": 500, "height": 300})
result = structured(s.response(1, timeout=5))
check("show returns a window id", bool(result and result.get("window")), result)
window = (result or {}).get("window", "")
s.call(2, "close_window", {"window": window})
check("close_window", structured(s.response(2)) == {"closed": True})
s.call(3, "close_window", {"window": window})
check("close_window again", structured(s.response(3)) == {"closed": False})

# Diff and table viewers open; bad arguments come back as tool errors.
s.call(10, "show", {"title": "Diff", "kind": "diff", "old_text": "a\nb\n", "new_text": "a\nc\n"})
check("show diff (texts)", bool(structured(s.response(10, timeout=5))))
s.call(11, "show", {"title": "Diff", "kind": "diff", "old_path": os.path.abspath(__file__), "new_text": "x"})
check("show diff (file and text)", bool(structured(s.response(11, timeout=5))))
s.call(12, "show", {"title": "Table", "kind": "table", "columns": ["Name", "Size"],
                    "rows": [["a", 1], ["b"], ["c", 2.5]]})
check("show table", bool(structured(s.response(12, timeout=5))))
for request_id, arguments in [(13, {"title": "T", "kind": "table", "columns": ["A"], "rows": [["1", "2"]]}),
                              (14, {"title": "T", "kind": "diff", "old_text": "a"}),
                              (15, {"title": "T", "kind": "diff", "old_path": "relative", "new_text": "b"}),
                              (18, {"title": "T", "kind": "table", "columns": ["A", 1]}),
                              (19, {"title": "T", "kind": "table", "columns": ["A"], "rows": "x"})]:
    s.call(request_id, "show", arguments)
    message = s.response(request_id)
    check("show rejects %s" % json.dumps(arguments)[:60], (message or {}).get("result", {}).get("isError") is True, message)

# Field limit, and a long dialog (its fields scroll) still opens and answers.
s.call(16, "ask_user", {"title": "T", "fields": [{"key": "f%d" % i} for i in range(31)]})
check("more than 30 fields rejected", (s.response(16) or {}).get("result", {}).get("isError") is True)
for request_id, field in [(20, {"key": "s", "kind": "slider", "step": 0.5}),
                          (21, {"key": "s", "kind": "slider", "default": 5})]:
    s.call(request_id, "ask_user", {"title": "T", "fields": [field]})
    check("slider rejects %s" % json.dumps(field), (s.response(request_id) or {}).get("result", {}).get("isError") is True)
s.call(17, "ask_user", {"title": "Long", "timeout_s": 3,
                        "fields": [{"key": "m%d" % i, "kind": "multiline"} for i in range(8)]
                        + [{"key": "s", "kind": "slider", "min": 0, "max": 1, "step": 0.25, "default": 0.5}]})
check("long dialog opens and times out", structured(s.response(17)) == {"action": "timeout", "button": None})

# validate_document: structure, safety rules, and ActionUI's own load errors.
FORM = {"type": "VStack", "properties": {"padding": 16, "spacing": 8}, "children": [
    {"type": "Text", "id": 1, "properties": {"text": "Status: idle"}},
    {"type": "TextField", "id": 2, "properties": {"title": "Name", "text": "Ada"}},
    {"type": "Toggle", "id": 3, "properties": {"title": "Loud", "isOn": True}},
    {"type": "Button", "id": 4, "properties": {"title": "Go", "actionID": "go"}},
    {"type": "Table", "id": 5, "properties": {"columns": ["A", "B"], "frame": {"height": 80}}}]}
s.call(30, "validate_document", {"document": FORM})
result = structured(s.response(30))
check("validate good document", (result or {}).get("ok") is True and result.get("errors") == [], result)
bad = {"type": "VStack", "properties": {"children": []}, "children": [
    {"type": "Text", "id": 1}, {"type": "Text", "id": 1}, {"type": "SecureField", "id": -2}, {"properties": {}}]}
s.call(31, "validate_document", {"document": bad})
result = structured(s.response(31)) or {}
check("validate finds structural errors (%d)" % len(result.get("errors", [])),
      result.get("ok") is False and len(result.get("errors", [])) == 5, result)
s.call(32, "validate_document", {"document": {"type": "NoSuchElement"}})
result = structured(s.response(32)) or {}
check("validate reports ActionUI load errors", result.get("ok") is False and result.get("errors"), result)
s.call(33, "validate_document", {"document": json.dumps(FORM)})
result = structured(s.response(33)) or {}
check("validate rejects a document passed as a string", result.get("ok") is False, result)
s.call(51, "validate_document", {"document": {"type": "Text", "properties": {"txt": "hi"}}})
result = structured(s.response(51)) or {}
check("validate warns about a property typo", result.get("ok") is True
      and any("possible typo" in w for w in result.get("warnings", [])), result)
s.call(52, "show_document", {"title": "T", "document": {"type": "VStack", "properties": {"spacing": "16"}}})
message = s.response(52)
check("show_document refuses a wrong value type", is_error(message)
      and "expected number, got string" in message["result"]["content"][0]["text"], message)
s.call(53, "validate_document", {"document": {"type": "QuickLook", "properties": {"filePath": "/tmp/x.pdf"}}})
result = structured(s.response(53)) or {}
check("validate knows add-on elements", result.get("ok") is True and result.get("warnings") == [], result)
s.call(34, "show_document", {"title": "T", "document": {"type": "NoSuchElement"}})
check("show_document refuses a document ActionUI cannot load", is_error(s.response(34)))

# A live window: values in, values out, rows, wait with a timeout, close event.
s.call(35, "show_document", {"title": "Live", "document": FORM})
result = structured(s.response(35)) or {}
live = result.get("window", "")
check("show_document window mode", bool(live), result)
s.call(36, "update_window", {"window": live, "values": {"1": "Status: busy", "2": "Grace", "3": False, "99": "x"},
                             "rows": {"5": [["a", 1], ["b", 2]]}, "append_rows": {"5": [["c", 3]]}})
result = structured(s.response(36)) or {}
check("update_window", result.get("updated") == 5 and result.get("problems") == ["no element with id 99"], result)
s.call(37, "get_values", {"window": live, "ids": [1, 2, 3]})
result = structured(s.response(37)) or {}
check("get_values reads what update_window wrote",
      result.get("values") == {"1": "Status: busy", "2": "Grace", "3": False}, result)
s.call(38, "wait", {"window": live, "timeout_s": 1})
result = structured(s.response(38)) or {}
check("wait times out with no events", result.get("events") == [] and result.get("timed_out") is True, result)
s.call(39, "close_window", {"window": live})
s.response(39)
s.call(40, "wait", {"window": live, "timeout_s": 5})
result = structured(s.response(40)) or {}
check("wait reports window.closed", [e.get("action") for e in result.get("events", [])] == ["window.closed"], result)
s.call(41, "wait", {"window": live, "timeout_s": 1})
check("wait on a closed, drained window is an error", is_error(s.response(41)))

# A wait for one window ends when an older wait for any window takes that window's close event.
s.call(44, "show_document", {"title": "Live", "document": FORM})
live = (structured(s.response(44)) or {}).get("window", "")
s.call(45, "wait", {"timeout_s": 20})
time.sleep(0.3)
s.call(46, "wait", {"window": live, "timeout_s": 20})
time.sleep(0.3)
s.call(47, "close_window", {"window": live})
result = structured(s.response(45, timeout=5)) or {}
check("any-window wait gets window.closed", [e.get("action") for e in result.get("events", [])] == ["window.closed"], result)
result = structured(s.response(46, timeout=5)) or {}
check("wait for the closed window ends at once", result.get("events") == [] and not result.get("timed_out"), result)
s.call(48, "get_values", {"window": live, "ids": [1e300]})
check("get_values survives an out-of-range id", is_error(s.response(48)))
hidden = {"type": "VStack", "children": [
    {"type": "NavigationLink", "properties": {"title": "x"}, "destination": {"type": "SecureField", "id": 7}},
    {"type": "Grid", "rows": [[{"type": "SecureField", "id": 8}]]}]}
s.call(49, "validate_document", {"document": hidden})
result = structured(s.response(49)) or {}
check("validate finds elements nested in destination and Grid rows",
      result.get("ok") is False and len(result.get("errors", [])) == 2, result)

# pick_path: a bad folder is an error; an unanswered panel times out.
s.call(42, "pick_path", {"directory": "/no/such/folder"})
check("pick_path rejects a missing folder", is_error(s.response(42)))
s.call(43, "pick_path", {"kind": "save", "default_name": "x.txt", "timeout_s": 2})
check("pick_path times out", structured(s.response(43)) == {"action": "timeout", "paths": []})

# Cancellation closes the dialog and suppresses the response; the server keeps answering.
s.call(4, "ask_user", {"title": "Continue?"})
time.sleep(1)
s.send({"jsonrpc": "2.0", "method": "notifications/cancelled", "params": {"requestId": 4, "reason": "test"}})
s.send({"jsonrpc": "2.0", "id": 5, "method": "ping"})
check("ping after cancel", s.response(5) is not None)
check("no response for the cancelled call", s.response(4, timeout=1) is None)

# An action in a live window reaches a waiting agent, with the element's value.
s.close()
s = Session(binary, action="go@2")
s.call(1, "show_document", {"title": "Live", "document": FORM})
live = (structured(s.response(1)) or {}).get("window", "")
s.call(2, "wait", {"timeout_s": 10})
result = structured(s.response(2)) or {}
events = result.get("events", [])
check("wait receives the action", len(events) == 1 and events[0].get("action") == "go"
      and events[0].get("window") == live and events[0].get("id") == 2 and events[0].get("value") == "Ada", result)
s.close()

# Agent document as a dialog: chrome buttons and declared close actions both return every value.
s = Session(binary, press="Save")
s.call(1, "show_document", {"title": "Edit", "mode": "dialog", "document": FORM, "buttons": ["Cancel", "Save"]})
result = structured(s.response(1)) or {}
check("document dialog accept", result.get("action") == "accept" and result.get("button") == "Save"
      and result.get("values", {}).get("2") == "Ada" and result.get("values", {}).get("3") is True, result)
s.close()
s = Session(binary, action="go@4")
s.call(1, "show_document", {"title": "Edit", "mode": "dialog", "document": FORM, "buttons": [], "close_actions": ["go"]})
result = structured(s.response(1)) or {}
check("document dialog close action", result.get("action") == "accept" and result.get("close_action") == "go", result)
s.call(2, "show_document", {"title": "Edit", "mode": "dialog", "document": FORM, "buttons": []})
check("document dialog needs a way out", is_error(s.response(2)))

# A modern client: server/discover, then a real dialog, with no initialize.
s.close()
s = Session(binary, press="OK", modern=True)
s.send({"jsonrpc": "2.0", "id": 1, "method": "server/discover", "params": {"_meta": s.meta}})
result = (s.response(1) or {}).get("result", {})
check("modern server/discover", "2026-07-28" in result.get("supportedVersions", [])
      and result.get("resultType") == "complete", result)
s.call(2, "ask_user", {"title": "Modern", "fields": [{"key": "n", "default": "x"}]})
message = s.response(2) or {}
check("modern ask_user", message.get("result", {}).get("resultType") == "complete"
      and structured(message) == {"action": "accept", "button": "OK", "values": {"n": "x"}}, message)

# Element reference as resources, from the documentation bundles next to the binary.
s.send({"jsonrpc": "2.0", "id": 3, "method": "resources/list", "params": {"_meta": s.meta}})
listed = [r["uri"] for r in (s.response(3) or {}).get("result", {}).get("resources", [])]
check("resources/list has the guide and core and add-on elements (%d)" % len(listed),
      {"actionui://docs/guide", "actionui://docs/elements/Button", "actionui://docs/elements/QuickLook"} <= set(listed))
s.send({"jsonrpc": "2.0", "id": 4, "method": "resources/read",
        "params": {"uri": "actionui://docs/templates/TextField", "_meta": s.meta}})
contents = ((s.response(4) or {}).get("result", {}).get("contents") or [{}])[0]
check("resources/read returns a template", contents.get("mimeType") == "application/json"
      and '"TextField"' in contents.get("text", ""), contents)

# Shutdown with a dialog pending must fit the client's 2 s grace period.
s.call(6, "ask_user", {"title": "Pending at shutdown"})
time.sleep(1)
elapsed = s.close()
check("exit on end of input (%.2f s)" % elapsed, elapsed < 2 and s.proc.returncode == 0, s.proc.returncode)

print("%d failure(s)" % len(failures))
sys.exit(1 if failures else 0)
