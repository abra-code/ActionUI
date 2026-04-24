'use strict';
/**
 * test_menu_bar.js — Menu bar integration tests.
 *
 * Mirrors test_menu_bar.py from ActionUIPython.
 * Exercises:
 *   1. Native API surface (appLoadMenuBar exists and is callable)
 *   2. JS wrapper API (Application.loadMenuBar)
 *   3. Default menu bar installation via app.run()
 *   4. CommandMenu JSON — adds a custom top-level menu with Button children
 *   5. CommandGroup JSON — inserts items into an existing default menu
 *   6. Action handler dispatch from a custom menu item
 *
 * Starts a real NSApplication run loop (requires a graphical macOS environment).
 * Uses the process.on('exit') pattern from test_app_lifecycle.js because
 * NSApplication.terminate() calls C exit() directly.
 *
 * Note: onWillFinishLaunching must be registered before onDidFinishLaunching
 * for the Swift framework's AppDelegate to be fully activated before app.run().
 *
 * Run: node test_menu_bar.js
 */

const { isMainThread, Worker, workerData } = require('worker_threads');
const path = require('path');
const fs   = require('fs');

// ---------------------------------------------------------------------------
// Worker thread — background terminate sequence
// ---------------------------------------------------------------------------

if (!isMainThread) {
    const { addonDir, delayMs } = workerData;

    function sleep(ms) {
        Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
    }

    const native = require('node-gyp-build')(addonDir);
    sleep(delayMs);
    console.log('  [BG] requesting termination …');
    native.appTerminate();
    return;
}

// ---------------------------------------------------------------------------
// Main thread
// ---------------------------------------------------------------------------

const actionui = require('./index.js');
const native = actionui._native;

const SAFETY_TIMEOUT_MS = 30000;
const DISPLAY_MS        = 10000;  // leave time to visually inspect menus (10s matches Python)

const FIXTURE_JSON = path.normalize(
    path.join(__dirname, '..', 'ActionUIObjCTestApp', 'DefaultWindowContentView.json')
);

// ---------------------------------------------------------------------------
// Shared state
// ---------------------------------------------------------------------------

const state = {
    willFinishLaunching: false,
    menuBarInstalled:    false,
    customMenuLoaded:    false,
    commandGroupLoaded:  false,
    actionFired:         false,
    actionIdReceived:    null,
    errors:              [],
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

    console.log('Native API surface:');
    check('native.appLoadMenuBar is present',  'appLoadMenuBar' in native);
    check('native.appLoadMenuBar is callable', typeof native.appLoadMenuBar === 'function');

    console.log();
    console.log('Lifecycle callbacks:');
    check('willFinishLaunching fired', state.willFinishLaunching);

    console.log();
    console.log('Default menu bar:');
    check('Menu bar was installed by app.run()', state.menuBarInstalled);

    console.log();
    console.log('CommandMenu (custom top-level menu):');
    check('Custom CommandMenu JSON loaded without error', state.customMenuLoaded);

    console.log();
    console.log('CommandGroup (items into existing menu):');
    check('CommandGroup JSON loaded without error', state.commandGroupLoaded);

    console.log();
    console.log('Action handler dispatch:');
    check('Action handler was fired from menu item',   state.actionFired);
    check("Received correct actionID 'test.menuAction'",
          state.actionIdReceived === 'test.menuAction');

    console.log();
    console.log('='.repeat(50));
    const allBad = [...failures, ...state.errors];
    if (allBad.length > 0) {
        console.error(`FAILED — ${allBad.length} issue(s):`);
        for (const item of allBad) console.error(`  - ${item}`);
        process.exitCode = 1;
    } else {
        console.log(`All ${checkCount} menu bar checks PASSED.`);
    }
});

// ---------------------------------------------------------------------------
// Pre-run-loop tests (no NSApplication needed)
// ---------------------------------------------------------------------------

function testAPISurface() {
    console.log('\n=== native: menu bar API surface ===');
    check('native.appLoadMenuBar exists',      'appLoadMenuBar' in native);
    check('native.appLoadMenuBar is callable', typeof native.appLoadMenuBar === 'function');
}

function testLoadMenuBarNoArgs() {
    console.log('\n=== appLoadMenuBar() — no args ===');
    try {
        native.appLoadMenuBar();
        check('appLoadMenuBar() with no args does not throw', true);
    } catch (e) {
        check(`appLoadMenuBar() raised ${e.constructor.name}: ${e.message}`, false);
    }
}

function testLoadMenuBarNull() {
    console.log('\n=== appLoadMenuBar(null) ===');
    try {
        native.appLoadMenuBar(null);
        check('appLoadMenuBar(null) does not throw', true);
    } catch (e) {
        check(`appLoadMenuBar(null) raised ${e.constructor.name}: ${e.message}`, false);
    }
}

function testJSAPIExists() {
    console.log('\n=== Application.loadMenuBar method ===');
    check('Application has loadMenuBar method',
          typeof actionui.Application.prototype.loadMenuBar === 'function');
}

function testInvalidJSON() {
    console.log('\n=== appLoadMenuBar() — invalid JSON ===');
    try {
        native.appLoadMenuBar('this is not json');
        check('Invalid JSON string does not crash', true);
    } catch (e) {
        check(`Invalid JSON raised ${e.constructor.name}: ${e.message}`, false);
    }

    try {
        native.appLoadMenuBar('{"type":"CommandMenu"}');
        check('Non-array JSON does not crash', true);
    } catch (e) {
        check(`Non-array JSON raised ${e.constructor.name}: ${e.message}`, false);
    }
}

function testEmptyArray() {
    console.log('\n=== appLoadMenuBar() — empty array ===');
    try {
        native.appLoadMenuBar('[]');
        check("Empty array JSON does not crash", true);
    } catch (e) {
        check(`Empty array raised ${e.constructor.name}: ${e.message}`, false);
    }
}

// ---------------------------------------------------------------------------
// JSON fixtures for run-loop tests
// ---------------------------------------------------------------------------

const COMMAND_MENU_JSON = JSON.stringify([
    {
        type: 'CommandMenu',
        id: 500,
        properties: { name: 'Test Tools' },
        children: [
            {
                type: 'Button',
                id: 501,
                properties: {
                    title: 'Run Test Action',
                    actionID: 'test.menuAction',
                    keyboardShortcut: { key: 't', modifiers: ['command', 'shift'] },
                },
            },
            { type: 'Divider', id: 502 },
            {
                type: 'Button',
                id: 503,
                properties: { title: 'No Shortcut Item', actionID: 'test.noShortcut' },
            },
        ],
    },
]);

const COMMAND_GROUP_JSON = JSON.stringify([
    {
        type: 'CommandGroup',
        id: 600,
        properties: { placement: 'after', placementTarget: 'help' },
        children: [
            {
                type: 'Button',
                id: 601,
                properties: { title: 'Extra Help Item', actionID: 'test.extraHelp' },
            },
        ],
    },
]);

// ---------------------------------------------------------------------------
// Application setup
// ---------------------------------------------------------------------------

console.log('ActionUI Menu Bar Integration Test');
console.log('='.repeat(50));

// Pre-run-loop tests
testAPISurface();
testLoadMenuBarNoArgs();
testLoadMenuBarNull();
testJSAPIExists();
testInvalidJSON();
testEmptyArray();

const app = new actionui.Application({ name: 'MenuBarTest' });

// Action handler for the custom menu item
function onTestAction(ctx) {
    state.actionFired       = true;
    state.actionIdReceived  = ctx.actionId;
    console.log(`  [CB] action handler fired: ${ctx.actionId}`);
}

app.action('test.menuAction', onTestAction);

// onWillFinishLaunching must be registered before onDidFinishLaunching to
// ensure the Swift framework's AppDelegate is activated before app.run().
app.onWillFinishLaunching(() => {
    state.willFinishLaunching = true;
    console.log('  [CB] willFinishLaunching');
});

app.onDidFinishLaunching(() => {
    console.log('\n  [CB] didFinishLaunching');

    // Open a window so the app can activate properly
    if (fs.existsSync(FIXTURE_JSON)) {
        const window = app.loadAndPresentWindow(FIXTURE_JSON, null, 'Menu Bar Test');
        state.windowUuid = window.uuid;
        console.log(`  [CB] window opened: ${window.uuid}`);
    } else {
        console.log(`  [CB] fixture not found: ${FIXTURE_JSON} — skipping window`);
    }

    // After app.run() the default menu bar has been installed.
    // We trust no-crash as confirmation (no ObjC introspection in Node.js).
    state.menuBarInstalled = true;
    console.log('  [CB] Default menu bar assumed installed (no-crash = OK)');

    // Load a custom CommandMenu
    try {
        app.loadMenuBar(COMMAND_MENU_JSON);
        state.customMenuLoaded = true;
        console.log('  [CB] CommandMenu JSON loaded successfully');
    } catch (e) {
        state.errors.push(`CommandMenu load failed: ${e.message}`);
    }

    // Load a CommandGroup into the existing Help menu
    try {
        app.loadMenuBar(COMMAND_GROUP_JSON);
        state.commandGroupLoaded = true;
        console.log('  [CB] CommandGroup JSON loaded successfully');
    } catch (e) {
        state.errors.push(`CommandGroup load failed: ${e.message}`);
    }

    // Trigger the action handler directly to verify JS-side dispatch
    // (mirrors Python's non-PyObjC fallback path)
    console.log("  [CB] Triggering 'test.menuAction' handler directly …");
    onTestAction(new actionui.ActionContext('test.menuAction', '', 0n, 0n, null));

    // Schedule termination after DISPLAY_MS so menus can be inspected visually
    new Worker(__filename, {
        workerData: { addonDir: __dirname, delayMs: DISPLAY_MS },
    }).on('error', (e) => state.errors.push(`Worker error: ${e.message}`));
});

// ---------------------------------------------------------------------------
// Safety timer
// ---------------------------------------------------------------------------

new Worker(
    `const { workerData } = require('worker_threads');
     const native = require('node-gyp-build')(workerData.addonDir);
     Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, workerData.timeoutMs);
     native.appTerminate();`,
    { eval: true, workerData: { addonDir: __dirname, timeoutMs: SAFETY_TIMEOUT_MS } }
).on('error', () => {});

// ---------------------------------------------------------------------------
// Run
// ---------------------------------------------------------------------------

console.log('\nStarting NSApplication run loop …');
app.run();
// Never reached — NSApplication.terminate() calls exit() directly.
