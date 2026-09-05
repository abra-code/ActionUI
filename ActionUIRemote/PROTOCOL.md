# ActionUI Remote Protocol, version 1

The wire contract between an ActionUI host (any process that embeds ActionUI and starts
`ActionUIRemoteServer`) and an out-of-process client (a Python script, a tool, a test harness).
This document is normative; the Swift server and every language client are written against it.
Where the code and this document disagree, the document is wrong until it is corrected, and the
change is a protocol change.

## 1. Transport

- A Unix domain stream socket. The host creates it at a path of its choosing, mode 0600, in a
  directory private to the user. The path is handed to clients through the environment
  (section 9).
- The host accepts connections only from processes running as its own uid (`getpeereid`); any
  other peer is closed immediately. Nothing else authenticates: the socket's permissions and
  its directory are the security boundary, the same boundary a same-user CFMessagePort has.
- The socket path is limited by `sun_path` to 103 bytes on macOS.
- The server holds no per-client state. A client may open one connection per process and keep
  it, or open one per request; both are equally correct. Every request names its window.
- A client must keep its write side open until it has read the reply. The host closes a
  connection when it reads EOF, even with a reply still pending on its main thread, so a client
  that half-closes as soon as it has sent - as `nc` does the moment its stdin ends - can lose its
  own answer.

## 2. Framing

- One JSON value per line, terminated by `\n` (a trailing `\r` before it is ignored). UTF-8.
- A line never contains a raw newline; JSON escapes them.
- Maximum line length is 64 MiB in either direction: the host closes a connection that sends a
  longer line, and a client should do the same with a longer reply (the host does not truncate
  a large result, so a client asking for it must be prepared to drop the connection).
- An empty line is a parse error (`-32700`, null id), not a no-op.
- Requests on one connection are answered in the order they were sent. Independent connections
  interleave at request granularity on the host's main thread.

## 3. Envelope (JSON-RPC 2.0)

Request:

```json
{"jsonrpc":"2.0","id":7,"method":"actionui.getValue","params":{"window":"...","viewID":2}}
```

Success reply:

```json
{"jsonrpc":"2.0","id":7,"result":"Ada"}
```

Error reply:

```json
{"jsonrpc":"2.0","id":7,"error":{"code":1002,"message":"Unknown view 2 in window ...","data":null}}
```

Rules:

- `jsonrpc` must be the string `"2.0"`.
- `id` is a number or a string and is returned verbatim. A request without `id`, or with
  `"id": null`, is a **notification**: it is executed and never answered (this protocol treats
  a null id as absent; do not send null ids).
- `params` is always an object with named keys. A missing or null `params` is an empty object.
  Positional params (an array) are rejected with `-32602`.
- A JSON array is a **batch**. Its members run inside one main-thread turn, in order, so a
  later member sees an earlier member's write and the whole batch applies within one frame. The
  reply is an array in the same order, omitting notifications; a batch of only notifications
  gets no reply at all. An empty array is `-32600`. A batch of more than 4096 members is
  `-32600` before any of it runs.
- Invalid members of a batch get an individual error reply in place (with the member's id when
  one could be read, null otherwise); the other members still run.
- An invalid request (`-32600`) is always answered, with the id when it could be read and null
  otherwise, even if it looked like a notification. Any other rejection of a notification
  (unknown method, bad params, engine failure) is logged by the host and not answered.
- `error.data` is present only when the error carries extra JSON-ready information.
- The server never sends anything unsolicited in version 1. A client must ignore any line that
  is not a reply to one of its requests, so that future versions can add server-initiated
  notifications.

## 4. Error codes

| Code | Meaning |
|---|---|
| -32700 | Parse error: the line is not JSON. Reply carries a null id. |
| -32600 | Invalid request: not an object or array, empty or oversized batch, wrong `jsonrpc`, bad `method`, bad `id` type. |
| -32601 | Method not found. |
| -32602 | Invalid params: positional params, a missing or mistyped param (the message names it). |
| -32603 | Internal error: the host could not produce a well-formed result. |
| 1001 | Unknown window: no window with that UUID is loaded. |
| 1002 | Unknown view: the window has no element with that id. |
| 1003 | Engine failure: the engine refused the operation (insert into a non-container, state type mismatch, unreadable modal resource). The message is the engine's. |
| 1004 | Host refused: a host-registered method threw an error that is not an `ActionUIRemoteError`. The message is the error's description. |
| 1005 | Main thread unavailable: the host's main thread did not respond within its timeout (10 s by default). The request was not applied unless it was already running. |
| 1006 | Unauthenticated: the host requires a token and this connection has not presented a valid one. See section 10. |

Positive application codes are deliberate: they read better in logs than the customary
`-32000...-32099` range and cannot collide with anything reserved.

## 5. Value encoding

Element values, property values, and state values cross the wire as JSON values with exactly
the encoding of the in-process C adapter (`actionUIGetElementValueJSON` and
`actionUISetElementValueJSON`), which every adapter shares through `ActionUIJSON`:

- Strings, numbers, booleans, `[String]`, `[[String]]`, and JSON objects as themselves.
- A value that has no JSON form (a DatePicker's Date, a ColorPicker's Color, a Map's
  coordinate) is returned as `null` by `actionui.getValue`, `getProperty` and `getState`.
  `actionui.getValueString` and `setValueString` are the supported path for those types
  (ISO 8601 for dates, JSON for coordinates).
- `setState` converts a JSON scalar toward the type of the state already stored (a stored
  Double accepts a whole number, a stored Bool accepts a bool), and stores a new key as the
  Swift-native type (Bool, Int, Double, String). A value that still does not match the stored
  type is `1003`.

## 6. Common parameters

- `window` (string): the window UUID. Required by every element and presentation method.
- `viewID` (integer): the element id. Positive ids are the ones assigned in the JSON; negative
  ids are auto-assigned and are addressable when a client has learned them (an action's
  trigger context).
- `viewPartID` (integer, default 0): a sub-part, notably a 1-based Table column for
  `getValue`/`getValueString` (0 means the whole selected row).
- Integers must be JSON numbers with no fractional part; a boolean where a number is expected
  is `-32602`.
- `position` (object, default append) for insertions: `{"kind":"append"}`,
  `{"kind":"prepend"}`, `{"kind":"at","index":n}`, `{"kind":"before","siblingID":n}`,
  `{"kind":"after","siblingID":n}`. The strings `"append"` and `"prepend"` are accepted as
  shorthand.
- Dialog buttons: an array of `{"title":"...","role":"cancel"|"destructive","actionID":"..."}`;
  `role` and `actionID` are optional.

## 7. Methods, `actionui.*`

Setters return `true` so that a batch reply is easy to scan.

| Method | Params | Result |
|---|---|---|
| `actionui.hello` | none | `{"protocolVersion":1,"host":{"name","version"},"methods":[...sorted],"windows":[...sorted]}` |
| `actionui.listWindows` | none | `[uuid...]`, sorted |
| `actionui.getElementInfo` | window | `{"<id>":"<Type>",...}` for positive ids |
| `actionui.getValue` | window, viewID, viewPartID? | value or null |
| `actionui.setValue` | window, viewID, viewPartID?, value | `true` |
| `actionui.getValueString` | window, viewID, viewPartID?, contentType? | string or null |
| `actionui.setValueString` | window, viewID, viewPartID?, value (string), contentType? | `true` |
| `actionui.getProperty` | window, viewID, name | value or null |
| `actionui.setProperty` | window, viewID, name, value | `true` |
| `actionui.getState` | window, viewID, key | value or null |
| `actionui.getStateString` | window, viewID, key | string or null |
| `actionui.setState` | window, viewID, key, value | `true`; `1003` on type mismatch |
| `actionui.setStateString` | window, viewID, key, value (string) | `true` |
| `actionui.getColumnCount` | window, viewID | integer (0 for non-tables) |
| `actionui.getRows` | window, viewID | `[[string]]` or null |
| `actionui.setRows` | window, viewID, rows `[[string]]` | `true` |
| `actionui.appendRows` | window, viewID, rows | `true` |
| `actionui.clearRows` | window, viewID | `true` |
| `actionui.selectRow` | window, viewID, index (0-based) | the selected row `[string]`; null when out of range (selection cleared) or when the element is not a Table or List (selection untouched) |
| `actionui.selectRowWithContent` | window, viewID, text, column? (0-based; omit for any column) | the matched row index, or -1 |
| `actionui.clearSelection` | window, viewID | `true` |
| `actionui.insertElement` | window, parentID, element (object), container?, position? | the new element's id |
| `actionui.insertRow` | window, parentID, cells (array of objects), container?, position? | the new cells' ids `[int]` |
| `actionui.removeElement` | window, viewID | `true`; the root cannot be removed (`1003`) |
| `actionui.presentModal` | window, one of element (object) / json (string) / path (string), format? (`json`/`plist`), style? (`sheet`/`fullScreenCover`), onDismissActionID? | `true` |
| `actionui.dismissModal` | window | `true` |
| `actionui.presentAlert` | window, title, message?, buttons? | `true` (default: one OK button) |
| `actionui.presentConfirmationDialog` | window, title, message?, buttons (non-empty) | `true` |
| `actionui.dismissDialog` | window | `true` |
| `actionui.presentToast` | window, message, duration? (seconds, default 4), actionTitle?, actionID? | `true` |
| `actionui.dismissToast` | window | `true` |
| `actionui.contentSizeLimits` | window | `{"minWidth","minHeight","maxWidth","maxHeight"}` or null |

Notes:

- `presentModal` with `path`: the host may register a resolver that maps a resource name or a
  relative path to a file (OMC resolves `"MyModal"` to `MyModal.json` in the applet the way
  `omc_present_modal` does). Without a resolver only absolute paths are accepted. `format`
  defaults to `plist` for a `.plist` extension and `json` otherwise; an explicit `format` wins.
- Selection methods are programmatic and fire no action.
- Unknown window and unknown view are checked before every element call, so `1001`/`1002` are
  reported even for methods the engine would otherwise treat as a silent no-op.

## 8. Host extension methods

A host registers additional methods under its own namespace (`omc.*`, `app.*`); the `actionui.`
prefix is reserved. They appear in `actionui.hello`'s `methods` list, take named params like
everything else, and map errors as described for `1004`. A client discovers what a host offers
from `hello` and must not assume any namespace beyond `actionui.` exists.

## 9. Environment contract

A host that spawns child processes expected to use the bridge sets:

- `ACTIONUI_REMOTE_ENDPOINT`: the absolute socket path.
- `ACTIONUI_WINDOW_UUID`: the window the child is about, when there is one.
- `ACTIONUI_REMOTE_TOKEN`: the token, when the host requires one. See section 10.

Hosts may export additional aliases under their own names (OMC also exports
`OMC_ACTIONUI_REMOTE_ENDPOINT` and `OMC_ACTIONUI_WINDOW_UUID`). Clients read the two generic
names by default.

## 10. Authentication

Optional, and off unless the host turns it on. When it is on, every request must carry a valid
token or is refused with `1006`.

- The token is a string in the request's `params` under the key `token`. That key is
  reserved on every method: the host removes it before dispatch even when it requires none, so a
  host extension must not define a parameter of its own by that name. It is stripped before
  the method runs, so no handler - including a host extension - ever sees it.
- A connection that presents a valid token once is remembered, so a long-lived client pays
  nothing per request afterwards.
- A client may instead send it on **every** request. That is not redundant: section 1 allows one
  connection per request, and that pattern would otherwise need an extra round trip to
  authenticate each one. The reference client always sends it, which makes reconnects
  transparent too.
- A host may have many tokens live at once and withdraw them independently - one per unit of
  work it spawns, revoked when that work ends. Revoking stops new connections; it does not tear
  down authenticated ones.

Clients should read `ACTIONUI_REMOTE_TOKEN` from the environment and send it without being asked,
so that a host turning the requirement on breaks nothing. A client may also accept the token from
an inherited descriptor named by `ACTIONUI_REMOTE_TOKEN_FD`; the shell clients do. That is how a
host or a parent process delivers a token that is never in the child's environment at all (see
the end of this section). The lifecycle has two owners: the process that creates the pipe writes
the token and closes its write end; the client reads it once, closes the descriptor and removes
the variable, so that nothing it spawns inherits either, and as early as it can - the Python
client does it when the module is imported, rather than on the first request, because until then
everything the process spawns inherits both. The Python and shell clients both implement this;
precedence in all of them is an explicitly given token, then the descriptor, then the
environment. A descriptor that is configured but cannot be read is a failure, never a fallback to
the environment: falling back would silently undo the point of the descriptor.

**What this is for, and what it is not.** A host that spawns children hands them the token in
the environment, so a process the host did not spawn does not have it and cannot obtain it merely
by listing the socket directory - which it otherwise could, the path being no secret.

**How much that is worth, measured rather than assumed.** Whether one process can read another's
environment on macOS depends on the target's code-signing flags, not on whether it is an Apple
binary. The kernel withholds the environment from a same-uid, non-root caller only when the target
carries `CS_RESTRICT` (Apple platform/SIP binaries, or setuid processes); the interpreters this
bridge's clients run under do not carry it. `/usr/bin/python3` is itself an Apple platform binary
and still exposes its environment, because it lacks the flag:

| target process | code-signing | `ps eww` reveals its environment |
|---|---|---|
| `/bin/sleep`, `/bin/sh` | platform + `CS_RESTRICT` | no |
| `/usr/bin/python3` | platform, no `CS_RESTRICT` | **yes** |
| python.org python3, `node` | hardened runtime, no `CS_RESTRICT` | **yes** |

So while a handler holding the token is alive, any same-uid process can read the token out of it
with one `ps` invocation. The host's own environment is not exposed this way - a `setenv` after
exec does not appear in the process-arguments block - so the token is only readable through the
children, and only while one is running.

**Therefore: this raises the cost of casual and accidental access, and does not stop a deliberate
same-uid attacker.** It is worth having because it is nearly free and because it stops a stray
script that simply connects to a socket it found; it is not a boundary, and nothing should be
designed as though it were. Same-uid has never been a security boundary on macOS, and a host with
something genuinely sensitive on screen should not rely on this.

Two consequences worth stating: a handler that logs its own environment gives the token away, and
`python3 -m actionui_remote --token` puts it in argv, which every process can read. Hosts and test
harnesses must not record it; the reference fake host redacts it from its request log.

A host that needs the token kept off `ps` entirely cannot get there by hardening the interpreter -
`CS_RESTRICT` is reserved to Apple platform/SIP and setuid binaries and cannot be conferred on a
third-party `python3` or `node`. The only route is to keep the secret out of the process's
environment: deliver it by an inherited file descriptor, or write it to a 0600 file and export only
the path. Clearing the variable in-process does not help, because `ps` reads a snapshot frozen at
exec time.

## 11. Versioning

`protocolVersion` is an integer reported by `actionui.hello`. Adding methods, adding optional
params, or adding fields to a result object does not bump it. Changing an existing result's
shape, removing a method, or changing an error code does. A client may skip `hello` entirely
and rely on `-32601` for methods a host lacks.

Reserved for a later version: server-initiated notifications (`actionui.event`) and a
subscription method, for long-running clients that want actions pushed to them.
