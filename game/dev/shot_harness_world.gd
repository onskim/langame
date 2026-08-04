extends Node
## Screenshots of the split world for founder verification.
##   godot --resolution 1280x720 res://dev/shot_harness_world.tscn

const OUT_DIR := "user://shots_world"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	DayCycle.running = false
	await _run()
	get_tree().quit()


func _run() -> void:
	# --- the farm: private, quiet, Anna only -------------------------------
	DayCycle.hour = 9.0
	var farm: Node2D = load("res://scenes/world/farm.tscn").instantiate()
	add_child(farm)
	await _settle(20)
	var player: CharacterBody2D = farm.get_node("Player")
	player.global_position = Vector2(500, 336)
	await _settle(12)
	await _shoot("21-farm-private")

	# the gate out, east side
	player.global_position = Vector2(800, 320)
	await _settle(12)
	await _shoot("22-farm-gate-to-village")
	farm.queue_free()
	await _settle(4)

	# --- the village: social, buildings, the cast --------------------------
	var village: Node2D = load("res://scenes/world/village.tscn").instantiate()
	add_child(village)
	await _settle(20)
	var vp: CharacterBody2D = village.get_node("Player")
	vp.global_position = Vector2(368, 300)
	await _settle(180)
	await _shoot("23-village-square")

	vp.global_position = Vector2(368, 200)
	await _settle(30)
	await _shoot("24-village-shopfronts")

	# evening: Anna comes into town, lights go blue
	DayCycle.hour = 18.0
	DayCycle.time_changed.emit(18.0)
	village._resync_npcs()
	vp.global_position = Vector2(368, 300)
	await _settle(200)
	await _shoot("25-village-evening")

	print("[harness] shots -> %s" % ProjectSettings.globalize_path(OUT_DIR))


func _settle(frames: int) -> void:
	for i in range(frames):
		await get_tree().physics_frame


func _shoot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png("%s/%s.png" % [OUT_DIR, name])
	if err != OK:
		printerr("[harness] failed %s (%d)" % [name, err])
		return
	print("[harness] %s" % name)
