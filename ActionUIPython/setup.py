#!/usr/bin/env python3
"""
Setup script for building the ActionUI Python extension module.

ActionUI.framework and ActionUICAdapter.framework are STATIC frameworks.
Their compiled code is linked directly into the resulting .so, making the
extension fully self-contained — no frameworks need to be installed at
runtime.  Only Apple system frameworks (Foundation, SwiftUI, AppKit) are
dynamic dependencies; those are part of macOS and always present.

Locating the frameworks
-----------------------
Provide the path to a directory that contains both pre-built static
.framework bundles using one of the following methods, in priority order:

  1. Environment variable ACTIONUI_FRAMEWORKS_DIR
         ACTIONUI_FRAMEWORKS_DIR=/path/to/dir pip install .

  2. Local  ./frameworks/  subdirectory next to this script
         Place ActionUI.framework and ActionUICAdapter.framework there.

The expected layout inside that directory:
    <dir>/
        ActionUI.framework/
            ActionUI          ← static library (Mach-O archive)
            Headers/
                ...
            Modules/
                ...
        ActionUICAdapter.framework/
            ActionUICAdapter  ← static library
            Headers/
                ActionUIC.h
                ActionUICAdapter.h
                ActionUICAdapter-Swift.h   ← Swift-generated declarations
            Modules/
                ...
        ActionUIAppKitApplication.framework/
            ActionUIAppKitApplication  ← static library
            Headers/
                ActionUIApp.h
                ActionUIAppKitApplication.h
                ActionUIAppKitApplication-Swift.h  ← Swift-generated declarations
            Modules/
                ...

Building
--------
    # Standard install (recommended):
    pip install .

    # Editable / development install:
    pip install -e .

    # Build the .so in-place for development without installing:
    python3 setup.py build_ext --inplace

    # Or with an explicit path:
    ACTIONUI_FRAMEWORKS_DIR=/path/to/frameworks \\
        python3 setup.py build_ext --inplace

Future: ActionUI releases will publish pre-built static framework archives
as GitHub Actions artifacts.  A fetch helper will be added to download and
unpack them into ./frameworks/ automatically before this script runs.
"""

import os
import sys
from setuptools import setup, Extension

# ---------------------------------------------------------------------------
# Deployment target - must match ActionUI deployment target
# ---------------------------------------------------------------------------
MIN_MACOS_VERSION = "14.6"

if sys.platform != 'darwin':
    print("Error: ActionUI Python extension only supports macOS", file=sys.stderr)
    sys.exit(1)

# ---------------------------------------------------------------------------
# Locate the static framework directory
# ---------------------------------------------------------------------------

def find_frameworks_dir():
    """
    Return the first directory that contains both static .framework bundles,
    or None if neither candidate is valid.
    """
    candidates = []

    env = os.environ.get('ACTIONUI_FRAMEWORKS_DIR', '').strip()
    if env:
        candidates.append(env)

    # Convenience: ./frameworks/ next to this script
    script_dir = os.path.dirname(os.path.abspath(__file__))
    candidates.append(os.path.join(script_dir, 'frameworks'))

    for d in candidates:
        has_actionui  = os.path.isdir(os.path.join(d, 'ActionUI.framework'))
        has_adapter   = os.path.isdir(os.path.join(d, 'ActionUICAdapter.framework'))
        has_appkit    = os.path.isdir(os.path.join(d, 'ActionUIAppKitApplication.framework'))
        if has_actionui and has_adapter and has_appkit:
            return d

    return None


fw_dir = find_frameworks_dir()

if fw_dir is None:
    print(
        "Error: could not locate all required static frameworks.\n"
        "\n"
        "Provide the path to the directory that contains all three static .framework\n"
        "bundles using the ACTIONUI_FRAMEWORKS_DIR environment variable:\n"
        "\n"
        "  ACTIONUI_FRAMEWORKS_DIR=/path/to/frameworks pip install .\n"
        "\n"
        "Or place both .framework bundles in ./frameworks/ next to this script.\n"
        "\n"
        "Build the frameworks from the ActionUI Xcode project (see BUILD.md),\n"
        "or download a pre-built archive from the ActionUI GitHub releases.",
        file=sys.stderr,
    )
    sys.exit(1)

print(f"Static frameworks directory            : {fw_dir}")
print(f"  ActionUI.framework                   OK")
print(f"  ActionUICAdapter.framework           OK")
print(f"  ActionUIAppKitApplication.framework  OK")

# ---------------------------------------------------------------------------
# Extension definition
# ---------------------------------------------------------------------------
#
# Compile flags
#   -F{fw_dir}      exposes <ActionUICAdapter/ActionUICAdapter-Swift.h> and
#                   <ActionUICAdapter/ActionUIC.h> via the -F framework search
#                   path so #include <ActionUICAdapter/…> resolves correctly.
#
# Link flags
#   -F{fw_dir}      lets the linker locate the .framework bundles.
#   -framework X    links X statically (the linker reads the Mach-O archive
#                   inside the bundle and bakes the code into the extension .so).
#   No -rpath       there is no runtime framework search needed for ActionUI or
#                   ActionUICAdapter — they are fully embedded in the .so.
#
# System frameworks (Foundation, SwiftUI, AppKit) are resolved automatically
# via the macOS SDK sysroot; they remain dynamic OS-level dependencies.
#
actionui_extension = Extension(
    '_actionui',
    # actionui_native.m is compiled as Objective-C so that __OBJC__ is
    # defined automatically by clang.  The Swift-generated bridging header
    # (ActionUICAdapter-Swift.h) guards all @_cdecl function declarations
    # with #if defined(__OBJC__); ObjC compilation mode enters that block
    # naturally without any preprocessor tricks.  The source code itself
    # is plain C — only the compilation mode is Objective-C.
    sources=['actionui_native.m'],
    extra_compile_args=[
        f'-F{fw_dir}',
        f"-mmacosx-version-min={MIN_MACOS_VERSION}",
    ],
    extra_link_args=[
        f'-F{fw_dir}',
        '-framework', 'ActionUI',
        '-framework', 'ActionUICAdapter',
        '-framework', 'ActionUIAppKitApplication',
        # ObjC runtime (required when linking any .m translation unit).
        # '-lobjc',
        # System frameworks used by ActionUI's Swift code.
        # clang resolves these from the SDK sysroot on any standard macOS
        # setup, but listing them explicitly avoids surprises in CI or
        # non-standard toolchain environments.
        '-framework', 'Foundation',
        '-framework', 'SwiftUI',
        '-framework', 'AppKit',
        '-framework', 'AVKit',
        f"-mmacosx-version-min={MIN_MACOS_VERSION}",
    ],
)

setup(ext_modules=[actionui_extension])
