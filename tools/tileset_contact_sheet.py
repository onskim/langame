#!/usr/bin/env python3
"""Paint a demo map from every PixelLab Wang tileset and stack them into one sheet.

Two jobs, both from Style Bible §6.3 (weekly consistency review):

1. CORRECTNESS. A 4x4 atlas that looks fine as a grid can still fail to
   autotile. This paints a real blob of upper terrain over lower using the
   sidecar corner table, so a mis-sliced sheet shows up as visible seams
   instead of surviving to the first Godot session.
2. CONSISTENCY. Stacking every set in one image is the squint test -- the
   grass in the path set and the grass in the pond set have to be the SAME
   grass, or the chaining silently drifted.

Usage: python tools/tileset_contact_sheet.py [output.png]
"""

import glob
import json
import os
import sys

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TILESETS = os.path.join(ROOT, "game", "assets", "tilesets")
DEFAULT_OUT = os.path.join(ROOT, "docs", "tileset-contact-sheet.png")

CELLS_W, CELLS_H = 14, 9
SCALE = 4
PAD = 8


def demo_vertices(w: int, h: int) -> list[list[int]]:
    """A deterministic blob of upper terrain: exercises every corner case.

    Two overlapping shapes plus a lone single-vertex dot. The dot matters --
    an isolated vertex forces the four "one corner only" tiles, which are the
    ones a bad slice most often gets wrong.
    """
    v = [[0] * (w + 1) for _ in range(h + 1)]
    for y in range(1, 6):
        for x in range(1, 7):
            v[y][x] = 1
    for y in range(4, 9):
        for x in range(5, 12):
            v[y][x] = 1
    v[2][10] = 1
    return v


def paint(sheet: Image.Image, tiles: list[dict], tile_px: int) -> Image.Image:
    by_corners = {
        "".join(t["corners"][k][0] for k in ("NW", "NE", "SW", "SE")): t["atlas_coords"]
        for t in tiles
    }
    v = demo_vertices(CELLS_W, CELLS_H)
    out = Image.new("RGBA", (CELLS_W * tile_px, CELLS_H * tile_px))
    for cy in range(CELLS_H):
        for cx in range(CELLS_W):
            sig = "".join(
                "ul"[v[cy + dy][cx + dx]]
                for dy, dx in ((0, 0), (0, 1), (1, 0), (1, 1))
            )
            col, row = by_corners[sig]
            src = sheet.crop(
                (col * tile_px, row * tile_px, (col + 1) * tile_px, (row + 1) * tile_px)
            )
            out.paste(src, (cx * tile_px, cy * tile_px))
    return out


def main(out_path: str) -> None:
    rows = []
    for json_path in sorted(glob.glob(os.path.join(TILESETS, "*.tiles.json"))):
        name = os.path.basename(json_path)[: -len(".tiles.json")]
        meta = json.load(open(json_path))
        tile_px = meta["tile_size"]
        sheet = Image.open(os.path.join(TILESETS, f"{name}.png")).convert("RGBA")

        atlas = sheet.resize(
            (sheet.width * SCALE, sheet.height * SCALE), Image.Resampling.NEAREST
        )
        demo = paint(sheet, meta["tiles"], tile_px)
        demo = demo.resize(
            (demo.width * SCALE, demo.height * SCALE), Image.Resampling.NEAREST
        )
        rows.append((name, meta, atlas, demo))

    label_h = 18
    row_h = max(max(a.height, d.height) for _, _, a, d in rows) + label_h + PAD
    width = max(a.width + d.width + PAD * 3 for _, _, a, d in rows)
    canvas = Image.new("RGBA", (width, row_h * len(rows) + PAD), (24, 20, 18, 255))
    draw = ImageDraw.Draw(canvas)

    y = PAD
    for name, meta, atlas, demo in rows:
        draw.text((PAD, y), f"{name}   {meta['lower']}  ->  {meta['upper']}"[:150],
                  fill=(235, 225, 200, 255))
        canvas.paste(atlas, (PAD, y + label_h), atlas)
        canvas.paste(demo, (PAD * 2 + atlas.width, y + label_h), demo)
        y += row_h

    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    canvas.save(out_path)
    print(f"{len(rows)} tilesets -> {out_path} ({canvas.width}x{canvas.height})")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else DEFAULT_OUT)
