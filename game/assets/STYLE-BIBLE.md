# LANGUAGE RPG — Style Bible v1
**The consistency contract for ALL art (PixelLab, commissions, UI). Copy into `~/langame/game/assets/STYLE-BIBLE.md` at Week 1.**
**References (approved 2026-08-04):** `reference/style-world-mode-v1.png` (top-down) · `reference/style-scene-mode-v1.png` (close-up)

---

## 1. The Two Looks

- **World Mode** = reference 1: dense storybook-Alpine top-down, Stardew-class readability, brighter and more saturated than Stardew. Cobblestone paths, timber-frame buildings, terracotta roofs, blue shutters, flower boxes everywhere, blossom-tree pink accents.
- **Scene Mode** = reference 2: same palette and world, three-quarter close-up, painterly-pixel hybrid, big expressive characters, warm dialogue frame.
- Every asset must sit convincingly *inside* its reference image. When in doubt, place the new sprite into the reference and squint.

## 2. Palette (draft hexes — sample exact values from the reference PNGs during repo setup, then freeze)

| Role | Hex (approx) |
|---|---|
| Roof terracotta / highlight | `#C0552F` / `#E07B47` |
| Timber beams / dark wood | `#8B5E3C` / `#6B4A2F` |
| Wall plaster cream / stone | `#E8D9B0` / `#C9BFA4` |
| Shutter & door blue | `#4E7FB5` |
| Meadow green / deep foliage | `#6FA34D` / `#3F6B35` |
| Cobble tan / grout | `#C9AE84` / `#A98F6B` |
| Sky / water | `#7EC4E8` / `#4A90B8` |
| Blossom pink accent | `#E8A0C0` |
| UI paper / UI frame / UI text | `#E5C793` / `#7A4E2A` / `#3A2A1A` |
| **Article hues (grammar-reserved, NEVER decorative)** | der `#4A90D9` · die `#D94A6A` · das `#4AB57A` |

Global cap ~48 colors for world tiles/sprites; Scene Mode may exceed for portraits. Article hues must pass contrast on UI paper and survive deuteranopia/protanopia simulation (Part 3 §8) — verify once, then freeze.

## 3. Form Rules

- World sprites: clean 1px dark outlines (warm dark brown, not black), consistent top-left light, ~30° top-down. Sizes per Part 11 §2 (16px tiles, 16×32 characters, 64×64 portraits).
- Scene Mode: soft outlines, painterly shading allowed, characters ~160px tall, expressions readable at arm's length on a phone.
- Teachable nouns: silhouette-first — if the sprite isn't identifiable unprompted at 16px, redraw (art-is-curriculum rule, Part 6 §4).
- Cozy density: flower boxes, barrels, signage, path-side flowers — clutter is welcome but never on walkable gameplay tiles that need readability.

## 4. HUD Specification (founder request 2026-08-04)

Layout at 640×360 logical resolution; all HUD chrome uses the UI paper/frame palette. **No health bar — no combat exists; energy + hunger are the body meters.**

```
┌────────────────────────────────────────────── 640×360 ─────┐
│  [₥ 124]  [Frühling 12 · Mo · 09:40]              (top-right, small) │
│                                                            │
│                        (world view)                        │
│                                                            │
│ [📱]   [1][2][3][4][5][6][7][8]        [⚡████░] [🍽███░░] │
│ phone        toolbar 8 slots            energy    hunger   │
└────────────────────────────────────────────────────────────┘
```

- **Bottom-left — Phone button:** opens the full-screen phone (6 apps: Wörter, Aufgaben, Wetter, Karte, Kalender, Leute). Notification dot when a new task/craving/discovery lands. **The map is the phone's Karte app** — no separate map button; long-press (mobile) / M key (PC) deep-links straight to Karte.
- **Bottom-center — Toolbar:** 8 slots, 20×20px icons in paper-framed cells; number keys/scroll on PC, tap on mobile; active slot highlighted with the frame-brown glow. Holds tools + consumables (Part 14 tools).
- **Bottom-right — Meters:** two compact horizontal bars: ⚡ Energy (meadow-green fill) and 🍽 Hunger (terracotta fill). Craving icon floats beside hunger bar when active (tap it → phone Wörter entry for that food word — a hidden vocab link). Bars pulse gently below 30%; no alarms, no red flashing (affective-filter rule).
- **Top-right — Money + date/time:** small text chips, always visible; clock feeds off Part 12 §5 calendar. German day/season names ("Frühling 12 · Montag") — the HUD itself is passive reading exposure.
- **Dialogue/Scene Mode:** all HUD chrome fades out except nothing — full immersion during conversation; meters return on close.
- **Mobile deltas:** virtual joystick bottom-left above phone button; toolbar collapses to 4 visible slots with swipe; all targets ≥ 48dp (Part 3 §5).

## 5. HUD Mockup Prompt (generate to verify the look before building)

> Take this pixel art village scene style [attach style-world-mode-v1.png] and add a cozy game HUD: bottom-left a small smartphone icon button in a warm paper-and-wood UI style; bottom-center a horizontal toolbar of 8 square item slots framed in carved wood holding tiny tool icons (hoe, watering can, axe, seeds); bottom-right two small horizontal meter bars — one green with a lightning bolt icon, one terracotta-orange with a plate icon, plus a small floating thought-bubble showing a pretzel; top-right small paper chips reading "₥ 124" and "Frühling 12 · Mo 09:40". Keep the HUD minimal, warm parchment tones, rounded pixel corners, matching the scene's palette. 16:9.

## 6. Production Workflow

1. Sample exact palette hexes from the two references → freeze this file at v1.0.
2. PixelLab: every request cites the size table (Part 11 §2) + this palette + "must match reference/style-world-mode-v1.png".
3. Weekly consistency review: place the week's new assets into a contact-sheet against the references; regenerate drifters.
4. Scene Mode assets (backdrops, large characters) additionally check against reference 2.
5. This file is versioned; palette changes after v1.0 require regenerating affected assets — change it rarely.
