'use strict';
/**
 * actionui_remote - a Node.js client for the ActionUI Remote Protocol, version 1.
 *
 * The wire contract is ActionUIRemote/PROTOCOL.md. This is the Node counterpart of
 * ActionUIRemote/Python/actionui_remote.py and reads the same environment: a host that spawned
 * this process exports ACTIONUI_REMOTE_ENDPOINT, optionally ACTIONUI_WINDOW_UUID, and either a
 * token or a descriptor to read one from. A handler writes nothing about tokens at all.
 *
 *     const aui = require('./actionui_remote');
 *     const win = aui.Window.fromEnvironment();
 *     await win.setString(4, 'Working...');
 *     const rows = await win.getRows(5);
 *
 * Everything that talks to the host is asynchronous, because Node has no synchronous socket
 * read. The one exception is the token descriptor, which is drained when this module loads -
 * see readTokenDescriptor for why that has to happen there and not on the first request.
 *
 * CommonJS on purpose: a handler is usually a bare .js file run as `node worker.js` with no
 * package.json anywhere near it, and `require` is what works in that setting.
 *
 * Command line:
 *
 *     node actionui_remote.js [--endpoint PATH] [--window UUID] [--timeout SEC] COMMAND ...
 *     node actionui_remote.js --help
 */

const fs = require('fs');
const net = require('net');
const { execFileSync } = require('child_process');

const PROTOCOL_VERSION = 1;

const ENDPOINT_ENV = 'ACTIONUI_REMOTE_ENDPOINT';
const WINDOW_ENV = 'ACTIONUI_WINDOW_UUID';
// A host may require a token; the ones it spawned inherit it here. Read automatically, so a
// script that never heard of it keeps working against a host that turns the requirement on.
const TOKEN_ENV = 'ACTIONUI_REMOTE_TOKEN';
// Or the host hands it over on an inherited pipe and names the descriptor here, so that the
// token is never in this process's environment - where `ps` would show it to any process of the
// same user. The number is no secret; the pipe is. See readTokenDescriptor.
const TOKEN_FD_ENV = 'ACTIONUI_REMOTE_TOKEN_FD';

const DEFAULT_TIMEOUT = 15.0;           // seconds; covers the host's 10 s main-thread wait
const MAX_LINE_LENGTH = 64 * 1024 * 1024;
const SUN_PATH_LIMIT = 103;             // macOS sun_path, PROTOCOL.md section 1

const EXIT_OK = 0;
const EXIT_REMOTE_ERROR = 1;    // the host answered an error; the message carries the code
const EXIT_USAGE = 2;
const EXIT_NO_HOST = 3;         // no endpoint set, nothing listening, or a dead socket

// --- Errors ---------------------------------------------------------------------------------

/** The host answered with a JSON-RPC error object. `code` is the protocol code. */
class RemoteError extends Error {
    constructor(code, message, data = null, requestId = null, results = null) {
        super(`[${code}] ${message}`);
        this.name = 'RemoteError';
        this.code = code;
        this.remoteMessage = message;
        this.data = data;
        this.requestId = requestId;
        // Set on a batch failure: every entry's outcome, in the order sent.
        this.results = results;
    }
}

/** No host to talk to, or a token this process was told to fetch and could not. */
class EndpointError extends Error {
    constructor(message) {
        super(message);
        this.name = 'EndpointError';
    }
}

/** The host said something the protocol does not allow. */
class ProtocolError extends Error {
    constructor(message) {
        super(message);
        this.name = 'ProtocolError';
    }
}

// --- Small value types ----------------------------------------------------------------------

const ButtonRole = Object.freeze({
    DEFAULT: 'default',
    CANCEL: 'cancel',
    DESTRUCTIVE: 'destructive',
});

const ModalStyle = Object.freeze({
    SHEET: 'sheet',
    FULL_SCREEN_COVER: 'fullScreenCover',
});

/** A button for presentAlert and presentConfirmationDialog. */
class DialogButton {
    constructor(title, { role = null, actionId = null } = {}) {
        this.title = title;
        this.role = role;
        this.actionId = actionId;
    }

    toJSON() {
        const json = { title: this.title };
        if (this.role != null && this.role !== ButtonRole.DEFAULT) json.role = this.role;
        if (this.actionId != null) json.actionID = this.actionId;
        return json;
    }

    /** Accept a DialogButton, a plain object already in wire shape, or a bare title. */
    static coerce(value) {
        if (value instanceof DialogButton) return value.toJSON();
        if (typeof value === 'string') return { title: value };
        if (value !== null && typeof value === 'object') return value;
        throw new TypeError('a button must be a DialogButton, an object, or a title string');
    }
}

/** Where insertElement and insertRow put the new child. */
class InsertPosition {
    constructor(jsonValue) {
        this._json = jsonValue;
    }

    toJSON() {
        return this._json;
    }

    // The wire shape is PROTOCOL.md section 6: an object with a "kind", and the index or sibling
    // under its own name. Not {at: n} - the host reads position.kind and rejects anything else.
    static append() { return new InsertPosition({ kind: 'append' }); }
    static prepend() { return new InsertPosition({ kind: 'prepend' }); }
    static at(index) { return new InsertPosition({ kind: 'at', index: intOrThrow(index, 'index') }); }

    static before(siblingId) {
        return new InsertPosition({ kind: 'before', siblingID: intOrThrow(siblingId, 'siblingId') });
    }

    static after(siblingId) {
        return new InsertPosition({ kind: 'after', siblingID: intOrThrow(siblingId, 'siblingId') });
    }

    static coerce(value) {
        if (value === null || value === undefined) return null;
        if (value instanceof InsertPosition) return value.toJSON();
        // A bare 'append' / 'prepend' is sugar for the object; anything else a caller hands over
        // as an object is passed through for the host to validate.
        if (typeof value === 'string') return { kind: value };
        if (typeof value === 'object') return value;
        throw new TypeError("position must be an InsertPosition, an object, or 'append'/'prepend'");
    }
}

function intOrThrow(value, name) {
    if (typeof value !== 'number' || !Number.isInteger(value)) {
        throw new TypeError(`${name} must be an integer, not ${JSON.stringify(value)}`);
    }
    return value;
}

// --- The token on a descriptor --------------------------------------------------------------

// Read once and held for the life of the process: the pipe is drained by its first reader, so
// there is nothing to read a second time. null means "not read yet", not "no token".
let _tokenFromDescriptor = null;
// And the failure, if it failed, so that every later attempt reports the same thing.
let _tokenDescriptorError = null;

// A token is 64 characters. The cap is not about tokens, it is about a descriptor that is not
// the pipe the contract describes - a tty, or a socket nobody closed - which would otherwise be
// read until it blocked forever or exhausted memory.
const MAX_TOKEN_LENGTH = 4096;
// How long to wait for bytes that should already be there. The creator writes the token and
// closes its write end before the child can run, so a correct handoff never waits at all; this
// only bounds a misconfigured descriptor whose write end someone holds open and never writes -
// which the size cap cannot catch, there being nothing to count.
const TOKEN_DESCRIPTOR_TIMEOUT = 10.0;
const MAX_DESCRIPTOR = 2 ** 31 - 1;

function tokenDescriptorFailure(message, fd = null) {
    // Recorded because the answer must not change between calls. The descriptor is closed
    // because the reader's half of the contract is to leave nothing for its children to inherit,
    // and that is no less true of one that turned out to be unusable. The variable is
    // deliberately NOT removed: it is the only remaining trace of how this process was
    // configured, and the recorded message, not a re-read, is what later attempts report.
    _tokenDescriptorError = message;
    if (fd !== null) {
        try { fs.closeSync(fd); } catch (error) { /* nothing left to salvage */ }
    }
    throw new EndpointError(message);
}

/**
 * The token from $ACTIONUI_REMOTE_TOKEN_FD, or null when no descriptor is configured.
 *
 * The lifecycle has two owners (PROTOCOL.md section 10). The process that creates the pipe
 * writes the token and a newline and closes its write end at once. This side reads once, then
 * closes the descriptor and removes the variable, so that nothing this script spawns inherits an
 * open descriptor to a drained pipe, or a variable naming one. A child that needs the bridge
 * must be handed its own token.
 *
 * A descriptor that is configured but cannot be read is a failure, never a fallback to the
 * environment: falling back would silently undo the point of the descriptor, which is that the
 * token is not in the environment at all.
 *
 * Descriptors 0, 1 and 2 are accepted. The number is the creator's to choose, and a creator that
 * can only hand over stdin - Foundation's Process, for one - is still a valid creator.
 *
 * The read is delegated to `head -n 1` rather than done with fs.readSync, and that is the one
 * place this client cannot copy the Python one. The wait has to be bounded: a stale
 * ACTIONUI_REMOTE_TOKEN_FD inherited from a grandparent names whatever this process happens to
 * have at that number, and a tty or an unclosed socket there would hang a synchronous read for
 * good - at load time, before the handler has run a line. Python bounds it with select.poll;
 * Node has no synchronous poll, no fcntl, and no timeout on fs.readSync. execFileSync does have
 * one, and passing the descriptor as the child's stdin reads the pipe under it.
 *
 * `head -n 1` and not `cat`, because Python stops at the first newline rather than at EOF. A
 * creator that writes the token and a newline but holds its write end open is out of contract,
 * but it is answered rather than timed out - and the two clients agreeing matters more here than
 * either behavior does on its own.
 *
 * The token reaches us through the child's stdout pipe, never its argv or environment, so
 * nothing is exposed that was not already.
 */
function readTokenDescriptor() {
    if (_tokenFromDescriptor !== null) return _tokenFromDescriptor;
    if (_tokenDescriptorError !== null) throw new EndpointError(_tokenDescriptorError);

    const raw = process.env[TOKEN_FD_ENV];
    if (!raw) return null;
    if (!/^[0-9]+$/.test(raw)) {
        tokenDescriptorFailure(`${TOKEN_FD_ENV} must be a descriptor number, not ${JSON.stringify(raw)}`);
    }
    const fd = Number(raw);
    if (fd > MAX_DESCRIPTOR) {
        tokenDescriptorFailure(`${TOKEN_FD_ENV} is not a descriptor number: ${JSON.stringify(raw)}`);
    }

    let output;
    try {
        output = execFileSync('/usr/bin/head', ['-n', '1'], {
            stdio: [fd, 'pipe', 'ignore'],
            timeout: TOKEN_DESCRIPTOR_TIMEOUT * 1000,
            maxBuffer: MAX_TOKEN_LENGTH,
            encoding: 'buffer',
        });
    } catch (error) {
        // A timeout, a descriptor that is not open at all, and more than MAX_TOKEN_LENGTH bytes
        // with nobody closing the write end all arrive here, and all mean the same thing: this
        // is not the token pipe the contract describes.
        if (error && error.code === 'ETIMEDOUT') {
            tokenDescriptorFailure(
                `descriptor ${fd} (${TOKEN_FD_ENV}) produced nothing in ${TOKEN_DESCRIPTOR_TIMEOUT} `
                + 'seconds; the token should already be there', fd);
        }
        if (error && error.code === 'ENOBUFS') {
            tokenDescriptorFailure(
                `descriptor ${fd} (${TOKEN_FD_ENV}) gave more than ${MAX_TOKEN_LENGTH} bytes; `
                + 'it is not the token pipe', fd);
        }
        tokenDescriptorFailure(
            `descriptor ${fd} (${TOKEN_FD_ENV}) could not be read: ${error && error.message}`, fd);
    }

    // Only the first line is the token; the contract says the creator writes one and a newline.
    const text = output.toString('utf8');
    const newline = text.indexOf('\n');
    const token = (newline >= 0 ? text.slice(0, newline) : text).trim();
    if (!token) {
        tokenDescriptorFailure(`nothing could be read from descriptor ${fd} (${TOKEN_FD_ENV})`, fd);
    }

    try { fs.closeSync(fd); } catch (error) { /* the token is in hand; a failed close changes nothing */ }
    delete process.env[TOKEN_FD_ENV];
    _tokenFromDescriptor = token;
    return token;
}

// Drained at load, not at first use. Until it is read, this process holds an open descriptor to
// a live token and exports the variable naming it, so everything it spawns inherits both - and a
// handler that runs a subprocess before its first bridge call would hand that child its token,
// or have the token read out from under it. PROTOCOL.md section 10 wants the descriptor closed
// out and the variable gone; the earliest this module can do that is now.
//
// A failure here is recorded, not thrown: loading a module must not fail over a token nothing
// has asked for yet, and the caller sees the same error at the point it does ask.
try {
    readTokenDescriptor();
} catch (error) {
    if (!(error instanceof EndpointError)) throw error;
}

// --- Connection -----------------------------------------------------------------------------

const _connections = new Map();

/**
 * One socket to one host. Lazily connected, reconnects once on a dead socket.
 *
 * Requests are answered out of a map keyed by JSON-RPC id, so several may be in flight at once -
 * though the host processes one connection strictly in order, so they are answered in order too.
 */
class Connection {
    constructor(endpoint, { timeout = DEFAULT_TIMEOUT, token = null } = {}) {
        if (!endpoint) throw new EndpointError('no ActionUI remote endpoint given');
        this.endpoint = endpoint;
        this.timeout = timeout;
        // An explicit token wins; otherwise the descriptor, then the environment, consulted per
        // request rather than captured here. connect() caches one Connection per endpoint, so
        // capturing would pin whatever the environment held the first time anything connected -
        // and a host that starts serving later would never be seen. The descriptor is the
        // exception and is cached module-wide: a pipe can only be read once.
        this._explicitToken = token;
        this._socket = null;
        this._buffer = '';
        this._nextId = 1;
        this._pending = new Map();
        this._connecting = null;
    }

    /**
     * The token this connection sends: the explicit one, else the one on
     * $ACTIONUI_REMOTE_TOKEN_FD, else $ACTIONUI_REMOTE_TOKEN now.
     *
     * Throws EndpointError when a descriptor is configured but unreadable - a host that went to
     * the trouble of keeping the token out of the environment must not be answered with an
     * environment token that a `ps` sweep could have supplied.
     */
    get token() {
        if (this._explicitToken !== null && this._explicitToken !== undefined) {
            return this._explicitToken;
        }
        const fromDescriptor = readTokenDescriptor();
        if (fromDescriptor) return fromDescriptor;
        return process.env[TOKEN_ENV] || '';
    }

    get isConnected() {
        return this._socket !== null;
    }

    close() {
        const socket = this._socket;
        this._socket = null;
        this._failPending(new EndpointError('the connection was closed'));
        if (socket) {
            socket.removeAllListeners();
            socket.destroy();
        }
    }

    _failPending(error) {
        for (const entry of this._pending.values()) {
            clearTimeout(entry.timer);
            entry.reject(error);
        }
        this._pending.clear();
    }

    _connect() {
        if (this._socket) return Promise.resolve(this._socket);
        if (this._connecting) return this._connecting;

        if (Buffer.byteLength(this.endpoint, 'utf8') > SUN_PATH_LIMIT) {
            return Promise.reject(new EndpointError(
                `socket path is too long for sun_path (limit ${SUN_PATH_LIMIT} bytes): ${this.endpoint}`));
        }

        this._connecting = new Promise((resolve, reject) => {
            const socket = net.connect(this.endpoint);
            socket.setEncoding('utf8');
            const onError = (error) => {
                socket.removeAllListeners();
                socket.destroy();
                this._connecting = null;
                if (error && (error.code === 'ENOENT' || error.code === 'ECONNREFUSED')) {
                    reject(new EndpointError(
                        `no ActionUI host is listening at ${this.endpoint} (${error.code})`));
                    return;
                }
                reject(new EndpointError(`cannot connect to ${this.endpoint}: ${error && error.message}`));
            };
            socket.once('error', onError);
            socket.once('connect', () => {
                socket.removeListener('error', onError);
                socket.on('data', (chunk) => this._onData(chunk));
                socket.on('error', () => this._onDisconnect());
                socket.on('close', () => this._onDisconnect());
                // A cached connection must not be the reason a handler script never exits.
                // connect() keeps one per endpoint for the life of the process, and a referenced
                // socket keeps the event loop alive forever - so a three-line handler would hang
                // after doing its work, and the 'exit' hook that closes connections would never
                // run because the process never reaches exit. While a request is outstanding its
                // timeout timer holds the loop open, which is the only time it needs holding.
                socket.unref();
                this._socket = socket;
                this._connecting = null;
                resolve(socket);
            });
        });
        return this._connecting;
    }

    _onDisconnect() {
        if (this._socket) {
            this._socket.removeAllListeners();
            this._socket.destroy();
            this._socket = null;
        }
        this._buffer = '';
        this._failPending(new EndpointError(`the host at ${this.endpoint} closed the connection`));
    }

    _onData(chunk) {
        this._buffer += chunk;
        if (this._buffer.length > MAX_LINE_LENGTH) {
            const error = new ProtocolError(
                `the host sent more than ${MAX_LINE_LENGTH} bytes with no newline`);
            this._failPending(error);
            this._onDisconnect();
            return;
        }
        let newline = this._buffer.indexOf('\n');
        while (newline >= 0) {
            const line = this._buffer.slice(0, newline);
            this._buffer = this._buffer.slice(newline + 1);
            if (line.trim()) this._deliver(line);
            newline = this._buffer.indexOf('\n');
        }
    }

    _deliver(line) {
        let value;
        try {
            value = JSON.parse(line);
        } catch (error) {
            this._failPending(new ProtocolError(`the host sent invalid JSON: ${error.message}`));
            return;
        }
        // A batch reply is an array; it is claimed by the entry that sent the batch, which is
        // found by the id of any entry in it. An id that matches nothing pending is a reply to
        // something already timed out and is dropped.
        const entry = Array.isArray(value) ? this._claimBatch(value) : this._pending.get(value && value.id);
        if (!entry) return;
        this._pending.delete(entry.id);
        clearTimeout(entry.timer);
        entry.resolve(value);
    }

    // Batch replies may come back in any order and may contain error objects with a null id, so
    // the batch is found by the first id in it that is pending and was sent as a batch. Matching
    // "the only pending request" instead would hand a stale batch reply to an unrelated single
    // request, which then fails with "not an object" while its own reply is dropped.
    _claimBatch(entries) {
        for (const entry of entries) {
            if (!entry || entry.id === null || entry.id === undefined) continue;
            const pending = this._pending.get(entry.id);
            if (pending && pending.isBatch) return pending;
        }
        return null;
    }

    _envelope(method, params, notification = false) {
        const envelope = { jsonrpc: '2.0', method, params: Object.assign({}, params) };
        // On every request, not once per connection. The host remembers a connection that has
        // authenticated, so this costs nothing after the first; sending it every time is what
        // lets the one-connection-per-request pattern (PROTOCOL.md section 1) work without an
        // extra round trip, and what makes a reconnect transparent. The connection's token
        // wins over anything of that name in `params`: `token` is reserved on every method.
        const token = this.token;
        if (token) envelope.params.token = token;
        if (!notification) envelope.id = this._nextId++;
        return envelope;
    }

    async _roundTrip(payload, expectReply) {
        // One reconnect, and only one, and only for a failure to send. A failure while waiting
        // for the reply is deliberately not retried: the request may already have been applied,
        // and resending an appendRows would apply it twice. Same rule as the Python client.
        //
        // Where the two differ: Python's blocking send raises EPIPE on a dead socket and retries
        // there. Node's write buffers and reports the failure later, so a host that closed this
        // connection while the process was idle is usually noticed before the next call - the
        // FIN arrives, 'close' fires, _onDisconnect drops the socket, and _connect makes a fresh
        // one. If the FIN is still in flight when the write goes out, the request is lost and
        // the caller gets the timeout rather than a fast reconnect. That is the safe side of the
        // trade: retrying there would be the double-apply the rule above exists to prevent.
        for (let attempt = 1; attempt <= 2; attempt += 1) {
            let socket;
            try {
                socket = await this._connect();
            } catch (error) {
                throw error;                    // EndpointError: nothing to reconnect to
            }
            const reply = await this._writeAndWait(socket, payload, expectReply);
            if (reply !== RETRY) return reply;
            if (attempt === 2) {
                throw new EndpointError(`the host at ${this.endpoint} closed the connection`);
            }
        }
        return null;
    }

    _writeAndWait(socket, payload, expectReply) {
        return new Promise((resolve, reject) => {
            if (!expectReply) {
                socket.write(payload, (error) => {
                    if (error) {
                        this._onDisconnect();
                        resolve(RETRY);
                        return;
                    }
                    resolve(null);
                });
                return;
            }
            const id = payload.id;
            const timer = setTimeout(() => {
                this._pending.delete(id);
                // Drop the socket with it. A reply that arrives after the caller has given up
                // has nowhere to go, and leaving the connection open would let it be read while
                // some later request is outstanding. The Python client closes here too.
                this._onDisconnect();
                reject(new EndpointError(
                    `the host at ${this.endpoint} did not answer within ${this.timeout} seconds`));
            }, this.timeout * 1000);
            this._pending.set(id, { id, timer, resolve, reject, isBatch: Boolean(payload.isBatch) });
            socket.write(payload.line, (error) => {
                if (error && this._pending.has(id)) {
                    this._pending.delete(id);
                    clearTimeout(timer);
                    this._onDisconnect();
                    resolve(RETRY);
                }
            });
        });
    }

    /** Call one method and return its result. Throws RemoteError on an error reply. */
    async call(method, params = null) {
        const envelope = this._envelope(method, params);
        const reply = await this._roundTrip(
            { id: envelope.id, line: JSON.stringify(envelope) + '\n' }, true);
        return unpack(reply, envelope.id);
    }

    /** Fire and forget: the host executes the method and sends no reply. */
    async notify(method, params = null) {
        const envelope = this._envelope(method, params, true);
        await this._roundTrip(JSON.stringify(envelope) + '\n', false);
    }

    /**
     * Send several calls as one JSON-RPC batch. `calls` is an array of [method, params] pairs.
     * Returns an array with one entry per call: the result, or a RemoteError instance.
     */
    async callBatch(calls) {
        if (!Array.isArray(calls) || calls.length === 0) return [];
        const envelopes = calls.map(([method, params]) => this._envelope(method, params));
        const first = envelopes[0].id;
        const reply = await this._roundTrip(
            { id: first, isBatch: true, line: JSON.stringify(envelopes) + '\n' }, true);
        if (!Array.isArray(reply)) {
            if (reply && reply.error) {
                throw new RemoteError(reply.error.code, reply.error.message, reply.error.data, reply.id);
            }
            throw new ProtocolError('the host answered a batch with something that is not an array');
        }
        const byId = new Map();
        for (const entry of reply) {
            if (entry && entry.id !== undefined) byId.set(entry.id, entry);
        }
        return envelopes.map((envelope) => {
            const entry = byId.get(envelope.id);
            if (!entry) {
                return new ProtocolError(`the host sent no reply for request ${envelope.id}`);
            }
            if (entry.error) {
                return new RemoteError(entry.error.code, entry.error.message, entry.error.data, entry.id);
            }
            return entry.result === undefined ? null : entry.result;
        });
    }
}

// A sentinel: the socket died mid-write and the caller should reconnect once.
const RETRY = Symbol('retry');

function unpack(reply, expectedId) {
    if (reply === null || typeof reply !== 'object' || Array.isArray(reply)) {
        throw new ProtocolError('the host answered a request with something that is not an object');
    }
    if (reply.jsonrpc !== '2.0') {
        throw new ProtocolError(`malformed reply, no "jsonrpc": "2.0": ${JSON.stringify(reply)}`);
    }
    if (reply.error) {
        throw new RemoteError(reply.error.code, reply.error.message, reply.error.data, reply.id);
    }
    if (reply.id !== expectedId) {
        throw new ProtocolError(`the host answered request ${expectedId} with id ${reply.id}`);
    }
    return reply.result === undefined ? null : reply.result;
}

/**
 * The process-wide Connection for an endpoint (default: $ACTIONUI_REMOTE_ENDPOINT).
 *
 * One connection per endpoint is shared by every Window in the process.
 */
function connect({ endpoint = null, timeout = DEFAULT_TIMEOUT, token = null } = {}) {
    const target = endpoint || process.env[ENDPOINT_ENV];
    if (!target) {
        throw new EndpointError(
            `${ENDPOINT_ENV} is not set; this host did not start the ActionUI remote server`);
    }
    let connection = _connections.get(target);
    if (!connection) {
        connection = new Connection(target, { timeout, token });
        _connections.set(target, connection);
    } else if (connection.timeout !== timeout) {
        connection.timeout = timeout;
    }
    return connection;
}

/** The host's actionui.hello: protocol version, host name and version, methods, windows. */
function hello(endpoint = null) {
    return connect({ endpoint }).call('actionui.hello');
}

function closeAllConnections() {
    for (const connection of _connections.values()) connection.close();
    _connections.clear();
}

process.on('exit', closeAllConnections);

// --- Window ---------------------------------------------------------------------------------

/** One ActionUI window, addressed by UUID. Every method returns a Promise. */
class Window {
    constructor(uuid, { endpoint = null, connection = null, timeout = DEFAULT_TIMEOUT } = {}) {
        if (!uuid) throw new TypeError('a window UUID is required');
        this.uuid = uuid;
        this._connection = connection;
        this._endpoint = endpoint;
        this._timeout = timeout;
    }

    /** The window this process was started for, named by $ACTIONUI_WINDOW_UUID. */
    static fromEnvironment({ timeout = DEFAULT_TIMEOUT } = {}) {
        const uuid = process.env[WINDOW_ENV];
        if (!uuid) {
            throw new EndpointError(
                `${WINDOW_ENV} is not set; this process was not started for an ActionUI window`);
        }
        return new Window(uuid, { timeout });
    }

    get connection() {
        if (!this._connection) {
            this._connection = connect({ endpoint: this._endpoint, timeout: this._timeout });
        }
        return this._connection;
    }

    _params(more = null, viewId = null, viewPartId = null) {
        const params = { window: this.uuid };
        if (viewId !== null) params.viewID = intOrThrow(viewId, 'viewId');
        if (viewPartId !== null && viewPartId !== 0) {
            params.viewPartID = intOrThrow(viewPartId, 'viewPartId');
        }
        return more ? Object.assign(params, more) : params;
    }

    /**
     * Every call this class makes goes through here, and that is what makes batching honest:
     * `Batch` records by overriding this one method, so a batched call builds its params through
     * exactly the same code as a direct one and gets exactly the same post-processing. The
     * alternative - a parallel table of method names and shapes - is how the two drift apart.
     */
    _invoke(method, params, post = null) {
        const promise = this.connection.call(method, params);
        return post ? promise.then(post) : promise;
    }

    call(method, params = null) {
        return this._invoke(method, this._params(params));
    }

    /** Collect several calls and send them as one round trip. See Batch. */
    batch({ throwOnError = true } = {}) {
        return new Batch(this, throwOnError);
    }

    // -- discovery

    getElementInfo() {
        return this._invoke('actionui.getElementInfo', this._params(), POST.elementInfo);
    }

    contentSizeLimits() {
        return this._invoke('actionui.contentSizeLimits', this._params(), POST.sizeLimits);
    }

    // -- values

    getValue(viewId, viewPartId = 0) {
        return this._invoke('actionui.getValue', this._params(null, viewId, viewPartId));
    }

    setValue(viewId, viewPartId, value) {
        return this._invoke('actionui.setValue', this._params({ value }, viewId, viewPartId));
    }

    getString(viewId, viewPartId = 0, contentType = null) {
        const more = contentType === null ? null : { contentType };
        return this._invoke('actionui.getValueString', this._params(more, viewId, viewPartId));
    }

    setString(viewId, value, viewPartId = 0, contentType = null) {
        const more = { value: String(value) };
        if (contentType !== null) more.contentType = contentType;
        return this._invoke('actionui.setValueString', this._params(more, viewId, viewPartId));
    }

    getInt(viewId, viewPartId = 0) {
        return this._invoke('actionui.getValue', this._params(null, viewId, viewPartId), POST.int);
    }

    setInt(viewId, value, viewPartId = 0) {
        return this.setValue(viewId, viewPartId, intOrThrow(value, 'value'));
    }

    getDouble(viewId, viewPartId = 0) {
        return this._invoke('actionui.getValue', this._params(null, viewId, viewPartId), POST.double);
    }

    setDouble(viewId, value, viewPartId = 0) {
        return this.setValue(viewId, viewPartId, Number(value));
    }

    getBool(viewId, viewPartId = 0) {
        return this._invoke('actionui.getValue', this._params(null, viewId, viewPartId), POST.bool);
    }

    setBool(viewId, value, viewPartId = 0) {
        return this.setValue(viewId, viewPartId, Boolean(value));
    }

    // -- properties and state

    getProperty(viewId, name) {
        return this._invoke('actionui.getProperty', this._params({ name }, viewId));
    }

    setProperty(viewId, name, value) {
        return this._invoke('actionui.setProperty', this._params({ name, value }, viewId));
    }

    /** Sugar for the `disabled` property (omc_enable / omc_disable), which is what the engine has. */
    setEnabled(viewId, enabled) {
        return this.setProperty(viewId, 'disabled', !enabled);
    }

    setHidden(viewId, hidden) {
        return this.setProperty(viewId, 'hidden', Boolean(hidden));
    }

    getState(viewId, key) {
        return this._invoke('actionui.getState', this._params({ key }, viewId));
    }

    getStateString(viewId, key) {
        return this._invoke('actionui.getStateString', this._params({ key }, viewId));
    }

    setState(viewId, key, value) {
        return this._invoke('actionui.setState', this._params({ key, value }, viewId));
    }

    setStateFromString(viewId, key, value) {
        return this._invoke('actionui.setStateString',
                            this._params({ key, value: String(value) }, viewId));
    }

    // -- rows and selection

    getColumnCount(viewId) {
        return this._invoke('actionui.getColumnCount', this._params(null, viewId));
    }

    getRows(viewId) {
        return this._invoke('actionui.getRows', this._params(null, viewId));
    }

    setRows(viewId, rows) {
        return this._invoke('actionui.setRows', this._params({ rows: coerceRows(rows) }, viewId));
    }

    appendRows(viewId, rows) {
        return this._invoke('actionui.appendRows', this._params({ rows: coerceRows(rows) }, viewId));
    }

    clearRows(viewId) {
        return this._invoke('actionui.clearRows', this._params(null, viewId));
    }

    selectRow(viewId, index) {
        return this._invoke('actionui.selectRow',
                            this._params({ index: intOrThrow(index, 'index') }, viewId));
    }

    selectRowWithContent(viewId, text, column = null) {
        const more = { text: String(text) };
        if (column !== null) more.column = intOrThrow(column, 'column');
        return this._invoke('actionui.selectRowWithContent', this._params(more, viewId));
    }

    clearSelection(viewId) {
        return this._invoke('actionui.clearSelection', this._params(null, viewId));
    }

    // -- structural mutation

    // The parent is `parentID`, a named param of its own - not the `viewID` every other method
    // sends. The host reads parentID and would reject viewID as a missing parameter.

    insertElement(parentId, element, { container = null, position = null } = {}) {
        const more = { parentID: intOrThrow(parentId, 'parentId'), element };
        if (container !== null) more.container = container;
        if (position !== null) more.position = InsertPosition.coerce(position);
        return this._invoke('actionui.insertElement', this._params(more));
    }

    insertRow(parentId, cells, { container = null, position = null } = {}) {
        const more = { parentID: intOrThrow(parentId, 'parentId'), cells: Array.from(cells) };
        if (container !== null) more.container = container;
        if (position !== null) more.position = InsertPosition.coerce(position);
        return this._invoke('actionui.insertRow', this._params(more));
    }

    removeElement(viewId) {
        return this._invoke('actionui.removeElement', this._params(null, viewId));
    }

    // -- presentation

    /**
     * Present a sheet or full-screen cover. The host takes the content one of three ways and
     * exactly one must be given: `element` (an object), `json` (JSON or plist text, with
     * `format`), or `path` (a resource name or path the host resolves).
     *
     * `source` is the shorthand the in-process module takes positionally: an object means
     * `element`, a string means `json`.
     */
    presentModal({ source = null, element = null, json = null, path = null,
                   format = null, style = null, onDismissActionId = null } = {}) {
        if (source !== null) {
            if (typeof source === 'object') element = source;
            else if (typeof source === 'string') json = source;
            else throw new TypeError('source must be an object (element) or a string (JSON/plist text)');
        }
        const more = {};
        if (element !== null) more.element = element;
        else if (json !== null) more.json = String(json);
        else if (path !== null) more.path = String(path);
        else throw new TypeError('presentModal needs element, json, or path');
        if (format !== null) more.format = format;
        if (style !== null) more.style = style;
        if (onDismissActionId !== null) more.onDismissActionID = onDismissActionId;
        return this._invoke('actionui.presentModal', this._params(more));
    }

    dismissModal() {
        return this._invoke('actionui.dismissModal', this._params());
    }

    presentAlert(title, { message = null, buttons = null } = {}) {
        const more = { title: String(title) };
        if (message !== null) more.message = String(message);
        if (buttons !== null) more.buttons = buttons.map(DialogButton.coerce);
        return this._invoke('actionui.presentAlert', this._params(more));
    }

    /** `buttons` is required and must be a non-empty array, as the in-process module requires. */
    presentConfirmationDialog(title, { message = null, buttons = null } = {}) {
        if (!Array.isArray(buttons) || buttons.length === 0) {
            throw new TypeError('presentConfirmationDialog needs a non-empty array of buttons');
        }
        const more = { title: String(title), buttons: buttons.map(DialogButton.coerce) };
        if (message !== null) more.message = String(message);
        return this._invoke('actionui.presentConfirmationDialog', this._params(more));
    }

    dismissDialog() {
        return this._invoke('actionui.dismissDialog', this._params());
    }

    presentToast(message, { duration = null, actionTitle = null, actionId = null } = {}) {
        const more = { message: String(message) };
        if (duration !== null) more.duration = Number(duration);
        if (actionTitle !== null) more.actionTitle = String(actionTitle);
        if (actionId !== null) more.actionID = String(actionId);
        return this._invoke('actionui.presentToast', this._params(more));
    }

    dismissToast() {
        return this._invoke('actionui.dismissToast', this._params());
    }
}

// What the typed getters do to a raw wire result, shared with Batch so that a batched
// b.getInt(...) yields the same value as win.getInt(...). Null passes through as null: the host
// says "no value" that way, and it is not a protocol violation.
const POST = {
    int: (value) => (value === null ? null : coerceNumber(value, 'an integer')),
    double: (value) => (value === null ? null : coerceNumber(value, 'a number')),
    bool: (value) => (value === null ? null : Boolean(value)),
    elementInfo: (value) => {
        const out = {};
        for (const [key, type] of Object.entries(value || {})) out[Number(key)] = type;
        return out;
    },
    sizeLimits: (value) => (value
        ? [value.minWidth, value.minHeight, value.maxWidth, value.maxHeight]
        : null),
};

function coerceNumber(value, what) {
    if (typeof value === 'number') return value;
    if (typeof value === 'string' && value.trim() !== '' && Number.isFinite(Number(value))) {
        return Number(value);
    }
    throw new ProtocolError(`the host answered with ${JSON.stringify(value)}, which is not ${what}`);
}

// Cells go over the wire as strings, and the host refuses anything else. A bare string row is
// rejected rather than wrapped: it is almost always one row written as `['a', 'b']` by mistake,
// and silently turning it into two one-cell rows would hide that.
function coerceRows(rows) {
    if (!Array.isArray(rows)) throw new TypeError('rows must be an array of arrays');
    return rows.map((row) => {
        if (typeof row === 'string') {
            throw new TypeError(`each row must be an array of cells, not a string: ${JSON.stringify(row)}`);
        }
        if (!Array.isArray(row)) throw new TypeError('each row must be an array of cells');
        return row.map((cell) => String(cell));
    });
}

// --- Batch ----------------------------------------------------------------------------------

/**
 * Collect several window calls and send them as one JSON-RPC batch.
 *
 *     const batch = win.batch();
 *     batch.setString(4, 'one');
 *     batch.setString(5, 'two');
 *     const results = await batch.send();
 *
 * Every Window method is available and returns the Batch rather than a Promise, so calls chain.
 * `send()` resolves to the results in order; with throwOnError (the default) the first
 * RemoteError among them is thrown instead, carrying all of the results on `.results`.
 */
class Batch {
    constructor(window, throwOnError = true) {
        this._window = window;
        this._throwOnError = throwOnError;
        this._calls = [];       // [method, params, post]
        this._sent = false;

        // Every Window method, recorded rather than sent. The recorder is a Window with one
        // method replaced, so a batched call runs the real argument handling and carries the
        // real post-processing - a batched getInt yields a number exactly as a direct one does.
        // Nothing here awaits, which is the other half of the point: an async getter awaiting a
        // recorder would resolve to the recorder and blow up in a promise nobody holds.
        const recorder = Object.create(Object.getPrototypeOf(window));
        Object.assign(recorder, window);
        recorder._invoke = (method, params, post = null) => {
            this._calls.push([method, params, post]);
            return undefined;
        };

        for (const name of Object.getOwnPropertyNames(Window.prototype)) {
            if (name === 'constructor' || name === 'batch' || name.startsWith('_')) continue;
            const member = Object.getOwnPropertyDescriptor(Window.prototype, name);
            if (typeof member.value !== 'function') continue;
            this[name] = (...args) => {
                member.value.apply(recorder, args);
                return this;        // chainable; the value comes back from send()
            };
        }
    }

    get length() {
        return this._calls.length;
    }

    /**
     * Send everything recorded as one batch. Resolves to the results in order, each
     * post-processed as the direct call would have been, or a RemoteError in a failed slot.
     */
    async send() {
        if (this._sent) throw new Error('this batch was already sent');
        if (this._calls.length === 0) {
            this._sent = true;
            return [];
        }
        const calls = this._calls;
        // Cleared before the round trip, not after it: a transport failure must not leave the
        // calls recorded, or a caller that catches and retries sends them all a second time.
        this._calls = [];
        this._sent = true;

        const raw = await this._window.connection.callBatch(calls.map(([method, params]) => [method, params]));
        const results = raw.map((outcome, index) => {
            const post = calls[index][2];
            return (outcome instanceof Error || post === null) ? outcome : post(outcome);
        });
        if (this._throwOnError) {
            for (const result of results) {
                if (result instanceof RemoteError) {
                    result.results = results;
                    throw result;
                }
            }
        }
        return results;
    }
}

// --- Command line ---------------------------------------------------------------------------

function usage() {
    return [
        'usage: node actionui_remote.js [--endpoint PATH] [--window UUID] [--timeout SEC] COMMAND',
        '',
        'commands:',
        '  hello                            print the host\'s actionui.hello',
        '  windows                          print every window UUID, one per line',
        '  elements                         print the window\'s element ids and types as JSON',
        '  get-value VIEWID [--part N]      print an element\'s value as JSON',
        '  set-value VIEWID JSON [--part N] set an element\'s value from JSON',
        '  get-string VIEWID [--part N] [--content-type TYPE]',
        '  set-string VIEWID TEXT [--part N] [--content-type TYPE]',
        '  get-rows VIEWID                  print a Table\'s rows as JSON',
        '  set-rows VIEWID JSON             set a Table\'s rows from a JSON array of arrays',
        '  get-property VIEWID NAME         print a property as JSON',
        '  set-property VIEWID NAME JSON    set a property from JSON',
        '  get-state VIEWID KEY             print a state key as JSON',
        '  set-state VIEWID KEY JSON        set a state key from JSON',
        '  call METHOD [JSON]               call any method, host methods included',
        '',
        `The window defaults to $${WINDOW_ENV} and the endpoint to $${ENDPOINT_ENV}.`,
        'A token is picked up from $' + TOKEN_FD_ENV + ' or $' + TOKEN_ENV + ' without being asked for.',
        '',
        `exit codes: ${EXIT_OK} ok, ${EXIT_REMOTE_ERROR} the host answered an error, `
            + `${EXIT_USAGE} usage, ${EXIT_NO_HOST} no host`,
    ].join('\n');
}

function parseArguments(argv) {
    const options = { endpoint: null, window: null, timeout: DEFAULT_TIMEOUT, part: 0, contentType: null };
    const positional = [];
    for (let index = 0; index < argv.length; index += 1) {
        const argument = argv[index];
        const next = () => {
            index += 1;
            if (index >= argv.length) throw new UsageError(`${argument} needs a value`);
            return argv[index];
        };
        switch (argument) {
        case '--endpoint': options.endpoint = next(); break;
        case '--window': options.window = next(); break;
        case '--timeout': {
            const value = Number(next());
            if (!Number.isFinite(value) || value <= 0) throw new UsageError('--timeout must be a positive number');
            options.timeout = value;
            break;
        }
        case '--part': {
            const value = Number(next());
            if (!Number.isInteger(value)) throw new UsageError('--part must be an integer');
            options.part = value;
            break;
        }
        case '--content-type': options.contentType = next(); break;
        case '-h':
        case '--help': options.help = true; break;
        case '--':
            // Everything after this is a value, however it starts. Without it there is no way to
            // pass a TEXT or a JSON argument beginning with two dashes.
            positional.push(...argv.slice(index + 1));
            index = argv.length;
            break;
        default:
            if (argument.startsWith('--')) throw new UsageError(`unknown option ${argument}`);
            positional.push(argument);
        }
    }
    return { options, positional };
}

class UsageError extends Error {}

function jsonArgument(text) {
    try {
        return JSON.parse(text);
    } catch (error) {
        throw new UsageError(`not valid JSON: ${text}`);
    }
}

function printJSON(value) {
    process.stdout.write(JSON.stringify(value === undefined ? null : value) + '\n');
}

async function runCommand(command, positional, options) {
    const connection = connect({ endpoint: options.endpoint, timeout: options.timeout });
    const windowFor = () => {
        const uuid = options.window || process.env[WINDOW_ENV];
        if (!uuid) {
            throw new EndpointError(
                `no window given and ${WINDOW_ENV} is not set; pass --window UUID`);
        }
        return new Window(uuid, { connection });
    };
    const viewId = () => {
        const raw = positional[0];
        if (raw === undefined) throw new UsageError(`${command} needs a VIEWID`);
        const value = Number(raw);
        if (raw.trim() === '' || !Number.isInteger(value)) {
            throw new UsageError(`VIEWID must be an integer, not ${JSON.stringify(raw)}`);
        }
        return value;
    };
    // A missing argument is a usage error, not a request with the string "undefined" in it.
    const argument = (index, name) => {
        const raw = positional[index];
        if (raw === undefined) throw new UsageError(`${command} needs ${name}`);
        return raw;
    };

    switch (command) {
    case 'hello':
        printJSON(await connection.call('actionui.hello'));
        return EXIT_OK;
    case 'windows': {
        const reply = await connection.call('actionui.listWindows');
        const list = Array.isArray(reply) ? reply : (reply && reply.windows) || [];
        for (const uuid of list) process.stdout.write(String(uuid) + '\n');
        return EXIT_OK;
    }
    case 'elements':
        printJSON(await windowFor().getElementInfo());
        return EXIT_OK;
    case 'get-value':
        printJSON(await windowFor().getValue(viewId(), options.part));
        return EXIT_OK;
    case 'set-value':
        await windowFor().setValue(viewId(), options.part, jsonArgument(argument(1, 'a JSON value')));
        return EXIT_OK;
    case 'get-string':
        process.stdout.write(
            String(await windowFor().getString(viewId(), options.part, options.contentType)) + '\n');
        return EXIT_OK;
    case 'set-string':
        await windowFor().setString(viewId(), argument(1, 'TEXT'), options.part, options.contentType);
        return EXIT_OK;
    case 'get-rows':
        printJSON(await windowFor().getRows(viewId()));
        return EXIT_OK;
    case 'set-rows':
        await windowFor().setRows(viewId(), jsonArgument(argument(1, 'a JSON array of arrays')));
        return EXIT_OK;
    case 'get-property':
        printJSON(await windowFor().getProperty(viewId(), argument(1, 'a property NAME')));
        return EXIT_OK;
    case 'set-property':
        await windowFor().setProperty(viewId(), argument(1, 'a property NAME'), jsonArgument(argument(2, 'a JSON value')));
        return EXIT_OK;
    case 'get-state':
        printJSON(await windowFor().getState(viewId(), argument(1, 'a state KEY')));
        return EXIT_OK;
    case 'set-state':
        await windowFor().setState(viewId(), argument(1, 'a state KEY'), jsonArgument(argument(2, 'a JSON value')));
        return EXIT_OK;
    case 'call': {
        const params = positional.length > 1 ? jsonArgument(positional[1]) : null;
        if (params !== null && (typeof params !== 'object' || Array.isArray(params))) {
            throw new UsageError('params must be a JSON object with named keys');
        }
        printJSON(await connection.call(argument(0, 'a METHOD'), params));
        return EXIT_OK;
    }
    default:
        throw new UsageError(`unknown command ${command}`);
    }
}

/** The `node actionui_remote.js` entry point. Resolves to the process exit code. */
async function main(argv = process.argv.slice(2)) {
    let parsed;
    try {
        parsed = parseArguments(argv);
    } catch (error) {
        process.stderr.write(`${error.message}\n\n${usage()}\n`);
        return EXIT_USAGE;
    }
    const { options, positional } = parsed;
    if (options.help || positional.length === 0) {
        process.stdout.write(usage() + '\n');
        return options.help ? EXIT_OK : EXIT_USAGE;
    }
    const command = positional.shift();
    try {
        return await runCommand(command, positional, options);
    } catch (error) {
        if (error instanceof UsageError) {
            process.stderr.write(`${error.message}\n\n${usage()}\n`);
            return EXIT_USAGE;
        }
        if (error instanceof RemoteError) {
            process.stderr.write(`${error.message}\n`);
            return EXIT_REMOTE_ERROR;
        }
        if (error instanceof EndpointError || error instanceof ProtocolError) {
            // Both mean there is nothing usable to talk to, which is what exit code 3 says.
            process.stderr.write(`${error.message}\n`);
            return EXIT_NO_HOST;
        }
        if (error instanceof TypeError) {
            // A JSON argument that parsed but is the wrong shape: a string where rows belong.
            process.stderr.write(`${error.message}\n`);
            return EXIT_USAGE;
        }
        process.stderr.write(`${error && error.stack ? error.stack : error}\n`);
        return EXIT_REMOTE_ERROR;
    } finally {
        closeAllConnections();
    }
}

module.exports = {
    PROTOCOL_VERSION, ENDPOINT_ENV, WINDOW_ENV, TOKEN_ENV, TOKEN_FD_ENV,
    DEFAULT_TIMEOUT, MAX_LINE_LENGTH, SUN_PATH_LIMIT, MAX_TOKEN_LENGTH,
    RemoteError, EndpointError, ProtocolError,
    InsertPosition, DialogButton, ButtonRole, ModalStyle,
    Connection, Window, Batch, connect, hello, closeAllConnections, main,
    EXIT_OK, EXIT_REMOTE_ERROR, EXIT_USAGE, EXIT_NO_HOST,
    // For the tests, which drive the descriptor rules directly.
    _readTokenDescriptor: readTokenDescriptor,
    _resetTokenDescriptorForTesting() {
        _tokenFromDescriptor = null;
        _tokenDescriptorError = null;
    },
};

if (require.main === module) {
    main().then((code) => { process.exitCode = code; });
}
