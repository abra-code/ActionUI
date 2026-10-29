#!/usr/bin/env python3
"""Adds an ActionUI app to the Linux desktop's app list (GNOME's Apps, KDE's launcher and others),
or takes it off, for the current user.

The app folder's Info.json gives the application ID, name and icon, as the ActionUI runtime reads
them, and optionally a summary and categories for the entry:

    {"applicationID": "org.example.MyApp", "name": "My App", "icon": "MyApp.svg",
     "summary": "Edits my things", "categories": ["Utility"]}

install writes $XDG_DATA_HOME/applications/<applicationID>.desktop (XDG_DATA_HOME defaults to
~/.local/share). The desktop matches the app's windows to that entry by the application ID, so the
dock shows the entry's name and icon. The icon is copied into the user's hicolor icon theme as
<applicationID>.svg (scalable) or .png (its own size), and the entry names it by the ID. A PNG of a
size the theme has no folder for is named by its path in the app folder instead.

Usage:
    linux-app-entry.py install <app folder> [--exec <command line>]
    linux-app-entry.py uninstall <app folder | application ID>

--exec: the entry's command line, quoted as the Desktop Entry Specification quotes Exec arguments
(an argument with spaces in double quotes; field codes such as %f kept), run in the app folder:
for a Python or Node.js app, such as 'python3 MyApp.py'. Without it, the entry runs the app
folder's program: the executable file named after the folder (MyApp for MyApp.app), else the only
executable file in it.

uninstall takes the application ID itself when the app folder is gone.

Exit status: 0 done, 1 a step failed, 64 bad arguments or Info.json.
"""

import json
import os
import shutil
import struct
import subprocess
import sys

# The square sizes the hicolor theme has an apps folder for.
HICOLOR_SIZES = (16, 22, 24, 32, 36, 48, 64, 72, 96, 128, 192, 256, 512)


class UsageError(Exception):
    pass


def fail(message, status=1):
    print("linux-app-entry: " + message, file=sys.stderr)
    sys.exit(status)


def data_home():
    value = os.environ.get("XDG_DATA_HOME", "")
    if os.path.isabs(value):
        return value
    return os.path.join(os.path.expanduser("~"), ".local", "share")


def is_valid_application_id(value):
    """GLib's rules (g_application_id_is_valid): at most 255 characters, two or more elements
    separated by dots, each of ASCII letters, digits, "_" and "-", none starting with a digit."""
    if not value or len(value) > 255:
        return False
    elements = value.split(".")
    if len(elements) < 2:
        return False
    for element in elements:
        if not element or element[0].isdigit():
            return False
        for character in element:
            if not (character.isascii() and (character.isalnum() or character in "_-")):
                return False
    return True


def read_info(folder):
    """Info.json in folder, with its keys checked; an empty string counts as left out."""
    path = os.path.join(folder, "Info.json")
    try:
        with open(path, encoding="utf-8") as file:
            info = json.load(file)
    except FileNotFoundError:
        raise UsageError(path + " is missing; it gives the application ID the entry is named after")
    except (OSError, ValueError) as error:
        raise UsageError("could not read " + path + ": " + str(error))
    if not isinstance(info, dict):
        raise UsageError(path + " is not a JSON object")
    for key in ("applicationID", "name", "icon", "summary"):
        value = info.get(key)
        if value is not None and not isinstance(value, str):
            raise UsageError(path + ": " + key + " is not a string")
        if value == "":
            info.pop(key)
    categories = info.get("categories", [])
    if not isinstance(categories, list) or not all(isinstance(item, str) for item in categories):
        raise UsageError(path + ": categories is not a list of strings")
    application_id = info.get("applicationID")
    if application_id is None:
        raise UsageError(path + " has no applicationID")
    if not is_valid_application_id(application_id):
        raise UsageError(path + ": '" + application_id + "' is not a valid application ID (reverse DNS, such as org.example.MyApp)")
    return info


def default_program(folder):
    """The folder's executable file named after it, else its only executable file."""
    base = os.path.basename(os.path.normpath(folder))
    named = os.path.join(folder, base[:-4] if base.endswith(".app") else base)
    if os.path.isfile(named) and os.access(named, os.X_OK):
        return named
    executables = []
    for name in sorted(os.listdir(folder)):
        path = os.path.join(folder, name)
        if os.path.isfile(path) and os.access(path, os.X_OK) and not name.endswith(".so"):
            executables.append(path)
    if len(executables) == 1:
        return executables[0]
    if not executables:
        raise UsageError("no executable file in " + folder + "; give the command line with --exec")
    raise UsageError("more than one executable file in " + folder + "; give the command line with --exec")


def quote_exec_argument(argument):
    """An argument of an entry's Exec line, quoted as the Desktop Entry Specification asks."""
    reserved = " \t\n\"'\\><~|&;$*?#()`"
    if argument and not any(character in reserved for character in argument):
        return argument.replace("%", "%%")
    escaped = argument
    for character in ("\\", "\"", "`", "$"):
        escaped = escaped.replace(character, "\\" + character)
    return "\"" + escaped.replace("%", "%%") + "\""


def escape_value(value):
    """A string value of a desktop entry key."""
    return value.replace("\\", "\\\\").replace("\n", "\\n").replace("\t", "\\t").replace("\r", "\\r")


def png_size(path):
    """(width, height) of a PNG file, else None."""
    with open(path, "rb") as file:
        header = file.read(24)
    if len(header) < 24 or header[:8] != b"\x89PNG\r\n\x1a\n" or header[12:16] != b"IHDR":
        return None
    return struct.unpack(">II", header[16:24])


def icon_files(application_id):
    """The icon files install may have put in the user's hicolor theme for application_id."""
    theme = os.path.join(data_home(), "icons", "hicolor")
    candidates = [os.path.join(theme, "scalable", "apps", application_id + ".svg")]
    candidates += [os.path.join(theme, "%dx%d" % (size, size), "apps", application_id + ".png") for size in HICOLOR_SIZES]
    return [path for path in candidates if os.path.isfile(path)]


def refresh_icon_cache():
    """GTK reads a theme folder's icon-theme.cache instead of the folder when there is one; a stale
    one hides icons added since. Most user themes have none."""
    theme = os.path.join(data_home(), "icons", "hicolor")
    if not os.path.isfile(os.path.join(theme, "icon-theme.cache")):
        return
    for tool in ("gtk4-update-icon-cache", "gtk-update-icon-cache"):
        path = shutil.which(tool)
        if path:
            result = subprocess.run([path, "--force", "--ignore-theme-index", "--quiet", theme], check=False)
            if result.returncode != 0:
                print("linux-app-entry: " + tool + " failed for " + theme + "; the icon may not show until its cache is updated", file=sys.stderr)
            return
    print("linux-app-entry: " + theme + " has an icon cache and no gtk-update-icon-cache was found; the icon may not show until it is updated", file=sys.stderr)


def install_icon(folder, info):
    """Copies the app's icon into the user's hicolor theme; returns the entry's Icon value, or None."""
    icon = info.get("icon")
    application_id = info["applicationID"]
    if icon is None:
        # A copy an earlier install made is no longer named by the entry.
        for old in icon_files(application_id):
            os.remove(old)
        return None
    path = icon if os.path.isabs(icon) else os.path.join(folder, icon)
    if not os.path.isfile(path):
        # A path or a file name would make an entry with no icon (and one desktop-file-validate
        # rejects): most likely a misspelled file.
        if "/" in icon or os.path.splitext(icon)[1].lower() in (".png", ".svg", ".xpm", ".icns"):
            raise UsageError(path + " is missing; the icon is a PNG or SVG file in the app folder, or an icon theme name")
        # An icon theme name, as the runtime takes it.
        for old in icon_files(application_id):
            os.remove(old)
        return icon
    theme = os.path.join(data_home(), "icons", "hicolor")
    lower = path.lower()
    if lower.endswith(".svg"):
        target = os.path.join(theme, "scalable", "apps", application_id + ".svg")
    elif lower.endswith(".png"):
        size = png_size(path)
        if size is None:
            raise UsageError(path + " is not a PNG file")
        if size[0] != size[1] or size[0] not in HICOLOR_SIZES:
            target = None
        else:
            target = os.path.join(theme, "%dx%d" % size, "apps", application_id + ".png")
    else:
        raise UsageError(path + " is neither a PNG nor an SVG file, the only icons GTK and the desktop read")
    # The previous install's icon, of another size or format, goes only once the new one is known
    # to be usable, so a refused install leaves the installed entry whole.
    for old in icon_files(application_id):
        os.remove(old)
    if target is None:
        print("linux-app-entry: %s is %dx%d, a size the icon theme has no folder for (square %s); the entry names the file by its path" % (path, size[0], size[1], ", ".join(str(s) for s in HICOLOR_SIZES)), file=sys.stderr)
        return os.path.abspath(path)
    os.makedirs(os.path.dirname(target), exist_ok=True)
    shutil.copyfile(path, target)
    refresh_icon_cache()
    return application_id


def install(folder, exec_line):
    info = read_info(folder)
    application_id = info["applicationID"]
    if exec_line is None:
        program = default_program(folder)
        if "%" in program:
            # GLib looks for the program before it turns "%%" back into "%", finds no such file and
            # drops the entry, though the specification asks for the "%%".
            raise UsageError(program + " has a \"%\" in its path, which GNOME and other GLib-based desktops do not list; move the app to a path without one")
        exec_line = quote_exec_argument(program)
    icon = install_icon(folder, info)
    base = os.path.basename(os.path.normpath(folder))
    lines = [
        "[Desktop Entry]",
        "Type=Application",
        "Version=1.5",
        "Name=" + escape_value(info.get("name") or (base[:-4] if base.endswith(".app") else base)),
    ]
    if info.get("summary"):
        lines.append("Comment=" + escape_value(info["summary"]))
    # The string escape (a backslash doubled) comes on top of the Exec quoting.
    lines.append("Exec=" + escape_value(exec_line))
    lines.append("Path=" + escape_value(folder))
    if icon is not None:
        lines.append("Icon=" + escape_value(icon))
    else:
        print("linux-app-entry: Info.json names no icon; the desktop shows a generic one", file=sys.stderr)
    lines.append("Terminal=false")
    categories = [item for item in info.get("categories", []) if item]
    if categories:
        lines.append("Categories=" + "".join(escape_value(item).replace(";", "\\;") + ";" for item in categories))
    # Matches the window to the entry in an X11 session, where the window class stands for the ID.
    lines.append("StartupWMClass=" + application_id)
    applications = os.path.join(data_home(), "applications")
    os.makedirs(applications, exist_ok=True)
    entry = os.path.join(applications, application_id + ".desktop")
    with open(entry, "w", encoding="utf-8") as file:
        file.write("\n".join(lines) + "\n")
    validator = shutil.which("desktop-file-validate")
    if validator:
        result = subprocess.run([validator, entry], capture_output=True, text=True, check=False)
        if result.returncode != 0 or result.stdout.strip():
            print("linux-app-entry: desktop-file-validate: " + (result.stdout + result.stderr).strip(), file=sys.stderr)
    print("installed " + entry)


def uninstall(application_id):
    removed = icon_files(application_id)
    entry = os.path.join(data_home(), "applications", application_id + ".desktop")
    if os.path.isfile(entry):
        removed.append(entry)
    for path in removed:
        os.remove(path)
    if removed:
        refresh_icon_cache()
        print("removed " + ", ".join(removed))
    else:
        print("nothing installed for " + application_id)


def main(arguments):
    if len(arguments) < 2 or arguments[0] not in ("install", "uninstall"):
        raise UsageError("usage: linux-app-entry.py install <app folder> [--exec <command line>] | uninstall <app folder | application ID>")
    command, folder = arguments[0], os.path.abspath(arguments[1])
    rest = arguments[2:]
    exec_line = None
    if command == "install" and len(rest) == 2 and rest[0] == "--exec" and rest[1].strip():
        exec_line = rest[1]
    elif rest:
        raise UsageError("unexpected arguments: " + " ".join(rest))
    if command == "uninstall" and not os.path.isdir(folder) and is_valid_application_id(arguments[1]):
        uninstall(arguments[1])
        return
    if not os.path.isdir(folder):
        raise UsageError(folder + " is not a folder")
    if command == "install":
        install(folder, exec_line)
    else:
        uninstall(read_info(folder)["applicationID"])


if __name__ == "__main__":
    try:
        main(sys.argv[1:])
    except UsageError as error:
        fail(str(error), 64)
    except OSError as error:
        fail(str(error))
