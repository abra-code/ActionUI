"""test_live_client - drives actionui_remote against a real ActionUI host.

Run by ActionUIRemoteTests/PythonClientIntegrationTests.swift, which loads a headless window,
starts a real ActionUIRemoteServer on it, and then runs:

    python3 test_live_client.py <socket path> <window uuid> [expected host name]

Exits 0 when every check passed and 1 otherwise, printing one line per failure. The two
variables of the environment contract are set by the caller as well, and checked here.

test_actionui_remote.py covers the client against the in-memory fake; this script is where a
disagreement between that fake and the engine would show up, so it leans on the values only the
engine produces: a DatePicker holds a Date and has no JSON form, a Table's column count comes
from its columns property while it is empty and from its content rows once it has any, a
TextField refuses to be a container, a relative modal path is refused without a host resolver,
and a getter inside a batch sees the setter before it.

The window it drives is the fixture of ActionUIRemoteServerTests: VStack 10 containing TextField
2, Toggle 3, Table 5 (columns A and B), DatePicker 6, Grid 7 (holding Text 70), and Text 11.

It deliberately leaves state behind for the Swift test to re-read through ActionUIModel:

    element 2      value "final text", state "count" == 7 (Int)
    element 3      value True, property "disabled" == True
    element 5      rows [["x1", "y1"], ["x2", "y2"]]
    element 300    removed again after being inserted
    element 301    a Text inserted into VStack 10
    elements 310, 311   a row inserted into Grid 7
    the window     a toast reading "done from python", no modal and no dialog
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import actionui_remote as aui         # noqa: E402


FAILURES = []
CHECKS = [0]


def check(condition, description):
    CHECKS[0] += 1
    if not condition:
        FAILURES.append(description)


def check_equal(actual, expected, description):
    CHECKS[0] += 1
    if actual != expected:
        FAILURES.append("%s: expected %r, got %r" % (description, expected, actual))


def check_raises(code, description, function, *args, **kwargs):
    CHECKS[0] += 1
    try:
        result = function(*args, **kwargs)
    except aui.RemoteError as error:
        if error.code != code:
            FAILURES.append("%s: expected code %d, got %d (%s)" % (description, code, error.code, error.message))
        return
    except Exception as error:                                  # noqa: BLE001 - reported, not swallowed
        FAILURES.append("%s: expected RemoteError %d, raised %r" % (description, code, error))
        return
    FAILURES.append("%s: expected RemoteError %d, returned %r" % (description, code, result))


def check_discovery(win, uuid, expected_host):
    info = aui.hello(win.connection.endpoint)
    check_equal(info["protocolVersion"], 1, "hello.protocolVersion")
    check(uuid in info["windows"], "hello.windows must list the window under test")
    if expected_host is not None:
        # Proves this reached the host that started us, not another one left on a stale endpoint.
        check_equal(info["host"]["name"], expected_host, "hello.host.name")
    for name in ("actionui.hello", "actionui.getValue", "actionui.setRows",
                 "actionui.insertElement", "actionui.presentToast", "actionui.contentSizeLimits"):
        check(name in info["methods"], "hello.methods must list %s" % name)
    check_equal(info["methods"], sorted(info["methods"]), "hello.methods must be sorted")

    raw = win.connection.call("actionui.getElementInfo", {"window": uuid})
    check(all(isinstance(key, str) for key in raw),
          "getElementInfo ids cross the wire as strings, got %r" % (sorted(raw)[:3],))
    elements = win.get_element_info()
    check_equal(sorted(elements), sorted(int(key) for key in raw),
                "the client turns every wire id into an integer")
    for view_id, element_type in ((2, "TextField"), (3, "Toggle"), (5, "Table"),
                                  (6, "DatePicker"), (7, "Grid"), (10, "VStack"), (11, "Text")):
        check_equal(elements.get(view_id), element_type, "element %d type" % view_id)

    # A loaded root always has limits; null is for an unknown window or a window with no root.
    limits = win.content_size_limits()
    check(isinstance(limits, tuple) and len(limits) == 4
          and all(isinstance(number, (int, float)) for number in limits),
          "content_size_limits must be a 4-tuple of numbers, got %r" % (limits,))
    if isinstance(limits, tuple) and len(limits) == 4:
        check(limits[0] <= limits[2] and limits[1] <= limits[3],
              "content_size_limits must have min <= max, got %r" % (limits,))


def check_values(win):
    check_equal(win.set_value(2, 0, "Ada"), True, "set_value returns true")
    check_equal(win.get_value(2), "Ada", "get_value after set_value")
    check_equal(win.get_string(2), "Ada", "get_string after set_value")

    check_equal(win.set_bool(3, True), True, "set_bool")
    check_equal(win.get_bool(3), True, "get_bool")

    win.set_string(2, "42")
    check_equal(win.get_int(2), 42, "get_int coerces the wire value")
    check_equal(win.get_double(2), 42.0, "get_double coerces the wire value")

    # A DatePicker holds a Date: no JSON form, so the value is null and the string path works.
    check_equal(win.set_string(6, "2026-09-02T10:00:00Z"), True, "set_string on a DatePicker")
    check_equal(win.get_value(6), None, "a Date has no JSON form, so get_value is None")
    date_text = win.get_string(6)
    check(isinstance(date_text, str) and date_text.startswith("2026-09-02"),
          "get_string on a DatePicker must be ISO 8601, got %r" % (date_text,))

    check_equal(win.set_string(11, "# Hi", content_type="markdown"), True, "set_string with a content type")
    plain = win.get_string(11, content_type="plain")
    check(isinstance(plain, str) and "Hi" in plain, "markdown round trip, got %r" % (plain,))


def check_properties_and_state(win):
    check_equal(win.set_enabled(2, False), True, "set_enabled")
    check_equal(win.get_property(2, "disabled"), True, "disabled property after set_enabled(False)")
    check_equal(win.set_enabled(2, True), True, "set_enabled back")
    check_equal(win.get_property(2, "disabled"), False, "disabled property after set_enabled(True)")

    check_equal(win.set_state(2, "count", 1), True, "set_state creates a key")
    check_equal(win.get_state(2, "count"), 1, "get_state")
    check_equal(win.get_state_string(2, "count"), "1", "get_state_string")
    check_equal(win.get_state(2, "absent"), None, "get_state of an unset key")
    check_raises(1003, "set_state with a mismatched type", win.set_state, 2, "count", "not a number")
    check_equal(win.set_state_from_string(2, "count", "5"), True, "set_state_from_string")
    check_equal(win.get_state(2, "count"), 5, "set_state_from_string parses toward the stored type")

    # The engine seeds states with Swift-native values while the wire carries NSNumber; a whole
    # JSON number must land in a Double state rather than report a spurious mismatch.
    check_equal(win.set_state(2, "ratio", 0.5), True, "set_state creates a Double state")
    check_equal(win.set_state(2, "ratio", 2), True, "a whole number is accepted by a Double state")
    check_equal(win.get_state(2, "ratio"), 2.0, "the Double state took the new value")
    # 2.0 crosses the wire as 2 and decodes as an int, so only the string getter can tell a
    # Double state that kept its type from one the engine quietly turned into an Int.
    check_equal(win.get_state_string(2, "ratio"), "2.0", "the Double state kept its type")


def check_rows(win):
    # getElementColumnCount reads the columns property only while there is no content, and the
    # content rows once there is, so the property path has to be checked before anything is set.
    check_equal(win.get_column_count(5), 2, "get_column_count comes from the columns property when empty")

    check_equal(win.set_rows(5, [["a1", "b1"], ["a2", "b2"]]), True, "set_rows")
    check_equal(win.get_rows(5), [["a1", "b1"], ["a2", "b2"]], "get_rows")
    check_equal(win.get_column_count(5), 2, "get_column_count comes from the content rows")
    check_equal(win.append_rows(5, [["a3", "b3"]]), True, "append_rows")
    check_equal(len(win.get_rows(5)), 3, "row count after append_rows")

    check_equal(win.select_row(5, 1), ["a2", "b2"], "select_row returns the row")
    check_equal(win.get_value(5), ["a2", "b2"], "the selected row is the Table's value")
    check_equal(win.get_value(5, view_part_id=2), "b2", "view_part_id selects a column")
    check_equal(win.get_string(5, view_part_id=1), "a2", "get_string with a view_part_id")
    check_equal(win.select_row_with_content(5, "a3"), 2, "select_row_with_content")
    check_equal(win.select_row_with_content(5, "a3", column=1), -1, "select_row_with_content in the wrong column")
    check_equal(win.select_row_with_content(5, "nothing here"), -1, "select_row_with_content with no match")
    check_equal(win.clear_selection(5), True, "clear_selection")
    check_equal(win.get_value(5), [], "the Table's value is empty after clear_selection")
    check_equal(win.clear_rows(5), True, "clear_rows")
    check_equal(win.get_rows(5), [], "rows are empty after clear_rows")


def check_structure(win):
    new_id = win.insert_element(10, {"id": 300, "type": "Text", "properties": {"text": "temporary"}},
                                position=aui.InsertPosition.prepend())
    check_equal(new_id, 300, "insert_element returns the element's own id")
    check_equal(win.get_element_info().get(300), "Text", "the inserted element is in the element info")
    check_equal(win.remove_element(300), True, "remove_element")
    check(300 not in win.get_element_info(), "the removed element is gone")

    ids = win.insert_row(7, [{"id": 310, "type": "Text", "properties": {"text": "r1c0"}},
                             {"id": 311, "type": "Text", "properties": {"text": "r1c1"}}],
                         position=aui.InsertPosition.at(0))
    check_equal(ids, [310, 311], "insert_row returns one id per cell")


def check_presentation(win):
    check_equal(win.present_toast("Saved", duration=2), True, "present_toast")
    check_equal(win.dismiss_toast(), True, "dismiss_toast")

    check_equal(win.present_alert("Sure?", "This cannot be undone", [
        aui.DialogButton("Cancel", role=aui.ButtonRole.CANCEL),
        aui.DialogButton("Delete", role=aui.ButtonRole.DESTRUCTIVE, action_id="delete.confirmed"),
    ]), True, "present_alert with buttons")
    check_equal(win.dismiss_dialog(), True, "dismiss_dialog")
    check_equal(win.present_alert("Plain"), True, "present_alert without buttons")
    check_equal(win.dismiss_dialog(), True, "dismiss_dialog again")
    check_equal(win.present_confirmation_dialog("Really?", buttons=["Yes", "No"]), True,
                "present_confirmation_dialog")
    check_equal(win.dismiss_dialog(), True, "dismiss_dialog after the confirmation dialog")

    check_equal(win.present_modal({"id": 200, "type": "VStack",
                                   "children": [{"id": 201, "type": "Text", "properties": {"text": "modal"}}]},
                                  style=aui.ModalStyle.SHEET), True, "present_modal from an element")
    check_equal(win.dismiss_modal(), True, "dismiss_modal")


def check_errors(win, uuid):
    check_raises(1002, "get_value on an unknown view", win.get_value, 99)
    check_raises(1002, "remove_element on an unknown view", win.remove_element, 99)
    check_raises(1001, "an unknown window", aui.Window("no-such-window", connection=win.connection).get_value, 2)
    check_raises(1003, "insert into a TextField, which is not a container",
                 win.insert_element, 2, {"type": "Text"})
    check_raises(-32601, "an unknown method", win.connection.call, "actionui.noSuchMethod")
    check_raises(-32602, "a missing param", win.connection.call, "actionui.getValue", {"window": uuid})
    # Without a host resolver only an absolute path is accepted, and it has to exist.
    check_raises(-32602, "a relative modal path with no host resolver", win.present_modal, path="relative.json")
    check_raises(1003, "an absolute modal path that does not exist", win.present_modal, path="/nonexistent/modal.json")


def check_batches_and_notifications(win):
    with win.batch() as batch:
        batch.set_string(2, "batched")
        batch.get_string(2)
        batch.set_rows(5, [["x1", "y1"], ["x2", "y2"]])
    check_equal(batch.results, [True, "batched", True],
                "a getter in a batch sees the setter before it, in one main-thread turn")
    check_equal(win.get_rows(5), [["x1", "y1"], ["x2", "y2"]], "the batch's rows landed")

    with win.batch(raise_on_error=False) as batch:
        batch.get_value(99)
        batch.set_string(2, "after the failure")
    check(isinstance(batch.results[0], aui.RemoteError) and batch.results[0].code == 1002,
          "a failing batch member carries its error, got %r" % (batch.results[0],))
    check_equal(batch.results[1], True, "a batch member after a failing one still runs")
    check_equal(win.get_string(2), "after the failure", "the surviving batch member was applied")

    raised = None
    try:
        with win.batch() as batch:
            batch.set_string(2, "before")
            batch.get_value(99)
    except aui.RemoteError as error:
        raised = error
    check(raised is not None and raised.code == 1002, "a failing batch raises on exit by default")
    check(raised is not None and len(raised.results or []) == 2, "the raised error carries every result")

    # A notification is executed and never answered; if the host replied, the next call would
    # read that reply and fail on its id.
    win.connection.notify("actionui.setValue", {"window": win.uuid, "viewID": 3, "value": False})
    check_equal(win.get_bool(3), False, "a notification is applied")


def check_environment(uuid):
    from_env = aui.Window.from_environment()
    check_equal(from_env.uuid, uuid, "Window.from_environment uses ACTIONUI_WINDOW_UUID")
    check_equal(from_env.get_element_info().get(2), "TextField",
                "the window built from the environment reaches the same host")


def leave_final_state(win):
    """The state PythonClientIntegrationTests re-reads through ActionUIModel."""
    win.set_string(2, "final text")
    win.set_state(2, "count", 7)
    win.set_bool(3, True)
    win.set_enabled(3, False)
    win.set_rows(5, [["x1", "y1"], ["x2", "y2"]])
    win.insert_element(10, {"id": 301, "type": "Text", "properties": {"text": "left behind"}})
    win.present_toast("done from python", duration=60)


def main(argv):
    if len(argv) not in (3, 4):
        sys.stderr.write("usage: test_live_client.py <socket path> <window uuid> [expected host name]\n")
        return 2
    endpoint, uuid = argv[1], argv[2]
    expected_host = argv[3] if len(argv) == 4 else None

    win = aui.Window(uuid, connection=aui.Connection(endpoint, timeout=30.0))
    try:
        check_discovery(win, uuid, expected_host)
        check_values(win)
        check_properties_and_state(win)
        check_rows(win)
        check_structure(win)
        check_presentation(win)
        check_errors(win, uuid)
        check_batches_and_notifications(win)
        check_environment(uuid)
        leave_final_state(win)
    except Exception as error:                                  # noqa: BLE001 - reported, not swallowed
        import traceback
        FAILURES.append("unexpected %s: %s\n%s" % (type(error).__name__, error, traceback.format_exc()))

    for failure in FAILURES:
        print("FAIL: %s" % failure)
    print("live client: %d checks, %d failures" % (CHECKS[0], len(FAILURES)))
    return 1 if FAILURES else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
