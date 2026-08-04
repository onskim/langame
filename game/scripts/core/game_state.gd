extends Node
## Global run state. GDD Part 10 §6 Week 1.
##
## Week 1 scope only: day counter, player spawn position, save/load wiring.
## Meters (reputation/affection/money/energy — Part 12) arrive later; do not
## widen this file ahead of the week that needs them.

signal day_advanced(day: int)
signal state_loaded()

var day: int = 1
var player_position: Vector2 = Vector2(160, 128)

var _loaded_position: Variant = null


func _ready() -> void:
	load_state()


func to_dict() -> Dictionary:
	return {
		"day": day,
		"player_x": player_position.x,
		"player_y": player_position.y,
	}


func save_state() -> void:
	SaveService.save_game(to_dict())


func load_state() -> void:
	var data := SaveService.load_game()
	if data.is_empty():
		return
	day = int(data.get("day", 1))
	if data.has("player_x") and data.has("player_y"):
		_loaded_position = Vector2(float(data["player_x"]), float(data["player_y"]))
		player_position = _loaded_position
	state_loaded.emit()


## Returns the spawn point a scene should use, consuming any loaded position.
func consume_spawn_position(default_position: Vector2) -> Vector2:
	if _loaded_position != null:
		var p: Vector2 = _loaded_position
		_loaded_position = null
		return p
	return default_position


## Bed interaction: advance the day, reset the clock, autosave.
func sleep(spawn_position: Vector2) -> void:
	day += 1
	player_position = spawn_position
	DayCycle.reset_to_morning()
	save_state()
	day_advanced.emit(day)
	print("[state] slept -> day %d" % day)
