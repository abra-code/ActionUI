'use strict';
/**
 * test_configuration.js - ActionUI's configuration (actionui.configure, actionui.getConfiguration),
 * against a real window. Mirrors test_configuration.py.
 *
 * Before any window loads:
 * - new Application({ resourceFolder }) is the configuration's resourceFolder;
 * - configure changes only the keys it names (the nesting depth to 2, a trusted origin) and keeps
 *   the rest;
 * - an unknown key, a wrong type and an origin that is not https are refused, and change nothing;
 *   a settings value that is not an object is a TypeError.
 * Then one window whose LoadableViews nest three deep (a.json, b.json, c.json): with the depth at
 * 2, b.json loads and c.json is refused. Once the window has loaded, configure is refused: the
 * configuration is fixed.
 *
 * Requirements: a graphical session (macOS, or Linux with a display); the addon built.
 * Run: node test_configuration.js
 */

const fs = require('fs');
const os = require('os');
const path = require('path');
const actionui = require('./index.js');

const SAFETY_TIMEOUT_MS = 15000;
const WINDOW_DISPLAY_MS = 1500;

const folder = fs.mkdtempSync(path.join(os.tmpdir(), 'actionui-configuration-'));
function write(name, value) {
    const file = path.join(folder, name);
    fs.writeFileSync(file, JSON.stringify(value));
    return file;
}
write('c.json', { type: 'Text', id: 40, properties: { text: 'Too deep' } });
write('b.json', { type: 'VStack', id: 30, children: [
    { type: 'LoadableView', id: 31, properties: { filePath: path.join(folder, 'c.json') } }] });
write('a.json', { type: 'VStack', id: 20, children: [
    { type: 'LoadableView', id: 21, properties: { filePath: path.join(folder, 'b.json') } }] });
const root = write('root.json', { type: 'VStack', id: 1, children: [
    { type: 'LoadableView', id: 3, properties: { filePath: path.join(folder, 'a.json') } }] });

const state = { origins: {}, lateRefusal: null, lateConfiguration: null, closed: false };
const failures = [];

function check(label, condition) {
    console.log(`  [${condition ? 'PASS' : 'FAIL'}] ${label}`);
    if (!condition) failures.push(label);
}

/** The message configure threw for settings, or null when it did not throw. */
function refused(settings) {
    try {
        actionui.configure(settings);
    } catch (e) {
        return String(e.message);
    }
    return null;
}

// Deep equality: ActionUI writes JSON keys in no fixed order.
const same = (a, b) => require('util').isDeepStrictEqual(a, b);

const app = new actionui.Application({ resourceFolder: folder });

console.log('Before the first window:');
const initial = actionui.getConfiguration();
check('every key is there', same(Object.keys(initial).sort(), ['addOns', 'limits', 'resourceFolder', 'trust']));
check('the defaults: 16 MB, 256 loads in 60 s, 16 deep, no trusted origins',
    initial.limits.maximumJSONSize === 16777216 && initial.limits.loadBudget.loads === 256
    && initial.limits.loadBudget.seconds === 60 && initial.limits.maximumNestingDepth === 16
    && same(initial.trust.trustedOrigins, []));
check("new Application({ resourceFolder }) is the configuration's resource folder",
    fs.realpathSync(initial.resourceFolder ?? '/') === fs.realpathSync(folder));

actionui.configure({ limits: { maximumNestingDepth: 2 }, trust: { trustedOrigins: ['https://ui.example.com'] } });
const changed = actionui.getConfiguration();
check('configure changes only the keys it names',
    changed.limits.maximumNestingDepth === 2 && changed.limits.maximumJSONSize === 16777216
    && same(changed.trust.trustedOrigins, ['https://ui.example.com']) && changed.resourceFolder === initial.resourceFolder);

for (const [settings, expected] of [
    [{ limits: { maximumNestingDepth: 5 }, trustedOrigin: [] }, 'unknown configuration key trustedOrigin'],
    [{ limits: { maximumJSONSize: 'big' } }, 'limits.maximumJSONSize must be a whole number'],
    [{ trust: { trustedOrigins: ['http://ui.example.com'] } }, 'is not an https address'],
]) {
    const message = refused(settings);
    check(`refused: ${JSON.stringify(settings)}`, message !== null && message.includes(expected));
}
for (const bad of [null, 'limits', [1]]) {
    let typeError = false;
    try { actionui.configure(bad); } catch (e) { typeError = e instanceof TypeError; }
    check(`a TypeError for settings ${JSON.stringify(bad)}`, typeError);
}
check('the refusals changed nothing', same(actionui.getConfiguration(), changed));

app.onDidFinishLaunching(() => {
    const window = app.loadAndPresentWindow(root, null, 'ActionUI Configuration Test');
    setTimeout(() => {
        app.closeWindow(window.uuid);
        setTimeout(() => app.terminate(), 500);
    }, WINDOW_DISPLAY_MS);
});

app.onWindowWillClose((window) => {
    state.closed = true;
    for (const viewId of [1, 20, 30, 40]) state.origins[viewId] = window.getElementOrigin(viewId);
    state.lateRefusal = refused({ limits: { maximumNestingDepth: 8 } });
    state.lateConfiguration = actionui.getConfiguration();
});

app.onShouldTerminate(() => true);

app.onWillTerminate(() => report());

function report() {
    console.log('\nWith a window:');
    check('the window closed', state.closed);
    check('the window and the first two nested LoadableViews loaded',
        [1, 20, 30].every((viewId) => state.origins[viewId] != null));
    check('the third, past the configured depth of 2, was refused', state.origins[40] === null);
    check('configure is refused once a window has loaded', (state.lateRefusal ?? '').includes('fixed'));
    check('and the configuration stays as it was', same(state.lateConfiguration, changed));
    console.log('='.repeat(50));
    if (failures.length > 0) {
        console.log(`FAILED - ${failures.length} issue(s)`);
        process.exit(1);
    }
    console.log('All configuration checks PASSED.');
}

setTimeout(() => {
    check(`Safety timeout (${SAFETY_TIMEOUT_MS} ms): app did not terminate`, false);
    report();
    process.exit(1);
}, SAFETY_TIMEOUT_MS).unref();

app.run();
