#!/usr/bin/env python3
"""
Comprehensive API surface test for the _actionui C extension.

Exercises every function in the module table to catch signature mismatches,
segfaults, and argument-order bugs without needing a live UI or NSApp run loop.

Run with: python3 test_native_api.py
"""

import _actionui
import json
import uuid


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
    _actionui.register_action_handler("test.action", handler)
    _actionui.unregister_action_handler("test.action")
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
    test_noop_calls(test_uuid)
    test_modal_noop(test_uuid)
    test_load_hosting_controller(test_uuid)

    print()
    print("All API surface tests passed.")


if __name__ == "__main__":
    main()