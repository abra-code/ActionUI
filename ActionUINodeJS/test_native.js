'use strict';
/**
 * test_native.js — API reachability check (no NSApplication run loop).
 *
 * Mirrors test_native.py from ActionUIPython.
 * Verifies that the native addon loads and every API function is callable
 * without requiring a graphical environment or started run loop.
 *
 * Run: node test_native.js
 */

const actionui = require('./index.js');
const { randomUUID } = require('crypto');

let passed = 0;
let failed = 0;

function check(label, condition) {
    if (condition) {
        console.log(`  [PASS] ${label}`);
        passed++;
    } else {
        console.error(`  [FAIL] ${label}`);
        failed++;
    }
}

// ---------------------------------------------------------------------------
// Version
// ---------------------------------------------------------------------------
console.log('\nActionUI Node.js Native Addon — API Reachability Check');
console.log('='.repeat(55));
console.log('(No NSApplication run loop — tests the N-API binding layer only)\n');

const version = actionui.getVersion();
console.log(`ActionUI version: ${version}`);
check('getVersion() returns a non-empty string', typeof version === 'string' && version.length > 0);

// ---------------------------------------------------------------------------
// Error API
// ---------------------------------------------------------------------------
console.log('\n=== Error API ===');
actionui.clearError();
check('clearError() does not throw', true);
const err = actionui.getLastError();
check('getLastError() returns null or string after clearError()', err === null || typeof err === 'string');

// ---------------------------------------------------------------------------
// Application creation
// ---------------------------------------------------------------------------
console.log('\n=== Application ===');
const app = new actionui.Application({ name: 'TestApp' });
check('Application constructor does not throw', app instanceof actionui.Application);
check('Application.instance() returns the same object', actionui.Application.instance() === app);

// ---------------------------------------------------------------------------
// Action handler registration / deregistration
// ---------------------------------------------------------------------------
console.log('\n=== Action handler registration ===');
let handlerCalled = false;
app.action('test.action', (ctx) => { handlerCalled = true; });
check('registerHandler does not throw', true);

app.unregisterHandler('test.action');
check('unregisterHandler does not throw', true);

app.setDefaultHandler((ctx) => {});
check('setDefaultHandler does not throw', true);
app.setDefaultHandler(null);
check('setDefaultHandler(null) clears handler without throw', true);

// ---------------------------------------------------------------------------
// Lifecycle registration
// ---------------------------------------------------------------------------
console.log('\n=== Lifecycle registration ===');
const noop = () => {};
app.onWillFinishLaunching(noop);   check('onWillFinishLaunching() does not throw', true);
app.onDidFinishLaunching(noop);    check('onDidFinishLaunching() does not throw', true);
app.onWillBecomeActive(noop);      check('onWillBecomeActive() does not throw', true);
app.onDidBecomeActive(noop);       check('onDidBecomeActive() does not throw', true);
app.onWillResignActive(noop);      check('onWillResignActive() does not throw', true);
app.onDidResignActive(noop);       check('onDidResignActive() does not throw', true);
app.onWillTerminate(noop);         check('onWillTerminate() does not throw', true);
app.onShouldTerminate(() => true); check('onShouldTerminate() does not throw', true);
app.onWindowWillClose(noop);       check('onWindowWillClose() does not throw', true);
app.onWindowWillPresent(noop);     check('onWindowWillPresent() does not throw', true);

// Clear them (pass null/undefined should be accepted by the C layer)
try { actionui._native.appSetWillFinishLaunching(null);  check('appSetWillFinishLaunching(null) clears handler', true); }
catch { check('appSetWillFinishLaunching(null) clears handler', false); }

// ---------------------------------------------------------------------------
// Window — value API reachability (no UI loaded; getters return null)
// ---------------------------------------------------------------------------
console.log('\n=== Window value API (no UI loaded — getters return null) ===');
const win = new actionui.Window(randomUUID());
check('Window constructor does not throw', win instanceof actionui.Window);
check('Window.uuid is a non-empty string', typeof win.uuid === 'string' && win.uuid.length > 0);
check('Window.viewPtr is null without a loaded URL', win.viewPtr === null);

// Setters are silent when no ViewModel exists — they must not throw.
win.setInt(100, 42);       check('setInt() does not throw', true);
win.setDouble(101, 3.14);  check('setDouble() does not throw', true);
win.setBool(102, true);    check('setBool() does not throw', true);
win.setString(103, 'hi');  check('setString() does not throw', true);

// Getters return null when no UI is loaded.
const iv = win.getInt(100);
const dv = win.getDouble(101);
const bv = win.getBool(102);
const sv = win.getString(103);
check('getInt() returns null or number', iv === null || typeof iv === 'number');
check('getDouble() returns null or number', dv === null || typeof dv === 'number');
check('getBool() returns null or boolean', bv === null || typeof bv === 'boolean');
check('getString() returns null or string', sv === null || typeof sv === 'string');

// Generic setValue / getValue
win.setValue(104, 100);             check('setValue(int) does not throw', true);
win.setValue(105, 2.718);           check('setValue(float) does not throw', true);
win.setValue(106, false);           check('setValue(bool) does not throw', true);
win.setValue(107, 'Test');          check('setValue(string) does not throw', true);
win.setValue(108, { k: 'v' });      check('setValue(object) does not throw', true);
win.setValue(109, [1, 2, 'three']); check('setValue(array) does not throw', true);

const gv104 = win.getValue(104);
const gv107 = win.getValue(107);
check('getValue() returns null or any', gv104 === null || gv104 !== undefined);
check('getValue(string) returns null or string', gv107 === null || typeof gv107 === 'string');

// ---------------------------------------------------------------------------
// Window — element rows / property / state API reachability
// ---------------------------------------------------------------------------
console.log('\n=== Window element rows / property / state (no UI loaded) ===');
try { win.getColumnCount(1); check('getColumnCount() does not throw', true); }
catch { check('getColumnCount() does not throw', false); }

try { win.getRows(1); check('getRows() does not throw', true); }
catch { check('getRows() does not throw', false); }

try { win.setRows(1, [['a', 'b']]); check('setRows() does not throw', true); }
catch { check('setRows() does not throw', false); }

try { win.appendRows(1, [['c']]); check('appendRows() does not throw', true); }
catch { check('appendRows() does not throw', false); }

try { win.clearRows(1); check('clearRows() does not throw', true); }
catch { check('clearRows() does not throw', false); }

try { win.getProperty(1, 'columns'); check('getProperty() does not throw', true); }
catch { check('getProperty() does not throw', false); }

try { win.setProperty(1, 'columns', [{ header: 'Name' }]); check('setProperty() does not throw', true); }
catch { check('setProperty() does not throw', false); }

try { win.getState(1, 'isLoading'); check('getState() does not throw', true); }
catch { check('getState() does not throw', false); }

try { win.setState(1, 'count', 5); check('setState() does not throw', true); }
catch { check('setState() does not throw', false); }

try { win.getStateString(1, 'label'); check('getStateString() does not throw', true); }
catch { check('getStateString() does not throw', false); }

try { win.setStateFromString(1, 'label', 'hello'); check('setStateFromString() does not throw', true); }
catch { check('setStateFromString() does not throw', false); }

try {
    const info = win.getElementInfo();
    check('getElementInfo() returns an object', typeof info === 'object' && info !== null);
} catch { check('getElementInfo() does not throw', false); }

// ---------------------------------------------------------------------------
// App control (no-run-loop safe calls)
// ---------------------------------------------------------------------------
console.log('\n=== App control API ===');
try { app.closeWindow('00000000-0000-0000-0000-000000000000'); check('closeWindow(unknown UUID) does not throw', true); }
catch { check('closeWindow(unknown UUID) does not throw', false); }

try { app.loadMenuBar(); check('loadMenuBar() with no args does not throw', true); }
catch { check('loadMenuBar() with no args does not throw', false); }

try { app.loadMenuBar('[]'); check("loadMenuBar('[]') does not throw", true); }
catch { check("loadMenuBar('[]') does not throw", false); }

// ---------------------------------------------------------------------------
// Application singleton enforcement
// ---------------------------------------------------------------------------
console.log('\n=== Application singleton enforcement ===');
let singletonThrew = false;
try { new actionui.Application(); }
catch (e) { if (e instanceof Error) singletonThrew = true; }
check('Second Application() throws Error', singletonThrew);

// ---------------------------------------------------------------------------
// URL conversion logic (JS layer)
// ---------------------------------------------------------------------------
console.log('\n=== URL conversion (JS layer) ===');
const path = require('path');
function convertURL(url) {
    if (!url.startsWith('file://') && !url.startsWith('http://') && !url.startsWith('https://')) {
        url = 'file://' + path.resolve(url);
    }
    return url;
}
check('bare /abs/path → file:///abs/path', convertURL('/tmp/ui.json') === 'file:///tmp/ui.json');
check('relative path → file:// + abspath', convertURL('ui.json').startsWith('file://'));
check('file:// URL unchanged', convertURL('file:///tmp/ui.json') === 'file:///tmp/ui.json');
check('http:// URL unchanged', convertURL('http://example.com/ui.json') === 'http://example.com/ui.json');
check('https:// URL unchanged', convertURL('https://example.com/ui.json') === 'https://example.com/ui.json');

// ---------------------------------------------------------------------------
// Summary
// ---------------------------------------------------------------------------
console.log('\n' + '='.repeat(55));
if (failed === 0) {
    console.log(`All ${passed} checks PASSED.`);
} else {
    console.error(`FAILED — ${failed} of ${passed + failed} checks failed.`);
    process.exit(1);
}
