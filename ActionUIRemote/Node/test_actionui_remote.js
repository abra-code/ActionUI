'use strict';
/**
 * test_actionui_remote.js - the Node client against the reference fake host.
 *
 * The host is ActionUIRemote/Python/actionui_remote_testing.py, the same oracle the Python
 * client's suite uses, so the two clients are held to one definition of the protocol rather than
 * to each other. The token-descriptor rules are driven in child processes, because the client
 * reads the descriptor when it loads and a process can only do that once.
 *
 * Run: node test_actionui_remote.js
 * Unix-socket bind needs the tool sandbox disabled in this harness.
 */

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const net = require('net');
const { spawn, spawnSync } = require('child_process');

const aui = require('./actionui_remote');

const CLIENT = path.join(__dirname, 'actionui_remote.js');
const FAKE_HOST_DIR = path.join(__dirname, '..', 'Python');
const WINDOW = '11111111-2222-3333-4444-555555555555';
// Mirrors TOKEN_DESCRIPTOR_TIMEOUT in the client; a test that waited that long has not proved
// the thing it is checking.
const TOKEN_DESCRIPTOR_TIMEOUT_SECONDS = 10;

let passed = 0;
const failures = [];

function check(label, condition, detail) {
    if (condition) {
        console.log(`  [PASS] ${label}`);
        passed += 1;
    } else {
        console.error(`  [FAIL] ${label}${detail ? ': ' + detail : ''}`);
        failures.push(label);
    }
}

async function checkThrows(label, run, predicate) {
    try {
        await run();
        check(label, false, 'nothing was thrown');
    } catch (error) {
        check(label, predicate(error), `${error && error.name}: ${error && error.message}`);
    }
}

function sleep(ms) {
    return new Promise((resolve) => setTimeout(resolve, ms));
}

// --- the fake host --------------------------------------------------------------------------

class FakeHost {
    constructor(socketPath, tokens) {
        this.socketPath = socketPath;
        const args = ['-m', 'actionui_remote_testing', '--socket', socketPath,
                      '--window', WINDOW,
                      '--element', `${WINDOW}:2:TextField`,
                      '--element', `${WINDOW}:5:Table`];
        for (const token of tokens || []) args.push('--token', token);
        this.process = spawn('python3', args, {
            cwd: FAKE_HOST_DIR,
            env: Object.assign({}, process.env, { PYTHONPATH: FAKE_HOST_DIR }),
            stdio: ['ignore', 'ignore', 'inherit'],
        });
    }

    async ready() {
        const deadline = Date.now() + 10000;
        while (Date.now() < deadline) {
            if (fs.existsSync(this.socketPath)) return this;
            await sleep(25);
        }
        throw new Error(`the fake host never created ${this.socketPath}`);
    }

    stop() {
        try { this.process.kill('SIGTERM'); } catch (error) { /* already gone */ }
    }
}

// --- the client in a child process ----------------------------------------------------------

// The descriptor is read once, when the module loads, so every rule about it has to be checked
// in a process that has not loaded it yet. `tokenFd` is either a descriptor number to hand the
// child as its fd 3, or 'pipe' for one this test writes to itself.
function runProbe(script, { env = {}, tokenFd = null } = {}) {
    const stdio = ['ignore', 'pipe', 'pipe'];
    if (tokenFd !== null) stdio.push(tokenFd);
    const result = spawnSync(process.execPath, ['-e', script], {
        env: Object.assign({}, process.env, env),
        stdio,
        encoding: 'utf8',
        timeout: 30000,
    });
    return {
        stdout: (result.stdout || '').trim(),
        stderr: (result.stderr || '').trim(),
        status: result.status,
    };
}

const REPORT_TOKEN = `
const aui = require(${JSON.stringify(CLIENT)});
try {
    const connection = new aui.Connection('/nowhere.sock');
    console.log(JSON.stringify({
        token: connection.token,
        fdVariable: process.env.ACTIONUI_REMOTE_TOKEN_FD === undefined ? null
                                                                      : process.env.ACTIONUI_REMOTE_TOKEN_FD,
        fdStillOpen: (() => {
            try { require('fs').fstatSync(3); return true; } catch (e) { return false; }
        })(),
    }));
} catch (error) {
    console.log(JSON.stringify({ error: error.name, message: error.message }));
}
`;

// --- a server that records instead of answering ---------------------------------------------

// The fake host validates params and would reject a wrong shape, which is worth having - but it
// answers with an error rather than telling us what we sent. This records the exact envelope, so
// a test can assert the method name and every key that went over the wire. That is the check
// that was missing: every wire-shape bug in this client got past a suite that only asserted
// round trips through methods the fake happened to be lenient about.
class RecordingHost {
    constructor(socketPath) {
        this.socketPath = socketPath;
        this.requests = [];
        this.server = net.createServer((socket) => {
            let buffer = '';
            socket.setEncoding('utf8');
            socket.on('data', (chunk) => {
                buffer += chunk;
                let newline = buffer.indexOf('\n');
                while (newline >= 0) {
                    const line = buffer.slice(0, newline);
                    buffer = buffer.slice(newline + 1);
                    newline = buffer.indexOf('\n');
                    if (!line.trim()) continue;
                    const value = JSON.parse(line);
                    const entries = Array.isArray(value) ? value : [value];
                    for (const entry of entries) this.requests.push(entry);
                    const reply = Array.isArray(value)
                        ? value.map((e) => ({ jsonrpc: '2.0', id: e.id, result: null }))
                        : { jsonrpc: '2.0', id: value.id, result: null };
                    socket.write(JSON.stringify(reply) + '\n');
                }
            });
            socket.on('error', () => {});
        });
    }

    listen() {
        return new Promise((resolve) => this.server.listen(this.socketPath, () => resolve(this)));
    }

    get last() {
        return this.requests[this.requests.length - 1];
    }

    close() {
        this.server.close();
    }
}

async function testTheWireShapes(directory) {
    console.log('\n=== What actually goes on the wire ===');
    const socketPath = path.join(directory, 'record.sock');
    const host = await new RecordingHost(socketPath).listen();
    try {
        const connection = new aui.Connection(socketPath, { timeout: 10 });
        const win = new aui.Window(WINDOW, { connection });
        const sent = async (run) => { await run(); return host.last; };
        const paramsOf = (envelope) => {
            const copy = Object.assign({}, envelope.params);
            delete copy.window;
            return copy;
        };

        // The parent of an insert is `parentID`, not the `viewID` every other method sends.
        let envelope = await sent(() => win.insertElement(7, { type: 'Label' }));
        check('insertElement names the method correctly',
              envelope.method === 'actionui.insertElement', envelope.method);
        check('insertElement sends parentID, not viewID',
              JSON.stringify(paramsOf(envelope)) === JSON.stringify({ parentID: 7, element: { type: 'Label' } }),
              JSON.stringify(paramsOf(envelope)));

        envelope = await sent(() => win.insertRow(7, [{ type: 'Label' }]));
        check('insertRow calls actionui.insertRow', envelope.method === 'actionui.insertRow',
              envelope.method);
        check('insertRow sends parentID and cells',
              JSON.stringify(paramsOf(envelope)) === JSON.stringify({ parentID: 7, cells: [{ type: 'Label' }] }),
              JSON.stringify(paramsOf(envelope)));

        // PROTOCOL.md section 6: the position is {kind, ...}, not {at: n}.
        const positions = [
            [aui.InsertPosition.append(), { kind: 'append' }],
            [aui.InsertPosition.prepend(), { kind: 'prepend' }],
            [aui.InsertPosition.at(3), { kind: 'at', index: 3 }],
            [aui.InsertPosition.before(9), { kind: 'before', siblingID: 9 }],
            [aui.InsertPosition.after(9), { kind: 'after', siblingID: 9 }],
        ];
        for (const [position, expected] of positions) {
            envelope = await sent(() => win.insertElement(7, { type: 'Label' }, { position }));
            check(`position ${expected.kind} goes over the wire as {kind, ...}`,
                  JSON.stringify(envelope.params.position) === JSON.stringify(expected),
                  JSON.stringify(envelope.params.position));
        }
        envelope = await sent(() => win.insertElement(7, { type: 'Label' }, { position: 'append' }));
        check("the 'append' shorthand becomes {kind: 'append'}",
              JSON.stringify(envelope.params.position) === JSON.stringify({ kind: 'append' }));

        // The host takes modal content as element / json / path, and nothing else.
        envelope = await sent(() => win.presentModal({ element: { type: 'Group' } }));
        check('presentModal sends element',
              JSON.stringify(paramsOf(envelope)) === JSON.stringify({ element: { type: 'Group' } }),
              JSON.stringify(paramsOf(envelope)));
        envelope = await sent(() => win.presentModal({ source: '{"type":"Group"}', style: 'sheet' }));
        check('a string source becomes json',
              JSON.stringify(paramsOf(envelope)) === JSON.stringify({ json: '{"type":"Group"}', style: 'sheet' }),
              JSON.stringify(paramsOf(envelope)));
        envelope = await sent(() => win.presentModal({ path: 'Sheet.json' }));
        check('presentModal sends path', paramsOf(envelope).path === 'Sheet.json');
        await checkThrows('presentModal with no content is a TypeError',
                          async () => win.presentModal({ style: 'sheet' }),
                          (error) => error instanceof TypeError);

        // The engine's property is `disabled`; there is no `enabled`.
        envelope = await sent(() => win.setEnabled(4, false));
        check('setEnabled sets disabled, inverted',
              JSON.stringify(paramsOf(envelope)) === JSON.stringify({ viewID: 4, name: 'disabled', value: true }),
              JSON.stringify(paramsOf(envelope)));

        // Cells go over the wire as strings.
        envelope = await sent(() => win.setRows(5, [[1, 2]]));
        check('setRows stringifies cells',
              JSON.stringify(envelope.params.rows) === JSON.stringify([['1', '2']]),
              JSON.stringify(envelope.params.rows));
        await checkThrows('a flat row of strings is rejected rather than silently reshaped',
                          async () => win.setRows(5, ['a', 'b']),
                          (error) => error instanceof TypeError);

        // `token` is reserved on every method: the connection's wins.
        const guarded = new aui.Connection(socketPath, { timeout: 10, token: 'real' });
        const guardedWindow = new aui.Window(WINDOW, { connection: guarded });
        await guardedWindow.call('omc.probe', { token: 'forged' });
        check("a caller's own token param cannot override the connection's",
              host.last.params.token === 'real', JSON.stringify(host.last.params));
        guarded.close();

        connection.close();
    } finally {
        host.close();
    }
}

// A host that answers exactly what a test tells it to, for replies a real host does not send.
function scriptedHost(socketPath, respond) {
    const server = net.createServer((socket) => {
        let buffer = '';
        socket.setEncoding('utf8');
        socket.on('data', (chunk) => {
            buffer += chunk;
            let newline = buffer.indexOf('\n');
            while (newline >= 0) {
                const line = buffer.slice(0, newline);
                buffer = buffer.slice(newline + 1);
                newline = buffer.indexOf('\n');
                if (line.trim()) respond(JSON.parse(line), (reply) => socket.write(JSON.stringify(reply) + '\n'));
            }
        });
        socket.on('error', () => {});
    });
    return new Promise((resolve) => server.listen(socketPath, () => resolve(server)));
}

async function testRepliesThatDoNotArriveOrArriveOddly(directory) {
    console.log('\n=== Replies a real host does not send ===');

    // A request that is never answered must time out AND take the connection with it. Leaving it
    // open would let the late reply be read while some later request is outstanding, and be
    // handed to the wrong one. The Python client closes here too.
    const silentPath = path.join(directory, 'silent.sock');
    const silent = await scriptedHost(silentPath, () => {});
    try {
        const connection = new aui.Connection(silentPath, { timeout: 0.4 });
        await checkThrows('a host that never answers times out',
                          () => connection.call('actionui.hello'),
                          (error) => error instanceof aui.EndpointError && /did not answer/.test(error.message));
        check('and the connection is dropped with it', connection.isConnected === false);
        connection.close();
    } finally {
        silent.close();
    }

    // A batch reply is claimed by the batch that sent it, found through any id in it. The first
    // entry may be an error with a null id, which matches nothing - claiming "the only pending
    // request" instead is how a stale batch reply used to be handed to an unrelated call.
    const oddPath = path.join(directory, 'odd.sock');
    const odd = await scriptedHost(oddPath, (request, send) => {
        if (!Array.isArray(request)) {
            send({ jsonrpc: '2.0', id: request.id, result: 'single' });
            return;
        }
        send([
            { jsonrpc: '2.0', id: null, error: { code: -32600, message: 'Invalid request' } },
            { jsonrpc: '2.0', id: request[1].id, result: 'second' },
            { jsonrpc: '2.0', id: request[0].id, result: 'first' },
        ]);
    });
    try {
        const connection = new aui.Connection(oddPath, { timeout: 5 });
        const results = await connection.callBatch([['a.one', {}], ['a.two', {}]]);
        check('a batch reply led by a null-id error is still matched to its batch',
              results[0] === 'first' && results[1] === 'second', JSON.stringify(results));
        check('and a following single call still gets its own answer',
              (await connection.call('a.three')) === 'single');
        connection.close();
    } finally {
        odd.close();
    }
}

async function testBatchingCarriesItsTypes(directory) {
    console.log('\n=== Batching ===');
    const socketPath = path.join(directory, 'batch.sock');
    const host = await new FakeHost(socketPath).ready();
    try {
        const connection = new aui.Connection(socketPath, { timeout: 10 });
        const win = new aui.Window(WINDOW, { connection });
        await win.setValue(2, 0, 41);

        // The bug this pins: a batched typed getter used to await the recorder, resolve to the
        // Batch object and throw inside a promise nobody held - which on current Node exits the
        // process. It must record like any other call and come back post-processed.
        const batch = win.batch();
        batch.setValue(2, 0, 7);
        batch.getInt(2);
        batch.getElementInfo();
        const results = await batch.send();
        check('a batched getter yields a post-processed value, not the batch',
              results[1] === 7, JSON.stringify(results[1]));
        check('and getElementInfo comes back keyed by number',
              results[2] && results[2][2] === 'TextField', JSON.stringify(results[2]));

        await checkThrows('sending a batch twice is refused',
                          () => batch.send(),
                          (error) => error instanceof Error && /already sent/.test(error.message));

        // An element the host has no value for answers null, and a typed getter must pass that
        // through rather than turn "no value" into a ProtocolError. Element 5 is never set here.
        check('getValue on an unset element is null', (await win.getValue(5)) === null);
        check('getInt on a null value is null', (await win.getInt(5)) === null);
        check('getBool on a null value is null', (await win.getBool(5)) === null);

        connection.close();
    } finally {
        host.stop();
    }
}

function testAHandlerScriptExits(directory) {
    console.log('\n=== A handler script that finishes, exits ===');
    // The cached connection must not keep the event loop alive. A handler that does its work and
    // falls off the end has to end; anything else hangs the applet command that spawned it.
    const socketPath = path.join(directory, 'exiting.sock');
    const host = new FakeHost(socketPath);
    const deadline = Date.now() + 10000;
    while (!fs.existsSync(socketPath) && Date.now() < deadline) {
        spawnSync('/bin/sleep', ['0.05']);
    }
    try {
        const script = `
            const aui = require(${JSON.stringify(CLIENT)});
            const win = new aui.Window(${JSON.stringify(WINDOW)},
                                       { endpoint: ${JSON.stringify(socketPath)} });
            win.setString(2, 'done').then(() => console.log('finished'));
        `;
        const started = Date.now();
        const result = spawnSync(process.execPath, ['-e', script],
                                 { encoding: 'utf8', timeout: 15000 });
        const elapsed = (Date.now() - started) / 1000;
        check('the handler ran its work', (result.stdout || '').trim() === 'finished',
              JSON.stringify(result.stdout));
        check('and the process exited on its own', result.status === 0 && !result.signal,
              `status=${result.status} signal=${result.signal} after ${elapsed.toFixed(1)} s`);
    } finally {
        host.stop();
    }
}

// --- tests ----------------------------------------------------------------------------------

async function testAgainstTheFakeHost(directory) {
    console.log('\n=== Against the reference fake host ===');
    const socketPath = path.join(directory, 'plain.sock');
    const host = await new FakeHost(socketPath).ready();
    try {
        const connection = new aui.Connection(socketPath, { timeout: 10 });
        const greeting = await connection.call('actionui.hello');
        check('hello reports the protocol version', greeting.protocolVersion === aui.PROTOCOL_VERSION,
              JSON.stringify(greeting));

        const win = new aui.Window(WINDOW, { connection });
        await win.setString(2, 'written by node');
        check('a value set through the client comes back',
              (await win.getString(2)) === 'written by node');

        await win.setValue(2, 0, 42);
        check('getInt reads it back as a number', (await win.getInt(2)) === 42);

        await win.setRows(5, [['a', 'b'], ['c', 'd']]);
        const rows = await win.getRows(5);
        check('rows round trip', JSON.stringify(rows) === JSON.stringify([['a', 'b'], ['c', 'd']]),
              JSON.stringify(rows));

        const info = await win.getElementInfo();
        check('getElementInfo describes the fixture', JSON.stringify(info).includes('Table'),
              JSON.stringify(info));

        await checkThrows('an unknown view is a RemoteError with the protocol code',
                          () => win.getValue(9999),
                          (error) => error instanceof aui.RemoteError && error.code === 1002);

        await checkThrows('an unknown actionui method is -32601',
                          () => connection.call('actionui.noSuchMethod'),
                          (error) => error instanceof aui.RemoteError && error.code === -32601);

        const batch = win.batch();
        batch.setString(2, 'one');
        batch.setValue(2, 0, 'two');
        const results = await batch.send();
        check('a batch sends every call in one round trip', results.length === 2,
              JSON.stringify(results));
        check('and the last one wins', (await win.getValue(2)) === 'two');

        connection.close();
        check('close leaves the connection unconnected', connection.isConnected === false);
    } finally {
        host.stop();
    }
}

async function testTheEnvironmentToken(directory) {
    console.log('\n=== The token from the environment ===');
    const socketPath = path.join(directory, 'guarded.sock');
    const host = await new FakeHost(socketPath, ['good-token']).ready();
    try {
        // Exactly what a spawned handler writes: nothing about tokens at all.
        const previous = process.env[aui.TOKEN_ENV];
        process.env[aui.TOKEN_ENV] = 'good-token';
        try {
            const connection = new aui.Connection(socketPath, { timeout: 10 });
            const win = new aui.Window(WINDOW, { connection });
            await win.setString(2, 'let in');
            check('the environment token is sent without the caller asking',
                  (await win.getString(2)) === 'let in');
            connection.close();
        } finally {
            if (previous === undefined) delete process.env[aui.TOKEN_ENV];
            else process.env[aui.TOKEN_ENV] = previous;
        }

        const refused = new aui.Connection(socketPath, { timeout: 10 });
        await checkThrows('no token is refused with 1006',
                          () => refused.call('actionui.listWindows'),
                          (error) => error instanceof aui.RemoteError && error.code === 1006);
        refused.close();

        const wrong = new aui.Connection(socketPath, { timeout: 10, token: 'not-the-token' });
        await checkThrows('a wrong token is refused',
                          () => wrong.call('actionui.listWindows'),
                          (error) => error instanceof aui.RemoteError && error.code === 1006);
        wrong.close();

        // One call, not two: a refusal here must fail this check rather than abort the run.
        const explicit = new aui.Connection(socketPath, { timeout: 10, token: 'good-token' });
        let listed = null;
        try {
            listed = await explicit.call('actionui.listWindows');
        } catch (error) {
            listed = error;
        }
        check('an explicit token is accepted', Array.isArray(listed) && listed.includes(WINDOW),
              JSON.stringify(listed instanceof Error ? String(listed) : listed));
        explicit.close();
    } finally {
        host.stop();
    }
}

function testTheTokenDescriptor(directory) {
    console.log('\n=== The token on a descriptor ===');

    // A file rather than a pipe wherever the difference does not matter: the client reads to EOF
    // either way, and a file gives the test a deterministic one.
    const tokenFile = path.join(directory, 'token');
    fs.writeFileSync(tokenFile, 'descriptor-token\n');

    const withFile = (env) => {
        const fd = fs.openSync(tokenFile, 'r');
        try {
            return runProbe(REPORT_TOKEN, { env, tokenFd: fd });
        } finally {
            fs.closeSync(fd);
        }
    };

    let reply = JSON.parse(withFile({ ACTIONUI_REMOTE_TOKEN_FD: '3' }).stdout);
    check('the descriptor token is read', reply.token === 'descriptor-token', JSON.stringify(reply));
    check('the descriptor is closed afterwards', reply.fdStillOpen === false);
    check('and the variable naming it is gone, so nothing spawned inherits it',
          reply.fdVariable === null);

    reply = JSON.parse(withFile({
        ACTIONUI_REMOTE_TOKEN_FD: '3', ACTIONUI_REMOTE_TOKEN: 'environment-token',
    }).stdout);
    check('the descriptor beats the environment', reply.token === 'descriptor-token',
          JSON.stringify(reply));

    reply = JSON.parse(runProbe(REPORT_TOKEN, {
        env: { ACTIONUI_REMOTE_TOKEN: 'environment-token' },
    }).stdout);
    check('with no descriptor the environment is used', reply.token === 'environment-token');

    // Precedence: explicit beats both. The probe builds its Connection without one, so this
    // needs its own script.
    reply = JSON.parse(runProbe(`
        const aui = require(${JSON.stringify(CLIENT)});
        const c = new aui.Connection('/nowhere.sock', { token: 'explicit' });
        console.log(JSON.stringify({ token: c.token }));
    `, { env: { ACTIONUI_REMOTE_TOKEN: 'environment-token' } }).stdout);
    check('an explicit token beats the environment', reply.token === 'explicit');

    // A descriptor that is configured but not open is a failure, never a fallback: falling back
    // would silently undo the point of the descriptor.
    reply = JSON.parse(runProbe(REPORT_TOKEN, {
        env: { ACTIONUI_REMOTE_TOKEN_FD: '42', ACTIONUI_REMOTE_TOKEN: 'environment-token' },
    }).stdout);
    check('an unreadable descriptor is an EndpointError, not a fallback',
          reply.error === 'EndpointError', JSON.stringify(reply));
    check('and it says which descriptor', String(reply.message).includes('42'), reply.message);

    reply = JSON.parse(runProbe(REPORT_TOKEN, {
        env: { ACTIONUI_REMOTE_TOKEN_FD: 'three' },
    }).stdout);
    check('a descriptor that is not a number is an EndpointError',
          reply.error === 'EndpointError', JSON.stringify(reply));

    // Only the first line is the token, and it is stripped.
    const noisy = path.join(directory, 'noisy');
    fs.writeFileSync(noisy, 'first-line\nsecond line nobody asked for\n');
    const noisyFd = fs.openSync(noisy, 'r');
    try {
        reply = JSON.parse(runProbe(REPORT_TOKEN, {
            env: { ACTIONUI_REMOTE_TOKEN_FD: '3' }, tokenFd: noisyFd,
        }).stdout);
    } finally {
        fs.closeSync(noisyFd);
    }
    check('only the first line is the token', reply.token === 'first-line', JSON.stringify(reply));

    const empty = path.join(directory, 'empty');
    fs.writeFileSync(empty, '');
    const emptyFd = fs.openSync(empty, 'r');
    try {
        reply = JSON.parse(runProbe(REPORT_TOKEN, { env: { ACTIONUI_REMOTE_TOKEN_FD: '3' }, tokenFd: emptyFd }).stdout);
    } finally {
        fs.closeSync(emptyFd);
    }
    check('an empty descriptor is an EndpointError', reply.error === 'EndpointError',
          JSON.stringify(reply));
}

function testTheDescriptorWaitIsBounded() {
    console.log('\n=== A descriptor nobody writes to ===');
    // The justification for reading the descriptor through /bin/cat rather than fs.readSync: a
    // stale ACTIONUI_REMOTE_TOKEN_FD inherited from a grandparent names whatever this process
    // happens to have at that number, and a synchronous read of something that never delivers
    // would hang the handler at load time. This must end in an error, not a hang.
    //
    // 'pipe' at index 3 gives the child a descriptor whose other end this process holds open and
    // never writes to. Takes TOKEN_DESCRIPTOR_TIMEOUT to answer, deliberately.
    const started = Date.now();
    const result = runProbe(REPORT_TOKEN, {
        env: { ACTIONUI_REMOTE_TOKEN_FD: '3' },
        tokenFd: 'pipe',
    });
    const elapsed = (Date.now() - started) / 1000;
    let reply;
    try {
        reply = JSON.parse(result.stdout);
    } catch (error) {
        check('a descriptor nobody writes to ends in an error rather than a hang', false,
              `stdout=${JSON.stringify(result.stdout)} stderr=${result.stderr}`);
        return;
    }
    check('a descriptor nobody writes to ends in an EndpointError rather than a hang',
          reply.error === 'EndpointError', JSON.stringify(reply));
    check('and it is bounded by the descriptor timeout',
          elapsed < 25, `took ${elapsed.toFixed(1)} s`);
}

async function testACreatorThatHoldsItsWriteEndOpen() {
    console.log('\n=== A creator that writes the token but does not close ===');
    // Out of contract - the creator is supposed to close its write end at once - but the Python
    // client answers it, because it stops at the first newline rather than at EOF. This client
    // reads with `head -n 1` for that reason, and this is the check that keeps the two agreeing.
    // If it ever reverts to reading to EOF, this takes the full descriptor timeout and fails.
    const child = spawn(process.execPath, ['-e', REPORT_TOKEN], {
        env: Object.assign({}, process.env, { ACTIONUI_REMOTE_TOKEN_FD: '3' }),
        stdio: ['ignore', 'pipe', 'pipe', 'pipe'],
    });
    child.stdio[3].write('held-open-token\n');       // written, and deliberately not closed

    let out = '';
    child.stdout.on('data', (chunk) => { out += chunk; });
    const started = Date.now();
    const exited = await new Promise((resolve) => {
        const timer = setTimeout(() => resolve(false), 20000);
        child.on('exit', () => { clearTimeout(timer); resolve(true); });
    });
    const elapsed = (Date.now() - started) / 1000;
    try { child.stdio[3].end(); } catch (error) { /* already gone */ }
    if (!exited) {
        try { child.kill('SIGKILL'); } catch (error) { /* already gone */ }
    }

    let reply = null;
    try {
        reply = JSON.parse(out);
    } catch (error) {
        reply = null;
    }
    check('a token followed by a newline is read even with the write end still open',
          reply !== null && reply.token === 'held-open-token',
          `stdout=${JSON.stringify(out)} after ${elapsed.toFixed(1)} s`);
    check('and it does not wait for the descriptor timeout to do it',
          elapsed < TOKEN_DESCRIPTOR_TIMEOUT_SECONDS, `took ${elapsed.toFixed(1)} s`);
}

async function testTheCommandLine(directory) {
    console.log('\n=== The command line ===');
    const socketPath = path.join(directory, 'cli.sock');
    const host = await new FakeHost(socketPath).ready();
    try {
        const run = (args) => spawnSync(process.execPath, [CLIENT, '--endpoint', socketPath].concat(args),
                                        { encoding: 'utf8', timeout: 20000 });

        let result = run(['hello']);
        check('hello exits 0', result.status === aui.EXIT_OK, result.stderr);
        check('and prints the host', result.stdout.includes('protocolVersion'), result.stdout);

        result = run(['--window', WINDOW, 'set-string', '2', 'from the command line']);
        check('set-string exits 0', result.status === aui.EXIT_OK, result.stderr);
        result = run(['--window', WINDOW, 'get-string', '2']);
        check('get-string prints what was set', result.stdout.trim() === 'from the command line',
              JSON.stringify(result.stdout));

        result = run(['--window', WINDOW, 'get-value', '9999']);
        check('a host error exits EXIT_REMOTE_ERROR', result.status === aui.EXIT_REMOTE_ERROR,
              `status=${result.status} stderr=${result.stderr}`);

        result = run(['no-such-command']);
        check('an unknown command exits EXIT_USAGE', result.status === aui.EXIT_USAGE,
              `status=${result.status}`);

        // A missing argument is a usage error. It used to store the string "undefined".
        result = run(['--window', WINDOW, 'set-string', '2']);
        check('set-string with no TEXT exits EXIT_USAGE', result.status === aui.EXIT_USAGE,
              `status=${result.status} stderr=${result.stderr}`);
        result = run(['--window', WINDOW, 'get-string', '2']);
        check('and stored nothing', result.stdout.trim() !== 'undefined',
              JSON.stringify(result.stdout));
        result = run(['--window', WINDOW, 'get-property', '2']);
        check('get-property with no NAME exits EXIT_USAGE', result.status === aui.EXIT_USAGE,
              `status=${result.status}`);
        result = run(['--window', WINDOW, 'get-value']);
        check('a missing VIEWID exits EXIT_USAGE', result.status === aui.EXIT_USAGE,
              `status=${result.status}`);

        // Without `--` there is no way to pass a value that begins with two dashes.
        result = run(['--window', WINDOW, 'set-string', '2', '--', '--not-an-option']);
        check('-- passes a value that looks like an option', result.status === aui.EXIT_OK,
              `status=${result.status} stderr=${result.stderr}`);
        result = run(['--window', WINDOW, 'get-string', '2']);
        check('and it arrived intact', result.stdout.trim() === '--not-an-option',
              JSON.stringify(result.stdout));

        // A JSON argument that parses but is the wrong shape is a usage error, as in Python.
        result = run(['--window', WINDOW, 'set-rows', '5', '"not rows"']);
        check('a JSON argument of the wrong shape exits EXIT_USAGE',
              result.status === aui.EXIT_USAGE, `status=${result.status} stderr=${result.stderr}`);

        result = spawnSync(process.execPath, [CLIENT, '--endpoint', path.join(directory, 'nothing.sock'), 'hello'],
                           { encoding: 'utf8', timeout: 20000 });
        check('nothing listening exits EXIT_NO_HOST', result.status === aui.EXIT_NO_HOST,
              `status=${result.status} stderr=${result.stderr}`);
    } finally {
        host.stop();
    }
}

// --- main -----------------------------------------------------------------------------------

async function main() {
    const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'aui-node-'));
    try {
        await testAgainstTheFakeHost(directory);
        await testTheWireShapes(directory);
        await testBatchingCarriesItsTypes(directory);
        await testRepliesThatDoNotArriveOrArriveOddly(directory);
        testAHandlerScriptExits(directory);
        await testTheEnvironmentToken(directory);
        testTheTokenDescriptor(directory);
        testTheDescriptorWaitIsBounded();
        await testACreatorThatHoldsItsWriteEndOpen();
        await testTheCommandLine(directory);
    } finally {
        fs.rmSync(directory, { recursive: true, force: true });
    }

    console.log('\n' + '='.repeat(55));
    if (failures.length === 0) {
        console.log(`All ${passed} checks PASSED.`);
        return 0;
    }
    console.error(`FAILED - ${failures.length} of ${passed + failures.length} checks:`);
    for (const failure of failures) console.error(`  - ${failure}`);
    return 1;
}

main().then((code) => { process.exitCode = code; },
            (error) => { console.error(error); process.exitCode = 1; });
