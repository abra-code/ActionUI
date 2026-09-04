"""Unit tests for actionui_remote (the client) and actionui_remote_testing (the fake host).

Run from this directory:

    python3 -m unittest test_actionui_remote

`-m unittest` puts the working directory on sys.path rather than the test file's directory, so
running it from the package root would not find the modules; this file adds its own directory to
sys.path as well, so `python3 ActionUIRemote/Python/test_actionui_remote.py` works too.

Everything here runs the real client over a real Unix socket against FakeServer, so a test
exercises the same encoding, framing and connection code a script uses against a live ActionUI
host. Where the fake deliberately differs from the host (no rendering, any unregistered host
method answers true, rows and column counts tracked with no notion of table-ness) the test that
touches it says so.
"""

import json
import os
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import threading
import time
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import actionui_remote as aui                                   # noqa: E402
from actionui_remote_testing import FakeServer, Failure         # noqa: E402


HERE = os.path.dirname(os.path.abspath(__file__))
SUN_PATH_LIMIT = 103                # macOS sun_path budget, PROTOCOL.md section 1
WINDOW = "W-1"
FIXTURE = {2: "TextField", 3: "Toggle", 5: "Table", 10: "VStack"}   # same shape as the Swift tests


def _socket_dir():
    """A temp directory in which "<dir>/s" still fits in sun_path."""
    for extra in ({}, {"dir": "/tmp"}):
        try:
            directory = tempfile.mkdtemp(prefix="aui", **extra)
        except OSError:
            continue
        if len(os.path.join(directory, "s").encode("utf-8")) <= SUN_PATH_LIMIT:
            return directory
        shutil.rmtree(directory, ignore_errors=True)
    raise unittest.SkipTest("no temp directory short enough for a Unix socket path")


def _wait_for(predicate, seconds=10.0):
    limit = time.time() + seconds
    while time.time() < limit:
        if predicate():
            return True
        time.sleep(0.02)
    return predicate()


class _ScriptedHost:
    """A socket that accepts one connection, reads one line, and writes canned lines back.

    It exists to drive the client through replies a well-behaved host never sends: an
    unsolicited line, a reply to somebody else's id, garbage, a malformed envelope, a close
    with no reply, or no reply at all.
    """

    def __init__(self, path, replies=(), hold=False, terminate=True):
        self.path = path
        self.replies = list(replies)
        self.hold = hold
        self.terminate = terminate
        self.received = []
        self._release = threading.Event()
        self._sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self._sock.bind(path)
        self._sock.listen(1)
        self._thread = threading.Thread(target=self._serve, daemon=True)
        self._thread.start()

    def _serve(self):
        try:
            connection, _ = self._sock.accept()
        except OSError:
            return
        try:
            buffer = b""
            while b"\n" not in buffer:
                chunk = connection.recv(65536)
                if not chunk:
                    return
                buffer += chunk
            self.received.append(buffer.split(b"\n")[0])
            for reply in self.replies:
                payload = reply.encode("utf-8")
                connection.sendall(payload + b"\n" if self.terminate else payload)
            if self.hold:
                self._release.wait(30.0)
        except OSError:
            pass
        finally:
            connection.close()

    def stop(self):
        self._release.set()
        try:
            self._sock.close()
        except OSError:
            pass
        self._thread.join(timeout=5)


class FakeHostTestCase(unittest.TestCase):
    """A fake host with the standard fixture window, and a client connected to it."""

    def setUp(self):
        self.dir = _socket_dir()
        self.addCleanup(shutil.rmtree, self.dir, True)
        self.socket_path = os.path.join(self.dir, "s")
        self.fake = self.start_fake()
        self.connection = aui.Connection(self.socket_path, timeout=5.0)
        self.addCleanup(self.connection.close)
        self.win = aui.Window(WINDOW, connection=self.connection)

    def start_fake(self, log_path=None):
        fake = FakeServer(self.socket_path, log_path=log_path, host_name="TestHost", host_version="1.2")
        fake.add_window(WINDOW, FIXTURE)
        fake.serve_in_thread()
        self.addCleanup(fake.stop)
        return fake

    # -- helpers

    @property
    def model(self):
        return self.fake.model[WINDOW]

    def methods_called(self):
        return [request["method"] for request in self.fake.requests]

    def last_params(self):
        return self.fake.requests[-1]["params"]


# --- discovery ------------------------------------------------------------------------------

class TokenTests(FakeHostTestCase):
    """A host may require a token. The point of the design is that a caller never mentions it."""

    def setUp(self):
        super().setUp()
        self._saved = os.environ.get(aui.TOKEN_ENV)
        self.addCleanup(self._restore_token)

    def _restore_token(self):
        if self._saved is None:
            os.environ.pop(aui.TOKEN_ENV, None)
        else:
            os.environ[aui.TOKEN_ENV] = self._saved

    def start_guarded(self, *tokens):
        """A second fake on its own socket that requires one of `tokens`."""
        path = os.path.join(self.dir, "guarded")
        fake = FakeServer(path, host_name="Guarded", host_version="1", tokens=tokens)
        fake.add_window(WINDOW, FIXTURE)
        fake.serve_in_thread()
        self.addCleanup(fake.stop)
        return path

    def test_the_environment_token_is_sent_without_the_caller_asking(self):
        path = self.start_guarded("good")
        os.environ[aui.TOKEN_ENV] = "good"
        # Exactly what a spawned handler writes: nothing about tokens at all.
        win = aui.Window(WINDOW, endpoint=path, timeout=5.0)
        self.addCleanup(win.connection.close)
        win.set_value(2, 0, "written")
        self.assertEqual(win.get_value(2), "written")

    def test_no_token_is_refused_with_1006(self):
        path = self.start_guarded("good")
        os.environ.pop(aui.TOKEN_ENV, None)
        win = aui.Window(WINDOW, endpoint=path, timeout=5.0)
        self.addCleanup(win.connection.close)
        with self.assertRaises(aui.RemoteError) as caught:
            win.get_value(2)
        self.assertEqual(caught.exception.code, 1006)

    def test_a_wrong_token_is_refused(self):
        path = self.start_guarded("good")
        os.environ[aui.TOKEN_ENV] = "wrong"
        win = aui.Window(WINDOW, endpoint=path, timeout=5.0)
        self.addCleanup(win.connection.close)
        with self.assertRaises(aui.RemoteError) as caught:
            win.get_value(2)
        self.assertEqual(caught.exception.code, 1006)

    def test_an_explicit_token_beats_the_environment(self):
        path = self.start_guarded("good")
        os.environ[aui.TOKEN_ENV] = "wrong"
        connection = aui.Connection(path, timeout=5.0, token="good")
        self.addCleanup(connection.close)
        win = aui.Window(WINDOW, connection=connection)
        win.set_value(2, 0, "allowed")
        self.assertEqual(win.get_value(2), "allowed")

    def test_an_empty_explicit_token_sends_none_deliberately(self):
        path = self.start_guarded("good")
        os.environ[aui.TOKEN_ENV] = "good"
        connection = aui.Connection(path, timeout=5.0, token="")
        self.addCleanup(connection.close)
        with self.assertRaises(aui.RemoteError) as caught:
            aui.Window(WINDOW, connection=connection).get_value(2)
        self.assertEqual(caught.exception.code, 1006)

    def test_the_token_is_read_per_request_not_captured_at_connect(self):
        # connect() caches one Connection per endpoint, so capturing the token when the object
        # is built would pin whatever the environment held the first time anything connected.
        path = self.start_guarded("good")
        os.environ.pop(aui.TOKEN_ENV, None)
        connection = aui.Connection(path, timeout=5.0)
        self.addCleanup(connection.close)
        win = aui.Window(WINDOW, connection=connection)
        with self.assertRaises(aui.RemoteError):
            win.get_value(2)
        os.environ[aui.TOKEN_ENV] = "good"          # the value appears in the environment later
        win.set_value(2, 0, "now allowed")
        self.assertEqual(win.get_value(2), "now allowed")

    def test_a_host_requiring_nothing_ignores_a_token(self):
        os.environ[aui.TOKEN_ENV] = "irrelevant"
        self.win.set_value(2, 0, "fine")
        self.assertEqual(self.win.get_value(2), "fine")

    def test_the_token_is_redacted_from_the_hosts_request_log(self):
        log_path = os.path.join(self.dir, "requests.jsonl")
        path = os.path.join(self.dir, "logged")
        fake = FakeServer(path, log_path=log_path, host_name="Logged", host_version="1",
                          tokens=("secret-value",))
        fake.add_window(WINDOW, FIXTURE)
        fake.serve_in_thread()
        self.addCleanup(fake.stop)

        os.environ[aui.TOKEN_ENV] = "secret-value"
        win = aui.Window(WINDOW, endpoint=path, timeout=5.0)
        self.addCleanup(win.connection.close)
        win.get_value(2)
        fake.stop()

        with open(log_path) as handle:
            body = handle.read()
        self.assertNotIn("secret-value", body, "a credential must not land in a test log")
        self.assertIn("<redacted>", body)
        # And in memory, which is what bridge_called reads through.
        self.assertNotIn("secret-value", json.dumps(fake.requests))


class DiscoveryTests(FakeHostTestCase):

    def test_hello_reports_the_protocol_the_host_and_the_windows(self):
        info = aui.hello(self.socket_path)
        self.addCleanup(_forget_cached_connection, self.socket_path)
        self.assertEqual(info["protocolVersion"], aui.PROTOCOL_VERSION)
        self.assertEqual(info["host"], {"name": "TestHost", "version": "1.2"})
        self.assertEqual(info["windows"], [WINDOW])
        self.assertIn("actionui.hello", info["methods"])
        self.assertEqual(info["methods"], sorted(info["methods"]))

    def test_list_windows(self):
        self.fake.add_window("W-2")
        self.assertEqual(self.connection.call("actionui.listWindows"), [WINDOW, "W-2"])

    def test_get_element_info_keys_are_integers(self):
        self.assertEqual(self.win.get_element_info(), FIXTURE)

    def test_content_size_limits_is_none_when_the_host_does_not_render(self):
        # A documented divergence: the fake models no layout, so it always answers null.
        self.assertIsNone(self.win.content_size_limits())

    def test_content_size_limits_becomes_a_tuple(self):
        # The conversion a real host's object goes through. A registered handler wins over the
        # fake's builtin, which is the only way to make it answer an object here.
        self.fake.register("actionui.contentSizeLimits",
                           lambda params: {"minWidth": 100, "minHeight": 50,
                                           "maxWidth": 800, "maxHeight": 600})
        self.assertEqual(self.win.content_size_limits(), (100, 50, 800, 600))

    def test_repr_names_the_window_and_the_endpoint(self):
        self.assertIn(WINDOW, repr(self.win))
        self.assertIn(self.socket_path, repr(self.win))


# --- values ---------------------------------------------------------------------------------

class ValueTests(FakeHostTestCase):

    def test_set_value_takes_the_in_process_argument_order(self):
        # (view_id, view_part_id, value), as ActionUIPython's Window.set_value.
        self.assertTrue(self.win.set_value(2, 0, "Ada"))
        self.assertEqual(self.model["values"][2], "Ada")
        self.assertEqual(self.win.get_value(2), "Ada")

    def test_view_part_id_reaches_the_wire_and_selects_a_cell(self):
        self.win.set_value(5, 0, ["a", "b", "c"])
        self.assertEqual(self.win.get_value(5, view_part_id=2), "b")
        self.assertEqual(self.last_params()["viewPartID"], 2)

    def test_view_part_id_zero_is_omitted(self):
        self.win.get_value(2)
        self.assertNotIn("viewPartID", self.last_params())

    def test_get_value_of_an_unset_element_is_none(self):
        self.assertIsNone(self.win.get_value(2))

    def test_string_round_trip_with_a_content_type(self):
        self.assertTrue(self.win.set_string(2, "**bold**", content_type="markdown"))
        self.assertEqual(self.last_params()["contentType"], "markdown")
        self.assertEqual(self.win.get_string(2), "**bold**")
        # get_string and set_string take their optional arguments in a different order, so the
        # getter's content type has to be checked on its own.
        self.assertEqual(self.win.get_string(2, content_type="plain"), "**bold**")
        self.assertEqual(self.last_params()["contentType"], "plain")

    def test_set_string_stringifies_its_argument(self):
        self.win.set_string(2, 42)
        self.assertEqual(self.model["strings"][2], "42")

    def test_get_string_stringifies_a_value_that_was_not_set_as_a_string(self):
        # Every other string test sets through set_string first, which short-circuits the
        # host's stringification; this is the read-back path a script actually takes.
        self.win.set_int(2, 42)
        self.assertEqual(self.win.get_string(2), "42")
        self.win.set_bool(3, True)
        self.assertEqual(self.win.get_string(3), "true")

    def test_typed_getters_coerce_the_wire_value(self):
        self.win.set_string(2, "42")
        self.assertEqual(self.win.get_int(2), 42)
        self.assertEqual(self.win.get_double(2), 42.0)
        self.assertIsInstance(self.win.get_double(2), float)
        self.win.set_bool(3, True)
        self.assertIs(self.win.get_bool(3), True)

    def test_typed_getters_pass_none_through(self):
        self.assertIsNone(self.win.get_int(2))
        self.assertIsNone(self.win.get_double(2))
        self.assertIsNone(self.win.get_bool(2))

    def test_typed_setters_convert_before_sending(self):
        self.win.set_int(2, "7")
        self.assertEqual(self.model["values"][2], 7)
        self.win.set_double(2, 3)
        self.assertEqual(self.model["values"][2], 3.0)
        self.win.set_bool(3, 1)
        self.assertIs(self.model["values"][3], True)

    def test_a_view_id_must_be_an_integer(self):
        with self.assertRaises(TypeError):
            self.win.get_value("2")
        with self.assertRaises(TypeError):
            self.win.get_value(True)          # a bool is not a view id, though it is an int


# --- properties and state -------------------------------------------------------------------

class PropertyAndStateTests(FakeHostTestCase):

    def test_property_round_trip(self):
        self.assertTrue(self.win.set_property(2, "disabled", True))
        self.assertIs(self.win.get_property(2, "disabled"), True)

    def test_unset_property_is_none(self):
        self.assertIsNone(self.win.get_property(2, "disabled"))

    def test_set_enabled_and_set_hidden_are_sugar_over_set_property(self):
        self.win.set_enabled(2, False)
        self.assertEqual(self.methods_called()[-1], "actionui.setProperty")
        self.assertIs(self.win.get_property(2, "disabled"), True)
        self.win.set_enabled(2, True)
        self.assertIs(self.win.get_property(2, "disabled"), False)
        self.win.set_hidden(2, True)
        self.assertIs(self.win.get_property(2, "hidden"), True)

    def test_state_round_trip_and_string_view(self):
        self.assertTrue(self.win.set_state(2, "count", 1))
        self.assertEqual(self.win.get_state(2, "count"), 1)
        self.assertEqual(self.win.get_state_string(2, "count"), "1")

    def test_unset_state_is_none(self):
        self.assertIsNone(self.win.get_state(2, "count"))
        self.assertIsNone(self.win.get_state_string(2, "count"))

    def test_state_type_mismatch_is_an_engine_failure(self):
        self.win.set_state(2, "count", 1)
        with self.assertRaises(aui.RemoteError) as caught:
            self.win.set_state(2, "count", "one")
        self.assertEqual(caught.exception.code, aui.RemoteError.ENGINE_FAILURE)

    def test_a_bool_state_does_not_accept_a_number(self):
        self.win.set_state(3, "on", True)
        with self.assertRaises(aui.RemoteError) as caught:
            self.win.set_state(3, "on", 1)
        self.assertEqual(caught.exception.code, aui.RemoteError.ENGINE_FAILURE)

    def test_state_coerces_toward_the_stored_type(self):
        # The host accepts a whole number into a Double state and an integral float into an Int.
        self.win.set_state(2, "ratio", 1.5)
        self.assertTrue(self.win.set_state(2, "ratio", 2))
        self.assertEqual(self.win.get_state(2, "ratio"), 2.0)
        self.win.set_state(2, "count", 1)
        self.assertTrue(self.win.set_state(2, "count", 4.0))
        self.assertEqual(self.win.get_state(2, "count"), 4)

    def test_set_state_from_string_parses_toward_the_stored_type(self):
        self.win.set_state(2, "count", 1)
        self.assertTrue(self.win.set_state_from_string(2, "count", 7))
        self.assertEqual(self.win.get_state(2, "count"), 7)

        self.win.set_state(3, "flag", True)
        self.win.set_state_from_string(3, "flag", "yes")
        self.assertIs(self.win.get_state(3, "flag"), True)
        self.win.set_state_from_string(3, "flag", "off")
        self.assertIs(self.win.get_state(3, "flag"), False)

        self.win.set_state(3, "ratio", 0.5)
        self.win.set_state_from_string(3, "ratio", "1.25")
        self.assertEqual(self.win.get_state(3, "ratio"), 1.25)

        self.win.set_state_from_string(3, "fresh", "text")
        self.assertEqual(self.win.get_state(3, "fresh"), "text")


# --- rows and selection ---------------------------------------------------------------------

class RowTests(FakeHostTestCase):

    ROWS = [["Ada", "1815"], ["Grace", "1906"]]

    def test_rows_round_trip(self):
        self.assertTrue(self.win.set_rows(5, self.ROWS))
        self.assertEqual(self.win.get_rows(5), self.ROWS)
        # Another divergence: the fake counts the widest stored row, while the real host reads
        # the columns property whenever the Table has no content.
        self.assertEqual(self.win.get_column_count(5), 2)

    def test_append_and_clear_rows(self):
        self.win.set_rows(5, self.ROWS)
        self.assertTrue(self.win.append_rows(5, [["Alan", "1912"]]))
        self.assertEqual(len(self.win.get_rows(5)), 3)
        self.assertTrue(self.win.clear_rows(5))
        self.assertEqual(self.win.get_rows(5), [])

    def test_get_rows_is_none_when_no_rows_are_recorded(self):
        # A divergence: the fake has no notion of table-ness and answers null for any view it
        # holds no rows for, the Table included. The real host answers null only for an element
        # that is not a Table or List.
        self.assertIsNone(self.win.get_rows(2))
        self.assertIsNone(self.win.get_rows(5))

    def test_cells_are_stringified(self):
        self.win.set_rows(5, [[1, 2.5, True]])
        self.assertEqual(self.win.get_rows(5), [["1", "2.5", "True"]])

    def test_a_string_row_is_refused_rather_than_shredded_into_characters(self):
        with self.assertRaises(TypeError):
            self.win.set_rows(5, ["ab", "cd"])
        with self.assertRaises(TypeError):
            self.win.append_rows(5, ["ab"])

    def test_select_row_returns_the_row(self):
        self.win.set_rows(5, self.ROWS)
        self.assertEqual(self.win.select_row(5, 1), ["Grace", "1906"])
        self.assertEqual(self.model["selection"][5], 1)

    def test_select_row_out_of_range_returns_none_and_clears_the_selection(self):
        self.win.set_rows(5, self.ROWS)
        self.win.select_row(5, 0)
        self.assertIsNone(self.win.select_row(5, 9))
        self.assertNotIn(5, self.model["selection"])

    def test_select_row_with_content_in_any_column_or_one_column(self):
        self.win.set_rows(5, self.ROWS)
        self.assertEqual(self.win.select_row_with_content(5, "1906"), 1)
        self.assertEqual(self.win.select_row_with_content(5, "Ada", column=0), 0)
        self.assertEqual(self.win.select_row_with_content(5, "Ada", column=1), -1)
        self.assertEqual(self.win.select_row_with_content(5, "nobody"), -1)

    def test_clear_selection(self):
        self.win.set_rows(5, self.ROWS)
        self.win.select_row(5, 0)
        self.assertTrue(self.win.clear_selection(5))
        self.assertNotIn(5, self.model["selection"])

    def test_an_index_must_be_an_integer(self):
        with self.assertRaises(TypeError):
            self.win.select_row(5, True)
        with self.assertRaises(TypeError):
            self.win.select_row_with_content(5, "Ada", column="0")


# --- structural mutation --------------------------------------------------------------------

class StructureTests(FakeHostTestCase):

    def test_insert_element_returns_the_new_id(self):
        self.assertEqual(self.win.insert_element(10, {"type": "Text", "id": 42, "title": "hi"}), 42)
        self.assertEqual(self.win.get_element_info()[42], "Text")

    def test_insert_element_without_an_id_gets_a_negative_one(self):
        new_id = self.win.insert_element(10, {"type": "Text"})
        self.assertLess(new_id, 0)

    def test_insert_positions_reach_the_wire(self):
        cases = [
            (aui.InsertPosition.append(), {"kind": "append"}),
            (aui.InsertPosition.prepend(), {"kind": "prepend"}),
            (aui.InsertPosition.at(2), {"kind": "at", "index": 2}),
            (aui.InsertPosition.before(7), {"kind": "before", "siblingID": 7}),
            (aui.InsertPosition.after(7), {"kind": "after", "siblingID": 7}),
            ("append", "append"),
            ({"kind": "at", "index": 0}, {"kind": "at", "index": 0}),
        ]
        for position, expected in cases:
            with self.subTest(position=expected):
                self.win.insert_element(10, {"type": "Text"}, position=position)
                self.assertEqual(self.last_params()["position"], expected)

    def test_position_must_be_a_known_shape(self):
        with self.assertRaises(TypeError):
            self.win.insert_element(10, {"type": "Text"}, position=3)

    def test_insert_element_carries_the_container(self):
        self.win.insert_element(10, {"type": "Text"}, container="content")
        self.assertEqual(self.last_params()["container"], "content")

    def test_insert_row_returns_one_id_per_cell(self):
        ids = self.win.insert_row(5, [{"type": "Text", "id": 51}, {"type": "Text", "id": 52}],
                                  position=aui.InsertPosition.at(0))
        self.assertEqual(ids, [51, 52])
        self.assertEqual(self.last_params()["position"], {"kind": "at", "index": 0})

    def test_insert_row_carries_the_container(self):
        self.win.insert_row(5, [{"type": "Text"}], container="rows")
        self.assertEqual(self.last_params()["container"], "rows")

    def test_insert_into_an_unknown_parent_is_an_engine_failure(self):
        with self.assertRaises(aui.RemoteError) as caught:
            self.win.insert_element(999, {"type": "Text"})
        self.assertEqual(caught.exception.code, aui.RemoteError.ENGINE_FAILURE)

    def test_remove_element(self):
        self.win.insert_element(10, {"type": "Text", "id": 42})
        self.assertTrue(self.win.remove_element(42))
        self.assertNotIn(42, self.win.get_element_info())

    def test_a_parent_id_must_be_an_integer(self):
        with self.assertRaises(TypeError):
            self.win.insert_element("10", {"type": "Text"})


# --- presentation ---------------------------------------------------------------------------

class PresentationTests(FakeHostTestCase):

    def test_present_modal_from_a_positional_element(self):
        self.assertTrue(self.win.present_modal({"type": "VStack"}))
        self.assertEqual(self.model["modal"]["source"], {"element": {"type": "VStack"}})
        self.assertEqual(self.model["modal"]["style"], "sheet")

    def test_present_modal_from_positional_json_text(self):
        self.win.present_modal('{"type":"Text"}', format="json")
        self.assertEqual(self.model["modal"]["source"], {"json": '{"type":"Text"}'})
        self.assertEqual(self.last_params()["format"], "json")

    def test_present_modal_from_a_path_with_a_style_and_a_dismiss_action(self):
        self.win.present_modal(path="MyModal", style=aui.ModalStyle.FULL_SCREEN_COVER,
                               on_dismiss_action_id="done")
        self.assertEqual(self.model["modal"]["source"], {"path": "MyModal"})
        self.assertEqual(self.model["modal"]["style"], "fullScreenCover")
        self.assertEqual(self.model["modal"]["onDismissActionID"], "done")

    def test_present_modal_needs_a_source(self):
        with self.assertRaises(ValueError):
            self.win.present_modal()
        with self.assertRaises(TypeError):
            self.win.present_modal(5)

    def test_an_unknown_modal_style_is_refused_by_the_host(self):
        with self.assertRaises(aui.RemoteError) as caught:
            self.win.present_modal({"type": "VStack"}, style="popover")
        self.assertEqual(caught.exception.code, aui.RemoteError.INVALID_PARAMS)

    def test_dismiss_modal(self):
        self.win.present_modal({"type": "VStack"})
        self.assertTrue(self.win.dismiss_modal())
        self.assertIsNone(self.model["modal"])

    def test_present_alert_defaults_to_one_ok_button(self):
        self.assertTrue(self.win.present_alert("Saved"))
        self.assertEqual(self.model["dialog"]["title"], "Saved")
        self.assertEqual(self.model["dialog"]["buttons"], [{"title": "OK", "role": "cancel"}])

    def test_buttons_accept_the_three_spellings(self):
        self.win.present_alert("Delete?", "This cannot be undone", [
            aui.DialogButton("Delete", role=aui.ButtonRole.DESTRUCTIVE, action_id="del"),
            "Cancel",
            {"title": "Later"},
        ])
        self.assertEqual(self.model["dialog"]["buttons"], [
            {"title": "Delete", "role": "destructive", "actionID": "del"},
            {"title": "Cancel"},
            {"title": "Later"},
        ])
        self.assertEqual(self.model["dialog"]["message"], "This cannot be undone")

    def test_a_button_must_be_a_button_a_dict_or_a_title(self):
        with self.assertRaises(TypeError):
            self.win.present_alert("Hm", buttons=[5])

    def test_present_confirmation_dialog_keeps_the_in_process_argument_order(self):
        self.assertTrue(self.win.present_confirmation_dialog("Sure?", "Really", ["Yes", "No"]))
        self.assertEqual(self.model["dialog"]["style"], "confirmationDialog")
        self.assertEqual(self.model["dialog"]["message"], "Really")
        self.assertEqual([b["title"] for b in self.model["dialog"]["buttons"]], ["Yes", "No"])

    def test_present_confirmation_dialog_refuses_an_empty_button_list(self):
        for buttons in (None, [], "Yes", {"title": "Yes"}, aui.DialogButton("Yes")):
            with self.subTest(buttons=buttons):
                with self.assertRaises(ValueError):
                    self.win.present_confirmation_dialog("Sure?", buttons=buttons)
        self.assertEqual(self.methods_called(), [])   # nothing reached the host

    def test_dismiss_dialog(self):
        self.win.present_alert("Saved")
        self.assertTrue(self.win.dismiss_dialog())
        self.assertIsNone(self.model["dialog"])

    def test_present_toast_with_and_without_options(self):
        self.assertTrue(self.win.present_toast("Done"))
        self.assertEqual(self.model["toast"], {"message": "Done", "duration": 4.0,
                                               "actionTitle": None, "actionID": None})
        self.win.present_toast("Deleted", duration=2, action_title="Undo", action_id="undo")
        self.assertEqual(self.model["toast"], {"message": "Deleted", "duration": 2.0,
                                               "actionTitle": "Undo", "actionID": "undo"})

    def test_dismiss_toast(self):
        self.win.present_toast("Done")
        self.assertTrue(self.win.dismiss_toast())
        self.assertIsNone(self.model["toast"])


# --- errors ---------------------------------------------------------------------------------

class ErrorTests(FakeHostTestCase):

    def test_unknown_window(self):
        other = aui.Window("no-such-window", connection=self.connection)
        with self.assertRaises(aui.RemoteError) as caught:
            other.get_value(2)
        self.assertEqual(caught.exception.code, aui.RemoteError.UNKNOWN_WINDOW)

    def test_unknown_view(self):
        with self.assertRaises(aui.RemoteError) as caught:
            self.win.get_value(99)
        error = caught.exception
        self.assertEqual(error.code, aui.RemoteError.UNKNOWN_VIEW)
        self.assertIn("99", error.message)
        self.assertEqual(str(error), "[%d] %s" % (error.code, error.message))
        self.assertIsNotNone(error.request_id)
        self.assertIsNone(error.results)

    def test_unknown_actionui_method(self):
        with self.assertRaises(aui.RemoteError) as caught:
            self.connection.call("actionui.noSuchThing")
        self.assertEqual(caught.exception.code, aui.RemoteError.METHOD_NOT_FOUND)

    def test_a_missing_param_is_invalid_params(self):
        with self.assertRaises(aui.RemoteError) as caught:
            self.connection.call("actionui.getValue", {"window": WINDOW})
        self.assertEqual(caught.exception.code, aui.RemoteError.INVALID_PARAMS)
        self.assertIn("viewID", caught.exception.message)

    def test_a_host_method_goes_through_call_with_the_window_filled_in(self):
        seen = {}

        def handler(params):
            seen.update(params)
            return {"ok": True}

        self.fake.register("omc.getContext", handler)
        self.assertEqual(self.win.call("omc.getContext", {"depth": 1}), {"ok": True})
        self.assertEqual(seen, {"window": WINDOW, "depth": 1})

    def test_a_host_handler_can_answer_a_protocol_error_code(self):
        self.fake.register("omc.terminate", lambda params: (_ for _ in ()).throw(Failure(1004, "refused")))
        with self.assertRaises(aui.RemoteError) as caught:
            self.win.call("omc.terminate")
        self.assertEqual(caught.exception.code, aui.RemoteError.HOST_REFUSED)
        self.assertEqual(caught.exception.message, "refused")

    def test_a_host_handler_that_raises_anything_else_is_host_refused(self):
        def handler(params):
            raise ValueError("boom")

        self.fake.register("omc.boom", handler)
        with self.assertRaises(aui.RemoteError) as caught:
            self.win.call("omc.boom")
        self.assertEqual(caught.exception.code, aui.RemoteError.HOST_REFUSED)
        self.assertEqual(caught.exception.message, "boom")

    def test_an_error_carries_its_data(self):
        self.fake.register("omc.busy", lambda params: (_ for _ in ()).throw(
            Failure(1004, "busy", {"why": "a command is running"})))
        with self.assertRaises(aui.RemoteError) as caught:
            self.win.call("omc.busy")
        self.assertEqual(caught.exception.data, {"why": "a command is running"})

    def test_an_unregistered_host_method_is_answered_true_by_the_fake(self):
        # Documented divergence: the real host answers -32601 for a method it does not have.
        self.assertIs(self.win.call("omc.nextCommand", {"id": "next"}), True)

    def test_a_window_needs_a_uuid(self):
        with self.assertRaises(ValueError):
            aui.Window("", connection=self.connection)

    def test_a_connection_needs_an_endpoint(self):
        with self.assertRaises(aui.EndpointError):
            aui.Connection("")


# --- batches --------------------------------------------------------------------------------

BATCH_CALLS = [
    ("get_element_info", (), {}, "actionui.getElementInfo"),
    ("content_size_limits", (), {}, "actionui.contentSizeLimits"),
    ("get_value", (2,), {}, "actionui.getValue"),
    ("set_value", (2, 0, "x"), {}, "actionui.setValue"),
    ("get_string", (2,), {}, "actionui.getValueString"),
    ("set_string", (2, "x"), {}, "actionui.setValueString"),
    ("get_int", (2,), {}, "actionui.getValue"),
    ("set_int", (2, 1), {}, "actionui.setValue"),
    ("get_double", (2,), {}, "actionui.getValue"),
    ("set_double", (2, 1.5), {}, "actionui.setValue"),
    ("get_bool", (3,), {}, "actionui.getValue"),
    ("set_bool", (3, True), {}, "actionui.setValue"),
    ("get_property", (2, "disabled"), {}, "actionui.getProperty"),
    ("set_property", (2, "disabled", True), {}, "actionui.setProperty"),
    ("set_enabled", (2, False), {}, "actionui.setProperty"),
    ("set_hidden", (2, True), {}, "actionui.setProperty"),
    ("get_state", (2, "k"), {}, "actionui.getState"),
    ("get_state_string", (2, "k"), {}, "actionui.getStateString"),
    ("set_state", (2, "k", 1), {}, "actionui.setState"),
    ("set_state_from_string", (2, "k", "1"), {}, "actionui.setStateString"),
    ("get_column_count", (5,), {}, "actionui.getColumnCount"),
    ("get_rows", (5,), {}, "actionui.getRows"),
    ("set_rows", (5, [["a"]]), {}, "actionui.setRows"),
    ("append_rows", (5, [["b"]]), {}, "actionui.appendRows"),
    ("clear_rows", (5,), {}, "actionui.clearRows"),
    ("select_row", (5, 0), {}, "actionui.selectRow"),
    ("select_row_with_content", (5, "a"), {}, "actionui.selectRowWithContent"),
    ("clear_selection", (5,), {}, "actionui.clearSelection"),
    ("insert_element", (10, {"type": "Text"}), {}, "actionui.insertElement"),
    ("insert_row", (5, [{"type": "Text"}]), {}, "actionui.insertRow"),
    ("remove_element", (11,), {}, "actionui.removeElement"),
    ("present_modal", ({"type": "VStack"},), {}, "actionui.presentModal"),
    ("dismiss_modal", (), {}, "actionui.dismissModal"),
    ("present_alert", ("Title",), {}, "actionui.presentAlert"),
    ("present_confirmation_dialog", ("Title", None, ["OK"]), {}, "actionui.presentConfirmationDialog"),
    ("dismiss_dialog", (), {}, "actionui.dismissDialog"),
    ("present_toast", ("hi",), {}, "actionui.presentToast"),
    ("dismiss_toast", (), {}, "actionui.dismissToast"),
    ("call", ("omc.terminate", {"ok": True}), {}, "omc.terminate"),
]


class BatchTests(FakeHostTestCase):

    def test_every_window_method_records_exactly_one_call(self):
        for name, args, kwargs, expected in BATCH_CALLS:
            with self.subTest(method=name):
                batch = self.win.batch()
                getattr(batch, name)(*args, **kwargs)
                calls = [call for call, _ in batch._calls]
                self.assertEqual(len(calls), 1)
                self.assertEqual(calls[0][0], expected)
                self.assertEqual(calls[0][1].get("window"), WINDOW)
        self.assertEqual(self.fake.requests, [])   # recording sends nothing

    def test_the_batch_table_covers_the_whole_window_api(self):
        covered = {name for name, _, _, _ in BATCH_CALLS}
        public = {name for name in vars(aui.Window) if not name.startswith("_")}
        self.assertEqual(public - covered - {"batch", "connection", "from_environment"}, set())

    def test_a_batch_applies_in_order_and_returns_one_result_per_call(self):
        with self.win.batch() as batch:
            batch.set_string(2, "Working...")
            batch.set_enabled(2, False)
            batch.set_rows(5, [["a", "b"]])
        self.assertEqual(batch.results, [True, True, True])
        self.assertEqual(self.methods_called(),
                         ["actionui.setValueString", "actionui.setProperty", "actionui.setRows"])
        self.assertEqual(self.win.get_string(2), "Working...")

    def test_batched_getters_are_post_processed_like_direct_calls(self):
        self.win.set_string(2, "42")
        with self.win.batch() as batch:
            batch.get_int(2)
            batch.get_double(2)
            batch.get_element_info()
        self.assertEqual(batch.results[0], 42)
        self.assertIsInstance(batch.results[0], int)
        self.assertEqual(batch.results[1], 42.0)
        self.assertIsInstance(batch.results[1], float)
        self.assertEqual(batch.results[2], FIXTURE)

    def test_a_failing_member_raises_on_exit_and_carries_every_result(self):
        batch = self.win.batch()
        with self.assertRaises(aui.RemoteError) as caught:
            with batch as recorder:
                recorder.set_string(2, "first")
                recorder.get_value(99)
                recorder.set_string(3, "third")
        error = caught.exception
        self.assertEqual(error.code, aui.RemoteError.UNKNOWN_VIEW)
        self.assertEqual(len(error.results), 3)
        self.assertIs(error.results, batch.results)
        self.assertIs(error.results[0], True)
        self.assertIsInstance(error.results[1], aui.RemoteError)
        self.assertIs(error.results[2], True)
        # A failing member does not stop the others: both writes were applied.
        self.assertEqual(self.win.get_string(2), "first")
        self.assertEqual(self.win.get_string(3), "third")

    def test_raise_on_error_false_leaves_the_inspection_to_the_caller(self):
        with self.win.batch(raise_on_error=False) as batch:
            batch.get_value(99)
            batch.set_string(2, "ok")
        self.assertIsInstance(batch.results[0], aui.RemoteError)
        self.assertIs(batch.results[1], True)

    def test_an_exception_inside_the_block_sends_nothing(self):
        batch = self.win.batch()
        with self.assertRaises(ZeroDivisionError):
            with batch as recorder:
                recorder.set_string(2, "never")
                1 / 0
        self.assertIsNone(batch.results)
        self.assertEqual(self.fake.requests, [])

    def test_an_empty_batch_sends_nothing(self):
        with self.win.batch() as batch:
            pass
        self.assertEqual(batch.results, [])
        self.assertEqual(self.fake.requests, [])

    def test_a_batch_cannot_be_sent_twice(self):
        with self.win.batch() as batch:
            batch.dismiss_toast()
        with self.assertRaises(RuntimeError):
            batch.send()

    def test_a_batch_exposes_only_window_methods(self):
        batch = self.win.batch()
        for name in ("no_such_method", "_connection", "batch", "connection", "from_environment"):
            with self.subTest(name=name):
                with self.assertRaises(AttributeError):
                    getattr(batch, name)


# --- connection and transport ---------------------------------------------------------------

def _forget_cached_connection(endpoint):
    connection = aui._connections.pop(endpoint, None)
    if connection is not None:
        connection.close()


class ConnectionTests(FakeHostTestCase):

    def test_a_notification_is_executed(self):
        self.connection.notify("actionui.setValueString",
                               {"window": WINDOW, "viewID": 2, "value": "quiet"})
        self.assertEqual(self.win.get_string(2), "quiet")

    def test_a_notification_gets_no_line_back(self):
        # The call above cannot prove this: the client skips any line that is not its own
        # reply, so a stray answer to the notification would pass unnoticed. Only a raw socket,
        # which reads whatever arrives, can show that nothing was sent for it.
        raw = self._raw_socket()
        raw.sendall(b'{"jsonrpc":"2.0","method":"actionui.setValueString","params":'
                    b'{"window":"' + WINDOW.encode("utf-8") + b'","viewID":2,"value":"quiet"}}\n')
        raw.sendall(b'{"jsonrpc":"2.0","id":7,"method":"actionui.listWindows"}\n')
        self.assertEqual(self._read_json(raw)["id"], 7, "the first line back must be the call's")

    def test_a_closed_connection_reconnects_on_the_next_call(self):
        self.win.set_string(2, "before")
        self.connection.close()
        self.assertFalse(self.connection.is_connected)
        self.assertEqual(self.win.get_string(2), "before")
        self.assertTrue(self.connection.is_connected)

    def test_a_restarted_host_is_reachable_on_the_next_call(self):
        self.win.set_string(2, "before")
        self.fake.stop()
        self.fake = self.start_fake()
        self.win.set_string(2, "after")          # the send fails, reconnects, and is resent
        self.assertEqual(self.win.get_string(2), "after")
        # Both calls reached the NEW fake. Without this, a handler thread of the stopped one
        # still serving the client's existing socket would satisfy everything above.
        self.assertEqual(self.methods_called(),
                         ["actionui.setValueString", "actionui.getValueString"])

    def test_a_host_that_is_gone_names_the_endpoint(self):
        self.win.set_string(2, "before")
        self.fake.stop()
        with self.assertRaises(aui.EndpointError) as caught:
            self.win.get_string(2)
        self.assertIn(self.socket_path, str(caught.exception))

    def test_nothing_listening_at_a_fresh_path(self):
        with self.assertRaises(aui.EndpointError) as caught:
            aui.Connection(os.path.join(self.dir, "absent"), timeout=2.0).call("actionui.hello")
        self.assertIn("no ActionUI host is listening", str(caught.exception))

    def test_a_path_too_long_for_sun_path_says_so(self):
        endpoint = os.path.join(self.dir, "x" * SUN_PATH_LIMIT)
        with self.assertRaises(aui.EndpointError) as caught:
            aui.Connection(endpoint, timeout=2.0).call("actionui.hello")
        self.assertIn("socket path is too long for sun_path", str(caught.exception))
        self.assertIn(str(SUN_PATH_LIMIT), str(caught.exception))

    def test_a_path_of_exactly_the_limit_is_not_refused(self):
        # The boundary: 103 bytes still binds, so the client must let it through to connect().
        # Reaching "nothing is listening" is what proves it got that far.
        room = SUN_PATH_LIMIT - len(self.dir.encode("utf-8")) - 1
        if room < 1:
            self.skipTest("the temp directory leaves no room for a name")
        endpoint = os.path.join(self.dir, "x" * room)
        self.assertEqual(len(endpoint.encode("utf-8")), SUN_PATH_LIMIT)
        with self.assertRaises(aui.EndpointError) as caught:
            aui.Connection(endpoint, timeout=2.0).call("actionui.hello")
        self.assertIn("no ActionUI host is listening", str(caught.exception))

    def test_the_limit_is_measured_in_bytes_not_characters(self):
        # sun_path holds bytes, and a path well under the limit in characters can be over it
        # once encoded, so the check has to encode before it measures.
        room = SUN_PATH_LIMIT - len(self.dir.encode("utf-8")) - 1
        if room < 8:
            self.skipTest("the temp directory leaves no room for a name")
        endpoint = os.path.join(self.dir, "\u00e9" * (room - 2))
        self.assertLessEqual(len(endpoint), SUN_PATH_LIMIT)
        self.assertGreater(len(endpoint.encode("utf-8")), SUN_PATH_LIMIT)
        with self.assertRaises(aui.EndpointError) as caught:
            aui.Connection(endpoint, timeout=2.0).call("actionui.hello")
        # The client's own message, not CPython's "AF_UNIX path too long": falling through to
        # the interpreter is exactly the regression this guards.
        self.assertIn("socket path is too long for sun_path", str(caught.exception))

    def test_an_oversized_batch_is_rejected_whole_and_fanned_out(self):
        calls = [("actionui.hello", {})] * (4096 + 1)
        results = self.connection.call_batch(calls)
        self.assertEqual(len(results), len(calls))
        for outcome in results:
            self.assertIsInstance(outcome, aui.RemoteError)
            self.assertEqual(outcome.code, aui.RemoteError.INVALID_REQUEST)

    def test_a_batch_of_one_still_arrives_as_a_batch(self):
        results = self.connection.call_batch([("actionui.listWindows", {})])
        self.assertEqual(results, [[WINDOW]])

    def test_call_batch_with_nothing_sends_nothing(self):
        self.assertEqual(self.connection.call_batch([]), [])
        self.assertEqual(self.fake.requests, [])

    def test_the_host_answers_a_parse_error_with_a_null_id(self):
        reply = self._raw_exchange(b"not json at all\n")
        self.assertIsNone(reply["id"])
        self.assertEqual(reply["error"]["code"], aui.RemoteError.PARSE_ERROR)

    def test_an_empty_line_is_a_parse_error_not_a_no_op(self):
        reply = self._raw_exchange(b"\n")
        self.assertEqual(reply["error"]["code"], aui.RemoteError.PARSE_ERROR)

    def test_a_scalar_line_is_an_invalid_request(self):
        reply = self._raw_exchange(b"42\n")
        self.assertEqual(reply["error"]["code"], aui.RemoteError.INVALID_REQUEST)

    def test_an_empty_batch_is_an_invalid_request(self):
        reply = self._raw_exchange(b"[]\n")
        self.assertEqual(reply["error"]["code"], aui.RemoteError.INVALID_REQUEST)

    def test_an_invalid_batch_member_is_answered_in_place(self):
        replies = self._raw_exchange(
            b'[{"jsonrpc":"2.0","id":1,"method":"actionui.listWindows"},'
            b'"not an object",'
            b'{"jsonrpc":"2.0","id":3,"method":"actionui.listWindows"}]\n')
        self.assertEqual([reply.get("id") for reply in replies], [1, None, 3])
        self.assertEqual(replies[1]["error"]["code"], aui.RemoteError.INVALID_REQUEST)
        self.assertEqual(replies[0]["result"], [WINDOW])
        self.assertEqual(replies[2]["result"], [WINDOW], "the members around it still run")

    def test_a_wrong_protocol_version_is_an_invalid_request(self):
        reply = self._raw_exchange(b'{"jsonrpc":"1.0","id":1,"method":"actionui.listWindows"}\n')
        self.assertEqual(reply["error"]["code"], aui.RemoteError.INVALID_REQUEST)
        self.assertEqual(reply["id"], 1, "the id is returned when it could be read")

    def test_an_empty_method_is_an_invalid_request(self):
        reply = self._raw_exchange(b'{"jsonrpc":"2.0","id":1,"method":""}\n')
        self.assertEqual(reply["error"]["code"], aui.RemoteError.INVALID_REQUEST)

    def test_a_boolean_id_is_an_invalid_request_with_a_null_id(self):
        reply = self._raw_exchange(b'{"jsonrpc":"2.0","id":true,"method":"actionui.listWindows"}\n')
        self.assertEqual(reply["error"]["code"], aui.RemoteError.INVALID_REQUEST)
        self.assertIsNone(reply["id"])

    def test_positional_params_are_invalid_params(self):
        reply = self._raw_exchange(
            b'{"jsonrpc":"2.0","id":1,"method":"actionui.listWindows","params":[1,2]}\n')
        self.assertEqual(reply["error"]["code"], aui.RemoteError.INVALID_PARAMS)

    def _raw_socket(self):
        raw = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        raw.settimeout(5.0)
        raw.connect(self.socket_path)
        self.addCleanup(raw.close)
        return raw

    def _read_json(self, raw):
        buffer = b""
        while b"\n" not in buffer:
            chunk = raw.recv(65536)
            self.assertTrue(chunk, "the host closed the connection without replying")
            buffer += chunk
        return json.loads(buffer.split(b"\n")[0].decode("utf-8"))

    def _raw_exchange(self, payload):
        raw = self._raw_socket()
        raw.sendall(payload)
        return self._read_json(raw)


class ScriptedHostTests(unittest.TestCase):
    """Replies a real host does not send, to pin down the client's tolerance rules."""

    def setUp(self):
        self.dir = _socket_dir()
        self.addCleanup(shutil.rmtree, self.dir, True)
        self.socket_path = os.path.join(self.dir, "s")

    def host(self, replies=(), hold=False, terminate=True):
        host = _ScriptedHost(self.socket_path, replies, hold=hold, terminate=terminate)
        self.addCleanup(host.stop)
        return host

    def client(self, timeout=5.0):
        connection = aui.Connection(self.socket_path, timeout=timeout)
        self.addCleanup(connection.close)
        return connection

    def test_a_line_that_is_not_our_reply_is_skipped(self):
        # PROTOCOL.md section 3: a client must ignore anything that is not a reply to it, so
        # that a later version can add server-initiated notifications.
        self.host(['{"jsonrpc":"2.0","method":"actionui.event","params":{"kind":"click"}}',
                   '{"jsonrpc":"2.0","id":1,"result":"ok"}'])
        self.assertEqual(self.client().call("actionui.hello"), "ok")

    def test_a_reply_to_another_id_is_skipped(self):
        self.host(['{"jsonrpc":"2.0","id":99,"result":"stale"}',
                   '{"jsonrpc":"2.0","id":1,"result":"ok"}'])
        self.assertEqual(self.client().call("actionui.hello"), "ok")

    def test_an_unreadable_line_resets_the_connection(self):
        self.host(["}{ not json"])
        connection = self.client()
        with self.assertRaises(aui.ProtocolError) as caught:
            connection.call("actionui.hello")
        self.assertIn("unreadable reply", str(caught.exception))
        self.assertFalse(connection.is_connected)

    def test_a_malformed_envelope_is_a_protocol_error(self):
        self.host(['{"id":1,"result":"ok"}'])           # no "jsonrpc"
        with self.assertRaises(aui.ProtocolError) as caught:
            self.client().call("actionui.hello")
        self.assertIn("malformed reply", str(caught.exception))

    def test_a_host_that_closes_before_replying_says_so(self):
        self.host([])
        with self.assertRaises(aui.ProtocolError) as caught:
            self.client().call("actionui.hello")
        self.assertIn("closed the connection", str(caught.exception))

    def test_a_silent_host_times_out_and_names_the_endpoint(self):
        self.host([], hold=True)
        connection = self.client(timeout=0.3)
        with self.assertRaises(aui.ProtocolError) as caught:
            connection.call("actionui.hello")
        self.assertIn("no reply from %s" % self.socket_path, str(caught.exception))
        self.assertFalse(connection.is_connected)

    def test_a_line_over_the_length_limit_drops_the_connection(self):
        # PROTOCOL.md section 2: a client that cannot hold a line drops the connection rather
        # than truncating it. Sent unterminated and held open, so the limit is what trips.
        original = aui.MAX_LINE_LENGTH
        aui.MAX_LINE_LENGTH = 1024
        self.addCleanup(setattr, aui, "MAX_LINE_LENGTH", original)
        self.host(["x" * 4096], hold=True, terminate=False)
        connection = self.client()
        with self.assertRaises(aui.ProtocolError) as caught:
            connection.call("actionui.hello")
        self.assertIn("exceeds", str(caught.exception))
        self.assertFalse(connection.is_connected)

    def test_a_main_thread_timeout_arrives_as_1005(self):
        # The one protocol code no in-process fake can produce.
        self.host(['{"jsonrpc":"2.0","id":1,"error":{"code":1005,"message":"main thread"}}'])
        with self.assertRaises(aui.RemoteError) as caught:
            self.client().call("actionui.hello")
        self.assertEqual(caught.exception.code, aui.RemoteError.MAIN_THREAD_UNAVAILABLE)

    def test_a_whole_batch_rejection_is_fanned_out_to_every_slot(self):
        self.host(['{"jsonrpc":"2.0","id":null,"error":{"code":-32700,"message":"Parse error"}}'])
        results = self.client().call_batch([("actionui.hello", {}), ("actionui.listWindows", {})])
        self.assertEqual(len(results), 2)
        for outcome in results:
            self.assertIsInstance(outcome, aui.RemoteError)
            self.assertEqual(outcome.code, aui.RemoteError.PARSE_ERROR)

    def test_a_batch_member_with_no_reply_gets_an_internal_error(self):
        self.host(['[{"jsonrpc":"2.0","id":1,"result":true}]'])
        results = self.client().call_batch([("actionui.hello", {}), ("actionui.listWindows", {})])
        self.assertIs(results[0], True)
        self.assertIsInstance(results[1], aui.RemoteError)
        self.assertEqual(results[1].code, aui.RemoteError.INTERNAL_ERROR)


# --- environment ----------------------------------------------------------------------------

class EnvironmentTests(FakeHostTestCase):

    def setUp(self):
        super().setUp()
        self.saved = {name: os.environ.get(name) for name in (aui.ENDPOINT_ENV, aui.WINDOW_ENV)}
        self.addCleanup(self._restore_environment)
        self.addCleanup(_forget_cached_connection, self.socket_path)

    def _restore_environment(self):
        for name, value in self.saved.items():
            if value is None:
                os.environ.pop(name, None)
            else:
                os.environ[name] = value

    def test_from_environment_uses_both_variables(self):
        os.environ[aui.ENDPOINT_ENV] = self.socket_path
        os.environ[aui.WINDOW_ENV] = WINDOW
        win = aui.Window.from_environment()
        self.assertEqual(win.uuid, WINDOW)
        self.assertEqual(win.get_element_info(), FIXTURE)

    def test_from_environment_without_a_window_names_the_variable(self):
        os.environ[aui.ENDPOINT_ENV] = self.socket_path
        os.environ.pop(aui.WINDOW_ENV, None)
        with self.assertRaises(aui.EndpointError) as caught:
            aui.Window.from_environment()
        self.assertIn(aui.WINDOW_ENV, str(caught.exception))

    def test_connect_without_an_endpoint_names_the_variable(self):
        os.environ.pop(aui.ENDPOINT_ENV, None)
        with self.assertRaises(aui.EndpointError) as caught:
            aui.connect()
        self.assertIn(aui.ENDPOINT_ENV, str(caught.exception))

    def test_connect_shares_one_connection_per_endpoint_and_retimes_it(self):
        first = aui.connect(self.socket_path, timeout=4.0)
        first.call("actionui.hello")
        second = aui.connect(self.socket_path, timeout=6.0)
        self.assertIs(first, second)
        self.assertEqual(first.timeout, 6.0)
        self.assertEqual(first._sock.gettimeout(), 6.0)


# --- the client as a command line tool --------------------------------------------------------

class ClientCLITests(FakeHostTestCase):
    """`python3 -m actionui_remote`, run as a child process against the fake host.

    Driven through subprocess rather than by calling main() so that argparse's own exits, the
    module's __main__ guard and what actually reaches stdout are all covered.
    """

    def _environment(self, **overrides):
        env = dict(os.environ)
        env.pop(aui.ENDPOINT_ENV, None)
        env.pop(aui.WINDOW_ENV, None)
        env.update(overrides)
        env["PYTHONDONTWRITEBYTECODE"] = "1"
        return env

    def cli(self, *arguments, **environment):
        return subprocess.run([sys.executable, "-m", "actionui_remote"] + list(arguments),
                              cwd=HERE, capture_output=True, timeout=60,
                              env=self._environment(**environment))

    def ok(self, *arguments, **environment):
        """Run a command that must succeed and return its stdout as text."""
        run = self.cli(*arguments, **environment)
        self.assertEqual(run.returncode, 0, run.stderr.decode("utf-8", "replace"))
        return run.stdout.decode("utf-8")

    def at(self, *arguments):
        """The same command with the endpoint and window given as flags."""
        return ("--endpoint", self.socket_path, "--window", WINDOW) + arguments

    # -- reads

    def test_hello(self):
        info = json.loads(self.ok(*self.at("hello")))
        self.assertEqual(info["protocolVersion"], aui.PROTOCOL_VERSION)
        self.assertEqual(info["windows"], [WINDOW])

    def test_windows_prints_one_uuid_per_line(self):
        self.fake.add_window("W-2")
        self.assertEqual(self.ok("--endpoint", self.socket_path, "windows").split(),
                         [WINDOW, "W-2"])

    def test_elements(self):
        self.assertEqual(json.loads(self.ok(*self.at("elements"))),
                         {str(view_id): name for view_id, name in FIXTURE.items()})

    def test_value_round_trip(self):
        self.assertEqual(self.ok(*self.at("set-value", "2", '"Ada"')), "",
                         "a setter that succeeded prints nothing")
        self.assertEqual(json.loads(self.ok(*self.at("get-value", "2"))), "Ada")

    def test_get_string_prints_the_text_itself_not_json(self):
        self.ok(*self.at("set-string", "2", "plain text"))
        self.assertEqual(self.ok(*self.at("get-string", "2")), "plain text\n")

    def test_get_string_of_an_unset_element_prints_an_empty_line(self):
        self.assertEqual(self.ok(*self.at("get-string", "2")), "\n")

    def test_a_content_type_and_a_view_part_reach_the_wire(self):
        self.ok(*self.at("set-string", "2", "# Hi", "--content-type", "markdown"))
        self.assertEqual(self.last_params()["contentType"], "markdown")
        self.ok(*self.at("get-value", "5", "--part", "2"))
        self.assertEqual(self.last_params()["viewPartID"], 2)
        self.ok(*self.at("get-string", "2", "--content-type", "plain", "--part", "3"))
        self.assertEqual(self.last_params()["contentType"], "plain")
        self.assertEqual(self.last_params()["viewPartID"], 3)

    def test_rows_round_trip(self):
        self.ok(*self.at("set-rows", "5", '[["a","b"],["c","d"]]'))
        self.assertEqual(json.loads(self.ok(*self.at("get-rows", "5"))), [["a", "b"], ["c", "d"]])

    def test_property_and_state_round_trip(self):
        self.ok(*self.at("set-property", "2", "disabled", "true"))
        self.assertIs(json.loads(self.ok(*self.at("get-property", "2", "disabled"))), True)
        self.ok(*self.at("set-state", "2", "count", "7"))
        self.assertEqual(json.loads(self.ok(*self.at("get-state", "2", "count"))), 7)

    def test_call_fills_in_the_window_when_one_is_given(self):
        self.assertEqual(json.loads(self.ok(*self.at("call", "actionui.getElementInfo"))),
                         {str(view_id): name for view_id, name in FIXTURE.items()})
        self.assertEqual(self.last_params()["window"], WINDOW)

    def test_call_without_a_window_takes_it_from_the_params(self):
        output = self.ok("--endpoint", self.socket_path, "call", "actionui.getValue",
                         json.dumps({"window": WINDOW, "viewID": 2}))
        self.assertEqual(json.loads(output), None)
        self.assertEqual(self.last_params()["window"], WINDOW)

    def test_an_explicit_window_in_the_params_wins_over_the_flag(self):
        output = self.ok("--endpoint", self.socket_path, "--window", "not-this-one",
                         "call", "actionui.getElementInfo", json.dumps({"window": WINDOW}))
        self.assertEqual(json.loads(output),
                         {str(view_id): name for view_id, name in FIXTURE.items()})
        self.assertEqual(self.last_params()["window"], WINDOW)

    def test_a_negative_element_id_needs_no_separator(self):
        # argparse's negative-number matcher lets -5 through as a value, so a negative id (the
        # engine assigns them) works either way.
        for arguments in (("get-value", "-5"), ("get-value", "--", "-5")):
            with self.subTest(arguments=arguments):
                run = self.cli(*self.at(*arguments))
                self.assertEqual(run.returncode, 1, run.stderr.decode("utf-8"))
                self.assertIn("-5", run.stderr.decode("utf-8"))

    def test_a_dash_argument_that_is_not_a_number_needs_the_separator(self):
        self.ok(*self.at("set-string", "2", "--", "-hello"))
        self.assertEqual(self.win.get_string(2), "-hello")

    # -- the environment contract

    def test_the_endpoint_and_window_come_from_the_environment(self):
        info = json.loads(self.ok("hello", **{aui.ENDPOINT_ENV: self.socket_path}))
        self.assertEqual(info["windows"], [WINDOW])
        environment = {aui.ENDPOINT_ENV: self.socket_path, aui.WINDOW_ENV: WINDOW}
        self.assertEqual(json.loads(self.ok("get-rows", "5", **environment)), None)

    # -- failures

    def test_a_host_error_exits_one_and_names_the_code(self):
        run = self.cli(*self.at("get-value", "99"))
        self.assertEqual(run.returncode, 1, "a host error is exit 1, the documented code")
        self.assertEqual(run.returncode, aui.EXIT_REMOTE_ERROR)
        self.assertIn("[%d]" % aui.RemoteError.UNKNOWN_VIEW, run.stderr.decode("utf-8"))
        self.assertEqual(run.stdout, b"")

    def test_no_endpoint_exits_three_and_names_the_variable(self):
        run = self.cli("hello")
        self.assertEqual(run.returncode, 3, "no host is exit 3, the documented code")
        self.assertEqual(run.returncode, aui.EXIT_NO_HOST)
        self.assertIn(aui.ENDPOINT_ENV, run.stderr.decode("utf-8"))

    def test_no_endpoint_is_no_host_even_for_a_command_that_needs_a_window(self):
        # The point of code 3: a handler running outside an ActionUI window can tell "no host"
        # from "no such element" without reading messages, whatever it asked for.
        run = self.cli("get-string", "2")
        self.assertEqual(run.returncode, aui.EXIT_NO_HOST)
        self.assertIn(aui.ENDPOINT_ENV, run.stderr.decode("utf-8"))

    def test_nothing_listening_exits_three(self):
        run = self.cli("--endpoint", os.path.join(self.dir, "absent"), "hello")
        self.assertEqual(run.returncode, aui.EXIT_NO_HOST)
        self.assertIn("no ActionUI host is listening", run.stderr.decode("utf-8"))

    def test_elements_needs_a_window(self):
        run = self.cli("--endpoint", self.socket_path, "elements")
        self.assertEqual(run.returncode, aui.EXIT_USAGE)
        self.assertIn(aui.WINDOW_ENV, run.stderr.decode("utf-8"))

    def test_a_timeout_names_the_seconds_it_waited(self):
        silent = _ScriptedHost(os.path.join(self.dir, "silent"), hold=True)
        self.addCleanup(silent.stop)
        run = self.cli("--endpoint", silent.path, "--timeout", "0.5", "hello")
        self.assertEqual(run.returncode, aui.EXIT_NO_HOST)
        self.assertIn("within 0.5 s", run.stderr.decode("utf-8"))

    def test_a_timeout_of_zero_or_less_is_refused(self):
        for value in ("0", "-1", "soon"):
            with self.subTest(timeout=value):
                run = self.cli("--endpoint", self.socket_path, "--timeout", value, "hello")
                self.assertEqual(run.returncode, aui.EXIT_USAGE)
                self.assertIn("timeout", run.stderr.decode("utf-8"))

    def test_a_missing_window_exits_two_and_says_how_to_give_one(self):
        run = self.cli("--endpoint", self.socket_path, "get-value", "2")
        self.assertEqual(run.returncode, aui.EXIT_USAGE)
        self.assertIn(aui.WINDOW_ENV, run.stderr.decode("utf-8"))

    def test_a_json_argument_that_is_not_json_exits_two(self):
        run = self.cli(*self.at("set-value", "2", "not json"))
        self.assertEqual(run.returncode, aui.EXIT_USAGE)
        self.assertIn("expected JSON", run.stderr.decode("utf-8"))

    def test_a_json_argument_of_the_wrong_shape_exits_two(self):
        # Valid JSON, but rows are arrays of arrays; the client refuses a string row.
        run = self.cli(*self.at("set-rows", "5", '["ab","cd"]'))
        self.assertEqual(run.returncode, aui.EXIT_USAGE)
        self.assertIn("not a string", run.stderr.decode("utf-8"))

    def test_call_with_positional_params_exits_two(self):
        run = self.cli(*self.at("call", "actionui.hello", "[1,2]"))
        self.assertEqual(run.returncode, aui.EXIT_USAGE)
        self.assertIn("named keys", run.stderr.decode("utf-8"))

    def test_a_closed_output_pipe_is_not_an_error(self):
        # `python3 -m actionui_remote get-rows 5 | head -1` is the idiom this tool exists for.
        # The rows are large enough that the write is still going when the reader disappears.
        self.win.set_rows(5, [["a" * 40, "b" * 40] for _ in range(4000)])
        read_fd, write_fd = os.pipe()
        process = subprocess.Popen(
            [sys.executable, "-m", "actionui_remote"] + list(self.at("get-rows", "5")),
            cwd=HERE, stdout=write_fd, stderr=subprocess.PIPE, env=self._environment())
        self.addCleanup(_reap, process)
        os.close(write_fd)
        os.close(read_fd)
        _, stderr = process.communicate(timeout=60)
        self.assertEqual(process.returncode, 0, stderr.decode("utf-8", "replace"))
        self.assertNotIn(b"Traceback", stderr)
        self.assertNotIn(b"BrokenPipeError", stderr)

    def test_an_interrupt_exits_quietly(self):
        silent = _ScriptedHost(os.path.join(self.dir, "quiet"), hold=True)
        self.addCleanup(silent.stop)
        process = subprocess.Popen(
            [sys.executable, "-m", "actionui_remote",
             "--endpoint", silent.path, "--timeout", "60", "hello"],
            cwd=HERE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=self._environment())
        self.addCleanup(_reap, process)
        # Interrupt it only once it is blocked waiting for the reply.
        self.assertTrue(_wait_for(lambda: bool(silent.received)), "the tool never sent a request")
        process.send_signal(signal.SIGINT)
        _, stderr = process.communicate(timeout=30)
        self.assertEqual(process.returncode, 130, stderr.decode("utf-8", "replace"))
        self.assertNotIn(b"Traceback", stderr)

    def test_a_non_integer_element_id_exits_two(self):
        run = self.cli(*self.at("get-value", "two"))
        self.assertEqual(run.returncode, aui.EXIT_USAGE)

    def test_no_command_exits_two(self):
        run = self.cli(*self.at())
        self.assertEqual(run.returncode, aui.EXIT_USAGE)
        self.assertIn("COMMAND", run.stderr.decode("utf-8"))


# --- the fake host as a command line tool -----------------------------------------------------

class FakeHostCLITests(unittest.TestCase):
    """The path OMC's omctest harness will use: the fake as a separate process."""

    def setUp(self):
        self.dir = _socket_dir()
        self.addCleanup(shutil.rmtree, self.dir, True)
        self.socket_path = os.path.join(self.dir, "s")
        self.log_path = os.path.join(self.dir, "log.jsonl")
        self.state_path = os.path.join(self.dir, "state.json")

    def test_serves_a_prepared_window_and_writes_its_log_and_state(self):
        process = subprocess.Popen(
            [sys.executable, "-m", "actionui_remote_testing",
             "--socket", self.socket_path, "--log", self.log_path, "--state", self.state_path,
             "--window", WINDOW, "--element", "%s:2:TextField" % WINDOW,
             "--host-name", "omctest", "--host-version", "5.3"],
            cwd=HERE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.addCleanup(_reap, process)
        self.assertTrue(_wait_for(lambda: os.path.exists(self.socket_path)),
                        "the fake host never created its socket")

        connection = aui.Connection(self.socket_path, timeout=5.0)
        self.addCleanup(connection.close)
        info = connection.call("actionui.hello")
        self.assertEqual(info["host"], {"name": "omctest", "version": "5.3"})
        self.assertEqual(info["windows"], [WINDOW])
        win = aui.Window(WINDOW, connection=connection)
        win.set_string(2, "from a child process")
        connection.close()

        process.terminate()
        # communicate rather than wait: wait alone deadlocks if the child ever fills a pipe.
        out, err = process.communicate(timeout=15)
        self.assertEqual(process.returncode, 0, (out + err).decode("utf-8", "replace"))

        with open(self.log_path, encoding="utf-8") as handle:
            logged = [json.loads(line) for line in handle if line.strip()]
        self.assertEqual([entry["method"] for entry in logged],
                         ["actionui.hello", "actionui.setValueString"])
        self.assertEqual(logged[1]["params"]["value"], "from a child process")

        with open(self.state_path, encoding="utf-8") as handle:
            state = json.load(handle)
        self.assertEqual(state[WINDOW]["values"]["2"], "from a child process")
        self.assertEqual(state[WINDOW]["elements"]["2"], "TextField")

    def test_a_malformed_element_specification_is_refused(self):
        process = subprocess.run(
            [sys.executable, "-m", "actionui_remote_testing",
             "--socket", self.socket_path, "--element", "W:notanumber:TextField"],
            cwd=HERE, capture_output=True, timeout=30)
        self.assertEqual(process.returncode, 2)
        self.assertIn(b"--element", process.stderr)


def _reap(process):
    if process.poll() is None:
        process.kill()
        process.wait(timeout=10)
    for stream in (process.stdout, process.stderr):
        if stream is not None:
            stream.close()


if __name__ == "__main__":
    unittest.main()
