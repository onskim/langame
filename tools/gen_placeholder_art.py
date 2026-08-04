#!/usr/bin/env python3
"""Generate PLACEHOLDER pixel art at the exact sizes pinned in GDD Part 11 §2.

This exists only because PixelLab MCP was unavailable in the Week 1 session.
Every asset it writes is gray-box scaffolding to be REPLACED by PixelLab output
once the style bible lands (Part 11 §2 workflow rule). Do not treat any of this
as art direction.

Pure stdlib — no Pillow dependency.
"""

import os
import struct
import zlib

ASSETS = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "game", "assets")

# Palette — placeholder only. Article-gender hues from Part 11 §2 are RESERVED
# and deliberately not used for scenery.
C = {
    "transparent": (0, 0, 0, 0),
    "grass_a": (106, 158, 78, 255),
    "grass_b": (94, 145, 70, 255),
    "grass_c": (118, 170, 88, 255),
    "path_a": (196, 172, 130, 255),
    "path_b": (180, 156, 116, 255),
    "soil_a": (122, 88, 62, 255),
    "soil_b": (102, 72, 50, 255),
    "wood": (140, 96, 56, 255),
    "wood_dark": (104, 70, 40, 255),
    "skin": (232, 186, 148, 255),
    "hair": (86, 60, 40, 255),
    "shirt": (74, 144, 217, 255),   # player: blue
    "shirt_n": (217, 74, 106, 255),  # Anna: distinct hue for silhouette test
    "pants": (66, 78, 104, 255),
    "boot": (58, 44, 36, 255),
    "cow_body": (238, 238, 232, 255),
    "cow_spot": (52, 48, 46, 255),
    "cow_udder": (226, 150, 154, 255),
    "pig_body": (222, 146, 152, 255),
    "pig_ear": (198, 122, 130, 255),
    "pig_snout": (176, 104, 114, 255),
    "pig_hoof": (86, 62, 62, 255),
    "hay": (214, 182, 96, 255),
    "hay_dark": (184, 152, 74, 255),
    "water": (86, 152, 196, 255),
    "metal": (128, 132, 140, 255),
    "outline": (38, 32, 30, 255),
    "bed_frame": (128, 84, 52, 255),
    "bed_sheet": (226, 226, 236, 255),
    "bed_pillow": (245, 245, 250, 255),
}


def write_png(path, width, height, pixels):
    """pixels: list of rows, each a list of RGBA tuples."""
    raw = b""
    for row in pixels:
        raw += b"\x00"  # filter type 0
        for px in row:
            raw += struct.pack("BBBB", *px)

    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9))
    png += chunk(b"IEND", b"")

    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(png)
    print("  %-52s %dx%d" % (os.path.relpath(path, ASSETS), width, height))


def blank(w, h, fill="transparent"):
    return [[C[fill] for _ in range(w)] for _ in range(h)]


# ---------------------------------------------------------------- tiles 16x16

def tile_grass():
    px = blank(16, 16, "grass_a")
    for (x, y) in [(2, 3), (3, 3), (9, 5), (10, 5), (5, 11), (6, 11), (13, 9), (12, 13)]:
        px[y][x] = C["grass_b"]
    for (x, y) in [(7, 2), (14, 6), (1, 8), (4, 14), (11, 1)]:
        px[y][x] = C["grass_c"]
    return px


def tile_path():
    px = blank(16, 16, "path_a")
    for (x, y) in [(1, 2), (5, 4), (9, 1), (13, 6), (3, 9), (11, 12), (7, 14), (14, 10)]:
        px[y][x] = C["path_b"]
    return px


def tile_soil():
    """Tilled soil — horizontal furrows so orientation is readable."""
    px = blank(16, 16, "soil_a")
    for y in range(16):
        if y % 4 in (2, 3):
            for x in range(16):
                px[y][x] = C["soil_b"]
    return px


def tile_fence():
    """Fence on grass — collision tile."""
    px = tile_grass()
    for x in range(16):           # top rail
        px[5][x] = C["wood"]
        px[6][x] = C["wood_dark"]
    for x in range(16):           # lower rail
        px[10][x] = C["wood"]
        px[11][x] = C["wood_dark"]
    for x in (2, 3, 11, 12):      # posts
        for y in range(3, 15):
            px[y][x] = C["wood"] if x in (2, 11) else C["wood_dark"]
    return px


# ------------------------------------------------- characters 16x32, 4 frames

def character_frame(direction, frame, shirt):
    """16x32 character. direction: 0=down 1=up 2=left 3=right. frame 0..3 walk cycle."""
    px = blank(16, 32)
    cx = 8

    def rect(x0, y0, x1, y1, col):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                if 0 <= x < 16 and 0 <= y < 32:
                    px[y][x] = C[col]

    # head 8x8 centred, y 4..11
    rect(cx - 4, 4, cx + 3, 11, "skin")
    rect(cx - 4, 3, cx + 3, 6, "hair")           # hair cap
    if direction == 0:                            # facing down: eyes
        px[8][cx - 2] = C["outline"]
        px[8][cx + 1] = C["outline"]
    elif direction == 2:                          # left
        px[8][cx - 3] = C["outline"]
        rect(cx + 1, 3, cx + 3, 9, "hair")
    elif direction == 3:                          # right
        px[8][cx + 2] = C["outline"]
        rect(cx - 4, 3, cx - 2, 9, "hair")
    else:                                         # up: back of head
        rect(cx - 4, 3, cx + 3, 9, "hair")

    # torso y 12..21
    rect(cx - 4, 12, cx + 3, 21, shirt)
    # arms
    rect(cx - 5, 13, cx - 5, 19, "skin")
    rect(cx + 4, 13, cx + 4, 19, "skin")
    # legs y 22..29 with 4-frame walk swing
    swing = [0, 1, 0, -1][frame]
    rect(cx - 3, 22, cx - 1, 29 + min(0, swing), "pants")
    rect(cx + 1, 22, cx + 3, 29 - max(0, swing), "pants")
    # boots
    rect(cx - 3, 29 + min(0, swing), cx - 1, 30 + min(0, swing), "boot")
    rect(cx + 1, 29 - max(0, swing), cx + 3, 30 - max(0, swing), "boot")
    return px


def spritesheet(shirt):
    """4 directions x 4 frames -> 64x128 sheet (16x32 cells)."""
    sheet = blank(64, 128)
    for d in range(4):
        for f in range(4):
            cell = character_frame(d, f, shirt)
            for y in range(32):
                for x in range(16):
                    sheet[d * 32 + y][f * 16 + x] = cell[y][x]
    return sheet


# ------------------------------------------------------------- props

def cow():
    """32x32, side view, facing left. Distinct silhouette per Part 6 §4."""
    px = blank(32, 32)

    def rect(x0, y0, x1, y1, col):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                if 0 <= x < 32 and 0 <= y < 32:
                    px[y][x] = C[col]

    rect(6, 10, 26, 22, "cow_body")      # body
    rect(2, 8, 9, 17, "cow_body")        # head
    rect(3, 6, 4, 8, "cow_body")         # ears
    rect(7, 6, 8, 8, "cow_body")
    px[12][3] = C["outline"]             # eye
    rect(2, 15, 5, 17, "cow_spot")       # muzzle
    for (x0, y0, x1, y1) in [(12, 12, 17, 16), (20, 15, 24, 19), (14, 19, 16, 21)]:
        rect(x0, y0, x1, y1, "cow_spot")
    rect(8, 23, 10, 29, "cow_body")      # legs
    rect(13, 23, 15, 29, "cow_body")
    rect(19, 23, 21, 29, "cow_body")
    rect(23, 23, 25, 29, "cow_body")
    for x in (8, 13, 19, 23):
        rect(x, 29, x + 2, 30, "cow_spot")
    rect(16, 21, 19, 23, "cow_udder")    # udder
    rect(26, 11, 27, 20, "cow_body")     # tail
    rect(26, 20, 27, 22, "cow_spot")
    return px


def pig():
    """32x32, side view facing left. Deliberately NOT a recoloured cow: shorter
    legs, rounder body, snout, curly tail. The Tier I wrong-action mechanic
    (feed the pig instead of the cow) only works if they read apart instantly.
    """
    px = blank(32, 32)

    def rect(x0, y0, x1, y1, col):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                if 0 <= x < 32 and 0 <= y < 32:
                    px[y][x] = C[col]

    rect(7, 13, 25, 24, "pig_body")      # body: low and round
    rect(5, 12, 11, 21, "pig_body")      # head
    rect(4, 11, 5, 13, "pig_ear")        # ears (forward, floppy)
    rect(8, 10, 10, 12, "pig_ear")
    rect(3, 17, 6, 20, "pig_snout")      # snout
    px[18][4] = C["outline"]             # nostrils
    px[18][5] = C["outline"]
    px[14][8] = C["outline"]             # eye
    rect(9, 25, 11, 29, "pig_body")      # legs: short, stubby
    rect(13, 25, 15, 29, "pig_body")
    rect(19, 25, 21, 29, "pig_body")
    rect(22, 25, 24, 29, "pig_body")
    for x in (9, 13, 19, 22):
        rect(x, 29, x + 2, 30, "pig_hoof")
    rect(26, 15, 27, 17, "pig_body")     # curly tail
    rect(27, 14, 28, 15, "pig_body")
    rect(26, 13, 27, 14, "pig_body")
    return px


def hay_bale():
    px = blank(16, 16)
    for y in range(5, 15):
        for x in range(2, 14):
            px[y][x] = C["hay"] if (y % 3) else C["hay_dark"]
    for x in range(2, 14):
        px[4][x] = C["hay_dark"]
    for y in range(5, 15):
        px[y][2] = C["hay_dark"]
        px[y][13] = C["hay_dark"]
    return px


def trough():
    px = blank(16, 16)
    for y in range(7, 14):
        for x in range(1, 15):
            px[y][x] = C["wood"]
    for x in range(2, 14):
        for y in range(8, 11):
            px[y][x] = C["water"]
    for x in range(1, 15):
        px[13][x] = C["wood_dark"]
    for y in range(7, 14):
        px[y][1] = C["wood_dark"]
        px[y][14] = C["wood_dark"]
    return px


def bed():
    """32x32 bed — the sleep interactable."""
    px = blank(32, 32)

    def rect(x0, y0, x1, y1, col):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                if 0 <= x < 32 and 0 <= y < 32:
                    px[y][x] = C[col]

    rect(4, 4, 27, 30, "bed_frame")
    rect(6, 6, 25, 28, "bed_sheet")
    rect(7, 7, 24, 12, "bed_pillow")
    for y in range(16, 28, 4):
        rect(6, y, 25, y, "bed_frame")
    return px


def main():
    print("Generating placeholder art (Part 11 §2 sizes):")
    t = os.path.join(ASSETS, "tilesets")
    write_png(os.path.join(t, "grass.png"), 16, 16, tile_grass())
    write_png(os.path.join(t, "path.png"), 16, 16, tile_path())
    write_png(os.path.join(t, "soil_tilled.png"), 16, 16, tile_soil())
    write_png(os.path.join(t, "fence.png"), 16, 16, tile_fence())

    s = os.path.join(ASSETS, "sprites")
    write_png(os.path.join(s, "player.png"), 64, 128, spritesheet("shirt"))
    write_png(os.path.join(s, "npc_anna.png"), 64, 128, spritesheet("shirt_n"))
    write_png(os.path.join(s, "cow.png"), 32, 32, cow())
    write_png(os.path.join(s, "pig.png"), 32, 32, pig())
    write_png(os.path.join(s, "hay_bale.png"), 16, 16, hay_bale())
    write_png(os.path.join(s, "trough.png"), 16, 16, trough())
    write_png(os.path.join(s, "bed.png"), 32, 32, bed())
    print("Done. ALL PLACEHOLDER — regenerate via PixelLab MCP per Part 11 §2.")


if __name__ == "__main__":
    main()
