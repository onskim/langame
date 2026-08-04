extends Node2D
class_name WorldMap
## Base for every place the player can stand: farm, village, and each interior.
## GDD Part 14 §2–§3.
##
## A place scene owns ONLY its place — terrain, props, doors, location markers.
## Everything that outlives a place (HUD, phone, dialogue, quest state, the
## learner model) is autoloaded, so walking through a door does not rebuild the
## interface or reset the quest you are on.
##
## Adding a location is therefore a scene plus a row in content/config/world.yaml.

@export var map_id: String = ""
@export var map_width_tiles: int = 56
@export var map_height_tiles: int = 40
@export var default_spawn: Vector2 = Vector2(384, 336)
## Interiors are small and lit differently; they opt out of the outdoor clock tint.
@export var is_interior: bool = false

@onready var _player: CharacterBody2D = $Player

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
	WorldRouter.current_world = self
	GameState.current_map = map_id

	build_ground()

	_collect_locations()
	_spawn_player()
	_clamp_camera()
	_register_world_objects()

	Quests.setup(Dialogue)
	Phone.setup(Quests)
	if not Quests.quest_completed.is_connected(_on_quest_completed):
		Quests.quest_completed.connect(_on_quest_completed)
	if not Quests.step_advanced.is_connected(_on_step_advanced):
		Quests.step_advanced.connect(_on_step_advanced)

	if not DayCycle.time_changed.is_connected(_on_time_changed):
		DayCycle.time_changed.connect(_on_time_changed)

	populate_npcs()
	_bind_pets()
	_apply_light()
	HUD.refresh()

	print("[map] %s ready — day %d, %d NPC(s) present"
		% [map_id, GameState.day, get_tree().get_nodes_in_group("npc").size()])

	Quests.start_next_available()

	# Arriving somewhere is a thought. Fired last so the place is fully built —
	# a thought about the village that renders before the village does reads as
	# a loading artefact.
	Monologue.trigger("location_enter", map_id)


func _exit_tree() -> void:
	if DayCycle.time_changed.is_connected(_on_time_changed):
		DayCycle.time_changed.disconnect(_on_time_changed)


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
		return
	# A door asking for a marker this map does not have used to fall through here
	# in silence, dumping the player at the map's default spawn — you walked out
	# of your own front door and landed in the middle of the field. Every
	# interior exit had this bug. Falling back is still the right behaviour, but
	# it must never again be quiet about it.
	if arrival != "":
		push_error("[map] %s has no arrival marker '%s' — spawning at default"
			% [map_id, arrival])
	_player.global_position = GameState.consume_spawn_position(default_spawn)


func _register_world_objects() -> void:
	Dialogue.clear_targets()
	for node in get_tree().get_nodes_in_group("world_object"):
		if node.object_id != "":
			Dialogue.register_target(node.object_id, node)
		if not node.interacted.is_connected(_on_world_object):
			node.interacted.connect(_on_world_object)
	for node in get_tree().get_nodes_in_group("interactable"):
		if not node.interacted.is_connected(_on_interactable):
			node.interacted.connect(_on_interactable)


## Spawn exactly the NPCs content says are here right now. The rest of the cast
## is tracked from content without paying for their physics.
func populate_npcs() -> void:
	if not has_node("NPCs"):
		return
	for npc_id in WorldRouter.npcs_on_map(map_id, DayCycle.hour):
		_spawn_npc(npc_id)


func _spawn_npc(npc_id: String) -> void:
	var npc: NPC = NPC_SCENE.instantiate()
	npc.npc_id = npc_id
	npc.placeholder_tint = NPC_TINTS.get(npc_id, Color.WHITE)
	npc.position = _locations.get(
		WorldRouter.scheduled_location(npc_id, DayCycle.hour), default_spawn)
	$NPCs.add_child(npc)
	npc.set_locations(_locations)


## An NPC scheduled away walks off and despawns; one scheduled here appears.
func resync_npcs() -> void:
	if not has_node("NPCs"):
		return
	var should_be_here := WorldRouter.npcs_on_map(map_id, DayCycle.hour)
	var present: Dictionary = {}
	for node in $NPCs.get_children():
		present[node.npc_id] = node
		if not should_be_here.has(node.npc_id):
			node.queue_free()
	for npc_id in should_be_here:
		if not present.has(npc_id):
			_spawn_npc(npc_id)


## Pets follow whoever is playing. Addendum §10 constraint 4: commands are
## tap-input this week; Week 6 routes scored speech into the same `obey()`.
func _bind_pets() -> void:
	for pet in get_tree().get_nodes_in_group("pet"):
		pet.set_player(_player)


const PET_COMMAND_ACTIONS := {
	"pet_command_sitz": "sitz",
	"pet_command_komm": "komm",
	"pet_command_hier": "hier",
}


func _unhandled_input(event: InputEvent) -> void:
	# The day-end card owns input while it is up — it is the session ritual,
	# not something to walk away from.
	if DayEndCard.is_open:
		return

	for action in PET_COMMAND_ACTIONS:
		if event.is_action_pressed(action):
			_command_pets(PET_COMMAND_ACTIONS[action])
			return

	if event.is_action_pressed("phone"):
		Phone.toggle()
		_player.can_move = not Phone.is_open
		return
	if Phone.is_open:
		return

	if event.is_action_pressed("interact"):
		_on_interact_pressed()

	if event.is_action_pressed("debug_screenshot"):
		_save_screenshot()


func _command_pets(command_id: String) -> void:
	for pet in get_tree().get_nodes_in_group("pet"):
		pet.obey(command_id)


func _on_interact_pressed() -> void:
	# A door in reach takes priority: standing on a threshold and pressing E
	# should get you through it.
	var door := _door_in_reach()
	if door != null:
		door.use()
		return
	var target: Node = _player.current_interactable()
	if target != null:
		target.interact()
		return
	if Dialogue.is_open:
		Dialogue.close()


func _door_in_reach() -> Door:
	for node in get_tree().get_nodes_in_group("door"):
		if (node as Door).player_in_range:
			return node
	return null


func _on_world_object(who: WorldObject) -> void:
	# Looking at a thing is when a thought about it is welcome. Fires before the
	# action resolves, so the thought reads as the impulse, not the report.
	Monologue.trigger("object_examine", who.object_id)
	if who.is_pickup:
		# Pickups go into the inventory, which puts the item in hand if the
		# hands are free. Setting `carrying` directly used to mean picking up a
		# second bale replaced the first and the player owned neither.
		Inventory.add(who.grants_item, 1)
		HUD.refresh()
		print("[map] picked up %s (now %d)"
			% [who.grants_item, Inventory.count(who.grants_item)])
		return

	if who.action == "":
		return

	# --- the farm's own verbs -------------------------------------------------
	# These resolve against the simulation rather than the dialogue runner,
	# because their answer depends on the state of the world (is the cow fed, is
	# the plot ready) and not on what an NPC just asked for. They still report
	# to the dialogue runner afterwards, so a quest step listening for "milk the
	# cow" still hears it.
	if _handle_farm_action(who):
		HUD.refresh()
		return

	if who.requires_item != "" and not Inventory.has(who.requires_item):
		var hint: String = Quests.current_step().get("hint_line", "")
		if hint != "" and not Dialogue.is_open:
			Dialogue.play_line(hint)
		return

	var correct: bool = Dialogue.submit_action(who.action, who.object_id, GameState.carrying)
	if correct and who.requires_item != "" and who.consumes_item:
		Inventory.remove(who.requires_item, 1)
	HUD.refresh()


## Farm verbs the simulation owns. Returns true if this action was handled here.
func _handle_farm_action(who: WorldObject) -> bool:
	match who.action:
		"animal":
			return _handle_animal_action(who)
		"farm":
			return _handle_field_action(who)
		"craft":
			var recipes := Crafting.recipes_at(who.object_id)
			for recipe_id in recipes:
				if Crafting.can_craft(recipe_id):
					var made := Crafting.craft(recipe_id)
					DayEndCard.note_word(made)
					Dialogue.submit_action("craft", who.object_id, made)
					return true
			_say_sign("missing_ingredients")
			return true
	return false


## An animal answers ONE key, and what it does depends on what it needs. Take
## first, feed second: the player who walks up to a cow with milk waiting wants
## the milk, and making them press E twice to get past a feeding they did not
## ask for is the kind of friction that ends a daily ritual.
func _handle_animal_action(who: WorldObject) -> bool:
	if not Livestock.is_animal(who.object_id):
		return false
	if Livestock.can_collect(who.object_id):
		var item := Livestock.collect(who.object_id)
		DayEndCard.note_word(item)
		Dialogue.submit_action("collect", who.object_id, item)
		return true
	if not Livestock.was_fed_today(who.object_id):
		var feed := Livestock.feed_item(who.object_id)
		if feed != "" and not Inventory.has(feed):
			# Naming what is missing is the teaching moment: "die Kuh hat
			# Hunger" while you stand there holding nothing is a vocabulary
			# lesson delivered exactly when it lands.
			_say_sign("animal_hungry")
			return true
		if Livestock.feed(who.object_id):
			# Feeding is also the comprehension event a quest may be waiting on.
			Dialogue.submit_action("feed", who.object_id, feed)
			return true
	_say_sign(Livestock.refusal_reason(who.object_id))
	return true


## The field is worked a PLOT at a time, and the plot is the one the player is
## standing on. Using the player's own tile rather than the object's means the
## field is a place you walk around in, not a single button.
func _handle_field_action(who: WorldObject) -> bool:
	var cell := Vector2i(
		int(floor(_player.global_position.x / float(WangTileset.TILE))),
		int(floor(_player.global_position.y / float(WangTileset.TILE))))
	if not Farm.is_plot(cell):
		_say_sign("not_a_field")
		return true

	# ONE verb, chosen by what the plot needs. A field with three buttons makes
	# the player think about the interface; a field with one makes them think
	# about the field. The German the action reports differs per branch, which
	# is what turns a single keypress into three different words.
	if not Farm.is_planted(cell):
		var seed_crop := _seed_in_hand()
		if seed_crop == "":
			_say_sign("no_seed")
			return true
		if not Farm.plant(cell, seed_crop):
			_say_sign("already_planted")
			return true
		Inventory.remove(seed_crop, 1)
		DayEndCard.note_word(seed_crop)
		Dialogue.submit_action("plant", who.object_id, seed_crop)
	elif Farm.is_ready(cell):
		var picked := Farm.harvest(cell)
		if picked == "":
			_say_sign("not_ripe")
			return true
		DayEndCard.note_word(picked)
		Dialogue.submit_action("harvest", who.object_id, picked)
	elif Farm.is_dead(cell):
		Farm.clear_plot(cell)
	else:
		if not Inventory.has("wasser"):
			_say_sign("no_water")
			return true
		if not Farm.water(cell):
			_say_sign("already_watered")
			return true
		Dialogue.submit_action("water", who.object_id, "wasser")
	_refresh_crops()
	return true


## A held item that names a crop is a seed for it. Seeds are not separate items:
## "die Kartoffel" in your bag IS the potato you plant and the potato you sell,
## which keeps one word doing all the work instead of inventing "Kartoffelsamen".
func _seed_in_hand() -> String:
	if GameState.carrying != "" and not Farm.crop_def(GameState.carrying).is_empty():
		return GameState.carrying
	for row in Inventory.contents():
		var item := str(row["item"])
		if not Farm.crop_def(item).is_empty():
			return item
	return ""


func _refresh_crops() -> void:
	if has_method("repaint_crops"):
		call("repaint_crops")


## Say a diegetic one-liner by content key. The world explains itself in German
## rather than falling silent, which is the difference between a refusal that
## teaches and one that just feels broken (Part 3 §2).
func _say_sign(key: String) -> void:
	if key == "" or Dialogue.is_open:
		return
	var entry := Config.diegetic(key)
	if not entry.is_empty():
		Dialogue.play_diegetic(entry)


func _on_interactable(who: Interactable) -> void:
	if who.is_bed:
		_sleep()
		return
	Dialogue.play_line(who.placeholder_line)


func _on_quest_completed(_quest_id: String, _rewards: Dictionary) -> void:
	HUD.refresh()


func _on_step_advanced(_quest_id: String, _index: int) -> void:
	HUD.refresh()


## Sleep = save = the day-end card. Part 3 §3/§5: this card is the session-end
## ritual for the whole game, so it fires BEFORE the day rolls over — it is a
## summary of the day just lived, not a preview of the next one.
func _sleep(show_card: bool = true) -> void:
	if show_card:
		DayEndCard.show_card()
		await DayEndCard.dismissed
	GameState.sleep(default_spawn)
	_player.global_position = default_spawn
	resync_npcs()
	HUD.refresh()


func _on_time_changed(_hour: float) -> void:
	_apply_light()
	for npc in get_tree().get_nodes_in_group("npc"):
		npc.on_time_changed(DayCycle.hour)
	# A quest whose giver was elsewhere can begin the moment they arrive.
	if Quests.active_quest == "":
		Quests.start_next_available()

	# Arriving somewhere is a thought. Fired last so the place is fully built —
	# a thought about the village that renders before the village does reads as
	# a loading artefact.
	Monologue.trigger("location_enter", map_id)


func _apply_light() -> void:
	if not has_node("Light"):
		return
	var tint: CanvasModulate = $Light
	if is_interior:
		# Indoors is lamplit: warm, and it does not track the sun.
		tint.color = Color(0.98, 0.94, 0.86)
		return
	var d := DayCycle.darkness()
	tint.color = Color(1.0, 1.0, 1.0).lerp(Color(0.24, 0.28, 0.55), d)


func _clamp_camera() -> void:
	var camera: Camera2D = _player.get_node("Camera2D")
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = map_width_tiles * WorldBuilder.TILE
	camera.limit_bottom = map_height_tiles * WorldBuilder.TILE


func _save_screenshot() -> void:
	var image := get_viewport().get_texture().get_image()
	image.save_png("user://screenshot.png")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		GameState.save_state()
