#!/usr/bin/env python3
"""Cut a crop-growth TILE STRIP out of the founder's farmland reference.

Four earlier attempts tried to isolate individual plants and all four failed, in
an instructive way: this reference does not draw crops as sprites, it draws them
as a PATTERN of plants on soil. Cutting one plant out yields three green pixels
with no shape. The plots themselves, though, are exactly what a tiled field
needs — "a tile of young crop", "a tile of grown crop" — so the unit to extract
is a 16x16 window, not a plant.

The windows are opaque and carry their own soil, so a crop tile REPLACES the
soil tile beneath it rather than compositing over it.

Two filters do all the work:
  * soil must dominate even at full growth, or the ripe frame is a patch of
    lawn and the field stops reading as tilled;
  * the tile's own edges must be soil, so a window straddling the grass border
    between two plots is rejected instead of shipping a green stripe.

Usage:
  .venv/bin/python tools/extract_crop_tiles.py SOURCE.png --crop L,T,R,B --out NAME.png
"""

import argparse
import os
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SPRITES = os.path.join(ROOT, "game", "assets", "sprites")
CELL = 16


def is_leaf(rgb):
    r, g, b = rgb[:3]
    return g > r + 18 and g > 85 and b < g


def is_soil(rgb):
    r, g, b = rgb[:3]
    return r > g + 12 and r > 60 and b < r - 25


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("source")
    ap.add_argument("--crop", required=True, help="left,top,right,bottom in SOURCE pixels")
    ap.add_argument("--scale", type=int, default=4)
    ap.add_argument("--stages", type=int, default=5)
    ap.add_argument("--min-soil", type=int, default=120,
                    help="soil pixels a tile must have to count as tilled ground")
    ap.add_argument("--max-leaf", type=int, default=70,
                    help="leaf pixels above which a tile is lawn, not a crop")
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    im = Image.open(args.source).convert("RGB")
    im = im.crop(tuple(int(v) for v in args.crop.split(",")))
    w, h = im.size
    im = im.resize((w // args.scale, h // args.scale), Image.BOX)
    w, h = im.size
    px = im.load()

    def edges_are_soil(tx, ty):
        for y in range(ty, ty + CELL):
            for x in (tx, tx + CELL - 1):
                if is_leaf(px[x, y]):
                    return False
        for x in range(tx, tx + CELL):
            for y in (ty, ty + CELL - 1):
                if is_leaf(px[x, y]):
                    return False
        return True

    tiles = []
    for ty in range(0, h - CELL, 2):
        for tx in range(0, w - CELL, 2):
            leaf = 0
            soil = 0
            for y in range(ty, ty + CELL):
                for x in range(tx, tx + CELL):
                    c = px[x, y]
                    if is_leaf(c):
                        leaf += 1
                    elif is_soil(c):
                        soil += 1
            if soil >= args.min_soil and leaf <= args.max_leaf and edges_are_soil(tx, ty):
                tiles.append((leaf, tx, ty))

    if len(tiles) < args.stages:
        raise SystemExit("only %d usable tiles found" % len(tiles))
    tiles.sort()
    print("%d candidate tiles, leaf %d..%d" % (len(tiles), tiles[0][0], tiles[-1][0]))

    picks = [tiles[min(len(tiles) - 1, int(i * (len(tiles) - 1) / (args.stages - 1)))]
             for i in range(args.stages)]
    sheet = Image.new("RGBA", (CELL * args.stages, CELL))
    for index, (leaf, tx, ty) in enumerate(picks):
        sheet.paste(im.crop((tx, ty, tx + CELL, ty + CELL)), (index * CELL, 0))
        print("  stage %d: %d leaf px" % (index, leaf))

    dest = args.out if os.path.isabs(args.out) else os.path.join(SPRITES, args.out)
    sheet.save(dest)
    print("wrote %s  %dx%d" % (os.path.relpath(dest, ROOT), sheet.width, sheet.height))
    return 0


if __name__ == "__main__":
    sys.exit(main())
