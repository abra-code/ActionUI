"""actionui_remote_windows - the named-pipe transport of actionui_remote on Windows.

actionui_remote loads this file from its own folder on Windows (never from sys.path, so a module
of this name in the current folder cannot stand in for it). It gives the client what a Unix socket
gives it elsewhere, with the checks PROTOCOL.md section 12 asks of a client before it sends a token:

- The endpoint must be a local pipe name, `\\\\.\\pipe\\` and then letters, digits, '.', '-' or '_'
  (not ending in '.'). Another computer's name (`\\\\host\\pipe\\...`) is refused before anything
  is opened: opening it would send the token, and the user's sign-in, over the network.
- The pipe is opened for identification only (SECURITY_SQOS_PRESENT | SECURITY_IDENTIFICATION), so
  the server may read who the client is but not act as it.
- The pipe's owner must be this user (GetSecurityInfo): a pipe somebody else made after the server
  ended gets nothing.

Pure standard library (ctypes), no threads. The handle is synchronous; a read waits for bytes with
PeekNamedPipe, so it can give up after the connection's timeout as a socket read does.
"""

import ctypes
import os
import socket
import time
from ctypes import wintypes

PIPE_PREFIX = "\\\\.\\pipe\\"
MAX_PIPE_NAME = 256

_GENERIC_READ = 0x80000000
_GENERIC_WRITE = 0x40000000
_OPEN_EXISTING = 3
_SECURITY_SQOS_PRESENT = 0x00100000
_SECURITY_IDENTIFICATION = 1 << 16          # SecurityIdentification << 16
_INVALID_HANDLE_VALUE = ctypes.c_void_p(-1).value
_ERROR_FILE_NOT_FOUND = 2
_ERROR_ACCESS_DENIED = 5
_ERROR_BROKEN_PIPE = 109
_ERROR_PIPE_BUSY = 231
_ERROR_NO_DATA = 232
_ERROR_PIPE_NOT_CONNECTED = 233
_SE_KERNEL_OBJECT = 6
_OWNER_SECURITY_INFORMATION = 1
_TOKEN_QUERY = 0x0008
_TOKEN_USER = 1

_kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
_advapi32 = ctypes.WinDLL("advapi32", use_last_error=True)

_CreateFileW = _kernel32.CreateFileW
_CreateFileW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD, wintypes.DWORD, wintypes.LPVOID, wintypes.DWORD,
                         wintypes.DWORD, wintypes.HANDLE]
_CreateFileW.restype = wintypes.HANDLE
_WaitNamedPipeW = _kernel32.WaitNamedPipeW
_WaitNamedPipeW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD]
_WaitNamedPipeW.restype = wintypes.BOOL
_PeekNamedPipe = _kernel32.PeekNamedPipe
_PeekNamedPipe.argtypes = [wintypes.HANDLE, wintypes.LPVOID, wintypes.DWORD, ctypes.POINTER(wintypes.DWORD),
                           ctypes.POINTER(wintypes.DWORD), ctypes.POINTER(wintypes.DWORD)]
_PeekNamedPipe.restype = wintypes.BOOL
_ReadFile = _kernel32.ReadFile
_ReadFile.argtypes = [wintypes.HANDLE, wintypes.LPVOID, wintypes.DWORD, ctypes.POINTER(wintypes.DWORD), wintypes.LPVOID]
_ReadFile.restype = wintypes.BOOL
_WriteFile = _kernel32.WriteFile
_WriteFile.argtypes = [wintypes.HANDLE, wintypes.LPCVOID, wintypes.DWORD, ctypes.POINTER(wintypes.DWORD), wintypes.LPVOID]
_WriteFile.restype = wintypes.BOOL
_CloseHandle = _kernel32.CloseHandle
_CloseHandle.argtypes = [wintypes.HANDLE]
_CloseHandle.restype = wintypes.BOOL
_LocalFree = _kernel32.LocalFree
_LocalFree.argtypes = [wintypes.HLOCAL]
_LocalFree.restype = wintypes.HLOCAL
_GetCurrentProcess = _kernel32.GetCurrentProcess
_GetCurrentProcess.argtypes = []
_GetCurrentProcess.restype = wintypes.HANDLE
_OpenProcessToken = _advapi32.OpenProcessToken
_OpenProcessToken.argtypes = [wintypes.HANDLE, wintypes.DWORD, ctypes.POINTER(wintypes.HANDLE)]
_OpenProcessToken.restype = wintypes.BOOL
_GetTokenInformation = _advapi32.GetTokenInformation
_GetTokenInformation.argtypes = [wintypes.HANDLE, ctypes.c_int, wintypes.LPVOID, wintypes.DWORD,
                                 ctypes.POINTER(wintypes.DWORD)]
_GetTokenInformation.restype = wintypes.BOOL
_GetSecurityInfo = _advapi32.GetSecurityInfo
_GetSecurityInfo.argtypes = [wintypes.HANDLE, ctypes.c_int, wintypes.DWORD, ctypes.POINTER(wintypes.LPVOID),
                             ctypes.POINTER(wintypes.LPVOID), ctypes.POINTER(wintypes.LPVOID),
                             ctypes.POINTER(wintypes.LPVOID), ctypes.POINTER(wintypes.LPVOID)]
_GetSecurityInfo.restype = wintypes.DWORD
_EqualSid = _advapi32.EqualSid
_EqualSid.argtypes = [wintypes.LPVOID, wintypes.LPVOID]
_EqualSid.restype = wintypes.BOOL
_ConvertSidToStringSidW = _advapi32.ConvertSidToStringSidW
_ConvertSidToStringSidW.argtypes = [wintypes.LPVOID, ctypes.POINTER(wintypes.LPWSTR)]
_ConvertSidToStringSidW.restype = wintypes.BOOL


def _is_name_character(character):
    return character.isascii() and (character.isalnum() or character in ".-_")


def check_endpoint(name, error_type):
    """Raises `error_type` unless `name` is a local pipe name this client may send a token to."""
    if not isinstance(name, str) or len(name) <= len(PIPE_PREFIX) or len(name) > MAX_PIPE_NAME \
            or name[:len(PIPE_PREFIX)].lower() != PIPE_PREFIX:
        raise error_type("not a local pipe name (\\\\.\\pipe\\...): %s" % name)
    rest = name[len(PIPE_PREFIX):]
    if not all(_is_name_character(character) for character in rest) or rest.endswith("."):
        raise error_type("not a local pipe name (letters, digits, '.', '-' or '_' after \\\\.\\pipe\\, "
                         "not ending in '.'): %s" % name)


def _sid_text(sid):
    text = wintypes.LPWSTR()
    if not _ConvertSidToStringSidW(sid, ctypes.byref(text)):
        return "unknown"
    try:
        return text.value
    finally:
        _LocalFree(ctypes.cast(text, wintypes.HLOCAL))


class _TokenUser(ctypes.Structure):
    _fields_ = [("sid", wintypes.LPVOID), ("attributes", wintypes.DWORD)]


def _my_user_sid():
    """This process's user SID, in a buffer that keeps it alive, and the SID's address in it."""
    token = wintypes.HANDLE()
    if not _OpenProcessToken(_GetCurrentProcess(), _TOKEN_QUERY, ctypes.byref(token)):
        raise OSError(ctypes.get_last_error(), "OpenProcessToken failed")
    try:
        size = wintypes.DWORD(0)
        _GetTokenInformation(token, _TOKEN_USER, None, 0, ctypes.byref(size))
        buffer = ctypes.create_string_buffer(size.value)
        if not _GetTokenInformation(token, _TOKEN_USER, buffer, size, ctypes.byref(size)):
            raise OSError(ctypes.get_last_error(), "GetTokenInformation failed")
        return buffer, ctypes.cast(buffer, ctypes.POINTER(_TokenUser)).contents.sid
    finally:
        _CloseHandle(token)


def _check_owner(handle, name, error_type):
    """Raises `error_type` unless the pipe behind `handle` is owned by this process's user."""
    owner = wintypes.LPVOID()
    descriptor = wintypes.LPVOID()
    code = _GetSecurityInfo(handle, _SE_KERNEL_OBJECT, _OWNER_SECURITY_INFORMATION, ctypes.byref(owner),
                            None, None, None, ctypes.byref(descriptor))
    if code != 0:
        raise error_type("cannot read the owner of %s (Windows error %d)" % (name, code))
    try:
        keep_alive, mine = _my_user_sid()
        if not _EqualSid(owner, mine):
            raise error_type("%s belongs to another account (%s), not this user (%s)"
                             % (name, _sid_text(owner), _sid_text(mine)))
        del keep_alive
    finally:
        _LocalFree(descriptor)


class PipeConnection:
    """A client end of a pipe with the parts of a socket that actionui_remote.Connection uses:
    sendall, recv (raising socket.timeout after the timeout), settimeout and close."""

    def __init__(self, handle, timeout):
        self._handle = handle
        self._timeout = timeout

    def settimeout(self, timeout):
        self._timeout = timeout

    def close(self):
        handle, self._handle = self._handle, None
        if handle is not None:
            _CloseHandle(handle)

    def _closed_error(self, code):
        if code in (_ERROR_BROKEN_PIPE, _ERROR_NO_DATA, _ERROR_PIPE_NOT_CONNECTED):
            return BrokenPipeError(code, "the host closed the pipe")
        return OSError(code, "Windows error %d" % code)

    def sendall(self, data):
        if self._handle is None:
            raise BrokenPipeError("the pipe is closed")
        view = memoryview(data)
        while view:
            written = wintypes.DWORD(0)
            chunk = bytes(view[:1 << 20])
            if not _WriteFile(self._handle, chunk, len(chunk), ctypes.byref(written), None):
                raise self._closed_error(ctypes.get_last_error())
            view = view[written.value:]

    def recv(self, size):
        """Up to `size` bytes; b"" when the host has closed its end."""
        if self._handle is None:
            return b""
        deadline = None if self._timeout is None else time.monotonic() + self._timeout
        pause = 0.001
        while True:
            available = wintypes.DWORD(0)
            if not _PeekNamedPipe(self._handle, None, 0, None, ctypes.byref(available), None):
                code = ctypes.get_last_error()
                if code in (_ERROR_BROKEN_PIPE, _ERROR_PIPE_NOT_CONNECTED):
                    return b""
                raise self._closed_error(code)
            if available.value:
                count = min(size, available.value)
                buffer = ctypes.create_string_buffer(count)
                read = wintypes.DWORD(0)
                if not _ReadFile(self._handle, buffer, count, ctypes.byref(read), None):
                    code = ctypes.get_last_error()
                    if code in (_ERROR_BROKEN_PIPE, _ERROR_PIPE_NOT_CONNECTED):
                        return b""
                    raise self._closed_error(code)
                return buffer.raw[:read.value]
            if deadline is not None and time.monotonic() >= deadline:
                raise socket.timeout("timed out")
            time.sleep(pause)
            pause = min(pause * 2, 0.02)


def open_pipe(name, timeout, error_type):
    """Opens the pipe `name` for identification only and checks its owner. Raises `error_type` when
    no host listens there, or the pipe is not this user's."""
    check_endpoint(name, error_type)
    deadline = time.monotonic() + (timeout if timeout is not None else 60.0)
    while True:
        handle = _CreateFileW(name, _GENERIC_READ | _GENERIC_WRITE, 0, None, _OPEN_EXISTING,
                              _SECURITY_SQOS_PRESENT | _SECURITY_IDENTIFICATION, None)
        if handle is not None and handle != _INVALID_HANDLE_VALUE:
            break
        code = ctypes.get_last_error()
        if code == _ERROR_FILE_NOT_FOUND:
            raise error_type("no ActionUI host is listening at %s" % name)
        if code == _ERROR_ACCESS_DENIED:
            raise error_type("%s refused this process (access denied: another user's pipe, or this "
                             "process runs below the host's integrity level)" % name)
        if code != _ERROR_PIPE_BUSY:
            raise error_type("cannot open %s (Windows error %d)" % (name, code))
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise error_type("%s stayed busy for %.1f s" % (name, timeout or 60.0))
        # At least 1 ms: 0 would mean the server's default wait, not none.
        _WaitNamedPipeW(name, max(1, int(min(remaining, 1.0) * 1000)))
    try:
        _check_owner(handle, name, error_type)
    except BaseException:
        _CloseHandle(handle)
        raise
    return PipeConnection(handle, timeout)
