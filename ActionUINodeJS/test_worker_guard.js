'use strict';
/**
 * test_worker_guard.js - Calls that store a callback, and appRun, belong to the main thread.
 *
 * ActionUI calls every stored callback on the main thread, with the main thread's environment.
 * A first worker loads the addon before the main thread does; a second one starts after the
 * main thread loaded it. In each worker, those calls throw, while a call that only goes through
 * to C still works. On the main thread they work, the logger set there is called, and neither
 * worker's exit stops them working.
 *
 * Tests the N-API binding layer directly without a running NSApplication.
 *
 * Run: node test_worker_guard.js
 */

const { isMainThread, Worker, workerData, parentPort } = require('worker_threads');

const fn = () => {};
const GUARDED = [
    ['setLogger', [fn]],
    ['registerActionHandler', ['worker.action', fn]],
    ['unregisterActionHandler', ['worker.action']],
    ['setDefaultActionHandler', [fn]],
    ['appSetWillFinishLaunching', [fn]],
    ['appSetDidFinishLaunching', [fn]],
    ['appSetWillBecomeActive', [fn]],
    ['appSetDidBecomeActive', [fn]],
    ['appSetWillResignActive', [fn]],
    ['appSetDidResignActive', [fn]],
    ['appSetWillTerminate', [fn]],
    ['appSetShouldTerminate', [() => true]],
    ['appSetWindowWillClose', [fn]],
    ['appSetWindowWillPresent', [fn]],
    ['appRun', []],
];

// ---------------------------------------------------------------------------
// Worker thread - tries every guarded call, then waits for the main thread
// ---------------------------------------------------------------------------

if (!isMainThread && workerData.probe) {
    // Linux probe: this worker is the first to load the addon, which must be refused.
    try {
        require('node-gyp-build')(workerData.addonDir);
        parentPort.postMessage({ refused: null });
    } catch (e) {
        parentPort.postMessage({ refused: e.message });
    }
    return;
}

if (!isMainThread) {
    const native = require('node-gyp-build')(workerData.addonDir);
    const results = GUARDED.map(([name, args]) => {
        try {
            native[name](...args);
            return { name, threw: false };
        } catch (e) {
            return { name, threw: true, message: e.message };
        }
    });
    parentPort.postMessage({ results, version: native.getVersion() });
    // Stay alive while the main thread checks its calls, so both states exist.
    Atomics.wait(new Int32Array(workerData.gate), 0, 0, 10000);
    return;
}

// ---------------------------------------------------------------------------
// Main thread
// ---------------------------------------------------------------------------

let failures = [];
let native = null;

function check(label, condition) {
    if (condition) {
        console.log(`  [PASS] ${label}`);
    } else {
        console.error(`  [FAIL] ${label}`);
        failures.push(label);
    }
    return condition;
}

function checkMainThreadCalls(when) {
    const logged = [];
    try {
        native.setLogger((msg, level) => logged.push(msg));
        native.log(`main thread log ${when}`, native.LOG_INFO);
        native.setLogger(null);
        check(`setLogger works on the main thread ${when}`, true);
    } catch (e) {
        check(`setLogger works on the main thread ${when} (${e.message})`, false);
    }
    check(`the main thread's logger is called ${when}`, logged.some((m) => m.includes(`main thread log ${when}`)));
    try {
        native.registerActionHandler('main.action', fn);
        native.unregisterActionHandler('main.action');
        native.setDefaultActionHandler(fn);
        native.setDefaultActionHandler(null);
        native.appSetWillTerminate(fn);
        native.appSetWillTerminate(null);
        check(`action and lifecycle setters work on the main thread ${when}`, true);
    } catch (e) {
        check(`action and lifecycle setters work on the main thread ${when} (${e.message})`, false);
    }
}

/* Starts a worker. When it reports, checks its results, runs onReport, then lets it exit;
 * onExit runs after it exited. */
function runWorker(title, onReport, onExit) {
    const gate = new SharedArrayBuffer(4);
    const worker = new Worker(__filename, { workerData: { addonDir: __dirname, gate } });
    worker.on('error', (e) => check(`worker error: ${e.message}`, false));
    worker.on('message', (msg) => {
        console.log(`\n=== ${title} ===`);
        for (const r of msg.results) {
            check(`${r.name} throws in a worker`, r.threw && /must be called on the main thread/.test(r.message || ''));
        }
        check('getVersion works in a worker', typeof msg.version === 'string' && msg.version.length > 0);
        onReport();
        const flag = new Int32Array(gate);
        Atomics.store(flag, 0, 1);
        Atomics.notify(flag, 0);
    });
    worker.on('exit', onExit);
}

function finish() {
    console.log('\n' + '='.repeat(55));
    if (failures.length === 0) {
        console.log('All worker guard tests PASSED.');
    } else {
        console.error(`FAILED - ${failures.length} check(s):`);
        for (const f of failures) console.error(`  - ${f}`);
        process.exit(1);
    }
}

/* Linux, in a process of its own (the refusal lasts for the process): a worker loads the addon
 * first; it and then the main thread are refused with an error naming the main thread. */
function workerFirstProbe() {
    const worker = new Worker(__filename, { workerData: { addonDir: __dirname, probe: true } });
    worker.on('message', (msg) => {
        let mainRefused = null;
        try {
            require('./index.js');
        } catch (e) {
            mainRefused = e.message;
        }
        // Written at once: what goes wrong in this process must not take the answer with it.
        require('fs').writeSync(1, JSON.stringify({ worker: msg.refused, main: mainRefused }) + '\n');
    });
}

function checkWorkerFirstLoadIsRefused() {
    console.log('\n=== Linux: a worker that loads the addon before the main thread ===');
    const { spawnSync } = require('child_process');
    const probe = spawnSync(process.execPath, [__filename, '--worker-first-probe'], { encoding: 'utf8', timeout: 15000 });
    const line = (probe.stdout || '').split('\n').find((l) => l.startsWith('{'));
    const result = line ? JSON.parse(line) : {};
    check('the worker is refused, naming the main thread', /loaded on the main thread/.test(result.worker || ''));
    check('the main thread is refused after it', /loaded on the main thread/.test(result.main || ''));
}

function main() {
    const safety = setTimeout(() => {
        console.error('  [FAIL] the workers did not finish within 20 s');
        process.exit(1);
    }, 20000);

    if (process.platform === 'linux') {
        // On Linux the addon must be loaded on the main thread first (src/actionui_node.c,
        // note_loading_thread): the first scenario below is refused, and checked as such.
        checkWorkerFirstLoadIsRefused();
        console.log('\n=== On the main thread, before any worker ===');
        native = require('./index.js')._native;
        checkMainThreadCalls('before any worker');
        runWorker('In a worker started after the main thread loaded the addon', () => {
            console.log('\n=== On the main thread, the worker still running ===');
            checkMainThreadCalls('while the worker runs');
        }, () => {
            clearTimeout(safety);
            console.log('\n=== On the main thread, after the worker exited ===');
            checkMainThreadCalls('after the worker exited');
            finish();
        });
        return;
    }

    runWorker('In a worker that loaded the addon before the main thread', () => {
        console.log('\n=== On the main thread, the first worker still running ===');
        native = require('./index.js')._native;
        checkMainThreadCalls('while the first worker runs');
    }, () => {
        console.log('\n=== On the main thread, after the first worker exited ===');
        if (!check('the main thread loaded the addon', native !== null)) {
            clearTimeout(safety);
            finish();
            return;
        }
        checkMainThreadCalls('after the first worker exited');

        runWorker('In a worker started after the main thread loaded the addon', () => {
            console.log('\n=== On the main thread, the second worker still running ===');
            checkMainThreadCalls('while the second worker runs');
        }, () => {
            clearTimeout(safety);
            console.log('\n=== On the main thread, after the second worker exited ===');
            checkMainThreadCalls('after the second worker exited');
            finish();
        });
    });
}

if (process.argv.includes("--worker-first-probe")) {
    workerFirstProbe();
} else {
    main();
}
