# actionui_remote for Node

A Node.js client for the ActionUI Remote Protocol, version 1. The wire contract is
[`../PROTOCOL.md`](../PROTOCOL.md); this is the Node counterpart of
[`../Python/actionui_remote.py`](../Python/actionui_remote.py). Its tests run against the same
reference fake host the Python client's suite uses, and additionally assert the exact method name
and parameters of every call against a recording server - a round trip through a lenient host is
not evidence that the right thing went over the wire.

No dependencies, no build step, nothing to install: one file that `require`s.

## Using it

```js
const aui = require('/path/to/actionui_remote.js');

const win = aui.Window.fromEnvironment();      // the window this process was started for
await win.setString(4, 'Working...');
const rows = await win.getRows(5);
await win.setValue(2, 0, rows.length);
```

A handler writes nothing about endpoints or tokens. The host that spawned it exported
`ACTIONUI_REMOTE_ENDPOINT` and `ACTIONUI_WINDOW_UUID`, and handed over a token in one of the two
ways section 10 of the protocol describes; the client finds all of it.

Everything that talks to the host returns a Promise. Node has no synchronous socket read, so
there is no blocking form of this API and there cannot be one - that is the one place this client
cannot mirror the Python one, whose calls are ordinary blocking calls.

CommonJS on purpose. A handler is usually a bare `.js` file run as `node worker.js` with no
`package.json` anywhere near it, and `require` is what works in that setting.

### Several calls in one round trip

```js
const batch = win.batch();
batch.setString(4, 'one');
batch.setString(5, 'two');
batch.clearRows(7);
await batch.send();
```

Every `Window` method is available on a `Batch` and returns the batch, so calls chain. `send()`
resolves to the results in order; by default the first host error among them is thrown, carrying
all of the results on `.results`.

### Talking to a specific window, or a specific host

```js
const connection = aui.connect({ endpoint: '/tmp/my.sock', timeout: 30 });
const win = new aui.Window(uuid, { connection });
```

`connect()` caches one connection per endpoint for the whole process. `new aui.Connection(...)`
makes an unshared one.

## The command line

```
node actionui_remote.js hello
node actionui_remote.js --window "$ACTIONUI_WINDOW_UUID" get-string 4
node actionui_remote.js --window "$ACTIONUI_WINDOW_UUID" set-rows 5 '[["a","b"],["c","d"]]'
node actionui_remote.js call omc.getContext '{"key":"selection"}'
node actionui_remote.js --help
```

Exit codes: `0` ok, `1` the host answered an error (the message carries the protocol code), `2`
usage, `3` nothing to talk to.

## The token

Read automatically, from whichever of the two forms the host used, in this order: a token passed
explicitly to `Connection`, then `ACTIONUI_REMOTE_TOKEN_FD`, then `ACTIONUI_REMOTE_TOKEN`.

**The descriptor is drained when this module loads**, not on the first request. Until it is read,
the process holds an open descriptor to a live token and exports the variable naming it, so
everything it spawns inherits both - and a handler that runs a subprocess before its first bridge
call would hand that child its token, or have the token read out from under it. Once read, the
descriptor is closed and the variable removed, which is the reader's half of the two-owner
lifecycle in section 10. **A child that needs the bridge must be handed its own token**: a pipe
is drained by its first reader, and there is nothing left in it.

A descriptor that is configured but cannot be read is an `EndpointError`, never a quiet fall back
to the environment. Falling back would undo the whole point of the descriptor, which is that the
token is not in the environment at all.

### Why the descriptor is read through `head -n 1`

The one deliberate deviation from the Python client, and the reason is worth keeping.

The wait has to be bounded. A stale `ACTIONUI_REMOTE_TOKEN_FD` inherited from a grandparent names
whatever this process happens to have at that number - a tty, an unclosed socket - and a
synchronous read of something that never delivers would hang the handler at load time, before it
has run a line of its own. Python bounds this with `select.poll`. Node has no synchronous poll,
no `fcntl` to set `O_NONBLOCK`, and no timeout on `fs.readSync`. `execFileSync` does have a
timeout, and passing the descriptor as the child's stdin reads the pipe under it.

`head -n 1` rather than `cat`, because Python stops at the first newline and not at EOF. A
creator that writes the token and a newline but holds its write end open is out of contract, but
it gets an answer instead of a ten-second timeout - and the two clients agreeing matters more here
than either behavior does on its own.

The token reaches this process through the child's stdout pipe. It is never in its argv or
environment, so nothing is exposed that was not already.

## What the token is worth

Measured, in section 10 of the protocol, and worth reading before relying on it. A process's
environment is readable by any process of the same user unless it carries the `CS_RESTRICT`
code-signing flag, which `node` and `python3` do not and cannot be given. So while a handler
holding `ACTIONUI_REMOTE_TOKEN` is alive, one `ps` invocation reads it.

The token raises the cost of casual and accidental access. It is not a security boundary, and
nothing should be designed as though it were. A host that needs the token off `ps` entirely must
use the descriptor form, which is why this client reads it.

Two consequences: a handler that logs its own environment gives the token away, and
`node actionui_remote.js --token ...` would put it in argv, which every process can read - which
is why there is no such option.

## Tests

```sh
node test_actionui_remote.js
```

73 checks. Stands up `../Python/actionui_remote_testing.py` and drives the client against it;
asserts the exact wire shape of every call against a recording server; drives the descriptor
rules in child processes, since the descriptor is read once per process and each rule needs a
fresh one; and runs a real handler script end to end to prove it exits when its work is done.
Unix-socket binding needs the tool sandbox disabled in this harness.
