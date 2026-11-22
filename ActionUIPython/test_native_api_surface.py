#!/usr/bin/env python3
"""
Comprehensive API surface test for the _actionui C extension.

Exercises every function in the module table to catch signature mismatches,
segfaults, and argument-order bugs without needing a live UI or NSApp run loop.

Run with: python3 test_native_api.py
"""

import _actionui
import json
import sys
import threading
import uuid


def test_callback_errors_are_reported_and_cleared():
    """An exception raised in a callback is printed and cleared, so later calls work; sys.exit()
    in a callback ends the process with its code. Before, the error indicator was left set: the
    exception was never shown and a later call failed with a SystemError."""
    import os
    import subprocess
    here = os.path.dirname(os.path.abspath(__file__))
    script = (
        "import sys\n"
        "sys.path.insert(0, sys.argv[1])\n"
        "import _actionui\n"
        "mode = sys.argv[2]\n"
        "def logger(message, level):\n"
        "    if mode == 'raise':\n"
        "        raise ValueError('boom from the logger')\n"
        "    sys.exit(7)\n"
        "_actionui.set_logger(logger)\n"
        "_actionui.get_string_value('no-such-window', 1, 0)\n"
        "print('second call returned', _actionui.get_version(), flush=True)\n"
    )
    raised = subprocess.run([sys.executable, "-c", script, here, "raise"], capture_output=True, text=True, timeout=60)
    assert raised.returncode == 0, raised.stdout + raised.stderr
    assert "ValueError: boom from the logger" in raised.stderr, raised.stderr
    assert "second call returned" in raised.stdout, raised.stdout + raised.stderr
    exited = subprocess.run([sys.executable, "-c", script, here, "exit"], capture_output=True, text=True, timeout=60)
    assert exited.returncode == 7, exited.stdout + exited.stderr
    assert "second call returned" not in exited.stdout
    print("  callback errors: reported and cleared; sys.exit() ends the process")


def test_module_constants():
    assert _actionui.LOG_ERROR == 1
    assert _actionui.LOG_WARNING == 2
    assert _actionui.LOG_INFO == 3
    assert _actionui.LOG_DEBUG == 4
    assert _actionui.LOG_VERBOSE == 5
    print("  module_constants: OK")


def test_version():
    v = _actionui.get_version()
    assert v is not None and isinstance(v, str) and len(v) > 0
    print(f"  get_version: '{v}'")


def test_logging():
    _actionui.set_logger(lambda msg, level: None)
    _actionui.log("test message", 2)
    _actionui.set_logger(None)
    print("  logging: OK")


def test_error_lifecycle():
    _actionui.clear_error()
    assert _actionui.get_last_error() is None
    print("  error_lifecycle: OK")


def test_action_handler_lifecycle():
    def handler(aid, wid, vid, vpid, ctx):
        pass
    before = sys.getrefcount(handler)
    for _ in range(10):
        _actionui.register_action_handler("test.action", handler)
    # The handler table holds one reference, however often the id is registered.
    assert sys.getrefcount(handler) == before + 1, (before, sys.getrefcount(handler))
    _actionui.unregister_action_handler("test.action")
    assert sys.getrefcount(handler) == before, (before, sys.getrefcount(handler))
    # An id that was never registered is no error (it used to raise SystemError).
    _actionui.unregister_action_handler("never.registered")
    _actionui.set_default_action_handler(handler)
    _actionui.set_default_action_handler(None)
    print("  action_handler_lifecycle: OK")


def test_app_calls():
    _actionui.app_load_menu_bar()
    _actionui.app_load_menu_bar("[]")
    _actionui.app_set_will_finish_launching(lambda: None)
    _actionui.app_set_did_finish_launching(lambda: None)
    _actionui.app_set_will_become_active(lambda: None)
    _actionui.app_set_did_become_active(lambda: None)
    _actionui.app_set_will_resign_active(lambda: None)
    _actionui.app_set_did_resign_active(lambda: None)
    _actionui.app_set_will_terminate(lambda: None)
    _actionui.app_set_should_terminate(lambda: True)
    _actionui.app_set_window_will_close(lambda w: None)
    _actionui.app_set_window_will_present(lambda w: None)
    _actionui.app_set_will_finish_launching(None)
    _actionui.app_set_did_finish_launching(None)
    _actionui.app_set_will_become_active(None)
    _actionui.app_set_did_become_active(None)
    _actionui.app_set_will_resign_active(None)
    _actionui.app_set_did_resign_active(None)
    _actionui.app_set_will_terminate(None)
    _actionui.app_set_should_terminate(None)
    _actionui.app_set_window_will_close(None)
    _actionui.app_set_window_will_present(None)
    print("  app_calls: OK")


def test_app_run_off_the_main_thread():
    # AppKit runs only on the main thread: from another thread app_run refuses at once.
    errors = []

    def run():
        try:
            _actionui.app_run()
        except RuntimeError as e:
            errors.append(str(e))

    thread = threading.Thread(target=run)
    thread.start()
    thread.join(10)
    assert not thread.is_alive(), "app_run on another thread did not return"
    assert errors and "main thread" in errors[0], errors
    print("  app_run_off_the_main_thread: OK")


def test_type_specific_setters_and_getters(uuid_str):
    vid = 1
    vpid = 0

    r = _actionui.set_int_value(uuid_str, vid, vpid, 42)
    assert r is True, f"set_int_value returned {r}"
    _actionui.set_int_value(uuid_str, vid, vpid, -7)
    r = _actionui.set_double_value(uuid_str, vid, vpid, 3.14)
    assert r is True
    r = _actionui.set_bool_value(uuid_str, vid, vpid, True)
    assert r is True
    r = _actionui.set_bool_value(uuid_str, vid, vpid, False)
    assert r is True
    r = _actionui.set_string_value(uuid_str, vid, vpid, "hello world")
    assert r is True
    r = _actionui.set_string_value(uuid_str, vid, vpid, "")
    assert r is True

    # Getters return None without a loaded UI.
    assert _actionui.get_int_value(uuid_str, vid, vpid) is None
    assert _actionui.get_double_value(uuid_str, vid, vpid) is None
    assert _actionui.get_bool_value(uuid_str, vid, vpid) is None
    assert _actionui.get_string_value(uuid_str, vid, vpid) is None
    print("  type_specific_setters_and_getters: OK")


def test_view_part_id_isolation(uuid_str):
    vid = 2
    for vpid in (0, 1, 2):
        r = _actionui.set_int_value(uuid_str, vid, vpid, 100 + vpid)
        assert r is True
    print("  view_part_id_isolation: OK")


def test_default_view_part_id(uuid_str):
    vid = 3
    r = _actionui.set_int_value(uuid_str, vid, 0, 999)
    assert r is True
    print("  default_view_part_id: OK")


def test_string_boundary_cases(uuid_str):
    vid = 4
    vpid = 0
    for s in ("", "a", "x" * 1000):
        r = _actionui.set_string_value(uuid_str, vid, vpid, s)
        assert r is True
    print("  string_boundary_cases: OK")


def test_value_from_string(uuid_str):
    vid = 5
    vpid = 0

    r = _actionui.set_value_from_string(uuid_str, vid, vpid, "plain text")
    assert r is True
    r = _actionui.set_value_from_string(uuid_str, vid, vpid, "**bold**", "markdown")
    assert r is True
    r = _actionui.set_value_from_string(uuid_str, vid, vpid, "another value")
    assert r is True
    print("  set_value_from_string: OK")


def test_value_from_json(uuid_str):
    vid = 6
    vpid = 0

    r = _actionui.set_value_from_json(uuid_str, vid, vpid, json.dumps({"k": "v"}))
    assert r is True
    r = _actionui.set_value_from_json(uuid_str, vid, vpid, "{}")
    assert r is True
    r = _actionui.set_value_from_json(uuid_str, vid, vpid, "[]")
    assert r is True
    print("  value_from_json: OK")


def test_element_column_count(uuid_str):
    vid = 10
    r = _actionui.get_element_column_count(uuid_str, vid)
    assert isinstance(r, int)
    print("  element_column_count: OK")


def test_element_rows(uuid_str):
    vid = 11
    rows = [["A", "B"], ["C", "D"]]
    r = _actionui.set_element_rows_json(uuid_str, vid, json.dumps(rows))
    assert r is True
    r = _actionui.append_element_rows_json(uuid_str, vid, json.dumps([["E", "F"]]))
    assert r is True
    r = _actionui.append_element_text(uuid_str, vid, "x")
    assert r is True
    _actionui.clear_element_rows(uuid_str, vid)
    print("  element_rows: OK")


def test_element_property(uuid_str):
    vid = 12
    r = _actionui.set_element_property_json(uuid_str, vid, "hidden", json.dumps(True))
    assert r is True
    print("  element_property: OK")


def test_element_state(uuid_str):
    vid = 13
    key = "counter"
    r = _actionui.set_element_state_json(uuid_str, vid, key, json.dumps(0))
    assert r is True
    r = _actionui.set_element_state_from_string(uuid_str, vid, key, "42")
    assert r is True
    print("  element_state: OK")


def test_element_info(uuid_str):
    v = _actionui.get_element_info_json(uuid_str)
    assert v is None or isinstance(json.loads(v), dict)
    print("  element_info: OK")


def test_trust_policy_calls(uuid_str):
    assert _actionui.get_element_origin_json(uuid_str, 1) is None   # no such element
    assert _actionui.get_element_origin_json("no-such-window", 1) is None
    for bad in (("not callable", None), (None, 42)):
        try:
            _actionui.set_trust_policy(*bad)
            raise AssertionError("set_trust_policy accepted %r" % (bad,))
        except TypeError:
            pass
    _actionui.set_trust_policy(lambda s, p, d: d, lambda c, o, d: d)
    errors = []
    def off_main():
        try:
            _actionui.set_trust_policy(None, None)
            errors.append("set_trust_policy ran off the main thread")
        except RuntimeError:
            pass
    thread = threading.Thread(target=off_main)
    thread.start()
    thread.join()
    assert not errors, errors
    _actionui.set_trust_policy(None, None)   # ActionUI's own policy again
    print("  trust_policy: OK")


def test_configuration_calls():
    import json
    current = json.loads(_actionui.get_configuration_json())
    assert set(current) == {"limits", "trust", "resourceFolder", "addOns"}, current
    for bad in [(), (1,), (None,), ("{}", "{}")]:
        try:
            _actionui.set_configuration_json(*bad)
            raise AssertionError("set_configuration_json accepted %r" % (bad,))
        except TypeError:
            pass
    for text, expected in [("{limits", "not valid JSON"), ('{"limit": {}}', "unknown configuration key limit")]:
        try:
            _actionui.set_configuration_json(text)
            raise AssertionError("set_configuration_json accepted %r" % text)
        except RuntimeError as error:
            # Refused for the key, or (when an earlier call loaded a window) because it is fixed.
            assert expected in str(error) or "fixed" in str(error), str(error)
    assert json.loads(_actionui.get_configuration_json()) == current, "a refusal changes nothing"
    print("  configuration: OK")


def test_remove_window(uuid_str):
    assert _actionui.remove_window(uuid_str) is None
    assert _actionui.remove_window(uuid_str) is None   # unknown window is ignored
    v = _actionui.get_element_info_json(uuid_str)
    assert v is None or json.loads(v) == {}
    print("  remove_window: OK")


def test_noop_calls(uuid_str):
    vid = 99
    vpid = 0
    _actionui.set_int_value(uuid_str, vid, vpid, 1)
    _actionui.set_double_value(uuid_str, vid, vpid, 1.0)
    _actionui.set_bool_value(uuid_str, vid, vpid, True)
    _actionui.set_string_value(uuid_str, vid, vpid, "x")
    _actionui.set_value_from_string(uuid_str, vid, vpid, "x")
    _actionui.set_value_from_json(uuid_str, vid, vpid, "{}")
    _actionui.set_element_rows_json(uuid_str, vid, "[]")
    _actionui.append_element_rows_json(uuid_str, vid, "[]")
    _actionui.append_element_text(uuid_str, vid, "x")
    _actionui.clear_element_rows(uuid_str, vid)
    _actionui.set_element_property_json(uuid_str, vid, "x", "{}")
    _actionui.set_element_state_json(uuid_str, vid, "x", "{}")
    _actionui.set_element_state_from_string(uuid_str, vid, "x", "x")
    assert _actionui.get_int_value(uuid_str, vid, vpid) is None
    assert _actionui.get_double_value(uuid_str, vid, vpid) is None
    assert _actionui.get_bool_value(uuid_str, vid, vpid) is None
    assert _actionui.get_string_value(uuid_str, vid, vpid) is None
    assert _actionui.get_value_as_string(uuid_str, vid, vpid) is None
    assert _actionui.get_value_as_json(uuid_str, vid, vpid) is None
    assert _actionui.get_element_rows_json(uuid_str, vid) is None
    assert _actionui.get_element_column_count(uuid_str, vid) == 0
    assert _actionui.get_element_property_json(uuid_str, vid, "x") is None
    assert _actionui.get_element_state_json(uuid_str, vid, "x") is None
    assert _actionui.get_element_state_string(uuid_str, vid, "x") is None
    print("  noop_calls: OK")


def test_modal_noop(uuid_str):
    for fn in [
        lambda: _actionui.present_modal(uuid_str, "{}", "json", "sheet", None),
        lambda: _actionui.dismiss_modal(uuid_str),
        lambda: _actionui.present_alert(uuid_str, "title", "message", None),
        lambda: _actionui.present_confirmation_dialog(uuid_str, "title", "message", "[]"),
        lambda: _actionui.dismiss_dialog(uuid_str),
    ]:
        try:
            fn()
        except RuntimeError:
            pass
    print("  modal_noop: OK")


def test_content_size_limits_unknown_window():
    # On every platform; an unknown window has no limits, which the C function reports as an error.
    try:
        _actionui.get_content_size_limits(str(uuid.uuid4()))
        raise AssertionError("get_content_size_limits must raise for an unknown window")
    except RuntimeError as error:
        assert "Unknown windowUUID" in str(error), str(error)
    print("  get_content_size_limits: OK")


def test_load_hosting_controller(uuid_str):
    ptr = _actionui.load_hosting_controller("file:///nonexistent/path.json", uuid_str, True)
    assert ptr is not None
    print("  load_hosting_controller: OK")


def main():
    print("ActionUI _actionui C Extension — API Surface Test")
    print("=" * 55)

    test_module_constants()
    test_version()
    test_logging()
    test_error_lifecycle()
    test_action_handler_lifecycle()
    test_app_calls()
    test_app_run_off_the_main_thread()
    test_callback_errors_are_reported_and_cleared()
    test_configuration_calls()

    test_uuid = str(uuid.uuid4())

    test_type_specific_setters_and_getters(test_uuid)
    test_view_part_id_isolation(test_uuid)
    test_default_view_part_id(test_uuid)
    test_string_boundary_cases(test_uuid)
    test_value_from_string(test_uuid)
    test_value_from_json(test_uuid)
    test_element_column_count(test_uuid)
    test_element_rows(test_uuid)
    test_element_property(test_uuid)
    test_element_state(test_uuid)
    test_element_info(test_uuid)
    test_trust_policy_calls(test_uuid)
    test_remove_window(test_uuid)
    test_noop_calls(test_uuid)
    test_modal_noop(test_uuid)
    test_content_size_limits_unknown_window()
    # Apple only: the Linux library hands out no native view.
    if sys.platform == "darwin":
        test_load_hosting_controller(test_uuid)

    print()
    print("All API surface tests passed.")


if __name__ == "__main__":
    main()