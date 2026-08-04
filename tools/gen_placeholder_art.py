#!/usr/bin/env python3
"""Generate PLACEHOLDER pixel art at the exact sizes pinned in GDD Part 11 §2.

This exists only because PixelLab MCP was unavailable in the Week 1 session.
Every asset it writes is gray-box scaffolding to be REPLACED by PixelLab output
once the style bible lands (Part 11 §2 workflow rule). Do not treat any of this
as art direction.

Pure stdlib — no Pillow dependency.
"""

import math
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
    "leaf_dk": (58, 122, 46, 255),
    "leaf_md": (86, 158, 62, 255),
    "leaf_lt": (122, 190, 84, 255),
    "flower_w": (246, 248, 236, 255),
    "flower_y": (244, 214, 92, 255),
    "flower_p": (238, 176, 186, 255),
    "rock_md": (146, 146, 138, 255),
    "rock_dk": (104, 104, 98, 255),
    "rock_lt": (178, 178, 168, 255),
    "dog_body": (196, 142, 84, 255),
    "dog_dark": (154, 104, 58, 255),
    "cat_body": (232, 152, 78, 255),
    "cat_dark": (196, 118, 54, 255),
    "hay": (214, 182, 96, 255),
    "hay_dark": (184, 152, 74, 255),
    "water": (86, 152, 196, 255),
    "metal": (128, 132, 140, 255),
    "outline": (38, 32, 30, 255),
    "bed_frame": (128, 84, 52, 255),
    "bed_sheet": (226, 226, 236, 255),
    "bed_pillow": (245, 245, 250, 255),
    "wall": (222, 206, 182, 255),
    "wall_shade": (198, 180, 156, 255),
    "roof_bake": (188, 96, 74, 255),
    "roof_shop": (92, 124, 176, 255),
    "roof_hall": (120, 104, 152, 255),
    "roof_dark": (62, 52, 48, 255),
    "door": (108, 74, 46, 255),
    "window": (140, 190, 214, 255),
    "sign": (240, 226, 190, 255),
    "stone": (150, 148, 142, 255),
    "stone_dark": (112, 110, 106, 255),
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


def building(roof_col, width=64, height=64):
    """A shopfront: roof, wall, door, two windows. Distinct roof colour per
    building so the player can navigate by silhouette + hue before they can
    read the sign."""
    px = blank(width, height)

    def rect(x0, y0, x1, y1, col):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                if 0 <= x < width and 0 <= y < height:
                    px[y][x] = C[col]

    body_top = height // 3
    rect(2, body_top, width - 3, height - 5, "wall")
    for y in range(body_top, height - 4):          # wall shading on the right
        rect(width - 10, y, width - 3, y, "wall_shade")

    # gabled roof
    for i in range(body_top + 3):
        x0 = max(0, i - 2)
        x1 = min(width - 1, width - 1 - i + 2)
        if x0 <= x1:
            rect(x0, i, x1, i, roof_col)
    rect(0, body_top + 1, width - 1, body_top + 3, "roof_dark")

    door_x = width // 2 - 5
    rect(door_x, height - 20, door_x + 9, height - 5, "door")
    rect(door_x + 7, height - 13, door_x + 7, height - 12, "sign")   # handle

    rect(6, body_top + 8, 15, body_top + 17, "window")
    rect(width - 16, body_top + 8, width - 7, body_top + 17, "window")
    rect(6, body_top + 8, 15, body_top + 8, "roof_dark")
    rect(width - 16, body_top + 8, width - 7, body_top + 8, "roof_dark")

    rect(door_x - 4, body_top + 6, door_x + 13, body_top + 11, "sign")  # signboard
    rect(door_x - 4, body_top + 6, door_x + 13, body_top + 6, "roof_dark")

    rect(0, height - 5, width - 1, height - 1, "stone_dark")            # footing
    return px


def barn():
    """Anna's big barn — 80x64. Deliberately larger and squarer than a
    shopfront so the plot next door reads as a working farm at a glance."""
    w, h = 80, 64
    px = blank(w, h)

    def rect(x0, y0, x1, y1, col):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                if 0 <= x < w and 0 <= y < h:
                    px[y][x] = C[col]

    rect(3, 20, w - 4, h - 5, "roof_bake")        # red board walls
    for y in range(20, h - 4):
        if y % 5 == 0:
            rect(3, y, w - 4, y, "roof_dark")
    # gambrel roof: two slopes, the barn silhouette
    for i in range(10):
        rect(max(0, 14 - i), 10 + i, min(w - 1, w - 15 + i), 10 + i, "wood_dark")
    for i in range(10):
        rect(max(0, 24 - i * 2), i, min(w - 1, w - 25 + i * 2), i, "wood_dark")
    rect(0, 19, w - 1, 21, "roof_dark")

    rect(w // 2 - 13, h - 30, w // 2 + 12, h - 5, "wood")   # big double doors
    rect(w // 2 - 1, h - 30, w // 2, h - 5, "roof_dark")
    rect(w // 2 - 13, h - 30, w // 2 + 12, h - 28, "roof_dark")
    rect(10, 26, 19, 34, "window")
    rect(w - 20, 26, w - 11, 34, "window")
    rect(0, h - 5, w - 1, h - 1, "stone_dark")
    return px


def well():
    """The village well — the square's landmark and Mila's hangout."""
    px = blank(32, 32)

    def rect(x0, y0, x1, y1, col):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                if 0 <= x < 32 and 0 <= y < 32:
                    px[y][x] = C[col]

    rect(6, 14, 25, 27, "stone")
    for y in range(14, 28):
        if y % 3 == 0:
            rect(6, y, 25, y, "stone_dark")
    rect(6, 12, 25, 14, "stone_dark")
    rect(13, 15, 18, 20, "water")
    rect(7, 2, 9, 14, "wood")       # posts
    rect(22, 2, 24, 14, "wood")
    rect(5, 0, 26, 3, "roof_dark")  # little roof
    rect(15, 4, 16, 9, "wood")      # rope
    rect(13, 9, 18, 12, "wood_dark")
    return px


def pet_frame(direction, frame, body, dark, height):
    """Pets share one behaviour system and differ only by sprite (Addendum §6).
    Dog 16x24, cat 16x16 per Part 11 §2."""
    px = blank(16, height)

    def rect(x0, y0, x1, y1, col):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                if 0 <= x < 16 and 0 <= y < height:
                    px[y][x] = col

    base = height - 1
    bob = [0, -1, 0, 0][frame]
    rect(3, base - 9 + bob, 12, base - 3 + bob, body)          # body
    head_x = 9 if direction == 3 else (1 if direction == 2 else 5)
    rect(head_x, base - 13 + bob, head_x + 5, base - 8 + bob, body)   # head
    rect(head_x, base - 15 + bob, head_x + 1, base - 13 + bob, dark)  # ears
    rect(head_x + 4, base - 15 + bob, head_x + 5, base - 13 + bob, dark)
    if direction != 1:                                          # eye
        px[base - 11 + bob][head_x + (4 if direction == 3 else 1)] = C["outline"]
    swing = [0, 1, 0, -1][frame]
    rect(4, base - 3 + bob, 5, base - max(0, swing) + bob, dark)      # legs
    rect(10, base - 3 + bob, 11, base + min(0, swing) + bob, dark)
    tail_x = 2 if direction == 3 else 13                        # tail
    rect(tail_x, base - 11 + bob, tail_x + 1, base - 7 + bob, dark)
    return px


def pet_sheet(body, dark, height):
    """4 directions x 4 frames."""
    sheet = blank(64, height * 4)
    for d in range(4):
        for f in range(4):
            cell = pet_frame(d, f, body, dark, height)
            for y in range(height):
                for x in range(16):
                    sheet[d * height + y][f * 16 + x] = cell[y][x]
    return sheet


# ------------------------------------------------------- ground decoration
#
# The reference ground reads lush not because the base tile is busy, but
# because it is SCATTERED with small props: leafy clumps, wildflower clusters,
# stones. A repeated base tile always reads flat; the scatter is what breaks it.
# 16x16, transparent, drawn onto a decor layer above the terrain.

def _leaf_clump(seedv):
    """A leafy plant clump — the biggest scatter element."""
    px = blank(16, 16)
    rnd = _Rnd(seedv)
    cx, cy = 8, 10
    for i in range(6):
        ang = i * 1.05 + rnd.f() * 0.4
        length = 3 + rnd.i(3)
        for t in range(length):
            x = int(cx + math.cos(ang) * t)
            y = int(cy - abs(math.sin(ang)) * t * 0.8)
            for dx in (-1, 0, 1):
                if 0 <= x + dx < 16 and 0 <= y < 16:
                    shade = "leaf_lt" if t >= length - 1 else ("leaf_md" if dx == 0 else "leaf_dk")
                    px[y][x + dx] = C[shade]
    return px


def _flower_cluster(seedv, petal):
    """Three or four tiny blossoms with stems."""
    px = blank(16, 16)
    rnd = _Rnd(seedv)
    for _ in range(3 + rnd.i(2)):
        x = 2 + rnd.i(11)
        y = 4 + rnd.i(8)
        for sy in range(y + 1, min(15, y + 4)):       # stem
            px[sy][x] = C["leaf_dk"]
        px[y][x] = C[petal]                            # blossom
        for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            if 0 <= x + dx < 16 and 0 <= y + dy < 16:
                px[y + dy][x + dx] = C[petal]
        px[y][x] = C["flower_y"] if petal != "flower_y" else C["flower_w"]
    return px


def _stone(seedv):
    """A small rounded stone with a highlight."""
    px = blank(16, 16)
    rnd = _Rnd(seedv)
    w = 4 + rnd.i(3)
    h = 3 + rnd.i(2)
    ox, oy = 5, 8
    for y in range(h):
        span = w - abs(y - h // 2)
        for x in range(span):
            px[oy + y][ox + x] = C["rock_md"]
    for x in range(w - 2):
        px[oy][ox + 1 + x] = C["rock_lt"]
    for x in range(w - 1):
        px[oy + h - 1][ox + x] = C["rock_dk"]
    return px


def _grass_tuft(seedv):
    """A few blades — the lightest scatter, used most often."""
    px = blank(16, 16)
    rnd = _Rnd(seedv)
    for _ in range(3 + rnd.i(3)):
        x = 2 + rnd.i(12)
        h = 2 + rnd.i(3)
        lean = rnd.i(3) - 1
        for t in range(h):
            y = 13 - t
            xx = x + int(lean * t / max(h - 1, 1))
            if 0 <= xx < 16 and 0 <= y < 16:
                px[y][xx] = C["leaf_lt"] if t == h - 1 else C["leaf_md"]
    return px


class _Rnd:
    """Tiny deterministic RNG so the decor atlas is reproducible."""
    def __init__(self, seedv):
        self.s = (seedv * 1103515245 + 12345) & 0x7FFFFFFF

    def next(self):
        self.s = (self.s * 1103515245 + 12345) & 0x7FFFFFFF
        return self.s

    def i(self, n):
        return self.next() % max(n, 1)

    def f(self):
        return self.next() / float(0x7FFFFFFF)


def decor_atlas():
    """One row of 16x16 scatter props: tufts, clumps, flowers, stones."""
    kinds = []
    for i in range(4):
        kinds.append(_grass_tuft(i + 1))
    for i in range(3):
        kinds.append(_leaf_clump(i + 40))
    for i, petal in enumerate(["flower_w", "flower_y", "flower_p"]):
        kinds.append(_flower_cluster(i + 90, petal))
    for i in range(2):
        kinds.append(_stone(i + 200))
    sheet = blank(16 * len(kinds), 16)
    for k, cell in enumerate(kinds):
        for y in range(16):
            for x in range(16):
                sheet[y][k * 16 + x] = cell[y][x]
    return sheet, len(kinds)


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
    write_png(os.path.join(s, "bld_bakery.png"), 64, 64, building("roof_bake"))
    write_png(os.path.join(s, "bld_shop.png"), 64, 64, building("roof_shop"))
    write_png(os.path.join(s, "bld_rathaus.png"), 80, 72, building("roof_hall", 80, 72))
    write_png(os.path.join(s, "well.png"), 32, 32, well())
    atlas, count = decor_atlas()
    write_png(os.path.join(ASSETS, "tilesets", "decor.png"), 16 * count, 16, atlas)
    print("  decor atlas: %d props" % count)
    write_png(os.path.join(s, "pet_dog.png"), 64, 96,
              pet_sheet(C["dog_body"], C["dog_dark"], 24))
    write_png(os.path.join(s, "pet_cat.png"), 64, 64,
              pet_sheet(C["cat_body"], C["cat_dark"], 16))
    write_png(os.path.join(s, "bld_barn.png"), 80, 64, barn())
    write_png(os.path.join(s, "bld_anna_house.png"), 64, 64, building("roof_hall"))
    print("Done. ALL PLACEHOLDER — regenerate via PixelLab MCP per Part 11 §2.")


if __name__ == "__main__":
    main()
