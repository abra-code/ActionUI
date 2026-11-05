"""The add-ons in libActionUI.so, seen from Python through its C functions only.

A program in another language cannot call an add-on's register(), so the library must register its add-ons itself.
The document shows RichText, CachedImage and Diff, which must draw, and QuickLook, which has no renderer on Linux: it
must log the warning the other three must not, which shows the warning would have been seen. The exit status is 0 when so.

Usage: python3 add_ons.py <libActionUI.so> <add_ons.json>
"""

import ctypes
import sys

WINDOW = b"add-ons"
RICH_TEXT = 2
MISSING = "is not available on Linux yet"

LOGGER = ctypes.CFUNCTYPE(None, ctypes.c_char_p, ctypes.c_int)
LIFECYCLE_HANDLER = ctypes.CFUNCTYPE(None)
TIMEOUT = ctypes.CFUNCTYPE(ctypes.c_int, ctypes.c_void_p)


def main():
    if len(sys.argv) != 3:
        print(__doc__.strip().splitlines()[-1], file=sys.stderr)
        return 2
    lib = ctypes.CDLL(sys.argv[1])
    glib = ctypes.CDLL("libglib-2.0.so.0")
    glib.g_timeout_add.argtypes = [ctypes.c_uint, TIMEOUT, ctypes.c_void_p]
    lib.actionUISetLogger.argtypes = [LOGGER]
    lib.actionUIAppSetName.argtypes = [ctypes.c_char_p]
    lib.actionUIAppSetApplicationID.argtypes = [ctypes.c_char_p]
    lib.actionUIAppSetDidFinishLaunchingHandler.argtypes = [LIFECYCLE_HANDLER]
    lib.actionUIAppLoadAndPresentWindow.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p]
    lib.actionUIGetElementStateString.argtypes = [ctypes.c_char_p, ctypes.c_int64, ctypes.c_char_p]
    lib.actionUIGetElementStateString.restype = ctypes.c_void_p
    lib.actionUIFreeString.argtypes = [ctypes.c_void_p]

    log = []
    states = {}

    def logged(message, level):
        log.append((message or b"").decode("utf-8", "replace"))

    def search_state(view_id):
        pointer = lib.actionUIGetElementStateString(WINDOW, view_id, b"search")
        if not pointer:
            return None
        text = ctypes.string_at(pointer).decode("utf-8")
        lib.actionUIFreeString(pointer)
        return text

    def stop(data):
        # ctypes swallows an exception raised in a callback, so without the finally the application would not end.
        try:
            states["rich text"] = search_state(RICH_TEXT)
        finally:
            lib.actionUIAppTerminate()
        return 0

    timeout = TIMEOUT(stop)

    def launched():
        # The window is built before this runs; the wait gives anything it does later the chance to log.
        glib.g_timeout_add(1000, timeout, None)

    # Kept alive for as long as the application runs: ctypes frees a callback with its object.
    logger = LOGGER(logged)
    handler = LIFECYCLE_HANDLER(launched)
    lib.actionUISetLogger(logger)
    lib.actionUIAppSetName(b"Add-ons (Python)")
    lib.actionUIAppSetApplicationID(b"com.abracode.actionui.AddOnsPython")
    lib.actionUIAppSetDidFinishLaunchingHandler(handler)
    lib.actionUIAppLoadAndPresentWindow(sys.argv[2].encode("utf-8"), WINDOW, b"Add-ons (Python)")
    lib.actionUIAppRun()

    missing = [line for line in log if MISSING in line]
    print("python: missing:", missing)
    print("python: search state:", states)
    failures = []
    if not any("QuickLook" in line for line in missing):
        failures.append("QuickLook logged no warning, so the log proves nothing")
    for name in ("RichText", "CachedImage", "Diff"):
        if any(name in line for line in missing):
            failures.append("%s is not registered" % name)
    if states.get("rich text") != "":
        failures.append("RichText's spec did not seed its search state: %r" % states.get("rich text"))
    for failure in failures:
        print("python:", failure)
    if not failures:
        print("python: add-ons registered")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
