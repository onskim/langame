extends CharacterBody2D
## Player movement + facing + interaction probe. GDD Part 10 §6 Week 1.

const SPEED := 60.0
const FRAME_TIME := 0.14

enum Facing { DOWN, UP, LEFT, RIGHT }

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _interact_area: Area2D = $InteractArea

var facing: int = Facing.DOWN
var _frame: int = 0
var _frame_timer: float = 0.0
var can_move: bool = true


func _physics_process(delta: float) -> void:
	var input := Vector2.ZERO
	if can_move:
		input.x = Input.get_axis("move_left", "move_right")
		input.y = Input.get_axis("move_up", "move_down")
		input = input.normalized()

	velocity = input * SPEED
	move_and_slide()

	if input != Vector2.ZERO:
		_update_facing(input)
		_advance_walk_cycle(delta)
	else:
		_frame = 0
		_frame_timer = 0.0

	_apply_frame()
	GameState.player_position = global_position
	_orient_interact_area()


func _update_facing(input: Vector2) -> void:
	if abs(input.x) > abs(input.y):
		facing = Facing.RIGHT if input.x > 0.0 else Facing.LEFT
	else:
		facing = Facing.DOWN if input.y > 0.0 else Facing.UP


func _advance_walk_cycle(delta: float) -> void:
	_frame_timer += delta
	if _frame_timer >= FRAME_TIME:
		_frame_timer -= FRAME_TIME
		_frame = (_frame + 1) % 4


func _apply_frame() -> void:
	# Sheet is 4 columns (frames) x 4 rows (directions), cells of 16x32.
	_sprite.frame = facing * 4 + _frame


func _orient_interact_area() -> void:
	var offset := Vector2.ZERO
	match facing:
		Facing.DOWN: offset = Vector2(0, 12)
		Facing.UP: offset = Vector2(0, -12)
		Facing.LEFT: offset = Vector2(-12, 0)
		Facing.RIGHT: offset = Vector2(12, 0)
	_interact_area.position = offset


## Nearest interactable currently in range, or null.
func current_interactable() -> Node:
	for area in _interact_area.get_overlapping_areas():
		var owner_node := area.get_parent()
		if owner_node.has_method("interact"):
			return owner_node
	return null
