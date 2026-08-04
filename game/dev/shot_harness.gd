extends Node
## Screenshot harness — drives the farm scene through the Week 1 acceptance
## beats and writes a PNG at each one, so the founder can verify visually
## without playing through it.
##
## Run windowed (NOT --headless; headless renders nothing):
##   godot --path game --resolution 1280x720 res://dev/shot_harness.tscn
##
## Dev tooling only. Never shipped.

const OUT_DIR := "user://shots"

var _farm: Node2D
var _shots: Array[String] = []


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_farm = load("res://scenes/world/farm.tscn").instantiate()
	add_child(_farm)
	await get_tree().process_frame
	_run()


func _run() -> void:
	var player: CharacterBody2D = _farm.get_node("Player")
	var cow: Node2D = _farm.get_node("Cow")
	var bed: Node2D = _farm.get_node("Bed")

	# --- 1. morning on the farm -------------------------------------------
	player.global_position = Vector2(384, 330)
	await _settle(20)
	await _shoot("01-farm-morning")

	# --- 2. walk to the cow and interact ----------------------------------
	player.global_position = cow.global_position + Vector2(-26, 4)
	player.facing = 3  # RIGHT
	await _settle(15)
	await _shoot("02-approach-cow")

	cow.interact()
	await _settle(6)
	await _shoot("03-cow-dialogue")

	_farm.get_node("DialogueBox").close()
	await _settle(4)

	# --- 3. day/night curve: noon (no tint) vs late night (deep tint) ------
	# NOTE: 06:00 and 21:30 sit at nearly equal darkness on the curve, so
	# comparing those two proves nothing. Noon vs 23:30 is the real test.
	player.global_position = Vector2(384, 330)
	await _set_hour(12.0)
	await _shoot("04a-noon")
	await _set_hour(23.5)
	await _shoot("04b-night")

	# --- 4. sleep in the bed -> day advances, autosave ---------------------
	player.global_position = bed.global_position + Vector2(0, 24)
	await _settle(8)
	bed.interact()
	await _settle(8)
	await _shoot("05-slept-day2")

	print("[harness] shots written to %s" % ProjectSettings.globalize_path(OUT_DIR))
	print("[harness] day is now %d, save at %s" % [GameState.day, SaveService.absolute_path()])
	get_tree().quit()


## Freeze the clock at a given hour so a shot is deterministic.
func _set_hour(hour: float) -> void:
	DayCycle.running = false
	DayCycle.hour = hour
	DayCycle.time_changed.emit(hour)
	await _settle(6)


func _settle(frames: int) -> void:
	for i in range(frames):
		await get_tree().process_frame


func _shoot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, name]
	var err := image.save_png(path)
	if err != OK:
		printerr("[harness] failed to save %s (%d)" % [path, err])
		return
	_shots.append(path)
	print("[harness] %s  %dx%d" % [name, image.get_width(), image.get_height()])
