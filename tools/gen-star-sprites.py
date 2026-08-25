#!/usr/bin/env python
"""Generate the starfield sprite PNGs in resources/drawables.

The field draws each bright tier as a single tinted blit (Dial.drawStarSprite),
so the sprite files are the shape of the stars. They are grayscale on opaque
black: drawBitmap2's :tintColor scales by luminance, so a 255 pixel comes out
at the star's full colour and a 115 pixel at 45% of it - which is how the
sparkle's dim diagonals ride along in the same call.

Sizes are 2x the original 3/5/7 px sprites: arms of 2, 4 and 6 pixels around a
centre pixel, so 5x5, 9x9 and 13x13. Doubling a one-pixel cross on its own
reads as a spider rather than a star, so the arms fade towards their tips and
the near-diagonals carry a little body.

Run:  python tools/gen-star-sprites.py
"""

import os
import struct
import zlib

OUT = os.path.join(os.path.dirname(__file__), "..", "resources", "drawables")

# Per tier: arm length, brightness along an arm by distance (index 0 is the
# centre), and brightness along a diagonal by distance (index 0 unused).
TIERS = [
    # tier 0 - the faint majority of the field. Smallest sprite, still round.
    ("star_5x5.png",   2, [255, 255, 150],                          [0, 60]),
    # tier 1 - a longer cross with a solid core.
    ("star_9x9.png",   4, [255, 255, 210, 150, 80],                 [0, 90, 40]),
    # tier 2/3 - the four-point sparkle; the diagonals are its body.
    ("star_13x13.png", 6, [255, 255, 225, 190, 150, 110, 70],       [0, 115, 100, 70]),
]


def build(arm, axis, diag):
    n = 2 * arm + 1
    rows = [[0] * n for _ in range(n)]
    for dy in range(-arm, arm + 1):
        for dx in range(-arm, arm + 1):
            v = 0
            if dx == 0 or dy == 0:
                v = axis[max(abs(dx), abs(dy))]
            elif abs(dx) == abs(dy) and abs(dx) < len(diag):
                v = diag[abs(dx)]
            rows[dy + arm][dx + arm] = v
    return rows


def write_png(path, rows):
    n = len(rows)
    raw = b"".join(b"\x00" + bytes(b for v in row for b in (v, v, v)) for row in rows)
    def chunk(tag, data):
        c = tag + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c))
    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", struct.pack(">IIBBBBB", n, n, 8, 2, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(raw, 9))
           + chunk(b"IEND", b""))
    with open(path, "wb") as f:
        f.write(png)


for name, arm, axis, diag in TIERS:
    rows = build(arm, axis, diag)
    write_png(os.path.join(OUT, name), rows)
    print(name)
    for row in rows:
        print("  " + "".join(" .:-=+*#%@"[v * 9 // 255] for v in row))
