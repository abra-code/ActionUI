#!/usr/bin/env python3
"""Tests for linux-app-entry.py, run as a program with XDG_DATA_HOME in a temporary folder, so
nothing reaches the user's own desktop. Runs on Linux and macOS.

Usage: python3 Scripts/test-linux-app-entry.py
"""

import os
import plistlib
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

    def write_info(self, path, info):
        """Info.plist at path: a dictionary written as a property list, a string as given."""
        if isinstance(info, dict):
            with open(path, "wb") as file:
                plistlib.dump(info, file)
        else:
            with open(path, "w", encoding="utf-8") as file:
                file.write(info)

    def app(self, name, info, files=None, program=True):
        """A flat app folder holding Info.plist, files, and an executable program named after the
        folder."""
        folder = os.path.join(self.apps, name)
        os.makedirs(folder)
        self.write_info(os.path.join(folder, "Info.plist"), info)
        for file_name, content in (files or {}).items():
            with open(os.path.join(folder, file_name), "wb" if isinstance(content, bytes) else "w") as file:
                file.write(content)
        if program:
            self.executable(os.path.join(folder, name[:-4] if name.endswith(".app") else name))
        return folder

    def contents_app(self, name, info, resources=None, programs=("Applet",)):
        """An app folder in the macOS layout: Contents/Info.plist, Contents/Resources holding
        resources, and the executables programs in Contents/Linux."""
        folder = os.path.join(self.apps, name)
        contents = os.path.join(folder, "Contents")
        os.makedirs(os.path.join(contents, "Resources"))
        os.makedirs(os.path.join(contents, "Linux"))
        self.write_info(os.path.join(contents, "Info.plist"), info)
        for file_name, content in (resources or {}).items():
            with open(os.path.join(contents, "Resources", file_name), "wb" if isinstance(content, bytes) else "w") as file:
                file.write(content)
        for program in programs:
            self.executable(os.path.join(contents, "Linux", program))
        return folder

    def executable(self, path):
        with open(path, "w") as file:
            file.write("#!/bin/sh\n")
        os.chmod(path, 0o755)

    def run_script(self, *arguments, tools=None):
        """The script's result; tools, a folder put first on PATH, stands in for desktop tools."""
        environment = dict(os.environ, XDG_DATA_HOME=self.data_home)
        if tools is not None:
            environment["PATH"] = tools + os.pathsep + environment.get("PATH", "")
        return subprocess.run([sys.executable, SCRIPT] + list(arguments), env=environment, capture_output=True, text=True)

    def entry(self, application_id):
        with open(os.path.join(self.data_home, "applications", application_id + ".desktop"), encoding="utf-8") as file:
            return file.read().splitlines()

    def theme_file(self, *parts):
        return os.path.join(self.data_home, "icons", "hicolor", *parts)

    def test_an_app_with_an_svg_icon_is_installed(self):
        folder = self.app("My App.app", {"CFBundleIdentifier": "org.example.MyApp", "CFBundleName": "MyApp", "CFBundleDisplayName": "My App",
                                         "CFBundleIconFile": "MyApp", "LinuxDesktopComment": "Edits things",
                                         "LinuxDesktopCategories": ["Utility", "Development"]}, {"MyApp.svg": SVG, "MyApp.icns": b"icns"})
        result = self.run_script("install", folder)
        self.assertEqual(result.returncode, 0, result.stderr)
        lines = self.entry("org.example.MyApp")
        self.assertEqual(lines[0], "[Desktop Entry]")
        self.assertIn("Type=Application", lines)
        self.assertIn("Name=My App", lines, "the display name before the name")
        self.assertIn("Comment=Edits things", lines)
        self.assertIn('Exec="' + folder + '/My App" %U', lines, "the program, quoted for the space, given the files it opens")
        self.assertIn("TryExec=" + folder + "/My App", lines, "the entry goes once the program is gone")
        self.assertIn("Path=" + folder, lines)
        self.assertIn("Icon=org.example.MyApp", lines)
        self.assertIn("Categories=Utility;Development;", lines)
        self.assertIn("StartupWMClass=org.example.MyApp", lines)
        self.assertTrue(os.path.isfile(self.theme_file("scalable", "apps", "org.example.MyApp.svg")), "the SVG, not the .icns")

    def test_an_app_in_the_macos_layout_is_installed(self):
        folder = self.contents_app("Applet.app", {"CFBundleIdentifier": "org.example.Applet", "CFBundleName": "Applet",
                                                  "CFBundleExecutable": "Applet", "CFBundleIconFile": "AppIcon"},
                                   {"AppIcon.png": png_header(512, 512), "AppIcon.icns": b"icns"}, programs=("Applet", "helper"))
        result = self.run_script("install", folder)
        self.assertEqual(result.returncode, 0, result.stderr)
        lines = self.entry("org.example.Applet")
        self.assertIn("Exec=" + folder + "/Contents/Linux/Applet %U", lines, "CFBundleExecutable in Contents/Linux")
        self.assertFalse(any(line.startswith("MimeType=") for line in lines), "no document types, no MimeType")
        self.assertIn("Name=Applet", lines)
        self.assertIn("Icon=org.example.Applet", lines)
        self.assertTrue(os.path.isfile(self.theme_file("512x512", "apps", "org.example.Applet.png")))
        self.assertEqual(self.run_script("uninstall", folder).returncode, 0)
        self.assertFalse(os.path.exists(os.path.join(self.data_home, "applications", "org.example.Applet.desktop")))

    def test_a_missing_cfbundleexecutable_program_is_refused(self):
        folder = self.contents_app("Broken.app", {"CFBundleIdentifier": "org.example.Broken", "CFBundleExecutable": "Gone"})
        result = self.run_script("install", folder)
        self.assertEqual(result.returncode, 64)
        self.assertIn("CFBundleExecutable Gone", result.stderr)

    def test_a_png_icon_goes_to_its_size_folder(self):
        folder = self.app("Tool", {"CFBundleIdentifier": "org.example.Tool", "CFBundleIconFile": "Tool.png"}, {"Tool.png": png_header(256, 256)})
        result = self.run_script("install", folder)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(os.path.isfile(self.theme_file("256x256", "apps", "org.example.Tool.png")))
        self.assertIn("Icon=org.example.Tool", self.entry("org.example.Tool"))
        self.assertIn("Name=Tool", self.entry("org.example.Tool"), "the folder's name with no name in Info.plist")

    def test_a_png_of_an_odd_size_is_named_by_its_path(self):
        folder = self.app("Odd", {"CFBundleIdentifier": "org.example.Odd", "CFBundleIconFile": "Odd"}, {"Odd.png": png_header(100, 100)})
        result = self.run_script("install", folder)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("100x100", result.stderr)
        self.assertIn("Icon=" + folder + "/Odd.png", self.entry("org.example.Odd"))

    def test_an_icns_alone_gives_an_entry_with_the_generic_icon(self):
        # A bundle made on macOS, or a new applet before its first build: the entry is made, with a
        # warning, and an earlier install's icon copy goes, as the entry no longer names it.
        folder = self.app("MacOnly", {"CFBundleIdentifier": "org.example.MacOnly", "CFBundleIconFile": "MacOnly"}, {"MacOnly.svg": SVG})
        self.assertEqual(self.run_script("install", folder).returncode, 0)
        os.remove(os.path.join(folder, "MacOnly.svg"))
        with open(os.path.join(folder, "MacOnly.icns"), "wb") as file:
            file.write(b"icns")
        result = self.run_script("install", folder)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("export a PNG or an SVG", result.stderr)
        self.assertFalse(any(line.startswith("Icon=") for line in self.entry("org.example.MacOnly")))
        self.assertFalse(os.path.exists(self.theme_file("scalable", "apps", "org.example.MacOnly.svg")))

    def test_a_command_line_runs_in_the_app_folder(self):
        folder = self.app("PyApp", {"CFBundleIdentifier": "org.example.PyApp", "CFBundleDisplayName": ""}, program=False)
        result = self.run_script("install", folder, "--exec", "python3 PyApp.py %F")
        self.assertEqual(result.returncode, 0, result.stderr)
        lines = self.entry("org.example.PyApp")
        self.assertIn("Exec=python3 PyApp.py %F", lines)
        self.assertFalse(any(line.startswith("TryExec=") for line in lines), "a command line of the user's has no TryExec")
        self.assertIn("Path=" + folder, lines)
        self.assertIn("Name=PyApp", lines, "an empty name counts as left out")
        self.assertIn("no icon", result.stderr)

    def test_no_program_and_no_command_line_is_refused(self):
        folder = self.app("Script", {"CFBundleIdentifier": "org.example.Script"}, program=False)
        result = self.run_script("install", folder)
        self.assertEqual(result.returncode, 64)
        self.assertIn("--exec", result.stderr)

    def test_a_missing_or_invalid_info_plist_is_refused(self):
        cases = (("NoID", {"CFBundleName": "x"}), ("BadID", {"CFBundleIdentifier": "no-dots"}),
                 ("Digit", {"CFBundleIdentifier": "org.9lives.App"}), ("NotPlist", "{"),
                 ("BadXML", "<?xml version=\"1.0\"?><plist version=\"1.0\"><dict><key>CFBundleIdentifier</key>"),
                 ("WrongType", {"CFBundleIdentifier": "org.example.Wrong", "CFBundleName": 5}),
                 ("BadCategories", {"CFBundleIdentifier": "org.example.Cat", "LinuxDesktopCategories": "Utility"}))
        for name, info in cases:
            folder = self.app(name, info)
            result = self.run_script("install", folder)
            self.assertEqual(result.returncode, 64, name)
        empty = os.path.join(self.apps, "Empty")
        os.makedirs(empty)
        self.assertEqual(self.run_script("install", empty).returncode, 64, "no Info.plist")
        self.assertFalse(os.path.exists(os.path.join(self.data_home, "applications")), "nothing written")

    def test_uninstall_removes_the_entry_and_the_icon(self):
        folder = self.app("Gone", {"CFBundleIdentifier": "org.example.Gone", "CFBundleIconFile": "Gone"}, {"Gone.svg": SVG})
        self.assertEqual(self.run_script("install", folder).returncode, 0)
        result = self.run_script("uninstall", folder)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(os.path.exists(os.path.join(self.data_home, "applications", "org.example.Gone.desktop")))
        self.assertFalse(os.path.exists(self.theme_file("scalable", "apps", "org.example.Gone.svg")))
        self.assertIn("nothing installed", self.run_script("uninstall", folder).stdout)

    def test_uninstall_takes_the_application_id_when_the_folder_is_gone(self):
        folder = self.app("Removed", {"CFBundleIdentifier": "org.example.Removed", "CFBundleIconFile": "Removed"}, {"Removed.svg": SVG})
        self.assertEqual(self.run_script("install", folder).returncode, 0)
        result = self.run_script("uninstall", "org.example.Removed")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(os.path.exists(os.path.join(self.data_home, "applications", "org.example.Removed.desktop")))
        self.assertFalse(os.path.exists(self.theme_file("scalable", "apps", "org.example.Removed.svg")))

    def test_a_percent_sign_in_the_program_path_is_refused(self):
        folder = self.app("100%", {"CFBundleIdentifier": "org.example.Percent"})
        result = self.run_script("install", folder)
        self.assertEqual(result.returncode, 64)
        self.assertFalse(os.path.exists(os.path.join(self.data_home, "applications", "org.example.Percent.desktop")))

    def test_no_icon_removes_an_earlier_copy(self):
        folder = self.app("Retheme", {"CFBundleIdentifier": "org.example.Retheme", "CFBundleIconFile": "Retheme"}, {"Retheme.svg": SVG})
        self.assertEqual(self.run_script("install", folder).returncode, 0)
        self.write_info(os.path.join(folder, "Info.plist"), {"CFBundleIdentifier": "org.example.Retheme"})
        self.assertEqual(self.run_script("install", folder).returncode, 0)
        self.assertFalse(os.path.exists(self.theme_file("scalable", "apps", "org.example.Retheme.svg")))
        self.assertFalse(any(line.startswith("Icon=") for line in self.entry("org.example.Retheme")))

    def test_a_new_icon_replaces_the_old_one(self):
        folder = self.app("Swap", {"CFBundleIdentifier": "org.example.Swap", "CFBundleIconFile": "Swap.png"}, {"Swap.png": png_header(128, 128), "Swap.svg": SVG})
        self.assertEqual(self.run_script("install", folder).returncode, 0)
        self.write_info(os.path.join(folder, "Info.plist"), {"CFBundleIdentifier": "org.example.Swap", "CFBundleIconFile": "Swap.svg"})
        self.assertEqual(self.run_script("install", folder).returncode, 0)
        self.assertFalse(os.path.exists(self.theme_file("128x128", "apps", "org.example.Swap.png")))
        self.assertTrue(os.path.isfile(self.theme_file("scalable", "apps", "org.example.Swap.svg")))

    def mime_line(self, application_id):
        lines = [line for line in self.entry(application_id) if line.startswith("MimeType=")]
        return lines[0] if lines else None

    def test_an_app_that_opens_bundles_is_offered_for_folders(self):
        # AppletBuilder's document types: bundles by identifier and by extension, all folders on Linux
        types = [{"CFBundleTypeExtensions": ["app", "omc", "droplet", "applet"], "CFBundleTypeRole": "Viewer",
                  "LSItemContentTypes": ["com.apple.application-bundle", "com.apple.bundle", "com.apple.package"]}]
        folder = self.app("Builder.app", {"CFBundleIdentifier": "org.example.Builder", "CFBundleDocumentTypes": types})
        result = self.run_script("install", folder)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.mime_line("org.example.Builder"), "MimeType=inode/directory;", "once, however many say it")
        self.assertNotIn("no MIME type known", result.stderr, "the unknown extensions are covered by the identifiers")

    def test_any_file_and_legacy_file_types_list_nothing(self):
        # The applet templates: "*" (any file) is not listed, or the app would become the default
        # for untyped files; CFBundleTypeOSTypes (legacy) are not read. Neither is reported.
        folder = self.app("Droplet", {"CFBundleIdentifier": "org.example.Droplet", "CFBundleDocumentTypes": [
            {"CFBundleTypeExtensions": ["*"], "CFBundleTypeOSTypes": ["****"], "CFBundleTypeRole": "Viewer"},
            {"CFBundleTypeOSTypes": ["fold"], "CFBundleTypeRole": "Viewer"}]})
        result = self.run_script("install", folder)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIsNone(self.mime_line("org.example.Droplet"))
        self.assertNotIn("no MIME type known", result.stderr)

    def test_url_schemes_are_listed_as_scheme_handlers(self):
        folder = self.app("Linked", {"CFBundleIdentifier": "org.example.Linked", "CFBundleURLTypes": [
            {"CFBundleURLName": "Linked", "CFBundleURLSchemes": ["Applet-Builder", "file"]}, {"CFBundleURLSchemes": ["x.y+z-1"]}],
            "CFBundleDocumentTypes": [{"LSItemContentTypes": ["public.folder"]}]})
        result = self.run_script("install", folder)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.mime_line("org.example.Linked"),
                         "MimeType=inode/directory;x-scheme-handler/applet-builder;x-scheme-handler/x.y+z-1;",
                         "lowercased; file is no scheme an app handles")
        for bad in ({"CFBundleURLTypes": "applet"}, {"CFBundleURLTypes": [{"CFBundleURLSchemes": ["1abc"]}]},
                    {"CFBundleURLTypes": [{"CFBundleURLSchemes": ["a b"]}]}, {"CFBundleURLTypes": [{"CFBundleURLSchemes": "abc"}]}):
            self.write_info(os.path.join(folder, "Info.plist"), dict({"CFBundleIdentifier": "org.example.Linked"}, **bad))
            self.assertEqual(self.run_script("install", folder).returncode, 64, str(bad))

    def test_types_from_every_key_in_order_and_role_none_left_out(self):
        folder = self.app("Viewer", {"CFBundleIdentifier": "org.example.Viewer", "LinuxMimeTypes": ["application/x-example", "text/plain"],
                                     "CFBundleDocumentTypes": [
                                         {"CFBundleTypeMIMETypes": ["text/x-log"], "LSItemContentTypes": ["public.plain-text", "com.adobe.pdf"],
                                          "CFBundleTypeExtensions": ["png", ".MD"], "CFBundleTypeRole": "Editor"},
                                         {"CFBundleTypeExtensions": ["zip"], "CFBundleTypeRole": "None"}]})
        result = self.run_script("install", folder)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.mime_line("org.example.Viewer"),
                         "MimeType=text/x-log;text/plain;application/pdf;image/png;text/markdown;application/x-example;")

    def test_an_unknown_type_is_said_and_left_out(self):
        folder = self.app("Odd", {"CFBundleIdentifier": "org.example.OddTypes", "CFBundleDocumentTypes": [
            {"CFBundleTypeExtensions": ["zzqqx"], "LSItemContentTypes": ["com.example.nothing"]}]})
        result = self.run_script("install", folder)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("no MIME type known for com.example.nothing, .zzqqx", result.stderr)
        self.assertIsNone(self.mime_line("org.example.OddTypes"))

    def test_a_compressed_extension_is_not_its_uncompressed_type(self):
        # mimetypes gives tgz as application/x-tar (with an encoding); the desktop has its own type
        folder = self.app("Packed", {"CFBundleIdentifier": "org.example.Packed", "CFBundleDocumentTypes": [
            {"CFBundleTypeExtensions": ["tgz", "gz", "svgz"]}, {"CFBundleTypeExtensions": ["bz2", "tar.bz2"]}]})
        result = self.run_script("install", folder)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.mime_line("org.example.Packed"), "MimeType=application/x-compressed-tar;application/gzip;image/svg+xml-compressed;")
        self.assertIn("no MIME type known for .bz2, .tar.bz2", result.stderr)

    def test_the_desktop_database_is_updated_on_install_and_uninstall(self):
        tools = os.path.join(self.temporary.name, "tools")
        os.makedirs(tools)
        log = os.path.join(self.temporary.name, "update-desktop-database.log")
        with open(os.path.join(tools, "update-desktop-database"), "w") as file:
            file.write('#!/bin/sh\nprintf "%s\\n" "$*" >> "' + log + '"\n')
        os.chmod(os.path.join(tools, "update-desktop-database"), 0o755)
        folder = self.app("Listed", {"CFBundleIdentifier": "org.example.Listed", "CFBundleDocumentTypes": [{"LSItemContentTypes": ["public.folder"]}]})
        applications = os.path.join(self.data_home, "applications")
        self.assertEqual(self.run_script("install", folder, tools=tools).returncode, 0)
        self.assertEqual(self.run_script("uninstall", folder, tools=tools).returncode, 0)
        self.assertEqual(self.run_script("uninstall", folder, tools=tools).returncode, 0, "nothing left to remove")
        with open(log) as file:
            self.assertEqual(file.read().splitlines(), ["--quiet " + applications] * 2, "after install and the uninstall that removed the entry")

    def test_a_wildcard_type_is_said_and_left_out(self):
        folder = self.app("Wild", {"CFBundleIdentifier": "org.example.Wild", "CFBundleDocumentTypes": [
            {"CFBundleTypeMIMETypes": ["image/*", "image/png"]}]})
        result = self.run_script("install", folder)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("image/* is left out", result.stderr)
        self.assertEqual(self.mime_line("org.example.Wild"), "MimeType=image/png;")

    def test_malformed_document_types_are_refused_and_leave_the_entry(self):
        folder = self.app("Typed", {"CFBundleIdentifier": "org.example.Typed", "CFBundleDocumentTypes": [{"LSItemContentTypes": ["public.folder"]}]})
        self.assertEqual(self.run_script("install", folder).returncode, 0)
        cases = ({"CFBundleDocumentTypes": "public.folder"}, {"CFBundleDocumentTypes": ["public.folder"]},
                 {"CFBundleDocumentTypes": [{"CFBundleTypeExtensions": "txt"}]}, {"LinuxMimeTypes": "text/plain"},
                 {"LinuxMimeTypes": ["text plain"]}, {"CFBundleDocumentTypes": [{"CFBundleTypeMIMETypes": ["text/plain;x"]}]})
        for case in cases:
            self.write_info(os.path.join(folder, "Info.plist"), dict({"CFBundleIdentifier": "org.example.Typed"}, **case))
            result = self.run_script("install", folder)
            self.assertEqual(result.returncode, 64, str(case))
            self.assertEqual(self.mime_line("org.example.Typed"), "MimeType=inode/directory;", str(case))
        self.assertEqual(self.run_script("uninstall", folder).returncode, 0, "a bad document type does not stop an uninstall")

    def test_a_refused_icon_leaves_the_installed_one(self):
        folder = self.app("Keep", {"CFBundleIdentifier": "org.example.Keep", "CFBundleIconFile": "Keep.svg"}, {"Keep.svg": SVG, "Bad.png": b"not a PNG"})
        self.assertEqual(self.run_script("install", folder).returncode, 0)
        installed = self.theme_file("scalable", "apps", "org.example.Keep.svg")
        for icon in ("Bad.png", "icons/Missing.png"):
            self.write_info(os.path.join(folder, "Info.plist"), {"CFBundleIdentifier": "org.example.Keep", "CFBundleIconFile": icon})
            result = self.run_script("install", folder)
            self.assertEqual(result.returncode, 64, icon)
            self.assertTrue(os.path.isfile(installed), icon)
        self.assertIn("Icon=org.example.Keep", self.entry("org.example.Keep"))


if __name__ == "__main__":
    unittest.main()
