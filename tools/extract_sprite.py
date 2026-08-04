#!/usr/bin/env python3
"""Turn a hand-picked reference PNG into a game-resolution sprite.

The founder supplies art as large, soft-edged renders — a building drawn at
1500px with anti-aliased edges. The game draws it at 16px-tile scale. Naively
resizing leaves a blurry smear that reads as "AI art shrunk down"; the fix is
the same one the ground tileset uses: resize, then snap to a tight palette so
edges become pixels again, and hard-threshold alpha so there is no semi-
transparent fringe glowing against the grass.

Usage:
  .venv/bin/python tools/extract_sprite.py SOURCE.png --width 96 --out NAME.png
  .venv/bin/python tools/extract_sprite.py SOURCE.png --crop 0,0,1536,755 ...
"""

import argparse
import os
import sys
from collections import deque

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SPRITES = os.path.join(ROOT, "game", "assets", "sprites")


def drop_background(im, tolerance=40):
    """Flood-fill the border colour to alpha.

    Only for references that arrive on a solid backdrop. Filling from the border
    rather than testing every pixel means a white window frame inside the house
    survives a white background.
    """
    im = im.convert("RGBA")
    px = im.load()
    w, h = im.size
    bg = px[0, 0]
    if bg[3] == 0:
        return im  # already cut out

    def close(c):
        return c[3] > 0 and sum(abs(a - b) for a, b in zip(c[:3], bg[:3])) < tolerance

    seen = [[False] * w for _ in range(h)]
    queue = deque((x, y) for x in range(w) for y in (0, h - 1))
    queue.extend((x, y) for y in range(h) for x in (0, w - 1))
    while queue:
        x, y = queue.popleft()
        if x < 0 or y < 0 or x >= w or y >= h or seen[y][x]:
            continue
        seen[y][x] = True
        if not close(px[x, y]):
            continue
        px[x, y] = (0, 0, 0, 0)
        queue.extend(((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)))
    return im


def crispen(im, colors):
    """Palette-snap the colour and hard-threshold the alpha."""
    alpha = im.getchannel("A").point(lambda a: 255 if a > 128 else 0)
    flat = Image.new("RGBA", im.size, (0, 0, 0, 0))
    flat.paste(im, (0, 0))
    rgb = flat.convert("RGB")
    q = rgb.quantize(colors=colors, method=Image.MEDIANCUT, dither=Image.NONE).convert("RGB")
    q.putalpha(alpha)
    return q


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("source")
    ap.add_argument("--crop", help="left,top,right,bottom in source pixels")
    ap.add_argument("--width", type=int, help="target width; height follows the aspect")
    ap.add_argument("--height", type=int, help="target height; width follows the aspect")
    ap.add_argument("--colors", type=int, default=32)
    ap.add_argument("--out", required=True, help="filename under game/assets/sprites")
    args = ap.parse_args()

    im = Image.open(args.source).convert("RGBA")
    if args.crop:
        im = im.crop(tuple(int(v) for v in args.crop.split(",")))
    im = drop_background(im)
    # Renders carry a halo of alpha-1..15 pixels far outside the subject. Left
    # in, they win the bounding box and the sprite ends up padded with nothing.
    im.putalpha(im.getchannel("A").point(lambda a: a if a > 16 else 0))
    box = im.getbbox()
    if box is None:
        raise SystemExit("nothing left after background removal")
    im = im.crop(box)
    print("content %dx%d (aspect %.2f)" % (im.width, im.height, im.width / im.height))

    if args.width and args.height:
        size = (args.width, args.height)
    elif args.width:
        size = (args.width, max(1, round(args.width * im.height / im.width)))
    elif args.height:
        size = (max(1, round(args.height * im.width / im.height)), args.height)
    else:
        raise SystemExit("give --width or --height")

    out = crispen(im.resize(size, Image.LANCZOS), args.colors)
    dest = args.out if os.path.isabs(args.out) else os.path.join(SPRITES, args.out)
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    out.save(dest)
    print("wrote %s  %dx%d" % (os.path.relpath(dest, ROOT), out.width, out.height))
    return 0


if __name__ == "__main__":
    sys.exit(main())
