#!/usr/bin/env python3
"""make_icon_svg.py - draws the ActionUI MCP server's icon as one SVG: a circle with the ActionUI braces and a
play triangle, from circle-tile.svg (icedit's template, copied here) and the two glyphs beside it.

    make_icon_svg.py <linux|macos> <output.svg>

  linux   the template as it is: a 944 circle with its darker side, as GNOME's app icons are drawn.
  macos   the flat circle 1008 across, centered, no side: the Dock draws icons small, where a margin
          or a shadow only makes the icon smaller and duller (see the template's comment).

The circle sets the server apart from regular apps, whose icons are rounded squares: it is a server an
agent started, not an app the user opened. The glyphs are Material Symbols Rounded (Apache License 2.0),
drawn with glyphsvg at weight 400: data_object, and play_arrow filled. Their placement follows the
template's mapping for Icon Composer layers (a 768 box on the 1024 artboard, then scale and move).
Output follows the template's rules: plain groups and paths, no nested <svg>, so KDE Plasma's Qt
renderer draws it too. Exit status 0 when written, 1 otherwise.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))

FACE = ("#303030", "#1b1b1b")         # top and bottom of the circle
SIDE = "#0c0c0c"                      # the darker side below it (linux)
GLYPH = ("#ffa640", "#e5841c")        # the glyphs, top to bottom of the canvas
MACOS_DIAMETER = 1008

# (glyph file, scale, x, y): as Icon Composer layers, bottom layer first
LAYERS = [
    ("data_object.svg", 1.1, 0, 0),
    ("play_arrow.svg", 0.47, 30, 0),
]


def glyph_group(name, scale, tx, ty):
    """The glyph's paths in a group that does what the template asks of a layer."""
    text = open(os.path.join(HERE, name)).read()
    box = re.search(r'viewBox="([^"]+)"', text)
    paths = re.findall(r'<path d="([^"]+)"', text)
    if not box or not paths:
        raise ValueError(f"{name}: no viewBox or no path")
    x, y, w, h = (float(v) for v in box.group(1).split())
    s = min(768 / w, 768 / h)
    inner = f"translate({(768 - w * s) / 2 - x * s:.2f}, {(768 - h * s) / 2 - y * s:.2f}) scale({s:.4f})"
    outer = f"translate({512 + tx:g}, {512 + ty:g}) scale({scale:g}) translate(-384, -384)"
    body = "\n".join(f'        <path d="{d}"/>' for d in paths)
    layer_id = name.rsplit(".", 1)[0]
    return (f'    <g id="{layer_id}" transform="{outer}">\n'
            f'      <g transform="{inner}">\n{body}\n      </g>\n    </g>')


def replace_once(text, old, new):
    if text.count(old) != 1:
        raise ValueError(f"circle-tile.svg: expected one {old!r}; the template changed?")
    return text.replace(old, new)


def icon_svg(platform):
    t = open(os.path.join(HERE, "circle-tile.svg")).read()
    t = re.sub(r"<!--.*?-->\n", "", t, count=1, flags=re.S)
    t = replace_once(t, 'stop-color="#4b4b52"', f'stop-color="{FACE[0]}"')
    t = replace_once(t, 'stop-color="#1f1f23"', f'stop-color="{FACE[1]}"')
    t = t.replace('stop-color="#121214"', f'stop-color="{SIDE}"')
    t = replace_once(t, "  </defs>",
                     '    <linearGradient id="glyph-fill" gradientUnits="userSpaceOnUse" x1="0" y1="0" x2="0" y2="1024">\n'
                     f'      <stop offset="0" stop-color="{GLYPH[0]}"/>\n'
                     f'      <stop offset="1" stop-color="{GLYPH[1]}"/>\n'
                     "    </linearGradient>\n  </defs>")
    if platform == "macos":
        r = MACOS_DIAMETER / 2
        t, removed = re.subn(r'  <circle id="tile-side"[^>]*/>\n', "", t)
        if removed != 1:
            raise ValueError("circle-tile.svg: no tile-side circle")
        t = replace_once(t, 'cx="512" cy="496" r="472"', f'cx="512" cy="512" r="{r:g}"')
        t = replace_once(t, 'transform="translate(40, 24) scale(0.921875)"',
                         f'transform="translate({512 - r:g}, {512 - r:g}) scale({MACOS_DIAMETER / 1024:g})"')
    groups = "\n".join(glyph_group(*layer) for layer in LAYERS)
    t, filled = re.subn(r'(<g id="layers" transform="[^"]+")>\n  </g>',
                        lambda m: m.group(1) + ' fill="url(#glyph-fill)">\n' + groups + "\n  </g>", t)
    if filled != 1:
        raise ValueError("circle-tile.svg: no empty layers group")
    return t


def main(argv):
    if len(argv) != 3 or argv[1] not in ("linux", "macos"):
        sys.stderr.write("usage: make_icon_svg.py <linux|macos> <output.svg>\n")
        return 1
    try:
        svg = icon_svg(argv[1])
        with open(argv[2], "w") as out:
            out.write(svg)
    except (OSError, ValueError) as error:
        sys.stderr.write(f"make_icon_svg.py: {error}\n")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
