extends Node
class_name WorldBuilder
## Builds the Week 1 gray-box farm ground + fence collision in code.
##
## Deliberately procedural: the real hand-authored tilemaps arrive with the
## style bible and PixelLab tilesets (Part 11 §2). Keeping this in code means
## the gray-box is reproducible and no fragile .tres is hand-maintained.

const TILE := 16
## Larger than the 640x360 viewport (40x22 tiles) so the camera actually has to
## follow the player — a farm that fits on one screen hides camera bugs.
const FARM_W := 56
const FARM_H := 40


static func build_tileset() -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE, TILE)
	for path in [
		"res://assets/tilesets/grass.png",
		"res://assets/tilesets/path.png",
		"res://assets/tilesets/soil_tilled.png",
		"res://assets/tilesets/fence.png",
	]:
		var source := TileSetAtlasSource.new()
		source.texture = load(path)
		source.texture_region_size = Vector2i(TILE, TILE)
		source.create_tile(Vector2i.ZERO)
		ts.add_source(source)
	return ts


## Source ids, in the order added above.
enum Tile { GRASS = 0, PATH = 1, SOIL = 2, FENCE = 3 }


static func paint_ground(layer: TileMapLayer) -> void:
	layer.tile_set = build_tileset()

	for y in range(FARM_H):
		for x in range(FARM_W):
			layer.set_cell(Vector2i(x, y), Tile.GRASS, Vector2i.ZERO)

	# Paths give movement a readable destination rather than open field, and
	# run past the edge of one screen so scrolling is obvious.
	for x in range(3, FARM_W - 3):
		layer.set_cell(Vector2i(x, 20), Tile.PATH, Vector2i.ZERO)
	for y in range(4, FARM_H - 4):
		layer.set_cell(Vector2i(24, y), Tile.PATH, Vector2i.ZERO)

	# Tilled field — the farm sim proper is Part 14, this is just readable ground.
	for y in range(25, 33):
		for x in range(5, 19):
			layer.set_cell(Vector2i(x, y), Tile.SOIL, Vector2i.ZERO)

	# Anna's plot, north of the divider (Part 14 §3: adjacent farm plot).
	# Her field is tilled too, so the two holdings read as the same kind of work.
	for y in range(4, 9):
		for x in range(34, 46):
			layer.set_cell(Vector2i(x, y), Tile.SOIL, Vector2i.ZERO)
	for x in range(30, FARM_W - 2):
		layer.set_cell(Vector2i(x, 12), Tile.PATH, Vector2i.ZERO)


enum GateSide { NONE, EAST, WEST }


## Perimeter fence: visual tiles on `fence_layer`, collision as StaticBody2D
## children of `collision_parent`. `gate` leaves a gap so the farm has a way
## out — a fenced field with no gate is a prison, not a smallholding.
static func build_fence(fence_layer: TileMapLayer, collision_parent: Node2D,
		gate: GateSide = GateSide.NONE) -> void:
	fence_layer.tile_set = build_tileset()

	var cells: Array[Vector2i] = []
	for x in range(FARM_W):
		cells.append(Vector2i(x, 0))
		cells.append(Vector2i(x, FARM_H - 1))
	var gate_rows := [FARM_H / 2 - 1, FARM_H / 2, FARM_H / 2 + 1]
	for y in range(1, FARM_H - 1):
		if not (gate == GateSide.WEST and gate_rows.has(y)):
			cells.append(Vector2i(0, y))
		if not (gate == GateSide.EAST and gate_rows.has(y)):
			cells.append(Vector2i(FARM_W - 1, y))

	# The divider between the player's plot and Anna's, with a gap to walk
	# through. Neighbours, not strangers — the boundary should be legible but
	# never an obstacle.
	if gate != GateSide.NONE:
		for x in range(28, FARM_W - 1):
			if x < 36 or x > 39:
				cells.append(Vector2i(x, 14))

	for cell in cells:
		fence_layer.set_cell(cell, Tile.FENCE, Vector2i.ZERO)

	var body := StaticBody2D.new()
	body.name = "FenceCollision"
	collision_parent.add_child(body)

	for cell in cells:
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(TILE, TILE)
		shape.shape = rect
		shape.position = Vector2(cell.x * TILE + TILE / 2.0, cell.y * TILE + TILE / 2.0)
		body.add_child(shape)


# ------------------------------------------------------------------ village

const VILLAGE_W := 46
const VILLAGE_H := 34


## The village square and its lanes. Buildings are placed in the scene; this
## lays the ground they stand on.
static func paint_village(layer: TileMapLayer) -> void:
	layer.tile_set = build_tileset()

	for y in range(VILLAGE_H):
		for x in range(VILLAGE_W):
			layer.set_cell(Vector2i(x, y), Tile.GRASS, Vector2i.ZERO)

	# The square itself — paved, central, the place people gather.
	for y in range(12, 22):
		for x in range(15, 31):
			layer.set_cell(Vector2i(x, y), Tile.PATH, Vector2i.ZERO)

	# The lane in from the farm (west edge) and the lanes to each shopfront.
	for x in range(0, 16):
		layer.set_cell(Vector2i(x, 16), Tile.PATH, Vector2i.ZERO)
		layer.set_cell(Vector2i(x, 17), Tile.PATH, Vector2i.ZERO)
	for y in range(6, 13):
		layer.set_cell(Vector2i(20, y), Tile.PATH, Vector2i.ZERO)
		layer.set_cell(Vector2i(26, y), Tile.PATH, Vector2i.ZERO)
	for y in range(21, 29):
		layer.set_cell(Vector2i(23, y), Tile.PATH, Vector2i.ZERO)


# ----------------------------------------------------------------- interiors

const ROOM_W := 20
const ROOM_H := 14


## A room: floorboards inside, wall band along the top, solid walls around.
## Interiors are small by design — one screen, no camera hunting for the door.
static func paint_interior(layer: TileMapLayer, collision_parent: Node2D,
		room_w: int = ROOM_W, room_h: int = ROOM_H) -> void:
	layer.tile_set = build_tileset()

	for y in range(room_h):
		for x in range(room_w):
			# Row 0-1 read as the back wall, the rest as floor.
			var tile := Tile.PATH if y >= 2 else Tile.SOIL
			layer.set_cell(Vector2i(x, y), tile, Vector2i.ZERO)

	var body := StaticBody2D.new()
	body.name = "RoomCollision"
	collision_parent.add_child(body)

	var walls: Array[Vector2i] = []
	for x in range(room_w):
		walls.append(Vector2i(x, 0))
		walls.append(Vector2i(x, 1))
		walls.append(Vector2i(x, room_h - 1))
	for y in range(2, room_h - 1):
		walls.append(Vector2i(0, y))
		walls.append(Vector2i(room_w - 1, y))

	for cell in walls:
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(TILE, TILE)
		shape.shape = rect
		shape.position = Vector2(cell.x * TILE + TILE / 2.0, cell.y * TILE + TILE / 2.0)
		body.add_child(shape)
