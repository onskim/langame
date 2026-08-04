#!/usr/bin/env python3
"""Cut the individual plants out of a farmland reference into a growth strip.

The founder's farmland sheet shows planted plots at several stages — bare seed
dimples, two-leaf sprouts, leafy seedlings, full bushes. Those are the frames a
crop needs as it grows, but they arrive embedded in soil, dozens to a plot.

This finds each plant as a connected blob of green sitting on brown, crops a
fixed cell around it, drops the soil to alpha, and sorts the result by leaf area
— which for this sheet is the same ordering as growth stage. Output is a strip of
equal cells, so the engine can treat stage as a frame index.

Nothing consumes this yet: crops do not grow in the game today. It is extracted
now because the reference exists now, and re-deriving it later by eye is worse.

Usage:
  .venv/bin/python tools/extract_crop_stages.py SOURCE.png --crop L,T,R,B --out NAME.png
"""

import argparse
import os
import sys
from collections import deque

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SPRITES = os.path.join(ROOT, "game", "assets", "sprites")
CELL = 16


def is_leaf(rgb):
    """Plant green, distinct from the yellow-green of surrounding turf."""
    r, g, b = rgb[:3]
    return g > r + 18 and g > 85 and b < g


def blobs(mask, w, h, min_size, max_size=10 ** 9):
    """Connected components, so one plant is one sprite and not four leaves.

    `max_size` is what makes this work on the founder's sheet without knowing
    where the plots are. The grass borders between plots are green too, and they
    touch every plant they surround, so a plain flood fill returns a handful of
    enormous blobs. A plant is a few pixels; a border is hundreds. Discarding
    anything too big to be a plant separates them with no geometry at all —
    which is what two rounds of guessing plot rectangles failed to do.
    """
    seen = [[False] * w for _ in range(h)]
    found = []
    for sy in range(h):
        for sx in range(w):
            if seen[sy][sx] or not mask[sy][sx]:
                continue
            queue = deque([(sx, sy)])
            seen[sy][sx] = True
            cells = []
            while queue:
                x, y = queue.popleft()
                cells.append((x, y))
                for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                    if 0 <= nx < w and 0 <= ny < h and not seen[ny][nx] and mask[ny][nx]:
                        seen[ny][nx] = True
                        queue.append((nx, ny))
            if min_size <= len(cells) <= max_size:
                found.append(cells)
    return found


def find_plots(im, scale, min_leaf=4, gap=8):
    """Locate the planted plots by leaf DENSITY rather than by eye.

    The first attempt at this guessed plot rectangles off a screenshot and got
    them wrong: two of three windows contained no plants at all. The reference's
    plots are separated by grass borders, and grass is green too — so the
    borders connect every plant in the sheet into one blob and blur the plots
    together.

    The fix is to look for leaf-on-SOIL: green pixels whose neighbourhood is
    mostly brown. That signature exists inside a plot and nowhere along a grass
    border, so the column and row profiles it produces have clean gaps exactly
    where the borders are.
    """
    w, h = im.size
    px = im.load()

    def leaf_on_soil(x, y):
        if not is_leaf(px[x, y]):
            return False
        soil = 0
        seen = 0
        for dy in range(-3, 4):
            for dx in range(-3, 4):
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h:
                    seen += 1
                    r, g, b = px[nx, ny][:3]
                    if r > g + 12 and r > 60 and b < r - 25:
                        soil += 1
        return seen > 0 and soil * 2 > seen

    mask = [[leaf_on_soil(x, y) for x in range(w)] for y in range(h)]
    cols = [sum(1 for y in range(h) if mask[y][x]) for x in range(w)]
    rows = [sum(1 for x in range(w) if mask[y][x]) for y in range(h)]

    def spans(profile, floor_value):
        found = []
        start = None
        quiet = 0
        for i, value in enumerate(profile):
            if value >= floor_value:
                if start is None:
                    start = i
                quiet = 0
            elif start is not None:
                quiet += 1
                if quiet >= gap:
                    found.append((start, i - quiet))
                    start = None
        if start is not None:
            found.append((start, len(profile)))
        return [(a, b) for a, b in found if b - a >= 16]

    boxes = []
    for x0, x1 in spans(cols, min_leaf):
        for y0, y1 in spans(rows, min_leaf):
            inside = sum(1 for y in range(y0, y1) for x in range(x0, x1) if mask[y][x])
            if inside >= min_leaf * 8:
                boxes.append((x0, y0, x1, y1))
    return boxes


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("source")
    ap.add_argument("--crop", help="left,top,right,bottom in SOURCE pixels")
    ap.add_argument("--auto-plots", action="store_true",
                    help="find the planted plots by leaf-on-soil density")
    ap.add_argument("--scale", type=int, default=4, help="upscale factor of the source")
    ap.add_argument("--min-size", type=int, default=6, help="smallest blob kept, in native px")
    ap.add_argument("--max-size", type=int, default=60,
                    help="largest blob still small enough to be a plant, not a grass border")
    ap.add_argument("--stages", type=int, default=6, help="how many growth stages to keep")
    ap.add_argument("--colors", type=int, default=16)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    im = Image.open(args.source).convert("RGB")
    if args.crop:
        im = im.crop(tuple(int(v) for v in args.crop.split(",")))
    w, h = im.size
    im = im.resize((w // args.scale, h // args.scale), Image.BOX)
    w, h = im.size
    px = im.load()

    if args.auto_plots:
        boxes = find_plots(im, args.scale)
        print("found %d planted plot(s): %s" % (len(boxes), boxes))
        if not boxes:
            raise SystemExit("no planted plots found — check --crop")
        # Search only INSIDE the plots. Outside them the grass border joins
        # every plant into one blob, which is what wrecked the first attempt.
        mask = [[False] * w for _ in range(h)]
        for x0, y0, x1, y1 in boxes:
            for y in range(y0, y1):
                for x in range(x0, x1):
                    mask[y][x] = is_leaf(px[x, y])
    else:
        mask = [[is_leaf(px[x, y]) for x in range(w)] for y in range(h)]

    plants = blobs(mask, w, h, args.min_size, args.max_size)
    if not plants:
        raise SystemExit("no plants found in that crop")
    print("found %d plants in a %dx%d native grid" % (len(plants), w, h))

    # Bucket by leaf area, then take the median plant of each bucket: an average
    # example of a stage beats the largest, which is usually two plants touching.
    plants.sort(key=len)
    step = max(1, len(plants) // args.stages)
    chosen = [plants[min(len(plants) - 1, int((i + 0.5) * step))]
              for i in range(args.stages)]

    strip = Image.new("RGBA", (CELL * len(chosen), CELL), (0, 0, 0, 0))
    for index, cells in enumerate(chosen):
        cx = sum(c[0] for c in cells) / len(cells)
        cy = sum(c[1] for c in cells) / len(cells)
        left = max(0, min(w - CELL, int(round(cx)) - CELL // 2))
        top = max(0, min(h - CELL, int(round(cy)) - CELL // 2))
        cell = im.crop((left, top, left + CELL, top + CELL)).convert("RGBA")
        cp = cell.load()
        for y in range(CELL):
            for x in range(CELL):
                if not is_leaf(cp[x, y]):
                    cp[x, y] = (0, 0, 0, 0)
        strip.paste(cell, (index * CELL, 0), cell)
        print("  stage %d: %d leaf px" % (index, len(cells)))

    alpha = strip.getchannel("A").point(lambda a: 255 if a > 128 else 0)
    out = strip.convert("RGB").quantize(
        colors=args.colors, method=Image.MEDIANCUT, dither=Image.NONE).convert("RGB")
    out.putalpha(alpha)

    dest = args.out if os.path.isabs(args.out) else os.path.join(SPRITES, args.out)
    out.save(dest)
    print("wrote %s  %dx%d (%d stages of %dpx)"
          % (os.path.relpath(dest, ROOT), out.width, out.height, len(chosen), CELL))
    return 0


if __name__ == "__main__":
    sys.exit(main())
