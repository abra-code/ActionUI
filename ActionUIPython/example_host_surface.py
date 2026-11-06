#!/usr/bin/env python3
"""
A HostSurface drawn from Python: a window with an ActionUI slider beside a canvas that Python renders itself
and presents as pixels (actionui.present_pixels). The canvas shows color bands that drift over time; the
slider sets their speed, and a click on the canvas flips their direction.

Frame pacing: while the bands move, the surface is continuous (a frame callback at every display refresh). At
speed 0 the script turns that off and asks for single frames only when the picture must be drawn again (a new
surface, a new size), so a still canvas costs no CPU. This is the pattern to follow for content that changes
only now and then.

The element asks for "kind": "sink", a frame sink on macOS and Linux alike, so the same script draws on both.

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
         "properties": {"surfaceName": "bands", "kind": "sink", "continuous": True, "idealWidth": 480, "idealHeight": 240}},
        {"type": "Text", "id": 7, "properties": {"text": "Speed (click the canvas to reverse)"}},
        {"type": "Slider", "id": 6, "properties": {"value": 60, "range": {"min": 0, "max": 240}, "valueChangeActionID": "speed"}},
    ],
}

PALETTE = [(0x2E, 0x86, 0xDE), (0xF4, 0xA2, 0x59), (0x8C, 0xC0, 0x84), (0xE0, 0x5A, 0x6A), (0x7A, 0x5C, 0xC9)]


class Bands(actionui.SurfaceDelegate):
    def __init__(self):
        self.size = {}          # surface_id -> (width_pixels, height_pixels, scale)
        self.speed = 60.0       # points per second
        self.direction = 1
        self.offset = 0.0       # how far the bands have moved, in pixels
        self.last = None        # the previous frame's timestamp

    def moving(self):
        return self.speed > 0

    def pace(self, surface_id):
        """Frames at every refresh while the bands move; else one frame, to draw the still picture."""
        actionui.set_continuous(surface_id, self.moving())
        if not self.moving():
            actionui.request_frame(surface_id)

    def set_speed(self, speed):
        was_moving = self.moving()
        self.speed = speed
        if self.moving() != was_moving:
            # Start timing afresh, so the time spent still does not move the bands at once.
            self.last = None
            for surface_id in self.size:
                self.pace(surface_id)

    def created(self, info):
        self.size[info.surface_id] = (info.width_pixels, info.height_pixels, info.scale)
        actionui.set_cursor(info.surface_id, actionui.Cursor.POINTING_HAND)
        if info.kind != actionui.SurfaceKind.FRAME_SINK:
            print(f"The surface is {info.kind.name}, not a frame sink: nothing to present here.")
        self.pace(info.surface_id)

    def changed(self, info):
        self.size[info.surface_id] = (info.width_pixels, info.height_pixels, info.scale)
        # A new size needs a new picture; while moving, the next refresh brings one anyway.
        if not self.moving():
            actionui.request_frame(info.surface_id)

    def destroyed(self, info):
        self.size.pop(info.surface_id, None)

    def input(self, surface_id, event):
        if event.kind == actionui.InputKind.POINTER_DOWN:
            # At speed 0 the picture does not change, so no frame is needed.
            self.direction = -self.direction

    def frame(self, surface_id, timestamp):
        if surface_id not in self.size:
            return
        width, height, scale = self.size[surface_id]
        # Moved by the time since the last frame, so a new speed or direction takes over from where the bands are.
        if self.last is not None:
            self.offset += (timestamp - self.last) * self.speed * scale * self.direction
        self.last = timestamp
        offset = int(self.offset)
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
        bands.set_speed(value)


folder = tempfile.mkdtemp(prefix="actionui-host-surface-example-")
path = os.path.join(folder, "bands.json")
with open(path, "w") as file:
    json.dump(DOCUMENT, file)


@app.did_finish_launching
def _launched():
    app.load_and_present_window(path, title="HostSurface from Python")


app.run()
