extends Node2D
class_name WorldMap
## Shared behaviour for every playable map (farm, village, later forest/lake).
## GDD Part 14 §2.
##
## Subclasses supply their own ground and props; everything common — player
## spawn, camera clamp, NPC population from schedules, HUD, phone, dialogue,
## quests, day/night — lives here so a new map is a scene, not a system.

@export var map_id: String = ""
@export var map_width_tiles: int = 56
@export var map_height_tiles: int = 40
@export var default_spawn: Vector2 = Vector2(384, 336)

@onready var _player: CharacterBody2D = $Player
@onready var _dialogue: CanvasLayer = $DialogueRunner
@onready var _phone: CanvasLayer = $Phone
@onready var _hud_day: Label = $HUD/Root/Day
@onready var _hud_clock: Label = $HUD/Root/Clock
@onready var _hud_hint: Label = $HUD/Root/Hint
@onready var _hud_carry: Label = $HUD/Root/Carry
@onready var _hud_task: Label = $HUD/Root/Task
@onready var _hud_place: Label = $HUD/Root/Place
@onready var _night: CanvasModulate = $NightTint

var quests := QuestEngine.new()

var _locations: Dictionary = {}
const NPC_SCENE := preload("res://scenes/actors/npc.tscn")

## Placeholder tints so the cast is distinguishable before real sprites exist.
const NPC_TINTS := {
	"npc_anna": Color(1, 0.85, 0.85),
	"npc_karl": Color(0.82, 0.88, 1),
	"npc_petra": Color(1, 0.95, 0.72),
	"npc_weber": Color(0.78, 1, 0.85),
	"npc_mila": Color(0.92, 0.8, 1),
}


func _ready() -> void:
	WorldRouter.current_map = map_id
	GameState.current_map = map_id

	build_ground()

	$HUD/Root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_collect_locations()
	_spawn_player()
	_clamp_camera()

	for node in get_tree().get_nodes_in_group("world_object"):
		if node.object_id != "":
			_dialogue.register_target(node.object_id, node)
		node.interacted.connect(_on_world_object)

	for node in get_tree().get_nodes_in_group("interactable"):
		node.interacted.connect(_on_interactable)

	add_child(quests)
	quests.setup(_dialogue)
	quests.quest_completed.connect(_on_quest_completed)
	quests.step_advanced.connect(func(_q: String, _i: int) -> void: _refresh_hud())
	quests.objective_progress.connect(func(_q: String, _d: int, _n: int) -> void: _refresh_hud())

	_phone.setup(quests)
	DayCycle.time_changed.connect(_on_time_changed)

	populate_npcs()

	_refresh_hud()
	_on_time_changed(DayCycle.hour)
	print("[map] %s ready — day %d, %d NPC(s) present"
		% [map_id, GameState.day, get_tree().get_nodes_in_group("npc").size()])

	quests.start_next_available()


## Subclasses override to paint their own terrain.
func build_ground() -> void:
	pass


func _collect_locations() -> void:
	if not has_node("Locations"):
		return
	for marker in $Locations.get_children():
		_locations[marker.name] = marker.global_position


func _spawn_player() -> void:
	var arrival := WorldRouter.consume_arrival()
	if arrival != "" and has_node("Arrivals/" + arrival):
		_player.global_position = get_node("Arrivals/" + arrival).global_position
	else:
		_player.global_position = GameState.consume_spawn_position(default_spawn)
	_player.add_to_group("player")


## Spawn exactly the NPCs content says are on this map right now. The rest of
## the cast is not simulated here — the village stays alive without paying for
## two maps of physics.
func populate_npcs() -> void:
	for npc_id in WorldRouter.npcs_on_map(map_id, DayCycle.hour):
		var npc: NPC = NPC_SCENE.instantiate()
		npc.npc_id = npc_id
		npc.placeholder_tint = NPC_TINTS.get(npc_id, Color.WHITE)
		var location := WorldRouter.scheduled_location(npc_id, DayCycle.hour)
		npc.position = _locations.get(location, default_spawn)
		$NPCs.add_child(npc)
		npc.set_locations(_locations)


## An NPC whose schedule moves them off this map walks away and despawns; one
## scheduled onto it appears. Handled on the hour rather than per frame.
func _resync_npcs() -> void:
	var should_be_here := WorldRouter.npcs_on_map(map_id, DayCycle.hour)
	var present: Dictionary = {}
	for node in $NPCs.get_children():
		present[node.npc_id] = node
		if not should_be_here.has(node.npc_id):
			node.queue_free()
	for npc_id in should_be_here:
		if present.has(npc_id):
			continue
		var npc: NPC = NPC_SCENE.instantiate()
		npc.npc_id = npc_id
		npc.placeholder_tint = NPC_TINTS.get(npc_id, Color.WHITE)
		npc.position = _locations.get(WorldRouter.scheduled_location(npc_id, DayCycle.hour),
			default_spawn)
		$NPCs.add_child(npc)
		npc.set_locations(_locations)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("phone"):
		_phone.toggle()
		_player.can_move = not _phone.is_open
		return
	if _phone.is_open:
		return

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
	if _dialogue.is_open:
		_dialogue.close()


func _on_world_object(who: WorldObject) -> void:
	if who.is_pickup:
		GameState.carrying = who.grants_item
		_refresh_hud()
		print("[map] picked up %s" % who.grants_item)
		return

	if who.action == "":
		return

	if who.requires_item != "" and GameState.carrying != who.requires_item:
		var hint: String = quests.current_step().get("hint_line", "")
		if hint != "" and not _dialogue.is_open:
			_dialogue.play_line(hint)
		return

	var correct: bool = _dialogue.submit_action(who.action, who.object_id, GameState.carrying)
	if correct and who.requires_item != "" and who.consumes_item:
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
	quests.start_next_available()


func _sleep() -> void:
	GameState.sleep(default_spawn)
	_player.global_position = default_spawn
	_resync_npcs()
	_refresh_hud()


func _on_time_changed(_hour: float) -> void:
	_hud_clock.text = DayCycle.clock_string()
	var d := DayCycle.darkness()
	_night.color = Color(1.0, 1.0, 1.0).lerp(Color(0.24, 0.28, 0.55), d)
	for npc in get_tree().get_nodes_in_group("npc"):
		npc.on_time_changed(DayCycle.hour)


func _refresh_hud() -> void:
	_hud_day.text = "Day %d   rep %d" % [GameState.day, GameState.reputation]
	_hud_hint.text = _default_hint()
	_hud_task.text = quests.active_task_label()
	_hud_place.text = WorldRouter.display_name(map_id)
	if GameState.carrying == "":
		_hud_carry.text = ""
	else:
		var word := ContentDB.get_word(GameState.carrying)
		_hud_carry.text = "%s %s" % [word.get("article", ""), word.get("lemma", "")]


func _clamp_camera() -> void:
	var camera: Camera2D = _player.get_node("Camera2D")
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = map_width_tiles * WorldBuilder.TILE
	camera.limit_bottom = map_height_tiles * WorldBuilder.TILE


func _default_hint() -> String:
	return "WASD move   E interact   TAB phone   Space talk   F5 shot"


func _save_screenshot() -> void:
	var image := get_viewport().get_texture().get_image()
	image.save_png("user://screenshot.png")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		GameState.save_state()
