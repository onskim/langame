#!/usr/bin/env python3
"""Turn a founder-supplied 4-view character sheet into per-direction references.

The founder supplied one image containing the same character drawn four times:
front, right profile, back, left profile. PixelLab's character endpoint accepts a
reference image PER DIRECTION and uses it instead of inventing that rotation, so
feeding it these four is what keeps the generated sprite recognisably HIS
character rather than a lookalike.

The work here is unglamorous but load-bearing:

  1. split the sheet on columns of pure background
  2. flood-fill the background to alpha from the border only, so the character's
     own near-black outline survives
  3. crop every panel against a SHARED baseline and scale, so the four rotations
     line up foot-to-foot — otherwise the sprite bobs when the player turns
  4. downsample to the target canvas and quantise to a tight palette

Usage:
  .venv/bin/python tools/prepare_character_refs.py SHEET.png --height 64 --out DIR
"""

import argparse
import os
import sys
from collections import deque

from PIL import Image

# The founder's sheet reads left-to-right as front, right profile, back, left
# profile. PixelLab names directions by where the character is HEADED, and the
# engine's Facing enum agrees: south is toward the camera.
PANEL_DIRECTIONS = ["south", "east", "north", "west"]


def background_alpha(im, tolerance=44):
    """Background to transparent, by flood fill from the border.

    A plain colour-distance test would also eat the character's outline, which is
    nearly as dark as the backdrop. Filling from the border only removes pixels
    actually connected to the outside.
    """
    im = im.convert("RGBA")
    px = im.load()
    w, h = im.size
    bg = px[0, 0][:3]

    def close(c):
        return sum(abs(a - b) for a, b in zip(c[:3], bg)) < tolerance

    seen = [[False] * w for _ in range(h)]
    queue = deque()
    for x in range(w):
        for y in (0, h - 1):
            queue.append((x, y))
    for y in range(h):
        for x in (0, w - 1):
            queue.append((x, y))

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


def split_panels(im, min_width=30):
    """Columns that are entirely background separate one view from the next."""
    px = im.convert("RGB").load()
    w, h = im.size
    bg = px[0, 0]

    def is_bg(c):
        return sum(abs(a - b) for a, b in zip(c, bg)) < 44

    empty = []
    for x in range(w):
        empty.append(all(is_bg(px[x, y]) for y in range(0, h, 3)))

    spans = []
    start = None
    for x in range(w):
        if not empty[x] and start is None:
            start = x
        elif empty[x] and start is not None:
            if x - start >= min_width:
                spans.append((start, x))
            start = None
    if start is not None:
        spans.append((start, w))

    rows = []
    for y in range(h):
        rows.append(all(is_bg(px[x, y]) for x in range(0, w, 3)))
    used = [y for y in range(h) if not rows[y]]
    # One vertical crop for every panel: a shared baseline is what stops the
    # character sinking or growing as the player turns.
    return spans, (used[0], used[-1] + 1)


def fit(panel, box_w, box_h):
    """Scale to the box height, centre horizontally, keep feet on the floor."""
    bbox = panel.getbbox()
    panel = panel.crop(bbox)
    w, h = panel.size
    scale = box_h / float(h)
    new_w = max(1, int(round(w * scale)))
    small = panel.resize((new_w, box_h), Image.LANCZOS)
    if new_w > box_w:
        small = small.crop(((new_w - box_w) // 2, 0, (new_w - box_w) // 2 + box_w, box_h))
        new_w = box_w
    out = Image.new("RGBA", (box_w, box_h), (0, 0, 0, 0))
    out.paste(small, ((box_w - new_w) // 2, 0))
    return out


def crispen(im, colors):
    """Downsampling leaves soft edges; a tight palette snaps them back to pixels."""
    rgb = im.convert("RGB")
    alpha = im.getchannel("A").point(lambda a: 255 if a > 110 else 0)
    q = rgb.quantize(colors=colors, method=Image.MEDIANCUT, dither=Image.NONE).convert("RGB")
    q.putalpha(alpha)
    return q


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("sheet")
    ap.add_argument("--height", type=int, default=64, help="target canvas height")
    ap.add_argument("--width", type=int, default=0, help="target canvas width (default height/2)")
    ap.add_argument("--colors", type=int, default=24)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    box_h = args.height
    box_w = args.width or args.height // 2

    src = Image.open(args.sheet).convert("RGB")
    spans, (top, bottom) = split_panels(src)
    if len(spans) != len(PANEL_DIRECTIONS):
        print("expected %d views, found %d: %s"
              % (len(PANEL_DIRECTIONS), len(spans), spans), file=sys.stderr)
        return 2

    os.makedirs(args.out, exist_ok=True)
    for direction, (left, right) in zip(PANEL_DIRECTIONS, spans):
        panel = background_alpha(src.crop((left, top, right, bottom)))
        out = crispen(fit(panel, box_w, box_h), args.colors)
        path = os.path.join(args.out, "%s.png" % direction)
        out.save(path)
        print("%-6s %s  %dx%d" % (direction, path, out.size[0], out.size[1]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
