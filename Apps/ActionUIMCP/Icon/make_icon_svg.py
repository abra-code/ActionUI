#!/usr/bin/env python3
"""make_icon_svg.py - draws the ActionUI MCP server's icon as one SVG: a gunmetal gear with a darker recessed
disc, and on it the ActionUI braces and a play triangle in yellow, from circle-tile.svg (icedit's template,
copied here; the gear takes the place of its circle) and the two glyphs beside it.

    make_icon_svg.py <linux|macos> <output.svg>

  linux   the template's size: a gear 944 across with its darker side, as GNOME's app icons are drawn.
  macos   a flat gear 1008 across, centered, no side: the Dock draws icons small, where a margin or a
          shadow only makes the icon smaller and duller (see the template's comment).

The round gear sets the server apart from regular apps, whose icons are rounded squares: it is a server an
agent started, not an app the user opened. It has 24 rounded teeth, the fewest that still read as a fine
gear and the most that stay apart at Dock sizes. The yellow is the one the server's windows are marked with. The glyphs are Material Symbols Rounded (Apache License 2.0),
drawn with glyphsvg at weight 400: data_object, and play_arrow filled. Their placement follows the
template's mapping for Icon Composer layers (a 768 box on the 1024 artboard, then scale and move).
Output follows the template's rules: plain groups and paths, no nested <svg>, so KDE Plasma's Qt
renderer draws it too. Exit status 0 when written, 1 otherwise.
"""

import math
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))

FACE = ("#7c848d", "#3b4147")         # top and bottom of the gear: gunmetal
SIDE = "#1e2226"                      # the darker side below it (linux)
DISC = ("#23272b", "#363b41")         # the recessed disc, darker at the top
GLYPH = ("#fcf061", "#d8b94a")        # the glyphs, top to bottom of the canvas
MACOS_DIAMETER = 1008

# The gear, as fractions of its outer radius: tooth roots, the disc; then the number of teeth and, as
# fractions of the tooth pitch, the flat tip and each eased flank
ROOT = 456 / 504
DISC_RADIUS = 400 / 504
TEETH = 24
TIP, FLANK = 0.38, 0.16

# (glyph file, scale, x, y): as Icon Composer layers, bottom layer first; 0.8 of the sizes that filled
# the circle, to sit inside the disc
LAYERS = [
    ("data_object.svg", 0.88, 0, 0),
    ("play_arrow.svg", 0.376, 24, 0),
]


def smoothstep(e0, e1, x):
    t = min(max((x - e0) / (e1 - e0), 0.0), 1.0)
    return t * t * (3 - 2 * t)


def gear_path(cx, cy, outer):
    """The gear's outline as straight segments (SVG Tiny has no arcs): per tooth, a flat tip at the outer
    radius and flanks easing down to the root."""
    root = outer * ROOT
    per_tooth = 24
    points = []
    for k in range(TEETH * per_tooth):
        angle = 2 * math.pi * k / (TEETH * per_tooth)
        from_center = abs((k % per_tooth) / per_tooth - 0.5)
        r = root + (outer - root) * (1 - smoothstep(TIP / 2, TIP / 2 + FLANK, from_center))
        points.append((cx + r * math.sin(angle), cy - r * math.cos(angle)))
    return "M" + " L".join(f"{x:.1f},{y:.1f}" for x, y in points) + " Z"


def gear(match, fill_id, element_id):
    """A template circle element replaced by the gear with the same center and radius."""
    cx, cy, r = (float(match.group(name)) for name in ("cx", "cy", "r"))
    return f'<path id="{element_id}" d="{gear_path(cx, cy, r)}" fill="url(#{fill_id})"/>'


def disc(match):
    cx, cy, r = (float(match.group(name)) for name in ("cx", "cy", "r"))
    return f'<circle id="disc" cx="{cx:g}" cy="{cy:g}" r="{r * DISC_RADIUS:.1f}" fill="url(#disc-fill)"/>'


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
                     "    </linearGradient>\n"
                     '    <linearGradient id="disc-fill" x1="0" y1="0" x2="0" y2="1">\n'
                     f'      <stop offset="0" stop-color="{DISC[0]}"/>\n'
                     f'      <stop offset="1" stop-color="{DISC[1]}"/>\n'
                     "    </linearGradient>\n  </defs>")
    if platform == "macos":
        r = MACOS_DIAMETER / 2
        t, removed = re.subn(r'  <circle id="tile-side"[^>]*/>\n', "", t)
        if removed != 1:
            raise ValueError("circle-tile.svg: no tile-side circle")
        t = replace_once(t, 'cx="512" cy="496" r="472"', f'cx="512" cy="512" r="{r:g}"')
        t = replace_once(t, 'transform="translate(40, 24) scale(0.921875)"',
                         f'transform="translate({512 - r:g}, {512 - r:g}) scale({MACOS_DIAMETER / 1024:g})"')
    # The gear in place of the circle (and of its side, on Linux), the disc on its face.
    circle = r'<circle id="{}" cx="(?P<cx>[\d.]+)" cy="(?P<cy>[\d.]+)" r="(?P<r>[\d.]+)" fill="[^"]+"/>'
    t, sides = re.subn(circle.format("tile-side"), lambda m: gear(m, "side-fill", "tile-side"), t)
    if sides != (1 if platform == "linux" else 0):
        raise ValueError("circle-tile.svg: the tile-side circle changed")
    t, faces = re.subn(circle.format("tile-face"), lambda m: gear(m, "face-fill", "tile-face") + "\n  " + disc(m), t)
    if faces != 1:
        raise ValueError("circle-tile.svg: the tile-face circle changed")
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
