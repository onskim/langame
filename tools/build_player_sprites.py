#!/usr/bin/env python3
"""Generate the player character and its four-direction walk cycle via PixelLab.

Pipeline:

  1. POST /create-character-with-4-directions, passing the founder's own drawing
     as the reference for EACH direction. Provided directions are used rather
     than invented, which is the difference between "his character" and "a
     character like his".
  2. Poll until the rotations exist.
  3. POST /animate-character in template mode with the `walk` skeleton, all four
     directions. Template mode reuses the character's own rotations as the pose
     source, so the walk cannot drift into a different-looking person.
  4. Poll, download every frame, and assemble the engine's sheet.

The engine's sheet layout is fixed by `player.gd` and must not change here:
4 columns (walk frames) x 4 rows, rows ordered DOWN, UP, LEFT, RIGHT, cells
16x32 (Part 11 §2). A masters copy is kept at generation resolution so the sheet
can be rebuilt at a different size without paying for generation again.

Usage:
  .venv/bin/python tools/build_player_sprites.py --refs DIR [--size 32x64]
  .venv/bin/python tools/build_player_sprites.py --character-id ID --assemble-only
"""

import argparse
import base64
import io
import json
import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pixellab  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MASTERS = os.path.join(ROOT, "art", "player")
SHEET = os.path.join(ROOT, "game", "assets", "sprites", "player.png")

# PixelLab direction names in the row order `player.gd` indexes with
# `facing * 4 + frame`, where Facing is DOWN, UP, LEFT, RIGHT.
ROW_DIRECTIONS = ["south", "north", "west", "east"]

DESCRIPTION = (
    "young farmhand boy, messy spiky brown hair, large expressive eyes, "
    "cream linen shirt with rolled sleeves, brown leather suspenders, "
    "dark blue denim trousers with cuffed hems, brown leather boots, "
    "cosy farming RPG character"
)


def as_base64(path):
    with open(path, "rb") as f:
        return {"type": "base64",
                "base64": "data:image/png;base64," + base64.b64encode(f.read()).decode(),
                "format": "png"}


def decode(payload):
    """PixelLab returns images as data URLs or plain base64."""
    if isinstance(payload, dict):
        payload = payload.get("base64") or payload.get("image") or ""
    if isinstance(payload, str) and payload.startswith("http"):
        raise ValueError("expected inline image, got a URL")
    text = str(payload)
    if "," in text[:64]:
        text = text.split(",", 1)[1]
    return Image.open(io.BytesIO(base64.b64decode(text))).convert("RGBA")


def create_character(ref_dir, width, height):
    directions = {}
    for name in ROW_DIRECTIONS:
        path = os.path.join(ref_dir, name + ".png")
        if not os.path.exists(path):
            raise SystemExit("missing reference %s" % path)
        directions[name] = as_base64(path)

    body = {
        "description": DESCRIPTION,
        "image_size": {"width": width, "height": height},
        "directions": directions,
        # The reference is drawn straight-on in the Stardew idiom, not tilted
        # down. Matching that keeps the generated rotations consistent with the
        # art the founder actually approved.
        "view": "side",
        "outline": "single color black outline",
        "shading": "medium shading",
        "detail": "medium detail",
        "text_guidance_scale": 6.0,
        "proportions": {"type": "preset", "name": "cartoon"},
        "seed": 20260804,
    }
    print("creating character %dx%d from %s" % (width, height, ref_dir))
    response = pixellab.call("POST", "/create-character-with-4-directions", body)
    print(json.dumps(response, indent=1)[:600])
    return response["character_id"]


def animate_walk(character_id):
    body = {
        "character_id": character_id,
        "animation_name": "walk",
        "mode": "template",
        "template_animation_id": "walk",
        "directions": ROW_DIRECTIONS,
    }
    print("animating walk in %s" % ", ".join(ROW_DIRECTIONS))
    response = pixellab.call("POST", "/animate-character", body)
    print(json.dumps(response, indent=1)[:800])
    return response


def fetch_frames(character_id):
    """Every walk frame, per direction, at generation resolution."""
    detail = pixellab.call("GET", "/characters/%s" % character_id)
    os.makedirs(MASTERS, exist_ok=True)
    with open(os.path.join(MASTERS, "character.json"), "w", encoding="utf-8") as f:
        json.dump(detail, f, indent=1)

    frames = {}
    for animation in detail.get("animations", []):
        name = str(animation.get("name", "")).lower()
        if "walk" not in name:
            continue
        for direction, urls in (animation.get("frames") or {}).items():
            got = []
            for index, url in enumerate(urls):
                dest = os.path.join(MASTERS, "walk_%s_%d.png" % (direction, index))
                pixellab.download(url, dest)
                got.append(Image.open(dest).convert("RGBA"))
            frames[direction] = got
    return detail, frames


def trim_uniform(images):
    """Crop every frame by ONE shared box.

    Cropping each frame to its own content is the classic way to make a walk
    cycle jitter: the sprite would shift by however much the arms happened to
    swing. One box for the whole set keeps the body still and lets the limbs
    move.
    """
    box = None
    for image in images:
        bbox = image.getbbox()
        if bbox is None:
            continue
        box = bbox if box is None else (min(box[0], bbox[0]), min(box[1], bbox[1]),
                                        max(box[2], bbox[2]), max(box[3], bbox[3]))
    return [image.crop(box) for image in images], box


def build_sheet(frames, cell_w, cell_h, dest):
    ordered = []
    for direction in ROW_DIRECTIONS:
        row = frames.get(direction) or []
        if not row:
            raise SystemExit("no frames for direction %s" % direction)
        # The engine plays exactly 4 frames per direction.
        step = max(1, len(row) // 4)
        ordered.append([row[(i * step) % len(row)] for i in range(4)])

    flat = [image for row in ordered for image in row]
    flat, box = trim_uniform(flat)
    print("shared crop box %s" % (box,))

    scale = min(cell_w / float(flat[0].width), cell_h / float(flat[0].height))
    new_w = max(1, int(round(flat[0].width * scale)))
    new_h = max(1, int(round(flat[0].height * scale)))

    sheet = Image.new("RGBA", (cell_w * 4, cell_h * 4), (0, 0, 0, 0))
    for index, image in enumerate(flat):
        small = image.resize((new_w, new_h), Image.LANCZOS)
        row, col = divmod(index, 4)
        # Feet on the bottom edge of the cell: the engine anchors the collision
        # shape there.
        sheet.paste(small,
                    (col * cell_w + (cell_w - new_w) // 2,
                     row * cell_h + (cell_h - new_h)),
                    small)

    os.makedirs(os.path.dirname(dest), exist_ok=True)
    sheet.save(dest)
    print("wrote %s (%dx%d, cells %dx%d)"
          % (os.path.relpath(dest, ROOT), sheet.width, sheet.height, cell_w, cell_h))
    return sheet


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--refs", help="directory of south/north/east/west reference PNGs")
    ap.add_argument("--size", default="32x64", help="generation size WxH")
    ap.add_argument("--cell", default="16x32", help="engine sheet cell size WxH")
    ap.add_argument("--character-id")
    ap.add_argument("--assemble-only", action="store_true")
    ap.add_argument("--dest", default=SHEET)
    args = ap.parse_args()

    width, height = (int(v) for v in args.size.lower().split("x"))
    cell_w, cell_h = (int(v) for v in args.cell.lower().split("x"))

    character_id = args.character_id
    if not args.assemble_only:
        if not character_id:
            if not args.refs:
                raise SystemExit("--refs is required to create a character")
            character_id = create_character(args.refs, width, height)
            pixellab.wait_for(lambda: pixellab.character_ready(character_id),
                              "rotations for %s" % character_id)
            print("rotations ready: %s" % character_id)
        animate_walk(character_id)
        pixellab.wait_for(
            lambda: _walk_ready(character_id), "walk frames for %s" % character_id)

    detail, frames = fetch_frames(character_id)
    print("character %s: %s" % (character_id,
                                {k: len(v) for k, v in frames.items()}))
    build_sheet(frames, cell_w, cell_h, args.dest)
    return 0


def _walk_ready(character_id):
    detail = pixellab.call("GET", "/characters/%s" % character_id)
    for animation in detail.get("animations", []):
        if "walk" not in str(animation.get("name", "")).lower():
            continue
        frames = animation.get("frames") or {}
        if all(frames.get(d) for d in ROW_DIRECTIONS):
            return detail
    return None


if __name__ == "__main__":
    sys.exit(main())
