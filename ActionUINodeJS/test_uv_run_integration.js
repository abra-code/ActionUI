'use strict';
/**
 * test_uv_run_integration.js
 *
 * Proves that actionui_node.m's CFRunLoop / uv_run integration keeps the
 * Node.js main event loop alive while [NSApp run] blocks the main thread.
 *
 * Why a REAL external fetch target (and not a local http.createServer):
 *   A local server shares the same libuv loop as the fetch client.  Both
 *   ends depend on the CFRunLoop observer pumping uv_run(NOWAIT) often
 *   enough to cover every state transition — connect/accept, request/read,
 *   response/read — and each transition needs a separate uv__io_poll(0)
 *   pass because libuv only picks up events that are ready AT the poll
 *   call, not events scheduled by callbacks during the poll.  A local
 *   server therefore tests the I/O servicing latency as much as it tests
 *   the integration, and sluggishness on either side stalls the other.
 *   An external HTTPS endpoint isolates the client path.
 *
 * What this test proves, from inside app.onWillFinishLaunching():
 *   1. setTimeout(100ms)        → libuv timer phase fires
 *   2. setImmediate             → libuv check phase fires
 *   3. process.nextTick         → nextTick queue drained after callback
 *   4. Promise.resolve().then() → V8 microtask queue drained after callback
 *   5. https.get(example.com)   → raw TCP + TLS I/O completes (no undici)
 *   6. fetch(example.com)       → undici fetch() Promise resolves
 *
 * Interpretation:
 *   - If 3 or 4 miss: the lifecycle bridge is not draining microtasks
 *     (napi_make_callback not in effect, or process-level microtask
 *     policy is off).
 *   - If 5 passes but 6 misses: undici-specific scheduling issue.
 *   - If 5 and 6 both miss but 1 passes: the observer is firing but
 *     uv_run(NOWAIT) isn't being called often enough for TCP/TLS I/O.
 *
 * Run:   node test_uv_run_integration.js
 * Needs: graphical macOS session, internet access to example.com.
 */

const actionui = require('./index.js');
const https    = require('https');
const { Worker } = require('worker_threads');

const FETCH_URL = 'https://example.com/';
const SAFETY_TIMEOUT_MS = 20_000;

let t0 = 0;
const elapsed = () => `+${Date.now() - t0}ms`;

// Ordered so output columns align; ok=true default for entries that only
// need to "fire" (timers, microtasks) — they pass as soon as done is true.
const checks = {
    willFinishLaunching:      { done: false, detail: null, ok: true  },
    'setTimeout(100ms)':      { done: false, detail: null, ok: true  },
    'setImmediate':           { done: false, detail: null, ok: true  },
    'process.nextTick':       { done: false, detail: null, ok: true  },
    'Promise.then':           { done: false, detail: null, ok: true  },
    'https.get(example.com)': { done: false, detail: null, ok: false },
    'fetch(example.com)':     { done: false, detail: null, ok: false },
};

function mark(name, ok, detail = null) {
    const c = checks[name];
    c.done = true;
    c.ok = ok;
    c.detail = detail;
    console.log(`  [${ok ? 'PASS' : 'FAIL'}] ${name}${detail ? ' — ' + detail : ''}`);
    maybeTerminate();
}

// Terminate once both network checks have settled (pass or fail).
// The other probes are quick — if they haven't run by then, that's
// meaningful data and will show up as MISS in the summary.
let terminated = false;
function maybeTerminate() {
    if (terminated) return;
    if (checks['https.get(example.com)'].done &&
        checks['fetch(example.com)'].done) {
        terminated = true;
        console.log('  [done] both network checks settled — terminating app');
        app.terminate();
    }
}

// ---------------------------------------------------------------------------
// Exit handler — NSApplication.terminate() → exit() so this always runs
// ---------------------------------------------------------------------------

process.on('exit', () => {
    console.log('\n=== Summary ===');
    let allPass = true;
    for (const [name, r] of Object.entries(checks)) {
        const status = !r.done ? 'MISS' : r.ok ? 'PASS' : 'FAIL';
        if (status !== 'PASS') allPass = false;
        const detail = r.detail ? ' — ' + r.detail : '';
        console.log(`  ${status.padEnd(4)}  ${name}${detail}`);
    }
    console.log();
    if (!allPass) {
        console.error('FAILED');
        process.exitCode = 1;
    } else {
        console.log('All checks PASSED.');
    }
});

// ---------------------------------------------------------------------------
// Application
// ---------------------------------------------------------------------------

const app = new actionui.Application({ name: 'ActionUIUvRunTest' });

app.onWillFinishLaunching(() => {
    t0 = Date.now();
    mark('willFinishLaunching', true, elapsed());

    // 1. setTimeout — libuv timer phase
    setTimeout(() => mark('setTimeout(100ms)', true, elapsed()), 100);

    // 2. setImmediate — libuv check phase
    setImmediate(() => mark('setImmediate', true, elapsed()));

    // 3. process.nextTick — drained by napi_make_callback after this cb returns
    process.nextTick(() => mark('process.nextTick', true, elapsed()));

    // 4. Promise microtask — drained by napi_make_callback after this cb returns
    Promise.resolve().then(() => mark('Promise.then', true, elapsed()));

    // 5. Raw TLS/TCP via https.get — no undici, directly tests libuv TCP I/O
    console.log(`  [https.get] requesting ${FETCH_URL} …`);
    try {
        const req = https.get(FETCH_URL, { method: 'HEAD' }, (res) => {
            mark('https.get(example.com)', true, `status=${res.statusCode} ${elapsed()}`);
            res.resume(); // drain so the socket can close cleanly
        });
        req.on('error', (e) => mark('https.get(example.com)', false, `${e.message} ${elapsed()}`));
    } catch (e) {
        mark('https.get(example.com)', false, `sync throw: ${e.message}`);
    }

    // 6. fetch() via undici — same endpoint, exercises undici's dispatch path
    console.log(`  [fetch] requesting ${FETCH_URL} …`);
    try {
        fetch(FETCH_URL, { method: 'HEAD' })
            .then(r => mark('fetch(example.com)', true, `status=${r.status} ${elapsed()}`))
            .catch(e => mark('fetch(example.com)', false, `${e.message} ${elapsed()}`));
    } catch (e) {
        mark('fetch(example.com)', false, `sync throw: ${e.message}`);
    }
});

// ---------------------------------------------------------------------------
// Safety worker — force-terminates if the test hangs past SAFETY_TIMEOUT_MS.
// Runs on its own thread with its own libuv loop, so it's immune to main-
// loop stalls.  Uses Atomics.wait for a precise sleep.
// ---------------------------------------------------------------------------

new Worker(
    `const { workerData } = require('worker_threads');
     const native = require('node-gyp-build')(workerData.addonDir);
     Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, workerData.timeoutMs);
     console.log('  [safety] timeout reached — forcing terminate');
     native.appTerminate();`,
    { eval: true, workerData: { addonDir: __dirname, timeoutMs: SAFETY_TIMEOUT_MS } }
).on('error', () => {});

console.log('ActionUI uv_run / CFRunLoop Integration Test');
console.log('='.repeat(55));
console.log(`Fetch target    : ${FETCH_URL}`);
console.log(`Safety timeout  : ${SAFETY_TIMEOUT_MS / 1000}s`);
console.log();
console.log('Starting NSApplication run loop …');
app.run();
