extends WorldMap
## The player's farm — the PRIVATE space (GDD Part 14 §2).
##
## Labour, quiet, no NPCs except Anna next door. Nothing social happens here:
## that is the point. Going to the village has to be a choice with a reason.

const GROWTH_SHEET := preload("res://assets/sprites/crop_growth.png")

## One sprite per planted plot, keyed by cell. Rebuilt FROM the simulation
## rather than tracked alongside it: a second source of truth about what is
## growing where would drift the moment a night is simulated off-screen.
var _crop_sprites: Dictionary = {}


func build_ground() -> void:
	WorldBuilder.paint_ground($Ground, $Crops, $Water, self)
	WorldBuilder.build_fence($Fence, self, WorldBuilder.GateSide.EAST)


func _ready() -> void:
	super()
	if not Farm.plot_changed.is_connected(_on_plot_changed):
		Farm.plot_changed.connect(_on_plot_changed)
	repaint_crops()


func _on_plot_changed(_cell: Vector2i) -> void:
	repaint_crops()


## Draw every plot at its current growth stage. Dead plots go grey and wilted
## ones go yellow — the field must be readable at a glance from across the farm,
## because looking at it is how the player decides what their day is for.
func repaint_crops() -> void:
	var layer := get_node_or_null("CropSprites")
	if layer == null:
		return

	for cell in _crop_sprites.keys():
		if not Farm.is_planted(cell):
			(_crop_sprites[cell] as Node).queue_free()
			_crop_sprites.erase(cell)

	for key in Farm.plots:
		var parts := str(key).split(",")
		if parts.size() != 2:
			continue
		var cell := Vector2i(int(parts[0]), int(parts[1]))
		var sprite: Sprite2D = _crop_sprites.get(cell)
		if sprite == null:
			sprite = Sprite2D.new()
			sprite.texture = GROWTH_SHEET
			sprite.hframes = 5
			sprite.position = Vector2(cell) * WangTileset.TILE \
				+ Vector2(WangTileset.TILE, WangTileset.TILE) * 0.5
			layer.add_child(sprite)
			_crop_sprites[cell] = sprite
		sprite.frame = clampi(Farm.stage_of(cell), 0, 4)
		if Farm.is_dead(cell):
			sprite.modulate = Color(0.45, 0.40, 0.34)
		elif Farm.is_wilted(cell):
			sprite.modulate = Color(0.80, 0.72, 0.36)
		elif Farm.is_ready(cell):
			# Ripe reads slightly warmer, so "what can I pick today" is
			# answerable without walking the whole field.
			sprite.modulate = Color(1.10, 1.02, 0.90)
		else:
			sprite.modulate = Color.WHITE
