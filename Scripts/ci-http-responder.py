#!/usr/bin/env python3
"""A local HTTP server for Windows CI that records whether requests carry the app's identity.

Started by Scripts/ci-windows.py around one preview. It listens on the loopback addresses only
(127.0.0.1 and ::1, one port chosen by the system), writes that port to --port-file, and appends one
JSON line per request to --record:
  {"method": ..., "path": ..., "over": "IPv4" or "IPv6", "authorization": scheme or null, "cookie": [cookie names] or null, "agent": ...}
It records a sign-in's scheme (Negotiate, NTLM, Basic) and the names of the cookies sent, never their
values.

Routes:
  /set-cookie.json   200, small ActionUI JSON, and sets the cookie actionui_probe=1 for the whole site
  /outer.json        200, ActionUI JSON naming /auth/... and /cookie/... from a LoadableView, an AsyncImage,
                     a VideoPlayer and a WebView (served by this server, so it is less-trusted content)
  /auth/<name>       401, asking for Negotiate and NTLM sign-in; never completes one
  /cookie/<name>     200, a small valid body of the kind its name ends in (.json, .png, .mp4, .html)
Anything else is 404. Stops when --stop-file appears (or when its process is ended).
"""

import argparse
import base64
import json
import os
import socket
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

# A 1x1 transparent PNG.
PNG = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")
ELEMENTS = ["LoadableView", "AsyncImage", "VideoPlayer", "WebView"]


def outer_json(port):
    """The less-trusted document: each element kind once naming /auth/, once /cookie/."""
    base = f"http://localhost:{port}"
    children = []
    next_id = 201
    for prefix in ["auth", "cookie"]:
        for kind, name, key in [("LoadableView", "loadable.json", "url"), ("AsyncImage", "image.png", "url"),
                                ("VideoPlayer", "video.mp4", "url"), ("WebView", "page.html", "url")]:
            children.append({"type": kind, "id": next_id,
                             "properties": {key: f"{base}/{prefix}/{name}", "frame": {"width": 80, "height": 50}}})
            next_id += 1
    return {"type": "VStack", "id": 200, "properties": {"spacing": 4},
            "children": [{"type": "HStack", "id": 220, "properties": {"spacing": 4}, "children": children[:4]},
                         {"type": "HStack", "id": 221, "properties": {"spacing": 4}, "children": children[4:]}]}


class Handler(BaseHTTPRequestHandler):
    server_version = "ActionUIResponder/1"
    # Kept-alive connections, as a server that signs clients in with Negotiate or NTLM uses: a client
    # that starts that handshake sends its first message on the connection the 401 came on.
    protocol_version = "HTTP/1.1"

    def log_message(self, format, *args):
        # The record file is the log; stderr stays quiet.
        pass

    def record(self):
        authorization = self.headers.get("Authorization")
        cookie = self.headers.get("Cookie")
        # A cookie without "=" is a nameless cookie whose text is its value: recorded as "(nameless)".
        entry = {
            "method": self.command,
            "path": self.path,
            "over": "IPv6" if self.server.address_family == socket.AF_INET6 else "IPv4",
            "authorization": authorization.split(" ", 1)[0] if authorization else None,
            "cookie": sorted(part.split("=", 1)[0].strip() if "=" in part else "(nameless)"
                             for part in cookie.split(";")) if cookie else None,
            "agent": self.headers.get("User-Agent"),
        }
        with self.server.record_lock:
            with open(self.server.record_path, "a", encoding="utf-8") as record:
                record.write(json.dumps(entry) + "\n")

    def send_body(self, status, content_type, body, extra_headers=()):
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        for name, value in extra_headers:
            self.send_header(name, value)
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def do_HEAD(self):
        self.do_GET()

    def do_GET(self):
        self.record()
        path = self.path.split("?", 1)[0]
        if path == "/set-cookie.json":
            body = json.dumps({"type": "Text", "id": 101, "properties": {"text": "Cookie set"}}).encode()
            self.send_body(200, "application/json", body, [("Set-Cookie", "actionui_probe=1; Path=/")])
        elif path == "/outer.json":
            self.send_body(200, "application/json", json.dumps(outer_json(self.server.port)).encode())
        elif path.startswith("/auth/"):
            body = b"sign-in required"
            self.send_response(401)
            self.send_header("WWW-Authenticate", "Negotiate")
            self.send_header("WWW-Authenticate", "NTLM")
            self.send_header("Content-Type", "text/plain")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            if self.command != "HEAD":
                self.wfile.write(body)
        elif path.startswith("/cookie/"):
            if path.endswith(".json"):
                self.send_body(200, "application/json",
                               json.dumps({"type": "Text", "id": 102, "properties": {"text": "Cookie page"}}).encode())
            elif path.endswith(".png"):
                self.send_body(200, "image/png", PNG)
            elif path.endswith(".mp4") and self.server.video is not None:
                self.send_body(200, "video/mp4", self.server.video)
            elif path.endswith(".html"):
                self.send_body(200, "text/html", b"<html><head><title>Cookie page</title></head><body>page</body></html>")
            else:
                self.send_body(404, "text/plain", b"not found")
        else:
            self.send_body(404, "text/plain", b"not found")


class Server(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, address, family, settings):
        self.address_family = family
        super().__init__(address, Handler)
        self.record_path = settings["record"]
        self.record_lock = settings["lock"]
        self.video = settings["video"]
        self.port = settings["port"]


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--port-file", required=True, help="where the chosen port is written")
    parser.add_argument("--record", required=True, help="the file each request's line is appended to")
    parser.add_argument("--stop-file", required=True, help="the server stops when this file appears")
    parser.add_argument("--video", help="an MP4 file served for /cookie/*.mp4")
    arguments = parser.parse_args()
    video = Path(arguments.video).read_bytes() if arguments.video else None
    settings = {"record": arguments.record, "lock": threading.Lock(), "video": video, "port": 0}
    first = Server(("127.0.0.1", 0), socket.AF_INET, settings)
    port = first.server_address[1]
    settings["port"] = port
    first.port = port
    servers = [first]
    try:
        servers.append(Server(("::1", port), socket.AF_INET6, settings))
    except OSError as error:
        print(f"ci-http-responder: not listening on ::1 port {port}: {error}", file=sys.stderr, flush=True)
    for server in servers:
        threading.Thread(target=server.serve_forever, daemon=True).start()
    # Written whole, then renamed, so a reader polling for the file never sees it empty.
    partial = Path(arguments.port_file + ".partial")
    partial.write_text(str(port), encoding="utf-8")
    os.replace(partial, arguments.port_file)
    print(f"ci-http-responder: listening on port {port}", flush=True)
    try:
        while not os.path.exists(arguments.stop_file):
            time.sleep(0.2)
    except KeyboardInterrupt:
        pass
    for server in servers:
        server.shutdown()
        server.server_close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
