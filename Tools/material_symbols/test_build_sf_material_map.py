#!/usr/bin/env python3
"""
Unit tests for build_sf_material_map.py - the SF->Material embedded-map compiler.

Covers the pure transform (codepoint resolution, fill flag, weight handling,
score threshold, unresolved/rejected skips) and the line formatter.

Run:
    python3 test_build_sf_material_map.py
    python3 -m unittest -v
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

_HERE = Path(__file__).parent
sys.path.insert(0, str(_HERE))

from build_sf_material_map import (  # noqa: E402
    parse_codepoints,
    build_entries,
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
