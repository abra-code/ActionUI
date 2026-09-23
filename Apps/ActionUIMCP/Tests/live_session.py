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
    def __init__(self, binary, press=None):
        env = dict(os.environ)
        if press:
            env["ACTIONUI_MCP_TEST_PRESS"] = press
        self.proc = subprocess.Popen([binary], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                     stderr=sys.stderr, text=True, bufsize=1, env=env)
        self.inbox = queue.Queue()
        self.seen = []
        threading.Thread(target=self._read, daemon=True).start()
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
        if meta:
            params["_meta"] = meta
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

# Cancellation closes the dialog and suppresses the response; the server keeps answering.
s.call(4, "ask_user", {"title": "Continue?"})
time.sleep(1)
s.send({"jsonrpc": "2.0", "method": "notifications/cancelled", "params": {"requestId": 4, "reason": "test"}})
s.send({"jsonrpc": "2.0", "id": 5, "method": "ping"})
check("ping after cancel", s.response(5) is not None)
check("no response for the cancelled call", s.response(4, timeout=1) is None)

# Shutdown with a dialog pending must fit the client's 2 s grace period.
s.call(6, "ask_user", {"title": "Pending at shutdown"})
time.sleep(1)
elapsed = s.close()
check("exit on end of input (%.2f s)" % elapsed, elapsed < 2 and s.proc.returncode == 0, s.proc.returncode)

print("%d failure(s)" % len(failures))
sys.exit(1 if failures else 0)
