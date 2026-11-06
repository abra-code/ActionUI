#!/usr/bin/env node
/*
 * A HostSurface drawn from JavaScript: a window with an ActionUI slider beside a canvas that the program renders
 * itself into a Uint8Array and presents as pixels (actionui.presentPixels). The canvas shows color bands that
 * drift over time; the slider sets their speed, and a click on the canvas flips their direction.
 *
 * Frame pacing: while the bands move, the surface is continuous (a frame callback at every display refresh). At
 * speed 0 the program turns that off and asks for single frames only when the picture must be drawn again (a new
 * surface, a new size), so a still canvas costs no CPU. This is the pattern to follow for content that changes
 * only now and then.
 *
 * The element asks for "kind": "sink", a frame sink on macOS and Linux alike, so the same script draws on both.
 *
 * Run: node example_host_surface.js
 */

'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const actionui = require('./index.js');

const DOCUMENT = {
    type: 'VStack', properties: { padding: 12, spacing: 10 }, children: [
        { type: 'HostSurface', id: 5,
          properties: { surfaceName: 'bands', kind: 'sink', continuous: true, idealWidth: 480, idealHeight: 240 } },
        { type: 'Text', id: 7, properties: { text: 'Speed (click the canvas to reverse)' } },
        { type: 'Slider', id: 6, properties: { value: 60, range: { min: 0, max: 240 }, valueChangeActionID: 'speed' } },
        { type: 'Text', id: 8, properties: { text: '', foregroundStyle: 'secondary' } },
    ],
};

const PALETTE = [[0x2E, 0x86, 0xDE], [0xF4, 0xA2, 0x59], [0x8C, 0xC0, 0x84], [0xE0, 0x5A, 0x6A], [0x7A, 0x5C, 0xC9]];

const bands = {
    sizes: new Map(),   // surfaceId -> { width, height, scale, pixels, windowUuid }
    speed: 60,          // points per second
    direction: 1,
    offset: 0,          // how far the bands have moved, in pixels
    last: null,         // the previous frame's timestamp

    moving() { return this.speed > 0; },

    // Frames at every refresh while the bands move; else one frame, to draw the still picture.
    pace(surfaceId) {
        actionui.setContinuous(surfaceId, this.moving());
        if (!this.moving()) actionui.requestFrame(surfaceId);
        const status = this.moving() ? 'Frames: continuous, one at every display refresh'
                                     : 'Frames: still, drawn only when asked for (requestFrame)';
        new actionui.Window(this.sizes.get(surfaceId).windowUuid).setString(8, 0, status);
    },

    setSpeed(speed) {
        const wasMoving = this.moving();
        this.speed = speed;
        if (this.moving() !== wasMoving) {
            // Start timing afresh, so the time spent still does not move the bands at once.
            this.last = null;
            for (const surfaceId of this.sizes.keys()) this.pace(surfaceId);
        }
    },

    created(info) {
        this.resize(info);
        actionui.setCursor(info.surfaceId, actionui.Cursor.POINTING_HAND);
        if (info.kind !== actionui.SurfaceKind.FRAME_SINK) {
            console.log('The surface is not a frame sink: nothing to present here.');
        }
        this.pace(info.surfaceId);
    },
    changed(info) {
        this.resize(info);
        // A new size needs a new picture; while moving, the next refresh brings one anyway.
        if (!this.moving()) actionui.requestFrame(info.surfaceId);
    },
    destroyed(info) { this.sizes.delete(info.surfaceId); },

    resize(info) {
        const { widthPixels: width, heightPixels: height, scale } = info;
        this.sizes.set(info.surfaceId,
                       { width, height, scale, pixels: new Uint8Array(width * height * 4), windowUuid: info.windowUuid });
    },

    input(surfaceId, event) {
        // At speed 0 the picture does not change, so no frame is needed.
        if (event.kind === actionui.InputKind.POINTER_DOWN) this.direction = -this.direction;
    },

    frame(surfaceId, timestamp) {
        const size = this.sizes.get(surfaceId);
        if (!size) return;
        const { width, height, scale, pixels } = size;
        // Moved by the time since the last frame, so a new speed or direction takes over from where the bands are.
        if (this.last !== null) this.offset += (timestamp - this.last) * this.speed * scale * this.direction;
        this.last = timestamp;
        const offset = Math.floor(this.offset);
        const band = Math.max(1, Math.floor(40 * scale));
        // One row, then copied down: rows are the same.
        for (let x = 0; x < width; x++) {
            const index = ((Math.floor((x + offset) / band) % PALETTE.length) + PALETTE.length) % PALETTE.length;
            const [red, green, blue] = PALETTE[index];
            pixels[x * 4] = red;
            pixels[x * 4 + 1] = green;
            pixels[x * 4 + 2] = blue;
            pixels[x * 4 + 3] = 0xFF;
        }
        for (let y = 1; y < height; y++) pixels.copyWithin(y * width * 4, 0, width * 4);
        actionui.presentPixels(surfaceId, pixels, width, height);
    },
};

const app = new actionui.Application({ name: 'HostSurface Example' });
app.setSurfaceDelegate('bands', bands);
app.registerHandler('speed', (context) => {
    const value = new actionui.Window(context.windowUuid).getDouble(6);
    if (value != null) bands.setSpeed(value);
});

const folder = fs.mkdtempSync(path.join(os.tmpdir(), 'actionui-host-surface-example-'));
const documentPath = path.join(folder, 'bands.json');
fs.writeFileSync(documentPath, JSON.stringify(DOCUMENT));

app.onDidFinishLaunching(() => {
    app.loadAndPresentWindow(documentPath, null, 'HostSurface from JavaScript');
});
app.onWillTerminate(() => fs.rmSync(folder, { recursive: true, force: true }));
app.run();
