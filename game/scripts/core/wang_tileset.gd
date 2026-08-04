extends RefCounted
class_name WangTileset
## Corner-based Wang autotiling, driven by the PixelLab `.tiles.json` sidecars.
##
## Each pack is a 4x4 atlas of the 16 corner combinations between two terrains,
## `lower` and `upper`. A cell's tile is chosen by which of its four CORNERS are
## upper — corners, not edges, which is why soil can meet grass diagonally
## without a seam.
##
## Reading the sidecar rather than hardcoding the atlas order means regenerating
## a tileset in PixelLab cannot silently shuffle the terrain under the map.

const TILE := 16

var texture: Texture2D
var lower_name: String = ""
var upper_name: String = ""
## corner key -> Array[Vector2i] of interchangeable atlas coords.
##
## VARIANTS are why the ground stops reading as wallpaper. One tile per
## combination tiles visibly; several, picked by a stable hash of the cell,
## give the irregular look of painted ground and still redraw identically.
var _by_corners: Dictionary = {}
var _loaded: bool = false


static func load_pack(base_path: String) -> WangTileset:
	var pack := WangTileset.new()
	pack._load(base_path)
	return pack


func _load(base_path: String) -> void:
	var png := base_path + ".png"
	var json_path := base_path + ".tiles.json"
	if not ResourceLoader.exists(png):
		push_error("WangTileset: missing texture %s" % png)
		return
	texture = load(png)

	if not FileAccess.file_exists(json_path):
		push_error("WangTileset: missing sidecar %s" % json_path)
		return
	var file := FileAccess.open(json_path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("WangTileset: %s is not a JSON object" % json_path)
		return

	var data: Dictionary = parsed
	lower_name = str(data.get("lower", ""))
	upper_name = str(data.get("upper", ""))

	for entry in data.get("tiles", []):
		var corners: Dictionary = entry.get("corners", {})
		var coords: Array = entry.get("atlas_coords", [0, 0])
		var variants: Array[Vector2i] = []
		var listed: Variant = entry.get("variants")
		if listed is Array and (listed as Array).size() > 0:
			for v in listed:
				variants.append(Vector2i(int(v[0]), int(v[1])))
		else:
			variants.append(Vector2i(int(coords[0]), int(coords[1])))
		_by_corners[_key(
			corners.get("NE", "lower") == "upper",
			corners.get("NW", "lower") == "upper",
			corners.get("SE", "lower") == "upper",
			corners.get("SW", "lower") == "upper")] = variants
	# A hand-painted reference will not contain every combination (the two
	# diagonal-opposite cases barely occur in organic terrain), so a pack is
	# valid as long as the solid cases exist and the rest can fall back.
	_loaded = _by_corners.has(_key(false, false, false, false)) \
		and _by_corners.has(_key(true, true, true, true))


func is_valid() -> bool:
	return _loaded


static func _key(ne: bool, nw: bool, se: bool, sw: bool) -> int:
	return (int(ne) << 3) | (int(nw) << 2) | (int(se) << 1) | int(sw)


## Atlas coords for a cell whose four corners are upper/lower.
## `cell` seeds the variant choice, so the same cell always draws the same tile.
func atlas_for(ne: bool, nw: bool, se: bool, sw: bool,
		cell: Vector2i = Vector2i.ZERO) -> Vector2i:
	var variants: Variant = _by_corners.get(_key(ne, nw, se, sw))
	if not (variants is Array) or (variants as Array).is_empty():
		variants = _nearest(ne, nw, se, sw)
	var list: Array = variants
	if list.is_empty():
		return Vector2i.ZERO
	# A stable hash of the cell — deterministic, but with no visible period.
	var pick: int = abs(int(hash(Vector2i(cell.x * 73856093, cell.y * 19349663)))) % list.size()
	return list[pick]


## The reference may not contain a given combination. Fall back to the closest
## one it does have (fewest corners different) rather than dropping to tile 0,
## which would punch a hole of the wrong terrain into the map.
func _nearest(ne: bool, nw: bool, se: bool, sw: bool) -> Array:
	var want := [ne, nw, se, sw]
	var best: Array = []
	var best_distance := 99
	for key in _by_corners:
		var have := [
			bool(key & 8), bool(key & 4), bool(key & 2), bool(key & 1)]
		var distance := 0
		for i in range(4):
			if have[i] != want[i]:
				distance += 1
		if distance < best_distance:
			best_distance = distance
			best = _by_corners[key]
	return best


## Fully-lower and fully-upper tiles, for filling open ground.
func all_lower(cell: Vector2i = Vector2i.ZERO) -> Vector2i:
	return atlas_for(false, false, false, false, cell)


func all_upper(cell: Vector2i = Vector2i.ZERO) -> Vector2i:
	return atlas_for(true, true, true, true, cell)


func make_source() -> TileSetAtlasSource:
	var source := TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = Vector2i(TILE, TILE)
	for variants in _by_corners.values():
		for coords in variants:
			if not source.has_tile(coords):
				source.create_tile(coords)
	return source


## Paint `layer` with this pack, using `is_upper` to decide each CORNER.
##
## `is_upper` is called with corner coordinates, one more than the tile grid in
## each axis: corner (x, y) is the top-left corner of tile (x, y).
func paint(layer: TileMapLayer, source_id: int, width: int, height: int,
		is_upper: Callable) -> void:
	for y in range(height):
		for x in range(width):
			var nw: bool = is_upper.call(x, y)
			var ne: bool = is_upper.call(x + 1, y)
			var sw: bool = is_upper.call(x, y + 1)
			var se: bool = is_upper.call(x + 1, y + 1)
			var cell := Vector2i(x, y)
			layer.set_cell(cell, source_id, atlas_for(ne, nw, se, sw, cell))
