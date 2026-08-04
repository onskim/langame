#!/usr/bin/env python3
"""Turn a PixelLab character export folder into the engine's sprite sheet.

The export is one PNG per rotation, each holding that direction's walk frames
side by side, plus a `metadata.json` naming them. The engine wants one sheet:
4 columns (frames) x 4 rows (directions), rows ordered DOWN, UP, LEFT, RIGHT to
match `Facing` in player.gd, cells of the pinned world-sprite size (Part 11 §2).

The eight-direction export is deliberately reduced to four: the engine's input
and its facing logic are four-way, and shipping diagonals nothing reads is how a
sprite sheet quietly doubles in size for no visible gain.

The one thing this must get right is that every frame is cropped by the SAME
box. Cropping each frame to its own content is the classic way to make a walk
cycle jitter — the sprite would shift by however far the arms happened to swing.

Usage:
  .venv/bin/python tools/import_character_export.py ~/Downloads/MC-walking \
      --out player.png [--cell 16x32] [--frames 4]
"""

import argparse
import json
import os
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SPRITES = os.path.join(ROOT, "game", "assets", "sprites")

# Row order is fixed by `player.gd`, which indexes `facing * 4 + frame` with
# Facing = DOWN, UP, LEFT, RIGHT.
ROW_DIRECTIONS = ["south", "north", "west", "east"]


def load_rotations(folder):
    meta_path = os.path.join(folder, "metadata.json")
    if not os.path.exists(meta_path):
        raise SystemExit("no metadata.json in %s" % folder)
    with open(meta_path, encoding="utf-8") as f:
        meta = json.load(f)
    states = meta.get("states") or []
    if not states:
        raise SystemExit("metadata.json lists no states")
    rotations = ((states[0].get("frames") or {}).get("rotations") or {})
    if not rotations:
        raise SystemExit("metadata.json lists no rotations")
    return {d: os.path.join(folder, p) for d, p in rotations.items()}


def parse_rotation_spec(spec):
    """`DIR=SOURCE:f0,f1,f2,f3`, each frame optionally prefixed `~` to mirror.

    A generated export is not guaranteed to be usable as shipped. This one's
    `south` is not a walk cycle at all — it is the four VIEWS of the character
    (front, right profile, back, left profile), the reference sheet reproduced —
    and its `east` has a back-of-the-head frame sitting in the middle of the
    cycle. Rather than hand-editing PNGs, the repair is stated on the command
    line and lives in the devlog, so rebuilding the sheet reproduces it exactly.
    """
    if "=" not in spec or ":" not in spec:
        raise SystemExit("bad --rotation %r, want DIR=SOURCE:f0,f1,f2,f3" % spec)
    direction, rest = spec.split("=", 1)
    source, frame_list = rest.rsplit(":", 1)
    frames = []
    for token in frame_list.split(","):
        token = token.strip()
        mirrored = token.startswith("~")
        frames.append((int(token.lstrip("~")), mirrored))
    return direction.strip(), source.strip(), frames


def split_frames(image, count):
    """A rotation PNG is `count` frames laid out left to right."""
    width = image.width // count
    return [image.crop((i * width, 0, (i + 1) * width, image.height))
            for i in range(count)]


def shared_box(frames):
    """One bounding box for every frame, so the body holds still as legs move."""
    box = None
    for frame in frames:
        bbox = frame.getbbox()
        if bbox is None:
            continue
        box = bbox if box is None else (
            min(box[0], bbox[0]), min(box[1], bbox[1]),
            max(box[2], bbox[2]), max(box[3], bbox[3]))
    if box is None:
        raise SystemExit("every frame is empty")
    return box


def crispen(image, colors):
    """Downscaling softens edges; a tight palette snaps them back to pixels."""
    alpha = image.getchannel("A").point(lambda a: 255 if a > 110 else 0)
    flat = Image.new("RGBA", image.size, (0, 0, 0, 0))
    flat.paste(image, (0, 0))
    q = flat.convert("RGB").quantize(
        colors=colors, method=Image.MEDIANCUT, dither=Image.NONE).convert("RGB")
    q.putalpha(alpha)
    return q


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("folder")
    ap.add_argument("--frames", type=int, default=4, help="frames per rotation")
    ap.add_argument("--cell", default="16x32", help="engine cell size WxH")
    ap.add_argument("--colors", type=int, default=24)
    ap.add_argument("--rotation", action="append", default=[],
                    help="DIR=SOURCE:f0,f1,f2,f3 (prefix a frame with ~ to mirror); "
                         "repeatable, overrides the same-named rotation")
    ap.add_argument("--out", default="player.png")
    args = ap.parse_args()

    cell_w, cell_h = (int(v) for v in args.cell.lower().split("x"))
    paths = load_rotations(args.folder)

    overrides = {}
    for spec in args.rotation:
        direction, source, picks = parse_rotation_spec(spec)
        overrides[direction] = (source, picks)

    cache = {}

    def source_frames(name):
        if name not in cache:
            if name not in paths:
                raise SystemExit("export has no rotation %r" % name)
            cache[name] = split_frames(
                Image.open(paths[name]).convert("RGBA"), args.frames)
        return cache[name]

    rows = []
    for direction in ROW_DIRECTIONS:
        if direction in overrides:
            source, picks = overrides[direction]
            available = source_frames(source)
            row = []
            for index, mirrored in picks:
                frame = available[index]
                row.append(frame.transpose(Image.FLIP_LEFT_RIGHT) if mirrored else frame)
            rows.append(row)
            print("%-6s <- %s frames %s" % (direction, source, ",".join(
                ("~" if m else "") + str(i) for i, m in picks)))
        else:
            if direction not in paths:
                raise SystemExit("export has no rotation for %s and no --rotation for it"
                                 % direction)
            rows.append(source_frames(direction))
            print("%-6s <- %s (as exported)" % (direction, direction))

    flat = [frame for row in rows for frame in row]
    box = shared_box(flat)
    print("shared crop box %s (%dx%d)" % (box, box[2] - box[0], box[3] - box[1]))
    flat = [frame.crop(box) for frame in flat]

    # Fit inside the cell without distorting: a stretched sprite is obvious the
    # moment it stands next to a square-tiled world.
    scale = min(cell_w / float(flat[0].width), cell_h / float(flat[0].height))
    new_w = max(1, int(round(flat[0].width * scale)))
    new_h = max(1, int(round(flat[0].height * scale)))

    sheet = Image.new("RGBA", (cell_w * args.frames, cell_h * len(rows)), (0, 0, 0, 0))
    for index, frame in enumerate(flat):
        small = crispen(frame.resize((new_w, new_h), Image.LANCZOS), args.colors)
        row, col = divmod(index, args.frames)
        # Feet on the bottom edge: the collision shape is anchored there.
        sheet.paste(small,
                    (col * cell_w + (cell_w - new_w) // 2,
                     row * cell_h + (cell_h - new_h)), small)

    dest = args.out if os.path.isabs(args.out) else os.path.join(SPRITES, args.out)
    sheet.save(dest)
    print("wrote %s  %dx%d (%d frames x %d directions, cells %dx%d, sprite %dx%d)"
          % (os.path.relpath(dest, ROOT), sheet.width, sheet.height,
             args.frames, len(rows), cell_w, cell_h, new_w, new_h))
    return 0


if __name__ == "__main__":
    sys.exit(main())
