extends Node
## Week 4 screenshots: phone apps, pets, day-end card.
const OUT_DIR := "user://shots_w4"

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	DayCycle.running = false
	DayCycle.hour = 10.0
	var farm: Node2D = load("res://scenes/world/farm.tscn").instantiate()
	add_child(farm)
	for i in range(40): await get_tree().physics_frame
	var player: CharacterBody2D = farm.get_node("Player")
	player.global_position = Vector2(400, 340)
	for i in range(90): await get_tree().physics_frame
	await _shoot("41-pets-follow")

	for pet: Pet in get_tree().get_nodes_in_group("pet"):
		pet.obey("sitz")
	for i in range(20): await get_tree().physics_frame
	await _shoot("42-pets-sitz")

	# seed some vocabulary so Wörter has content
	for w in ["kuh", "heu", "fuettern", "hund", "katze", "regen", "sonne", "brot", "ei"]:
		WordStats.introduce(w, 1)
		WordStats.get_stat(w)["times_seen"] = 4
	WordStats.get_stat("kuh")["due_day"] = 1
	Phone.open_app("words"); Phone.open()
	for i in range(12): await get_tree().physics_frame
	await _shoot("43-phone-woerter")

	Phone.open_app("weather")
	for i in range(12): await get_tree().physics_frame
	await _shoot("44-phone-wetter")

	Phone.open_app("map")
	for i in range(12): await get_tree().physics_frame
	await _shoot("45-phone-karte")
	Phone.close()

	DayEndCard.begin_day(1)
	for w in ["kuh", "heu", "hund", "regen"]:
		DayEndCard.note_word(w)
	GameState.add_reputation("npc_anna", 4)
	DayEndCard.show_card()
	for i in range(14): await get_tree().physics_frame
	await _shoot("46-day-end-card")

	print("[harness] done")
	get_tree().quit()

func _shoot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [OUT_DIR, name])
	print("[harness] %s" % name)
