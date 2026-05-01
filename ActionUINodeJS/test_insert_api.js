'use strict';
/**
 * test_insert_api.js — Runtime structural mutations smoke tests.
 *
 * Exercises insertElement, insertRow, removeElement at both the native (N-API)
 * and JS wrapper (Window class) layers without a running NSApplication.
 * No UI is displayed — tests verify API surface, type correctness, and that
 * unknown UUIDs produce the expected errors without crashing.
 *
 * Run: node test_insert_api.js
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

const FAKE_UUID          = '00000000-0000-0000-0000-000000000000';
const VALID_ELEMENT_JSON = '{"type":"Text","properties":{"text":"hello"}}';
const VALID_CELLS_JSON   = '[{"type":"Text","properties":{"text":"C0"}},{"type":"Text","properties":{"text":"C1"}}]';

// ---------------------------------------------------------------------------
// Native API surface
// ---------------------------------------------------------------------------
function testNativeAPISurface() {
    console.log('\n=== Native module: structural mutation API surface ===');

    for (const name of ['insertElement', 'insertRow', 'removeElement']) {
        check(`native.${name} is present`, typeof native[name] === 'function');
    }
}

// ---------------------------------------------------------------------------
// Window method surface
// ---------------------------------------------------------------------------
function testWindowMethodSurface(win) {
    console.log('\n=== Window: structural mutation method surface ===');

    for (const name of ['insertElement', 'insertRow', 'removeElement']) {
        check(`win.${name} is a function`, typeof win[name] === 'function');
    }
}

// ---------------------------------------------------------------------------
// insertElement — unknown UUID throws
// ---------------------------------------------------------------------------
function testInsertElementUnknownUUID(win) {
    console.log('\n=== insertElement: unknown UUID throws ===');

    // Native layer
    let threw = false;
    try { native.insertElement(FAKE_UUID, 1n, VALID_ELEMENT_JSON, null, actionui.InsertPosition.APPEND, 0n); }
    catch { threw = true; }
    check('native.insertElement(unknown UUID) throws', threw);

    // JS wrapper (calls native internally)
    threw = false;
    try { win.insertElement(1, VALID_ELEMENT_JSON); }
    catch { threw = true; }
    check('win.insertElement(unknown UUID) throws', threw);
}

// ---------------------------------------------------------------------------
// insertElement — object input coerced to JSON
// ---------------------------------------------------------------------------
function testInsertElementObjectInput(win) {
    console.log('\n=== insertElement: object input coerced to JSON ===');

    const element = { type: 'Text', properties: { text: 'hello' } };
    let threw = false;
    try { win.insertElement(1, element); }
    catch (e) {
        // Should throw because UUID is unknown, not because of a TypeError
        threw = !(e instanceof TypeError);
    }
    check('win.insertElement(object) coerced to JSON (throws unknown-UUID, not TypeError)', threw);
}

// ---------------------------------------------------------------------------
// insertRow — unknown UUID throws
// ---------------------------------------------------------------------------
function testInsertRowUnknownUUID(win) {
    console.log('\n=== insertRow: unknown UUID throws ===');

    // Native layer
    let threw = false;
    try { native.insertRow(FAKE_UUID, 2n, VALID_CELLS_JSON, null, 0n, 0n); }
    catch { threw = true; }
    check('native.insertRow(unknown UUID) throws', threw);

    // JS wrapper
    threw = false;
    try { win.insertRow(2, VALID_CELLS_JSON); }
    catch { threw = true; }
    check('win.insertRow(unknown UUID) throws', threw);
}

// ---------------------------------------------------------------------------
// insertRow — array input coerced to JSON
// ---------------------------------------------------------------------------
function testInsertRowArrayInput(win) {
    console.log('\n=== insertRow: array input coerced to JSON ===');

    const cells = [
        { type: 'Text', properties: { text: 'C0' } },
        { type: 'Text', properties: { text: 'C1' } },
    ];
    let threw = false;
    try { win.insertRow(2, cells); }
    catch (e) {
        threw = !(e instanceof TypeError);
    }
    check('win.insertRow(array) coerced to JSON (throws unknown-UUID, not TypeError)', threw);
}

// ---------------------------------------------------------------------------
// removeElement — unknown UUID throws
// ---------------------------------------------------------------------------
function testRemoveElementUnknownUUID(win) {
    console.log('\n=== removeElement: unknown UUID throws ===');

    // Native layer
    let threw = false;
    try { native.removeElement(FAKE_UUID, 10n); }
    catch { threw = true; }
    check('native.removeElement(unknown UUID) throws', threw);

    // JS wrapper
    threw = false;
    try { win.removeElement(10); }
    catch { threw = true; }
    check('win.removeElement(unknown UUID) throws', threw);
}

// ---------------------------------------------------------------------------
// Position / optional arg defaults
// ---------------------------------------------------------------------------
function testPositionDefaults(win) {
    console.log('\n=== insertElement: optional args default correctly ===');

    const cases = [
        ['no container/position',         []],
        ['container=null',                [null]],
        ['container="children"',          ['children']],
        ['position=PREPEND',         [null, actionui.InsertPosition.PREPEND]],
        ['position=AT, param=0',     [null, actionui.InsertPosition.AT, 0]],
        ['position=BEFORE, param=9', [null, actionui.InsertPosition.BEFORE, 9]],
        ['position=AFTER, param=9',  [null, actionui.InsertPosition.AFTER, 9]],
    ];

    for (const [desc, extraArgs] of cases) {
        let threw = false, typeError = false;
        try { win.insertElement(1, VALID_ELEMENT_JSON, ...extraArgs); }
        catch (e) {
            threw = true;
            typeError = e instanceof TypeError;
        }
        check(`insertElement(${desc}) throws unknown-UUID error, not TypeError`,
              threw && !typeError);
    }
}

function testInsertRowPositionDefaults(win) {
    console.log('\n=== insertRow: optional args default correctly ===');

    const cases = [
        ['no container/position',       []],
        ['position=PREPEND',   [null, actionui.InsertPosition.PREPEND]],
        ['position=AT, index=0',    [null, actionui.InsertPosition.AT, 0]],
    ];

    for (const [desc, extraArgs] of cases) {
        let threw = false, typeError = false;
        try { win.insertRow(2, VALID_CELLS_JSON, ...extraArgs); }
        catch (e) {
            threw = true;
            typeError = e instanceof TypeError;
        }
        check(`insertRow(${desc}) throws unknown-UUID error, not TypeError`,
              threw && !typeError);
    }
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
console.log('ActionUI Structural Mutation API Smoke Tests');
console.log('='.repeat(55));
console.log('(No NSApplication run loop — tests the N-API binding layer only)');

const app = new actionui.Application({ name: 'InsertTestApp' });
const win = new actionui.Window(FAKE_UUID);

testNativeAPISurface();
testWindowMethodSurface(win);
testInsertElementUnknownUUID(win);
testInsertElementObjectInput(win);
testInsertRowUnknownUUID(win);
testInsertRowArrayInput(win);
testRemoveElementUnknownUUID(win);
testPositionDefaults(win);
testInsertRowPositionDefaults(win);

console.log('\n' + '='.repeat(55));
if (failures.length === 0) {
    console.log('All checks PASSED.');
    process.exit(0);
} else {
    console.error(`FAILED — ${failures.length} check(s):`);
    for (const f of failures) console.error(`  - ${f}`);
    process.exit(1);
}
