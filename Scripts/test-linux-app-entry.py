#!/usr/bin/env python3
"""Tests for linux-app-entry.py, run as a program with XDG_DATA_HOME in a temporary folder, so
nothing reaches the user's own desktop. Runs on Linux and macOS.

Usage: python3 Scripts/test-linux-app-entry.py
"""

import os
import struct
import subprocess
import sys
import tempfile
import unittest

SCRIPT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "linux-app-entry.py")
SVG = '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64"/>\n'


def png_header(width, height):
    """The start of a PNG file, as far as its size: what the script reads."""
    return b"\x89PNG\r\n\x1a\n" + struct.pack(">I", 13) + b"IHDR" + struct.pack(">II", width, height) + b"\x08\x06\x00\x00\x00"


class LinuxAppEntryTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.data_home = os.path.join(self.temporary.name, "share")
        self.apps = os.path.join(self.temporary.name, "apps")
        os.makedirs(self.apps)

    def tearDown(self):
        self.temporary.cleanup()

    def app(self, name, info, files=None, program=True):
        """An app folder holding Info.json (written as given when a string), files, and an
        executable program named after the folder."""
        folder = os.path.join(self.apps, name)
        os.makedirs(folder)
        with open(os.path.join(folder, "Info.json"), "w", encoding="utf-8") as file:
            file.write(info)
        for file_name, content in (files or {}).items():
            with open(os.path.join(folder, file_name), "wb" if isinstance(content, bytes) else "w") as file:
                file.write(content)
        if program:
            path = os.path.join(folder, name[:-4] if name.endswith(".app") else name)
            with open(path, "w") as file:
                file.write("#!/bin/sh\n")
            os.chmod(path, 0o755)
        return folder

    def run_script(self, *arguments):
        environment = dict(os.environ, XDG_DATA_HOME=self.data_home)
        return subprocess.run([sys.executable, SCRIPT] + list(arguments), env=environment, capture_output=True, text=True)

    def entry(self, application_id):
        with open(os.path.join(self.data_home, "applications", application_id + ".desktop"), encoding="utf-8") as file:
            return file.read().splitlines()

    def test_an_app_with_an_svg_icon_is_installed(self):
        folder = self.app("My App.app", '{"applicationID": "org.example.MyApp", "name": "My App", "icon": "MyApp.svg", "summary": "Edits things", "categories": ["Utility", "Development"]}', {"MyApp.svg": SVG})
        result = self.run_script("install", folder)
        self.assertEqual(result.returncode, 0, result.stderr)
        lines = self.entry("org.example.MyApp")
        self.assertEqual(lines[0], "[Desktop Entry]")
        self.assertIn("Type=Application", lines)
        self.assertIn("Name=My App", lines)
        self.assertIn("Comment=Edits things", lines)
        self.assertIn('Exec="' + folder + '/My App"', lines, "the program, quoted for the space")
        self.assertIn("Path=" + folder, lines)
        self.assertIn("Icon=org.example.MyApp", lines)
        self.assertIn("Categories=Utility;Development;", lines)
        self.assertIn("StartupWMClass=org.example.MyApp", lines)
        self.assertTrue(os.path.isfile(os.path.join(self.data_home, "icons", "hicolor", "scalable", "apps", "org.example.MyApp.svg")))

    def test_a_png_icon_goes_to_its_size_folder(self):
        folder = self.app("Tool", '{"applicationID": "org.example.Tool", "icon": "icons/Tool.png"}', {})
        os.makedirs(os.path.join(folder, "icons"))
        with open(os.path.join(folder, "icons", "Tool.png"), "wb") as file:
            file.write(png_header(256, 256))
        result = self.run_script("install", folder)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(os.path.isfile(os.path.join(self.data_home, "icons", "hicolor", "256x256", "apps", "org.example.Tool.png")))
        self.assertIn("Icon=org.example.Tool", self.entry("org.example.Tool"))
        self.assertIn("Name=Tool", self.entry("org.example.Tool"), "the folder's name with no name in Info.json")

    def test_a_png_of_an_odd_size_is_named_by_its_path(self):
        folder = self.app("Odd", '{"applicationID": "org.example.Odd", "icon": "Odd.png"}', {"Odd.png": png_header(100, 100)})
        result = self.run_script("install", folder)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("100x100", result.stderr)
        self.assertIn("Icon=" + folder + "/Odd.png", self.entry("org.example.Odd"))

    def test_an_icon_that_is_no_file_is_a_theme_name(self):
        folder = self.app("Themed", '{"applicationID": "org.example.Themed", "icon": "accessories-text-editor"}')
        result = self.run_script("install", folder)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Icon=accessories-text-editor", self.entry("org.example.Themed"))

    def test_a_command_line_runs_in_the_app_folder(self):
        folder = self.app("PyApp", '{"applicationID": "org.example.PyApp", "name": ""}', program=False)
        result = self.run_script("install", folder, "--exec", "python3 PyApp.py %F")
        self.assertEqual(result.returncode, 0, result.stderr)
        lines = self.entry("org.example.PyApp")
        self.assertIn("Exec=python3 PyApp.py %F", lines)
        self.assertIn("Path=" + folder, lines)
        self.assertIn("Name=PyApp", lines, "an empty name counts as left out")
        self.assertIn("no icon", result.stderr)

    def test_no_program_and_no_command_line_is_refused(self):
        folder = self.app("Script", '{"applicationID": "org.example.Script"}', program=False)
        result = self.run_script("install", folder)
        self.assertEqual(result.returncode, 64)
        self.assertIn("--exec", result.stderr)

    def test_a_missing_or_invalid_application_id_is_refused(self):
        for name, info in (("NoID", '{"name": "x"}'), ("BadID", '{"applicationID": "no-dots"}'), ("Digit", '{"applicationID": "org.9lives.App"}'), ("NotJSON", "{")):
            folder = self.app(name, info)
            result = self.run_script("install", folder)
            self.assertEqual(result.returncode, 64, name)
        self.assertFalse(os.path.exists(os.path.join(self.data_home, "applications")), "nothing written")

    def test_uninstall_removes_the_entry_and_the_icon(self):
        folder = self.app("Gone", '{"applicationID": "org.example.Gone", "icon": "Gone.svg"}', {"Gone.svg": SVG})
        self.assertEqual(self.run_script("install", folder).returncode, 0)
        result = self.run_script("uninstall", folder)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(os.path.exists(os.path.join(self.data_home, "applications", "org.example.Gone.desktop")))
        self.assertFalse(os.path.exists(os.path.join(self.data_home, "icons", "hicolor", "scalable", "apps", "org.example.Gone.svg")))
        self.assertIn("nothing installed", self.run_script("uninstall", folder).stdout)

    def test_uninstall_takes_the_application_id_when_the_folder_is_gone(self):
        folder = self.app("Removed", '{"applicationID": "org.example.Removed", "icon": "Removed.svg"}', {"Removed.svg": SVG})
        self.assertEqual(self.run_script("install", folder).returncode, 0)
        result = self.run_script("uninstall", "org.example.Removed")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(os.path.exists(os.path.join(self.data_home, "applications", "org.example.Removed.desktop")))
        self.assertFalse(os.path.exists(os.path.join(self.data_home, "icons", "hicolor", "scalable", "apps", "org.example.Removed.svg")))

    def test_a_percent_sign_in_the_program_path_is_refused(self):
        folder = self.app("100%", '{"applicationID": "org.example.Percent"}')
        result = self.run_script("install", folder)
        self.assertEqual(result.returncode, 64)
        self.assertFalse(os.path.exists(os.path.join(self.data_home, "applications", "org.example.Percent.desktop")))

    def test_a_theme_name_icon_removes_an_earlier_copy(self):
        folder = self.app("Retheme", '{"applicationID": "org.example.Retheme", "icon": "Retheme.svg"}', {"Retheme.svg": SVG})
        self.assertEqual(self.run_script("install", folder).returncode, 0)
        with open(os.path.join(folder, "Info.json"), "w") as file:
            file.write('{"applicationID": "org.example.Retheme", "icon": "accessories-text-editor"}')
        self.assertEqual(self.run_script("install", folder).returncode, 0)
        self.assertFalse(os.path.exists(os.path.join(self.data_home, "icons", "hicolor", "scalable", "apps", "org.example.Retheme.svg")))
        self.assertIn("Icon=accessories-text-editor", self.entry("org.example.Retheme"))

    def test_a_new_icon_replaces_the_old_one(self):
        folder = self.app("Swap", '{"applicationID": "org.example.Swap", "icon": "Swap.png"}', {"Swap.png": png_header(128, 128), "Swap.svg": SVG})
        self.assertEqual(self.run_script("install", folder).returncode, 0)
        with open(os.path.join(folder, "Info.json"), "w") as file:
            file.write('{"applicationID": "org.example.Swap", "icon": "Swap.svg"}')
        self.assertEqual(self.run_script("install", folder).returncode, 0)
        theme = os.path.join(self.data_home, "icons", "hicolor")
        self.assertFalse(os.path.exists(os.path.join(theme, "128x128", "apps", "org.example.Swap.png")))
        self.assertTrue(os.path.isfile(os.path.join(theme, "scalable", "apps", "org.example.Swap.svg")))

    def test_a_refused_icon_leaves_the_installed_one(self):
        folder = self.app("Keep", '{"applicationID": "org.example.Keep", "icon": "Keep.svg"}', {"Keep.svg": SVG, "Keep.png": b"not a PNG"})
        self.assertEqual(self.run_script("install", folder).returncode, 0)
        installed = os.path.join(self.data_home, "icons", "hicolor", "scalable", "apps", "org.example.Keep.svg")
        for icon in ("Keep.png", "Misspelled.svg", "icons/Missing.png"):
            with open(os.path.join(folder, "Info.json"), "w") as file:
                file.write('{"applicationID": "org.example.Keep", "icon": "' + icon + '"}')
            result = self.run_script("install", folder)
            self.assertEqual(result.returncode, 64, icon)
            self.assertTrue(os.path.isfile(installed), icon)
        self.assertIn("Icon=org.example.Keep", self.entry("org.example.Keep"))


if __name__ == "__main__":
    unittest.main()
