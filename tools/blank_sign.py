#!/usr/bin/env python3
"""Erase the painted lettering from a shop sign, leaving a blank plank.

Reference art arrives with the shop name painted on: "Bäckerei", "Café". Baked
in, that name is permanent — a French or Spanish build would still have a German
bakery. So the lettering comes OFF the sprite and is drawn by the engine from the
strings table instead, which is the whole point of Part 5 §7 keeping strings in a
table from day one.

Erasing works because a sign is dark wood with light letters. Every light pixel
inside the plank is replaced by the nearest wood pixel on its own row, which
preserves the horizontal grain and the bevel highlights along the top and bottom
edges. A flat fill would read as a sticker taped over the sign.

Usage:
  .venv/bin/python tools/blank_sign.py SRC.png --rect L,T,R,B [--rect ...] --out OUT.png
"""

import argparse
import sys

from PIL import Image


def blank(im, rect, tolerance, grow):
    """Replace lettering pixels inside `rect` with neighbouring wood.

    Lettering is found by distance from the row's MEDIAN colour, not by
    brightness. Painted letters have a cream core and a dark outline, and a
    brightness test removes only the core — leaving a legible ghost of the word
    embossed in the plank, which is worse than leaving it alone.

    The mask is then grown a couple of pixels, because the anti-aliased rim of a
    letter sits between the two colours and survives any threshold that does not
    also eat the wood.
    """
    left, top, right, bottom = rect
    px = im.load()
    width = right - left
    height = bottom - top

    rows = [[px[x, y] for x in range(left, right)] for y in range(top, bottom)]
    medians = []
    for row in rows:
        channels = []
        for ch in range(3):
            values = sorted(c[ch] for c in row)
            channels.append(values[len(values) // 2])
        medians.append(tuple(channels))

    mask = [[sum(abs(rows[j][i][ch] - medians[j][ch]) for ch in range(3)) > tolerance
             for i in range(width)] for j in range(height)]

    for _ in range(grow):
        grown = [row[:] for row in mask]
        for j in range(height):
            for i in range(width):
                if mask[j][i]:
                    continue
                for dj, di in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nj, ni = j + dj, i + di
                    if 0 <= nj < height and 0 <= ni < width and mask[nj][ni]:
                        grown[j][i] = True
                        break
        mask = grown

    erased = 0
    for j in range(height):
        wood = [i for i in range(width) if not mask[j][i]]
        for i in range(width):
            if not mask[j][i]:
                continue
            if wood:
                source = min(wood, key=lambda w: abs(w - i))
                px[left + i, top + j] = rows[j][source]
            else:
                px[left + i, top + j] = medians[j] + (255,)
            erased += 1
    return erased


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("source")
    ap.add_argument("--rect", action="append", required=True,
                    help="left,top,right,bottom of a plank interior; repeatable")
    ap.add_argument("--tolerance", type=int, default=60,
                    help="summed RGB distance from the row's wood colour that counts as lettering")
    ap.add_argument("--grow", type=int, default=2,
                    help="how many pixels to dilate the lettering mask")
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    im = Image.open(args.source).convert("RGBA")
    total = 0
    for spec in args.rect:
        rect = tuple(int(v) for v in spec.split(","))
        if len(rect) != 4:
            raise SystemExit("--rect wants left,top,right,bottom")
        n = blank(im, rect, args.tolerance, args.grow)
        print("blanked %d lettering px in %s" % (n, rect))
        total += n
    if total == 0:
        print("WARNING: nothing was erased — check the rect and threshold",
              file=sys.stderr)
    im.save(args.out)
    print("wrote %s" % args.out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
