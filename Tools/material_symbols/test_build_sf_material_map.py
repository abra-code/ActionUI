#!/usr/bin/env python3
"""
Unit tests for build_sf_material_map.py - the SF->Material embedded-map compiler.

Covers the pure transform (codepoint resolution, fill flag, weight handling,
score threshold, unresolved/rejected skips), the old-name aliases and the line
formatter.

Run:
    python3 test_build_sf_material_map.py
    python3 -m unittest -v
"""
from __future__ import annotations

import plistlib
import sys
import unittest
from pathlib import Path

_HERE = Path(__file__).parent
sys.path.insert(0, str(_HERE))

from build_sf_material_map import (  # noqa: E402
    parse_codepoints,
    build_entries,
    parse_aliases,
    add_alias_entries,
    format_lines,
    Entry,
    DEFAULT_MIN_SCORE,
)

# A tiny stand-in for MaterialSymbolsRounded.codepoints.
_CODEPOINTS = {
    "search": 0xEF7A,
    "delete": 0xE92E,
    "favorite": 0xE87D,
    "calendar_today": 0xE935,
}


def _wrap(rows: dict) -> dict:
    return {"_meta": {"x": 1}, "map": rows}


class ParseCodepointsTest(unittest.TestCase):
    def test_parses_name_and_hex(self):
        table = parse_codepoints("home e9b2\nsearch ef7a\n")
        self.assertEqual({"home": 0xE9B2, "search": 0xEF7A}, table)

    def test_skips_blank_and_malformed_and_non_hex(self):
        table = parse_codepoints("\n  \nbroken\nbad zzzz\nhome e9b2\n")
        self.assertEqual({"home": 0xE9B2}, table)

    def test_tolerates_extra_whitespace(self):
        self.assertEqual({"home": 0xE9B2}, parse_codepoints("  home    e9b2  \n"))


class BuildEntriesTest(unittest.TestCase):
    def test_resolves_codepoint_and_defaults(self):
        entries, stats, unresolved = build_entries(
            _wrap({"magnifyingglass": {"material": "search", "fill": False, "score": 95}}),
            _CODEPOINTS,
        )
        self.assertEqual([Entry("magnifyingglass", 0xEF7A, False, None)], entries)
        self.assertEqual(1, stats.emitted)
        self.assertEqual([], unresolved)

    def test_fill_true_is_carried(self):
        entries, stats, _ = build_entries(
            _wrap({"heart.fill": {"material": "favorite", "fill": True, "score": 90}}),
            _CODEPOINTS,
        )
        self.assertEqual([Entry("heart.fill", 0xE87D, True, None)], entries)
        self.assertEqual(1, stats.with_fill)

    def test_weight_override_carried_and_clamped_default_dropped(self):
        rows = {
            "a": {"material": "search", "weight": 600},   # kept
            "b": {"material": "delete", "weight": 400},   # default -> dropped
            "c": {"material": "favorite", "weight": 9000},  # clamped to 700
            "d": {"material": "calendar_today", "weight": True},  # bool -> ignored
        }
        entries, stats, _ = build_entries(_wrap(rows), _CODEPOINTS)
        by_name = {e.sf_name: e.weight for e in entries}
        self.assertEqual(600, by_name["a"])
        self.assertIsNone(by_name["b"])
        self.assertEqual(700, by_name["c"])
        self.assertIsNone(by_name["d"])
        self.assertEqual(2, stats.with_weight)  # a (600) and c (700)

    def test_min_score_filters_low_matches(self):
        rows = {
            "good": {"material": "search", "score": 88},
            "weak": {"material": "delete", "score": 40},
        }
        entries, stats, _ = build_entries(_wrap(rows), _CODEPOINTS, min_score=80)
        self.assertEqual(["good"], [e.sf_name for e in entries])
        self.assertEqual(1, stats.skipped_below_score)

    def test_default_floor_is_60_and_boundary_is_inclusive(self):
        # Product policy: keep score >= DEFAULT_MIN_SCORE, drop 59 and below.
        self.assertEqual(60, DEFAULT_MIN_SCORE)
        rows = {
            "at_floor":    {"material": "search", "score": 60},   # kept
            "below_floor": {"material": "delete", "score": 59},   # dropped
        }
        entries, stats, _ = build_entries(_wrap(rows), _CODEPOINTS, min_score=DEFAULT_MIN_SCORE)
        self.assertEqual(["at_floor"], [e.sf_name for e in entries])
        self.assertEqual(1, stats.skipped_below_score)

    def test_unresolved_material_name_is_skipped_and_sampled(self):
        entries, stats, unresolved = build_entries(
            _wrap({"x": {"material": "no_such_glyph", "score": 99}}),
            _CODEPOINTS,
        )
        self.assertEqual([], entries)
        self.assertEqual(1, stats.skipped_unresolved)
        self.assertEqual(["x -> no_such_glyph"], unresolved)

    def test_missing_or_rejected_material_is_skipped(self):
        rows = {
            "empty": {"material": "", "score": 99},
            "null": {"material": None, "score": 99},
            "rejected": {"material": "search", "reject": True, "score": 99},
        }
        entries, stats, _ = build_entries(_wrap(rows), _CODEPOINTS)
        self.assertEqual([], entries)
        self.assertEqual(3, stats.skipped_no_material)

    def test_entries_are_sorted_by_sf_name(self):
        rows = {
            "zebra": {"material": "search"},
            "alpha": {"material": "delete"},
        }
        entries, _, _ = build_entries(_wrap(rows), _CODEPOINTS)
        self.assertEqual(["alpha", "zebra"], [e.sf_name for e in entries])

    def test_accepts_bare_map_without_wrapper(self):
        entries, _, _ = build_entries({"a": {"material": "search"}}, _CODEPOINTS)
        self.assertEqual(["a"], [e.sf_name for e in entries])


class ParseAliasesTest(unittest.TestCase):
    def test_reads_a_binary_property_list(self):
        data = plistlib.dumps({"doc": "document", "mic": "microphone"}, fmt=plistlib.FMT_BINARY)
        self.assertEqual({"doc": "document", "mic": "microphone"}, parse_aliases(data))

    def test_skips_capitalized_placeholder_keys_and_non_strings(self):
        data = plistlib.dumps({
            "7F6042B6443143CB932E328C947DD2BE": "macmini.gen3",
            "7F6042B6443143CB932E328C947DD2BE.fill": "macmini.gen3.fill",
            "count": 3,
            "doc": "document",
        })
        self.assertEqual({"doc": "document"}, parse_aliases(data))

    def test_rejects_non_plist_and_non_dictionary(self):
        with self.assertRaises(ValueError):
            parse_aliases(b"not a plist")
        with self.assertRaises(ValueError):
            parse_aliases(b"<?xml version=\"1.0\"?><plist><dict><key>doc")
        with self.assertRaises(ValueError):
            parse_aliases(plistlib.dumps(["doc", "document"]))


class AddAliasEntriesTest(unittest.TestCase):
    _ENTRIES = [
        Entry("document", 0xE66D, False, 300),
        Entry("document.fill", 0xE66D, True, None),
        Entry("microphone", 0xE029, False, None),
    ]

    def test_old_name_copies_the_current_rows_axes(self):
        entries, added = add_alias_entries(self._ENTRIES, {"doc": "document", "doc.fill": "document.fill"})
        by_name = {e.sf_name: e for e in entries}
        self.assertEqual(Entry("doc", 0xE66D, False, 300), by_name["doc"])
        self.assertEqual(Entry("doc.fill", 0xE66D, True, None), by_name["doc.fill"])
        self.assertEqual(2, added)

    def test_old_name_with_its_own_row_keeps_it(self):
        entries, added = add_alias_entries(self._ENTRIES, {"microphone": "document"})
        self.assertEqual(self._ENTRIES, entries)
        self.assertEqual(0, added)

    def test_current_name_without_a_row_adds_nothing(self):
        entries, added = add_alias_entries(self._ENTRIES, {"star.slash.old": "star.slash"})
        self.assertEqual(self._ENTRIES, entries)
        self.assertEqual(0, added)

    def test_newer_current_name_copies_its_old_names_row(self):
        entries, added = add_alias_entries(self._ENTRIES, {"microphone": "microphone.new", "mic": "microphone.new"})
        by_name = {e.sf_name: e for e in entries}
        self.assertEqual(Entry("microphone.new", 0xE029, False, None), by_name["microphone.new"])
        self.assertEqual(Entry("mic", 0xE029, False, None), by_name["mic"])
        self.assertEqual(2, added)

    def test_newer_current_name_with_differing_old_rows_gets_none(self):
        entries, added = add_alias_entries(self._ENTRIES, {"microphone": "merged", "document": "merged"})
        self.assertEqual(self._ENTRIES, entries)
        self.assertEqual(0, added)

    def test_follows_an_alias_of_an_alias_and_stops_at_a_loop(self):
        aliases = {"mic.old": "mic", "mic": "microphone", "a": "b", "b": "a"}
        entries, added = add_alias_entries(self._ENTRIES, aliases)
        names = [e.sf_name for e in entries]
        self.assertIn("mic.old", names)
        self.assertIn("mic", names)
        self.assertNotIn("a", names)
        self.assertEqual(2, added)

    def test_result_is_sorted(self):
        entries, _ = add_alias_entries(self._ENTRIES, {"aaa": "microphone"})
        self.assertEqual(sorted(e.sf_name for e in entries), [e.sf_name for e in entries])


class FormatLinesTest(unittest.TestCase):
    def test_default_row_is_name_and_hex_only(self):
        self.assertEqual(["search ef7a"], format_lines([Entry("search", 0xEF7A, False, None)]))

    def test_fill_and_weight_are_bare_integers(self):
        # Bare numbers, disambiguated by range: 1 => fill, 100..700 => weight.
        lines = format_lines([
            Entry("heart.fill", 0xE87D, True, None),
            Entry("gear", 0xE8B8, False, 600),
            Entry("both.fill", 0xABCD, True, 500),
        ])
        self.assertEqual(
            ["heart.fill e87d 1", "gear e8b8 600", "both.fill abcd 1 500"],
            lines,
        )


if __name__ == "__main__":
    unittest.main()
