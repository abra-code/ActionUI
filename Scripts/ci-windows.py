#!/usr/bin/env python3
"""Windows build and test driver for ActionUI, used by .github/workflows/windows.yml and runnable
by hand on a Windows machine with the Swift toolchain installed.

Usage:
  python Scripts/ci-windows.py core [--results DIR]
      Builds the portable core (ACTIONUI_CORE_ONLY=1 selects that package) with its tests, then
      runs the tests, in its own build folder (.build/ci-windows-core) so a full build's folder is
      left alone. Writes each step's log, summary.md and summary.json into DIR (default:
      .build/ci-windows-results). On GitHub Actions the summary is also added to the job summary.
  python Scripts/ci-windows.py shim [--results DIR] [--install-runtime]
      Builds the WinUI shim (ActionUIWinUI/Shim) for this machine's architecture: downloads the
      pinned Windows App SDK and C++/WinRT NuGet packages, generates the C++/WinRT projection,
      compiles ActionUIWinUIShim.dll with MSVC, then builds and runs the C smoke test, which
      renders a window's content into DIR/shim-smoke.png. Everything goes to .build/winui-shim.
      --install-runtime first installs the Windows App SDK runtime from the package's MSIX files
      for the current user (the smoke test needs it; CI machines do not have it).
  python Scripts/ci-windows.py winui [--results DIR] [--install-runtime]
      What shim does, then builds the Swift package for Windows (windowsPackage in Package.swift)
      with the shim's import library on the linker path, in .build/ci-windows-winui, runs its
      smoke test ActionUIWinUISmoke, which renders DIR/swift-smoke.png, and renders each test file
      in ActionUIWinUI/Apps/Preview/TestFiles with ActionUIWinUIPreview into
      DIR/preview-<name>.png, printing where each element was placed. It also builds ActionUI.dll's
      package (ActionUIWinUI/Library) in .build/ci-windows-library, runs the C, C++ and language
      binding checks against the DLL, and renders each test file in ActionUIWinUI/Apps/Preview/TestFiles/AddOns
      with ActionUIWinUIAddOnPreview (the add-ons the DLL links) into DIR/add-on-preview-<name>.png.

Exit status: 0 passed, 1 a step failed or a tool is missing, 2 bad arguments.
"""

import argparse
import datetime
import hashlib
import http.client
import json
import os
import platform
import re
import shutil
import subprocess
import sys
import tarfile
import time
import urllib.error
import urllib.request
import zipfile
from pathlib import Path

REPO_DIR = Path(__file__).resolve().parent.parent
STEP_TIMEOUT_SECONDS = 45 * 60
ANSI_ESCAPE = re.compile(r"\x1b\[[0-9;]*m")

SHIM_DIR = REPO_DIR / "ActionUIWinUI" / "Shim"
SHIM_WORK = REPO_DIR / ".build" / "winui-shim"
# The NuGet packages the shim is built from. WinUI 2.7.0 refers to WebView2's metadata, at the
# version its own package depends on.
WINUI_PACKAGES = {
    "microsoft.windows.cppwinrt": "3.0.260818.1",
    "microsoft.windowsappsdk.foundation": "2.7.0",
    "microsoft.windowsappsdk.interactiveexperiences": "2.7.0",
    "microsoft.windowsappsdk.dwrite": "2.7.0",
    "microsoft.windowsappsdk.winui": "2.7.0",
    "microsoft.windowsappsdk.runtime": "2.7.0",
    "microsoft.web.webview2": "1.0.3719.77",
}
# The SHA-256 of each package's archive, by "<id>.<version>". An archive is used only when it matches,
# so a new version needs its value here. Values from nuget.org's downloads; each archive's SHA-512 matched
# the one nuget.org's catalog recorded when the package was published.
WINUI_PACKAGE_SHA256 = {
    "microsoft.windows.cppwinrt.3.0.260818.1": "a8993608ae9263a8288e1a1d9ee2684a5632f4acc59e1e89ddd86b3b889a7367",
    "microsoft.windowsappsdk.foundation.2.7.0": "4131660bda7476eef751ce134c9847b5a79e4051809bffbf9dd171f4246afdf8",
    "microsoft.windowsappsdk.interactiveexperiences.2.7.0": "5df51fd9e30a6093f737698ae8ad4e8d62d87f7081b00aa6a4ea0b893f03e1c2",
    "microsoft.windowsappsdk.dwrite.2.7.0": "d9ea79e67c2379d100a51a8ea681d1fb21af211c1a6676fd60ecf7795ac46a44",
    "microsoft.windowsappsdk.winui.2.7.0": "027ecdc0c51a2d31fd25985616ef2e9438f02ee3e7b6e72fd0601ddb119688b4",
    "microsoft.windowsappsdk.runtime.2.7.0": "326b47f40f051e767bfc83ce99c753c758bbba75a25f0a4febab8cd9ea8b5152",
    "microsoft.web.webview2.1.0.3719.77": "2f6be3a10a1a8d6d1fde986af4131dab344f8181fffe75590824e0f4b037ed73",
}
# WebView2's WinRT component, beside the programs (a WebView's browser cannot start without it).
WEBVIEW2_CORE = "Microsoft.Web.WebView2.Core.dll"
# Installed in this order: the framework package first, the others depend on it.
WINUI_RUNTIME_MSIX = [
    "Microsoft.WindowsAppRuntime.2.msix",
    "Microsoft.WindowsAppRuntime.Main.2.msix",
    "Microsoft.WindowsAppRuntime.Singleton.2.msix",
    "Microsoft.WindowsAppRuntime.DDLM.2.msix",
]
SMOKE_TIMEOUT_SECONDS = 180
# Options for ActionUIWinUIPreview by test file name (ActionUIWinUI/Apps/Preview/TestFiles), beside
# the test file and the PNG: a window size, and elements to operate with the actions they must fire.
# "{test_files_url}" in an option is the test files folder's file URL (an AsyncImage's file URLs);
# "{program_folder}" the folder the preview runs from (the app's resources, where ActionUIWinUI/Apps/Preview/Bundled
# is copied), and "{program_folder_upper}" the same in upper case; "{test_files_folder_json}" the test files
# folder's path as a JSON string's contents (backslashes doubled).
PREVIEW_OPTIONS = {
    # An element registered the way an add-on registers one (the preview's AddOnProbe) shows its text, and so does
    # one registered through the linked add-ons call (ActionUILinkedAddOns_register, defined by the preview); an
    # element type nothing registered shows the placeholder.
    "AddOns": ["420", "200",
               "--expect-automation", "3", "name", "add-on: registered",
               "--expect-automation", "5", "name", "add-on: linked",
               "--expect-log", "NoSuchAddOn is not available on Windows yet; showing a placeholder"],
    # The two chart test files at sizes that show their charts whole (the second has two columns).
    # Chart 16 is named by its marks' accessibilityLabel and accessibilityValue, read through UI Automation.
    "Charts": ["560", "720", "--expect-automation", "16", "name",
               "Swift, 42 projects; Kotlin, 31 projects; JavaScript, 27 projects; Rust, 12 projects"],
    "ChartTypes": ["760", "720"],
    "ChartAnnotations": ["600", "720"],
    # Selection with the real mouse (x64): a drag across the range chart (3; its range goes at the release),
    # then one across the hover chart (1; not taken, so its moves hover and the value stays under the
    # pointer), a pause for the settled action.
    "ChartSelection": ["660", "560", "--drag", "3", "40", "100", "200", "100",
                       "--drag", "1", "40", "100", "150", "100", "--delay", "500"],
    # Scrolling with the real wheel (x64): two notches over the dates (1; the pointer there also hovers its
    # value), three over the teams (2); the windows moved show in the PNG.
    "ChartScroll": ["600", "520", "--wheel", "1", "280", "100", "0", "2", "--wheel", "2", "280", "100", "0", "3",
                    "--delay", "500"],
    "Floors": ["420", "380"],
    "NestedFloors": ["420", "420"],
    "Images": ["560", "440"],
    "Labels": ["440", "300"],
    "States": ["420", "320"],
    "Forms": ["420", "370"],
    "Pickers": ["460", "470"],
    "Lists": ["420", "400", "--add-row", "3", "Apples", "--add-row", "3", "Bananas", "--add-row", "3", "Cherries"],
    "ListTemplates": ["420", "430", "--add-row", "3", "folder|Documents|12 items", "--add-row", "3", "photo|Pictures|3 items",
                      "--add-row", "3", "music.note|Music|0 items",
                      "--add-row", "10", "false|Milk", "--add-row", "10", "true|Eggs", "--add-row", "10", "false|Bread",
                      "--toggle", "11", "--expect-action", "item.toggled",
                      "--on-action", "item.toggled", "12", "The first row was toggled"],
    "ListCells": ["420", "380", "--add-row", "3", "Open", "--add-row", "3", "Rename", "--add-row", "3", "Delete",
                  "--add-row", "5", "star.fill", "--add-row", "5", "heart", "--add-row", "5", "folder",
                  "--invoke-row", "3", "1", "--expect-action", "row.pressed"],
    "TextEditors": ["420", "440", "--set-text", "8", "typed through UI Automation", "--expect-action", "typed.changed",
                    "--forbid-action", "wrapped.changed",
                    "--on-action", "typed.changed", "9", "The editor's text changed"],
    "DatePickers": ["480", "600", "--forbid-action", "day.changed", "--forbid-action", "time.changed",
                    "--forbid-action", "both.changed", "--forbid-action", "calendar.changed",
                    "--forbid-action", "outside.changed"],
    "Sliders": ["420", "340", "--set-text", "10", "0.75", "--expect-action", "moved.changed",
                "--on-action", "moved.changed", "12", "Moved through UI Automation",
                "--forbid-action", "plain.changed", "--forbid-action", "stepped.changed", "--forbid-action", "outside.changed"],
    "ProgressViews": ["420", "380", "--set-property", "7", "value", "0.8"],
    "Steppers": ["420", "320", "--invoke-part", "6", "1", "--invoke-part", "6", "1", "--invoke-part", "6", "1",
                 "--expect-action", "count.changed", "--on-action", "count.changed", "7", "Stepped up three times"],
    "ContentUnavailable": ["460", "640"],
    "Gauges": ["420", "360", "--set-value", "7", "80"],
    "SecureFields": ["360", "220", "--set-text", "4", "hunter2", "--expect-action", "typed.changed",
                     "--on-action", "typed.changed", "5", "The field's text changed",
                     "--forbid-action", "empty.changed", "--forbid-action", "filled.changed"],
    "FormSections": ["420", "460"],
    "FormColumns": ["460", "520"],
    "Grids": ["420", "400"],
    "TabViews": ["420", "300", "--select-part", "2", "2", "--expect-action", "tabs.changed",
                 "--on-action", "tabs.changed", "10", "Chose Advanced", "--set-value", "11", "1"],
    "LazyStacks": ["420", "400"],
    "NavigationStacks": ["420", "440", "--invoke", "4", "--wait", "--invoke-part", "1", "0", "--wait", "--invoke", "5",
                         "--set-path", "20", "30", "--select-part", "40", "1", "--expect-action", "places.chosen"],
    "StackTemplates": ["420", "520", "--add-row", "2", "star|Starred", "--add-row", "2", "heart|Liked", "--add-row", "2", "folder|Filed",
                       "--add-row", "6", "A", "--add-row", "6", "B", "--add-row", "6", "C",
                       "--add-row", "8", "Lazy one", "--add-row", "8", "Lazy two",
                       "--add-row", "10", "true|Wi-Fi", "--add-row", "10", "false|Bluetooth",
                       "--add-row", "13", "Sounds|true", "--add-row", "13", "Haptics|false",
                       "--add-row", "15", "A single ZStack layer",
                       "--toggle", "11", "--expect-action", "row.toggled"],
    "LazyRows": ["420", "440", "--add-rows", "4", "2000", "Row #|item #", "--add-rows", "10", "500", "#", "--wait",
                 "--scroll", "3", "0", "20000", "--scroll", "9", "4000", "0",
                 "--max-instances", "4", "200", "--max-instances", "10", "200"],
    "LazyLists": ["420", "440", "--add-rows", "2", "2000", "star|Row #", "--add-rows", "7", "1000", "Button #", "--wait",
                  "--scroll-row", "2", "1000", "--scroll-row", "7", "500", "--wait", "--invoke-row", "7", "500",
                  "--expect-action", "cell.pressed", "--on-action", "cell.pressed", "9", "Pressed row 500",
                  "--expect-row-name", "2", "1000", "star, Row 1001", "--expect-row-name", "2", "1900", "star, Row 1901",
                  "--expect-row-name", "7", "500", "Button 501",
                  "--max-instances", "2", "200"],
    "LazyGrids": ["420", "460", "--add-rows", "21", "2000", "Cell #", "--add-rows", "31", "300", "#", "--wait",
                  "--scroll", "20", "0", "5000", "--scroll", "30", "3000", "0",
                  "--max-instances", "21", "300", "--max-instances", "31", "150"],
    "DisclosureGroups": ["420", "380", "--add-row", "7", "Row one", "--add-row", "7", "Row two", "--toggle", "2",
                         "--expect-action", "details.toggled", "--on-action", "details.toggled", "9", "Details collapsed"],
    "Links": ["420", "220"],
    # The app's own links open whatever they name; links in JSON from a server or from a file outside the
    # app's resources open only web and mail addresses. --no-launch: nothing is opened.
    "LessTrustedLinks": ["420", "460", "--no-launch", "--delay", "4000",
                         "--invoke", "3", "--invoke", "4", "--invoke", "101", "--invoke", "102", "--invoke", "103",
                         "--invoke", "104", "--invoke", "105", "--invoke", "106", "--invoke", "107", "--invoke", "201",
                         "--invoke", "202",
                         # The address the policy judged (b.example), as Foundation writes it, not the text as written.
                         "--expect-log", "Link 105: opening https://a.example%5C@b.example/",
                         # A ShareLink's item with another scheme is asked as a link.
                         "--expect-log", "Not opening ms-settings:display from element 106 ",
                         "--expect-log", "Not opening \\\\server\\share\\report.txt from element 107 ",
                         "--expect-log", "Link 3: opening ms-settings:display",
                         "--expect-log", "Link 4: opening https://github.com/abra-code/ActionUI",
                         "--expect-log", "Not opening ms-settings:display from element 101 ",
                         "--expect-log", "Not opening file://server/share/report.txt from element 102 ",
                         "--expect-log", "Link 103: opening https://example.com/",
                         "--expect-log", "Link 104: opening mailto:someone@example.com",
                         "--expect-log", "Not opening ms-settings:display from element 201 ",
                         "--expect-log", "Link 202: opening https://example.com/"],
    "ColorPickers": ["420", "300", "--set-text", "2", "#2060FF",
                     "--expect-action", "color.picked", "--forbid-action", "color.renderer",
                     "--on-action", "color.picked", "8", "Picked"],
    "ControlGroups": ["420", "200", "--invoke", "4", "--expect-action", "group.italic"],
    "Canvases": ["420", "320"],
    "CanvasShading": ["420", "200"],
    "CanvasImages": ["420", "190"],
    "CanvasEffects": ["420", "210"],
    "ScrollReaders": ["420", "230", "--set-property", "4", "scrollTo", "230", "--wait"],
    "GeometryReaders": ["420", "190"],
    # The test files folder as the app's resources, so the files it loads are the app's own and load the files
    # beside them (content from a file elsewhere loads no local files).
    "Loadables": ["420", "330", "--configuration", '{"resourceFolder": "{test_files_folder_json}"}', "--delay", "4000", "--expect-action", "child.loaded", "--expect-action", "grandchild.loaded",
                  "--expect-action", "remote.loaded"],
    # A LoadableView's download: a redirect (github.com to raw.githubusercontent.com) is followed; a body past
    # the limit (lowered to 50 bytes here) is refused.
    "FetchRedirects": ["420", "120", "--delay", "6000", "--expect-action", "redirected.loaded"],
    "FetchSizeLimit": ["420", "120", "--fetch-limit", "50", "--delay", "4000", "--forbid-action", "oversized.loaded",
                       "--expect-log", "the response is larger than 50 bytes"],
    # A host policy that refuses LoadableViews' remote loads: the download is not even started; a file loads.
    "LoadPolicy": ["420", "160", "--refuse-remote-loads", "--delay", "3000", "--forbid-action", "refused.loaded",
                   "--expect-action", "file.loaded",
                   "--expect-log", "LoadableView 3: not loading https://raw.githubusercontent.com/abra-code/ActionUI/WinUI-CI/ActionUIWinUI/Apps/Preview/TestFiles/Loadable/Remote.json: the trust policy refuses it"],
    # The host trusts raw.githubusercontent.com (its configuration); JSON asked of github.com and redirected
    # there is judged by where it came from: trusted, so its Windows settings link opens (--no-launch).
    "TrustedOrigins": ["420", "220", "--no-launch",
                       "--configuration", '{"trust": {"trustedOrigins": ["https://raw.githubusercontent.com"]}}',
                       "--delay", "6000", "--invoke", "101",
                       "--expect-log", "was redirected to https://raw.githubusercontent.com/",
                       "--expect-log", "Link 101: opening ms-settings:display"],
    "Groups": ["420", "300", "--add-row", "21", "First", "--add-row", "21", "Second"],
    "NavigationSplitViews": ["420", "460", "--select-part", "2", "1", "--expect-action", "sidebar.changed",
                             "--drag", "20", "180.5", "70", "210.5", "70", "--expect-width", "23", "116",
                             "--invoke-part", "40", "0", "--expect-action", "sidebar.toggled"],
    "ButtonStyles": ["480", "240"],
    "Shadows": ["440", "260"],
    # Black shadows of radius 4, 8 and 12 on clean edges, to compare their blur with SwiftUI's.
    "ShadowBlur": ["420", "300"],
    "Overlays": ["440", "240"],
    "ControlSizes": ["560", "300"],
    "Tints": ["560", "420"],
    "TextAlignments": ["520", "320"],
    "TextSelections": ["460", "160"],
    "Hovers": ["420", "160", "--drag", "2", "-30.5", "20.5", "40.5", "20.5", "--drag", "2", "40.5", "20.5", "180.5", "20.5"],
    "Sheets": ["440", "300", "--invoke", "2", "--delay", "500", "--expect-state", "2", "sheetVisible", "true",
               "--expect-automation", "11", "name", "A sheet", "--invoke", "13", "--expect-action", "sheet.done"],
    # JSON from a server presents no sheet or popover and titles no screen: the sheet's state changes, nothing
    # is shown.
    "LessTrustedPresentations": ["440", "300", "--delay", "4000", "--invoke", "301", "--delay", "500",
                                 "--expect-state", "301", "sheetVisible", "true",
                                 "--expect-log", "Not presenting a sheet, cover or popover for element 301 ",
                                 "--expect-log", "Not presenting a sheet, cover or popover for element 303 ",
                                 "--expect-log", "Not setting the title for element 310 ",
                                 "--expect-log", "Not setting the title for element 321 "],
    "Popovers": ["440", "260", "--invoke", "4", "--delay", "500", "--expect-automation", "40", "name", "A sheet the host closes",
                 "--set-state", "4", "sheetVisible", "false", "--delay", "500", "--invoke", "3", "--delay", "500",
                 "--expect-automation", "21", "name", "A popover", "--expect-action", "sheet.dismissed",
                 "--expect-action", "popover.shown"],
    "Appearances": ["420", "260", "--select-part", "3", "1", "--add-row", "9", "Row a", "--delay", "300",
                    "--add-row", "9", "Row b", "--delay", "300", "--expect-action", "page.shown",
                    "--expect-action", "first.shown", "--expect-action", "first.hidden", "--expect-action", "second.shown",
                    "--expect-action", "row.shown", "--forbid-action", "row.hidden"],
    "Accessibility": ["420", "300", "--expect-automation", "2", "name", "Save the document",
                      "--expect-automation", "2", "help", "Writes it to disk", "--expect-automation", "2", "id", "save-button",
                      "--expect-automation", "3", "help", "Turns on alerts", "--expect-automation", "4", "name", "Plain name",
                      "--expect-automation", "7", "name", "Wireless network", "--expect-automation", "7", "id", "wifi-toggle",
                      "--expect-automation", "2", "accelerator", "Ctrl+S"],
    "Shares": ["420", "200"],
    # JSON from a server: a WebView shows the "Blocked" page for a file: address and reads no script file.
    # --allow-user-scripts: a host policy that lets it run user scripts, so only their files are refused.
    "LessTrustedWebViews": ["420", "200", "--allow-user-scripts", "--delay", "8000",
                            "--set-value", "601", "file:///C:/Windows/system.ini", "--delay", "1000",
                            "--expect-log", "WebView not showing file:///C:/Windows/system.ini: the trust policy refuses it",
                            "--expect-log", "WebView not showing file:///C:/Windows/win.ini: the trust policy refuses it",
                            "--expect-log", "Not reading Loadable/Child.json for element 602: the trust policy refuses it",
                            "--expect-log", "for element 603: the trust policy refuses it"],
    # JSON from a server: its WebView runs none of its user scripts (the page keeps its own title).
    "LessTrustedWebScripts": ["420", "180", "--delay", "10000", "--expect-state", "901", "title", "page",
                              "--expect-log", "WebView not running its 1 user script(s): the trust policy refuses them"],
    # JSON from a server: its pages' own navigations open no other app's scheme and no window.
    "LessTrustedWebPages": ["420", "200", "--delay", "12000",
                            "--expect-log", "WebView not going to ms-settings:display: the trust policy refuses it",
                            "--expect-log", "WebView 702 not opening a window for https://example.com/"],
    # JSON from a server: its page (html under a base on the JSON's own https origin, so a secure context
    # where the location is asked for, not refused unasked)
    # gets confirm() answered as dismissed, print() a no-op and the location denied (geolocation error 1),
    # with no dialog or question shown.
    "LessTrustedWebLimits": ["420", "200", "--delay", "12000", "--expect-state", "801", "title", "secure:true confirm:false print:off geo:1"],
    # html under an https base: the page has the base's origin and its relative image loads from there.
    "WebViewBase": ["420", "220", "--delay", "10000", "--expect-state", "3", "title", "loaded at https://raw.githubusercontent.com"],
    "WebViews": ["420", "300", "--delay", "10000", "--expect-state", "2", "title", "Hello Windows (script ran)",
                 "--expect-action", "web.loaded", "--expect-action", "web.url"],
    "Maps": ["420", "330", "--drag", "2", "200", "110", "120", "70", "--delay", "6000", "--expect-log", "Map 2 tiles: "],
    "SymbolMix": ["820", "300"],
    "UserLocations": ["420", "200", "--delay", "6000", "--expect-log", "; user location: "],
    # 20 s: Media Foundation's first open on a cold runner has taken more than 8 s (x64 twice, arm64 once).
    "VideoPlayers": ["420", "300", "--set-value", "2", "{test_files_url}/Media/one-second.mp4", "--delay", "20000",
                     "--expect-log", "VideoPlayer 2 opened", "--expect-log", "VideoPlayer 4 could not play"],
    # A host policy decides for the app's own videos too: refused, an https video is not opened.
    "RefusedMedia": ["420", "200", "--refuse-media", "--delay", "3000",
                     "--expect-log", "Not playing https://example.com/clip.mp4 for element 2 of window"],
    # JSON from a server plays no address of another scheme than file, http and https (the default policy).
    "LessTrustedVideos": ["420", "160", "--delay", "4000",
                          "--expect-log", "Not playing rtsp://example.com/stream for element 501 of window",
                          "--expect-log", "Not playing ms-appdata:///local/clip.mp4 for element 502 of window",
                          # A drive path is a local file to Windows' player: asked as a file read, not as media.
                          "--expect-log", "Not reading C:/Windows/Media/clip.mp4 for element 503"],
    "SplitViews": ["420", "260", "--drag", "2", "120.5", "45", "180.5", "45", "--expect-width", "3", "180"],
    "TableCells": ["420", "260", "--add-row", "2", "Write|false|star|false|{test_files_url}/Images/sample_image.png|Open",
                   "--add-row", "2", "Test|true|heart|true|{test_files_url}/Images/sample_image.png|Open", "--wait",
                   "--invoke-part", "2", "0", "--expect-action", "open.pressed", "--on-action", "open.pressed", "3", "Pressed row 0"],
    "Tables": ["420", "330", "--add-rows", "2", "100", "File #.txt|Document|# KB", "--add-row", "3", "Build|Run",
               "--add-row", "3", "Test|Run", "--wait", "--select-part", "2", "2", "--expect-action", "table.selected",
               "--on-action", "table.selected", "4", "Selected File 3.txt",
               "--drag", "2", "311.5", "10", "271.5", "10"],
    # The app's own Image and AsyncImage show a local file; the same file named by JSON from a server (Image,
    # AsyncImage, Canvas, List and Table cells, VideoPlayer) is refused, outside the app's resources.
    "LessTrustedFiles": ["420", "330", "--set-value", "5", "{test_files_url}/Images/sample_image.png", "--delay", "4000",
                         "--set-value", "405", "{test_files_url}/Images/sample_image.png",
                         "--set-value", "406", "{test_files_url}/Media/one-second.mp4",
                         "--add-row", "403", "Images/sample_image.png",
                         "--add-row", "404", "Images/sample_image.png|{test_files_url}/Images/sample_image.png",
                         "--delay", "1000",
                         "--expect-log", "for element 401: the trust policy refuses it",
                         "--expect-log", "for element 402: the trust policy refuses it",
                         "--expect-log", "for element 403: the trust policy refuses it",
                         "--expect-log", "for element 404: the trust policy refuses it",
                         "--expect-log", "for element 405: the trust policy refuses it",
                         "--expect-log", "for element 406: the trust policy refuses it",
                         "--expect-log", "for element 407: less-trusted content reads no network or device path",
                         "--expect-log", "for element 408: less-trusted content reads no network or device path",
                         "--expect-log", "Not loading C:/Windows/Web/Screen/img100.jpg for element 409: less-trusted content"],
    # JSON from a server loads no local file outside the app's resources, whatever form its Windows path has
    # (backslashes, forward slashes, a drive-relative path, an 8.3 short name, "..", a file: URL). Core's
    # refusal line names the element, so each element's line is one only the trust policy writes.
    "LessTrustedLocalFiles": ["420", "260", "--delay", "4000"]
                             + [option for element in range(851, 857)
                                for option in ["--expect-log", f"LoadableView {element}: not loading "]]
                             + ["--expect-log", ": the trust policy refuses it"],
    # JSON from a server: its LoadableView loads no file on a share (never touched).
    # The share on this machine (807) is the one check_share_reads shares and watches.
    "LessTrustedShares": ["420", "300", "--delay", "4000"]
                         + [option for element in range(801, 812)
                            for option in ["--expect-log", f"for element {element}: less-trusted content reads no network or device path"]],
    # ActionUI JSON in the program's folder (the app's resources) is trusted, its path in any case: its links
    # open Windows' settings, which a server's cannot. --no-launch: nothing is opened.
    "TrustedResources": ["420", "160", "--no-launch", "--set-value", "3", "{program_folder}\\BundledLinks.json",
                         "--set-value", "4", "{program_folder_upper}\\BUNDLEDLINKSUPPER.JSON", "--delay", "1000",
                         "--invoke", "901", "--invoke", "951",
                         "--expect-log", "Link 901: opening ms-settings:display",
                         "--expect-log", "Link 951: opening ms-settings:display"],
    # An image file that declares 9000 x 9000 pixels (in 10 KB) is not decoded: the photo symbol, logged.
    "ImageDecodeCap": ["420", "120", "--set-value", "6", "{test_files_url}/Images/declares-81-megapixels.png", "--delay", "1000",
                       "--expect-log", "Image not shown: Images/declares-81-megapixels.png is 9000 x 9000 pixels",
                       "--expect-log", "TestFiles/Images/declares-81-megapixels.png is 9000 x 9000 pixels"],
    "AsyncImages": ["460", "340", "--set-value", "7", "{test_files_url}/Images/sample_image.png",
                    "--set-value", "8", "{test_files_url}/Images/ActionUIDemo.svg"],
    "Menus": ["420", "260", "--invoke-menu-item", "2", "0", "--toggle-menu-item", "2", "3",
              "--expect-action", "menu.copy", "--expect-action", "menu.grid",
              "--on-action", "menu.grid", "12", "Copied, then the grid turned on"],
    "Toolbars": ["420", "300", "--invoke", "15", "--invoke", "20", "--expect-action", "toolbar.add",
                 "--expect-action", "toolbar.export", "--on-action", "toolbar.export", "3", "Added, then exported"],
    "NavigationToolbars": ["420", "300", "--invoke", "6", "--invoke", "31", "--invoke", "12", "--wait", "--invoke", "24",
                           "--expect-action", "nav.compose", "--expect-action", "nav.refresh", "--expect-action", "nav.reply"],
    "FloorChanges": ["420", "300", "--set-property", "3", "padding", "40", "--set-property", "7", "padding", "40"],
    "Fonts": ["480", "480"],
    "Scroll": ["360", "300", "--scroll", "3", "0", "50"],
    "Shapes": ["420", "340"],
    "GreedyRows": ["420", "220"],
    "NestedStacks": ["420", "260"],
    "ScrollShare": ["280", "260", "--scroll", "3", "0", "40"],
    "Controls": ["240", "220", "--invoke", "3", "--expect-action", "button.pressed",
                 "--on-action", "button.pressed", "2", "Pressed through UI Automation"],
    "Inputs": ["360", "260", "--toggle", "3", "--toggle", "4", "--set-text", "6", "typed through UI Automation",
               "--expect-action", "checkbox.changed", "--expect-action", "switch.changed",
               "--expect-action", "field.changed",
               "--on-action", "checkbox.changed", "2", "The check box changed",
               "--on-action", "field.changed", "5", "The field changed"],
}


def run_step(name, command, results, env, cwd=REPO_DIR, timeout=STEP_TIMEOUT_SECONDS):
    """Runs `command` in `cwd`, writing its combined output to results/<name>.log.
    Returns a dict with the step's name, exit status, duration and a note."""
    log_path = results / f"{name}.log"
    started = time.monotonic()
    status = None
    note = ""
    with open(log_path, "w", encoding="utf-8", errors="replace") as log:
        log.write(f"$ {' '.join(str(part) for part in command)}\n(cwd {cwd})\n\n")
        log.flush()
        try:
            completed = subprocess.run([str(part) for part in command], cwd=cwd, env=env, stdout=log,
                                       stderr=subprocess.STDOUT, timeout=timeout)
            status = completed.returncode
            if status > 255 or status < 0:
                # A Windows exception code such as 0xC0000409 (fail-fast) reads better in hex.
                note = f"exit 0x{status & 0xFFFFFFFF:08X}"
        except FileNotFoundError as error:
            note = f"could not start (the command or its current folder is missing): {error}"
            log.write(f"\n{note}\n")
        except OSError as error:
            # A current folder Windows cannot enter (on a share), for one.
            note = f"could not start: {error}"
            log.write(f"\n{note}\n")
        except subprocess.TimeoutExpired:
            note = f"timed out after {timeout} s"
            log.write(f"\n{note}\n")
    seconds = round(time.monotonic() - started, 1)
    print(f"{name}: status {status} in {seconds} s {note}".rstrip(), flush=True)
    return {"step": name, "status": status, "seconds": seconds, "note": note, "log": log_path.name}


def capture(command):
    """The stripped output of a short informational command, or the error it raised."""
    try:
        completed = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                   text=True, timeout=120)
    except (FileNotFoundError, subprocess.TimeoutExpired) as error:
        return f"<{error}>"
    return completed.stdout.strip()


def environment_facts():
    return {
        "date_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
        "platform": platform.platform(),
        "machine": platform.machine(),
        "swift_version": capture(["swift", "--version"]).replace("\n", " "),
        "commit": capture(["git", "-C", str(REPO_DIR), "rev-parse", "HEAD"]),
        "runner_image": (os.environ.get("ImageOS", "") + " " + os.environ.get("ImageVersion", "")).strip(),
    }


def xctest_counts(log_path):
    """The 'Executed N tests, with M failures' line under XCTest's 'All tests' suite, as numbers;
    None when the run printed no total (it crashed or ran nothing). A crashed run's last
    'Executed' line belongs to whichever suite finished last, not to the whole run."""
    text = log_path.read_text(encoding="utf-8", errors="replace")
    matches = re.findall(r"Test Suite 'All tests' (?:passed|failed) at [^\n]*\n"
                         r"\s*Executed (\d+) tests?, with (\d+) failures?", text)
    if not matches:
        return None
    executed, failures = matches[-1]
    return {"executed": int(executed), "failures": int(failures)}


def testing_counts(log_path):
    """Swift Testing's closing line ('Test run with N tests ... passed' or '... failed ... with M
    issues') as numbers; None when it printed none (no Swift Testing tests ran)."""
    text = ANSI_ESCAPE.sub("", log_path.read_text(encoding="utf-8", errors="replace"))
    matches = re.findall(r"Test run with (\d+) tests?\b[^\n]*?\b(passed|failed)(?:[^\n]*?with (\d+) issues?)?", text)
    if not matches:
        return None
    # swift test runs Swift Testing once per test product (an empty run after the real one, measured): all of them.
    return {"executed": sum(int(count) for count, _, _ in matches),
            "passed": all(outcome == "passed" for _, outcome, _ in matches),
            "issues": sum(int(issues or 0) for _, _, issues in matches)}


def check_verifier_tool(results, summary):
    """Builds Apps/ActionUIVerifier's actionui-verify and runs it on the parity fixtures: a valid
    UI description (exit 0, or 2 for warnings only) and one with errors (exit 1). It finds the schemas in
    this checkout, as a tool built from one does. True when both answered so."""
    scratch = ["--scratch-path", str(REPO_DIR / ".build" / "ci-windows-verifier")]
    package = ["--package-path", str(REPO_DIR / "Apps" / "ActionUIVerifier")]
    build = run_step("verifier-build", ["swift", "build"] + package + scratch, results, dict(os.environ))
    summary["steps"].append(build)
    if build["status"] == 0 and fails_on_warnings(build, results, summary):
        return False
    if build["status"] != 0:
        summary["errors"] = first_errors(results / build["log"])
        return False
    shown = subprocess.run(["swift", "build", "--show-bin-path"] + package + scratch, capture_output=True, text=True)
    tool = Path(shown.stdout.strip()) / "actionui-verify.exe"
    fixtures = REPO_DIR / "ActionUIVerifierTests" / "Parity" / "fixtures"
    passed = True
    for name, accepted in (("good-chart-nested.json", (0, 2)), ("bad-view.json", (1,))):
        step = run_step(f"verifier-{name.removesuffix('.json')}", [tool, fixtures / name], results, dict(os.environ))
        summary["steps"].append(step)
        answered = step["status"] in accepted
        summary["findings"].append(f"actionui-verify {name}: exit {step['status']} ({'as expected' if answered else 'NOT as expected'})")
        passed = passed and answered
        # Not a failure of the step itself: the exit code is the answer.
        step["status"] = 0 if answered else step["status"]
    return passed


def build_warnings(log_path, limit=40):
    """The distinct warnings of a Swift build log, first `limit` of them: the compiler's ('path:line:column:
    warning:'), the linker's (lld-link) and SwiftPM's about files a target does not handle. Not the build
    system's notes about stale objects, which a renamed file leaves once. The builds fail on them: a warning is
    not ignored. SwiftPM repeats a warning only for a file it compiles again, so a run that reuses a scratch
    folder (the VM's) may pass on warnings a fresh build reports; GitHub's builds are fresh."""
    text = ANSI_ESCAPE.sub("", log_path.read_text(encoding="utf-8", errors="replace"))
    found = re.findall(r"^\S.*:\d+:\d+: warning: .*$", text, flags=re.MULTILINE)
    found += [line for line in text.splitlines()
              if (line.startswith("warning:") and "which are unhandled" in line) or "lld-link: warning" in line]
    seen = []
    for line in found:
        if line not in seen:
            seen.append(line)
    return seen[:limit]


def fails_on_warnings(step, results, summary):
    """True when the step's log has build warnings (build_warnings): they become the summary's errors and a
    finding, and the step counts as failed."""
    warnings = build_warnings(results / step["log"])
    if not warnings:
        return False
    summary["errors"] = warnings
    summary.setdefault("findings", []).append(f"{step['step']}: {len(warnings)} warning(s), which fail the build")
    return True


def first_errors(log_path, limit=40):
    """The distinct 'path:line:column: error:' lines of a log, without color codes, first `limit`
    of them; else the distinct lines with 'error: ' or an MSVC 'error C2440:' / 'error LNK2019:'
    (a failed link, a failed command, an MSVC compile)."""
    text = ANSI_ESCAPE.sub("", log_path.read_text(encoding="utf-8", errors="replace"))
    located = re.findall(r"^\S.*:\d+:\d+: error: .*$", text, flags=re.MULTILINE)
    if not located:
        msvc_error = re.compile(r"\berror [A-Z]+\d{4}:")
        located = [line for line in text.splitlines() if "error: " in line or msvc_error.search(line)]
    seen = []
    for line in located:
        if line not in seen:
            seen.append(line)
        if len(seen) >= limit:
            break
    return seen


def write_summary(results, summary):
    (results / "summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    title = f"Windows {summary['environment']['machine']}: {summary['name']}"
    lines = [f"## {title}: {'passed' if summary['passed'] else 'FAILED'}", ""]
    for key, value in summary["environment"].items():
        lines.append(f"- {key}: {value}")
    lines += ["", "| Step | Status | Seconds | Note |", "|---|---|---|---|"]
    for step in summary["steps"]:
        lines.append(f"| {step['step']} | {step['status']} | {step['seconds']} | {step['note']} |")
    if summary.get("tests"):
        lines += ["", f"Tests: {summary['tests']['executed']} executed, "
                      f"{summary['tests']['failures']} failures"]
    if summary.get("findings"):
        lines += ["", "Findings:", ""] + [f"- {finding}" for finding in summary["findings"]]
    if summary.get("errors"):
        lines += ["", "First errors:", "", "```"] + summary["errors"] + ["```"]
    text = "\n".join(lines) + "\n"
    (results / "summary.md").write_text(text, encoding="utf-8")
    step_summary = os.environ.get("GITHUB_STEP_SUMMARY", "")
    if step_summary:
        with open(step_summary, "a", encoding="utf-8") as handle:
            handle.write(text)
    print(text, flush=True)


def check_core(results):
    env = dict(os.environ, ACTIONUI_CORE_ONLY="1")
    # --manifest-cache none: the package's exclude lists come from the folder listing (Package.swift).
    scratch = ["--scratch-path", str(REPO_DIR / ".build" / "ci-windows-core"), "--manifest-cache", "none"]
    summary = {"name": "core builds and passes its tests", "environment": environment_facts(),
               "steps": [], "passed": False}
    build = run_step("core-build", ["swift", "build", "--build-tests"] + scratch, results, env)
    summary["steps"].append(build)
    if build["status"] != 0 or fails_on_warnings(build, results, summary):
        if build["status"] != 0:
            summary["errors"] = first_errors(results / build["log"])
        write_summary(results, summary)
        return 1
    test = run_step("core-test", ["swift", "test", "--skip-build"] + scratch, results, env)
    summary["steps"].append(test)
    tests = xctest_counts(results / test["log"])
    summary["tests"] = tests
    # The verifier's tests (Swift Testing): coreCheckPackage adds them on Windows.
    testing = testing_counts(results / test["log"])
    summary["swift_testing"] = testing
    summary["findings"] = [f"Swift Testing: {testing['executed']} tests, {'passed' if testing['passed'] else 'FAILED'}"
                           if testing else "Swift Testing: no run"]
    if test["status"] != 0:
        summary["errors"] = first_errors(results / test["log"])
    # A zero exit with no XCTest total, or a total of none, ran nothing: not a pass. Likewise for
    # Swift Testing, which reports "Test run with 0 tests ... passed" when no target has its tests.
    summary["passed"] = (test["status"] == 0 and tests is not None and tests["executed"] > 0
                         and testing is not None and testing["passed"] and testing["executed"] > 0)
    summary["passed"] = check_verifier_tool(results, summary) and summary["passed"]
    summary["passed"] = check_overlay_packages(results, summary) and summary["passed"]
    write_summary(results, summary)
    return 0 if summary["passed"] else 1


# Packages ActionUI depends on, as their working trees, for a Windows check before their release: a CI-only commit
# puts each in OVERLAY_DIR/<package name> (a released ActionUI has none).
OVERLAY_DIR = REPO_DIR / ".ci-overlay"


def overlay_packages():
    """The packages in OVERLAY_DIR (folders with a Package.swift), by name."""
    if not OVERLAY_DIR.is_dir():
        return []
    return sorted(folder for folder in OVERLAY_DIR.iterdir() if (folder / "Package.swift").is_file())


def dependency_identities(node):
    """The identities of a `swift package show-dependencies --format json` tree, lowercased, the root's own included."""
    identities = {str(node.get("identity", node.get("name", ""))).lower()}
    for child in node.get("dependencies", []):
        identities |= dependency_identities(child)
    return identities


def edit_overlay_dependencies(package_arguments, results, summary, env):
    """Puts each overlay package the package of `package_arguments` (--package-path, --scratch-path) depends on in edit
    mode on its working tree (swift package edit), so the build uses it in place of its release. True when there was
    none, or each was put in edit mode."""
    overlays = overlay_packages()
    if not overlays:
        return True
    shown = subprocess.run(["swift", "package"] + package_arguments + ["show-dependencies", "--format", "json"],
                           capture_output=True, text=True, env=env)
    try:
        identities = dependency_identities(json.loads(shown.stdout))
    except (json.JSONDecodeError, AttributeError):
        summary["findings"].append(f"overlays: the dependencies could not be listed: {shown.stderr.strip()[-300:]}")
        return False
    for folder in overlays:
        if folder.name.lower() not in identities:
            continue
        step = run_step(f"overlay-{folder.name}-edit", ["swift", "package"] + package_arguments
                        + ["edit", folder.name.lower(), "--path", str(folder)], results, env)
        summary["steps"].append(step)
        if step["status"] != 0:
            summary["findings"].append(f"{folder.name} (working tree): FAILED to put it in edit mode")
            return False
        summary["findings"].append(f"{folder.name} (working tree): built in place of its release")
    return True


def check_overlay_packages(results, summary):
    """Builds each overlay package and runs its tests. True when each built and passed its tests (with at least
    one test run), or when there are none."""
    passed = True
    for folder in overlay_packages():
        name = folder.name
        arguments = ["--package-path", str(folder), "--scratch-path", str(REPO_DIR / ".build" / f"ci-overlay-{name}")]
        build = run_step(f"overlay-{name}-build", ["swift", "build", "--build-tests"] + arguments, results,
                         dict(os.environ))
        summary["steps"].append(build)
        if build["status"] != 0:
            summary.setdefault("errors", []).extend(first_errors(results / build["log"]))
            summary["findings"].append(f"{name} (working tree): FAILED to build")
            passed = False
            continue
        test = run_step(f"overlay-{name}-test", ["swift", "test", "--skip-build"] + arguments, results, dict(os.environ))
        summary["steps"].append(test)
        if test["status"] != 0:
            summary.setdefault("errors", []).extend(first_errors(results / test["log"]))
        counts = xctest_counts(results / test["log"])
        ran = counts is not None and counts["executed"] > 0
        summary["findings"].append(f"{name} (working tree): {counts['executed'] if counts else 0} XCTest tests, "
                                   f"{'passed' if test['status'] == 0 and ran else 'FAILED'}")
        passed = passed and test["status"] == 0 and ran
    return passed


# MARK: - The WinUI shim


def windows_arch():
    """'arm64' or 'x64': the names the NuGet packages and vcvarsall.bat use."""
    return "arm64" if platform.machine().upper() == "ARM64" else "x64"


# Real mouse input (--drag, and the --expect-width checks that follow one) needs the preview's window in
# front. On the Arm64 runner a system window (Windows.UI.Core.CoreWindow, in another program) stays in
# front and Windows refuses to bring another one there, so those options run on x64 only.
REAL_INPUT_OPTIONS = {"--drag": 5, "--wheel": 5, "--expect-width": 2}
# What a test file's --drag must cause, checked only where the drag runs (x64).
REAL_INPUT_EXPECTATIONS = {
    "Maps": ["--expect-action", "map.moved", "--expect-action", "map.changed"],
    "Hovers": ["--expect-action", "hover.changed"],
    "ChartSelection": ["--expect-action", "chart.selection.changed"],
    "ChartScroll": ["--expect-action", "chart.selection.changed"],
}


# The same for the add-on elements' test files (ActionUIWinUI/Apps/Preview/TestFiles/AddOns), rendered by the preview tool with the
# add-ons ActionUI.dll links (ActionUIWinUIAddOnPreview).
ADD_ON_PREVIEW_OPTIONS = {
    # The Diff add-on's element (linked into the program through ActionUILinkedAddOns_register): the add-on's example, a
    # diff with collapsed context (two gaps), and two identical texts ("No changes"). None shows the placeholder, and
    # each takes the width it is offered (520 less the stack's padding), as the SwiftUI view does.
    "Diff": ["520", "420",
             "--expect-automation", "2", "name", "Diff (add-on element): greet(_:) before and after",
             "--expect-width", "3", "496", "--expect-width", "4", "496", "--expect-width", "5", "496",
             "--forbid-log", "Diff is not available on Windows yet", "--forbid-log", "creating the element Diff",
             "--forbid-log", "Diff: "],
    # The CachedImage add-on's element over AsyncImageCache's Windows engine: a data: image (40 x 30), the preview's
    # sample image (160 x 100) by file URL in two elements (one load, one shared WinUI source), and an empty box with
    # a size hint. Each box takes its frame's width and the image's aspect for its height; WinUI shows every image
    # (no failure line).
    "CachedImage": ["520", "360",
                    "--set-value", "5", "{test_files_url}/../Images/sample_image.png",
                    "--set-value", "6", "{test_files_url}/../Images/sample_image.png",
                    "--delay", "3000",
                    "--expect-width", "4", "120", "--expect-height", "4", "90",
                    "--expect-width", "5", "160", "--expect-height", "5", "100",
                    "--expect-width", "6", "160", "--expect-height", "6", "100",
                    "--expect-width", "7", "320", "--expect-height", "7", "180",
                    "--forbid-log", "CachedImage is not available on Windows yet",
                    "--forbid-log", "creating the element CachedImage", "--forbid-log", "CachedImage: "],
    # The RichText add-on's element: headings, inline styles, a link, nested lists, a quote, a code block, a rule, a
    # table and an image in one RichTextBlock. It takes the width it is offered; no failure line.
    "RichText": ["520", "620", "--expect-width", "2", "496",
                 "--forbid-log", "RichText is not available on Windows yet", "--forbid-log", "creating the element RichText",
                 "--forbid-log", "RichText: "],
    # Its decorations where they are hardest to place: inline code at a line's start and wrapping onto the next line,
    # a quote with a nested quote (only the innermost bar) and a rule inside, a highlighted code block that ends in an
    # empty line. Narrow, so the long inline code wraps; no failure line.
    "RichTextDecorations": ["360", "520", "--expect-width", "2", "336",
                            "--forbid-log", "creating the element RichText", "--forbid-log", "RichText: "],
    # A Diff in JSON from a server reads no file on a share or a device, whatever form the path has: the add-on asks
    # the trust policy about the full path Windows opens (two slashes become backslashes, NUL is \\.\NUL), so each
    # refusal names that path. The share (actionui-canary, CANARY_SHARE) is the one check_share_reads shares and
    # watches; 904 and 905 (a relative path and the current drive's root) are judged there with the current folder
    # on the share.
    "LessTrustedDiffShares": ["520", "360", "--delay", "4000"]
                             + [option for element in [901, 902]
                                for option in ["--expect-log", f"Not reading \\\\localhost\\actionui-canary\\old.txt "
                                                               f"for element {element}: less-trusted content reads no network"]]
                             + ["--expect-log", "Not reading \\\\?\\UNC\\localhost\\actionui-canary\\old.txt for element 903: "
                                                "less-trusted content reads no network",
                                "--expect-log", "Not reading \\\\.\\NUL for element 906: less-trusted content reads no network"],
}


def without_real_input(options):
    """The preview options with --drag, --wheel and --expect-width (and their values) left out."""
    kept = []
    position = 0
    while position < len(options):
        count = REAL_INPUT_OPTIONS.get(options[position])
        if count is None:
            kept.append(options[position])
            position += 1
        else:
            position += 1 + count
    return kept


def sha256_of(path):
    """The file's SHA-256, as lowercase hex."""
    digest = hashlib.sha256()
    with open(path, "rb") as file:
        for block in iter(lambda: file.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def fetch_packages(work, findings):
    """Downloads and extracts WINUI_PACKAGES into work/packages/<id>/ (kept between runs). Every
    archive, downloaded or kept, must match its WINUI_PACKAGE_SHA256 value before it is used; one that
    does not is deleted and the fetch fails. Returns {id: folder}."""
    folders = {}
    packages = work / "packages"
    packages.mkdir(parents=True, exist_ok=True)
    for package_id, version in WINUI_PACKAGES.items():
        name = f"{package_id}.{version}"
        expected = WINUI_PACKAGE_SHA256.get(name)
        if expected is None:
            raise RuntimeError(f"no SHA-256 for {name} in WINUI_PACKAGE_SHA256")
        archive = packages / f"{name}.nupkg"
        folder = packages / name
        if archive.is_file():
            actual = sha256_of(archive)
            if actual != expected:
                archive.unlink()
                if folder.exists():
                    shutil.rmtree(folder)
                raise RuntimeError(f"the kept {archive.name} has SHA-256 {actual}, not {expected}; deleted")
        else:
            url = f"https://api.nuget.org/v3-flatcontainer/{package_id}/{version}/{name}.nupkg"
            partial = archive.with_suffix(".partial")
            urllib.request.urlretrieve(url, partial)
            actual = sha256_of(partial)
            if actual != expected:
                partial.unlink()
                raise RuntimeError(f"the downloaded {archive.name} has SHA-256 {actual}, not {expected}")
            partial.replace(archive)
            if folder.exists():
                shutil.rmtree(folder)
        if not folder.exists():
            # Extracted beside the folder and renamed, so an interrupted run leaves no half folder
            # for the next run to reuse.
            extracting = folder.with_name(folder.name + ".extracting")
            if extracting.exists():
                shutil.rmtree(extracting)
            with zipfile.ZipFile(archive) as zipped:
                zipped.extractall(extracting)
            extracting.replace(folder)
        folders[package_id] = folder
    findings.append("packages (SHA-256 checked): " + ", ".join(f"{key} {value}" for key, value in WINUI_PACKAGES.items()))
    return folders


def newest_winmd_files(folders):
    """Every .winmd under the packages' metadata folders and directly in lib/ (WebView2); where the
    same file name is in several version folders (metadata/10.0.17763.0/...), the one in the
    highest version."""
    def version_key(path):
        return [int(part) if part.isdigit() else -1 for part in path.parent.name.split(".")]
    chosen = {}
    for folder in folders.values():
        candidates = list((folder / "metadata").rglob("*.winmd")) if (folder / "metadata").is_dir() else []
        candidates += list((folder / "lib").glob("*.winmd")) if (folder / "lib").is_dir() else []
        for winmd in sorted(candidates):
            current = chosen.get(winmd.name)
            if current is None or version_key(winmd) > version_key(current):
                chosen[winmd.name] = winmd
    return sorted(chosen.values())


def msvc_environment(arch, results):
    """The environment of the newest Visual Studio's developer prompt for `arch`
    (vcvarsall.bat x64 or arm64), and the vcvarsall.bat path."""
    program_files_x86 = os.environ.get("ProgramFiles(x86)", r"C:\Program Files (x86)")
    vswhere = Path(program_files_x86) / "Microsoft Visual Studio" / "Installer" / "vswhere.exe"
    install = capture([str(vswhere), "-latest", "-products", "*", "-property", "installationPath"])
    lines = install.splitlines()
    vcvars = Path(lines[-1].strip() if lines else "") / "VC" / "Auxiliary" / "Build" / "vcvarsall.bat"
    if not vcvars.is_file():
        raise RuntimeError(f"no vcvarsall.bat (vswhere said: {install!r})")
    script = results / "vcvars-environment.bat"
    script.write_text(f'@call "{vcvars}" {arch} >nul\r\n@set\r\n', encoding="ascii")
    completed = subprocess.run(["cmd", "/c", str(script)], stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                               text=True, timeout=300)
    environment = {}
    for line in completed.stdout.splitlines():
        if "=" in line and not line.startswith("="):
            key, value = line.split("=", 1)
            environment[key] = value
    if "INCLUDE" not in environment:
        raise RuntimeError(f"{vcvars} {arch} gave no INCLUDE")
    return environment, vcvars


def resolve_tool(name, env):
    """`name` looked up on env's Path: Windows looks a bare program name up on this process's PATH,
    not on the child's."""
    resolved = shutil.which(name, path=env.get("Path") or env.get("PATH") or "")
    return resolved if resolved else name


def generate_projection(folders, work, msvc, results, summary):
    """Runs cppwinrt.exe over the Windows SDK and the packages' metadata into work/generated,
    unless a projection from the same inputs is already there. Returns the folder or None."""
    generated = work / "generated"
    stamp = generated / "inputs.json"
    inputs = {"packages": WINUI_PACKAGES, "windows_sdk": msvc.get("WindowsSDKVersion", "")}
    if stamp.is_file() and json.loads(stamp.read_text(encoding="utf-8")) == inputs:
        summary["findings"].append("C++/WinRT projection: reused (same packages and Windows SDK)")
        return generated
    if generated.exists():
        shutil.rmtree(generated)
    winmds = newest_winmd_files(folders)
    command = [folders["microsoft.windows.cppwinrt"] / "bin" / "cppwinrt.exe", "-input", "sdk"]
    for winmd in winmds:
        command += ["-input", winmd]
    command += ["-output", generated]
    step = run_step("shim-cppwinrt", command, results, msvc, cwd=work, timeout=900)
    summary["steps"].append(step)
    if step["status"] != 0:
        return None
    stamp.write_text(json.dumps(inputs, indent=2) + "\n", encoding="utf-8")
    summary["findings"].append(f"C++/WinRT projection: generated from {len(winmds)} winmd files and the Windows SDK")
    return generated


def install_runtime(folders, arch, results):
    msix_folder = folders["microsoft.windowsappsdk.runtime"] / "tools" / "MSIX" / f"win10-{arch}"
    lines = ["$ErrorActionPreference = 'Stop'"]
    for name in WINUI_RUNTIME_MSIX:
        lines.append(f"Write-Output 'Add-AppxPackage {name}'")
        lines.append(f"Add-AppxPackage -Path '{msix_folder / name}' -ForceApplicationShutdown")
    lines.append("Get-AppxPackage -Name '*WindowsAppRuntime*' | Format-Table -AutoSize Name, Version, Architecture")
    script = results / "install-runtime.ps1"
    script.write_text("\r\n".join(lines) + "\r\n", encoding="utf-8")
    return run_step("shim-runtime", ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script],
                    results, dict(os.environ), cwd=results, timeout=600)


# The WebView2 runtime's registration (its EdgeUpdate client), and Microsoft's installer for it (the
# evergreen bootstrapper). Windows 11 ships the runtime; Windows Server does not.
WEBVIEW2_RUNTIME_KEY = r"SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}"
WEBVIEW2_BOOTSTRAPPER = "https://go.microsoft.com/fwlink/p/?LinkId=2124703"


POWERSHELL = Path(os.environ.get("SystemRoot", r"C:\Windows")) / "System32" / "WindowsPowerShell" / "v1.0" / "powershell.exe"


def microsoft_signature(path):
    """Whether Windows finds a valid Authenticode signature on `path` made by Microsoft Corporation.
    Returns (True or False, what Windows said: the status and the signer's name)."""
    # The path goes in through the environment, so no quoting of it reaches PowerShell. The signer's
    # name comes one part per line, with a value that holds a comma quoted, so the organization is
    # compared as a whole line: text such as "O=Microsoft Corporation" inside another part cannot match.
    script = ("$s = Get-AuthenticodeSignature -LiteralPath $env:ACTIONUI_SIGNED_FILE; "
              "Write-Output $s.Status; "
              "if ($s.SignerCertificate) { Write-Output $s.SignerCertificate.SubjectName.Decode("
              "[System.Security.Cryptography.X509Certificates.X500DistinguishedNameFlags]::UseNewLines) }")
    if not path.is_file():
        return False, "no such file"
    # Without PSModulePath: when this script runs under PowerShell 7 (as on CI), Windows PowerShell would
    # inherit 7's module folders and fail to load 7's copy of the module that has Get-AuthenticodeSignature.
    env = {key: value for key, value in os.environ.items() if key.upper() != "PSMODULEPATH"}
    env["ACTIONUI_SIGNED_FILE"] = str(path)
    try:
        completed = subprocess.run([str(POWERSHELL), "-NoProfile", "-NonInteractive", "-Command", script],
                                   env=env, capture_output=True, text=True, errors="replace", timeout=120)
    except (OSError, subprocess.TimeoutExpired) as error:
        return False, f"Get-AuthenticodeSignature did not run: {error}"
    lines = [line.strip() for line in completed.stdout.splitlines() if line.strip()]
    status = lines[0] if lines else ""
    name = lines[1:]
    signed = completed.returncode == 0 and status == "Valid" and "O=Microsoft Corporation" in name
    said = f"{status or 'no status'}, signer {', '.join(name) or 'none'}"
    if not signed and completed.stderr.strip():
        said += f" (PowerShell: {' '.join(completed.stderr.split())[:300]})"
    return signed, said


def webview2_runtime_version():
    """The installed WebView2 runtime's version, from the registry (per machine or per user), or None."""
    import winreg
    places = [(winreg.HKEY_LOCAL_MACHINE, winreg.KEY_WOW64_32KEY), (winreg.HKEY_LOCAL_MACHINE, winreg.KEY_WOW64_64KEY),
              (winreg.HKEY_CURRENT_USER, 0)]
    for root, view in places:
        try:
            with winreg.OpenKey(root, WEBVIEW2_RUNTIME_KEY, 0, winreg.KEY_READ | view) as key:
                version, _ = winreg.QueryValueEx(key, "pv")
        except OSError:
            continue
        if version and version != "0.0.0.0":
            return version
    return None


def ensure_webview2_runtime(work, results, findings):
    """Installs the WebView2 runtime when it is missing (the WebView previews need it). Returns the
    installer's step, or None when the runtime was there."""
    version = webview2_runtime_version()
    if version:
        findings.append(f"WebView2 runtime {version}")
        return None
    installer = work / "MicrosoftEdgeWebview2Setup.exe"
    started = time.monotonic()
    try:
        urllib.request.urlretrieve(WEBVIEW2_BOOTSTRAPPER, installer)
    except Exception as error:  # the download failed
        findings.append(f"no WebView2 runtime, and its installer did not download: {error}")
        return {"step": "webview2-runtime", "status": 1, "seconds": round(time.monotonic() - started, 1),
                "note": "download failed", "log": ""}
    # Run only when Microsoft signed it: the address is a redirect, and the file is a program run as is.
    signed, said = microsoft_signature(installer)
    findings.append(f"WebView2 installer signature: {said}")
    if not signed:
        installer.unlink(missing_ok=True)
        findings.append("no WebView2 runtime: its installer is not signed by Microsoft; not run")
        return {"step": "webview2-runtime", "status": 1, "seconds": round(time.monotonic() - started, 1),
                "note": "installer not signed by Microsoft", "log": ""}
    step = run_step("webview2-runtime", [installer, "/silent", "/install"], results, dict(os.environ), cwd=work,
                    timeout=600)
    findings.append(f"WebView2 runtime installed: {webview2_runtime_version() or 'not found after installing'}")
    return step


def check_shim(results, install, swift=False):
    """The shim and its C smoke test; with `swift`, then the Swift package (windowsPackage) and its
    smoke test, ActionUIWinUISmoke, linked against the shim just built."""
    arch = windows_arch()
    name = ("WinUI shim and renderer build and drive a window from C and Swift" if swift
            else "WinUI shim builds and drives a window from C")
    summary = {"name": name, "environment": environment_facts(), "steps": [], "findings": [], "passed": False}
    findings = summary["findings"]

    def finish(passed):
        summary["passed"] = passed
        write_summary(results, summary)
        return 0 if passed else 1

    def failed_step(step):
        summary["errors"] = first_errors(results / step["log"])
        return finish(False)

    if platform.system() != "Windows":
        findings.append("not Windows: the shim builds on Windows only")
        return finish(False)
    work = SHIM_WORK
    work.mkdir(parents=True, exist_ok=True)
    started = time.monotonic()
    try:
        folders = fetch_packages(work, findings)
    except Exception as error:  # a download or an archive failed
        findings.append(f"fetching the NuGet packages failed: {error}")
        return finish(False)
    summary["steps"].append({"step": "shim-fetch", "status": 0, "seconds": round(time.monotonic() - started, 1),
                             "note": f"{len(folders)} packages", "log": ""})
    try:
        msvc, vcvars = msvc_environment(arch, results)
    except Exception as error:
        findings.append(f"no MSVC environment: {error}")
        return finish(False)
    findings.append(f"MSVC {msvc.get('VCToolsVersion', '?')} ({vcvars} {arch}), Windows SDK "
                    f"{msvc.get('WindowsSDKVersion', '?').strip(chr(92))}")

    generated = generate_projection(folders, work, msvc, results, summary)
    if generated is None:
        return failed_step(summary["steps"][-1])

    # The symbol outlines compiled into the shim (Scripts/prepare-windows-symbols.py, which needs fontTools).
    step = run_step("symbols-fonttools", [sys.executable, "-m", "pip", "install", "--quiet", "fonttools"], results,
                    dict(os.environ))
    summary["steps"].append(step)
    if step["status"] != 0:
        return failed_step(step)
    step = run_step("symbols-prepare", [sys.executable, REPO_DIR / "Scripts" / "prepare-windows-symbols.py"], results,
                    dict(os.environ))
    summary["steps"].append(step)
    if step["status"] != 0:
        return failed_step(step)

    out = work / arch
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    foundation = folders["microsoft.windowsappsdk.foundation"]
    includes = [f"/I{generated}", f"/I{SHIM_DIR / 'include'}", f"/I{SHIM_DIR / 'src'}"]
    includes += [f"/I{folder / 'include'}" for folder in folders.values() if (folder / "include").is_dir()]
    sources = sorted((SHIM_DIR / "src").glob("*.cpp"))
    # The shim's resources (Shim/resources/Shim.rc: the blank cursor), compiled for the linker to put in the DLL.
    resources = out / "Shim.res"
    step = run_step("shim-resources", [resolve_tool("rc", msvc), "/nologo", f"/fo{resources}",
                                       SHIM_DIR / "resources" / "Shim.rc"], results, msvc, cwd=SHIM_DIR / "resources")
    summary["steps"].append(step)
    if step["status"] != 0:
        return failed_step(step)
    command = [resolve_tool("cl", msvc), "/nologo", "/std:c++20", "/EHsc", "/permissive-", "/MD", "/O1",
               "/bigobj", "/utf-8", "/W3", "/WX", "/MP", "/DNOMINMAX"] + includes + sources + [resources,
               "/LD", f"/Fe{out / 'ActionUIWinUIShim.dll'}", f"/Fo{out}\\",
               "/link", "windowsapp.lib", "user32.lib", "ole32.lib", "shell32.lib",
               foundation / "lib" / "native" / arch / "Microsoft.WindowsAppRuntime.Bootstrap.lib"]
    step = run_step("shim-build", command, results, msvc, cwd=out)
    summary["steps"].append(step)
    if step["status"] != 0:
        return failed_step(step)

    tests = SHIM_DIR / "Tests"
    command = [resolve_tool("cl", msvc), "/nologo", "/std:c11", "/W4", "/WX", "/utf-8", f"/I{SHIM_DIR / 'include'}",
               tests / "ShimSmokeTest.c", f"/Fe{out / 'ShimSmokeTest.exe'}", f"/Fo{out}\\",
               "/link", out / "ActionUIWinUIShim.lib", "/MANIFEST:EMBED",
               f"/MANIFESTINPUT:{tests / 'ShimSmokeTest.exe.manifest'}"]
    step = run_step("smoke-build", command, results, msvc, cwd=out)
    summary["steps"].append(step)
    if step["status"] != 0:
        return failed_step(step)
    bootstrap = foundation / "runtimes" / f"win-{arch}" / "native" / "Microsoft.WindowsAppRuntime.Bootstrap.dll"
    # WinUI's WebView2 loads WebView2's WinRT component (the loader linked in) from the program's
    # folder, where an app's build puts it.
    webview_core = folders["microsoft.web.webview2"] / "runtimes" / f"win-{arch}" / "native_uap" / WEBVIEW2_CORE
    # The two Microsoft DLLs every program and the library package carry: copied only when Microsoft
    # signed them.
    for dll in [bootstrap, webview_core]:
        signed, said = microsoft_signature(dll)
        findings.append(f"{dll.name} signature: {said}")
        if not signed:
            findings.append(f"{dll.name} ({dll}) is not signed by Microsoft or is missing; not copied")
            return finish(False)
        shutil.copy2(dll, out / dll.name)

    if install:
        step = install_runtime(folders, arch, results)
        summary["steps"].append(step)
        if step["status"] != 0:
            return failed_step(step)
        # Not fatal: without it only the WebView previews fail, and say why.
        step = ensure_webview2_runtime(work, results, findings)
        if step is not None:
            summary["steps"].append(step)

    png = results / "shim-smoke.png"
    step = run_step("smoke-test", [out / "ShimSmokeTest.exe", png], results, dict(os.environ), cwd=out,
                    timeout=SMOKE_TIMEOUT_SECONDS)
    summary["steps"].append(step)
    findings += [line for line in (results / step["log"]).read_text(encoding="utf-8", errors="replace").splitlines()
                 if line.startswith("smoke:")]
    findings.append(f"ActionUIWinUIShim.dll: {(out / 'ActionUIWinUIShim.dll').stat().st_size} bytes")
    if not (step["status"] == 0 and png.is_file() and png.stat().st_size > 0):
        return finish(False)
    if not swift:
        return finish(True)
    # What a C++ host that runs its own WinUI application builds with: the projection's and the packages'
    # headers, the bootstrapper's import library.
    host_build = {"includes": includes,
                  "libraries": ["windowsapp.lib", "user32.lib", "ole32.lib",
                                foundation / "lib" / "native" / arch / "Microsoft.WindowsAppRuntime.Bootstrap.lib"],
                  # For the library package's notices.
                  "webview2_license": folders["microsoft.web.webview2"] / "LICENSE.txt"}
    return finish(check_swift_smoke(out, bootstrap, results, summary, msvc, host_build))


def check_viewer(shim_out, bin_path, results, summary, env):
    """Builds Apps/ActionUIViewer's Windows program (its own package, as on Linux) with the shim's import
    library, puts the shim's DLL, the bootstrapper, WebView2's Core DLL and the programs' manifest beside it,
    and runs it: a preview test file saved with --screenshot (exit 0, a PNG), and a file that cannot be
    loaded (exit 65, its error window saved). True when both answered so."""
    scratch = ["--scratch-path", str(REPO_DIR / ".build" / "ci-windows-viewer"), "--manifest-cache", "none"]
    package = ["--package-path", str(REPO_DIR / "Apps" / "ActionUIViewer")]
    step = run_step("viewer-build", ["swift", "build"] + package + scratch + ["-Xswiftc", f"-L{shim_out}"], results, env)
    summary["steps"].append(step)
    if step["status"] != 0:
        summary["errors"] = first_errors(results / step["log"])
        return False
    if fails_on_warnings(step, results, summary):
        return False
    shown = capture(["swift", "build"] + package + scratch + ["--show-bin-path"]).splitlines()
    viewer_bin = Path(shown[-1].strip()) if shown else Path()
    viewer = viewer_bin / "ActionUIViewer.exe"
    if not viewer.is_file():
        summary["findings"].append(f"viewer: no ActionUIViewer.exe in {viewer_bin}")
        return False
    for name in ["ActionUIWinUIShim.dll", "Microsoft.WindowsAppRuntime.Bootstrap.dll", WEBVIEW2_CORE]:
        shutil.copy2(bin_path / name, viewer_bin / name)
    shutil.copy2(REPO_DIR / "ActionUIWinUI" / "Apps" / "Smoke" / "ActionUIWinUISmoke.exe.manifest",
                 viewer_bin / "ActionUIViewer.exe.manifest")
    passed = True
    ui_file = REPO_DIR / "ActionUIWinUI" / "Apps" / "Preview" / "TestFiles" / "Controls.json"
    for name, path, expected in [("viewer-controls", ui_file, 0), ("viewer-missing", results / "no-such-file.json", 65)]:
        png = results / f"{name}.png"
        step = run_step(name, [viewer, path, "--screenshot", png], results, env, cwd=viewer_bin,
                        timeout=SMOKE_TIMEOUT_SECONDS)
        summary["steps"].append(step)
        answered = step["status"] == expected and png.is_file() and png.stat().st_size > 0
        if name == "viewer-missing":
            # The window says it in a short sentence with the file's name, not the raw error and its path.
            sentence = 'shows: The file "no-such-file.json" was not found.'
            if sentence not in (results / step["log"]).read_text(encoding="utf-8", errors="replace"):
                summary["findings"].append(f"viewer {path.name}: the window did not show the expected sentence")
                answered = False
        summary["findings"].append(f"viewer {path.name}: exit {step['status']}, "
                                   f"{'a PNG' if png.is_file() else 'no PNG'} ({'as expected' if answered else 'NOT as expected'})")
        # The exit code is the answer, not the step's failure.
        step["status"] = 0 if answered else (step["status"] or 1)
        passed = passed and answered
    return passed


# MARK: - The Windows library package and the language bindings

# The pinned commits of the symbol fonts the shim's outlines come from, and where their licenses are.
MATERIAL_COMMIT_FILE = REPO_DIR / "ActionUIAndroid" / "library" / "material-symbols-font.commit"
FLUENT_COMMIT_FILE = REPO_DIR / "Tools" / "fluent_symbols" / "fluent-icons-font.commit"
MATERIAL_LICENSE_URL = "https://raw.githubusercontent.com/google/material-design-icons/{commit}/LICENSE"
FLUENT_LICENSE_URL = "https://raw.githubusercontent.com/microsoft/fluentui-system-icons/{commit}/LICENSE"
# DLLs a program gets from Windows or the Visual C++ runtime it already has: never copied.
SYSTEM_DLL_PREFIXES = ("api-ms-win-", "ext-ms-", "vcruntime", "msvcp", "concrt", "ucrtbase", "dbghelp")
# DLLs the Windows App Runtime's framework package provides once installed (lowercase): never copied.
WINDOWS_APP_RUNTIME_DLLS = {"microsoft.windowsappruntime.dll"}


def dll_dependencies(dll, msvc):
    """The DLL names `dll` imports, its delay-loaded ones too (dumpbin /dependents)."""
    completed = subprocess.run([resolve_tool("dumpbin", msvc), "/nologo", "/dependents", str(dll)], env=msvc,
                               capture_output=True, text=True, errors="replace")
    return re.findall(r"^\s+(\S+\.dll)\s*$", completed.stdout, flags=re.MULTILINE | re.IGNORECASE)


def swift_runtime_folder(msvc):
    """The first folder on msvc's Path that holds swiftCore.dll (where the built programs find the Swift
    runtime), or None."""
    for entry in (msvc.get("Path") or msvc.get("PATH") or "").split(";"):
        if entry and (Path(entry) / "swiftCore.dll").is_file():
            return Path(entry)
    return None


def dll_closure(start, folders, msvc):
    """`start` and every DLL it loads, directly or not, found in `folders` (in order) and not part of
    Windows: what a program must carry beside ActionUI.dll. Returns (paths, names not found)."""
    windows = Path(os.environ.get("SystemRoot", r"C:\Windows")).resolve()
    found = {start.name.lower(): start}
    missing = set()
    pending = [start]
    while pending:
        for name in dll_dependencies(pending.pop(), msvc):
            key = name.lower()
            if key in found or key in missing or key.startswith(SYSTEM_DLL_PREFIXES):
                continue
            path = next((folder / name for folder in folders if (folder / name).is_file()), None)
            if path is None:
                missing.add(key)
                continue
            if windows in path.resolve().parents:
                missing.add(key)
                continue
            found[key] = path
            pending.append(path)
    return list(found.values()), sorted(missing)


def symbol_license(title, commit_file, url, lead):
    """A symbol font's notice: what the icons are, from which commit, then its license text."""
    commit = commit_file.read_text(encoding="utf-8").strip()
    with urllib.request.urlopen(url.format(commit=commit), timeout=120) as response:
        text = response.read().decode("utf-8")
    return f"{title}\n\n{lead.format(commit=commit)}\n\n{text}"


def make_library_package(bin_path, results, summary, msvc, webview2_license):
    """The Windows library package, the counterpart of Scripts/make-linux-library-package.sh's: what
    the language bindings (Python, Node.js, Rust) and C programs build against and ship.

        actionui-windows-<arch>/
          bin/       ActionUI.dll and every DLL it loads that Windows does not have: the WinUI shim,
                     the Windows App SDK bootstrapper, the Swift runtime; and WebView2's WinRT
                     component, which the shim loads from beside itself when a WebView is made
          lib/       ActionUI.lib, ActionUI.dll's import library
          include/   ActionUICAdapter/ActionUIC.h, ActionUIAppKitApplication/ActionUIApp.h,
                     ActionUIHostSurface/ActionUIHostSurface.h
          LICENSE.txt, LICENSE-MaterialSymbols.txt, LICENSE-FluentSystemIcons.txt (the symbol outlines in
          the shim), LICENSE-WebView2.txt (Microsoft.Web.WebView2.Core.dll)
          SHA256SUMS.txt: every other file's SHA-256

    A program copies bin/ beside itself (Windows finds a program's DLLs in its own folder). Returns the
    folder, or None (with findings) when something is missing."""
    package = REPO_DIR / ".build" / "ci-windows-package" / f"actionui-windows-{windows_arch()}"
    shutil.rmtree(package, ignore_errors=True)
    for folder in ["bin", "lib", "include/ActionUICAdapter", "include/ActionUIAppKitApplication",
                   "include/ActionUIHostSurface"]:
        (package / folder).mkdir(parents=True, exist_ok=True)
    # DLLs come from two places only: the build's folder and the Swift runtime's. Any other folder on
    # PATH could hold a DLL of the same name that would be shipped without anyone noticing.
    swift_runtime = swift_runtime_folder(msvc)
    if swift_runtime is None:
        summary["findings"].append("library package: no folder on PATH holds swiftCore.dll")
        return None
    summary["findings"].append(f"library package: the Swift runtime from {swift_runtime}")
    dlls, missing = dll_closure(bin_path / "ActionUI.dll", [bin_path, swift_runtime], msvc)
    # Every name not found must come from Windows or from the Windows App Runtime the program installs.
    system32 = Path(os.environ.get("SystemRoot", r"C:\Windows")) / "System32"
    unknown = [name for name in missing if name not in WINDOWS_APP_RUNTIME_DLLS and not (system32 / name).is_file()]
    if unknown:
        summary["findings"].append("library package: not in the build, the Swift runtime, Windows or the Windows "
                                   f"App Runtime: {', '.join(unknown)}")
        return None
    sources = []
    for dll in dlls + [bin_path / WEBVIEW2_CORE]:
        shutil.copy2(dll, package / "bin" / dll.name)
        sources.append({"file": f"bin/{dll.name}", "source": str(dll), "sha256": sha256_of(dll)})
    summary["package_dlls"] = sources
    shutil.copy2(bin_path / "ActionUI.lib", package / "lib" / "ActionUI.lib")
    for source, destination in [
            (REPO_DIR / "ActionUICAdapter" / "include" / "ActionUIC.h", "include/ActionUICAdapter/ActionUIC.h"),
            (REPO_DIR / "ActionUIAppKitApplication" / "include" / "ActionUIApp.h", "include/ActionUIAppKitApplication/ActionUIApp.h"),
            (REPO_DIR / "Add-ons" / "ActionUIHostSurface" / "Sources" / "CActionUIHostSurface" / "include" / "ActionUIHostSurface.h",
             "include/ActionUIHostSurface/ActionUIHostSurface.h"),
            (REPO_DIR / "LICENSE.txt", "LICENSE.txt"),
            (webview2_license, "LICENSE-WebView2.txt")]:
        shutil.copy2(source, package / destination)
    try:
        (package / "LICENSE-MaterialSymbols.txt").write_text(symbol_license(
            "Material Symbols", MATERIAL_COMMIT_FILE, MATERIAL_LICENSE_URL,
            "The symbol icons in ActionUIWinUIShim.dll are glyphs of the Material Symbols Rounded font by Google\n"
            "(https://github.com/google/material-design-icons, commit {commit}), converted to outlines when the\n"
            "software was built. They are used under the Apache License 2.0:"), encoding="utf-8")
        (package / "LICENSE-FluentSystemIcons.txt").write_text(symbol_license(
            "Fluent System Icons", FLUENT_COMMIT_FILE, FLUENT_LICENSE_URL,
            "Some symbol icons in ActionUIWinUIShim.dll are glyphs of the Fluent System Icons by Microsoft\n"
            "(https://github.com/microsoft/fluentui-system-icons, commit {commit}), converted to outlines when the\n"
            "software was built. They are used under the MIT License:"), encoding="utf-8")
    except (OSError, urllib.error.URLError) as error:
        summary["findings"].append(f"library package: a symbol license could not be fetched: {error}")
        return None
    names = sorted(dll.name for dll in (package / "bin").iterdir())
    summary["findings"].append(f"library package: {len(names)} DLLs in bin: {', '.join(names)}")
    if missing:
        summary["findings"].append(f"library package: from Windows or the Windows App Runtime (not copied): {', '.join(missing)}")
    # Every file's SHA-256, in sha256sum's format, so a copy of the package can be compared with this build.
    files = sorted(path for path in package.rglob("*") if path.is_file() and path.name != "SHA256SUMS.txt")
    lines = [f"{sha256_of(path)}  {path.relative_to(package).as_posix()}" for path in files]
    sums = package / "SHA256SUMS.txt"
    # Bytes, not text: text mode on Windows writes CRLF, and sha256sum -c then looks for "name\r".
    sums.write_bytes(("\n".join(lines) + "\n").encode("utf-8"))
    summary["findings"].append(f"library package: SHA256SUMS.txt lists {len(lines)} files; its own SHA-256 {sha256_of(sums)}")
    return package


def check_python(package, results, summary, msvc):
    """Builds the Python extension (ActionUIPython) against the library package with the Microsoft
    compiler, in a virtual environment, and runs its tests that need no person and nothing Windows does
    not have yet (the menu bar is left out, and the file panels' test, which waits for a person). True when every one passed;
    an interpreter of another architecture than the runner's is reported and not run."""
    work = REPO_DIR / ".build" / "ci-windows-python"
    shutil.rmtree(work, ignore_errors=True)
    source = work / "src"
    source.mkdir(parents=True)
    for item in (REPO_DIR / "ActionUIPython").iterdir():
        if item.is_file() and (item.suffix in (".py", ".c", ".toml") or item.name == "LICENSE.txt"):
            shutil.copy2(item, source / item.name)
    # test_app_lifecycle's UI description, at the path it expects beside the folder (../ActionUIObjCTestApp).
    fixture = REPO_DIR / "ActionUIObjCTestApp" / "DefaultWindowContentView.json"
    (work / fixture.parent.name).mkdir()
    shutil.copy2(fixture, work / fixture.parent.name / fixture.name)
    venv = work / "venv"
    step = run_step("python-venv", [sys.executable, "-m", "venv", venv], results, dict(os.environ))
    summary["steps"].append(step)
    python = venv / "Scripts" / "python.exe"
    if step["status"] != 0 or not python.is_file():
        return False
    # The interpreter's own architecture: platform.machine() names the machine's (an x64 Python under
    # emulation on Arm64 says ARM64).
    machine = capture([python, "-c", "import sysconfig; print(sysconfig.get_platform())"]).strip().lower()
    expected = {"x64": "win-amd64", "arm64": "win-arm64"}[windows_arch()]
    if machine != expected:
        summary["findings"].append(f"python: not run: the interpreter is {machine}, the build {expected}")
        return True
    step = run_step("python-setuptools", [python, "-m", "pip", "install", "--quiet", "setuptools"], results,
                    dict(os.environ))
    summary["steps"].append(step)
    if step["status"] != 0:
        return False
    # The Visual Studio environment's compiler, not one setuptools looks for itself.
    # CL: options cl adds to every compile, here warnings as errors.
    env = dict(msvc, DISTUTILS_USE_SDK="1", MSSdk="1", ACTIONUI_LIBRARY_DIR=str(package),
               PYTHONUTF8="1", PYTHONIOENCODING="utf-8", CL="/WX")
    step = run_step("python-build", [python, "setup.py", "build_ext", "--inplace"], results, env, cwd=source)
    summary["steps"].append(step)
    if step["status"] != 0:
        summary["errors"] = first_errors(results / step["log"])
        return False
    passed = True
    for test in PYTHON_TESTS:
        step = run_step(f"python-{test}", [python, source / f"{test}.py"], results, env, cwd=source,
                        timeout=SMOKE_TIMEOUT_SECONDS)
        summary["steps"].append(step)
        # A test that reports from the application's end (willTerminate) exits 0 without a word when that
        # never comes: its "PASSED" line is required too.
        reported = (test not in PYTHON_TESTS_REPORTING_PASSED
                    or "PASSED" in (results / step["log"]).read_text(encoding="utf-8", errors="replace"))
        succeeded = step["status"] == 0 and reported
        outcome = "passed" if succeeded else ("FAILED, no PASSED line" if step["status"] == 0 else f"FAILED, exit {step['status']}")
        summary["findings"].append(f"python {test}: {outcome}")
        passed = passed and succeeded
    # A WebView from Python run as a user runs a script, from another folder with only Windows' own folders
    # on PATH (no Swift runtime, no compiler): WebView2's Core DLL, which WinUI loads by name, is found
    # beside the shim (the extension's folder), not by the search a DLL loaded by name gets.
    elsewhere = work / "elsewhere"
    elsewhere.mkdir()
    system_root = os.environ.get("SystemRoot", r"C:\Windows")
    plain = dict(os.environ, PATH=f"{system_root}\\System32;{system_root}", PYTHONPATH=str(source),
                 PYTHONUTF8="1", PYTHONIOENCODING="utf-8")
    script = REPO_DIR / "ActionUIWinUI" / "Apps" / "PythonCheck" / "webview_elsewhere.py"
    step = run_step("python-webview-elsewhere", [python, script], results, plain, cwd=elsewhere,
                    timeout=SMOKE_TIMEOUT_SECONDS)
    summary["steps"].append(step)
    summary["findings"] += [line for line in (results / step["log"]).read_text(encoding="utf-8", errors="replace")
                            .splitlines() if line.startswith("python-elsewhere:")]
    succeeded = step["status"] == 0
    summary["findings"].append(f"python webview_elsewhere: {'passed' if succeeded else 'FAILED, exit ' + str(step['status'])}")
    # The same with the package's DLLs but WebView2's Core DLL, and a copy of that DLL planted in the
    # current folder and in a folder on PATH: no web view, a clear log line, and the planted copy never
    # loaded. The shim never searches the current folder or PATH for it.
    if not (source / WEBVIEW2_CORE).is_file():
        summary["findings"].append(f"python webview_without_core: not run: no {WEBVIEW2_CORE} beside the extension")
        return False
    without_core = work / "without-core"
    shutil.copytree(source, without_core, ignore=shutil.ignore_patterns(WEBVIEW2_CORE, "__pycache__", "build"))
    planted = work / "planted"
    planted.mkdir()
    shutil.copy2(source / WEBVIEW2_CORE, planted / WEBVIEW2_CORE)
    stripped = dict(plain, PYTHONPATH=str(without_core), PATH=f"{plain['PATH']};{planted}")
    step = run_step("python-webview-without-core", [python, script, "--without-core"], results, stripped, cwd=planted,
                    timeout=SMOKE_TIMEOUT_SECONDS)
    summary["steps"].append(step)
    summary["findings"] += [line for line in (results / step["log"]).read_text(encoding="utf-8", errors="replace")
                            .splitlines() if line.startswith("python-elsewhere:")]
    without_ok = step["status"] == 0
    summary["findings"].append(f"python webview_without_core: {'passed' if without_ok else 'FAILED, exit ' + str(step['status'])}")
    return passed and succeeded and without_ok


def fetch_node_build_files(work, version, arch):
    """Node's headers (extracted into work/headers) and work/node.lib for `version`, as node-gyp fetches
    them, each used only when it matches the release's SHASUMS256.txt. Returns None, or what went wrong."""
    base = f"https://nodejs.org/download/release/{version}"
    headers_name = f"node-{version}-headers.tar.gz"
    lib_name = f"win-{arch}/node.lib"
    try:
        with urllib.request.urlopen(f"{base}/SHASUMS256.txt", timeout=120) as response:
            listed = response.read().decode("utf-8", errors="replace")
        expected = {}
        for line in listed.splitlines():
            parts = line.split()
            if len(parts) == 2:
                expected[parts[1]] = parts[0].lower()
        for name in [headers_name, lib_name]:
            if name not in expected:
                return f"{name} is not in the release's SHASUMS256.txt"
        archive = work / "headers.tar.gz"
        library = work / "node.lib"
        for name, path in [(headers_name, archive), (lib_name, library)]:
            with urllib.request.urlopen(f"{base}/{name}", timeout=120) as response:
                path.write_bytes(response.read())
            actual = sha256_of(path)
            if actual != expected[name]:
                path.unlink()
                return f"{name} has SHA-256 {actual}, not {expected[name]} as SHASUMS256.txt lists"
        with tarfile.open(archive) as tar:
            tar.extractall(work / "headers", filter="data")
    except (OSError, urllib.error.URLError, http.client.HTTPException, tarfile.TarError) as error:
        return f"Node's headers or node.lib could not be fetched: {error}"
    return None


def check_node(package, results, summary, msvc):
    """Builds the Node.js addon (ActionUINodeJS/src/actionui_node.c and its Windows pump, actionui_uv_pump_windows.c) against the library package with clang-cl
    (the C uses GCC's cleanup attribute, which Microsoft's C compiler lacks; the Swift toolchain ships clang-cl),
    Node's headers and import library for the runner's Node version (fetched from nodejs.org), and runs its tests
    that need no person and nothing Windows does not have yet. True when every one passed; no Node, or one of
    another architecture, is reported and not run."""
    node = shutil.which("node")
    if node is None:
        summary["findings"].append("node: not run: no node on PATH")
        return True
    version = capture([node, "-p", "process.version"]).strip()
    arch = capture([node, "-p", "process.arch"]).strip()
    if arch != windows_arch():
        summary["findings"].append(f"node: not run: node {version} is {arch}, the build {windows_arch()}")
        return True
    work = REPO_DIR / ".build" / "ci-windows-node"
    shutil.rmtree(work, ignore_errors=True)
    source = work / "src"
    shutil.copytree(REPO_DIR / "ActionUINodeJS" / "src", source / "src")
    for item in (REPO_DIR / "ActionUINodeJS").iterdir():
        if item.is_file() and item.suffix in (".js", ".json"):
            shutil.copy2(item, source / item.name)
    # test_app_lifecycle's UI description, at the path it expects beside the folder (../ActionUIObjCTestApp).
    fixture = REPO_DIR / "ActionUIObjCTestApp" / "DefaultWindowContentView.json"
    (work / fixture.parent.name).mkdir()
    shutil.copy2(fixture, work / fixture.parent.name / fixture.name)
    headers = work / "headers"
    problem = fetch_node_build_files(work, version, arch)
    if problem is not None:
        summary["findings"].append(f"node: {problem}")
        return False
    summary["findings"].append(f"node: headers and node.lib for {version} match the release's SHASUMS256.txt")
    include = next(headers.glob("*/include/node"), None)
    if include is None:
        summary["findings"].append("node: no include/node in Node's headers")
        return False
    # node-gyp-build, the loader index.js uses (no build scripts run).
    npm = shutil.which("npm.cmd") or shutil.which("npm")
    step = run_step("node-npm", [npm or "npm", "install", "--omit=dev", "--ignore-scripts", "--no-audit", "--no-fund"],
                    results, dict(os.environ), cwd=source)
    summary["steps"].append(step)
    if step["status"] != 0:
        return False
    release = source / "build" / "Release"
    release.mkdir(parents=True)
    objects = work / "obj"
    objects.mkdir()
    command = [resolve_tool("clang-cl", msvc), "/nologo", "/LD", "/MD", "/O2", "/std:c11", "/utf-8", "/W3", "/WX",
               f"/I{include}", f"/I{package / 'include'}", source / "src" / "actionui_node.c",
               source / "src" / "actionui_uv_pump_windows.c", f"/Fe{release / 'actionui.node'}", f"/Fo{objects}\\", "/link", work / "node.lib",
               package / "lib" / "ActionUI.lib"]
    step = run_step("node-build", command, results, msvc, cwd=work)
    summary["steps"].append(step)
    if step["status"] != 0:
        summary["errors"] = first_errors(results / step["log"])
        return False
    # The addon's DLLs beside it: Node loads an addon with its folder searched for them.
    for dll in (package / "bin").iterdir():
        shutil.copy2(dll, release / dll.name)
    env = dict(os.environ)
    passed = True
    for test in NODE_TESTS:
        step = run_step(f"node-{test}", [node, source / f"{test}.js"], results, env, cwd=source,
                        timeout=SMOKE_TIMEOUT_SECONDS)
        summary["steps"].append(step)
        reported = (test not in NODE_TESTS_REPORTING_PASSED
                    or "PASSED" in (results / step["log"]).read_text(encoding="utf-8", errors="replace"))
        succeeded = step["status"] == 0 and reported
        outcome = "passed" if succeeded else ("FAILED, no PASSED line" if step["status"] == 0 else f"FAILED, exit {step['status']}")
        summary["findings"].append(f"node {test}: {outcome}")
        passed = passed and succeeded
    return passed


def check_rust(package, results, summary, msvc):
    """Builds the Rust crates (ActionUIRust: actionui-sys, actionui and its examples) against the library package
    with the MSVC linker, runs their tests that need no window, the HostSurface unit tests with wgpu, and the
    trust policy and HostSurface window tests, which run the application (ACTIONUI_GUI_TESTS; window_lifecycle needs the menu bar and the remote server, not
    on Windows yet). True when all passed; no cargo, or a toolchain of another architecture, is reported and not run."""
    cargo = shutil.which("cargo")
    if cargo is None:
        summary["findings"].append("rust: not run: no cargo on PATH")
        return True
    host = next((line.split(":", 1)[1].strip() for line in capture(["rustc", "-vV"]).splitlines()
                 if line.startswith("host:")), "")
    expected = {"x64": "x86_64-pc-windows-msvc", "arm64": "aarch64-pc-windows-msvc"}[windows_arch()]
    if host != expected:
        summary["findings"].append(f"rust: not run: the toolchain's host is {host or 'unknown'}, the build {expected}")
        return True
    workspace = REPO_DIR / "ActionUIRust"
    # RUSTFLAGS -D warnings: the crates' own warnings fail the build (cargo caps those of crates.io dependencies).
    env = dict(msvc, ACTIONUI_LIBRARY_DIR=str(package), RUSTFLAGS="-D warnings",
               CARGO_TARGET_DIR=str(REPO_DIR / ".build" / "ci-windows-rust" / "target"))
    passed = True
    for name, command, extra in [
            ("rust-build", [cargo, "build", "--workspace", "--examples"], {}),
            ("rust-test", [cargo, "test", "--workspace", "--all-targets"], {}),
            ("rust-trust-policy", [cargo, "test", "-p", "actionui", "--test", "trust_policy"], {"ACTIONUI_GUI_TESTS": "1"}),
            # With wgpu (and so host-surface): the unit tests, the frame sink's GPU tests among them (Direct3D 12,
            # on WARP without a GPU), the HostSurface window test, and the wgpu sketch example.
            ("rust-host-surface", [cargo, "test", "-p", "actionui", "--features", "wgpu", "--lib", "--test",
                                   "host_surface_window"], {"ACTIONUI_GUI_TESTS": "1"}),
            ("rust-wgpu-example", [cargo, "build", "-p", "actionui", "--features", "wgpu", "--example", "host_surface"], {})]:
        step = run_step(name, command, results, dict(env, **extra), cwd=workspace, timeout=STEP_TIMEOUT_SECONDS)
        summary["steps"].append(step)
        summary["findings"].append(f"{name}: {'passed' if step['status'] == 0 else 'FAILED, exit ' + str(step['status'])}")
        if step["status"] != 0:
            summary["errors"] = first_errors(results / step["log"])
            passed = False
            if name == "rust-build":
                break
    return passed


# The Node.js tests CI runs on Windows: not test_menu_bar (no menu bar on Windows yet).
NODE_TESTS = ["test_native", "test_native_api_surface", "test_insert_api", "test_action_id_lookup", "test_app_api",
              "test_configuration", "test_app_lifecycle", "test_trust_policy", "test_uv_run_integration",
              "test_worker_guard", "test_host_surface"]
# The tests that print a "PASSED" line when every check of theirs passed (the others exit 1 on a failure).
NODE_TESTS_REPORTING_PASSED = {"test_configuration", "test_app_lifecycle", "test_trust_policy", "test_uv_run_integration",
                               "test_host_surface"}


# The Python tests CI runs on Windows: not test_file_panels (it waits for a person) and test_menu_bar (not on
# Windows yet); test_app_api skips its remote server part there.
PYTHON_TESTS = ["test_native", "test_native_api_surface", "test_insert_api", "test_scalar_context",
                "test_modal_api", "test_app_api", "test_configuration", "test_app_lifecycle", "test_trust_policy",
                "test_worker_thread_calls", "test_host_surface"]
# The tests that print a "PASSED" line when every check of theirs passed.
PYTHON_TESTS_REPORTING_PASSED = {"test_configuration", "test_app_lifecycle", "test_trust_policy", "test_worker_thread_calls",
                                 "test_host_surface"}


def check_c_adapter(bin_path, results, summary, msvc, env):
    """Builds ActionUIWinUI/Apps/CAdapterCheck/main.c with MSVC against ActionUI.dll's import
    library, as a C host does, and runs it beside the DLL. True when every check passed."""
    library = bin_path / "ActionUI.lib"
    if not library.is_file() or not (bin_path / "ActionUI.dll").is_file():
        summary["findings"].append(f"no ActionUI.dll and .lib in {bin_path}")
        return False
    checker = bin_path / "ActionUICAdapterCheck.exe"
    source = REPO_DIR / "ActionUIWinUI" / "Apps" / "CAdapterCheck" / "main.c"
    command = [resolve_tool("cl", msvc), "/nologo", "/std:c11", "/W3", "/WX", "/MD", "/utf-8",
               f"/I{REPO_DIR / 'ActionUICAdapter' / 'include'}", source, f"/Fe{checker}", f"/Fo{bin_path}\\",
               "/link", library]
    step = run_step("c-adapter-build", command, results, msvc, cwd=bin_path)
    summary["steps"].append(step)
    if step["status"] != 0:
        summary["errors"] = first_errors(results / step["log"])
        return False
    step = run_step("c-adapter-check", [checker], results, env, cwd=bin_path, timeout=SMOKE_TIMEOUT_SECONDS)
    summary["steps"].append(step)
    summary["findings"] += [line for line in (results / step["log"]).read_text(encoding="utf-8", errors="replace")
                            .splitlines() if line.startswith("c-adapter:")]
    return step["status"] == 0


def check_c_app(bin_path, results, summary, msvc, env):
    """Builds ActionUIWinUI/Apps/CAppCheck/main.c against ActionUI.dll's import library and runs
    it: ActionUI's application from C (ActionUIApp.h): windows from JSON, a file and a server presented
    and closed (by the host, then as the user, with shouldTerminate), the handlers and values through the
    C adapter checked, alerts answered through UI Automation. True when every check passed."""
    library = bin_path / "ActionUI.lib"
    if not library.is_file():
        summary["findings"].append(f"no ActionUI.lib in {bin_path}")
        return False
    folder = REPO_DIR / "ActionUIWinUI" / "Apps" / "CAppCheck"
    checker = bin_path / "ActionUIAppCheck.exe"
    command = [resolve_tool("cl", msvc), "/nologo", "/std:c11", "/W3", "/WX", "/MD", "/utf-8",
               f"/I{REPO_DIR / 'ActionUICAdapter' / 'include'}", f"/I{REPO_DIR / 'ActionUIAppKitApplication' / 'include'}",
               folder / "main.c", f"/Fe{checker}", f"/Fo{bin_path}\\", "/link", library, "user32.lib", "ole32.lib",
               "oleaut32.lib"]
    step = run_step("c-app-build", command, results, msvc, cwd=bin_path)
    summary["steps"].append(step)
    if step["status"] != 0:
        summary["errors"] = first_errors(results / step["log"])
        return False
    # The manifest the other programs have (supported OS, per-monitor DPI).
    shutil.copy2(REPO_DIR / "ActionUIWinUI" / "Apps" / "Smoke" / "ActionUIWinUISmoke.exe.manifest",
                 bin_path / "ActionUIAppCheck.exe.manifest")
    remote = "https://raw.githubusercontent.com/abra-code/ActionUI/WinUI-CI/ActionUIWinUI/Apps/Preview/TestFiles/Loadable/Remote.json"
    step = run_step("c-app-check", [checker, folder / "Window.json", remote], results, env, cwd=bin_path,
                    timeout=SMOKE_TIMEOUT_SECONDS)
    summary["steps"].append(step)
    summary["findings"] += [line for line in (results / step["log"]).read_text(encoding="utf-8", errors="replace")
                            .splitlines() if line.startswith("c-app:")]
    return step["status"] == 0


def check_host_app(bin_path, results, summary, msvc, env, host_build):
    """Builds ActionUIWinUI/Apps/HostAppCheck/main.cpp, a host that runs its own WinUI application, with
    the headers the shim builds with, against ActionUI.dll's import library, and runs it: ActionUI JSON
    in the host's window, ActionUI's own application refused, a worker's call run under the host's loop.
    True when every check passed."""
    library = bin_path / "ActionUI.lib"
    if not library.is_file():
        summary["findings"].append(f"no ActionUI.lib in {bin_path}")
        return False
    folder = REPO_DIR / "ActionUIWinUI" / "Apps" / "HostAppCheck"
    checker = bin_path / "ActionUIHostAppCheck.exe"
    manifest = REPO_DIR / "ActionUIWinUI" / "Apps" / "Smoke" / "ActionUIWinUISmoke.exe.manifest"
    command = [resolve_tool("cl", msvc), "/nologo", "/std:c++20", "/EHsc", "/permissive-", "/MD", "/utf-8", "/W3", "/WX",
               "/bigobj", "/DNOMINMAX"] + host_build["includes"] + [
               f"/I{REPO_DIR / 'ActionUICAdapter' / 'include'}", f"/I{REPO_DIR / 'ActionUIAppKitApplication' / 'include'}",
               folder / "main.cpp", f"/Fe{checker}", f"/Fo{bin_path}\\",
               "/link", library, "/MANIFEST:EMBED", f"/MANIFESTINPUT:{manifest}"] + host_build["libraries"]
    step = run_step("host-app-build", command, results, msvc, cwd=bin_path)
    summary["steps"].append(step)
    if step["status"] != 0:
        summary["errors"] = first_errors(results / step["log"])
        return False
    step = run_step("host-app-check", [checker], results, env, cwd=bin_path, timeout=SMOKE_TIMEOUT_SECONDS)
    summary["steps"].append(step)
    summary["findings"] += [line for line in (results / step["log"]).read_text(encoding="utf-8", errors="replace")
                            .splitlines() if line.startswith("host-app:")]
    return step["status"] == 0


# The headers that declare ActionUI.dll's C functions.
LIBRARY_HEADERS = [REPO_DIR / "ActionUICAdapter" / "include" / "ActionUIC.h",
                   REPO_DIR / "ActionUIAppKitApplication" / "include" / "ActionUIApp.h",
                   REPO_DIR / "Add-ons" / "ActionUIHostSurface" / "Sources" / "CActionUIHostSurface" / "include" /
                   "ActionUIHostSurface.h"]


# ActionUI.dll's export list (ActionUIWinUI/Library/Package.swift links with it).
LIBRARY_DEFINITION = REPO_DIR / "ActionUIWinUI" / "Library" / "ActionUI.def"


def check_library_exports(summary, msvc):
    """Whether LIBRARY_DEFINITION names exactly the functions LIBRARY_HEADERS declare for Windows, as MSVC's
    preprocessor reads them (they declare some functions only for Apple or Linux; every one is named
    actionUI..., or ActionUI<AddOn>_register). A function declared and not listed would be missing from ActionUI.dll; one listed and not
    declared would be exported for no header. Findings name the differences."""
    declared = []
    for header in LIBRARY_HEADERS:
        try:
            completed = subprocess.run([resolve_tool("cl", msvc), "/nologo", "/EP", "/TC", str(header)], env=msvc,
                                       capture_output=True, text=True, timeout=120)
        except (FileNotFoundError, subprocess.TimeoutExpired) as error:
            summary["findings"].append(f"library exports: could not preprocess {header.name}: {error}")
            return False
        if completed.returncode != 0:
            summary["findings"].append(f"library exports: could not preprocess {header.name}: "
                                       f"{completed.stdout.strip()[-500:]} {completed.stderr.strip()[-500:]}")
            return False
        for name in re.findall(r"\b(actionUI[A-Za-z0-9_]*|ActionUI[A-Za-z0-9]*_register)\s*\(", completed.stdout):
            if name not in declared:
                declared.append(name)
    listed = []
    in_exports = False
    for line in LIBRARY_DEFINITION.read_text(encoding="utf-8").splitlines():
        words = line.split(";", 1)[0].split()
        if not words:
            continue
        if words[0] == "EXPORTS":
            in_exports = True
        elif in_exports:
            listed.append(words[0])
    missing = [name for name in declared if name not in listed]
    extra = [name for name in listed if name not in declared]
    if not declared or missing or extra:
        summary["findings"].append(f"library exports: {LIBRARY_DEFINITION.name} does not match the C headers: "
                                   f"declared, not listed: {', '.join(missing) or 'none'}; "
                                   f"listed, not declared: {', '.join(extra) or 'none'}")
        return False
    summary["findings"].append(f"library exports: {LIBRARY_DEFINITION.name} lists the {len(declared)} C functions of "
                               f"{', '.join(header.name for header in LIBRARY_HEADERS)}")
    return True


def build_library(shim_out, bin_path, results, summary, msvc, env):
    """Builds ActionUI.dll and its import library from their own package (ActionUIWinUI/Library: ActionUI,
    the C adapter, the application functions and the add-ons), exporting the functions LIBRARY_DEFINITION
    names once check_library_exports agrees, and the preview tool with the same add-ons
    (ActionUIWinUIAddOnPreview); copies the three into bin_path, beside the programs that load the DLL and
    the shim. True when built."""
    if not check_library_exports(summary, msvc):
        return False
    scratch = ["--package-path", str(REPO_DIR / "ActionUIWinUI" / "Library"),
               "--scratch-path", str(REPO_DIR / ".build" / "ci-windows-library"), "--manifest-cache", "none"]
    # SwiftPM does not count the module-definition file as a link input: without this, a rebuild after only
    # ActionUI.def changed would keep the DLL with the old exports.
    shown = capture(["swift", "build"] + scratch + ["--show-bin-path"]).splitlines()
    if shown:
        Path(shown[-1].strip(), "ActionUI.dll").unlink(missing_ok=True)
    if not edit_overlay_dependencies(scratch, results, summary, env):
        return False
    step = run_step("library-build", ["swift", "build"] + scratch + ["-Xswiftc", f"-L{shim_out}"], results, env)
    summary["steps"].append(step)
    if step["status"] != 0:
        summary["errors"] = first_errors(results / step["log"])
        return False
    if fails_on_warnings(step, results, summary):
        return False
    shown = capture(["swift", "build"] + scratch + ["--show-bin-path"]).splitlines()
    library_bin = Path(shown[-1].strip()) if shown else Path()
    for name in ["ActionUI.dll", "ActionUI.lib", "ActionUIWinUIAddOnPreview.exe"]:
        if not (library_bin / name).is_file():
            summary["findings"].append(f"no {name} in {library_bin}")
            return False
        shutil.copy2(library_bin / name, bin_path / name)
    return True


def render_previews(program, folder, options_by_name, real_input_by_name, prefix, bin_path, results, summary, env):
    """Renders each test file in `folder` with the preview tool `program` into results/<prefix>-<name>.png, with
    the options `options_by_name` gives its name, and on x64 the real input checks `real_input_by_name` gives it
    (removed on Arm64). True when every run passed."""
    passed = True
    for ui_file in sorted(folder.glob("*.json")):
        png = results / f"{prefix}-{ui_file.stem}.png"
        options = [option.replace("{test_files_url}", ui_file.parent.as_uri())
                   .replace("{test_files_folder_json}", json.dumps(str(ui_file.parent))[1:-1])
                   .replace("{program_folder_upper}", str(bin_path).upper()).replace("{program_folder}", str(bin_path))
                   for option in options_by_name.get(ui_file.stem, [])]
        if windows_arch() == "arm64":
            options = without_real_input(options)
        else:
            options += real_input_by_name.get(ui_file.stem, [])
        step = run_step(f"{prefix}-{ui_file.stem}", [program, ui_file, png] + options, results, env, cwd=bin_path,
                        timeout=SMOKE_TIMEOUT_SECONDS)
        summary["steps"].append(step)
        summary["findings"] += [line for line in (results / step["log"]).read_text(encoding="utf-8", errors="replace")
                                .splitlines() if line.startswith("preview:")]
        passed = passed and step["status"] == 0 and png.is_file() and png.stat().st_size > 0
    return passed


def check_swift_smoke(shim_out, bootstrap, results, summary, msvc, host_build):
    """Builds the Swift package for Windows (ActionUIWinUISmoke, ActionUIWinUIPreview) and ActionUI.dll's
    package (build_library) with the shim's import library on the linker path, places the shim DLL, the
    bootstrapper DLL and the programs' manifests beside them, runs the smoke test and the C adapter's check, then
    renders each test file in ActionUIWinUI/Apps/Preview/TestFiles with the preview and each in
    ActionUIWinUI/Apps/Preview/TestFiles/AddOns with the add-on preview. True when all of them passed."""
    # --manifest-cache none: the package's exclude lists come from the folder listing (Package.swift).
    scratch = ["--scratch-path", str(REPO_DIR / ".build" / "ci-windows-winui"), "--manifest-cache", "none"]
    env = dict(os.environ)
    env.pop("ACTIONUI_CORE_ONLY", None)
    step = run_step("swift-build", ["swift", "build"] + scratch + ["-Xswiftc", f"-L{shim_out}"], results, env)
    summary["steps"].append(step)
    if step["status"] != 0:
        summary["errors"] = first_errors(results / step["log"])
        return False
    if fails_on_warnings(step, results, summary):
        return False
    shown = capture(["swift", "build"] + scratch + ["--show-bin-path"]).splitlines()
    bin_path = Path(shown[-1].strip()) if shown else Path()
    program = bin_path / "ActionUIWinUISmoke.exe"
    preview = bin_path / "ActionUIWinUIPreview.exe"
    for expected in [program, preview]:
        if not expected.is_file():
            summary["findings"].append(f"no {expected.name} in {bin_path}")
            return False
    library_built = build_library(shim_out, bin_path, results, summary, msvc, env)
    # The checked copies in the shim's folder (check_shim), not the NuGet folders.
    for source in [shim_out / "ActionUIWinUIShim.dll", shim_out / bootstrap.name, shim_out / WEBVIEW2_CORE]:
        shutil.copy2(source, bin_path / source.name)
    # ActionUI JSON shipped with the program (TrustedResources.json loads it from there).
    for source in sorted((REPO_DIR / "ActionUIWinUI" / "Apps" / "Preview" / "Bundled").glob("*.json")):
        shutil.copy2(source, bin_path / source.name)
    # One manifest for the three programs (supported OS, per-monitor DPI).
    manifest = REPO_DIR / "ActionUIWinUI" / "Apps" / "Smoke" / "ActionUIWinUISmoke.exe.manifest"
    for name in ["ActionUIWinUISmoke.exe.manifest", "ActionUIWinUIPreview.exe.manifest",
                 "ActionUIWinUIAddOnPreview.exe.manifest"]:
        shutil.copy2(manifest, bin_path / name)
    png = results / "swift-smoke.png"
    step = run_step("swift-smoke", [program, png], results, env, cwd=bin_path, timeout=SMOKE_TIMEOUT_SECONDS)
    summary["steps"].append(step)
    summary["findings"] += [line for line in (results / step["log"]).read_text(encoding="utf-8", errors="replace")
                            .splitlines() if line.startswith("smoke:")]
    passed = step["status"] == 0 and png.is_file() and png.stat().st_size > 0 and library_built
    # The programs that load ActionUI.dll, and the library package, need it built.
    if library_built:
        passed = check_c_adapter(bin_path, results, summary, msvc, env) and passed
        passed = check_c_app(bin_path, results, summary, msvc, env) and passed
        passed = check_host_app(bin_path, results, summary, msvc, env, host_build) and passed
    passed = check_viewer(shim_out, bin_path, results, summary, env) and passed
    if library_built:
        package = make_library_package(bin_path, results, summary, msvc, host_build["webview2_license"])
        passed = package is not None and passed
        if package is not None:
            passed = check_python(package, results, summary, msvc) and passed
            passed = check_node(package, results, summary, msvc) and passed
            passed = check_rust(package, results, summary, msvc) and passed
    passed = render_previews(preview, REPO_DIR / "ActionUIWinUI" / "Apps" / "Preview" / "TestFiles", PREVIEW_OPTIONS,
                             REAL_INPUT_EXPECTATIONS, "preview", bin_path, results, summary, env) and passed
    if library_built:
        passed = render_previews(bin_path / "ActionUIWinUIAddOnPreview.exe",
                                 REPO_DIR / "ActionUIWinUI" / "Apps" / "Preview" / "TestFiles" / "AddOns", ADD_ON_PREVIEW_OPTIONS,
                                 {}, "add-on-preview", bin_path, results, summary, env) and passed
        passed = check_diff_files(bin_path / "ActionUIWinUIAddOnPreview.exe", results, summary, env) and passed
    passed = check_share_reads(preview, bin_path / "ActionUIWinUIAddOnPreview.exe" if library_built else None,
                               bin_path, results, summary, env) and passed
    passed = check_ambient_identity(preview, bin_path, results, summary, env) and passed
    return passed


def check_diff_files(add_on_preview, results, summary, env):
    """Whether the Diff add-on's element reads files on Windows, in the app's own JSON (trusted): a full path with
    backslashes, one with forward slashes, a path relative to the program's current folder and "~\\..." (the
    user's profile folder) each show the file (no failure line); a file it cannot read shows a note, and the
    message names the full path Windows opens: not UTF-8, a folder, NUL (a device, \\\\.\\NUL), over 4 MB,
    missing. True when both runs passed."""
    findings = summary["findings"]
    folder = Path(os.path.abspath(results / "diff-files"))
    folder.mkdir(parents=True, exist_ok=True)
    # Windows line endings (CRLF), as Windows editors write them; one copy with LF only.
    (folder / "old.txt").write_bytes(b"first\r\nsecond\r\nthird\r\n")
    (folder / "new.txt").write_bytes(b"first\r\nsecond, caf\xc3\xa9\r\nthird\r\n")
    (folder / "old-lf.txt").write_bytes(b"first\nsecond\nthird\n")
    (folder / "latin1.txt").write_bytes(b"caf\xe9\n")
    (folder / "folder").mkdir(exist_ok=True)
    big = folder / "big.txt"
    profile = os.environ.get("USERPROFILE", "")
    home_file = Path(profile) / "actionui-diff-check.txt" if profile else None
    readable = [{"type": "Diff", "id": 2, "properties": {"oldFile": str(folder / "old.txt"),
                                                          "newFile": str(folder / "new.txt").replace("\\", "/")}},
                {"type": "Diff", "id": 3, "properties": {"oldFile": "old.txt", "newFile": "new.txt"}},
                {"type": "Diff", "id": 5, "properties": {"oldFile": "old.txt", "newFile": "old-lf.txt"}}]
    if home_file is not None:
        readable.append({"type": "Diff", "id": 4, "properties": {"oldFile": "~\\actionui-diff-check.txt",
                                                                  "newText": "From the profile, changed\n"}})
    unreadable = [{"type": "Diff", "id": 2, "properties": {"oldFile": "latin1.txt", "newFile": "folder"}},
                  {"type": "Diff", "id": 3, "properties": {"oldFile": "NUL", "newFile": "big.txt"}},
                  {"type": "Diff", "id": 4, "properties": {"oldFile": "missing.txt", "newText": ""}}]
    expected = [f"Diff old: '{folder / 'latin1.txt'}' is not readable UTF-8",
                f"Diff new: cannot read '{folder / 'folder'}' (missing",
                "Diff old: cannot read '\\\\.\\NUL' (missing",
                f"Diff new: cannot read '{big}' (missing",
                f"Diff old: cannot read '{folder / 'missing.txt'}' (missing"]
    steps = []
    try:
        big.write_bytes(b"a" * (4 * 1024 * 1024 + 1))
        if home_file is not None:
            home_file.write_text("From the profile\n", encoding="utf-8")
        for name, children, options in [
                # Each CRLF line is a row: 2 and 3 are a line changed among three (4 rows, 64 points, as the
                # add-on's example measures), and 5, CRLF against LF, has no changes (its note, 24 points).
                ("diff-files", readable, ["--expect-height", "2", "64", "--expect-height", "3", "64",
                                          "--expect-height", "5", "24",
                                          "--forbid-log", "Diff old:", "--forbid-log", "Diff new:",
                                          "--forbid-log", "Diff: ", "--forbid-log", "Not reading",
                                          "--forbid-log", "Diff is not available on Windows yet",
                                          "--forbid-log", "creating the element Diff"]),
                ("diff-files-unreadable", unreadable, [option for text in expected for option in ["--expect-log", text]])]:
            ui_file = folder / f"{name}.json"
            ui_file.write_text(json.dumps({"type": "VStack", "id": 1, "properties": {"spacing": 8, "padding": 12},
                                            "children": children}), encoding="utf-8")
            steps.append(run_step(name, [add_on_preview, ui_file, results / f"{name}.png", "520", "360"] + options,
                                  results, env, cwd=folder, timeout=SMOKE_TIMEOUT_SECONDS))
    finally:
        big.unlink(missing_ok=True)
        if home_file is not None:
            home_file.unlink(missing_ok=True)
    summary["steps"] += steps
    failed = [step["step"] for step in steps if step["status"] != 0]
    findings.append(f"Diff files: FAILED ({', '.join(failed)})" if failed
                    else "Diff files: passed: read by each path form; each unreadable file named by its full path")
    return not failed


CANARY_SHARE = "actionui-canary"


def powershell(script):
    """Runs a short PowerShell script; returns its exit status and its stripped output."""
    try:
        completed = subprocess.run(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", script],
                                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=120)
    except (FileNotFoundError, subprocess.TimeoutExpired) as error:
        return None, f"<{error}>"
    return completed.returncode, completed.stdout.strip()


def canary_connections():
    """How many SMB connections this machine holds to the canary share, or None if it cannot be told."""
    status, output = powershell(f"@(Get-SmbConnection | Where-Object ShareName -eq '{CANARY_SHARE}').Count")
    if status != 0 or not output.isdigit():
        return None
    return int(output)


def check_share_reads(preview, add_on_preview, bin_path, results, summary, env):
    """Whether less-trusted content's LoadableView, or the Diff add-on's element, reaches a share before
    refusing it: a share on this machine (\\\\localhost\\actionui-canary) is named by JSON from a server
    (LessTrustedShares, and LessTrustedDiffShares with the add-on preview `add_on_preview` when ActionUI.dll's
    package was built), then by the app's own JSON (the control, which may load it). The first must open no
    SMB connection to it, the second one. Not run where the SMB server cannot share a folder; inconclusive
    when the control opens no connection either. Then, judged by their messages (a program whose current
    folder is on the share holds a connection to it): the Diff in JSON from a server refuses a relative path
    and the current drive's root with the current folder on the share, and the Diff in the app's own JSON
    reads a file on the share."""
    findings = summary["findings"]
    folder = results / "share-canary"
    folder.mkdir(parents=True, exist_ok=True)
    (folder / "view7.json").write_text(json.dumps({"type": "Text", "id": 1, "properties": {"text": "From the share"}}),
                                       encoding="utf-8")
    (folder / "old.txt").write_text("From the share\n", encoding="utf-8")
    share = f"\\\\localhost\\{CANARY_SHARE}"
    diff_steps = []
    status, output = powershell(f"New-SmbShare -Name '{CANARY_SHARE}' -Path '{folder}' -ReadAccess 'Everyone' "
                                "-ErrorAction Stop | Out-Null")
    if status != 0:
        findings.append(f"share check: not run: the folder could not be shared: {output.splitlines()[-1] if output else status}")
        return True
    try:
        before = canary_connections()
        ui_file = REPO_DIR / "ActionUIWinUI" / "Apps" / "Preview" / "TestFiles" / "LessTrustedShares.json"
        step = run_step("share-canary-less-trusted", [preview, ui_file, results / "share-canary-less-trusted.png"]
                        + PREVIEW_OPTIONS["LessTrustedShares"], results, env, cwd=bin_path, timeout=SMOKE_TIMEOUT_SECONDS)
        summary["steps"].append(step)
        diff_ui_file = REPO_DIR / "ActionUIWinUI" / "Apps" / "Preview" / "TestFiles" / "AddOns" / "LessTrustedDiffShares.json"
        if add_on_preview is not None:
            diff_steps.append(run_step("share-canary-less-trusted-diff",
                                       [add_on_preview, diff_ui_file, results / "share-canary-less-trusted-diff.png"]
                                       + ADD_ON_PREVIEW_OPTIONS["LessTrustedDiffShares"], results, env, cwd=bin_path,
                                       timeout=SMOKE_TIMEOUT_SECONDS))
        less_trusted = canary_connections()
        control = results / "share-canary-control.json"
        control.write_text(json.dumps({"type": "LoadableView", "id": 2, "properties": {
            "filePath": f"\\\\localhost\\{CANARY_SHARE}\\view7.json"}}), encoding="utf-8")
        control_step = run_step("share-canary-control", [preview, control, results / "share-canary-control.png", "300", "80",
                                                         "--delay", "3000"], results, env, cwd=bin_path,
                                timeout=SMOKE_TIMEOUT_SECONDS)
        summary["steps"].append(control_step)
        trusted = canary_connections()
        if add_on_preview is not None:
            # The same JSON from a server, the program's current folder on the share (the preview changes into the
            # folder of the UI description it is given, so that is read from the share): "old.txt" and "\old.txt"
            # are read from there, so the add-on must judge the full path Windows makes of each, a path on the share.
            shutil.copy2(diff_ui_file, folder / diff_ui_file.name)
            relative = [option for element in [904, 905]
                        for option in ["--expect-log", f"Not reading {share}\\old.txt for element {element}: "
                                                       "less-trusted content reads no network"]]
            diff_steps.append(run_step("share-canary-less-trusted-diff-current-folder",
                                       [add_on_preview, f"{share}\\{diff_ui_file.name}",
                                        results / "share-canary-less-trusted-diff-current-folder.png", "520", "360",
                                        "--delay", "4000"] + relative, results, env, cwd=bin_path,
                                       timeout=SMOKE_TIMEOUT_SECONDS))
            # The app's own JSON reads the same file on the share (the refusals above are not a path the add-on
            # cannot read at all): no failure line, and the Diff shows the file's line.
            trusted_diff = results / "share-canary-trusted-diff.json"
            trusted_diff.write_text(json.dumps({"type": "Diff", "id": 2, "properties": {
                "oldFile": f"{share}\\old.txt", "newText": "From the app\n"}}), encoding="utf-8")
            diff_steps.append(run_step("share-canary-trusted-diff",
                                       [add_on_preview, trusted_diff, results / "share-canary-trusted-diff.png", "400",
                                        "100", "--forbid-log", "Diff old:", "--forbid-log", "Diff new:",
                                        "--forbid-log", "Not reading", "--forbid-log",
                                        "Diff is not available on Windows yet", "--forbid-log",
                                        "creating the element Diff"], results, env, cwd=bin_path,
                                       timeout=SMOKE_TIMEOUT_SECONDS))
    finally:
        powershell(f"Remove-SmbShare -Name '{CANARY_SHARE}' -Force")
    summary["steps"] += diff_steps
    diff_passed = all(diff_step["status"] == 0 for diff_step in diff_steps)
    if add_on_preview is None:
        findings.append("share check: the Diff's checks not run: ActionUI.dll's package was not built")
    elif not diff_passed:
        failed = ", ".join(diff_step["step"] for diff_step in diff_steps if diff_step["status"] != 0)
        findings.append(f"share check: FAILED: the Diff's checks ({failed})")
    counts = f"connections before {before}, after JSON from a server {less_trusted}, after the app's own JSON {trusted}"
    if before is None or less_trusted is None or trusted is None:
        findings.append(f"share check: inconclusive: SMB connections could not be listed ({counts})")
        return step["status"] == 0 and diff_passed
    if less_trusted > before:
        findings.append(f"share check: FAILED: JSON from a server reached the share ({counts})")
        return False
    if trusted <= less_trusted:
        findings.append(f"share check: inconclusive: the app's own JSON opened no connection either ({counts})")
        return step["status"] == 0 and diff_passed
    findings.append(f"share check: passed: only the app's own JSON reached the share ({counts})")
    return step["status"] == 0 and control_step["status"] == 0 and diff_passed


# The less-trusted LoadableViews' downloads, each of which must come from the private fetch and carry no sign-in or
# cookie (the time and size limits are checked on the private fetch, not only on the error text).
PRIVATE_FETCH_PATHS = ["/auth/loadable.json", "/cookie/loadable.json", "/slow.json", "/endless.json",
                       "/auth/image.png", "/cookie/image.png", "/big.png", "/endless.png", "/cookie/drawing.svg",
                       "/stalled-private.json", "/stalled.png"]


def check_ambient_identity(preview, bin_path, results, summary, env):
    """Records what the app's network stacks send to a server that less-trusted content names: a local server (Scripts/ci-http-responder.py, on "localhost", which Windows may count as
    the intranet, where it signs in on its own) sets a cookie through the app's own LoadableView, then
    serves JSON (less trusted) whose LoadableView, AsyncImage, VideoPlayer and WebView each name a page
    that asks for Windows sign-in (/auth/) and one that does not (/cookie/). Each request's sign-in scheme
    and cookie names go into the findings, with the preview's warnings about those elements (a load refused
    sends no request).
    Fails when the less-trusted LoadableViews' and AsyncImages' downloads (the private fetch, user agent
    "ActionUI") carried a sign-in or a cookie or did not arrive, or when their limits did not hold
    (/slow.json given up after 3 seconds, the configuration's maximumDownloadTime, /endless.json refused
    past 100000 bytes, /endless.png past 32 MB, /big.png refused for its 9000 x 9000 pixels, an SVG image
    refused), or when a good image did not load; or when, with no time limit (maximumDownloadTime null), a
    download whose server stops answering is not given up after 30 seconds (the shim's limit on one step:
    the app's own LoadableViews before and after the headers, Windows' HTTP client; less-trusted content's
    LoadableView and AsyncImage, the private fetch); or when the less-trusted WebView sent the cookie the app's own WebView got (it keeps a private
    store), or the app's own WebView did not keep that cookie first. The video player, and the WebView's
    answers to sign-in requests, are recorded only."""
    findings = summary["findings"]
    folder = results / "ambient-identity"
    folder.mkdir(parents=True, exist_ok=True)
    port_file, record, stop_file = folder / "port", folder / "requests.jsonl", folder / "stop"
    for path in (port_file, record, stop_file):
        path.unlink(missing_ok=True)
    video = REPO_DIR / "ActionUIWinUI" / "Apps" / "Preview" / "TestFiles" / "Media" / "one-second.mp4"
    log = open(folder / "responder.log", "w", encoding="utf-8")
    try:
        responder = subprocess.Popen([sys.executable, "-I", str(REPO_DIR / "Scripts" / "ci-http-responder.py"),
                                      "--port-file", str(port_file), "--record", str(record),
                                      "--stop-file", str(stop_file), "--video", str(video),
                                      "--big", str(video.parent.parent / "Images" / "declares-81-megapixels.png")],
                                     stdout=log, stderr=subprocess.STDOUT)
    except OSError as error:
        log.close()
        findings.append(f"ambient identity: FAILED: the responder could not start: {error}")
        return False
    try:
        started = time.monotonic()
        while not port_file.is_file() and responder.poll() is None and time.monotonic() - started < 20:
            time.sleep(0.2)
        port = port_file.read_text(encoding="utf-8").strip() if port_file.is_file() else ""
        if not port.isdigit():
            findings.append("ambient identity: FAILED: the responder did not start (see ambient-identity/responder.log)")
            return False
        ui_file = REPO_DIR / "ActionUIWinUI" / "Apps" / "Preview" / "TestFiles" / "Probes" / "AmbientIdentity.json"
        step = run_step("ambient-identity", [preview, ui_file, results / "ambient-identity.png", "420", "400",
                                             "--configuration", '{"limits": {"maximumDownloadTime": 3}}',
                                             "--fetch-limit", "100000",
                                             "--expect-log", "/slow.json: loading it took longer than 3 seconds",
                                             "--expect-log", "/endless.json: the response is larger than 100000 bytes",
                                             "--expect-log", "AsyncImage 202 not shown:",
                                             "--expect-log", "AsyncImage 206 loaded",
                                             "--expect-log", "/big.png is 9000 x 9000 pixels",
                                             "--expect-log", "/endless.png: the response is larger than 32 MB",
                                             "--expect-log", "an SVG image from less-trusted content is not shown",
                                             "--set-value", "5", f"http://localhost:{port}/set-web-cookie.html",
                                             "--delay", "5000",
                                             "--set-value", "2", f"http://localhost:{port}/set-cookie.json",
                                             "--delay", "3000",
                                             "--set-value", "3", f"http://localhost:{port}/outer.json",
                                             "--delay", "15000"],
                        results, env, cwd=bin_path, timeout=SMOKE_TIMEOUT_SECONDS)
        summary["steps"].append(step)
        findings += [f"ambient identity: preview {line.strip()}" for line in
                     (results / step["log"]).read_text(encoding="utf-8", errors="replace").splitlines()
                     if ("[warning]" in line or "[error]" in line) and re.search(r"\b(20[1-9]|21[0-3])\b", line)]
        # No time limit: every stalled download still ends, after the 30 seconds one step may wait.
        stalled = "the server sent nothing for 30 seconds"
        stall_step = run_step("stalled-downloads",
                              [preview, ui_file.parent / "StalledDownloads.json", results / "stalled-downloads.png",
                               "420", "200", "--configuration", '{"limits": {"maximumDownloadTime": null}}',
                               "--expect-log", f"/silent.json: {stalled}",
                               "--expect-log", f"/stalled.json: {stalled}",
                               "--expect-log", f"/stalled-private.json: {stalled}",
                               "--expect-log", f"/stalled.png: {stalled}",
                               "--set-value", "2", f"http://localhost:{port}/silent.json",
                               "--set-value", "3", f"http://localhost:{port}/stalled.json",
                               "--set-value", "5", f"http://localhost:{port}/stalled-outer.json",
                               "--delay", "40000"],
                              results, env, cwd=bin_path, timeout=SMOKE_TIMEOUT_SECONDS)
        summary["steps"].append(stall_step)
        findings += [f"ambient identity: stalled {line.strip()}" for line in
                     (results / stall_step["log"]).read_text(encoding="utf-8", errors="replace").splitlines()
                     if stalled in line]
    finally:
        try:
            stop_file.write_text("stop", encoding="utf-8")
            responder.wait(timeout=10)
        except (OSError, subprocess.TimeoutExpired):
            responder.kill()
            responder.wait()
        log.close()
    lines = record.read_text(encoding="utf-8").splitlines() if record.is_file() else []
    entries = []
    for line in lines:
        try:
            entries.append(json.loads(line))
        except ValueError:
            continue
    for entry in entries:
        cookie = ",".join(entry.get("cookie") or []) or "none"
        findings.append(f"ambient identity: {entry.get('method')} {entry.get('path')} over {entry.get('over')}: "
                        f"sign-in {entry.get('authorization') or 'none'}, cookies {cookie}, agent {entry.get('agent') or 'none'}")
    passed = step["status"] == 0 and stall_step["status"] == 0
    for path in PRIVATE_FETCH_PATHS:
        requests = [entry for entry in entries if entry.get("path") == path]
        carried = [entry for entry in requests if entry.get("authorization") or entry.get("cookie")]
        other = [entry for entry in requests if entry.get("agent") != "ActionUI"]
        if not requests or carried or other:
            why = ("no request arrived" if not requests else "a sign-in or a cookie was sent" if carried
                   else "a request came from another client than the private fetch")
            findings.append(f"ambient identity: FAILED: {path}: {why}")
            passed = False
    # Whether the private stores' profiles leave folders in the preview's WebView2 data folder (recorded).
    profiles = Path(os.environ.get("LOCALAPPDATA", "")) / "ActionUIWinUIPreview" / "WebView2" / "EBWebView"
    private = sorted(child.name for child in profiles.glob("ActionUIPrivate*")) if profiles.is_dir() else []
    findings.append(f"ambient identity: private profile folders in {profiles}: {len(private)}"
                    + (f" ({', '.join(private[:5])}{', ...' if len(private) > 5 else ''})" if private else ""))
    # A less-trusted WebView keeps a private store: the cookie the app's own WebView got is not sent. The app's
    # own page loads an image that carries the cookie once it is kept (else the check below proves nothing),
    # and that comes before the less-trusted WebView's request.
    kept = [index for index, entry in enumerate(entries) if entry.get("path") == "/cookie/web-check.png"
            and "actionui_web_probe" in (entry.get("cookie") or [])]
    page_requests = [index for index, entry in enumerate(entries) if entry.get("path") == "/cookie/page.html"]
    shared = [index for index in page_requests if "actionui_web_probe" in (entries[index].get("cookie") or [])]
    if not kept or not page_requests or shared or kept[0] > page_requests[0]:
        why = ("the app's own WebView did not keep its cookie (no /cookie/web-check.png carrying it)" if not kept
               else "the less-trusted WebView made no request" if not page_requests
               else "the less-trusted WebView sent the cookie the app's own WebView got" if shared
               else "the less-trusted WebView's request came before the app's own WebView kept its cookie")
        findings.append(f"ambient identity: FAILED: /cookie/page.html: {why}")
        passed = False
    if passed:
        findings.append("ambient identity: passed: the less-trusted LoadableViews' and AsyncImages' downloads "
                        "carried no sign-in and no cookie, and stopped at their limits; the less-trusted WebView "
                        "did not get the app's own WebView's cookie; with no time limit, downloads whose server "
                        "stopped answering ended after 30 seconds")
    return passed


def main():
    parser = argparse.ArgumentParser(description="ActionUI Windows build and test driver")
    parser.add_argument("command", choices=["core", "shim", "winui"])
    parser.add_argument("--results", default=str(REPO_DIR / ".build" / "ci-windows-results"))
    parser.add_argument("--install-runtime", action="store_true",
                        help="shim, winui: install the Windows App SDK runtime for the current user first")
    arguments = parser.parse_args()
    # Piped stdout on Windows uses the ANSI code page; a log line it cannot encode (a test
    # fixture's text in an assertion message) must not end the run with a traceback.
    sys.stdout.reconfigure(errors="backslashreplace")
    results = Path(arguments.results).resolve()
    results.mkdir(parents=True, exist_ok=True)
    if arguments.command == "core":
        if shutil.which("swift") is None:
            print("ci-windows: swift is not on PATH; install the Swift toolchain for Windows",
                  file=sys.stderr)
            return 1
        return check_core(results)
    if arguments.command == "shim":
        return check_shim(results, arguments.install_runtime)
    if arguments.command == "winui":
        if shutil.which("swift") is None:
            print("ci-windows: swift is not on PATH; install the Swift toolchain for Windows",
                  file=sys.stderr)
            return 1
        return check_shim(results, arguments.install_runtime, swift=True)
    return 2


if __name__ == "__main__":
    sys.exit(main())
