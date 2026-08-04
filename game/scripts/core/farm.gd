extends Node2D
## Gray-box farm + Q02 host. GDD Part 10 §6 Weeks 1–2.
##
## Week 1 acceptance: walk the farm, interact with the cow, sleep, day persists.
## Week 2 acceptance: Q02 playable end-to-end from YAML with a pointing gesture.

const SPAWN := Vector2(384, 336)
const START_QUEST := "q02"

@onready var _player: CharacterBody2D = $Player
@onready var _dialogue: CanvasLayer = $DialogueRunner
@onready var _hud_day: Label = $HUD/Root/Day
@onready var _hud_clock: Label = $HUD/Root/Clock
@onready var _hud_hint: Label = $HUD/Root/Hint
@onready var _hud_carry: Label = $HUD/Root/Carry
@onready var _night: CanvasModulate = $NightTint

var _quest := StoryQuestRunner.new()


func _ready() -> void:
	WorldBuilder.paint_ground($Ground)
	WorldBuilder.build_fence($Fence, self)

	# A Control written into .tscn without layout_mode keeps a zero size,
	# so give the HUD root its full-rect layout in code.
	$HUD/Root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_player.global_position = GameState.consume_spawn_position(SPAWN)
	_clamp_camera_to_farm()

	# Register every pointable object under the id content uses (obj_cow …),
	# so a gesture authored in YAML can reach a sprite.
	for node in get_tree().get_nodes_in_group("world_object"):
		if node.object_id != "":
			_dialogue.register_target(node.object_id, node)
		node.interacted.connect(_on_world_object)

	for node in get_tree().get_nodes_in_group("interactable"):
		node.interacted.connect(_on_interactable)

	add_child(_quest)
	_quest.setup(_dialogue)
	_quest.quest_completed.connect(_on_quest_completed)

	DayCycle.time_changed.connect(_on_time_changed)

	_refresh_hud()
	_on_time_changed(DayCycle.hour)
	print("[farm] ready — day %d, spawn %s" % [GameState.day, _player.global_position])

	if not GameState.completed_quests.has(START_QUEST):
		_quest.start(START_QUEST)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		_on_interact_pressed()

	# Week 1 placeholder: push-to-talk is wired to prove the binding exists.
	# Real mic capture + Azure PA arrive Week 5 (Part 10 §6).
	if event.is_action_pressed("push_to_talk"):
		_hud_hint.text = "[push-to-talk held — mic arrives Week 5]"
	if event.is_action_released("push_to_talk"):
		_hud_hint.text = _default_hint()

	if event.is_action_pressed("debug_screenshot"):
		_save_screenshot()


func _on_interact_pressed() -> void:
	var target: Node = _player.current_interactable()
	if target != null:
		target.interact()
		return
	# Nothing in reach: E advances the open line.
	if _dialogue.is_open:
		_dialogue.close()


## The player acted on a world object. Route it through the Tier I objective so
## a wrong choice (the pig, not the cow) is judged as a comprehension miss.
func _on_world_object(who: WorldObject) -> void:
	if who.is_pickup:
		GameState.carrying = who.grants_item
		_refresh_hud()
		print("[farm] picked up %s" % who.grants_item)
		return

	if who.action == "":
		return

	if who.requires_item != "" and GameState.carrying != who.requires_item:
		# Right object, missing item — play the hint line rather than fail them.
		var step: Dictionary = _quest.current_step()
		var hint: String = step.get("hint_line", "")
		if hint != "" and not _dialogue.is_open:
			_dialogue.play_line(hint)
		return

	var correct: bool = _dialogue.submit_action(who.action, who.object_id, GameState.carrying)
	if correct and who.requires_item != "":
		GameState.carrying = ""
		_refresh_hud()


func _on_interactable(who: Interactable) -> void:
	if who.is_bed:
		_sleep()
		return
	_dialogue.play_line(who.placeholder_line)


func _on_quest_completed(quest_id: String, rewards: Dictionary) -> void:
	GameState.complete_quest(quest_id, rewards)
	_refresh_hud()


func _sleep() -> void:
	GameState.sleep(SPAWN)
	_player.global_position = SPAWN
	_refresh_hud()


func _on_time_changed(_hour: float) -> void:
	_hud_clock.text = DayCycle.clock_string()
	# CanvasModulate multiplies the world canvas; CanvasLayers (HUD, dialogue)
	# are unaffected, so UI stays readable after dark.
	var d := DayCycle.darkness()
	_night.color = Color(1.0, 1.0, 1.0).lerp(Color(0.24, 0.28, 0.55), d)


func _refresh_hud() -> void:
	_hud_day.text = "Day %d   rep %d" % [GameState.day, GameState.reputation]
	_hud_hint.text = _default_hint()
	if GameState.carrying == "":
		_hud_carry.text = ""
	else:
		# Carried item is shown by its German lemma from content, never a
		# hardcoded string — this label is the player's first passive exposure.
		var word := ContentDB.get_word(GameState.carrying)
		_hud_carry.text = "%s %s" % [word.get("article", ""), word.get("lemma", "")]


## Stop the camera at the fence line so the void outside never comes into view.
func _clamp_camera_to_farm() -> void:
	var camera: Camera2D = _player.get_node("Camera2D")
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = WorldBuilder.FARM_W * WorldBuilder.TILE
	camera.limit_bottom = WorldBuilder.FARM_H * WorldBuilder.TILE


func _default_hint() -> String:
	return "WASD/arrows move   E interact   Space push-to-talk   F5 screenshot"


func _save_screenshot() -> void:
	var image := get_viewport().get_texture().get_image()
	var path := "user://screenshot.png"
	image.save_png(path)
	print("[shot] %s" % ProjectSettings.globalize_path(path))


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		GameState.save_state()
