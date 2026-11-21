'use strict';
/**
 * test_trust_policy.js - the host's trust policy (setTrustPolicy) and element origins
 * (Window.getElementOrigin), against a real window. Mirrors test_trust_policy.py.
 *
 * One window loaded from a temporary folder, outside the app's resources (its subfolder "res",
 * named explicitly):
 * - root.json, the window's own document, is made trusted by the trust callback, as a host trusts
 *   a document it chose itself;
 * - less.json, in its first LoadableView, keeps ActionUI's own decision, less trusted; its Image
 *   reads a file there, which reaches the allows callback with ActionUI's refusal as the default;
 * - trusted.json, in the second, is made trusted by the trust callback;
 * - res/throws.json, in the third, is trusted by default (a resource inside trusted content), but
 *   the trust callback throws for it, so it is less trusted (fails closed; the error printed for
 *   it is expected).
 * The origins are read in windowWillClose and checked from willTerminate.
 *
 * Requirements: a graphical session (macOS, or Linux with a display); the addon built.
 * Run: node test_trust_policy.js
 */

const fs = require('fs');
const os = require('os');
const path = require('path');
const zlib = require('zlib');
const actionui = require('./index.js');

const SAFETY_TIMEOUT_MS = 15000;
const WINDOW_DISPLAY_MS = 1500;

/** A valid 1x1 RGBA PNG. */
function png() {
    function crc32(buffer) {
        let crc = ~0;
        for (const byte of buffer) {
            crc ^= byte;
            for (let k = 0; k < 8; k++) crc = (crc >>> 1) ^ (0xedb88320 & -(crc & 1));
        }
        return ~crc >>> 0;
    }
    function chunk(kind, data) {
        const length = Buffer.alloc(4); length.writeUInt32BE(data.length);
        const body = Buffer.concat([Buffer.from(kind, 'ascii'), data]);
        const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(body));
        return Buffer.concat([length, body, crc]);
    }
    const header = Buffer.alloc(13);
    header.writeUInt32BE(1, 0); header.writeUInt32BE(1, 4);
    header[8] = 8; header[9] = 6;
    return Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
        chunk('IHDR', header), chunk('IDAT', zlib.deflateSync(Buffer.from([0, 255, 0, 0, 255]))), chunk('IEND', Buffer.alloc(0))]);
}

const folder = fs.mkdtempSync(path.join(os.tmpdir(), 'actionui-trust-'));
const picture = path.join(folder, 'pic.png');
fs.writeFileSync(picture, png());
fs.writeFileSync(path.join(folder, 'less.json'), JSON.stringify({ type: 'VStack', id: 20, children: [
    { type: 'Image', id: 21, properties: { filePath: picture } }] }));
fs.writeFileSync(path.join(folder, 'trusted.json'), JSON.stringify({ type: 'Text', id: 30, properties: { text: 'Trusted by the host' } }));
const resources = path.join(folder, 'res');
fs.mkdirSync(resources);
fs.writeFileSync(path.join(resources, 'throws.json'), JSON.stringify({ type: 'Text', id: 50, properties: { text: 'The trust callback throws' } }));
const root = path.join(folder, 'root.json');
fs.writeFileSync(root, JSON.stringify({ type: 'VStack', id: 1, children: [
    { type: 'LoadableView', id: 3, properties: { filePath: path.join(folder, 'less.json') } },
    { type: 'LoadableView', id: 4, properties: { filePath: path.join(folder, 'trusted.json') } },
    { type: 'LoadableView', id: 5, properties: { filePath: path.join(resources, 'throws.json') } }] }));

const state = { trustCalls: [], allowsCalls: [], origins: {}, errors: [], closed: false };
const failures = [];

function check(label, condition) {
    console.log(`  [${condition ? 'PASS' : 'FAIL'}] ${label}`);
    if (!condition) failures.push(label);
}

const sameOrigin = (a, b) => a != null && b != null && JSON.stringify(Object.entries(a).sort()) === JSON.stringify(Object.entries(b).sort());

function report() {
    console.log('\nChecks:');
    for (const error of state.errors) check(error, false);
    check('the window closed', state.closed);
    const rootOrigin = state.origins[1] ?? {};
    check("the window's own document is a file, trusted by the trust callback, with no parent",
        rootOrigin.source === 'file' && (rootOrigin.path ?? '').endsWith('root.json')
        && rootOrigin.trust === 'trusted' && !('parentID' in rootOrigin));
    const less = state.origins[20] ?? {};
    check('less.json is a file, less trusted, inside LoadableView 3',
        less.source === 'file' && (less.path ?? '').endsWith('less.json') && less.trust === 'lessTrusted' && less.parentID === 3);
    const made = state.origins[30] ?? {};
    check('trusted.json is trusted by the trust callback', made.trust === 'trusted' && made.parentID === 4);
    const thrown = state.origins[50] ?? {};
    check('res/throws.json is a resource, less trusted because the trust callback threw',
        thrown.source === 'resource' && thrown.trust === 'lessTrusted' && thrown.parentID === 5);
    check('an element the window does not have has no origin', state.origins[999] === null);
    const paths = state.trustCalls.map((call) => call[0].path ?? '');
    check('the trust callback was asked for both documents',
        paths.some((p) => p.endsWith('less.json')) && paths.some((p) => p.endsWith('trusted.json')));
    check("every call had less trusted as the default but throws.json's (outside the resources)",
        state.trustCalls.length > 0 && paths.some((p) => p.endsWith('throws.json'))
        && state.trustCalls.every((call) => (call[2] === actionui.Trust.TRUSTED) === (call[0].path ?? '').endsWith('throws.json')));
    check("the window's document had no parent, the LoadableViews' the trusted root",
        state.trustCalls.every((call) => (call[1] === null) === (call[0].path ?? '').endsWith('root.json')
            && (call[1] === null || sameOrigin(call[1], rootOrigin))));
    const reads = state.allowsCalls.filter((call) => call[0].capability === 'readLocalFile' && (call[0].path ?? '').endsWith('pic.png'));
    check("the allows callback was asked about less.json's picture, refused by default",
        reads.length > 0 && reads.every((call) => call[1].trust === 'lessTrusted' && call[2] === false));
    console.log('='.repeat(50));
    if (failures.length > 0) {
        console.log(`FAILED - ${failures.length} issue(s)`);
        process.exit(1);
    }
    console.log('All trust policy checks PASSED.');
}

// Only the subfolder is the app's resources, wherever this script is run from.
const app = new actionui.Application({ resourceFolder: resources });

// Wrong arguments are refused and change nothing.
try {
    actionui.setTrustPolicy({ trust: 'not a function' });
    state.errors.push('a trust argument that is not a function was accepted');
} catch (e) {
    if (!(e instanceof TypeError)) state.errors.push(`a wrong trust argument threw ${e}`);
}
actionui.setTrustPolicy({
    trust(source, parent, byDefault) {
        state.trustCalls.push([source, parent, byDefault]);
        if ((source.path ?? '').endsWith('throws.json')) throw new Error('expected: the trust callback throws for throws.json');
        return /(root|trusted)\.json$/.test(source.path ?? '') ? actionui.Trust.TRUSTED : byDefault;
    },
    allows(capability, origin, byDefault) {
        state.allowsCalls.push([capability, origin, byDefault]);
        return byDefault;
    },
});

app.onDidFinishLaunching(() => {
    const window = app.loadAndPresentWindow(root, null, 'ActionUI Trust Policy Test');
    setTimeout(() => {
        app.closeWindow(window.uuid);
        setTimeout(() => app.terminate(), 500);
    }, WINDOW_DISPLAY_MS);
});

app.onWindowWillClose((window) => {
    state.closed = true;
    for (const viewId of [1, 20, 30, 50, 999]) state.origins[viewId] = window.getElementOrigin(viewId);
});

app.onShouldTerminate(() => true);

app.onWillTerminate(() => {
    actionui.setTrustPolicy();
    report();
});

setTimeout(() => {
    state.errors.push(`Safety timeout (${SAFETY_TIMEOUT_MS} ms): app did not terminate`);
    report();
    process.exit(1);
}, SAFETY_TIMEOUT_MS).unref();

app.run();
