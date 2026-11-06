#!/usr/bin/env node
/*
 * A HostSurface drawn from JavaScript: a window with an ActionUI slider beside a canvas that the program renders
 * itself into a Uint8Array and presents as pixels (actionui.presentPixels). The canvas shows color bands that
 * drift over time; the slider sets their speed, and a click on the canvas flips their direction.
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
        { type: 'Slider', id: 6, properties: { value: 60, range: { min: 0, max: 240 }, actionID: 'speed' } },
    ],
};

const PALETTE = [[0x2E, 0x86, 0xDE], [0xF4, 0xA2, 0x59], [0x8C, 0xC0, 0x84], [0xE0, 0x5A, 0x6A], [0x7A, 0x5C, 0xC9]];

const bands = {
    sizes: new Map(),   // surfaceId -> { width, height, scale, pixels }
    speed: 60,          // points per second
    direction: 1,
    start: null,

    created(info) {
        this.resize(info);
        actionui.setCursor(info.surfaceId, actionui.Cursor.POINTING_HAND);
        if (info.kind !== actionui.SurfaceKind.FRAME_SINK) {
            console.log('The surface is not a frame sink: nothing to present here.');
        }
    },
    changed(info) { this.resize(info); },
    destroyed(info) { this.sizes.delete(info.surfaceId); },

    resize(info) {
        const { widthPixels: width, heightPixels: height, scale } = info;
        this.sizes.set(info.surfaceId, { width, height, scale, pixels: new Uint8Array(width * height * 4) });
    },

    input(surfaceId, event) {
        if (event.kind === actionui.InputKind.POINTER_DOWN) this.direction = -this.direction;
    },

    frame(surfaceId, timestamp) {
        const size = this.sizes.get(surfaceId);
        if (!size) return;
        if (this.start === null) this.start = timestamp;
        const { width, height, scale, pixels } = size;
        const offset = Math.floor((timestamp - this.start) * this.speed * scale * this.direction);
        const band = Math.max(1, Math.floor(40 * scale));
        // One row, then copied down: rows are the same.
        for (let x = 0; x < width; x++) {
            const index = ((Math.floor((x + offset) / band) % PALETTE.length) + PALETTE.length) % PALETTE.length;
            const [red, green, blue] = PALETTE[index];
            pixels.set([red, green, blue, 0xFF], x * 4);
        }
        for (let y = 1; y < height; y++) pixels.copyWithin(y * width * 4, 0, width * 4);
        actionui.presentPixels(surfaceId, pixels, width, height);
    },
};

const app = new actionui.Application({ name: 'HostSurface Example' });
app.setSurfaceDelegate('bands', bands);
app.registerHandler('speed', (context) => {
    const value = new actionui.Window(context.windowUuid).getDouble(6);
    if (value != null) bands.speed = value;
});

const folder = fs.mkdtempSync(path.join(os.tmpdir(), 'actionui-host-surface-example-'));
const documentPath = path.join(folder, 'bands.json');
fs.writeFileSync(documentPath, JSON.stringify(DOCUMENT));

app.onDidFinishLaunching(() => {
    app.loadAndPresentWindow(documentPath, null, 'HostSurface from JavaScript');
});
app.onWillTerminate(() => fs.rmSync(folder, { recursive: true, force: true }));
app.run();
