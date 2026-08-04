#!/usr/bin/env python3
"""Slice a hand-picked pixel-art ground reference into a corner-Wang tileset.

The founder supplied a painted ground reference (grass with winding dirt paths)
and asked for THAT art in the game. This turns the painting into a tileset:

  1. downsample the upscaled image back to its native pixel grid
  2. quantise to a tight palette so edges are crisp pixels, not gradients
  3. slice 16x16 tiles
  4. classify every tile by which of its four CORNERS are dirt vs grass
  5. keep several VARIANTS per corner-combination

Step 5 is the point. A single tile per combination is what made the first pass
read as flat and repetitive; the reference looks alive because no two patches of
grass are identical. The painter picks a variant per cell from a stable hash, so
the map is varied but identical on every run.

Output matches the PixelLab sidecar shape the engine already reads, plus a
`variants` block, so `WangTileset` needs only to learn about variants.

Usage:
  .venv/bin/python tools/extract_ground_tileset.py SOURCE.png [--scale 4]
"""

import argparse
import json
import os
import sys
from collections import Counter, defaultdict

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "game", "assets", "tilesets")
TILE = 16

# A pixel is "dirt" when it is warm and desaturated-brown rather than green.
def is_dirt(rgb):
    r, g, b = rgb[:3]
    return r > g and r > 110 and b < r - 30


def is_grass(rgb):
    r, g, b = rgb[:3]
    return g > r and g > 70


def downsample(im, scale):
    """Back to the native pixel grid, area-averaged."""
    w, h = im.size
    return im.resize((w // scale, h // scale), Image.BOX)


def quantise(im, colors):
    """Crisp pixels: a tight palette removes the interpolation mush."""
    q = im.convert("RGB").quantize(colors=colors, method=Image.MEDIANCUT, dither=Image.NONE)
    return q.convert("RGB")


def corner_flags(tile):
    """Which of the four quadrants are predominantly GRASS.

    Grass is the "upper" terrain, matching the convention of the existing
    ground_path_grass pack (lower = dirt path, upper = grass) so the painters
    can describe a map as "where is grass" without caring which pack is loaded.
    """
    px = tile.load()
    half = TILE // 2
    out = {}
    for name, (ox, oy) in (("NW", (0, 0)), ("NE", (half, 0)),
                           ("SW", (0, half)), ("SE", (half, half))):
        dirt = 0
        total = 0
        for y in range(oy, oy + half):
            for x in range(ox, ox + half):
                c = px[x, y]
                total += 1
                if is_dirt(c):
                    dirt += 1
        # Grass unless the quadrant is clearly worn through.
        out[name] = dirt <= total * 0.55
    return out


def key_of(flags):
    return "%d%d%d%d" % (int(flags["NE"]), int(flags["NW"]),
                         int(flags["SE"]), int(flags["SW"]))


def purity(tile, want_dirt):
    """How cleanly a tile represents its classification — used to rank variants."""
    px = tile.load()
    good = 0
    total = 0
    for y in range(TILE):
        for x in range(TILE):
            c = px[x, y]
            total += 1
            if want_dirt and is_dirt(c):
                good += 1
            elif not want_dirt and is_grass(c):
                good += 1
    return good / float(total)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("source")
    ap.add_argument("--scale", type=int, default=4,
                    help="upscale factor of the source (default 4)")
    ap.add_argument("--colors", type=int, default=48,
                    help="palette size after quantisation")
    ap.add_argument("--variants", type=int, default=6,
                    help="max tiles kept per corner combination")
    ap.add_argument("--name", default="ground_ref")
    args = ap.parse_args()

    if not os.path.exists(args.source):
        print("no such file: %s" % args.source, file=sys.stderr)
        return 2

    im = Image.open(args.source).convert("RGB")
    im = downsample(im, args.scale)
    im = quantise(im, args.colors)
    w, h = im.size
    print("native grid: %dx%d  (%d x %d tiles)" % (w, h, w // TILE, h // TILE))

    # Bucket every tile by its corner signature.
    buckets = defaultdict(list)
    for ty in range(h // TILE):
        for tx in range(w // TILE):
            tile = im.crop((tx * TILE, ty * TILE, (tx + 1) * TILE, (ty + 1) * TILE))
            flags = corner_flags(tile)
            k = key_of(flags)
            all_grass = all(flags.values())
            all_dirt = not any(flags.values())
            score = 0.0
            if all_dirt:
                score = purity(tile, True)
            elif all_grass:
                score = purity(tile, False)
            else:
                score = 0.5  # edge tiles: keep variety rather than rank
            buckets[k].append((score, tile))

    missing = [k for k in ["%d%d%d%d" % (a, b, c, d)
                           for a in (0, 1) for b in (0, 1) for c in (0, 1) for d in (0, 1)]
               if k not in buckets]
    if missing:
        print("WARNING: the reference contains no example of corner combos %s"
              % ", ".join(missing))
        print("         those cells will fall back to the nearest available tile.")

    # Keep the best N variants per combination.
    chosen = {}
    for k, entries in buckets.items():
        entries.sort(key=lambda e: -e[0])
        chosen[k] = [t for _, t in entries[:args.variants]]

    cols = max(len(v) for v in chosen.values())
    rows = len(chosen)
    atlas = Image.new("RGBA", (cols * TILE, rows * TILE), (0, 0, 0, 0))

    tiles_meta = []
    for row, k in enumerate(sorted(chosen.keys())):
        variants = []
        for col, tile in enumerate(chosen[k]):
            atlas.paste(tile, (col * TILE, row * TILE))
            variants.append([col, row])
        ne, nw, se, sw = (c == "1" for c in k)
        tiles_meta.append({
            "atlas_coords": variants[0],
            "variants": variants,
            "corners": {
                "NE": "upper" if ne else "lower",
                "NW": "upper" if nw else "lower",
                "SE": "upper" if se else "lower",
                "SW": "upper" if sw else "lower",
            },
        })

    os.makedirs(OUT_DIR, exist_ok=True)
    png_path = os.path.join(OUT_DIR, args.name + ".png")
    json_path = os.path.join(OUT_DIR, args.name + ".tiles.json")
    atlas.save(png_path)

    with open(json_path, "w", encoding="utf-8") as f:
        json.dump({
            "source": "founder-reference",
            "source_file": os.path.basename(args.source),
            "lower": "warm tan hard-packed dirt path with pebbles",
            "upper": "lush meadow grass with wildflowers, leafy clumps and stones",
            "tile_size": TILE,
            "grid": {"cols": cols, "rows": rows},
            "tiles": tiles_meta,
        }, f, indent=1)
        f.write("\n")

    print("wrote %s  (%dx%d, %d combos, up to %d variants each)"
          % (os.path.relpath(png_path, ROOT), atlas.size[0], atlas.size[1], rows, cols))
    for k in sorted(chosen.keys()):
        print("  %s  %d variant(s)" % (k, len(chosen[k])))
    return 0


if __name__ == "__main__":
    sys.exit(main())
