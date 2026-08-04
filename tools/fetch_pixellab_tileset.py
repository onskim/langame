#!/usr/bin/env python3
"""Fetch a completed PixelLab Wang tileset into game/assets/tilesets/.

PixelLab's create_topdown_tileset returns a 4x4 sheet of 16 corner-based Wang
tiles. The sheet alone is not enough to autotile: Godot's terrain system needs
to know, per tile, which of its four CORNERS is the upper terrain and which is
the lower. That mapping lives in the job metadata, so we write it beside the
PNG as a sidecar rather than re-deriving it (or worse, eyeballing it) later.

Sheet position is the tile's ARRAY INDEX -- col = i % 4, row = i // 4. It is
NOT `original_position` (the generation grid, whose rows exceed the sheet) and
NOT the `wang_N` name. Using either of those is what produces banded atlases.

Usage:
    python tools/fetch_pixellab_tileset.py <tileset_id> <output_name>

Writes:
    game/assets/tilesets/<output_name>.png         64x64, 4x4 of 16px tiles
    game/assets/tilesets/<output_name>.tiles.json  corner map + provenance
"""

import json
import os
import sys
import urllib.request

API = "https://api.pixellab.ai/mcp/tilesets"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "game", "assets", "tilesets")


def _get(url: str) -> bytes:
    with urllib.request.urlopen(url, timeout=60) as r:
        return r.read()


def fetch(tileset_id: str, name: str) -> None:
    meta = json.loads(_get(f"{API}/{tileset_id}/metadata"))

    layout = meta["layout"]
    if layout["tile_count"] != 16 or layout["grid_size"] != {"width": 4, "height": 4}:
        raise SystemExit(
            f"{name}: expected a 16-tile 4x4 sheet, got {layout}. "
            "Transition sheets repeat and omit tiles -- the index shortcut "
            "below would silently mis-slice them."
        )

    tile_px = meta["tile_size"]["width"]
    if tile_px != 16:
        raise SystemExit(f"{name}: tile size {tile_px}px, GDD Part 11 §2 pins 16px.")

    os.makedirs(OUT_DIR, exist_ok=True)
    png_path = os.path.join(OUT_DIR, f"{name}.png")
    with open(png_path, "wb") as f:
        f.write(_get(f"{API}/{tileset_id}/image?inline=true"))

    tiles = meta["tileset_data"]["tiles"]
    sidecar = {
        "source": "pixellab",
        "tileset_id": tileset_id,
        "lower": meta["lower_description"],
        "upper": meta["upper_description"],
        "transition": meta.get("transition_description"),
        "transition_size": meta.get("transition_size"),
        "tile_size": tile_px,
        "grid": {"cols": 4, "rows": 4},
        "base_tile_ids": meta["base_tile_ids"],
        # atlas_coords -> which terrain sits in each corner. Godot's
        # TileSet terrain peering bits map 1:1 onto these four keys.
        "tiles": [
            {
                "atlas_coords": [i % 4, i // 4],
                "wang": t["name"],
                "corners": t["corners"],
            }
            for i, t in enumerate(tiles)
        ],
    }
    json_path = os.path.join(OUT_DIR, f"{name}.tiles.json")
    with open(json_path, "w") as f:
        json.dump(sidecar, f, indent=2)
        f.write("\n")

    combos = {
        "".join(t["corners"][k][0] for k in ("NW", "NE", "SW", "SE")) for t in tiles
    }
    if len(combos) != 16:
        raise SystemExit(f"{name}: {len(combos)}/16 distinct corner combos -- sheet is incomplete.")

    print(f"{name}: {png_path} + sidecar, 16/16 corner combos")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    fetch(sys.argv[1], sys.argv[2])
