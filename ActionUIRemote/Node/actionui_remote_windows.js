'use strict';
/**
 * actionui_remote_windows.js - the named-pipe side of actionui_remote on Windows.
 *
 * actionui_remote.js loads this file from its own folder on Windows. Node connects to a local named
 * pipe with net.connect, as to a Unix socket elsewhere (PROTOCOL.md section 12). Of the checks that
 * section asks of a client before it sends a token, this one makes the first only:
 *
 * - The endpoint must be a local pipe name, `\\.\pipe\` and then letters, digits, '.', '-' or '_'
 *   (not ending in '.'). Another computer's name (`\\host\pipe\...`) is refused before anything is
 *   opened: opening it would send the token, and the user's sign-in, over the network.
 *
 * Plain JavaScript cannot make the other two (README.md, "On Windows"): Node opens the pipe without
 * asking for identification only, so a server may act as this process; and it cannot read the
 * pipe's owner, so a pipe somebody else made after the host's server ended would get the token. The
 * Python client makes both checks.
 */

const PIPE_PREFIX = '\\\\.\\pipe\\';
const MAX_PIPE_NAME = 256;

/** Throws an `ErrorType` unless `name` is a local pipe name this client may send a token to. */
function checkEndpoint(name, ErrorType) {
    if (typeof name !== 'string' || name.length <= PIPE_PREFIX.length || name.length > MAX_PIPE_NAME
        || name.slice(0, PIPE_PREFIX.length).toLowerCase() !== PIPE_PREFIX) {
        throw new ErrorType(`not a local pipe name (\\\\.\\pipe\\...): ${name}`);
    }
    const rest = name.slice(PIPE_PREFIX.length);
    if (!/^[A-Za-z0-9._-]+$/.test(rest) || rest.endsWith('.')) {
        throw new ErrorType(`not a local pipe name (letters, digits, '.', '-' or '_' after \\\\.\\pipe\\, `
            + `not ending in '.'): ${name}`);
    }
}

module.exports = { PIPE_PREFIX, checkEndpoint };
