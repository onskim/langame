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


def blobs(mask, w, h, min_size):
    """Connected components, so one plant is one sprite and not four leaves."""
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
            if len(cells) >= min_size:
                found.append(cells)
    return found


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("source")
    ap.add_argument("--crop", required=True, help="left,top,right,bottom in SOURCE pixels")
    ap.add_argument("--scale", type=int, default=4, help="upscale factor of the source")
    ap.add_argument("--min-size", type=int, default=6, help="smallest blob kept, in native px")
    ap.add_argument("--stages", type=int, default=6, help="how many growth stages to keep")
    ap.add_argument("--colors", type=int, default=16)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    im = Image.open(args.source).convert("RGB")
    im = im.crop(tuple(int(v) for v in args.crop.split(",")))
    w, h = im.size
    im = im.resize((w // args.scale, h // args.scale), Image.BOX)
    w, h = im.size
    px = im.load()

    mask = [[is_leaf(px[x, y]) for x in range(w)] for y in range(h)]
    plants = blobs(mask, w, h, args.min_size)
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
