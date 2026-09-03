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

```swift
import ActionUIRemote

let server = ActionUIRemoteServer(host: .init(name: "MyApp", version: "1.0"))
server.logger = ActionUIModel.shared.logger          // optional
try server.start(socketPath: socketPath)            // a 0600 file in a user-private directory
setenv("ACTIONUI_REMOTE_ENDPOINT", socketPath, 1)   // children inherit it

// Host-specific verbs, namespaced. Handlers run on the main actor.
server.register(method: "myapp.quit") { _ in
    NSApp.terminate(nil)
    return true
}

// Optional: resolve `presentModal` resource names to files.
server.setModalResourceResolver { name in Bundle.main.url(forResource: name, withExtension: "json") }

// On the way out:
server.stop()
```

Every request runs on the main actor against `ActionUIModel.shared`. A main thread that does
not respond within `mainThreadTimeout` (10 s) answers `1005` instead of hanging the client.

## Security model

- The socket file is created 0600; put it in a directory only the user can enter (the engine's
  per-user temp directory in OMC's case).
- Every connection's peer uid is checked against the server's uid.
- Descriptors are close-on-exec, so children spawned by the host never inherit the listener.
- Nothing else authenticates. This is the same boundary a same-user CFMessagePort has: any
  process of the same user can drive the UI, as it already could through the in-process tools.

## Layout

- `JSONRPC.swift`: envelope codec and `ActionUIRemoteError`.
- `UnixSocketServer.swift`: socket, framing, per-connection queues.
- `ActionUIRemoteServer.swift`: public API, method registry, main-thread hop.
- `ActionUIRemoteMethods.swift`: the `actionui.*` table over the engine.
- `Python/`: the stdlib-only Python client and a fake server for host test suites.
- Tests in `ActionUIRemoteTests/`.
