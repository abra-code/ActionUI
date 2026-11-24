#!/bin/bash
# make-symbol-fonts.sh - make the Fluent System Icons font the web renderer draws the SF Symbols that
# Material Symbols lacks with, and place it in ActionUIWeb/assets.
#
# The web draws Material glyphs with the Material Symbols web font the host page loads (see README.md).
# For an SF Symbol name the SF -> Material map has no row for, it draws the glyph that
# Tools/fluent_symbols/sf_to_fluent.map names, from this font. Nothing written here is committed:
#
#   assets/fonts/FluentSymbols.woff2                 the map's glyphs, the regular ones emboldened
#   assets/symbols/sf_to_fluent.map                  a copy of the map
#   assets/licenses/FluentSystemIcons-LICENSE.txt    the MIT license, with what was changed
#
# Steps: Tools/fluent_symbols/fetch-fluent-icons-font.sh downloads the upstream font at the map's commit
# (once); fontTools and brotli are installed at pinned versions into a private Python environment in
# Tools/material_symbols/build/web-python (once; outside ActionUIWeb, so packaging an app never copies
# it); Tools/material_symbols/make_symbol_fonts.py makes the font, the same one the Android build makes
# as FluentSymbols.ttf. A first run needs Python 3 and network access to GitHub and PyPI; later runs
# need neither.
#
# Usage:
#   bash scripts/make-symbol-fonts.sh
#
# PYTHON names the Python 3 (3.10 or later, for fontTools) that creates the private environment; the
# default is the python3 found on PATH, as in the Android build.
#
# Exit codes: 0 the files are in place; 1 a step failed (its message says which).

# Same fontTools as the Android build (ActionUIAndroid/library/build.gradle.kts, pinnedFontToolsVersion).
FONTTOOLS_VERSION="4.62.1"
BROTLI_VERSION="1.2.0"

script_dir="$(CDPATH= cd -P -- "$(/usr/bin/dirname "$0")" && pwd)"
if [ -z "$script_dir" ]; then
    printf 'error: could not find the folder of %s\n' "$0" >&2
    exit 1
fi
web_root="$(CDPATH= cd -P -- "$script_dir/.." && pwd)"
repo_root="$(CDPATH= cd -P -- "$web_root/.." && pwd)"
if [ -z "$web_root" ] || [ -z "$repo_root" ]; then
    printf 'error: could not find the ActionUIWeb folder above %s\n' "$script_dir" >&2
    exit 1
fi
if [ $# -ne 0 ]; then
    printf 'usage: bash %s\n' "$0" >&2
    exit 1
fi

/bin/bash "$repo_root/Tools/fluent_symbols/fetch-fluent-icons-font.sh"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'error: the Fluent System Icons font could not be fetched (see above)\n' >&2
    exit 1
fi

# The private Python environment, remade when the pinned versions change.
python_env="$repo_root/Tools/material_symbols/build/web-python"
python="$python_env/bin/python"
stamp="$python_env/requirements"
wanted="fonttools==$FONTTOOLS_VERSION brotli==$BROTLI_VERSION"
installed=""
if [ -r "$stamp" ]; then
    read -r installed < "$stamp"
fi
if [ "$installed" != "$wanted" ] || [ ! -x "$python" ]; then
    printf 'Installing %s into %s...\n' "$wanted" "$python_env"
    base_python="${PYTHON:-$(command -v python3)}"
    if [ -z "$base_python" ]; then
        printf 'error: no python3 on PATH; set PYTHON to a Python 3.10 or later\n' >&2
        exit 1
    fi
    "$base_python" -m venv --clear "$python_env"
    status=$?
    if [ "$status" -ne 0 ]; then
        printf 'error: could not create a Python environment in %s (set PYTHON to a Python 3)\n' "$python_env" >&2
        exit 1
    fi
    "$python" -m pip install --isolated --disable-pip-version-check --quiet \
        "fonttools==$FONTTOOLS_VERSION" "brotli==$BROTLI_VERSION"
    status=$?
    if [ "$status" -ne 0 ]; then
        printf 'error: pip could not install %s (is PyPI reachable? fontTools needs Python 3.10 or later: set PYTHON)\n' "$wanted" >&2
        exit 1
    fi
    printf '%s\n' "$wanted" > "$stamp"
    status=$?
    if [ "$status" -ne 0 ]; then
        printf 'error: could not write %s\n' "$stamp" >&2
        exit 1
    fi
fi

"$python" -I "$repo_root/Tools/material_symbols/make_symbol_fonts.py" web "$web_root/assets"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'error: make_symbol_fonts.py failed (see above)\n' >&2
    exit 1
fi
exit 0
