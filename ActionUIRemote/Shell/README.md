# ActionUI Remote, from the shell

`actionui_remote.sh` and `actionui_remote.zsh` are shell clients for the ActionUI remote bridge:
the same protocol, commands and exit codes as `python3 -m actionui_remote`, for a handler written
in `/bin/sh` or zsh. They exist for one reason, measured rather than assumed, and it is worth
understanding before choosing them over the Python client.

## Why a shell client

On macOS, whether another process of the same user can read a process's environment with `ps`
depends on one thing: the `CS_RESTRICT` code-signing flag. The kernel withholds the environment
from `KERN_PROCARGS2` (what `ps eww` and `ps -E` read) only for processes that carry it. Every
Apple-provided shell carries it, and so does every Apple tool these files spawn. A `python3` or
`node` process does not, whoever built it, and cannot be made to: the flag is reserved to Apple
platform binaries and setuid processes.

Measured on macOS 26, from a separate same-user process, with a marker in the target's environment:

| process | `CS_RESTRICT` | environment visible to `ps` |
|---|---|---|
| `/bin/sh`, `/bin/bash`, `/bin/zsh`, `/bin/ksh`, `/bin/dash`, `/bin/csh`, `/bin/tcsh` | yes | no |
| `/usr/bin/nc`, `awk`, `sed`, `grep`, `plutil`, `perl`, `ruby`, `osascript` and the rest of `/usr/bin` | yes | no |
| `/usr/bin/python3` (Apple's, backed by the Command Line Tools) | no | **yes** |
| python.org `python3`, `node` (hardened runtime, no `CS_RESTRICT`) | no | **yes** |
| a self-built binary, with or without the `__RESTRICT` segment, hardened runtime or an entitlement | no | **yes** |

So a handler that holds `ACTIONUI_REMOTE_TOKEN` in a Python or Node process shows it to any
`ps` invocation for as long as it runs. A handler that holds it in a shell does not - provided
the token never leaves the processes that hide it. That is the whole design of these files, and
it rests on three rules:

1. **Never in argv.** A process's arguments are visible to every other process, restricted or
   not. The token goes to `nc` on a pipe, `printf` and `echo` are shell builtins here, and the
   command line refuses `--token`.
2. **Never in the environment of a process that does not hide it.** Every helper these files run
   is an Apple binary with `CS_RESTRICT`. When a script has to spawn something else - a python3
   helper, a build tool - `actionui_hold_token` takes the token out of the environment first, and
   `actionui_handoff` delivers it to a child on a pipe instead.
3. **Never on disk in the clear, never logged.** The reference fake host redacts it; a handler
   that prints its environment gives it away, and so does one that runs with `set -x`, which
   traces the request line - token included - to stderr.

The guarantee is bounded, and the bound matters: this stops a same-user process from reading the
token with `ps`. It does not stop root, a debugger, or a same-user process willing to edit the
handler's own script. Same-uid has never been a security boundary on macOS. What these files
remove is the easiest route, the one a Python or Node handler leaves open.

## Which file

- **`actionui_remote.sh`** runs under `/bin/sh` (bash 3.2 in POSIX mode, as macOS ships it) and
  under zsh. Its transport is `/usr/bin/nc -U`, one connection per request, with the request and
  reply carried over a pair of FIFOs. Nothing to install.
- **`actionui_remote.zsh`** is the same API with zsh's own socket module as the transport
  (`zsh/net/socket`, shipped with `/bin/zsh`). No helper process at all, and one connection kept
  open for the whole script, the way the Python client does. Faster, and simpler underneath.
  It sources the `.sh`, so the two never drift.

Prefer the `.zsh` when the handler is zsh anyway. Use the `.sh` when it has to be `/bin/sh`.

## Use

As a library, sourced:

```sh
#!/bin/sh
. "$OMC_APPLET_RESOURCES/actionui_remote.sh"       # or wherever it is installed
actionui_hold_token                                 # first thing, in a sensitive handler

actionui_set_string 4 "Working..."                  # window from $ACTIONUI_WINDOW_UUID
name=$(actionui_get_string 2) || exit $?            # the text itself
rows=$(actionui_get_rows 5)                         # JSON, one line
actionui_batch_begin
actionui_set_rows 5 '[["a","1"],["b","2"]]'
actionui_set_enabled 7 false
actionui_batch_send >/dev/null                      # one main-thread turn on the host
```

As a command, with the same commands and exit codes as the Python CLI:

```sh
actionui_remote.sh hello
actionui_remote.sh --window UUID get-value 5
actionui_remote.sh get-rows 5                       # window from $ACTIONUI_WINDOW_UUID
actionui_remote.sh set-string 2 -- -starts-with-dash
actionui_remote.sh call omc.terminate '{"ok":true}'
```

Exit status: 0 on success; 1 when the host answered an error (`[code] message` on stderr); 2 for
a usage error; 3 when there is no host to talk to. An argument that starts with a dash and is
not a number needs `--` before it.

## Configuration

Read when a call is made, not when the file is sourced, so a script may set them at any point:

| variable | meaning |
|---|---|
| `ACTIONUI_REMOTE_ENDPOINT` | socket path, required; checked against the 103-byte `sun_path` limit by character count, so a non-ASCII path can pass the check and still fail to connect |
| `ACTIONUI_WINDOW_UUID` | default window for the element functions; `actionui_use_window UUID` overrides it |
| `ACTIONUI_REMOTE_WINDOW` | what `actionui_use_window` and the command line's `--window` set; outranks `ACTIONUI_WINDOW_UUID` when non-empty |
| `ACTIONUI_REMOTE_TOKEN` | the token, when the host requires one |
| `ACTIONUI_REMOTE_TOKEN_FD` | read the token from this inherited descriptor instead; read once, then closed, and the variable removed |
| `ACTIONUI_REMOTE_TIMEOUT` | seconds to wait for a reply, default 15; the `nc` transport truncates a fraction to whole seconds, never below one; zsh honors it |

Token precedence: a token already held, then the descriptor, then the environment. A descriptor
that is configured but cannot be read is a failure (exit 3; a non-numeric descriptor value is a
usage error, exit 2), not a fallback to the environment.
The descriptor is how a host or a parent delivers a token that is never in the child's
environment at all; see below.

## The token, and where it goes

`actionui_hold_token` copies the token into the shell and removes `ACTIONUI_REMOTE_TOKEN` (and
`ACTIONUI_REMOTE_TOKEN_FD`) from the environment. After it, nothing the script spawns inherits
the token, and the library keeps working from the held copy. Call it first thing in a handler
that has anything sensitive on screen. It fails closed: if the configured source cannot be read,
the variables are still removed, the library holds no token, and the status is 3.

`actionui_handoff COMMAND [ARGS...]` runs a command with the token delivered on descriptor 3 and
removed from the command's environment. The child is told which descriptor with
`ACTIONUI_REMOTE_TOKEN_FD=3` (the number is no secret). The command's own stdin is preserved,
and its exit status is returned.

**Who closes what.** The descriptor has two ends and two owners. Whoever creates the pipe - a
host spawning a handler, or `actionui_handoff` - writes the token and closes the write end at
once. The reader reads once, closes the descriptor, and removes `ACTIONUI_REMOTE_TOKEN_FD`, so
nothing it spawns inherits an open descriptor to a drained pipe or a variable naming one. This
library does that on first use, and so does `actionui_remote.py`; a Node client should do the
same. A child that needs the token is therefore given its own pipe, with `actionui_handoff`. A
Python child that uses `actionui_remote.py` writes nothing about tokens at all:

```python
import os, actionui_remote as aui
win = aui.Window(os.environ["ACTIONUI_WINDOW_UUID"])   # reads the descriptor, closes it, unsets it
```

This is the secure handoff from a shell handler to a Python one: the token is never in Python's
argv or environment, so `ps` shows nothing, and the pipe is readable by nobody else. Measured:

| handoff from `/bin/sh` to `python3` | python's environment as `ps` sees it |
|---|---|
| inherit the environment | token **visible** |
| `unset`, then pass in argv | token **visible** |
| `unset`, then deliver on stdin or a descriptor (`actionui_handoff`) | hidden |

Two things that do **not** work, both verified: clearing the variable inside the process after
it started (`ps` reads a snapshot frozen at exec), and making the interpreter restricted (the
flag cannot be conferred on third-party code).

## Functions

Every element function addresses the window from `ACTIONUI_WINDOW_UUID` or `actionui_use_window`.
Getters print their result as one line of JSON exactly as the host sent it; the string getters
print the text itself; setters print nothing. Arguments are shell-shaped: getters take `VIEWID`
then an optional `PART`; setters take `VIEWID`, the value, then an optional `PART`. Values the
protocol types as JSON are passed as JSON text; values typed as strings are passed as plain text
and escaped here. After every call `ACTIONUI_RESULT` holds the raw result, and on an error
`ACTIONUI_ERROR_CODE` and `ACTIONUI_ERROR_MESSAGE` are set.

Host: `actionui_hello`, `actionui_windows`, `actionui_call METHOD [PARAMS_JSON]` (fills in
`window` when one is configured and the params name none; host methods such as `omc.*` go here).

Discovery: `actionui_elements` (alias `actionui_get_element_info`), `actionui_content_size_limits`.

Values: `actionui_get_value VIEWID [PART]`, `actionui_set_value VIEWID JSON [PART]`,
`actionui_get_string VIEWID [PART] [CONTENT_TYPE]`, `actionui_set_string VIEWID TEXT [PART] [CONTENT_TYPE]`,
`actionui_get_int`, `actionui_set_int VIEWID N [PART]`, `actionui_get_double`,
`actionui_set_double VIEWID NUMBER [PART]`, `actionui_get_bool`, `actionui_set_bool VIEWID true|false [PART]`.

Properties and state: `actionui_get_property VIEWID NAME`, `actionui_set_property VIEWID NAME JSON`,
`actionui_set_enabled VIEWID true|false`, `actionui_set_hidden VIEWID true|false`,
`actionui_get_state VIEWID KEY`, `actionui_get_state_string VIEWID KEY`,
`actionui_set_state VIEWID KEY JSON`, `actionui_set_state_string VIEWID KEY TEXT`.

Rows and selection: `actionui_get_column_count VIEWID`, `actionui_get_rows VIEWID`,
`actionui_set_rows VIEWID JSON`, `actionui_append_rows VIEWID JSON`, `actionui_clear_rows VIEWID`,
`actionui_select_row VIEWID INDEX` (prints the row, or null), `actionui_select_row_with_content VIEWID TEXT [COLUMN]`
(prints the index, or -1), `actionui_clear_selection VIEWID`.

Structure: `actionui_insert_element PARENTID ELEMENT_JSON [CONTAINER] [POSITION]` (prints the new
id), `actionui_insert_row PARENTID CELLS_JSON [CONTAINER] [POSITION]` (prints the ids),
`actionui_remove_element VIEWID`. `POSITION` is `append`, `prepend`, or a JSON object such as
`{"kind":"at","index":2}`.

Presentation: `actionui_present_modal_element ELEMENT_JSON [FORMAT] [STYLE] [ON_DISMISS_ACTION_ID]`,
`actionui_present_modal_json TEXT [...]`, `actionui_present_modal_path PATH [...]`, `actionui_dismiss_modal`,
`actionui_present_alert TITLE [MESSAGE] [BUTTONS_JSON]`, `actionui_present_confirmation_dialog TITLE MESSAGE BUTTONS_JSON`,
`actionui_dismiss_dialog`, `actionui_present_toast MESSAGE [DURATION] [ACTION_TITLE] [ACTION_ID]`,
`actionui_dismiss_toast`.

Batch: between `actionui_batch_begin` and `actionui_batch_send`, every call is recorded instead
of sent, and the batch runs on the host inside one main-thread turn, in order. `actionui_batch_send`
prints the reply array exactly as the host sent it, one envelope per call, and returns 1 when any
member is an error (the first one on stderr).

Token: `actionui_hold_token`, `actionui_handoff COMMAND [ARGS...]`. Connection (zsh only):
`actionui_disconnect`.

## What the two transports do, and what they use

**`nc` (the `.sh`).** Each request starts `/usr/bin/nc -U` with its stdin and stdout on two FIFOs
in a fresh temporary directory. The request goes down the stdin FIFO; the reply is read from the
stdout FIFO with a timeout; only then is `nc`'s stdin closed. The order matters: macOS `nc`
half-closes the socket the moment its stdin ends, and the host closes a connection on EOF even
with a reply still pending on its main thread, so a request piped straight into `nc` can lose its
own answer. Descriptors 8 and 9 are used during a call; a script that has its own 8 or 9 open
will find them closed afterwards. `actionui_handoff` uses descriptor 5 within the call and 3 in
the child.

**`zsh/net/socket` (the `.zsh`).** One connection, opened on first use and kept. A request that
fails to send reconnects once and resends, since nothing reached the host; a failure while
waiting for the reply is reported, not retried, since the request may already have been applied
(a resent `appendRows` would apply twice). While a request is being written SIGPIPE is ignored so
that a host that went away is a failed send rather than a dead script; the disposition is then
reset to the default, which drops a PIPE trap of the script's own if it had one.

Both parse replies with `awk` (a top-level JSON walker: result, error, id, batch members) and
`plutil` (string unescaping, including `\uXXXX` and surrogate pairs), both restricted Apple
binaries. What they receive on stdin is replies, which never carry the token, plus in
`actionui_call` the caller's own params before the token is added. Request text is escaped in the
shell itself; text with control characters takes one `awk` pass, on stdin - the token included,
should a host ever mint one containing such a character, which is still stdin of a restricted
binary and never argv.

A reply the host could not parse at all comes back with a null id; these clients report it as the
`-32700` it is, where the Python client waits for a matching id and reports a timeout. A
well-formed line that is not our reply - a server-initiated line from a later protocol version,
say - is ignored, as the protocol requires. Text that is not JSON, an unterminated array, or an
object that carries our id with neither a result nor an error and no `method`, is reported as a
malformed reply (exit 3). A request the host never answers is a timeout (exit 3), bounded by
`ACTIONUI_REMOTE_TIMEOUT`.

Neither file sets a trap, so a script interrupted in the middle of an `nc` call leaves a small
directory with two FIFOs under `TMPDIR` and an `nc` that exits when its timeout expires. A script
that cares can trap INT and TERM itself. Under `/bin/sh` a failed redirection on `exec` ends the
script, as POSIX requires of a special builtin, so a process out of descriptors, or whose
`TMPDIR` vanished mid-call, ends there rather than reporting exit 3.

## Tests

```sh
cd ActionUIRemote/Shell && ./test_actionui_remote.sh          # the whole matrix
/bin/sh  test_actionui_remote.sh nc                            # one cell
/bin/zsh test_actionui_remote.sh zsocket
```

The matrix runs the `.sh` under `/bin/sh` and under zsh, and the `.zsh`, against the fake host in
`../Python/actionui_remote_testing.py` (needs a `python3`). The fake host requires a token, so
every request exercises the token path, and its log is checked at the end for the token in the
clear. The descriptor delivery is checked both ways: the token arrives, and afterwards the
descriptor is closed and the variable gone. The last group of checks is the reason the client exists: a child shell started with the
token in its environment does not show it to `ps -E`; with a request in flight, no process the
library runs shows it; a python3 child spawned with the token in its environment does, and the
same child through `actionui_handoff` does not. Those checks are positive as well as negative -
`ps` is shown to see the processes' argv - so they cannot pass on an empty `ps`. A request the
host never answers is also checked to time out, and to leave nothing behind that the next call
could mistake for its reply.

## Differences from the Python client

- Argument order is shell-shaped (see Functions), not the Python signatures.
- `--token` is refused on the command line. Use the environment or `ACTIONUI_REMOTE_TOKEN_FD`.
- Setters print nothing even as library functions; the Python API returns `True`.
- A null-id error reply (`-32700`) is reported rather than waited out.
- `actionui_batch_send` prints the raw reply array; there is no per-call post-processing.
- Under the `nc` transport the timeout is truncated to whole seconds (bash 3.2's `read -t` and `nc -w`).
- Extra arguments to a command are refused, as argparse does; `-h` is recognized only before the command.
