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

On Linux
--------
The extension links to libActionUI.so from the ActionUI library package
(made by Scripts/make-linux-library-package.sh, the actionui-<version>-linux-<arch>
folder), found in priority order:

  1. Environment variable ACTIONUI_LIBRARY_DIR, the unpacked package folder
         ACTIONUI_LIBRARY_DIR=/path/to/actionui-0.9.0-linux-aarch64 pip install .

  2. Local  ./library/  subdirectory next to this script, holding the package's
     contents (lib/, include/ and its license files)

The build copies libActionUI.so beside the extension (_actionui.*.so), and the
extension finds it there through its $ORIGIN rpath: the installed module is
self-contained, needing only the system's GTK 4, libadwaita and libsoup 3. The
library's licenses go beside it, as libActionUI-LICENSE.txt and
libActionUI-LICENSE-MaterialSymbols.txt (the Material Symbols icons in the library).

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
import shutil
import sys
import sysconfig
from setuptools import setup, Extension
from setuptools.command.build_ext import build_ext

# ---------------------------------------------------------------------------
# Deployment target - must match ActionUI deployment target
# ---------------------------------------------------------------------------
MIN_MACOS_VERSION = "14.6"

script_dir = os.path.dirname(os.path.abspath(__file__))


def macos_setup_arguments():
    """The extension and data files for macOS, over the static frameworks."""

    # -----------------------------------------------------------------------
    # Locate the static framework directory
    # -----------------------------------------------------------------------

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
        candidates.append(os.path.join(script_dir, 'frameworks'))

        for d in candidates:
            has_actionui  = os.path.isdir(os.path.join(d, 'ActionUI.framework'))
            has_adapter   = os.path.isdir(os.path.join(d, 'ActionUICAdapter.framework'))
            has_appkit    = os.path.isdir(os.path.join(d, 'ActionUIAppKitApplication.framework'))
            has_remote    = os.path.isdir(os.path.join(d, 'ActionUIRemote.framework'))
            if has_actionui and has_adapter and has_appkit and has_remote:
                return d

        return None

    fw_dir = find_frameworks_dir()

    if fw_dir is None:
        print(
            "Error: could not locate all required static frameworks.\n"
            "\n"
            "Provide the path to the directory that contains all four static .framework\n"
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
    print(f"  ActionUIRemote.framework             OK")

    # -----------------------------------------------------------------------
    # Extension definition
    # -----------------------------------------------------------------------
    #
    # Compile flags
    #   -F{fw_dir}      exposes <ActionUICAdapter/ActionUIC.h> and
    #                   <ActionUIAppKitApplication/ActionUIApp.h> via the -F framework
    #                   search path so #include <ActionUICAdapter/…> resolves correctly.
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
        # Plain C, over the frameworks' plain C headers (ActionUIC.h, ActionUIApp.h).
        sources=['actionui_native.c'],
        extra_compile_args=[
            f'-F{fw_dir}',
            f"-mmacosx-version-min={MIN_MACOS_VERSION}",
        ],
        extra_link_args=[
            f'-F{fw_dir}',
            '-framework', 'ActionUI',
            '-framework', 'ActionUICAdapter',
            '-framework', 'ActionUIAppKitApplication',
            '-framework', 'ActionUIRemote',
            # System frameworks used by ActionUI's Swift code.
            # clang resolves these from the SDK sysroot on any standard macOS
            # setup, but listing them explicitly avoids surprises in CI or
            # non-standard toolchain environments.
            '-framework', 'Foundation',
            '-framework', 'SwiftUI',
            '-framework', 'AppKit',
            '-framework', 'AVKit',
            '-framework', 'Charts',
            f"-mmacosx-version-min={MIN_MACOS_VERSION}",
        ],
    )

    # -----------------------------------------------------------------------
    # Data files — default app icon
    # -----------------------------------------------------------------------
    # data_files destinations are relative to sys.prefix when installed via pip.
    # Compute the relative path from sys.prefix to the purelib (site-packages)
    # directory so the icon lands alongside actionui.py.
    _purelib = sysconfig.get_path('purelib')
    _prefix  = sysconfig.get_config_var('prefix') or sys.prefix
    _site_packages_rel = os.path.relpath(_purelib, _prefix)

    return {
        'ext_modules': [actionui_extension],
        'data_files': [(_site_packages_rel, ['actionui-app-icon.icns'])],
    }


class build_ext_with_library(build_ext):
    """Builds the extension, then copies libActionUI.so beside it (Linux), where its
    $ORIGIN rpath finds it: in the build folder, which a wheel or an install copies
    whole, and in this folder for an in-place build. The library's licenses go with it:
    ActionUI's, and that of the Material Symbols icons compiled into the library."""

    library_dir = None

    # The package's license files, and their names beside the library: modules install
    # into the shared site-packages folder, where a plain LICENSE.txt would clash.
    license_files = [
        ('LICENSE.txt', 'libActionUI-LICENSE.txt'),
        ('LICENSE-MaterialSymbols.txt', 'libActionUI-LICENSE-MaterialSymbols.txt'),
    ]

    def run(self):
        super().run()
        folder = os.path.dirname(self.get_ext_fullpath('_actionui'))
        destination = os.path.join(folder, 'libActionUI.so')
        # A new file, not the old one overwritten: a program still running from an in-place
        # build keeps the library it mapped.
        if os.path.exists(destination):
            os.remove(destination)
        shutil.copy2(os.path.join(self.library_dir, 'lib', 'libActionUI.so'), destination)
        for source, name in self.license_files:
            shutil.copy2(os.path.join(self.library_dir, source), os.path.join(folder, name))


def linux_setup_arguments():
    """The extension for Linux, over libActionUI.so from the library package."""

    candidates = []
    env = os.environ.get('ACTIONUI_LIBRARY_DIR', '').strip()
    if env:
        # Absolute: pip may build in another folder than the one the path was given in.
        candidates.append(os.path.abspath(env))
    candidates.append(os.path.join(script_dir, 'library'))

    library_dir = None
    for d in candidates:
        has_library = os.path.isfile(os.path.join(d, 'lib', 'libActionUI.so'))
        has_headers = (os.path.isfile(os.path.join(d, 'include', 'ActionUICAdapter', 'ActionUIC.h'))
                       and os.path.isfile(os.path.join(d, 'include', 'ActionUIAppKitApplication', 'ActionUIApp.h')))
        has_licenses = all(os.path.isfile(os.path.join(d, source))
                           for source, _ in build_ext_with_library.license_files)
        if has_library and has_headers and not has_licenses:
            # A package made before it carried the icons' license: name it rather than
            # quietly trying the next folder.
            print(f"Error: {d} has no LICENSE.txt or LICENSE-MaterialSymbols.txt; make the\n"
                  "library package again with Scripts/make-linux-library-package.sh.",
                  file=sys.stderr)
            sys.exit(1)
        if has_library and has_headers:
            library_dir = d
            break

    if library_dir is None:
        print(
            "Error: could not locate the ActionUI library package.\n"
            "\n"
            "Provide the path to the unpacked actionui-<version>-linux-<arch> folder\n"
            "(lib/libActionUI.so, include/..., LICENSE.txt, LICENSE-MaterialSymbols.txt)\n"
            "using the ACTIONUI_LIBRARY_DIR environment variable:\n"
            "\n"
            "  ACTIONUI_LIBRARY_DIR=/path/to/actionui-0.9.0-linux-aarch64 pip install .\n"
            "\n"
            "Or place its contents in ./library/ next to this script.\n"
            "\n"
            "Make the package with Scripts/make-linux-library-package.sh.",
            file=sys.stderr,
        )
        sys.exit(1)

    print(f"ActionUI library package : {library_dir}")
    build_ext_with_library.library_dir = library_dir

    # The headers at the paths the Apple frameworks give them (<ActionUICAdapter/ActionUIC.h>),
    # so actionui_native.c includes them the same way on both platforms.
    actionui_extension = Extension(
        '_actionui',
        sources=['actionui_native.c'],
        include_dirs=[os.path.join(library_dir, 'include')],
        library_dirs=[os.path.join(library_dir, 'lib')],
        libraries=['ActionUI'],
        extra_link_args=['-Wl,-rpath,$ORIGIN'],
    )

    return {
        'ext_modules': [actionui_extension],
        'cmdclass': {'build_ext': build_ext_with_library},
    }


if sys.platform == 'darwin':
    setup_arguments = macos_setup_arguments()
elif sys.platform.startswith('linux'):
    setup_arguments = linux_setup_arguments()
else:
    print("Error: the ActionUI Python extension supports macOS and Linux", file=sys.stderr)
    sys.exit(1)

setup(**setup_arguments)
