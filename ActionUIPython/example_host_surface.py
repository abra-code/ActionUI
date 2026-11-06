#!/usr/bin/env python3
"""
A HostSurface drawn from Python: a window with an ActionUI slider beside a canvas that Python renders itself
and presents as pixels (actionui.present_pixels). The canvas shows color bands that drift over time; the
slider sets their speed, and a click on the canvas flips their direction.

On Linux the HostSurface is a frame sink, so this draws. On macOS the surface is a Metal layer, which needs a
Metal binding to draw into; the window opens, and the canvas stays empty.

Plain Python, no NumPy: each frame builds one row of pixels and repeats it, which bytes do in C.

Run: python3 example_host_surface.py
"""

import json
import os
import tempfile

import actionui

DOCUMENT = {
    "type": "VStack", "properties": {"padding": 12, "spacing": 10}, "children": [
        {"type": "HostSurface", "id": 5,
         "properties": {"surfaceName": "bands", "continuous": True, "idealWidth": 480, "idealHeight": 240}},
        {"type": "Text", "id": 7, "properties": {"text": "Speed (click the canvas to reverse)"}},
        {"type": "Slider", "id": 6, "properties": {"value": 60, "range": {"min": 0, "max": 240}, "actionID": "speed"}},
    ],
}

PALETTE = [(0x2E, 0x86, 0xDE), (0xF4, 0xA2, 0x59), (0x8C, 0xC0, 0x84), (0xE0, 0x5A, 0x6A), (0x7A, 0x5C, 0xC9)]


class Bands(actionui.SurfaceDelegate):
    def __init__(self):
        self.size = {}          # surface_id -> (width_pixels, height_pixels, scale)
        self.speed = 60.0       # pixels per second
        self.direction = 1
        self.start = None

    def created(self, info):
        self.size[info.surface_id] = (info.width_pixels, info.height_pixels, info.scale)
        actionui.set_cursor(info.surface_id, actionui.Cursor.POINTING_HAND)
        if info.kind != actionui.SurfaceKind.FRAME_SINK:
            print(f"The surface is {info.kind.name}, not a frame sink: nothing to present here.")

    def changed(self, info):
        self.size[info.surface_id] = (info.width_pixels, info.height_pixels, info.scale)

    def destroyed(self, info):
        self.size.pop(info.surface_id, None)

    def input(self, surface_id, event):
        if event.kind == actionui.InputKind.POINTER_DOWN:
            self.direction = -self.direction

    def frame(self, surface_id, timestamp):
        if surface_id not in self.size:
            return
        width, height, scale = self.size[surface_id]
        if self.start is None:
            self.start = timestamp
        offset = int((timestamp - self.start) * self.speed * scale * self.direction)
        band = max(1, int(40 * scale))
        row = bytearray()
        for x in range(width):
            red, green, blue = PALETTE[((x + offset) // band) % len(PALETTE)]
            row += bytes((red, green, blue, 0xFF))
        actionui.present_pixels(surface_id, bytes(row) * height, width, height)


bands = Bands()
app = actionui.Application(name="HostSurface Example")
app.set_surface_delegate("bands", bands)


@app.action("speed")
def _speed(context):
    value = actionui.Window(context.window_uuid).get_double(6)
    if value is not None:
        bands.speed = value


folder = tempfile.mkdtemp(prefix="actionui-host-surface-example-")
path = os.path.join(folder, "bands.json")
with open(path, "w") as file:
    json.dump(DOCUMENT, file)


@app.did_finish_launching
def _launched():
    app.load_and_present_window(path, title="HostSurface from Python")


app.run()
