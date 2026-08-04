extends Node
## Screenshots of each place scene.

const OUT_DIR := "user://shots_scenes"

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	DayCycle.running = false
	DayCycle.hour = 10.0
	await _shoot_place("res://scenes/world/interiors/farmhouse.tscn", "31-interior-farmhouse", Vector2(160, 150))
	await _shoot_place("res://scenes/world/interiors/bakery.tscn", "32-interior-bakery", Vector2(160, 150))
	await _shoot_place("res://scenes/world/village.tscn", "33-village-with-doors", Vector2(368, 200))
	await _shoot_place("res://scenes/world/farm.tscn", "34-farm-player-plot", Vector2(240, 220))
	await _shoot_place("res://scenes/world/farm.tscn", "36-farm-pond", Vector2(704, 480))
	await _shoot_place("res://scenes/world/lake.tscn", "37-lake-shore", Vector2(160, 250))
	await _shoot_place("res://scenes/world/lake.tscn", "38-lake-wide", Vector2(260, 250))
	DayCycle.hour = 13.0
	await _shoot_place("res://scenes/world/farm.tscn", "35-anna-plot", Vector2(640, 180))
	print("[harness] done -> %s" % ProjectSettings.globalize_path(OUT_DIR))
	get_tree().quit()

func _shoot_place(path: String, name: String, player_at: Vector2) -> void:
	var place: Node2D = load(path).instantiate()
	add_child(place)
	for i in range(30):
		await get_tree().physics_frame
	place.get_node("Player").global_position = player_at
	for i in range(20):
		await get_tree().physics_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [OUT_DIR, name])
	print("[harness] %s" % name)
	place.queue_free()
	await get_tree().process_frame
