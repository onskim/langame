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


## Perimeter fence: visual tiles on `fence_layer`, collision as StaticBody2D
## children of `collision_parent`.
static func build_fence(fence_layer: TileMapLayer, collision_parent: Node2D) -> void:
	fence_layer.tile_set = build_tileset()

	var cells: Array[Vector2i] = []
	for x in range(FARM_W):
		cells.append(Vector2i(x, 0))
		cells.append(Vector2i(x, FARM_H - 1))
	for y in range(1, FARM_H - 1):
		cells.append(Vector2i(0, y))
		cells.append(Vector2i(FARM_W - 1, y))

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
