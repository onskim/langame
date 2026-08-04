extends CharacterBody2D
class_name NPC
## ONE generic NPC scene for the whole cast (GDD Part 10 §2: "ONE generic NPC
## scene"). Everything that distinguishes Anna from Karl — name, schedule, tint,
## voice — comes from content. Adding the 16th villager must not add a scene.

const SPEED := 34.0
const ARRIVE_EPSILON := 3.0

@export var npc_id: String = ""
## Placeholder tint so the cast is distinguishable before real sprites exist.
@export var placeholder_tint: Color = Color.WHITE

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _label: Label = $Name

var data: Dictionary = {}
var current_location: String = ""

var _destination: Vector2 = Vector2.ZERO
var _has_destination: bool = false
var _locations: Dictionary = {}
var _frame: int = 0
var _frame_timer: float = 0.0
var _facing: int = 0


func _ready() -> void:
	add_to_group("npc")
	data = ContentDB.get_npc(npc_id)
	if data.is_empty():
		push_error("NPC: unknown npc_id '%s' — is it in content/npcs/?" % npc_id)
	_label.text = data.get("name", npc_id)
	_sprite.modulate = placeholder_tint


## The world scene tells each NPC where the named places are.
func set_locations(locations: Dictionary) -> void:
	_locations = locations
	_apply_schedule(DayCycle.hour, true)


## Where should this NPC be at `hour`? "" if the schedule does not say.
func location_at(hour: float) -> String:
	var schedule: Variant = data.get("schedule")
	if not (schedule is Array):
		return ""
	for window in schedule:
		var from_h := _parse_hour(window.get("from", "00:00"))
		var to_h := _parse_hour(window.get("to", "24:00"))
		if hour >= from_h and hour < to_h:
			return window.get("at", "")
	return ""


static func _parse_hour(text: String) -> float:
	var parts := text.split(":")
	if parts.size() != 2:
		return 0.0
	return float(parts[0]) + float(parts[1]) / 60.0


func on_time_changed(hour: float) -> void:
	_apply_schedule(hour, false)


func _apply_schedule(hour: float, teleport: bool) -> void:
	var target_name := location_at(hour)
	if target_name == "" or target_name == current_location:
		return
	if not _locations.has(target_name):
		# A schedule naming a place that does not exist yet is a content bug,
		# but it must not strand the NPC or spam every frame.
		push_warning("NPC %s scheduled at unknown location '%s'" % [npc_id, target_name])
		current_location = target_name
		return

	current_location = target_name
	_destination = _locations[target_name]
	_has_destination = true
	if teleport:
		global_position = _destination
		_has_destination = false


func _physics_process(delta: float) -> void:
	if not _has_destination:
		velocity = Vector2.ZERO
		_frame = 0
		_apply_frame()
		return

	var to_target := _destination - global_position
	if to_target.length() <= ARRIVE_EPSILON:
		global_position = _destination
		_has_destination = false
		velocity = Vector2.ZERO
		_frame = 0
		_apply_frame()
		return

	var direction := to_target.normalized()
	velocity = direction * SPEED
	move_and_slide()
	_update_facing(direction)
	_advance_walk_cycle(delta)
	_apply_frame()


func _update_facing(direction: Vector2) -> void:
	if abs(direction.x) > abs(direction.y):
		_facing = 3 if direction.x > 0.0 else 2
	else:
		_facing = 0 if direction.y > 0.0 else 1


func _advance_walk_cycle(delta: float) -> void:
	_frame_timer += delta
	if _frame_timer >= 0.16:
		_frame_timer -= 0.16
		_frame = (_frame + 1) % 4


func _apply_frame() -> void:
	_sprite.frame = _facing * 4 + _frame


func is_walking() -> bool:
	return _has_destination
