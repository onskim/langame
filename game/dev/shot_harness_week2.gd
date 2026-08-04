extends Node
## Week 2 screenshot harness — captures the Q02 beats for founder verification.
##
##   godot --resolution 1280x720 res://dev/shot_harness_week2.tscn
##
## Dev tooling only. Never shipped.

const OUT_DIR := "user://shots2"

var _farm: Node2D


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_farm = load("res://scenes/world/farm.tscn").instantiate()
	add_child(_farm)
	await get_tree().process_frame
	await _run()


func _run() -> void:
	var player: CharacterBody2D = _farm.get_node("Player")
	var runner: CanvasLayer = _farm.get_node("DialogueRunner")
	var cow: Node2D = _farm.get_node("Cow")
	var pig: Node2D = _farm.get_node("Pig")
	var hay: Node2D = _farm.get_node("Hay")

	DayCycle.running = false
	DayCycle.hour = 9.0
	DayCycle.time_changed.emit(9.0)

	# 1. Anna asks in German and points at the cow.
	player.global_position = Vector2(560, 330)
	await _settle(24)
	await _shoot("11-q02-ask-with-gesture")

	# 2. Wrong action: feed the pig -> diegetic recast, no punishment.
	GameState.carrying = "heu"
	runner.submit_action("feed", "obj_pig", "heu")
	await _settle(8)
	await _shoot("12-wrong-action-recast")

	# 3. Carry the hay (HUD shows the German lemma, article-coloured).
	GameState.carrying = ""
	hay.interact()
	await _settle(8)
	await _shoot("13-carrying-heu")

	# 4. Feed the cow -> quest advances to the thank-you line.
	player.global_position = cow.global_position + Vector2(-28, 2)
	cow.interact()
	await _settle(10)
	await _shoot("14-q02-complete")

	print("[harness] shots -> %s" % ProjectSettings.globalize_path(OUT_DIR))
	print("[harness] rep=%d money=%d done=%s"
		% [GameState.reputation, GameState.money, GameState.completed_quests])
	get_tree().quit()


func _settle(frames: int) -> void:
	for i in range(frames):
		await get_tree().process_frame


func _shoot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png("%s/%s.png" % [OUT_DIR, name])
	if err != OK:
		printerr("[harness] failed to save %s (%d)" % [name, err])
		return
	print("[harness] %s" % name)
