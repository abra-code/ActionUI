#!/usr/bin/env node
/*
 * Integration test of the HostSurface API (setSurfaceDelegate, presentPixels, ...).
 *
 * Starts a real application run loop with a window that holds HostSurface elements, and checks:
 * - a bound delegate of a "kind": "sink" element gets "created" as a frame sink, on macOS and Linux alike;
 * - a delegate bound inside a callback takes over after it: the old one gets "destroyed" first, the new one
 *   "created" with a new surface ID;
 * - presentPixels from a worker thread, and the argument checks;
 * - on Linux, a "gl" element's render callback;
 * - window close sends "destroyed".
 *
 * Requirements: a graphical session, and the addon built (node-gyp rebuild). Run: node test_host_surface.js
 * The report runs from onWillTerminate (the run loop ends the process with exit()).
 */

'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const { Worker } = require('worker_threads');
const actionui = require('./index.js');

const IS_LINUX = process.platform === 'linux';
const SAFETY_TIMEOUT_MS = 20000;

const DOCUMENT = {
    type: 'VStack', properties: { frame: { width: 300 } }, children: [
        { type: 'HostSurface', id: 5, properties: { surfaceName: 'js.canvas', kind: 'sink', frame: { width: 200, height: 120 } } },
        ...(IS_LINUX ? [{ type: 'HostSurface', id: 6,
            properties: { surfaceName: 'js.gl', kind: 'gl', frame: { width: 80, height: 60 } } }]
            // No kind: on macOS the surface stays a Metal layer, which takes no presented frames.
            : [{ type: 'HostSurface', id: 8, properties: { surfaceName: 'js.metal', frame: { width: 80, height: 60 } } }]),
        { type: 'HostSurface', id: 7, properties: { surfaceName: 'js.throws', frame: { width: 40, height: 40 } } },
    ],
};

const state = {
    first: [], second: [], glEvents: [], glRenders: 0, frames: 0,
    presentOnWorker: null, presentErrors: [], cursorSet: null, thrower: null, errors: [],
};

const second = {
    created(info) {
        state.second.push(['created', info]);
        state.cursorSet = actionui.setCursor(info.surfaceId, actionui.Cursor.CROSSHAIR);
        actionui.requestFrame(info.surfaceId);
        const { widthPixels: width, heightPixels: height } = info;
        // From a worker thread: presentPixels never waits for the main thread.
        const shared = new SharedArrayBuffer(width * height * 4);
        new Uint8Array(shared).fill(0x80);
        const worker = new Worker(`
            const { parentPort, workerData } = require('worker_threads');
            const actionui = require(workerData.index);
            const pixels = new Uint8Array(workerData.shared);
            parentPort.postMessage(actionui.presentPixels(workerData.id, pixels, workerData.width, workerData.height));
        `, { eval: true, workerData: { index: path.join(__dirname, 'index.js'), shared, id: info.surfaceId, width, height } });
        worker.on('message', (shown) => { state.presentOnWorker = shown; });
        worker.on('error', (error) => { state.errors.push(`worker: ${error.message}`); });
        const pixels = new Uint8Array(width * height * 4);
        for (const bad of [
            () => actionui.presentPixels(info.surfaceId, new Uint8Array(7), 2, 1),
            () => actionui.presentPixels(info.surfaceId, pixels, 0, 1),
            () => actionui.presentPixels(info.surfaceId, 'not pixels', 2, 1),
        ]) {
            try {
                bad();
                state.presentErrors.push('no error');
            } catch (error) {
                state.presentErrors.push(error.name);
            }
        }
    },
    suspended(info) { state.second.push(['suspended', info]); },
    resumed(info) { state.second.push(['resumed', info]); },
    frame() { state.frames += 1; },
    destroyed(info) { state.second.push(['destroyed', info]); },
};

const first = {
    created(info) {
        state.first.push(['created', info]);
        // Rebinding inside a callback: the change waits until this returns.
        actionui.setSurfaceDelegate('js.canvas', second);
        state.first.push(['rebound', null]);
    },
    destroyed(info) { state.first.push(['destroyed', info]); },
};

const metalClient = {
    created(info) {
        const shown = actionui.presentPixels(info.surfaceId, new Uint8Array(16), 2, 2);
        state.metal = [info.kind, info.handle, shown];
    },
};

const glClient = {
    created(info) { state.glEvents.push(['created', info.kind]); actionui.requestFrame(info.surfaceId); },
    render() { state.glRenders += 1; },
    destroyed(info) { state.glEvents.push(['destroyed', info.kind]); },
};

const failures = [];
function check(what, passed) {
    console.log(`  ${passed ? 'ok  ' : 'FAIL'} ${what}`);
    if (!passed) failures.push(what);
}

function report() {
    console.log('\nResults');
    const firstKinds = state.first.map(([kind]) => kind);
    const secondKinds = state.second.map(([kind]) => kind);
    check(`the first delegate got created, rebound, then destroyed (${firstKinds})`,
        JSON.stringify(firstKinds) === JSON.stringify(['created', 'rebound', 'destroyed']));
    const firstInfo = state.first.length ? state.first[0][1] : null;
    check(`created as a frame sink (${firstInfo && firstInfo.kind})`,
        firstInfo && firstInfo.kind === actionui.SurfaceKind.FRAME_SINK);
    if (firstInfo) {
        check(`the size of the frame, 200 x 120 points (${firstInfo.widthPoints} x ${firstInfo.heightPoints})`,
            firstInfo.widthPoints === 200 && firstInfo.heightPoints === 120);
        check('a nonzero pixel size', firstInfo.widthPixels > 0 && firstInfo.heightPixels > 0);
        check('no handle for a frame sink', firstInfo.handle === null);
    }
    const secondCreated = state.second.filter(([kind]) => kind === 'created').map(([, info]) => info);
    check('the second delegate got created', secondCreated.length === 1);
    if (secondCreated.length && firstInfo) {
        check('with a new surface ID', secondCreated[0].surfaceId !== firstInfo.surfaceId);
    }
    check(`the second delegate got destroyed at window close (${secondKinds})`, secondKinds[secondKinds.length - 1] === 'destroyed');
    check(`presentPixels from a worker returned true (${state.presentOnWorker})`, state.presentOnWorker === true);
    check(`presentPixels refuses a short buffer, a zero width, and a string (${state.presentErrors})`,
        JSON.stringify(state.presentErrors) === JSON.stringify(['RangeError', 'RangeError', 'TypeError']));
    check(`setCursor on a live surface returned true (${state.cursorSet})`, state.cursorSet === true);
    if (!secondKinds.includes('suspended')) {
        check(`a requested frame came (${state.frames})`, state.frames >= 1);
    } else {
        console.log('  (the window was not visible, so no frame was expected)');
    }
    check(`a bridge that threw a Symbol got its later calls (${state.thrower})`,
        state.thrower !== null && state.thrower[0] === 'created' && state.thrower[state.thrower.length - 1] === 'destroyed');
    if (!IS_LINUX) {
        const metal = state.metal;
        check(`an element with no kind is a Metal layer with a handle, and takes no frames (${metal})`,
            metal != null && metal[0] === actionui.SurfaceKind.METAL_LAYER && typeof metal[1] === 'bigint'
            && metal[1] !== 0n && metal[2] === false);
    }
    if (IS_LINUX) {
        check(`the GL client got created and destroyed (${JSON.stringify(state.glEvents)})`,
            JSON.stringify(state.glEvents) === JSON.stringify([['created', actionui.SurfaceKind.GL_AREA],
                ['destroyed', actionui.SurfaceKind.GL_AREA]]));
        check(`the GL client's render was called (${state.glRenders})`, state.glRenders >= 1);
    }
    for (const error of state.errors) check(error, false);
    console.log(`\n${failures.length ? 'FAILED' : 'PASSED'}: ${failures.length} failure(s)`);
    if (failures.length) process.exit(1);
}

console.log('ActionUI HostSurface Integration Test (Node.js)');
const app = new actionui.Application({ name: 'HostSurfaceTest' });
actionui.setSurfaceDelegate('js.canvas', first);
if (IS_LINUX) app.setSurfaceDelegate('js.gl', glClient);
else app.setSurfaceDelegate('js.metal', metalClient);

const folder = fs.mkdtempSync(path.join(os.tmpdir(), 'actionui-hostsurface-test-'));
const documentPath = path.join(folder, 'HostSurface.json');
fs.writeFileSync(documentPath, JSON.stringify(DOCUMENT));

app.onDidFinishLaunching(() => {
    const window = app.loadAndPresentWindow(documentPath, null, 'HostSurface Test');
    setTimeout(() => {
        // A raw bridge (without index.js's try/catch) that throws a Symbol, which cannot be shown as text, at every
        // call: that exception must not stay pending, or the next call into JS fails (a callback is lost, or the
        // set and remove calls below throw it).
        const kinds = [];
        try {
            actionui._native.hostSurfaceSetDelegate('js.throws', (kind) => {
                kinds.push(kind);
                throw Symbol('thrown');
            });
            actionui.removeSurfaceDelegate('js.throws');
        } catch (error) {
            state.errors.push(`after a bridge threw a Symbol: ${String(error)}`);
        }
        state.thrower = kinds;
    }, 1000);
    setTimeout(() => {
        app.closeWindow(window.uuid);
        setTimeout(() => app.terminate(), 500);
    }, 2000);
});

app.onWillTerminate(() => {
    fs.rmSync(folder, { recursive: true, force: true });
    report();
});

setTimeout(() => {
    state.errors.push(`safety timeout (${SAFETY_TIMEOUT_MS} ms): the app did not terminate`);
    app.terminate();
}, SAFETY_TIMEOUT_MS).unref?.();

app.run();
