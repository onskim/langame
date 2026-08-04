extends Node2D
## Gray-box farm. GDD Part 10 §6 Week 1 acceptance:
## walk the farm, interact with the cow, sleep, day counter survives relaunch.

const SPAWN := Vector2(384, 336)

@onready var _player: CharacterBody2D = $Player
@onready var _dialogue: CanvasLayer = $DialogueBox
@onready var _hud_day: Label = $HUD/Root/Day
@onready var _hud_clock: Label = $HUD/Root/Clock
@onready var _hud_hint: Label = $HUD/Root/Hint
@onready var _night: CanvasModulate = $NightTint


func _ready() -> void:
	WorldBuilder.paint_ground($Ground)
	WorldBuilder.build_fence($Fence, self)

	# A Control written into .tscn without layout_mode keeps a zero size,
	# so give the HUD root its full-rect layout in code.
	$HUD/Root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_player.global_position = GameState.consume_spawn_position(SPAWN)
	_clamp_camera_to_farm()

	for node in get_tree().get_nodes_in_group("interactable"):
		node.interacted.connect(_on_interacted)

	DayCycle.time_changed.connect(_on_time_changed)
	_dialogue.closed.connect(func() -> void: _player.can_move = true)

	_refresh_hud()
	_on_time_changed(DayCycle.hour)
	print("[farm] ready — day %d, spawn %s" % [GameState.day, _player.global_position])


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		if _dialogue.is_open:
			_dialogue.close()
		else:
			var target: Node = _player.current_interactable()
			if target != null:
				target.interact()

	# Week 1 placeholder: push-to-talk is wired to prove the binding exists.
	# Real mic capture + Azure PA arrive Week 5 (Part 10 §6).
	if event.is_action_pressed("push_to_talk"):
		_hud_hint.text = "[push-to-talk held — mic arrives Week 5]"
	if event.is_action_released("push_to_talk"):
		_hud_hint.text = _default_hint()

	if event.is_action_pressed("debug_screenshot"):
		_save_screenshot()


func _on_interacted(who: Interactable) -> void:
	if who.is_bed:
		_sleep()
		return
	_player.can_move = false
	_dialogue.show_line(who.speaker_name, who.placeholder_line)


func _sleep() -> void:
	GameState.sleep(SPAWN)
	_player.global_position = SPAWN
	_refresh_hud()
	_dialogue.show_line("", "You slept. Day %d. (saved)" % GameState.day)
	_player.can_move = false


func _on_time_changed(hour: float) -> void:
	_hud_clock.text = DayCycle.clock_string()
	# CanvasModulate multiplies the world canvas; CanvasLayers (HUD, dialogue)
	# are unaffected, so UI stays readable after dark.
	var d := DayCycle.darkness()
	_night.color = Color(1.0, 1.0, 1.0).lerp(Color(0.24, 0.28, 0.55), d)


func _refresh_hud() -> void:
	_hud_day.text = "Day %d" % GameState.day
	_hud_hint.text = _default_hint()


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
