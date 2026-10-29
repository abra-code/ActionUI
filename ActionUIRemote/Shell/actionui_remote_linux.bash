#!/bin/bash
# actionui_remote_linux.bash - actionui_remote.sh on Linux, under bash 5.
#
# Everything about the API, the commands, the exit codes and the token is in actionui_remote.sh,
# which this file sources; read that first. What this file changes is what is macOS's there:
#
#   - The transport. One OpenBSD netcat per request, `nc -N -U`, with the request on its stdin and
#     coreutils `timeout` bounding it: -N shuts the socket's sending side once the request is
#     written, the host answers a half-closed connection and then closes it, and nc exits. No
#     FIFOs and no `read -t`, and a fractional ACTIONUI_REMOTE_TIMEOUT is honored as it is.
#   - Reading a string back. actionui_remote.sh has plutil unescape a JSON string literal; Linux
#     has none, so actionui_remote_unquote.awk beside this file does it.
#   - The socket path limit: 107 bytes in Linux's sun_path, where macOS's is 103.
#
# Linux only, bash 5 or later. The bash 3.2 rule that actionui_remote.sh keeps for macOS does not
# apply to this file, whose own guard below turns away macOS's bash 3.2, any bash on macOS (the
# transport needs OpenBSD netcat's -N and coreutils' timeout, which macOS lacks), and other shells.
# Debian's and Ubuntu's /bin/sh is dash, which cannot run actionui_remote.sh, so the command line
# names bash in its first line rather than sh.
#
# The token: on Linux any process of the same user reads another's environment from
# /proc/<pid>/environ, shells included, so ACTIONUI_REMOTE_TOKEN in a shell's environment is no
# better hidden than in a python3 one; the descriptor (ACTIONUI_REMOTE_TOKEN_FD) is the only way to
# keep it out of reach, and the token still never goes into argv. See the README beside this file.
#
# Use as a library, from a bash script:
#
#     . /path/to/actionui_remote_linux.bash
#     actionui_set_string 4 "Working..."
#
# Use as a command, exactly like actionui_remote.sh:
#
#     actionui_remote_linux.bash --window UUID get-value 5
#
# Requirements: bash 5, OpenBSD netcat (Debian's and Ubuntu's netcat-openbsd, their default nc),
# coreutils timeout, awk (gawk or mawk), and the five files beside one another: this one,
# actionui_remote.sh, actionui_remote_escape.awk, actionui_remote_walk.awk and
# actionui_remote_unquote.awk.

# The guard, in syntax every shell parses, so that dash and macOS's bash 3.2 read as far as it and
# stop with a message: bash first, then Linux, then the version.
if [ -z "${BASH_VERSION:-}" ]; then
    printf '%s\n' "actionui_remote_linux.bash needs bash 5 or later; this shell is not bash" >&2
    return 2 2>/dev/null || exit 2
fi
case ${OSTYPE:-} in
    linux*) ;;
    *)
        printf '%s\n' "actionui_remote_linux.bash is for Linux (bash 5); on macOS use actionui_remote.sh or actionui_remote.zsh" >&2
        return 2 2>/dev/null || exit 2 ;;
esac
case $BASH_VERSION in
    [0-4].*)
        printf '%s\n' "actionui_remote_linux.bash needs bash 5 or later; this is bash $BASH_VERSION" >&2
        return 2 2>/dev/null || exit 2 ;;
esac

# The tools the transport needs: OpenBSD netcat for -U and -N (the traditional netcat has neither,
# and would fail every request with a misleading message), and timeout.
_aui_linux_nc_help=$(/usr/bin/nc -h 2>&1)
case $_aui_linux_nc_help in
    *"-N"*"-U"*) ;;
    *)
        printf '%s\n' "actionui_remote_linux.bash needs OpenBSD netcat at /usr/bin/nc, for its -U and -N (Debian and Ubuntu: netcat-openbsd)" >&2
        unset _aui_linux_nc_help
        return 2 2>/dev/null || exit 2 ;;
esac
unset _aui_linux_nc_help
if [ ! -x /usr/bin/timeout ]; then
    printf '%s\n' "actionui_remote_linux.bash needs /usr/bin/timeout (coreutils)" >&2
    return 2 2>/dev/null || exit 2
fi

# The folder of this file, symlinks resolved, so that the files beside it are found whatever the
# caller's directory, now or after a later cd.
_aui_linux_dir=$(/usr/bin/readlink -f "${BASH_SOURCE[0]}")
_aui_linux_dir=${_aui_linux_dir%/*}
if [ -z "$_aui_linux_dir" ]; then
    _aui_linux_dir=/
fi
_AUI_AWK_UNQUOTE="$_aui_linux_dir/actionui_remote_unquote.awk"
if [ ! -r "$_AUI_AWK_UNQUOTE" ]; then
    printf '%s\n' "actionui_remote_linux.bash: cannot read actionui_remote_unquote.awk in '$_aui_linux_dir'; the files go together, copy them as a set" >&2
    unset _aui_linux_dir _AUI_AWK_UNQUOTE
    return 2 2>/dev/null || exit 2
fi

# The API. The .sh refuses to load on Linux unless it is this file that loads it. It turns itself
# away when its own awk programs are missing and says so itself; what is tested here is whether
# it left the API behind, actionui_main being the last thing it defines.
_AUI_LINUX_WRAPPER=1
. "$_aui_linux_dir/actionui_remote.sh"
unset _AUI_LINUX_WRAPPER _aui_linux_dir
if ! declare -F actionui_main >/dev/null; then
    unset _AUI_AWK_UNQUOTE
    return 2 2>/dev/null || exit 2
fi

_AUI_SUN_PATH_LIMIT=107     # Linux sun_path, PROTOCOL.md section 1

# The transport, replacing the .sh's: send one request line and receive the reply, into
# _aui_reply. $1 is the line, $2 the id to wait for ("" for a batch). Returns 0, or
# ACTIONUI_EXIT_NO_HOST with _aui_error set.
#
# The request reaches nc on a pipe from printf, a builtin, so the token is never in an argv. nc
# prints what the host sends until the host closes, and timeout ends it (status 124) when the host
# does not. nc's own messages are not used: whether the socket file exists tells a missing host
# from a refused connection, as actionui_remote.zsh does. --foreground keeps timeout and nc in
# the script's process group: without it timeout moves to a group of its own, and a Ctrl-C (or a
# host signaling the handler's group) waits out the whole timeout before the script stops.
_aui_send_receive() {
    _aui_endpoint || return $?
    _aui_timeout
    local _aui_received _aui_line
    _aui_received=$(printf '%s\n' "$1" | /usr/bin/timeout --foreground "$_aui_to" /usr/bin/nc -N -U "$_aui_ep" 2>/dev/null)
    local _aui_status=$?
    _aui_reply=""
    if [ -n "$_aui_received" ]; then
        while IFS= read -r _aui_line; do
            _aui_reply_matches "$_aui_line" "$2"
            local _aui_match=$?
            if [ "$_aui_match" -eq 0 ]; then
                _aui_reply=$_aui_line
                return 0
            fi
            if [ "$_aui_match" -eq 2 ]; then
                _aui_error="malformed reply from host: $_aui_line"
                return "$ACTIONUI_EXIT_NO_HOST"
            fi
            # Not ours: a reply to nothing we sent, or a line from a later protocol version.
        done <<EOF
$_aui_received
EOF
    fi
    if [ "$_aui_status" -eq 124 ]; then
        _aui_error="no reply from $_aui_ep within $_aui_to s"
    elif [ ! -e "$_aui_ep" ]; then
        _aui_error="no ActionUI host is listening at $_aui_ep (No such file or directory)"
    elif [ "$_aui_status" -eq 0 ]; then
        _aui_error="the host at $_aui_ep closed the connection before replying"
    else
        _aui_error="no ActionUI host is listening at $_aui_ep (Connection refused)"
    fi
    return "$ACTIONUI_EXIT_NO_HOST"
}

# A raw JSON string literal to its text, into _aui_text, replacing the .sh's plutil version. A
# literal without escapes needs no process at all. The sentinel keeps $(...) from eating the
# text's own trailing newlines.
_aui_unquote() {
    _aui_text=$1
    _aui_text=${_aui_text#\"}
    _aui_text=${_aui_text%\"}
    case $_aui_text in
        *\\*)
            _aui_text=$(printf '%s\n' "$1" | LC_ALL=C /usr/bin/awk -f "$_AUI_AWK_UNQUOTE"; printf 'x')
            _aui_text=${_aui_text%x} ;;
    esac
    return 0
}

# The command line, when this file is run rather than sourced: bash sets BASH_SOURCE to this file
# and $0 to the caller's script when it is sourced.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    actionui_main "$@"
    exit $?
fi
