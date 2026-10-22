"""TemperatureConverter on Linux, hosted from Python through ActionUI's C functions only.

The same C names and signatures as ActionUI's C adapter and application functions on macOS
(actionUIRegisterActionHandler, actionUIGetStringValue, actionUIAppRun, ...), called with ctypes
from libActionUI.so.

With --check, the host sets the inputs itself once the window is up, converts four temperatures,
compares each result with the one expected, prints them and quits; the exit status is 0 when all
four match.

Usage: python3 temperature_converter.py <libActionUI.so> <TemperatureConverter.json> [--check]
"""

import ctypes
import sys

WINDOW = b"temperature-converter"
FIELD, SOURCE, TARGET, RESULT = 10, 20, 30, 40

# (value, source unit, target unit, the result expected). C and F are the pickers' first options,
# and recompute falls back to them, so only a check from F or K shows that the source picker was
# set, and only one to C or K that the target picker was.
CHECKS = [
    ("100", "C", "F", "212.00"),
    ("37", "C", "F", "98.60"),
    ("-40", "C", "F", "-40.00"),
    ("212", "F", "K", "373.15"),
]

ACTION_HANDLER = ctypes.CFUNCTYPE(None, ctypes.c_char_p, ctypes.c_char_p,
                                  ctypes.c_int64, ctypes.c_int64, ctypes.c_char_p)
LIFECYCLE_HANDLER = ctypes.CFUNCTYPE(None)


def load(library_path):
    lib = ctypes.CDLL(library_path)
    lib.actionUIRegisterActionHandler.argtypes = [ctypes.c_char_p, ACTION_HANDLER]
    lib.actionUIRegisterActionHandler.restype = ctypes.c_bool
    lib.actionUIGetStringValue.argtypes = [ctypes.c_char_p, ctypes.c_int64, ctypes.c_int64]
    lib.actionUIGetStringValue.restype = ctypes.c_void_p
    lib.actionUISetStringValue.argtypes = [ctypes.c_char_p, ctypes.c_int64, ctypes.c_int64, ctypes.c_char_p]
    lib.actionUISetStringValue.restype = ctypes.c_bool
    lib.actionUIFreeString.argtypes = [ctypes.c_void_p]
    lib.actionUIGetVersion.restype = ctypes.c_void_p
    lib.actionUIAppSetName.argtypes = [ctypes.c_char_p]
    lib.actionUIAppSetApplicationID.argtypes = [ctypes.c_char_p]
    lib.actionUIAppSetDidFinishLaunchingHandler.argtypes = [LIFECYCLE_HANDLER]
    lib.actionUIAppLoadAndPresentWindow.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p]
    return lib


def take_string(lib, pointer):
    if not pointer:
        return None
    text = ctypes.string_at(pointer).decode("utf-8")
    lib.actionUIFreeString(pointer)
    return text


def convert(value, source, target):
    """Through Celsius as the common pivot."""
    celsius = (value - 32) * 5 / 9 if source == "F" else value - 273.15 if source == "K" else value
    return celsius * 9 / 5 + 32 if target == "F" else celsius + 273.15 if target == "K" else celsius


def main():
    arguments = sys.argv[1:]
    check = "--check" in arguments
    arguments = [argument for argument in arguments if argument != "--check"]
    if len(arguments) != 2:
        print(__doc__.strip().splitlines()[-1], file=sys.stderr)
        return 2
    lib = load(arguments[0])
    print("ActionUI", take_string(lib, lib.actionUIGetVersion()), "from Python")

    def get(view_id):
        return take_string(lib, lib.actionUIGetStringValue(WINDOW, view_id, 0))

    def set_value(view_id, text):
        lib.actionUISetStringValue(WINDOW, view_id, 0, text.encode("utf-8"))

    def recompute(action_id=b"", window_uuid=b"", view_id=0, view_part_id=0, context=None):
        raw = get(FIELD) or ""
        source = get(SOURCE) or "C"
        target = get(TARGET) or "F"
        try:
            value = float(raw.strip())
        except ValueError:
            set_value(RESULT, "")
            return
        set_value(RESULT, "%.2f" % convert(value, source, target))

    passed = []

    def run_checks():
        # ctypes swallows an exception raised in a callback (it prints it and returns), so without
        # the finally the application would never be told to end.
        try:
            for value, source, target, expected in CHECKS:
                set_value(FIELD, value)
                set_value(SOURCE, source)
                set_value(TARGET, target)
                recompute()
                result = get(RESULT)
                mark = "ok" if result == expected else "MISMATCH, expected %s" % expected
                print("python: %s %s = %s %s (%s)" % (value, source, result, target, mark))
                if result == expected:
                    passed.append(value)
        finally:
            lib.actionUIAppTerminate()

    # Kept alive for as long as the application runs: ctypes frees a callback with its object.
    handler = ACTION_HANDLER(recompute)
    launched = LIFECYCLE_HANDLER(run_checks)
    lib.actionUIRegisterActionHandler(b"temp.recompute", handler)
    lib.actionUIAppSetName(b"Temperature Converter (Python)")
    lib.actionUIAppSetApplicationID(b"com.abracode.actionui.TemperatureConverterPython")
    if check:
        lib.actionUIAppSetDidFinishLaunchingHandler(launched)
    lib.actionUIAppLoadAndPresentWindow(arguments[1].encode("utf-8"), WINDOW, b"Temperature Converter (Python)")
    lib.actionUIAppRun()
    if check:
        print("python: %d of %d conversions as expected" % (len(passed), len(CHECKS)))
        return 0 if len(passed) == len(CHECKS) else 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
