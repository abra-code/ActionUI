'use strict';
/**
 * test_action_id_lookup.js - action ids that name built-in object properties.
 *
 * An action id comes from the ActionUI JSON. The addon keeps its handler table as a JavaScript object,
 * so an id such as "constructor", "toString" or "__defineGetter__" must not resolve to a function
 * inherited from Object.prototype: each must reach the host's handlers like any other id, and
 * "__proto__" must work as an ordinary registered id.
 *
 * Every element fires its id from onAppearActionID, with no click, as less-trusted ActionUI JSON can.
 *
 * Requirements: a graphical macOS session (the window must appear). Run: node test_action_id_lookup.js
 */

const { isMainThread } = require('worker_threads');
const { Worker } = require('worker_threads');
const fs = require('fs');
const os = require('os');
const path = require('path');

if (!isMainThread) {
    throw new Error('test_action_id_lookup.js has no worker part');
}

const actionui = require('./index.js');

const SAFETY_TIMEOUT_MS = 20000;
const UNREGISTERED_IDS = ['constructor', 'toString', 'valueOf', 'hasOwnProperty', '__defineGetter__', '__lookupGetter__'];
const REGISTERED_IDS = ['__proto__', 'test.known'];

const json = {
    type: 'VStack',
    properties: { frame: { minWidth: 300.0, minHeight: 200.0 } },
    children: [...UNREGISTERED_IDS, ...REGISTERED_IDS].map((actionID, index) => ({
        type: 'Text',
        id: index + 1,
        properties: { text: actionID, onAppearActionID: actionID },
    })),
};

const fixtureDir = fs.mkdtempSync(path.join(os.tmpdir(), 'actionui-action-id-'));
const fixturePath = path.join(fixtureDir, 'ActionIDLookup.json');
fs.writeFileSync(fixturePath, JSON.stringify(json));

const received = { byDefault: new Set(), byRegistered: new Set() };
let terminating = false;

function allArrived() {
    return UNREGISTERED_IDS.every((id) => received.byDefault.has(id)) &&
        REGISTERED_IDS.every((id) => received.byRegistered.has(id));
}

function finishSoon() {
    if (terminating || !allArrived()) return;
    terminating = true;
    setImmediate(() => app.terminate());
}

function report() {
    const failures = [];
    for (const id of UNREGISTERED_IDS) {
        const ok = received.byDefault.has(id);
        console.log(`  [${ok ? 'PASS' : 'FAIL'}] "${id}" reaches the default handler`);
        if (!ok) failures.push(id);
    }
    for (const id of REGISTERED_IDS) {
        const ok = received.byRegistered.has(id);
        console.log(`  [${ok ? 'PASS' : 'FAIL'}] "${id}" reaches its registered handler`);
        if (!ok) failures.push(id);
    }
    fs.rmSync(fixtureDir, { recursive: true, force: true });
    if (failures.length > 0) {
        console.error(`\n${failures.length} check(s) FAILED`);
        process.exit(1);
    }
    console.log('\nAll action id lookup checks PASSED.');
}

const app = new actionui.Application({ name: 'ActionUIActionIDLookupTest' });

app.setDefaultHandler((ctx) => {
    console.log(`  default handler: "${ctx.actionId}"`);
    received.byDefault.add(ctx.actionId);
    finishSoon();
});
for (const id of REGISTERED_IDS) {
    app.registerHandler(id, (ctx) => {
        console.log(`  handler for "${id}": "${ctx.actionId}"`);
        if (ctx.actionId === id) received.byRegistered.add(id);
        finishSoon();
    });
}

app.onDidFinishLaunching(() => {
    app.loadAndPresentWindow(fixturePath, null, 'Action ID Lookup Test');
});

app.onWillTerminate(() => report());

// Safety timer: every action arrives within a second or two, so a timeout is a failure. The worker
// ends the process itself with a failure status: asking the app to terminate is not enough, because
// when a JavaScript error is left pending in the addon the willTerminate callback cannot run and
// NSApplication exits with status 0.
new Worker(
    `const { workerData } = require('worker_threads');
     Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, workerData.timeoutMs);
     console.error('FAILED: not every action arrived within ' + workerData.timeoutMs + ' ms');
     process.kill(process.pid, 'SIGTERM');`,
    { eval: true, workerData: { timeoutMs: SAFETY_TIMEOUT_MS } }
).on('error', () => {}).unref();   // Where appRun returns (Windows), a passing run then ends without waiting for it.

console.log('ActionUI action id lookup test');
app.run();
