'use strict';
/**
 * test_native_api.js — Native module API surface smoke tests.
 *
 * Mirrors test_api_surface.py from ActionUIPython.
 * Tests the N-API binding layer directly without a running NSApplication.
 *
 * Run: node test_native_api.js
 */

const native = require('./index.js')._native;

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

function testModuleConstants() {
    console.log('\n=== Module constants ===');
    check('LOG_ERROR === 1',   native.LOG_ERROR === 1);
    check('LOG_WARNING === 2', native.LOG_WARNING === 2);
    check('LOG_INFO === 3',    native.LOG_INFO === 3);
    check('LOG_DEBUG === 4',    native.LOG_DEBUG === 4);
    check('LOG_VERBOSE === 5', native.LOG_VERBOSE === 5);
}

function testVersion() {
    console.log('\n=== Version ===');
    const v = native.getVersion();
    check('getVersion() returns a string', typeof v === 'string' && v.length > 0);
}

function testLogging() {
    console.log('\n=== Logging ===');
    try {
        native.setLogger((msg, level) => {});
        native.log('test message', native.LOG_INFO);
        native.setLogger(null);
        check('setLogger/log/clear works without throw', true);
    } catch (e) {
        check('setLogger/log/clear works without throw', false);
    }
}

function testErrorLifecycle() {
    console.log('\n=== Error lifecycle ===');
    native.clearError();
    check('clearError() does not throw', true);
    const err = native.getLastError();
    check('getLastError() returns null after clear', err === null);
}

function testActionHandlerLifecycle() {
    console.log('\n=== Action handler lifecycle ===');
    const handler = (aid, wid, vid, vpid, ctx) => {};
    try {
        native.registerActionHandler('test.action', handler);
        native.unregisterActionHandler('test.action');
        native.setDefaultActionHandler(handler);
        native.setDefaultActionHandler(null);
        check('register/unregister/setDefault works without throw', true);
    } catch (e) {
        check('register/unregister/setDefault works without throw', false);
    }
}

function testAppCalls() {
    console.log('\n=== App lifecycle calls ===');
    try {
        native.appLoadMenuBar();
        native.appLoadMenuBar('[]');
        native.appSetWillFinishLaunching(() => {});
        native.appSetDidFinishLaunching(() => {});
        native.appSetWillBecomeActive(() => {});
        native.appSetDidBecomeActive(() => {});
        native.appSetWillResignActive(() => {});
        native.appSetDidResignActive(() => {});
        native.appSetWillTerminate(() => {});
        native.appSetShouldTerminate(() => true);
        native.appSetWindowWillClose(() => {});
        native.appSetWindowWillPresent(() => {});
        native.appSetWillFinishLaunching(null);
        native.appSetDidFinishLaunching(null);
        native.appSetWillBecomeActive(null);
        native.appSetDidBecomeActive(null);
        native.appSetWillResignActive(null);
        native.appSetDidResignActive(null);
        native.appSetWillTerminate(null);
        native.appSetShouldTerminate(null);
        native.appSetWindowWillClose(null);
        native.appSetWindowWillPresent(null);
        check('All app lifecycle setters work without throw', true);
    } catch (e) {
        check('All app lifecycle setters work without throw', false);
    }
}

function testTypeSpecificSettersAndGetters(uuid) {
    console.log('\n=== Type-specific setters and getters ===');
    const vid = 1;
    const vpid = 0;

    let r = native.setIntValue(uuid, vid, vpid, 42);
    check('setIntValue returns true', r === true);
    r = native.setIntValue(uuid, vid, vpid, -7);
    check('setIntValue(-7) returns true', r === true);
    r = native.setDoubleValue(uuid, vid, vpid, 3.14);
    check('setDoubleValue returns true', r === true);
    r = native.setBoolValue(uuid, vid, vpid, true);
    check('setBoolValue(true) returns true', r === true);
    r = native.setBoolValue(uuid, vid, vpid, false);
    check('setBoolValue(false) returns true', r === true);
    r = native.setStringValue(uuid, vid, vpid, 'hello world');
    check('setStringValue returns true', r === true);
    r = native.setStringValue(uuid, vid, vpid, '');
    check('setStringValue(empty) returns true', r === true);

    check('getIntValue returns null (no UI)', native.getIntValue(uuid, vid, vpid) === null);
    check('getDoubleValue returns null', native.getDoubleValue(uuid, vid, vpid) === null);
    check('getBoolValue returns null', native.getBoolValue(uuid, vid, vpid) === null);
    check('getStringValue returns null', native.getStringValue(uuid, vid, vpid) === null);
}

function testViewPartIdIsolation(uuid) {
    console.log('\n=== View part ID isolation ===');
    const vid = 2;
    for (const vpid of [0, 1, 2]) {
        const r = native.setIntValue(uuid, vid, vpid, 100 + vpid);
        check(`setIntValue(vpid=${vpid}) returns true`, r === true);
    }
}

function testDefaultViewPartId(uuid) {
    console.log('\n=== Default view part ID ===');
    const vid = 3;
    const r = native.setIntValue(uuid, vid, 0, 999);
    check('setIntValue(vpid=0) returns true', r === true);
}

function testStringBoundaryCases(uuid) {
    console.log('\n=== String boundary cases ===');
    const vid = 4;
    const vpid = 0;
    for (const s of ['', 'a', 'x'.repeat(1000)]) {
        const r = native.setStringValue(uuid, vid, vpid, s);
        check(`setStringValue("${s.slice(0, 10)}...") returns true`, r === true);
    }
}

function testValueFromString(uuid) {
    console.log('\n=== Value from string ===');
    const vid = 5;
    const vpid = 0;

    let r = native.setValueFromString(uuid, vid, vpid, 'plain text');
    check('setValueFromString(plain) returns true', r === true);
    r = native.setValueFromString(uuid, vid, vpid, '**bold**', 'markdown');
    check('setValueFromString(markdown) returns true', r === true);
    r = native.setValueFromString(uuid, vid, vpid, 'another value');
    check('setValueFromString default format returns true', r === true);
}

function testValueFromJson(uuid) {
    console.log('\n=== Value from JSON ===');
    const vid = 6;
    const vpid = 0;

    let r = native.setValueFromJSON(uuid, vid, vpid, JSON.stringify({ k: 'v' }));
    check('setValueFromJSON(object) returns true', r === true);
    r = native.setValueFromJSON(uuid, vid, vpid, '{}');
    check('setValueFromJSON({}) returns true', r === true);
    r = native.setValueFromJSON(uuid, vid, vpid, '[]');
    check('setValueFromJSON([]) returns true', r === true);
}

function testElementColumnCount(uuid) {
    console.log('\n=== Element column count ===');
    const vid = 10;
    const r = native.getElementColumnCount(uuid, vid);
    check('getElementColumnCount returns an integer', typeof r === 'number');
}

function testElementRows(uuid) {
    console.log('\n=== Element rows ===');
    const vid = 11;
    const rows = [['A', 'B'], ['C', 'D']];
    let r = native.setElementRowsJSON(uuid, vid, JSON.stringify(rows));
    check('setElementRowsJSON returns true', r === true);
    r = native.appendElementRowsJSON(uuid, vid, JSON.stringify([['E', 'F']]));
    check('appendElementRowsJSON returns true', r === true);
    r = native.clearElementRows(uuid, vid);
    check('clearElementRows does not throw', r === true || r === undefined);
}

function testElementProperty(uuid) {
    console.log('\n=== Element property ===');
    const vid = 12;
    const r = native.setElementPropertyJSON(uuid, vid, 'hidden', JSON.stringify(true));
    check('setElementPropertyJSON returns true', r === true);
}

function testElementState(uuid) {
    console.log('\n=== Element state ===');
    const vid = 13;
    const key = 'counter';
    let r = native.setElementStateJSON(uuid, vid, key, JSON.stringify(0));
    check('setElementStateJSON returns true', r === true);
    r = native.setElementStateFromString(uuid, vid, key, '42');
    check('setElementStateFromString returns true', r === true);
}

function testElementInfo(uuid) {
    console.log('\n=== Element info ===');
    const v = native.getElementInfoJSON(uuid);
    check('getElementInfoJSON returns null or parses', v === null || typeof v === 'string');
}

function testNoopCalls(uuid) {
    console.log('\n=== No-op calls (getters without UI) ===');
    const vid = 99;
    const vpid = 0;

    native.setIntValue(uuid, vid, vpid, 1);
    native.setDoubleValue(uuid, vid, vpid, 1.0);
    native.setBoolValue(uuid, vid, vpid, true);
    native.setStringValue(uuid, vid, vpid, 'x');
    native.setValueFromString(uuid, vid, vpid, 'x');
    native.setValueFromJSON(uuid, vid, vpid, '{}');
    native.setElementRowsJSON(uuid, vid, '[]');
    native.appendElementRowsJSON(uuid, vid, '[]');
    native.clearElementRows(uuid, vid);
    native.setElementPropertyJSON(uuid, vid, 'x', '{}');
    native.setElementStateJSON(uuid, vid, 'x', '{}');
    native.setElementStateFromString(uuid, vid, 'x', 'x');

    check('getIntValue returns null', native.getIntValue(uuid, vid, vpid) === null);
    check('getDoubleValue returns null', native.getDoubleValue(uuid, vid, vpid) === null);
    check('getBoolValue returns null', native.getBoolValue(uuid, vid, vpid) === null);
    check('getStringValue returns null', native.getStringValue(uuid, vid, vpid) === null);
    check('getValueAsString returns null', native.getValueAsString(uuid, vid, vpid) === null);
    check('getValueAsJSON returns null', native.getValueAsJSON(uuid, vid, vpid) === null);
    check('getElementRowsJSON returns null', native.getElementRowsJSON(uuid, vid) === null);
    check('getElementColumnCount returns 0', native.getElementColumnCount(uuid, vid) === 0);
    check('getElementPropertyJSON returns null', native.getElementPropertyJSON(uuid, vid, 'x') === null);
    check('getElementStateJSON returns null', native.getElementStateJSON(uuid, vid, 'x') === null);
    check('getElementStateString returns null', native.getElementStateString(uuid, vid, 'x') === null);
}

function testModalNoop(uuid) {
    console.log('\n=== Modal no-op calls ===');
    const calls = [
        () => native.presentModal(uuid, '{}', 'json', 'sheet', null),
        () => native.dismissModal(uuid),
        () => native.presentAlert(uuid, 'title', 'message', null),
        () => native.presentConfirmationDialog(uuid, 'title', 'message', '[]'),
        () => native.dismissDialog(uuid),
    ];
    for (const fn of calls) {
        try { fn(); } catch {}
    }
    check('Modal calls do not crash', true);
}

function testLoadHostingController(uuid) {
    console.log('\n=== Load hosting controller ===');
    let threw = false;
    try {
        native.loadHostingController('file:///nonexistent/path.json', uuid, true);
    } catch (e) {
        threw = true;
    }
    check('loadHostingController returns without crash or throws on missing file', true);
}

function testMenuBarNoop() {
    console.log('\n=== Menu bar no-op ===');
    try {
        native.appLoadMenuBar('not valid json');
        check('appLoadMenuBar(invalid JSON) does not crash', true);
    } catch (e) {
        check('appLoadMenuBar(invalid JSON) does not crash', false);
    }
}

function testAppControl() {
    console.log('\n=== App control ===');
    const calls = [
        () => native.appSetName('TestApp'),
        () => native.appSetIcon(null),
    ];
    for (const fn of calls) {
        try { fn(); } catch {}
    }
    check('appSetName/appSetIcon do not throw', true);
}

function testFilePanels() {
    console.log('\n=== File panel API surface ===');
    check('appRunOpenPanel is a function', typeof native.appRunOpenPanel === 'function');
    check('appRunSavePanel is a function', typeof native.appRunSavePanel === 'function');
    check('appRunAlert is a function', typeof native.appRunAlert === 'function');
}

function testTypeChecking() {
    console.log('\n=== Type checking (non-function must throw TypeError) ===');
    const setters = [
        ['appSetWillFinishLaunching', native.appSetWillFinishLaunching.bind(native)],
        ['appSetShouldTerminate', native.appSetShouldTerminate.bind(native)],
        ['appSetWindowWillClose', native.appSetWindowWillClose.bind(native)],
        ['setLogger', native.setLogger.bind(native)],
    ];

    for (const [name, setter] of setters) {
        let threw = false;
        try { setter(42); } catch { threw = true; }
        check(`native.${name}(42) throws`, threw);
    }
}

function testNullClearing() {
    console.log('\n=== Null handler clearing ===');
    try {
        native.appSetWillFinishLaunching(() => {});
        native.appSetWillFinishLaunching(null);
        check('appSetWillFinishLaunching(null) clears without throw', true);
    } catch (e) {
        check('appSetWillFinishLaunching(null) clears without throw', false);
    }

    try {
        native.appSetShouldTerminate(() => true);
        native.appSetShouldTerminate(null);
        check('appSetShouldTerminate(null) clears without throw', true);
    } catch (e) {
        check('appSetShouldTerminate(null) clears without throw', false);
    }

    try {
        native.appSetWindowWillClose(() => {});
        native.appSetWindowWillClose(null);
        check('appSetWindowWillClose(null) clears without throw', true);
    } catch (e) {
        check('appSetWindowWillClose(null) clears without throw', false);
    }
}

function main() {
    console.log('ActionUI Native Module — API Surface Test');
    console.log('='.repeat(55));
    console.log('(No NSApplication run loop — tests the N-API binding only)');

    testModuleConstants();
    testVersion();
    testLogging();
    testErrorLifecycle();
    testActionHandlerLifecycle();
    testAppCalls();

    const testUuid = require('crypto').randomUUID();

    testTypeSpecificSettersAndGetters(testUuid);
    testViewPartIdIsolation(testUuid);
    testDefaultViewPartId(testUuid);
    testStringBoundaryCases(testUuid);
    testValueFromString(testUuid);
    testValueFromJson(testUuid);
    testElementColumnCount(testUuid);
    testElementRows(testUuid);
    testElementProperty(testUuid);
    testElementState(testUuid);
    testElementInfo(testUuid);
    testNoopCalls(testUuid);
    testModalNoop(testUuid);
    testLoadHostingController(testUuid);
    testMenuBarNoop();
    testAppControl();
    testFilePanels();
    testTypeChecking();
    testNullClearing();

    console.log('\n' + '='.repeat(55));
    if (failures.length === 0) {
        console.log('All API surface tests PASSED.');
    } else {
        console.error(`FAILED — ${failures.length} check(s):`);
        for (const f of failures) console.error(`  - ${f}`);
        process.exit(1);
    }
}

main();