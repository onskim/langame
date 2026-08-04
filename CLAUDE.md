# langame — repo anchor (read first, every session)

Speech-first German-learning cozy RPG. Godot 4.3+ / GDScript / SQLite / Azure Speech.
Design truth lives in `~/Documents/Claude/Projects/Language RPG/` (GDD Parts 1–14 + Addendum v0.2).
Supersession: Addendum v0.2 > Part 10/11 > Parts 3–9 > Parts 1–2.

## Hard rules
- Engine code NEVER contains a German string. All language content comes from
  content.db, compiled from content/*.yaml by tools/compile_db.py.
- Never hand-edit data/content.db. Never ship draft:true German.
- One acceptance criterion (GDD Part 10 §6) per commit. Run the scene via Godot MCP
  before every commit. Small commits, imperative messages.
- Assets: PixelLab MCP only, per GDD Part 11 §2 constants + style bible
  (game/assets/STYLE-BIBLE.md). Naming per GDD Part 10 §2.
- Every session appends one dated line to DEVLOG.md.

## Layout
game/ (Godot project) · content/ (YAML truth) · tools/ (Python pipeline) · data/ (build artifacts)

## Pinned constants (GDD Part 11 §2 — authoritative)
| Constant | Value |
|---|---|
| Base viewport | 640×360, integer-scaled |
| Tile size | 16×16 |
| World character sprites | 16×32, 4-direction, 4-frame walk |
| Pets | 16×16 (cat), 16×24 (dog) |
| Object sprites | 16×16 or 32×32 |
| Dialogue portraits | 64×64 |
| Scene Mode backdrop | 640×360 full-frame |
| Scene Mode characters | ~160 px tall, transparent bg |
| Palette | ≤48 colors global; der `#4A90D9`, die `#D94A6A`, das `#4AB57A` reserved |

## MCP servers configured
- **godot** — `@coding-solo/godot-mcp`: run scenes, capture debug output, manage scenes/nodes.
- **pixellab** — asset generation. Tool reference: `Projects/Language RPG/reference/pixellab-mcp-reference.md`.

## Current phase
Week 1 of GDD Part 10 §6 — repo initialized, Godot project boots. Check DEVLOG.md tail
for where the last session stopped.
