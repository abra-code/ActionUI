#!/bin/sh
# test_actionui_remote.sh - tests for actionui_remote.sh and actionui_remote.zsh.
#
# Run with no arguments and it runs the whole matrix - the sh library under /bin/sh, the sh
# library under /bin/zsh (nc transport), and the zsh wrapper under /bin/zsh (native transport) -
# against the fake host in ../Python/actionui_remote_testing.py, which needs a python3. Or run one
# cell directly:
#
#     /bin/sh  test_actionui_remote.sh nc
#     /bin/zsh test_actionui_remote.sh nc
#     /bin/zsh test_actionui_remote.sh zsocket
#
# Output is one line per check, "ok" or "not ok", then a summary; the exit status is the number
# of failures (0 when everything passed). The fake host requires a token, so every request also
# exercises the token path, and its log is checked at the end to confirm the token never reached
# it in the clear.
#
# The last group of checks is the reason this client exists: with a token in the environment, no
# process the library runs - the shell itself, or nc mid-request - shows that token to `ps -E`,
# while a python3 child spawned without actionui_hold_token does. Those checks need the host to
# hold a connection open without replying, which a bare `nc -l` provides.

_t_here=$(cd "$(/usr/bin/dirname "$0")" && pwd)
_t_python_dir="$_t_here/../Python"

# --- the matrix ---------------------------------------------------------------------------------

if [ "$#" -eq 0 ]; then
    _t_total=0
    t_cell() {
        printf '\n=== %s, %s transport ===\n' "$1" "$2"
        "$1" "$_t_here/test_actionui_remote.sh" "$2"
        _t_total=$((_t_total + $?))
    }
    t_cell /bin/sh nc
    t_cell /bin/zsh nc
    t_cell /bin/zsh zsocket
    printf '\n=== matrix: %s failure(s) ===\n' "$_t_total"
    exit "$_t_total"
fi

_t_transport=$1
# zsh renices background jobs and complains where it may not; this file starts several.
if [ -n "${ZSH_VERSION:-}" ]; then
    eval 'setopt no_bg_nice'
fi
case $_t_transport in
    nc|zsocket) ;;
    *) printf '%s\n' "usage: test_actionui_remote.sh [nc|zsocket]" >&2; exit 2 ;;
esac
if [ "$_t_transport" = "zsocket" ] && [ -z "${ZSH_VERSION:-}" ]; then
    printf '%s\n' "the zsocket transport needs zsh: /bin/zsh test_actionui_remote.sh zsocket" >&2
    exit 2
fi

# --- harness ------------------------------------------------------------------------------------

_t_pass=0
_t_fail=0

t_ok() {
    _t_pass=$((_t_pass + 1))
    printf 'ok - %s\n' "$1"
}

t_not_ok() {
    _t_fail=$((_t_fail + 1))
    printf 'not ok - %s\n' "$1"
    if [ -n "${2:-}" ]; then
        printf '    %s\n' "$2"
    fi
}

# t_eq NAME EXPECTED ACTUAL
t_eq() {
    if [ "$2" = "$3" ]; then
        t_ok "$1"
    else
        t_not_ok "$1" "expected [$2] got [$3]"
    fi
}

# t_contains NAME NEEDLE HAYSTACK
t_contains() {
    case $3 in
        *"$2"*) t_ok "$1" ;;
        *) t_not_ok "$1" "expected to find [$2] in [$3]" ;;
    esac
}

# t_lacks NAME NEEDLE HAYSTACK
t_lacks() {
    case $3 in
        *"$2"*) t_not_ok "$1" "found [$2] in [$3]" ;;
        *) t_ok "$1" ;;
    esac
}

_t_python=$(command -v python3)
if [ -z "$_t_python" ]; then
    printf '%s\n' "python3 is needed to run the fake host" >&2
    exit 2
fi

# A short scratch directory: the socket path has to fit in sun_path.
_t_tmp=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/auit.XXXXXX")
if [ $? -ne 0 ] || [ -z "$_t_tmp" ]; then
    printf '%s\n' "cannot create a scratch directory" >&2
    exit 2
fi
if [ "${#_t_tmp}" -gt 80 ]; then
    /bin/rm -rf "$_t_tmp"
    _t_tmp=$(/usr/bin/mktemp -d "/tmp/auit.XXXXXX")
    if [ $? -ne 0 ] || [ -z "$_t_tmp" ]; then
        printf '%s\n' "cannot create a short scratch directory under /tmp" >&2
        exit 2
    fi
fi
_t_sock="$_t_tmp/h.sock"
_t_log="$_t_tmp/log.jsonl"
_t_err="$_t_tmp/stderr"
_t_token="tok-$$-secret-3f9a1c"
_t_host=""

t_start_host() {
    "$_t_python" -m actionui_remote_testing --socket "$_t_sock" --log "$_t_log" \
        --window W-1 --element W-1:2:TextField --element W-1:5:Table --element W-1:7:Button \
        --token "$_t_token" >"$_t_tmp/host.out" 2>&1 &
    _t_host=$!
    _t_wait=0
    while [ ! -S "$_t_sock" ] && [ "$_t_wait" -lt 50 ]; do
        /bin/sleep 0.1
        _t_wait=$((_t_wait + 1))
    done
    if [ ! -S "$_t_sock" ]; then
        printf '%s\n' "the fake host did not start:" >&2
        /bin/cat "$_t_tmp/host.out" >&2
        exit 2
    fi
}

t_stop_host() {
    if [ -n "$_t_host" ]; then
        kill "$_t_host" 2>/dev/null
        wait "$_t_host" 2>/dev/null
        _t_host=""
    fi
}

t_cleanup() {
    t_stop_host
    /bin/rm -rf "$_t_tmp"
}
trap 't_cleanup' EXIT

cd "$_t_python_dir" || exit 2
t_start_host
cd "$_t_here" || exit 2

export ACTIONUI_REMOTE_ENDPOINT="$_t_sock"
export ACTIONUI_WINDOW_UUID="W-1"
export ACTIONUI_REMOTE_TOKEN="$_t_token"

if [ "$_t_transport" = "zsocket" ]; then
    . "$_t_here/actionui_remote.zsh"
    _t_cli="$_t_here/actionui_remote.zsh"
    _t_shell=/bin/zsh
else
    . "$_t_here/actionui_remote.sh"
    _t_cli="$_t_here/actionui_remote.sh"
    if [ -n "${ZSH_VERSION:-}" ]; then _t_shell=/bin/zsh; else _t_shell=/bin/sh; fi
fi
# The command line, run under the cell's shell rather than the file's shebang, so the zsh cells
# exercise the .sh's CLI under zsh too.
t_cli() {
    "$_t_shell" "$_t_cli" "$@"
}

# Run FUNCTION ARGS..., capturing stdout into _t_out, stderr into _t_stderr, status into _t_rc.
# The function runs in this shell - not in a $(...) subshell - so the library's state (request
# ids, an open batch, a held token, ACTIONUI_ERROR_CODE) carries from one call to the next, as it
# does in a real script.
t_run() {
    "$@" >"$_t_tmp/out" 2>"$_t_err"
    _t_rc=$?
    _t_out=$(/bin/cat "$_t_tmp/out")
    _t_stderr=$(/bin/cat "$_t_err")
}

# --- host level ---------------------------------------------------------------------------------

t_run actionui_hello
t_eq "hello exits 0" 0 "$_t_rc"
t_contains "hello reports the protocol version" '"protocolVersion":1' "$_t_out"
t_contains "hello lists the window" 'W-1' "$_t_out"

t_run actionui_windows
t_eq "windows prints one UUID per line" "W-1" "$_t_out"

t_run actionui_elements
t_contains "elements lists the text field" '"2":"TextField"' "$_t_out"

# --- values -------------------------------------------------------------------------------------

t_run actionui_get_value 2
t_eq "get_value of an unset element is null" "null" "$_t_out"

_t_nl=$(printf '\nx'); _t_nl=${_t_nl%x}
_t_tab=$(printf '\tx'); _t_tab=${_t_tab%x}
_t_tricky="quote \" backslash \\ slash / tab${_t_tab}tab newline${_t_nl}second line caf${_t_nl}"
_t_tricky="${_t_tricky}unicode: caf\0303\0251 \0360\0237\0230\0200 end"
_t_tricky=$(printf '%b' "$_t_tricky"; printf 'x'); _t_tricky=${_t_tricky%x}

t_run actionui_set_string 2 "$_t_tricky"
t_eq "set_string with quotes, backslashes, tabs, newlines, unicode exits 0" 0 "$_t_rc"
t_eq "set_string prints nothing" "" "$_t_out"
t_run actionui_get_string 2
t_eq "get_string round-trips the text exactly" "$_t_tricky" "$_t_out"
t_contains "the fixture really contains multi-byte text" "$(printf 'caf\303\251')" "$_t_tricky"
t_lacks "the fixture is not the literal escape text" "\\0303" "$_t_tricky"
t_run actionui_get_value 2
t_contains "get_value shows the JSON-escaped form" '\"' "$_t_out"

t_run actionui_set_string 2 ""
t_run actionui_get_string 2
t_eq "get_string of an empty string is an empty line" "" "$_t_out"

actionui_set_string 2 "two trailing${_t_nl}${_t_nl}" >/dev/null 2>&1
actionui_get_string 2 >"$_t_tmp/out" 2>"$_t_err"
_t_out=$(/bin/cat "$_t_tmp/out"; printf 'x'); _t_out=${_t_out%x}
t_eq "get_string keeps trailing newlines" "two trailing${_t_nl}${_t_nl}${_t_nl}" "$_t_out"

t_run actionui_set_value 2 '"plain"'
t_eq "set_value exits 0" 0 "$_t_rc"
t_run actionui_get_value 2
t_eq "get_value returns the JSON string" '"plain"' "$_t_out"

t_run actionui_set_int 2 42
t_run actionui_get_int 2
t_eq "set_int / get_int" "42" "$_t_out"
t_run actionui_set_int 2 -7
t_run actionui_get_int 2
t_eq "set_int accepts a negative number" "-7" "$_t_out"
t_run actionui_set_int 2 abc
t_eq "set_int rejects a non-integer with the usage status" 2 "$_t_rc"

t_run actionui_set_double 2 1.5
t_run actionui_get_double 2
t_eq "set_double / get_double" "1.5" "$_t_out"
t_run actionui_set_double 2 -1.5e-3
t_eq "set_double accepts an exponent" 0 "$_t_rc"
for _t_badnum in e - + 1e .5 +3 1e5e5 1. 1..2 1e- --1 1-2 1+2 e5 0123 1e+-5; do
    t_run actionui_set_double 2 "$_t_badnum"
    t_eq "set_double rejects '$_t_badnum'" 2 "$_t_rc"
done
for _t_goodnum in 1 -1 1.5 -1.5e-3 1E5 0.5 10e+2 0 -0.25; do
    t_run actionui_set_double 2 "$_t_goodnum"
    t_eq "set_double accepts '$_t_goodnum'" 0 "$_t_rc"
done
t_run actionui_get_value 2
t_eq "a successful call leaves ACTIONUI_RESULT set" "-0.25" "$ACTIONUI_RESULT"
t_run actionui_get_value x
t_eq "ACTIONUI_RESULT is cleared on a usage error too" "" "$ACTIONUI_RESULT"

t_run actionui_set_bool 2 true
t_run actionui_get_bool 2
t_eq "set_bool / get_bool" "true" "$_t_out"
t_run actionui_set_bool 2 no
t_run actionui_get_bool 2
t_eq "set_bool normalizes no to false" "false" "$_t_out"

t_run actionui_set_string 2 "col" 1
t_eq "set_string with a part exits 0" 0 "$_t_rc"
t_contains "viewPartID is sent for a non-zero part" '"viewPartID": 1' "$(/usr/bin/tail -n 1 "$_t_log")"

# --- properties and state -----------------------------------------------------------------------

t_run actionui_set_property 2 disabled true
t_run actionui_get_property 2 disabled
t_eq "set_property / get_property" "true" "$_t_out"
t_run actionui_set_enabled 2 true
t_run actionui_get_property 2 disabled
t_eq "set_enabled true clears disabled" "false" "$_t_out"
t_run actionui_set_hidden 2 1
t_run actionui_get_property 2 hidden
t_eq "set_hidden 1 sets hidden" "true" "$_t_out"

t_run actionui_set_state 2 counter 5
t_run actionui_get_state 2 counter
t_eq "set_state / get_state" "5" "$_t_out"
t_run actionui_set_state_string 2 label "a b"
t_run actionui_get_state_string 2 label
t_eq "set_state_string / get_state_string" "a b" "$_t_out"

# --- rows and selection -------------------------------------------------------------------------

t_run actionui_set_rows 5 '[["a","b"],["c","d"]]'
t_eq "set_rows exits 0" 0 "$_t_rc"
t_run actionui_get_rows 5
t_eq "get_rows returns the rows" '[["a","b"],["c","d"]]' "$_t_out"
t_run actionui_get_column_count 5
t_eq "get_column_count" "2" "$_t_out"
t_run actionui_append_rows 5 '[["e","f"]]'
t_run actionui_get_rows 5
t_contains "append_rows appends" '["e","f"]' "$_t_out"
t_run actionui_select_row 5 1
t_eq "select_row prints the row" '["c","d"]' "$_t_out"
t_run actionui_select_row 5 99
t_eq "select_row out of range is null" "null" "$_t_out"
t_run actionui_select_row_with_content 5 "e"
t_eq "select_row_with_content prints the index" "2" "$_t_out"
t_run actionui_select_row_with_content 5 "zzz" 0
t_eq "select_row_with_content with no match is -1" "-1" "$_t_out"
t_run actionui_clear_selection 5
t_eq "clear_selection exits 0 and prints nothing" "0:" "$_t_rc:$_t_out"
t_run actionui_clear_rows 5
t_run actionui_get_rows 5
t_eq "clear_rows empties the table" "[]" "$_t_out"

# --- structure and presentation -----------------------------------------------------------------

t_run actionui_insert_element 5 '{"type":"Label","id":40,"title":"x"}'
t_eq "insert_element prints the new id" "40" "$_t_out"
t_run actionui_insert_element 5 '{"type":"Label","title":"y"}' "" append
t_eq "insert_element with the append shorthand exits 0" 0 "$_t_rc"
t_run actionui_insert_row 5 '[{"type":"Label","id":41},{"type":"Label","id":42}]' "" '{"kind":"at","index":0}'
t_eq "insert_row prints the ids" "[41,42]" "$_t_out"
t_run actionui_remove_element 40
t_eq "remove_element exits 0" 0 "$_t_rc"

t_run actionui_present_alert "Title" "Body" '[{"title":"OK"}]'
t_eq "present_alert exits 0 and prints nothing" "0:" "$_t_rc:$_t_out"
t_run actionui_present_confirmation_dialog "Sure?" "" '[{"title":"Yes","role":"destructive"}]'
t_eq "present_confirmation_dialog exits 0" 0 "$_t_rc"
t_run actionui_dismiss_dialog
t_eq "dismiss_dialog exits 0" 0 "$_t_rc"
t_run actionui_present_toast "Saved" 2.5 "Undo" "undo"
t_eq "present_toast exits 0" 0 "$_t_rc"
t_contains "present_toast sends the duration" '"duration": 2.5' "$(/usr/bin/tail -n 1 "$_t_log")"
t_run actionui_present_toast "Saved" abc
t_eq "present_toast rejects a bad duration" 2 "$_t_rc"
t_run actionui_dismiss_toast
t_run actionui_present_modal_json '{"type":"Label"}' json sheet dismissed
t_eq "present_modal_json exits 0" 0 "$_t_rc"
t_contains "present_modal_json sends the style" '"style": "sheet"' "$(/usr/bin/tail -n 1 "$_t_log")"
t_run actionui_present_modal_path "MyModal"
t_eq "present_modal_path exits 0" 0 "$_t_rc"
t_run actionui_dismiss_modal
t_run actionui_content_size_limits
t_eq "content_size_limits is null on the fake" "null" "$_t_out"

# --- call, windows, batch -----------------------------------------------------------------------

t_run actionui_call actionui.getElementInfo
t_contains "call fills in the window" '"7":"Button"' "$_t_out"
t_run actionui_call actionui.getElementInfo '{"window":"W-1"}'
t_eq "call keeps an explicit window" 0 "$_t_rc"
t_run actionui_call omc.terminate '{"ok":true}'
t_eq "call reaches a host method" "true" "$_t_out"
t_run actionui_call actionui.getElementInfo '[1]'
t_eq "call rejects non-object params" 2 "$_t_rc"

actionui_use_window "W-1"
t_run actionui_get_value 7
t_eq "use_window addresses a window explicitly" "null" "$_t_out"

actionui_batch_begin
t_run actionui_set_string 2 "batched"
t_eq "a batched setter prints nothing and exits 0" "0:" "$_t_rc:$_t_out"
t_run actionui_get_value 2
t_eq "a batched getter prints nothing" "" "$_t_out"
t_run actionui_batch_send
t_eq "batch_send exits 0" 0 "$_t_rc"
t_contains "batch_send prints the reply array with the second result" '"result":"batched"' "$_t_out"
t_contains "the batch went out as one array" '"method": "actionui.setValueString"' "$(/usr/bin/tail -n 2 "$_t_log" | /usr/bin/head -n 1)"

actionui_batch_begin
actionui_get_value 2 >/dev/null
actionui_get_value 99 >/dev/null
t_run actionui_batch_send
t_eq "batch_send with a failed member exits 1" 1 "$_t_rc"
t_contains "batch_send reports the member's error" "[1002]" "$_t_stderr"
t_contains "batch_send still prints the whole reply" '"result":"batched"' "$_t_out"

t_run actionui_batch_send
t_eq "batch_send without a batch is a usage error" 2 "$_t_rc"

# --- errors -------------------------------------------------------------------------------------

t_run actionui_get_value 99
t_eq "an unknown view exits 1" 1 "$_t_rc"
t_contains "the error code and message go to stderr" "[1002]" "$_t_stderr"
t_eq "ACTIONUI_ERROR_CODE is set" "1002" "$ACTIONUI_ERROR_CODE"
t_run actionui_call actionui.noSuchMethod
t_contains "an unknown actionui method is -32601" "[-32601]" "$_t_stderr"

t_run actionui_set_value 2 '{not json'
t_eq "a request the host cannot parse exits 1" 1 "$_t_rc"
t_contains "the parse error with its null id is reported, not waited out" "[-32700]" "$_t_stderr"
t_run actionui_get_value 2
t_eq "the client is fine after a parse error" 0 "$_t_rc"

t_run actionui_get_value
t_eq "a missing VIEWID is a usage error" 2 "$_t_rc"
t_run actionui_get_value x
t_eq "a non-integer VIEWID is a usage error" 2 "$_t_rc"
t_run actionui_get_value ""
t_eq "an empty VIEWID is a usage error" 2 "$_t_rc"
t_run actionui_get_string ""
t_eq "an empty VIEWID to get_string is a usage error" 2 "$_t_rc"
t_run actionui_get_state_string "" key
t_eq "an empty VIEWID to get_state_string is a usage error" 2 "$_t_rc"

# Lines that are not our reply: a server-initiated line is skipped (PROTOCOL.md section 3), a
# reply to another id is skipped, and only text that is not JSON at all is malformed.
_aui_reply_matches '{"jsonrpc":"2.0","method":"actionui.event","params":{"viewID":7}}' 1
t_eq "a server-initiated notification is skipped, not an error" 1 "$?"
_aui_reply_matches '{"jsonrpc":"2.0","id":99,"result":true}' 1
t_eq "a reply to another id is skipped" 1 "$?"
_aui_reply_matches '"just a string"' 1
t_eq "a JSON scalar line is skipped" 1 "$?"
_aui_reply_matches 'not json at all' 1
t_eq "unparseable text is malformed" 2 "$?"
_aui_reply_matches '' 1
t_eq "an empty line is malformed" 2 "$?"
_aui_reply_matches '{"jsonrpc":"2.0","id":1,"result":null}' 1
t_eq "our reply matches" 0 "$?"
_aui_reply_matches '{"jsonrpc":"2.0","id":null,"error":{"code":-32700,"message":"x"}}' 1
t_eq "a null-id error is taken as our reply" 0 "$?"
_aui_reply_matches '{"jsonrpc":"2.0","id":1}' 1
t_eq "an object with our id but no result or error is malformed" 2 "$?"
_aui_reply_matches '[1,2' ""
t_eq "an unterminated batch array is malformed" 2 "$?"
_aui_reply_matches '[}' ""
t_eq "a mismatched closer is malformed, not a batch" 2 "$?"
_aui_reply_matches '{"jsonrpc":"2.0","id":1,"method":"actionui.event","params":{}}' 1
t_eq "a server-initiated request with our id is still skipped" 1 "$?"
ACTIONUI_REMOTE_TIMEOUT=.5 _aui_timeout
t_eq "a leading-dot timeout is normalized for zsh's read -t" "0.5" "$_aui_to"
unset ACTIONUI_REMOTE_TIMEOUT

# The array walker must always make progress: a malformed element used to loop forever.
for _t_bad in '[}]' '[1,}]' '[ } ]' '[}' '[{"a":1},}]' '["unterminated]'; do
    /bin/rm -f "$_t_tmp/walk.rc"
    ( printf '%s\n' "$_t_bad" | _aui_walk items >/dev/null 2>&1; printf '%s' "$?" >"$_t_tmp/walk.rc" ) &
    _t_walk=$!
    /bin/sleep 0.5
    if kill -0 "$_t_walk" 2>/dev/null; then
        kill "$_t_walk" 2>/dev/null
        t_not_ok "the items walker terminates on $_t_bad" "still running after 0.5 s"
    else
        t_eq "the items walker exits 1 on $_t_bad" 1 "$(/bin/cat "$_t_tmp/walk.rc" 2>/dev/null)"
    fi
    wait "$_t_walk" 2>/dev/null
done
_t_out=$(printf '%s\n' '["a",{"b":[1,2]},null]' | _aui_walk items | /usr/bin/wc -l | /usr/bin/tr -d ' ')
t_eq "the items walker still walks a good array" 3 "$_t_out"
t_run actionui_call actionui.getElementInfo '  {"window":"W-1"}  '
t_eq "call tolerates whitespace around the params" 0 "$_t_rc"

ACTIONUI_REMOTE_ENDPOINT="$_t_tmp/nobody.sock"
t_run actionui_hello
t_eq "no host listening exits 3" 3 "$_t_rc"
t_contains "no host listening says so" "no ActionUI host is listening" "$_t_stderr"
ACTIONUI_REMOTE_ENDPOINT=""
t_run actionui_hello
t_eq "no endpoint exits 3" 3 "$_t_rc"
t_contains "no endpoint names the variable" "ACTIONUI_REMOTE_ENDPOINT is not set" "$_t_stderr"
ACTIONUI_REMOTE_ENDPOINT="$_t_sock"

# --- token --------------------------------------------------------------------------------------

_t_saved_token=$ACTIONUI_REMOTE_TOKEN
ACTIONUI_REMOTE_TOKEN=""
t_run actionui_get_value 2
t_eq "without a token the host refuses with 1006" 1 "$_t_rc"
t_contains "1006 is reported" "[1006]" "$_t_stderr"
ACTIONUI_REMOTE_TOKEN="wrong"
t_run actionui_get_value 2
t_contains "a wrong token is 1006" "[1006]" "$_t_stderr"
ACTIONUI_REMOTE_TOKEN=$_t_saved_token
t_run actionui_get_value 2
t_eq "the right token again works" 0 "$_t_rc"

# From a descriptor: the secret arrives on a pipe the child inherits.
_t_out=$(printf '%s\n' "$_t_token" | ACTIONUI_REMOTE_TOKEN="" ACTIONUI_REMOTE_TOKEN_FD=0 t_cli get-value 2 2>"$_t_err"); _t_rc=$?
t_eq "the token can come from ACTIONUI_REMOTE_TOKEN_FD" 0 "$_t_rc"
_t_out=$(printf '' | ACTIONUI_REMOTE_TOKEN="" ACTIONUI_REMOTE_TOKEN_FD=0 t_cli get-value 2 2>"$_t_err"); _t_rc=$?
t_eq "an empty descriptor is reported as no host" 3 "$_t_rc"

# The descriptor's lifecycle, in this shell: read once, then closed, and the variable removed. A
# descriptor above 9, since zsh's redirection syntax stops at 9 and the library must cope; the
# file has a second line, so a read that still succeeds would prove the descriptor was left open.
printf '%s\nsecond line\n' "$_t_token" >"$_t_tmp/fd.txt"
if [ -n "${ZSH_VERSION:-}" ]; then
    eval 'exec {_t_tokfd}<"$_t_tmp/fd.txt"'
else
    _t_tokfd=12
    eval "exec $_t_tokfd<\"\$_t_tmp/fd.txt\""
fi
export ACTIONUI_REMOTE_TOKEN_FD=$_t_tokfd
ACTIONUI_REMOTE_TOKEN=""
_AUI_TOKEN_HELD=0
t_run actionui_get_value 2
t_eq "the token can be read from a descriptor above 9 in this shell" 0 "$_t_rc"
t_eq "after which the variable is removed" "" "${ACTIONUI_REMOTE_TOKEN_FD:-}"
_t_probe=""
IFS= read -r -u "$_t_tokfd" _t_probe 2>/dev/null
t_eq "and the descriptor is closed (a read from it gets nothing)" "" "$_t_probe"
t_run actionui_get_value 2
t_eq "and later calls use the held token" 0 "$_t_rc"
/bin/rm -f "$_t_tmp/fd.txt"

# A descriptor that cannot be read fails closed: hold_token still removes the variables, the
# message is ours alone, and the library then holds nothing (so the host answers 1006).
{ exec 6<&-; } 2>/dev/null
export ACTIONUI_REMOTE_TOKEN="$_t_token"
export ACTIONUI_REMOTE_TOKEN_FD=6
_AUI_TOKEN_HELD=0
actionui_hold_token 2>"$_t_err"
t_eq "hold_token with an unreadable descriptor returns 3" 3 "$?"
t_eq "and still removes the token from the environment" "" "${ACTIONUI_REMOTE_TOKEN:-}${ACTIONUI_REMOTE_TOKEN_FD:-}"
t_eq "and prints only its own message" "nothing could be read from descriptor 6 (ACTIONUI_REMOTE_TOKEN_FD)" "$(/bin/cat "$_t_err")"
t_run actionui_get_value 2
t_eq "and a request without a token is then refused" 1 "$_t_rc"
# Restore: take the real token again.
export ACTIONUI_REMOTE_TOKEN="$_t_token"
_AUI_TOKEN_HELD=0

# hold_token: the environment loses the token, the library keeps working.
actionui_hold_token
t_eq "hold_token removes ACTIONUI_REMOTE_TOKEN from the environment" "" "${ACTIONUI_REMOTE_TOKEN:-}"
t_lacks "a child no longer inherits the token" "ACTIONUI_REMOTE_TOKEN" "$(/usr/bin/env)"
t_run actionui_get_value 2
t_eq "calls keep working from the held token" 0 "$_t_rc"

# handoff: the child gets the token on descriptor 3, not in its environment or argv.
_t_probe='IFS= read -r t <&3; [ "$t" = "'"$_t_token"'" ] || exit 10; [ -z "${ACTIONUI_REMOTE_TOKEN:-}" ] || exit 11; [ "${ACTIONUI_REMOTE_TOKEN_FD:-}" = 3 ] || exit 12; exit 0'
actionui_handoff /bin/sh -c "$_t_probe"
t_eq "handoff delivers the token on fd 3 with the environment scrubbed" 0 "$?"
_t_out=$(printf 'stdin-data\n' | actionui_handoff /bin/sh -c 'IFS= read -r x; printf "%s" "$x"')
t_eq "handoff preserves the child's stdin" "stdin-data" "$_t_out"
actionui_handoff /bin/sh -c 'exit 7'
t_eq "handoff returns the child's status" 7 "$?"
t_run actionui_handoff
t_eq "handoff without a command is a usage error" 2 "$_t_rc"
# ...and the handed-off child can itself use the library through the descriptor.
_t_out=$(actionui_handoff t_cli get-value 2 2>"$_t_err"); _t_rc=$?
t_eq "a handed-off CLI reads its token from the descriptor and works" 0 "$_t_rc"

# --- the command line ---------------------------------------------------------------------------
# The CLI runs as a child process and reads its token from the environment, which hold_token
# above emptied; put it back for the children (the library itself keeps using the held copy).

export ACTIONUI_REMOTE_TOKEN="$_t_token"

_t_out=$(t_cli --window W-1 get-string 2 2>"$_t_err"); _t_rc=$?
t_eq "CLI get-string" "0:batched" "$_t_rc:$_t_out"
_t_out=$(t_cli set-string 2 -- -dash 2>"$_t_err"); _t_rc=$?
t_eq "CLI set-string with -- before a dash argument" "0:" "$_t_rc:$_t_out"
_t_out=$(t_cli get-string 2 2>"$_t_err")
t_eq "CLI get-string reads it back" "-dash" "$_t_out"
_t_out=$(t_cli set-value 2 '"p"' --part 1 2>"$_t_err"); _t_rc=$?
t_eq "CLI --part after the positionals" 0 "$_t_rc"
t_contains "CLI --part reaches the wire" '"viewPartID": 1' "$(/usr/bin/tail -n 1 "$_t_log")"
_t_out=$(t_cli call actionui.getRows '{"viewID":5}' 2>"$_t_err"); _t_rc=$?
t_eq "CLI call fills in the window" 0 "$_t_rc"
_t_out=$(t_cli windows 2>"$_t_err")
t_eq "CLI windows" "W-1" "$_t_out"
_t_out=$(t_cli get-value 99 2>"$_t_err"); _t_rc=$?
t_eq "CLI remote error exits 1" 1 "$_t_rc"
_t_out=$(t_cli get-value 2>"$_t_err"); _t_rc=$?
t_eq "CLI usage error exits 2" 2 "$_t_rc"
_t_out=$(t_cli bogus 2>"$_t_err"); _t_rc=$?
t_eq "CLI unknown command exits 2" 2 "$_t_rc"
_t_out=$(t_cli get-value 2 99 2>"$_t_err"); _t_rc=$?
t_eq "CLI extra positional argument exits 2" 2 "$_t_rc"
_t_out=$(t_cli hello extra 2>"$_t_err"); _t_rc=$?
t_eq "CLI extra argument to hello exits 2" 2 "$_t_rc"
_t_out=$(t_cli --timeout 2.5 hello 2>"$_t_err"); _t_rc=$?
t_eq "CLI accepts a fractional timeout" 0 "$_t_rc"
t_eq "and prints no shell noise on stderr" "" "$(/bin/cat "$_t_err")"
_t_out=$(t_cli --token x hello 2>"$_t_err"); _t_rc=$?
t_eq "CLI refuses --token" 2 "$_t_rc"
t_contains "CLI says why --token is refused" "argv" "$(/bin/cat "$_t_err")"
_t_out=$(ACTIONUI_WINDOW_UUID="" t_cli get-value 2 2>"$_t_err"); _t_rc=$?
t_eq "CLI without a window exits 2" 2 "$_t_rc"
_t_out=$(ACTIONUI_WINDOW_UUID="" ACTIONUI_REMOTE_ENDPOINT="" t_cli get-value 2 2>"$_t_err"); _t_rc=$?
t_eq "CLI reports a missing endpoint before a missing window" 3 "$_t_rc"
_t_out=$(t_cli --timeout 0 hello 2>"$_t_err"); _t_rc=$?
t_eq "CLI rejects a zero timeout" 2 "$_t_rc"
_t_out=$(t_cli --timeout 00 hello 2>"$_t_err"); _t_rc=$?
t_eq "CLI rejects 00 as a timeout" 2 "$_t_rc"
_t_out=$(t_cli --timeout .000 hello 2>"$_t_err"); _t_rc=$?
t_eq "CLI rejects .000 as a timeout" 2 "$_t_rc"
_t_out=$(t_cli --timeout 09 hello 2>"$_t_err"); _t_rc=$?
t_eq "CLI rejects a timeout with a leading zero" 2 "$_t_rc"
_t_out=$(t_cli --timeout 00.9 hello 2>"$_t_err"); _t_rc=$?
t_eq "CLI rejects 00.9 as a timeout" 2 "$_t_rc"
_t_out=$(t_cli --help 2>"$_t_err"); _t_rc=$?
t_eq "CLI --help exits 0" 0 "$_t_rc"

# --- the host restarting (persistent connection) -----------------------------------------------

if [ "$_t_transport" = "zsocket" ]; then
    t_run actionui_get_value 2
    t_stop_host
    cd "$_t_python_dir" && t_start_host && cd "$_t_here"
    t_run actionui_get_value 2
    t_eq "after the host restarts, the next call reconnects and succeeds" 0 "$_t_rc"
    t_run actionui_get_string 2
    t_eq "and the connection is usable afterwards" 0 "$_t_rc"
fi

# --- the log never saw the token ----------------------------------------------------------------

t_lacks "the fake host's request log does not contain the token" "$_t_token" "$(/bin/cat "$_t_log")"
t_contains "requests carried a token (the log redacts it)" '"token": "<redacted>"' "$(/usr/bin/tail -n 1 "$_t_log")"

# --- what ps can see ----------------------------------------------------------------------------
#
# ps -E reads KERN_PROCARGS2, the same source as `ps eww`. A process with CS_RESTRICT shows argv
# and no environment; python3 shows both. Two processes are excluded from the sweep on purpose:
# the fake host, which is a python3 process started with the token in its argv (argv is visible
# for every process, restricted or not - the reason the CLI refuses --token), and ps itself,
# which like any process can read its own environment. The token is unexported here so that ps
# and the sweep's own pipeline do not inherit it; the in-flight client gets it on its command
# line instead.

unset ACTIONUI_REMOTE_TOKEN

ACTIONUI_REMOTE_TOKEN="$_t_token" "$_t_shell" -c '/bin/sleep 1.5; exit 0  # aui-shell-probe' &
_t_shpid=$!
/bin/sleep 0.4
_t_sh_ps=$(/bin/ps -E -p "$_t_shpid" -o command= 2>/dev/null)
t_contains "ps can see a child shell's argv" "aui-shell-probe" "$_t_sh_ps"
t_lacks "a child shell with the token in its exec-time environment does not show it to ps" \
    "$_t_token" "$_t_sh_ps"
wait "$_t_shpid" 2>/dev/null

# A listener that accepts and never answers, so a request stays in flight while we look. Its
# stdin ends after three seconds, which makes it half-close and lets everything exit on its own.
_t_hang="$_t_tmp/hang.sock"
/bin/sleep 3 | /usr/bin/nc -l -U "$_t_hang" >/dev/null 2>&1 &
_t_hang_pid=$!
_t_wait=0
while [ ! -S "$_t_hang" ] && [ "$_t_wait" -lt 50 ]; do /bin/sleep 0.1; _t_wait=$((_t_wait + 1)); done
if [ -S "$_t_hang" ]; then
    ACTIONUI_REMOTE_TOKEN="$_t_token" ACTIONUI_REMOTE_ENDPOINT="$_t_hang" ACTIONUI_REMOTE_TIMEOUT=20 \
        t_cli get-value 2 >/dev/null 2>&1 &
    _t_inflight=$!
    /bin/sleep 1
    _t_all_ps=$(/bin/ps -A -E -o pid= -o command= 2>/dev/null | /usr/bin/grep -v "^ *$_t_host " | /usr/bin/grep -v ' /bin/ps -A -E ')
    _t_client_ps=$(printf '%s\n' "$_t_all_ps" | /usr/bin/grep -F "$_t_cli" | /usr/bin/grep -F "get-value 2" | /usr/bin/grep -v grep)
    if [ -n "$_t_client_ps" ]; then
        t_ok "ps can see the in-flight client's argv"
    else
        t_not_ok "ps can see the in-flight client's argv" "the client process was not found"
    fi
    _t_seen=$(printf '%s\n' "$_t_all_ps" | /usr/bin/grep -F "$_t_token" | /usr/bin/grep -v grep)
    t_eq "with a request in flight, no process shows the token to ps" "" "$_t_seen"
    if [ "$_t_transport" = "nc" ]; then
        _t_ncpids=$(/usr/bin/pgrep -f "nc -w [0-9]+ -U $_t_hang")
        if [ -n "$_t_ncpids" ]; then
            t_ok "the in-flight request has an nc helper to inspect"
        else
            t_not_ok "the in-flight request has an nc helper to inspect" "no nc found"
        fi
    fi
    wait "$_t_inflight" 2>/dev/null
    _t_rc=$?
    t_eq "when the host closes without answering, the request exits 3" 3 "$_t_rc"
else
    t_not_ok "a hanging listener could be started" "nc -l did not create $_t_hang"
fi
wait "$_t_hang_pid" 2>/dev/null

# A timeout is bounded, reported as one, and leaves nothing behind for the next call to mistake
# for its own reply. This is the library sourced in this shell, after successful calls above.
_t_hang="$_t_tmp/hang2.sock"
/bin/sleep 12 | /usr/bin/nc -l -U "$_t_hang" >/dev/null 2>&1 &
_t_hang_pid=$!
_t_wait=0
while [ ! -S "$_t_hang" ] && [ "$_t_wait" -lt 50 ]; do /bin/sleep 0.1; _t_wait=$((_t_wait + 1)); done
if [ -S "$_t_hang" ]; then
    # Set and restore explicitly: in bash's POSIX mode an assignment prefixed to a function call
    # persists after the call, so `VAR=x t_run ...` would leave the hang endpoint in place.
    _t_saved_ep=$ACTIONUI_REMOTE_ENDPOINT
    ACTIONUI_REMOTE_ENDPOINT=$_t_hang
    ACTIONUI_REMOTE_TIMEOUT=2
    _t_before=$(/bin/date +%s)
    t_run actionui_get_value 2
    _t_elapsed=$(( $(/bin/date +%s) - _t_before ))
    t_eq "a request the host never answers exits 3" 3 "$_t_rc"
    t_eq "and prints nothing, not the previous call's reply" "" "$_t_out"
    t_eq "and ACTIONUI_RESULT is cleared, not the previous call's" "" "$ACTIONUI_RESULT"
    t_contains "and is reported as a timeout" "no reply from" "$_t_stderr"
    if [ "$_t_elapsed" -le 6 ]; then
        t_ok "and returns within the timeout (${_t_elapsed}s)"
    else
        t_not_ok "and returns within the timeout" "took ${_t_elapsed}s"
    fi
    kill "$_t_hang_pid" 2>/dev/null
    wait "$_t_hang_pid" 2>/dev/null
    # A fresh listener for the batch: nc -l serves one connection and exits.
    _t_hang="$_t_tmp/hang3.sock"
    /bin/sleep 12 | /usr/bin/nc -l -U "$_t_hang" >/dev/null 2>&1 &
    _t_hang_pid=$!
    _t_wait=0
    while [ ! -S "$_t_hang" ] && [ "$_t_wait" -lt 50 ]; do /bin/sleep 0.1; _t_wait=$((_t_wait + 1)); done
    ACTIONUI_REMOTE_ENDPOINT=$_t_hang
    actionui_batch_begin
    actionui_get_value 2 >/dev/null
    t_run actionui_batch_send
    t_eq "a batch the host never answers exits 3, not 0 with a stale array" 3 "$_t_rc"
    t_eq "and prints nothing" "" "$_t_out"
    t_contains "and is reported as a timeout too" "no reply from" "$_t_stderr"
    ACTIONUI_REMOTE_ENDPOINT=$_t_saved_ep
    unset ACTIONUI_REMOTE_TIMEOUT
    t_run actionui_get_value 2
    t_eq "the next call to the real host works" 0 "$_t_rc"
    kill "$_t_hang_pid" 2>/dev/null
else
    t_not_ok "a second hanging listener could be started" "nc -l did not create $_t_hang"
fi
wait "$_t_hang_pid" 2>/dev/null
/bin/rm -f "$_t_hang"

# The contrast: a python3 child spawned with the token in the environment exposes it...
ACTIONUI_REMOTE_TOKEN="$_t_token" "$_t_python" -c 'import time; time.sleep(1.5)' &
_t_py=$!
/bin/sleep 0.5
t_contains "a python3 child with the token in its environment shows it to ps (the leak)" \
    "$_t_token" "$(/bin/ps -E -p "$_t_py" -o command= 2>/dev/null)"
wait "$_t_py" 2>/dev/null
# ...and the same child through the handoff does not. The marker in its argv is how it is found.
actionui_handoff "$_t_python" -c 'import os, time; os.read(3, 4096); time.sleep(2)  # aui-handoff-probe' &
_t_ho=$!
/bin/sleep 0.7
_t_probe_ps=$(/bin/ps -A -E -o command= 2>/dev/null | /usr/bin/grep -F 'aui-handoff-probe' | /usr/bin/grep -F 'os.read(3' | /usr/bin/grep -v grep)
if [ -n "$_t_probe_ps" ]; then
    t_ok "the handed-off python3 child is running and visible to ps"
else
    t_not_ok "the handed-off python3 child is running and visible to ps" "not found"
fi
t_lacks "a python3 child through actionui_handoff does not show the token to ps" "$_t_token" "$_t_probe_ps"
wait "$_t_ho" 2>/dev/null

# --- summary ------------------------------------------------------------------------------------

printf '%s passed, %s failed\n' "$_t_pass" "$_t_fail"
exit "$_t_fail"
