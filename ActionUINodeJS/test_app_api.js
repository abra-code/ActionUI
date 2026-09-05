'use strict';
/**
 * test_app_api.js — App API and native module surface smoke tests.
 *
 * Mirrors test_app_api.py from ActionUIPython.
 * Tests the N-API binding layer and JS wrapper without a running NSApplication.
 *
 * Run: node test_app_api.js
 * (Must be run after test_native.js or in isolation — both create an Application.)
 */

const actionui = require('./index.js');
const native = actionui._native;

let failures = [];

function check(label, condition) {
    if (condition) {
        console.log(`  [PASS] ${label}`);
    } else {
        console.error(`  [FAIL] ${label}`);
        failures.push(label);
    }
    return condition;
}

// ---------------------------------------------------------------------------
// Native module API surface
// ---------------------------------------------------------------------------
function testNativeAPISurface() {
    console.log('\n=== Native module: API surface ===');

    const expected = [
        // Version / errors
        'getVersion', 'getLastError', 'clearError',
        // Logging
        'setLogger', 'log',
        // Remote bridge
        'appStartRemoteServer', 'appStopRemoteServer', 'appRemoteServerEndpoint',
        'appRemoteServerToken',
        // Action handlers
        'registerActionHandler', 'unregisterActionHandler', 'setDefaultActionHandler',
        // Type-specific setters
        'setIntValue', 'setDoubleValue', 'setBoolValue', 'setStringValue',
        // Type-specific getters
        'getIntValue', 'getDoubleValue', 'getBoolValue', 'getStringValue',
        // Generic value access
        'setValueFromString', 'getValueAsString', 'setValueFromJSON', 'getValueAsJSON',
        // Element column count
        'getElementColumnCount',
        // Element rows
        'getElementRowsJSON', 'clearElementRows', 'setElementRowsJSON', 'appendElementRowsJSON',
        // Element properties
        'getElementPropertyJSON', 'setElementPropertyJSON',
        // Element state
        'getElementStateJSON', 'getElementStateString',
        'setElementStateJSON', 'setElementStateFromString',
        // Element info
        'getElementInfoJSON',
        // Modal presentation
        'presentModal', 'dismissModal',
        'presentAlert', 'presentConfirmationDialog', 'dismissDialog',
        'presentToast', 'dismissToast',
        // UI loading
        'loadHostingController',
        // App lifecycle setters
        'appSetWillFinishLaunching', 'appSetDidFinishLaunching',
        'appSetWillBecomeActive',    'appSetDidBecomeActive',
        'appSetWillResignActive',    'appSetDidResignActive',
        'appSetWillTerminate',       'appSetShouldTerminate',
        'appSetWindowWillClose',     'appSetWindowWillPresent',
        // App control
        'appSetName', 'appSetIcon',
        'appRun', 'appTerminate',
        'appLoadAndPresentWindow', 'appCloseWindow',
        'appLoadMenuBar',
        'appRunOpenPanel', 'appRunSavePanel', 'appRunAlert',
        // Log level constants
        'LOG_ERROR', 'LOG_WARNING', 'LOG_INFO', 'LOG_DEBUG', 'LOG_VERBOSE',
    ];

    for (const name of expected) {
        check(`native.${name} is present`, name in native);
    }
}

// ---------------------------------------------------------------------------
// JS wrapper API surface
// ---------------------------------------------------------------------------
function testJSAPISurface(app, win) {
    console.log('\n=== JS wrapper: Application method surface ===');
    const appMethods = [
        'action', 'registerHandler', 'unregisterHandler', 'setDefaultHandler',
        'onWillFinishLaunching', 'onDidFinishLaunching',
        'onWillBecomeActive', 'onDidBecomeActive',
        'onWillResignActive', 'onDidResignActive',
        'onWillTerminate', 'onShouldTerminate',
        'onWindowWillClose', 'onWindowWillPresent',
        'run', 'terminate',
        'loadAndPresentWindow', 'closeWindow',
        'loadMenuBar', 'openPanel', 'savePanel', 'alert',
    ];
    for (const m of appMethods) {
        check(`app.${m} is a function`, typeof app[m] === 'function');
    }

    console.log('\n=== JS wrapper: Window method surface ===');
    const winMethods = [
        'setInt', 'setDouble', 'setBool', 'setString',
        'getInt', 'getDouble', 'getBool', 'getString',
        'setValue', 'getValue',
        'getColumnCount',
        'getRows', 'setRows', 'appendRows', 'clearRows',
        'getProperty', 'setProperty',
        'getState', 'getStateString', 'setState', 'setStateFromString',
        'getElementInfo',
        'presentModal', 'dismissModal',
        'presentAlert', 'presentConfirmationDialog', 'dismissDialog',
        'presentToast', 'dismissToast',
    ];
    for (const m of winMethods) {
        check(`window.${m} is a function`, typeof win[m] === 'function');
    }
}

// ---------------------------------------------------------------------------
// Log level constants
// ---------------------------------------------------------------------------
function testLogLevelConstants() {
    console.log('\n=== Log level constants ===');
    for (const [name, value] of Object.entries(actionui.LogLevel)) {
        check(`LogLevel.${name} is a number`, typeof value === 'number');
    }
}

// ---------------------------------------------------------------------------
// Lifecycle registration / chaining
// ---------------------------------------------------------------------------
function testLifecycleRegistration(app) {
    console.log('\n=== Lifecycle registration and chaining ===');

    const noop = () => {};
    // All setters return app for chaining
    const chain = app
        .onWillFinishLaunching(noop)
        .onDidFinishLaunching(noop)
        .onWillBecomeActive(noop)
        .onDidBecomeActive(noop)
        .onWillResignActive(noop)
        .onDidResignActive(noop)
        .onWillTerminate(noop)
        .onShouldTerminate(() => true)
        .onWindowWillClose(noop)
        .onWindowWillPresent(noop);

    check('Lifecycle setters are chainable (return app)', chain === app);

    // action() is also chainable
    const chain2 = app.action('test.chain', noop);
    check('app.action() is chainable (returns app)', chain2 === app);
    app.unregisterHandler('test.chain');
}

// ---------------------------------------------------------------------------
// Handler deregistration
// ---------------------------------------------------------------------------
function testDeregistration() {
    console.log('\n=== Handler deregistration ===');

    try {
        native.appSetWillFinishLaunching(() => {});
        native.appSetWillFinishLaunching(null);
        check('appSetWillFinishLaunching(null) clears without throw', true);
    } catch (e) { check('appSetWillFinishLaunching(null) clears without throw', false); }

    try {
        native.appSetShouldTerminate(() => true);
        native.appSetShouldTerminate(null);
        check('appSetShouldTerminate(null) clears without throw', true);
    } catch (e) { check('appSetShouldTerminate(null) clears without throw', false); }

    try {
        native.appSetWindowWillClose(() => {});
        native.appSetWindowWillClose(null);
        check('appSetWindowWillClose(null) clears without throw', true);
    } catch (e) { check('appSetWindowWillClose(null) clears without throw', false); }
}

// ---------------------------------------------------------------------------
// Type checking — non-function must throw
// ---------------------------------------------------------------------------
function testTypeChecking() {
    console.log('\n=== Type checking (non-function must throw TypeError) ===');

    const setters = [
        ['appSetWillFinishLaunching', native.appSetWillFinishLaunching.bind(native)],
        ['appSetShouldTerminate',     native.appSetShouldTerminate.bind(native)],
        ['appSetWindowWillClose',     native.appSetWindowWillClose.bind(native)],
        ['setLogger',                 native.setLogger.bind(native)],
    ];

    for (const [name, setter] of setters) {
        let threw = false;
        try { setter(42); } catch { threw = true; }
        check(`native.${name}(42) throws`, threw);
    }
}

// ---------------------------------------------------------------------------
// Menu bar API
// ---------------------------------------------------------------------------
function testMenuBarAPI(app) {
    console.log('\n=== Menu bar API ===');

    try { app.loadMenuBar();     check('loadMenuBar() with no args does not throw', true); }
    catch { check('loadMenuBar() with no args does not throw', false); }

    try { app.loadMenuBar(null); check('loadMenuBar(null) does not throw', true); }
    catch { check('loadMenuBar(null) does not throw', false); }

    const validJSON = JSON.stringify([{
        type: 'CommandMenu', id: 900,
        properties: { name: 'Test' },
        children: [{ type: 'Button', id: 901, properties: { title: 'Item', actionID: 'test.item' } }],
    }]);
    try { app.loadMenuBar(validJSON); check('loadMenuBar(valid CommandMenu JSON) does not throw', true); }
    catch { check('loadMenuBar(valid CommandMenu JSON) does not throw', false); }

    const groupJSON = JSON.stringify([{
        type: 'CommandGroup', id: 910,
        properties: { placement: 'after', placementTarget: 'help' },
        children: [{ type: 'Divider', id: 911 }],
    }]);
    try { app.loadMenuBar(groupJSON); check('loadMenuBar(valid CommandGroup JSON) does not throw', true); }
    catch { check('loadMenuBar(valid CommandGroup JSON) does not throw', false); }

    try { app.loadMenuBar('not valid json'); check('loadMenuBar(invalid JSON) does not crash', true); }
    catch { check('loadMenuBar(invalid JSON) does not crash', false); }

    try { app.loadMenuBar('[]'); check("loadMenuBar('[]') does not throw", true); }
    catch { check("loadMenuBar('[]') does not throw", false); }

    try { native.appLoadMenuBar('{"type":"CommandMenu"}'); check('native non-array JSON does not crash', true); }
    catch { check('native non-array JSON does not crash', false); }
}

// ---------------------------------------------------------------------------
// File panel API surface
// ---------------------------------------------------------------------------
function testFilePanelAPI(app) {
    console.log('\n=== File panel API surface ===');
    check('app.openPanel is a function', typeof app.openPanel === 'function');
    check('app.savePanel is a function', typeof app.savePanel === 'function');
    check('native.appRunOpenPanel is a function', typeof native.appRunOpenPanel === 'function');
    check('native.appRunSavePanel is a function', typeof native.appRunSavePanel === 'function');
    check('native.appRunAlert is a function', typeof native.appRunAlert === 'function');
}

// ---------------------------------------------------------------------------
// Window registry
// ---------------------------------------------------------------------------
function testWindowRegistry(app) {
    console.log('\n=== Window registry ===');
    check('app._windows starts as a Map', app._windows instanceof Map);
    check('app._windows starts empty', app._windows.size === 0);

    try {
        app.closeWindow('00000000-0000-0000-0000-000000000000');
        check('closeWindow(unknown UUID) does not throw', true);
    } catch { check('closeWindow(unknown UUID) does not throw', false); }
}

// One request over the bridge from a separate process, with `env` as its whole environment.
// Returns the error code as a string, 'result', 'closed' when the host hung up without
// answering, or 'no-reply' when nothing came back in time.
//
// A child rather than an in-process socket, because the environment a child is given is the
// thing under test. Synchronous, so it drops into the smoke tests as an ordinary check.
const REMOTE_PROBE = [
    "const net = require('net');",
    "const s = net.connect(process.env.ACTIONUI_REMOTE_ENDPOINT);",
    "let out = 'no-reply', buf = '', done = false;",
    "function finish() { if (done) return; done = true; try { s.destroy(); } catch (e) {}",
    "                    console.log(out); process.exit(0); }",
    "s.on('connect', () => {",
    "  const params = {};",
    "  if (process.env.ACTIONUI_REMOTE_TOKEN) params.token = process.env.ACTIONUI_REMOTE_TOKEN;",
    "  s.write(JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'actionui.hello', params }) + '\\n');",
    // The clock starts once the request is on its way, not when this script does, so a slow
    // start cannot be mistaken for the host declining to answer.
    "  setTimeout(finish, 700);",
    "});",
    "s.on('data', (d) => {",
    "  buf += d.toString();",
    "  if (buf.indexOf('\\n') < 0) return;",
    "  const reply = JSON.parse(buf.split('\\n')[0]);",
    "  out = reply.error ? String(reply.error.code) : 'result';",
    "  finish();",
    "});",
    // A host that hangs up without answering is a different failure from one that accepted the
    // request and left it on a main thread nobody is servicing. Reporting both as 'no-reply'
    // would let the first pass the acceptance check below.
    "s.on('end', () => { if (out === 'no-reply') out = 'closed'; finish(); });",
    "s.on('error', () => { out = 'connect-failed'; finish(); });",
].join('\n');

function remoteProbe(env) {
    return require('child_process')
        .execFileSync(process.execPath, ['-e', REMOTE_PROBE],
                      { env, encoding: 'utf8', timeout: 15000 })
        .trim();
}

// ---------------------------------------------------------------------------
// Singleton enforcement
// ---------------------------------------------------------------------------
function testRemoteBridge(app) {
    // The whole chain (JS wrapper, N-API binding, Swift entry point, ActionUIRemoteServer)
    // without a run loop, which is fine because only request handling needs the main queue
    // to be serviced. Answering requests is covered by ActionUIRemoteTests.
    //
    // Authentication is the exception and is exercised here: the server refuses an
    // unauthenticated request on the connection queue, deliberately, so that refusing one
    // cannot itself be a way to stall the UI. That is what makes the token checks below
    // possible with no run loop running.
    console.log('\n=== Remote bridge ===');
    const fs = require('fs');

    check('endpoint is null before starting', app.remoteServerEndpoint === null);

    const endpoint = app.startRemoteServer();
    check('startRemoteServer returns a path', typeof endpoint === 'string' && endpoint.length > 0);
    check('the socket file exists', fs.existsSync(endpoint));
    check('the path fits in sun_path', Buffer.byteLength(endpoint, 'utf8') <= 103);
    check('remoteServerEndpoint reports it', app.remoteServerEndpoint === endpoint);
    check('the endpoint is exported to child processes',
          process.env.ACTIONUI_REMOTE_ENDPOINT === endpoint);

    const token = app.remoteServerToken;
    check('remoteServerToken reports a token', typeof token === 'string' && token.length > 0);
    check('the token is exported to child processes',
          process.env.ACTIONUI_REMOTE_TOKEN === token);

    // A real child, spawned the documented way, because that is the thing that was broken and
    // nothing above would have noticed: the framework publishes the token with setenv, which
    // process.env never sees, so a host that does not mirror it hands its children an
    // environment with no token in it and every one of them is refused.
    //
    // `env` must be passed explicitly. Inheriting it implicitly would give the child the real
    // environment, token and all, and the test would pass over exactly the bug it is here for.
    //
    // A request that passes the gate hops to the main thread, which nothing is servicing here,
    // so "no reply" is what acceptance looks like. That reads as an assertion about silence, so
    // the refusals are checked first: they prove replies do come back, and promptly.
    const withoutToken = { ...process.env };
    delete withoutToken.ACTIONUI_REMOTE_TOKEN;
    check('a child with no token is refused with 1006', remoteProbe(withoutToken) === '1006');
    check('a child with the wrong token is refused with 1006',
          remoteProbe({ ...process.env, ACTIONUI_REMOTE_TOKEN: 'not-the-token' }) === '1006');
    check('a child that inherits the environment passes the token gate',
          remoteProbe({ ...process.env }) === 'no-reply');

    let threw = false;
    try { app.startRemoteServer(); } catch (e) { threw = true; }
    check('starting twice throws', threw);

    app.stopRemoteServer();
    check('the socket file is removed', !fs.existsSync(endpoint));
    check('endpoint is null after stopping', app.remoteServerEndpoint === null);
    check('the environment variable is unset',
          process.env.ACTIONUI_REMOTE_ENDPOINT === undefined);
    check('remoteServerToken is null after stopping', app.remoteServerToken === null);
    check('the token variable is unset', process.env.ACTIONUI_REMOTE_TOKEN === undefined);

    let stoppedTwice = true;
    try { app.stopRemoteServer(); } catch (e) { stoppedTwice = false; }
    check('stopping twice does not throw', stoppedTwice);

    const directory = fs.mkdtempSync(require('path').join(require('os').tmpdir(), 'aui'));
    try {
        const chosen = require('path').join(directory, 's');
        check('a chosen path is honored', app.startRemoteServer(chosen) === chosen);
        check('the chosen socket exists', fs.existsSync(chosen));
        app.stopRemoteServer();
    } finally {
        fs.rmSync(directory, { recursive: true, force: true });
    }
}

function testSingletonEnforcement() {
    console.log('\n=== Application singleton enforcement ===');
    let threw = false;
    try { new actionui.Application(); } catch (e) { if (e instanceof Error) threw = true; }
    check('Second Application() throws Error', threw);
}

// ---------------------------------------------------------------------------
// URL conversion (JS layer)
// ---------------------------------------------------------------------------
function testURLConversion() {
    console.log('\n=== URL conversion (JS layer) ===');
    const path = require('path');
    function convert(url) {
        if (!url.startsWith('file://') && !url.startsWith('http://') && !url.startsWith('https://')) {
            url = 'file://' + path.resolve(url);
        }
        return url;
    }
    check('bare /abs/path → file:///abs/path',       convert('/tmp/ui.json') === 'file:///tmp/ui.json');
    check('relative path → file:// + abspath',       convert('ui.json').startsWith('file://'));
    check('file:// URL unchanged',                   convert('file:///tmp/ui.json') === 'file:///tmp/ui.json');
    check('http:// URL unchanged',                   convert('http://example.com/ui.json') === 'http://example.com/ui.json');
    check('https:// URL unchanged',                  convert('https://example.com/ui.json') === 'https://example.com/ui.json');
}

// ---------------------------------------------------------------------------
// ButtonRole / ModalStyle constants
// ---------------------------------------------------------------------------
function testConstants() {
    console.log('\n=== JS constants ===');
    check('ModalStyle.SHEET === "sheet"',                         actionui.ModalStyle.SHEET === 'sheet');
    check('ModalStyle.FULL_SCREEN_COVER === "fullScreenCover"',   actionui.ModalStyle.FULL_SCREEN_COVER === 'fullScreenCover');
    check('ButtonRole.DEFAULT === "default"',                     actionui.ButtonRole.DEFAULT === 'default');
    check('ButtonRole.CANCEL === "cancel"',                       actionui.ButtonRole.CANCEL === 'cancel');
    check('ButtonRole.DESTRUCTIVE === "destructive"',             actionui.ButtonRole.DESTRUCTIVE === 'destructive');
}

// ---------------------------------------------------------------------------
// ActionContext
// ---------------------------------------------------------------------------
function testActionContext() {
    console.log('\n=== ActionContext construction ===');
    const ctx = new actionui.ActionContext('save', 'uuid-1', 42n, 0n, '{"key":"val"}');
    check('ctx.actionId is set',    ctx.actionId === 'save');
    check('ctx.windowUuid is set',  ctx.windowUuid === 'uuid-1');
    check('ctx.viewId is set',      ctx.viewId === 42n);
    check('ctx.context is parsed',  ctx.context !== null && ctx.context.key === 'val');

    const ctx2 = new actionui.ActionContext('dismiss', 'uuid-2', 0n, 0n, null);
    check('ctx.context is null when contextJSON is null', ctx2.context === null);

    const ctx3 = new actionui.ActionContext('x', 'y', 0n, 0n, 'not-json');
    check('ctx.context is raw string when JSON.parse fails', typeof ctx3.context === 'string');
}

// ---------------------------------------------------------------------------
// Logger API
// ---------------------------------------------------------------------------
function testLoggerAPI() {
    console.log('\n=== Logger API ===');
    let logged = false;
    try {
        native.setLogger((msg, level) => { logged = true; });
        native.log('test message', native.LOG_INFO);
        // logger fires synchronously for our bridge
        check('log() and setLogger() work without throw', true);
    } catch (e) { check('log() and setLogger() work without throw', false); }

    try {
        native.setLogger(null);
        check('setLogger(null) clears logger without throw', true);
    } catch { check('setLogger(null) clears logger without throw', false); }
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
console.log('ActionUI App API Smoke Tests');
console.log('='.repeat(55));
console.log('(No NSApplication run loop — tests the N-API binding layer only)');

const app = new actionui.Application({ name: 'TestApp' });
const win = new actionui.Window();

testNativeAPISurface();
testJSAPISurface(app, win);
testLogLevelConstants();
testLifecycleRegistration(app);
testDeregistration();
testTypeChecking();
testMenuBarAPI(app);
testFilePanelAPI(app);
testWindowRegistry(app);
testURLConversion();
testConstants();
testActionContext();
testLoggerAPI();
testRemoteBridge(app);
testSingletonEnforcement();  // must be last — checks second Application() throws

console.log('\n' + '='.repeat(55));
if (failures.length === 0) {
    const total = (process.stdout.write + '').length; // unused, just count checks
    console.log(`All checks PASSED.`);
} else {
    console.error(`FAILED — ${failures.length} check(s):`);
    for (const f of failures) console.error(`  - ${f}`);
    process.exit(1);
}
