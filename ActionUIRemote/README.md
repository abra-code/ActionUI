# ActionUIRemote

Out-of-process access to ActionUI windows. A host that embeds ActionUI starts a small server
on a Unix domain socket; any process running as the same user can then read and mutate the
host's windows over newline-delimited JSON-RPC 2.0, with the same verbs and the same value
encoding as the in-process adapters. macOS only.

The wire contract is in [PROTOCOL.md](PROTOCOL.md). The Python client lives in `Python/`.

## Why

The in-process bindings (C, Python, Node, JavaScriptCore, WebKit) link the framework into the
process that owns the UI and keep state for the life of the app. Some hosts have the opposite
shape: the app owns the UI and the logic runs in short-lived child processes, as OMC applets do
with their shell and Python handlers. Those children need a read and write path to the windows
without linking anything. This target is that path, and because it speaks a small language-neutral
protocol the same server also serves test automation, agents driving a running app, and worker
subprocesses of an in-process Python app.

## Host integration

One server per process is what the environment contract assumes, so that is the API:

```swift
import ActionUIRemote

// Binds the socket, exports ACTIONUI_REMOTE_ENDPOINT so children inherit it, and returns the
// path. Omit socketPath for a per-process default in the user's temporary directory.
let endpoint = try ActionUIRemoteServer.startShared(
    host: .init(name: "MyApp", version: "1.0"),
    logger: ActionUIModel.shared.logger)            // optional

// Host-specific verbs, namespaced. Handlers run on the main actor.
ActionUIRemoteServer.shared?.register(method: "myapp.quit") { _ in
    NSApp.terminate(nil)
    return true
}

// Optional: resolve `presentModal` resource names to files.
ActionUIRemoteServer.shared?.setModalResourceResolver { name in
    Bundle.main.url(forResource: name, withExtension: "json")
}

// From the host's termination hook. The socket file outlives a process that just exits, so
// this matters: an `atexit` handler unlinks it as a backstop, but only this closes connections.
ActionUIRemoteServer.stopShared()
```

`startShared` throws `UnixSocketServerError.alreadyStarted` if one is already running, and
`ActionUIRemoteServer.sharedEndpoint` reports the path of the running one. Anything already at
the socket path is unlinked before binding, so pass a path of your own making.

A host that needs something else - two servers, a path it manages itself, no environment export -
constructs `ActionUIRemoteServer(host:)` directly and calls `start(socketPath:)` and `stop()` on
it. Nothing above is required.

### From a C or Objective-C host

`ActionUIRemoteServer` is a plain Swift class, so none of it reaches Objective-C through a
generated header. The same lifecycle is available as C entry points, declared in
`ActionUIRemote-Swift.h`:

```objc
@import ActionUIRemote;      // or #import <ActionUIRemote/ActionUIRemote-Swift.h>

if (actionUIRemoteStartServer(socketPath, "MyHost", "1.0")) {   // any argument may be NULL
    const char *endpoint = actionUIRemoteServerEndpoint();      // owned by the framework
    ...
}
actionUIRemoteStopServer();
```

`actionUIRemoteServerIsRunning()` answers whether one is up. NULL arguments mean the per-process
default path and the running process's name and version. This is what OMC calls.

Registering host methods is still Swift-only: a handler is a Swift closure, so a C host that
needs its own `omc.*` verbs supplies them through a small Swift file of its own.

Every request runs on the main actor against `ActionUIModel.shared`. A main thread that does
not respond within `mainThreadTimeout` (10 s) answers `1005` instead of hanging the client.

### From an ActionUIPython or ActionUINodeJS app

Those two hosts do not need any of the above: `ActionUIAppKitApplication` starts and stops one
server for the process, and the binding exposes it.

```python
endpoint = app.start_remote_server()     # returns the socket path, exports ACTIONUI_REMOTE_ENDPOINT
subprocess.run(["python3", "worker.py"],
               env={**os.environ, "ACTIONUI_WINDOW_UUID": window.uuid})
```

```js
const endpoint = app.startRemoteServer();
spawn('python3', ['worker.py'],
      { env: { ...process.env, ACTIONUI_WINDOW_UUID: window.uuid } });
```

Requests are answered only while the run loop is running, since every one of them hops to the
main thread. A worker started before `app.run()` should wait for its first reply rather than
assume the host is dead.

A PillowUI worker-process example belongs here and can be added later; PillowUI itself is
unchanged by this target.

## Command line

The Python client is also a tool, which is what gives a shell handler a read path: it is handed
its window's values as environment variables when it is spawned and has otherwise no way to ask
for them again.

```sh
export ACTIONUI_REMOTE_ENDPOINT=/path/to/host.sock    # the host sets these for its children
export ACTIONUI_WINDOW_UUID=...

python3 -m actionui_remote hello                      # what this host is and what it offers
python3 -m actionui_remote get-value 2                # JSON
python3 -m actionui_remote get-string 2               # the text itself, for $(...)
python3 -m actionui_remote get-rows 5                 # [["a","b"],["c","d"]]
python3 -m actionui_remote set-string 4 "Working..."
python3 -m actionui_remote call omc.terminate '{"ok":true}'
```

`--endpoint`, `--window` and `--timeout` come before the command and override the environment;
`call` reaches any method the host has, including its own namespace. `get-string` prints the
text itself, so an empty line means a null value or an empty string alike.

Exit codes are 0 for success, 1 when the host answered an error (the message carries the
protocol code), 2 for a bad command line, and 3 when there is no host to talk to, so a script
can tell "no ActionUI here" from "no such element" without reading messages. An output pipe
closed early (`| head`) is not an error.

Until a host puts the module on `PYTHONPATH` (OMC 5.3 vendors it into its framework), run these
from `ActionUIRemote/Python`, or name that directory in `PYTHONPATH`.

### From the shell, without Python

`Shell/actionui_remote.sh` is the same command line, and a library of the same surface, for a
handler written in `/bin/sh` or zsh, with no Python involved; `Shell/actionui_remote.zsh` is the
zsh variant with a persistent connection and no helper process. They exist for a security reason
rather than convenience: a `python3` or `node` process shows its environment, and so the token,
to any same-user `ps`, and a shell does not. `Shell/README.md` has the measurements and the three
rules that keep that true.

```sh
. /path/to/actionui_remote.sh                       # library
actionui_hold_token                                 # take the token out of the environment
name=$(actionui_get_string 2)
/path/to/actionui_remote.sh get-rows 5              # command: same commands and exit codes
```

## Security model

- The socket file is created 0600; put it in a directory only the user can enter (the engine's
  per-user temp directory in OMC's case).
- Every connection's peer uid is checked against the server's uid.
- Descriptors are close-on-exec, so children spawned by the host never inherit the listener.
- Optionally, a token. `startShared` mints one, requires it, and exports it as
  `ACTIONUI_REMOTE_TOKEN`; the client reads it from the environment and sends it without being
  asked, so a caller writes no code for it. `startShared(requireToken: false)` opts out, and the
  instance API requires none unless asked. See PROTOCOL.md section 10.
- A host that spawns children can keep the token out of their environment entirely: hand each
  child its own on an inherited pipe and name the descriptor with `ACTIONUI_REMOTE_TOKEN_FD`,
  then call `actionUIRemoteUnexportToken()` so nothing inherits `ACTIONUI_REMOTE_TOKEN` at all.
  Both the Python and the shell clients read the descriptor with no code from the caller. This is
  the only thing that removes the `ps` exposure described below; OMC does it for every handler.

Without a token the boundary is the socket's permissions and the peer-uid check - the same one a
same-user CFMessagePort has, where any process of the same user can drive the UI as it already
could through the in-process tools.

With one, a process the host did not spawn does not have the token and cannot get it by listing
the socket directory. That is worth having because **this bridge can read**, where the older tools
could only write: a window may be showing something a stray script has no business seeing.

**It does not stop a determined same-uid attacker, and the reason is measured rather than
assumed.** `ps eww` reveals the environment of a `python3` or `node` process to any process of the
same user. The kernel hides it only for processes carrying the `CS_RESTRICT` code-signing flag
(Apple platform/SIP binaries, or setuid), which those interpreters do not; `/usr/bin/python3` is
an Apple platform binary and still exposes its environment because it lacks the flag. So while a
handler holding the token is alive, the token is readable. The host's own environment is not
exposed that way, so the exposure is through the children and only while one runs.

A handler that must not show the token to `ps` gets it on a descriptor rather than in its
environment, so that its exec-time snapshot never contains it - which is the only thing that
helps, `ps` reading a snapshot frozen at exec. A host does that with `ACTIONUI_REMOTE_TOKEN_FD`
plus `actionUIRemoteUnexportToken()`, and a shell handler does it for its own children with
`actionui_handoff`. Failing that, a handler can be written against the shell clients in `Shell/`
instead: every Apple shell and every Apple tool they run carries `CS_RESTRICT`, so the token
stays inside processes that hide it. `Shell/README.md` says exactly what that does and does not
guarantee.

Treat it as raising the cost of casual and accidental access, not as a boundary. Same-uid has
never been one on macOS. A handler that logs its environment gives the token away, and the CLI's
`--token` puts it in argv where anything can read it. Anything that records requests must redact
it - the bundled fake host does.

## Layout

- `JSONRPC.swift`: envelope codec and `ActionUIRemoteError`.
- `UnixSocketServer.swift`: socket, framing, per-connection queues.
- `ActionUIRemoteServer.swift`: public API, method registry, main-thread hop.
- `ActionUIRemoteSharedServer.swift`: the process-wide server, its default path, and the
  environment export - what a host calls instead of writing its own singleton.
- `ActionUIRemoteMethods.swift`: the `actionui.*` table over the engine.
- `Python/`: the stdlib-only Python client (importable, and runnable with `-m`) and a fake
- `Shell/` - `actionui_remote.sh` and `actionui_remote.zsh`, the shell clients, their tests and README.
  server for host test suites.
- Tests in `ActionUIRemoteTests/`.
