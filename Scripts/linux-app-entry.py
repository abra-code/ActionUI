#!/usr/bin/env python3
"""Adds an ActionUI app to the Linux desktop's app list (GNOME's Apps, KDE's launcher and others),
or takes it off, for the current user.

The app's Info.plist gives the application ID, name and icon, as the ActionUI runtime reads them,
and optionally a comment and categories for the entry. It is at the app folder's top level (the flat
layout: the program beside its resources), or Contents/Info.plist in the macOS layout (the program
in Contents/Linux, the resources in Contents/Resources):

    CFBundleIdentifier      org.example.MyApp (required here)
    CFBundleDisplayName     My App (else CFBundleName, else the folder's name)
    CFBundleIconFile        MyApp: MyApp.svg, else MyApp.png, in the resources (or the file
                            named, when it is an SVG or a PNG)
    CFBundleExecutable      the program, in the folder or in Contents/Linux
    LinuxDesktopComment     Edits my things (the entry's Comment)
    LinuxDesktopCategories  an array of strings, such as Utility (the entry's Categories)
    CFBundleDocumentTypes   the files and folders the app opens (the entry's MimeType), as on macOS:
                            each type's CFBundleTypeMIMETypes as given, its LSItemContentTypes
                            (public.folder, com.apple.application-bundle, public.plain-text, ...)
                            and CFBundleTypeExtensions (txt, png) turned into MIME types; "*" (any
                            file) is not listed, a type whose CFBundleTypeRole is None is left out,
                            and CFBundleTypeOSTypes (legacy Mac OS file types) are not read
    CFBundleURLTypes        the URL schemes the app is opened with (each CFBundleURLSchemes item
                            as x-scheme-handler/<scheme> in MimeType)
    LinuxMimeTypes          an array of MIME types added as given, for what the above cannot say

install writes $XDG_DATA_HOME/applications/<CFBundleIdentifier>.desktop (XDG_DATA_HOME defaults
to ~/.local/share). The desktop matches the app's windows to that entry by the application ID, so
the dock shows the entry's name and icon. The program is given the files or URLs it is opened with
(%U), so the file manager's Open With lists the app for the types in MimeType. A folder's type is
inode/directory whatever its name, so an app that opens bundles (MyApp.app) is listed for every
folder. The icon is copied into the user's hicolor icon theme as
<id>.svg (scalable) or .png (its own size), and the entry names it by the ID. A PNG of a size the
theme has no folder for is named by its path in the app folder instead.

Usage:
    linux-app-entry.py install <app folder> [--exec <command line>]
    linux-app-entry.py uninstall <app folder | application ID>

--exec: the entry's command line, quoted as the Desktop Entry Specification quotes Exec arguments
(an argument with spaces in double quotes; field codes such as %f kept), run in the app folder:
for a Python or Node.js app, such as 'python3 MyApp.py %U'. Without it, the entry runs the app's
program, followed by %U: CFBundleExecutable in the program folder (the app folder, or
Contents/Linux), else the executable file named after the app folder (MyApp for MyApp.app), else
the only executable file there.

uninstall takes the application ID itself when the app folder is gone.

Exit status: 0 done, 1 a step failed, 64 bad arguments or Info.plist.
"""

import mimetypes
import os
import plistlib
import re
import shutil
import struct
import subprocess
import sys
import xml.parsers.expat

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


STRING_KEYS = ("CFBundleIdentifier", "CFBundleDisplayName", "CFBundleName", "CFBundleIconFile",
               "CFBundleExecutable", "LinuxDesktopComment")


def app_layout(folder):
    """(Info.plist path, resources folder, program folder) of the app folder: Info.plist at its top
    level (flat), else Contents/Info.plist (the macOS layout)."""
    flat = os.path.join(folder, "Info.plist")
    if os.path.isfile(flat):
        return flat, folder, folder
    contents = os.path.join(folder, "Contents")
    nested = os.path.join(contents, "Info.plist")
    if os.path.isfile(nested):
        return nested, os.path.join(contents, "Resources"), os.path.join(contents, "Linux")
    raise UsageError("no Info.plist in " + folder + " or its Contents folder; it gives the application ID the entry is named after")


def read_info(folder):
    """The app's Info.plist (app_layout), with its keys checked; an empty string counts as left
    out. Adds "resources" and "programs", the folders of the layout."""
    path, resources, programs = app_layout(folder)
    try:
        with open(path, "rb") as file:
            info = plistlib.load(file)
    except (OSError, ValueError, xml.parsers.expat.ExpatError) as error:
        raise UsageError("could not read " + path + ": " + str(error))
    if not isinstance(info, dict):
        raise UsageError(path + " is not a dictionary")
    for key in STRING_KEYS:
        value = info.get(key)
        if value is not None and not isinstance(value, str):
            raise UsageError(path + ": " + key + " is not a string")
        if value == "":
            info.pop(key)
    categories = info.get("LinuxDesktopCategories", [])
    if not isinstance(categories, list) or not all(isinstance(item, str) for item in categories):
        raise UsageError(path + ": LinuxDesktopCategories is not an array of strings")
    application_id = info.get("CFBundleIdentifier")
    if application_id is None:
        raise UsageError(path + " has no CFBundleIdentifier")
    if not is_valid_application_id(application_id):
        raise UsageError(path + ": '" + application_id + "' is not a valid application ID (reverse DNS, such as org.example.MyApp)")
    info["resources"] = resources
    info["programs"] = programs
    info["plistPath"] = path
    return info


def default_program(folder, info):
    """CFBundleExecutable in the program folder, else the executable file named after the app
    folder, else the only executable file in the program folder."""
    programs = info["programs"]
    named_executable = info.get("CFBundleExecutable")
    if named_executable is not None:
        path = os.path.join(programs, named_executable)
        if "/" not in named_executable and os.path.isfile(path) and os.access(path, os.X_OK):
            return path
        raise UsageError("CFBundleExecutable " + named_executable + " is not an executable file in " + programs)
    base = os.path.basename(os.path.normpath(folder))
    named = os.path.join(programs, base[:-4] if base.endswith(".app") else base)
    if os.path.isfile(named) and os.access(named, os.X_OK):
        return named
    if not os.path.isdir(programs):
        raise UsageError("no program folder " + programs + "; give the command line with --exec")
    executables = []
    for name in sorted(os.listdir(programs)):
        path = os.path.join(programs, name)
        if os.path.isfile(path) and os.access(path, os.X_OK) and not name.endswith(".so"):
            executables.append(path)
    if len(executables) == 1:
        return executables[0]
    if not executables:
        raise UsageError("no executable file in " + programs + "; give the command line with --exec")
    raise UsageError("more than one executable file in " + programs + "; give the command line with --exec")


def icon_path(info):
    """The icon file CFBundleIconFile names, as the runtime finds it: the file itself when it is an
    SVG or a PNG, else its name with .svg, then .png, in the resources. None when it names none, or
    there is no such file (said on stderr)."""
    icon_file = info.get("CFBundleIconFile")
    if icon_file is None:
        return None
    if "/" in icon_file:
        raise UsageError("CFBundleIconFile " + icon_file + " is a path; it is a file name in " + info["resources"])
    named = os.path.join(info["resources"], icon_file)
    base, extension = os.path.splitext(named)
    candidates = [named] if extension.lower() in (".svg", ".png") else []
    candidates += [base + ".svg", base + ".png"]
    for candidate in candidates:
        if os.path.isfile(candidate):
            return candidate
    # A bundle made on macOS names its .icns, and a new one may get its PNG or SVG only when it is
    # first built: the entry is still made, with the desktop's generic icon
    print("linux-app-entry: no icon for CFBundleIconFile " + icon_file + ": " + " or ".join(os.path.basename(c) for c in candidates)
          + " in " + info["resources"] + " (a macOS .icns or Icon Composer file does not work on Linux: export a PNG or an SVG)", file=sys.stderr)
    return None


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


# Apple's type identifiers (LSItemContentTypes) and the MIME types the desktop files the same things
# under. A bundle or package is a folder on Linux; the desktop types every folder inode/directory.
UTI_MIME_TYPES = {
    "public.item": ("application/octet-stream", "inode/directory"),
    "public.data": ("application/octet-stream",),
    "public.content": ("application/octet-stream",),
    "public.folder": ("inode/directory",),
    "public.directory": ("inode/directory",),
    "com.apple.bundle": ("inode/directory",),
    "com.apple.package": ("inode/directory",),
    "com.apple.application": ("inode/directory",),
    "com.apple.application-bundle": ("inode/directory",),
    "public.text": ("text/plain",),
    "public.plain-text": ("text/plain",),
    "public.utf8-plain-text": ("text/plain",),
    "public.utf16-plain-text": ("text/plain",),
    "public.source-code": ("text/plain",),
    "public.script": ("text/plain",),
    "public.shell-script": ("application/x-shellscript",),
    "public.python-script": ("text/x-python",),
    "public.json": ("application/json",),
    "public.xml": ("application/xml",),
    "public.yaml": ("application/yaml",),
    "public.html": ("text/html",),
    "public.comma-separated-values-text": ("text/csv",),
    "public.tab-separated-values-text": ("text/tab-separated-values",),
    "net.daringfireball.markdown": ("text/markdown",),
    "public.rtf": ("application/rtf",),
    "com.adobe.pdf": ("application/pdf",),
    "public.image": ("image/png", "image/jpeg", "image/gif", "image/tiff", "image/bmp", "image/webp", "image/svg+xml"),
    "public.png": ("image/png",),
    "public.jpeg": ("image/jpeg",),
    "com.compuserve.gif": ("image/gif",),
    "public.tiff": ("image/tiff",),
    "com.microsoft.bmp": ("image/bmp",),
    "org.webmproject.webp": ("image/webp",),
    "public.svg-image": ("image/svg+xml",),
    "public.heic": ("image/heic",),
    "public.audio": ("audio/mpeg", "audio/x-wav", "audio/flac", "audio/ogg", "audio/mp4"),
    "public.mp3": ("audio/mpeg",),
    "com.microsoft.waveform-audio": ("audio/x-wav",),
    "public.movie": ("video/mp4", "video/quicktime", "video/x-matroska", "video/webm"),
    "public.video": ("video/mp4", "video/quicktime", "video/x-matroska", "video/webm"),
    "public.mpeg-4": ("video/mp4",),
    "com.apple.quicktime-movie": ("video/quicktime",),
    "public.zip-archive": ("application/zip",),
    "public.tar-archive": ("application/x-tar",),
    "org.gnu.gnu-zip-archive": ("application/gzip",),
}

# Extensions (CFBundleTypeExtensions) whose MIME type differs from what Python's mimetypes says, or
# that it does not know; "app" is a bundle, which is a folder on Linux. For a compressed file
# mimetypes gives the type inside (tgz: application/x-tar) and an encoding, which the desktop does
# not use: it has a type of its own for the compressed file. "*" (any file) is not here: listed as
# application/octet-stream it would make the app the default for every file the desktop cannot
# type further, so an app that takes any file names its types to be offered for them.
EXTENSION_MIME_TYPES = {
    "app": ("inode/directory",),
    "md": ("text/markdown",),
    "markdown": ("text/markdown",),
    "py": ("text/x-python",),
    "sh": ("application/x-shellscript",),
    "yaml": ("application/yaml",),
    "yml": ("application/yaml",),
    "json": ("application/json",),
    "gz": ("application/gzip",),
    "tgz": ("application/x-compressed-tar",),
    "tar.gz": ("application/x-compressed-tar",),
    "svgz": ("image/svg+xml-compressed",),
}

URL_SCHEME_PATTERN = re.compile(r"^[A-Za-z][A-Za-z0-9+.-]*$")
MIME_TYPE_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9!#$&^_.+-]*/[A-Za-z0-9][A-Za-z0-9!#$&^_.+-]*$")


def string_array(value, where):
    """value when it is an array of strings, else a UsageError naming where it is."""
    if not isinstance(value, list) or not all(isinstance(item, str) for item in value):
        raise UsageError(where + " is not an array of strings")
    return value


def mime_types(info, plist_path):
    """The MIME types the entry lists (MimeType): CFBundleDocumentTypes turned into MIME types, then
    LinuxMimeTypes as given, without repeats. An identifier, extension or file type with no known
    MIME type is said on stderr when its document type gives none at all."""
    found = []
    document_types = info.get("CFBundleDocumentTypes", [])
    if not isinstance(document_types, list):
        raise UsageError(plist_path + ": CFBundleDocumentTypes is not an array")
    for index, document_type in enumerate(document_types):
        where = plist_path + ": CFBundleDocumentTypes item " + str(index)
        if not isinstance(document_type, dict):
            raise UsageError(where + " is not a dictionary")
        if document_type.get("CFBundleTypeRole") == "None":
            continue  # declared, not opened
        given = string_array(document_type.get("CFBundleTypeMIMETypes", []), where + " CFBundleTypeMIMETypes")
        identifiers = string_array(document_type.get("LSItemContentTypes", []), where + " LSItemContentTypes")
        extensions = string_array(document_type.get("CFBundleTypeExtensions", []), where + " CFBundleTypeExtensions")
        # CFBundleTypeOSTypes (classic Mac OS file types) are legacy and have no part on Linux
        types = list(given)
        unknown = []
        for identifier in identifiers:
            known = UTI_MIME_TYPES.get(identifier)
            if known:
                types.extend(known)
            else:
                unknown.append(identifier)
        for extension in extensions:
            extension = extension.lstrip(".").lower()
            if extension == "*":
                continue  # any file: not listed (EXTENSION_MIME_TYPES)
            known = EXTENSION_MIME_TYPES.get(extension)
            if known is None:
                guessed, encoding = mimetypes.guess_type("file." + extension, strict=False)
                known = (guessed,) if guessed and encoding is None else None
            if known:
                types.extend(known)
            elif extension:
                unknown.append("." + extension)
        if not types and unknown:
            print("linux-app-entry: " + where + ": no MIME type known for " + ", ".join(unknown)
                  + "; the app is not offered for them (list their MIME types in LinuxMimeTypes)", file=sys.stderr)
        found.extend(types)
    # The URL schemes the app is opened with (CFBundleURLTypes), as on macOS: the desktop hands the
    # URL to the program (%U). An OMC applet runs only a command that opts in to URLs.
    url_types = info.get("CFBundleURLTypes", [])
    if not isinstance(url_types, list):
        raise UsageError(plist_path + ": CFBundleURLTypes is not an array")
    for index, url_type in enumerate(url_types):
        where = plist_path + ": CFBundleURLTypes item " + str(index)
        if not isinstance(url_type, dict):
            raise UsageError(where + " is not a dictionary")
        for scheme in string_array(url_type.get("CFBundleURLSchemes", []), where + " CFBundleURLSchemes"):
            if not URL_SCHEME_PATTERN.match(scheme):
                raise UsageError(where + ": '" + scheme + "' is not a URL scheme (a letter, then letters, digits, +, - or .)")
            if scheme.lower() != "file":
                found.append("x-scheme-handler/" + scheme.lower())
    found.extend(string_array(info.get("LinuxMimeTypes", []), plist_path + ": LinuxMimeTypes"))
    result = []
    for mime_type in found:
        if mime_type.endswith("/*"):
            # A macOS plist may name a family (image/*); a desktop entry lists exact types only
            print("linux-app-entry: " + plist_path + ": " + mime_type + " is left out: a desktop entry lists exact MIME types (name them, or list them in LinuxMimeTypes)", file=sys.stderr)
            continue
        if not MIME_TYPE_PATTERN.match(mime_type):
            raise UsageError(plist_path + ": '" + mime_type + "' is not a MIME type (type/subtype)")
        if mime_type not in result:
            result.append(mime_type)
    return result


def update_desktop_database():
    """The desktop finds the apps for a MIME type in applications/mimeinfo.cache, which
    update-desktop-database rewrites; without it, Open With may not list the app until it runs."""
    tool = shutil.which("update-desktop-database")
    if tool is None:
        return
    applications = os.path.join(data_home(), "applications")
    result = subprocess.run([tool, "--quiet", applications], capture_output=True, text=True, check=False)
    if result.returncode != 0:
        print("linux-app-entry: update-desktop-database failed for " + applications + ": " + (result.stderr or result.stdout).strip(), file=sys.stderr)


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


def install_icon(info):
    """Copies the app's icon into the user's hicolor theme; returns the entry's Icon value, or None."""
    application_id = info["CFBundleIdentifier"]
    path = icon_path(info)
    if path is None:
        # A copy an earlier install made is no longer named by the entry.
        for old in icon_files(application_id):
            os.remove(old)
        return None
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
    application_id = info["CFBundleIdentifier"]
    program = None
    if exec_line is None:
        program = default_program(folder, info)
        if "%" in program:
            # GLib looks for the program before it turns "%%" back into "%", finds no such file and
            # drops the entry, though the specification asks for the "%%".
            raise UsageError(program + " has a \"%\" in its path, which GNOME and other GLib-based desktops do not list; move the app to a path without one")
        # %U: the files (as file:// URLs) or URLs the app is opened with; ActionUI and OMC apps
        # take both on their command line
        exec_line = quote_exec_argument(program) + " %U"
    # Before anything is written: a malformed document type leaves an installed entry whole
    opened_types = mime_types(info, info["plistPath"])
    icon = install_icon(info)
    base = os.path.basename(os.path.normpath(folder))
    name = info.get("CFBundleDisplayName") or info.get("CFBundleName") or (base[:-4] if base.endswith(".app") else base)
    lines = [
        "[Desktop Entry]",
        "Type=Application",
        "Version=1.5",
        "Name=" + escape_value(name),
    ]
    if info.get("LinuxDesktopComment"):
        lines.append("Comment=" + escape_value(info["LinuxDesktopComment"]))
    # The string escape (a backslash doubled) comes on top of the Exec quoting.
    lines.append("Exec=" + escape_value(exec_line))
    if program is not None:
        # The desktop leaves the entry out once the program is gone (an app moved or deleted, an
        # applet built in a temporary folder), rather than listing an app that does not start.
        lines.append("TryExec=" + escape_value(program))
    lines.append("Path=" + escape_value(folder))
    if icon is not None:
        lines.append("Icon=" + escape_value(icon))
    elif info.get("CFBundleIconFile") is None:
        print("linux-app-entry: Info.plist names no icon (CFBundleIconFile); the desktop shows a generic one", file=sys.stderr)
    lines.append("Terminal=false")
    categories = [item for item in info.get("LinuxDesktopCategories", []) if item]
    if categories:
        lines.append("Categories=" + "".join(escape_value(item).replace(";", "\\;") + ";" for item in categories))
    if opened_types:
        lines.append("MimeType=" + "".join(item + ";" for item in opened_types))
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
    update_desktop_database()
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
        if entry in removed:
            update_desktop_database()
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
        uninstall(read_info(folder)["CFBundleIdentifier"])


if __name__ == "__main__":
    try:
        main(sys.argv[1:])
    except UsageError as error:
        fail(str(error), 64)
    except OSError as error:
        fail(str(error))
