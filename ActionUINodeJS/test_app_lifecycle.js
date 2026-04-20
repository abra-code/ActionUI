'use strict';
/**
 * test_app_lifecycle.js — App lifecycle integration tests.
 *
 * Mirrors test_app_lifecycle.py from ActionUIPython.
 * Starts a real NSApplication run loop, exercises all major lifecycle and
 * window-management callbacks, and terminates automatically.
 *
 * Requirements
 * ------------
 * - Must run in a graphical macOS environment (attached screen / window server).
 * - Run: node test_app_lifecycle.js
 *
 * Design note
 * -----------
 * NSApplication.terminate() calls C exit() directly — app.run() never returns.
 * Assertions are registered via process.on('exit', ...) which fires via Node.js's
 * C-level atexit handler, same mechanism as Python's atexit module.
 *
 * Background close/terminate is handled by a worker thread (mirrors Python's
 * threading.Thread) since the main thread is blocked inside [NSApp run].
 */

const { isMainThread, Worker, workerData } = require('worker_threads');
const path = require('path');
const fs   = require('fs');

// ---------------------------------------------------------------------------
// Worker thread — background close/terminate sequence
// ---------------------------------------------------------------------------

if (!isMainThread) {
    const { uuid, addonDir, delayMs } = workerData;

    function sleep(ms) {
        Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
    }

    const native = require('node-gyp-build')(addonDir);

    sleep(delayMs);
    console.log('  [BG] closing window …');
    native.appCloseWindow(uuid);
    sleep(500);
    console.log('  [BG] requesting termination …');
    native.appTerminate();
    // Worker exits here; main thread is terminated by appTerminate()
    return;
}

// ---------------------------------------------------------------------------
// Main thread
// ---------------------------------------------------------------------------

const actionui = require('./index.js');

const FIXTURE_JSON = path.normalize(
    path.join(__dirname, '..', 'ActionUIObjCTestApp', 'DefaultWindowContentView.json')
);
const SAFETY_TIMEOUT_MS = 15000;
const WINDOW_DISPLAY_MS = 1000;

const state = {
    willFinishLaunching:    false,
    didFinishLaunching:     false,
    willBecomeActive:       false,
    didBecomeActive:        false,
    willTerminate:          false,
    shouldTerminateCalled:  false,
    shouldTerminateResult:  null,
    windowOpenedUuid:       null,
    windowPresentUuid:      null,
    windowClosedUuid:       null,
    errors:                 [],
};

let checkCount = 0;
const failures = [];

function check(label, condition) {
    checkCount++;
    const status = condition ? 'PASS' : 'FAIL';
    console.log(`  [${status}] ${label}`);
    if (!condition) failures.push(label);
    return condition;
}

// ---------------------------------------------------------------------------
// Exit handler — runs after NSApplication.terminate() → exit()
// ---------------------------------------------------------------------------

process.on('exit', () => {
    console.log('\nNSApplication exited — running assertions …\n');

    if (state.errors.length > 0) {
        for (const err of state.errors) console.log(`  [ERROR] ${err}`);
        console.log();
    }

    console.log('Lifecycle callbacks:');
    check('willFinishLaunching fired',    state.willFinishLaunching);
    check('didFinishLaunching fired',     state.didFinishLaunching);
    check('willBecomeActive fired',       state.willBecomeActive);
    check('didBecomeActive fired',        state.didBecomeActive);
    check('shouldTerminate was called',   state.shouldTerminateCalled);
    check('shouldTerminate returned true', state.shouldTerminateResult === true);
    check('willTerminate fired',          state.willTerminate);

    console.log();
    console.log('Window lifecycle:');
    check('window was opened (UUID recorded)', state.windowOpenedUuid !== null);
    check('windowWillPresent fired',           state.windowPresentUuid !== null);
    if (state.windowPresentUuid && state.windowOpenedUuid) {
        check('windowWillPresent UUID matches opened UUID',
              state.windowPresentUuid === state.windowOpenedUuid);
    }
    check('windowWillClose fired', state.windowClosedUuid !== null);
    if (state.windowOpenedUuid && state.windowClosedUuid) {
        check('windowWillClose UUID matches opened UUID',
              state.windowClosedUuid === state.windowOpenedUuid);
    }

    console.log();
    console.log('Window registry cleanup:');
    check('_windows map is empty after window closes', app._windows.size === 0);

    console.log();
    console.log('='.repeat(50));
    const allBad = [...failures, ...state.errors];
    if (allBad.length > 0) {
        console.error(`FAILED — ${allBad.length} issue(s):`);
        for (const item of allBad) console.error(`  - ${item}`);
        process.exitCode = 1;
    } else {
        console.log(`All ${checkCount} lifecycle integration checks PASSED.`);
    }
});

// ---------------------------------------------------------------------------
// Pre-flight checks
// ---------------------------------------------------------------------------

console.log('ActionUI App Lifecycle Integration Test');
console.log('='.repeat(50));

if (!fs.existsSync(FIXTURE_JSON)) {
    console.error(`ERROR: fixture not found: ${FIXTURE_JSON}`);
    process.exit(1);
}

console.log(`Fixture : ${FIXTURE_JSON}`);
console.log(`Timeout : ${SAFETY_TIMEOUT_MS / 1000}s`);
console.log();

// ---------------------------------------------------------------------------
// Application + lifecycle handlers
// ---------------------------------------------------------------------------

const app = new actionui.Application({ name: 'ActionUILifecycleTest' });

app.onWillFinishLaunching(() => {
    state.willFinishLaunching = true;
    console.log('  [CB] willFinishLaunching');
});

app.onDidFinishLaunching(() => {
    state.didFinishLaunching = true;
    console.log('  [CB] didFinishLaunching');

    if (!fs.existsSync(FIXTURE_JSON)) {
        state.errors.push(`Fixture disappeared: ${FIXTURE_JSON}`);
        app.terminate();
        return;
    }

    const window = app.loadAndPresentWindow(FIXTURE_JSON, null, 'ActionUI Lifecycle Test');
    state.windowOpenedUuid = window.uuid;
    console.log(`  [CB] window opened: ${window.uuid}`);

    new Worker(__filename, {
        workerData: {
            uuid:     window.uuid,
            addonDir: __dirname,
            delayMs:  WINDOW_DISPLAY_MS,
        },
    }).on('error', (e) => state.errors.push(`Worker error: ${e.message}`));
});

app.onWillBecomeActive(() => {
    state.willBecomeActive = true;
    console.log('  [CB] willBecomeActive');
});

app.onDidBecomeActive(() => {
    state.didBecomeActive = true;
    console.log('  [CB] didBecomeActive');
});

app.onWindowWillPresent((window) => {
    state.windowPresentUuid = window.uuid;
    console.log(`  [CB] windowWillPresent: ${window.uuid}`);
    window.setString(1, 'Hello from Node.js!');
    console.log("  [CB] view 1 ← 'Hello from Node.js!'");
});

app.onWindowWillClose((window) => {
    state.windowClosedUuid = window.uuid;
    console.log(`  [CB] windowWillClose: ${window.uuid}`);
});

app.onShouldTerminate(() => {
    state.shouldTerminateCalled = true;
    state.shouldTerminateResult = true;
    console.log('  [CB] shouldTerminate → true');
    return true;
});

app.onWillTerminate(() => {
    state.willTerminate = true;
    console.log('  [CB] willTerminate');
});

// ---------------------------------------------------------------------------
// Safety timer — worker terminates app if it doesn't exit within timeout
// ---------------------------------------------------------------------------

new Worker(
    `const { workerData } = require('worker_threads');
     const native = require('node-gyp-build')(workerData.addonDir);
     Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, workerData.timeoutMs);
     native.appTerminate();`,
    { eval: true, workerData: { addonDir: __dirname, timeoutMs: SAFETY_TIMEOUT_MS } }
).on('error', () => {});

// ---------------------------------------------------------------------------
// Run — app.run() blocks; exit handler reports results
// ---------------------------------------------------------------------------

console.log('Starting NSApplication run loop …');
app.run();
// Never reached — NSApplication.terminate() calls exit() directly.
