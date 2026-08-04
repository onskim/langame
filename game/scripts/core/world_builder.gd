extends Node
class_name WorldBuilder
## Builds the farm/village ground + fence collision in code.
##
## Deliberately procedural: keeping the layout in code means it is reproducible
## and no fragile .tres is hand-maintained.
##
## Ground art is the PixelLab corner-Wang packs in assets/tilesets/ (Addendum
## §10 Week 3 art pass). Painting MATCHES CORNERS via WangTileset rather than
## stamping one full-terrain tile per material: a map is described as boolean
## regions — where is grass, where is soil — and the autotiler resolves every
## edge and corner, so material boundaries blend instead of stepping.
##
## Which atlas cell means which corner combination is never guessed: it comes
## from each sheet's `.tiles.json` sidecar, so regenerating a tileset in
## PixelLab cannot silently shuffle the terrain under the map.

const TILE := 16

## Larger than the 640x360 viewport (40x22 tiles) so the camera actually has to
## follow the player — a farm that fits on one screen hides camera bugs.
const FARM_W := 56
const FARM_H := 40
const VILLAGE_W := 46
const VILLAGE_H := 34

const PACK_PATH_GRASS := "res://assets/tilesets/ground_ref"
const PACK_GRASS_SOIL := "res://assets/tilesets/ground_soil_ref"
const PACK_SOIL_WATERED := "res://assets/tilesets/ground_wetsoil_ref"
const PACK_GRASS_WILD := "res://assets/tilesets/ground_grass_wild"
const PACK_GRASS_WATER := "res://assets/tilesets/ground_water_ref"

enum GateSide { NONE, EAST, WEST }


## A wandering path, not a ruled line.
##
## Straight one-tile lanes were the thing that read worst: real tracks bend
## around obstacles, widen where people cut a corner, and have ragged grass
## edges. The centreline wobbles with two out-of-phase sine waves plus a hash
## jitter, and the width breathes — all deterministic, so the map is identical
## every run but never looks drawn with a ruler.
static func _path_offset(t: float, seed_value: int) -> float:
	return sin(t * 0.11 + seed_value) * 2.6 \
		+ sin(t * 0.29 + seed_value * 2.0) * 1.1


## Half-width in tiles. A track is something one or two people walk abreast —
## about three tiles — not an avenue. The first pass used 2.4±0.9, which read as
## a dirt field with grass islands rather than a path through a meadow.
static func _path_width(t: float, seed_value: int) -> float:
	return 1.15 + sin(t * 0.19 + seed_value * 1.7) * 0.35


## Is (x, y) inside a horizontal track whose centre runs along `centre_y`?
static func on_h_path(x: int, y: int, centre_y: int, from_x: int, to_x: int,
		seed_value: int) -> bool:
	if x < from_x or x > to_x:
		return false
	var centre: float = float(centre_y) + _path_offset(float(x), seed_value)
	return abs(float(y) - centre) <= _path_width(float(x), seed_value)


static func on_v_path(x: int, y: int, centre_x: int, from_y: int, to_y: int,
		seed_value: int) -> bool:
	if y < from_y or y > to_y:
		return false
	var centre: float = float(centre_x) + _path_offset(float(y), seed_value)
	return abs(float(x) - centre) <= _path_width(float(y), seed_value)


## Scattered bare patches where the grass has worn through — the reference is
## full of them, and they are most of what stops open ground reading as a sheet.
static func on_scuff(x: int, y: int) -> bool:
	var h: int = abs(int(hash(Vector2i(x / 3, y / 3))))
	if h % 41 != 0:
		return false
	# Only the centre of each 3x3 block, so scuffs stay small and rounded.
	return (x % 3 == 1) and (y % 3 == 1)


## Give `layer` a one-pack TileSet and return the loaded pack.
static func pack_layer(layer: TileMapLayer, base_path: String) -> WangTileset:
	var pack := WangTileset.load_pack(base_path)
	if not pack.is_valid():
		push_error("WorldBuilder: tileset pack %s failed to load" % base_path)
		return pack
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE, TILE)
	ts.add_source(pack.make_source(), 0)
	layer.tile_set = ts
	return pack


## Stamp only cells that touch the region, leaving the rest of the layer
## transparent so whatever is painted below shows through at the seams.
##
## `region_is_upper` exists because packs disagree about which terrain they call
## "upper". The PixelLab sets treat the stamped material as upper; packs cut from
## a founder reference always treat GRASS as upper, so for those the region — the
## soil — is the LOWER terrain and every corner flag has to be flipped. Getting
## this backwards paints a field of grass inside a meadow and reads as "nothing
## happened", which is exactly how the first ground tileset shipped inverted.
static func stamp(layer: TileMapLayer, pack: WangTileset, width: int, height: int,
		in_region: Callable, region_is_upper: bool = true) -> void:
	for y in range(height):
		for x in range(width):
			var nw: bool = in_region.call(x, y)
			var ne: bool = in_region.call(x + 1, y)
			var sw: bool = in_region.call(x, y + 1)
			var se: bool = in_region.call(x + 1, y + 1)
			if not (nw or ne or sw or se):
				continue
			var cell := Vector2i(x, y)
			# `cell` seeds the variant pick. Omitting it — as this did — pins
			# every cell to variant 0, so a plot tiles as visibly as wallpaper
			# no matter how many variants the pack carries.
			if region_is_upper:
				layer.set_cell(cell, 0, pack.atlas_for(ne, nw, se, sw, cell))
			else:
				layer.set_cell(cell, 0,
					pack.atlas_for(not ne, not nw, not se, not sw, cell))


## An irregular pond. Round ponds read as decals; the reference's water has
## lobed, wandering shores, so the radius is modulated by angle.
static func in_pond(x: int, y: int, cx: float, cy: float, radius: float,
		seed_value: int) -> bool:
	var dx := float(x) - cx
	var dy := (float(y) - cy) * 1.35     # wider than tall, like the reference
	var angle := atan2(dy, dx)
	var lobed: float = radius \
		+ sin(angle * 3.0 + seed_value) * radius * 0.22 \
		+ sin(angle * 5.0 + seed_value * 2.0) * radius * 0.11
	return sqrt(dx * dx + dy * dy) <= lobed


## Water is scenery you cannot walk into. Every water cell gets a body, so the
## shoreline stops the player exactly where it looks like it should.
static func build_water_collision(parent: Node2D, width: int, height: int,
		is_water: Callable) -> void:
	var body := StaticBody2D.new()
	body.name = "WaterCollision"
	parent.add_child(body)
	for y in range(height):
		for x in range(width):
			# Only fully-submerged cells block: a cell with any shore in it is
			# walkable bank, which keeps the edge generous rather than sticky.
			if is_water.call(x, y) and is_water.call(x + 1, y) \
					and is_water.call(x, y + 1) and is_water.call(x + 1, y + 1):
				var shape := CollisionShape2D.new()
				var rect := RectangleShape2D.new()
				rect.size = Vector2(TILE, TILE)
				shape.shape = rect
				shape.position = Vector2(x * TILE + TILE / 2.0, y * TILE + TILE / 2.0)
				body.add_child(shape)


# --------------------------------------------------------------------- farm

## Ground is two layers so material edges blend: lanes carved out of grass on
## the base, tilled soil stamped on top wherever a field is.
## The player's crop field. Shared by the painter and the crop simulation for
## the same reason the pond shares its predicate: soil you can see but not plant
## in, or plant in but not see, is the same class of lie.
static func in_player_field(x: int, y: int) -> bool:
	return x >= 5 and x <= 19 and y >= 25 and y <= 33


static func in_anna_field(x: int, y: int) -> bool:
	return x >= 34 and x <= 46 and y >= 4 and y <= 9


## Where the farm's pond sits — shared by the painter and the collision pass so
## the water you see and the water that stops you can never disagree.
static func farm_is_water(x: int, y: int) -> bool:
	return in_pond(x, y, 44.0, 30.0, 6.5, 3)


## The pond plus one ring of bank — what the water layer needs to draw.
static func _near_farm_water(x: int, y: int) -> bool:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if farm_is_water(x + dx, y + dy):
				return true
	return false


static func paint_ground(layer: TileMapLayer, crops: TileMapLayer = null,
		water: TileMapLayer = null, collision_parent: Node2D = null) -> void:
	# ground_path_grass: lower = dirt path, upper = grass. "Upper" therefore
	# means grass, and a lane is simply where grass is absent.
	var pack := pack_layer(layer, PACK_PATH_GRASS)
	if not pack.is_valid():
		return

	var is_grass := func(x: int, y: int) -> bool:
		# Tracks give movement a readable destination rather than open field, and
		# run past the edge of one screen so scrolling is obvious.
		# The pond is not a track — grass stops at its shore, and the water
		# layer draws over the top.
		if farm_is_water(x, y):
			return true
		var track_main: bool = on_h_path(x, y, 20, 2, FARM_W - 2, 11)
		var track_north: bool = on_v_path(x, y, 24, 3, FARM_H - 3, 29)
		var track_anna: bool = on_h_path(x, y, 12, 29, FARM_W - 2, 47)
		return not (track_main or track_north or track_anna or on_scuff(x, y))
	pack.paint(layer, 0, FARM_W, FARM_H, is_grass)

	if crops == null:
		return
	# ground_soil_ref is cut from the founder's farmland reference, so GRASS is
	# the upper terrain and the tilled soil is lower — hence region_is_upper
	# false below.
	var soil := pack_layer(crops, PACK_GRASS_SOIL)
	if not soil.is_valid():
		return
	var is_soil := func(x: int, y: int) -> bool:
		# Anna's plot is tilled too, so the two holdings read as the same work.
		return in_player_field(x, y) or in_anna_field(x, y)
	stamp(crops, soil, FARM_W, FARM_H, is_soil, false)

	if water == null:
		return
	# ground_water_ref: lower = water, upper = grass. The stamp draws the shore
	# where grass meets it, so the bank blends instead of stepping.
	var pond := pack_layer(water, PACK_GRASS_WATER)
	if not pond.is_valid():
		return
	# In this pack grass is "upper", so the region test is "is this corner NOT
	# water". Only cells near the pond are stamped, leaving the rest transparent.
	var is_bank := func(x: int, y: int) -> bool: return not farm_is_water(x, y)
	for y in range(FARM_H):
		for x in range(FARM_W):
			if not _near_farm_water(x, y):
				continue
			var nw: bool = is_bank.call(x, y)
			var ne: bool = is_bank.call(x + 1, y)
			var sw: bool = is_bank.call(x, y + 1)
			var se: bool = is_bank.call(x + 1, y + 1)
			var cell := Vector2i(x, y)
			water.set_cell(cell, 0, pond.atlas_for(ne, nw, se, sw, cell))
	if collision_parent != null:
		build_water_collision(collision_parent, FARM_W, FARM_H, farm_is_water)


## Perimeter fence: visual tiles on `fence_layer`, collision as StaticBody2D
## children of `collision_parent`. `gate` leaves a gap so the farm has a way
## out — a fenced field with no gate is a prison, not a smallholding.
static func build_fence(fence_layer: TileMapLayer, collision_parent: Node2D,
		gate: GateSide = GateSide.NONE) -> void:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE, TILE)
	var source := TileSetAtlasSource.new()
	source.texture = load("res://assets/tilesets/fence.png")
	source.texture_region_size = Vector2i(TILE, TILE)
	source.create_tile(Vector2i.ZERO)
	ts.add_source(source, 0)
	fence_layer.tile_set = ts

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
		fence_layer.set_cell(cell, 0, Vector2i.ZERO)

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

## The village square and its lanes. Buildings are placed in the scene; this
## lays the ground they stand on.
static func paint_village(layer: TileMapLayer, _crops: TileMapLayer = null) -> void:
	var pack := pack_layer(layer, PACK_PATH_GRASS)
	if not pack.is_valid():
		return

	var is_grass := func(x: int, y: int) -> bool:
		# The square is worn bare by footfall — its edge is rounded, not ruled.
		var dx := float(x) - 23.0
		var dy := (float(y) - 17.0) * 1.5
		var wobble: float = sin(atan2(dy, dx) * 3.0) * 1.2
		var square: bool = sqrt(dx * dx + dy * dy) <= 7.0 + wobble
		var lane_west: bool = on_h_path(x, y, 17, 0, 18, 5)
		var lane_bakery: bool = on_v_path(x, y, 20, 6, 14, 61)
		var lane_shop: bool = on_v_path(x, y, 26, 6, 14, 73)
		var lane_south: bool = on_v_path(x, y, 23, 20, 30, 83)
		return not (square or lane_west or lane_bakery or lane_shop
			or lane_south or on_scuff(x, y))
	pack.paint(layer, 0, VILLAGE_W, VILLAGE_H, is_grass)


# ---------------------------------------------------------------- interiors

const ROOM_W := 20
const ROOM_H := 14


## A room: a packed-earth floor and solid walls. Interiors are small by design —
## one screen, no camera hunting for the door.
static func paint_interior(layer: TileMapLayer, collision_parent: Node2D,
		room_w: int = ROOM_W, room_h: int = ROOM_H) -> void:
	var pack := pack_layer(layer, PACK_PATH_GRASS)
	if pack.is_valid():
		# All "lower" is the packed-dirt terrain — it reads as a floor indoors
		# and needs no transitions.
		var floor_coords := pack.all_lower()
		for y in range(room_h):
			for x in range(room_w):
				layer.set_cell(Vector2i(x, y), 0, floor_coords)

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


# --------------------------------------------------------------------- lake

const LAKE_W := 44
const LAKE_H := 32


## The lake shore (Part 14 §2: farm/village -> forest -> LAKE, where Jonas is).
##
## Grass on the west, open water filling the east, divided by a shoreline that
## runs roughly north-south and wanders. Deliberately NOT a pond in a field:
## the player should arrive at a bank and see water reach the far edge, so the
## lake reads as somewhere the world continues rather than a decorated pool.
static func lake_is_water(x: int, y: int) -> bool:
	var shore: float = 17.0 \
		+ sin(float(y) * 0.19) * 3.6 \
		+ sin(float(y) * 0.43 + 1.7) * 1.8
	if float(x) > shore:
		return true
	# A couple of inlets biting into the bank, so the shore is not a single curve.
	return in_pond(x, y, 12.0, 8.0, 3.4, 7) or in_pond(x, y, 10.0, 24.0, 2.8, 13)


static func paint_lake(layer: TileMapLayer, water: TileMapLayer = null,
		collision_parent: Node2D = null) -> void:
	# Base: grass and the worn track along the bank.
	var pack := pack_layer(layer, PACK_PATH_GRASS)
	if not pack.is_valid():
		return
	var is_grass := func(x: int, y: int) -> bool:
		if lake_is_water(x, y):
			return true          # water draws on its own layer above
		var bank_track: bool = on_v_path(x, y, 8, 2, LAKE_H - 2, 23)
		return not (bank_track or on_scuff(x, y))
	pack.paint(layer, 0, LAKE_W, LAKE_H, is_grass)

	if water == null:
		return
	var pond := pack_layer(water, PACK_GRASS_WATER)
	if not pond.is_valid():
		return
	var is_bank := func(x: int, y: int) -> bool: return not lake_is_water(x, y)
	for y in range(LAKE_H):
		for x in range(LAKE_W):
			var nw: bool = is_bank.call(x, y)
			var ne: bool = is_bank.call(x + 1, y)
			var sw: bool = is_bank.call(x, y + 1)
			var se: bool = is_bank.call(x + 1, y + 1)
			if nw and ne and sw and se:
				continue        # pure grass: leave the layer transparent
			var cell := Vector2i(x, y)
			water.set_cell(cell, 0, pond.atlas_for(ne, nw, se, sw, cell))

	if collision_parent != null:
		build_water_collision(collision_parent, LAKE_W, LAKE_H, lake_is_water)
