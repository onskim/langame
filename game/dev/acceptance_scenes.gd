extends Node
## Scene-architecture acceptance.
##
## The point of the refactor: persistent systems survive a place change, and
## every place is its own scene. The regression this guards against is the one
## the old design had — each map built its own QuestEngine, so walking through
## a door silently reset the quest you were on.
##
##   godot --headless res://dev/acceptance_scenes.tscn

var _failures: int = 0


func _ready() -> void:
	await _run()
	get_tree().quit(1 if _failures > 0 else 0)


func _check(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("  PASS  %s %s" % [label, detail])
	else:
		_failures += 1
		printerr("  FAIL  %s %s" % [label, detail])


func _run() -> void:
	print("--- scene architecture acceptance ---")
	DayCycle.running = false
	DayCycle.hour = 9.0

	# ---------- one scene per place, declared in content ----------
	# Every place is declared in content, so adding one is a scene + a row.
	var maps := WorldRouter.maps()
	_check("every place is declared in content", maps.size() >= 6, str(maps.keys()))
	for required in ["farm", "village", "interior_farmhouse", "interior_anna_kitchen"]:
		_check("%s is declared" % required, maps.has(required))
	for map_id in maps:
		var path: String = WorldRouter.scene_path(map_id)
		_check("%s has a scene file" % map_id, ResourceLoader.exists(path), path)

	# ---------- every exit lands where it says it lands ----------
	# A door names the marker it wants to arrive on. If the destination has no
	# marker by that name the spawn falls back to the map's DEFAULT — you leave
	# your own front door and appear in the middle of the field. That is exactly
	# what every interior exit did, and nothing failed, because the fallback is
	# silent by design. So assert the link itself, both ends, for every map.
	var arrivals_by_map: Dictionary = {}
	var exits: Array[Dictionary] = []
	for map_id in maps:
		var scene_path: String = WorldRouter.scene_path(map_id)
		if not ResourceLoader.exists(scene_path):
			continue
		var place: Node2D = (load(scene_path) as PackedScene).instantiate()
		var marker_names: Array[String] = []
		var arrivals := place.get_node_or_null("Arrivals")
		if arrivals != null:
			for marker in arrivals.get_children():
				marker_names.append(str(marker.name))
		arrivals_by_map[map_id] = marker_names
		for group in ["Doors", "Gates"]:
			var holder := place.get_node_or_null(group)
			if holder == null:
				continue
			for exit_node in holder.get_children():
				var target: String = str(exit_node.get("target_map"))
				if target == "":
					continue  # a door with nowhere to go is checked separately
				exits.append({
					"from": map_id, "name": str(exit_node.name), "to": target,
					"marker": str(exit_node.get("arrival_marker")),
				})
		# A door that names its building with a literal is a building that stays
		# German forever. Every one of them must resolve through the strings
		# table, or a Spanish edition ships with a "Bäckerei" in it.
		var holder := place.get_node_or_null("Doors")
		if holder != null:
			for door_node in holder.get_children():
				var key: String = str(door_node.get("sign_key"))
				var literal: String = str(door_node.get("sign_text"))
				_check("%s/%s names its building from content"
					% [map_id, door_node.name], key != "" and literal == "",
					"sign_key='%s' sign_text='%s'" % [key, literal])
				if key != "":
					_check("  and '%s' exists in the strings table" % key,
						Config.sign_text(key) != "")
		place.free()

	_check("the world has exits to check", exits.size() >= 8, "%d" % exits.size())
	for exit_info: Dictionary in exits:
		var known: Variant = arrivals_by_map.get(exit_info["to"])
		_check("%s/%s arrives on a real marker" % [exit_info["from"], exit_info["name"]],
			known is Array and (known as Array).has(exit_info["marker"]),
			"wants '%s' on %s, which has %s"
				% [exit_info["marker"], exit_info["to"], known])

	# Naming a real marker is not enough — the spawn code has to USE it. This is
	# the check that would have caught the bug from the player's side.
	WorldRouter.pending_arrival = "from_farmhouse"
	var farm_place: Node2D = (load(WorldRouter.scene_path("farm")) as PackedScene).instantiate()
	add_child(farm_place)
	await get_tree().process_frame
	var front_door: Vector2 = (farm_place.get_node("Doors/FarmhouseDoor") as Node2D).global_position
	var landed: Vector2 = (farm_place.get_node("Player") as Node2D).global_position
	_check("leaving the farmhouse puts you at its door, not the map centre",
		landed.distance_to(front_door) < 32.0,
		"landed %s, door %s" % [landed, front_door])
	farm_place.queue_free()
	await get_tree().process_frame

	# ---------- a signboard is content, not paint ----------
	# The founder's shopfront art arrived with the names painted on the boards.
	# Baked in, those buildings are German forever. They are erased from the
	# sprite and drawn from the strings table, so the test is that the world
	# language actually reaches them.
	var village_scene: Node2D = (load(WorldRouter.scene_path("village")) as PackedScene).instantiate()
	add_child(village_scene)
	await get_tree().process_frame
	for shop_name in ["Bakery", "Cafe"]:
		var sign_label := village_scene.get_node_or_null(
			"Buildings/%s/Sign" % shop_name) as Label
		_check("%s has a signboard" % shop_name, sign_label != null)
		if sign_label == null:
			continue
		var key: String = str(sign_label.get("sign_key"))
		_check("  it is painted from content, in the world's language",
			sign_label.text == Config.sign_text(key) and sign_label.text != "",
			"'%s' (key %s, lang %s)" % [sign_label.text, key, Config.world_language()])
		# The board and the door are one fact: if they can disagree, one of them
		# is wrong and the player is the one who finds out.
		var door_node := village_scene.get_node_or_null(
			"Doors/%sDoor" % shop_name) as Door
		if door_node != null:
			_check("  and its door says the same word",
				door_node.label() == sign_label.text,
				"door '%s' vs board '%s'" % [door_node.label(), sign_label.text])

	# Switching the world language must move every sign at once. English stands
	# in for the languages that do not exist yet — the mechanism is the same.
	var german := Config.sign_text("bakery")
	Config._section("ui_strings")["world_language"] = "en"
	var english := Config.sign_text("bakery")
	Config._section("ui_strings")["world_language"] = "de"
	_check("changing the world language changes the sign",
		german != english and english != "", "de='%s' en='%s'" % [german, english])
	_check("and changing it back restores German",
		Config.sign_text("bakery") == german)

	village_scene.queue_free()
	await get_tree().process_frame

	# ---------- persistent systems are autoloads, not per-scene copies ----------
	for name in ["HUD", "Dialogue", "Phone", "Quests", "WorldRouter", "GameState"]:
		_check("%s is a persistent autoload" % name,
			get_node_or_null("/root/" + name) != null)

	# ---------- world scenes must NOT carry their own UI ----------
	for map_id in ["farm", "village", "interior_farmhouse"]:
		var scene: Node2D = load(WorldRouter.scene_path(map_id)).instantiate()
		var has_ui := scene.has_node("HUD") or scene.has_node("Phone") \
			or scene.has_node("DialogueRunner")
		_check("%s owns no duplicate UI" % map_id, not has_ui)
		scene.free()

	# ---------- the regression: quest state survives a place change ----------
	var farm: Node2D = load("res://scenes/world/farm.tscn").instantiate()
	add_child(farm)
	await get_tree().process_frame

	_check("a quest is running on the farm", Quests.active_quest != "",
		"active=%s" % Quests.active_quest)
	var quest_before := Quests.active_quest
	var step_before: int = Quests.step_index
	WordStats.record("kuh", true, 1)
	var mastery_before := float(WordStats.get_stat("kuh").get("mastery", 0.0))

	farm.queue_free()
	await get_tree().process_frame

	var house: Node2D = load("res://scenes/world/interiors/farmhouse.tscn").instantiate()
	add_child(house)
	await get_tree().process_frame

	_check("quest survives walking indoors", Quests.active_quest == quest_before,
		"%s -> %s" % [quest_before, Quests.active_quest])
	_check("quest step survives", Quests.step_index == step_before,
		"%d -> %d" % [step_before, Quests.step_index])
	_check("learner model survives",
		is_equal_approx(float(WordStats.get_stat("kuh").get("mastery", 0.0)), mastery_before),
		"%.4f" % WordStats.get_stat("kuh").get("mastery", 0.0))

	# ---------- interiors ----------
	_check("interior is flagged as interior", house.is_interior)
	_check("interior is lamplit, not sun-tinted",
		house.get_node("Light").color.is_equal_approx(Color(0.98, 0.94, 0.86)),
		str(house.get_node("Light").color))
	_check("interior has a way out", house.get_node("Doors").get_child_count() >= 1)
	var exit_door: Door = house.get_node("Doors/Exit")
	_check("the exit leads back outdoors", exit_door.target_map == "farm",
		exit_door.target_map)
	_check("the bed moved indoors where a bed belongs",
		house.get_node_or_null("Furniture/Bed") != null)

	# The exit must be visible from where you arrive, not hidden across the room.
	var arrival: Marker2D = house.get_node("Arrivals/from_outside")
	_check("the exit is right where you arrive",
		arrival.global_position.distance_to(exit_door.global_position) < 48.0,
		"%.0f px" % arrival.global_position.distance_to(exit_door.global_position))

	house.queue_free()
	await get_tree().process_frame

	# ---------- Part 14 §3 access policy ----------
	var village: Node2D = load("res://scenes/world/village.tscn").instantiate()
	add_child(village)
	await get_tree().process_frame

	var doors := get_tree().get_nodes_in_group("door")
	_check("village shopfronts have doors", doors.size() >= 3, "count=%d" % doors.size())

	var bakery: Door = village.get_node("Doors/BakeryDoor")
	_check("the bakery is enterable (commercial ground floor)",
		bakery.effective_access() == Door.Access.OPEN)
	_check("the bakery door leads to its interior",
		bakery.target_map == "interior_bakery", bakery.target_map)

	# Part 14 §3 lists Mila's cottage as a blackout home.
	var cottage: Door = village.get_node("Doors/MilaCottageDoor")
	_check("a private home is blackout, not an invisible wall",
		cottage.effective_access() == Door.Access.BLACKOUT,
		"access=%d" % cottage.effective_access())
	_check("blackout doors know whose home it is",
		cottage.owner_npc() == "npc_mila", cottage.owner_npc())

	# Pre-wired unlock: at 3 hearts the door opens (Part 14 §3).
	GameState.affection["npc_mila"] = 3
	_check("blackout opens at 3 hearts (pre-wired)",
		cottage.effective_access() == Door.Access.OPEN,
		"access=%d" % cottage.effective_access())
	GameState.affection.erase("npc_mila")

	# Part 14 §3 makes the Rathaus "office via quests", not a heart-gated home.
	# It also used to point at interior_weber, which does not exist — the door
	# would have opened at 3 hearts and travelled nowhere, silently.
	var rathaus: Door = village.get_node("Doors/RathausDoor")
	_check("the Rathaus is locked, not heart-gated",
		rathaus.effective_access() == Door.Access.LOCKED,
		"access=%d" % rathaus.effective_access())
	for door: Door in get_tree().get_nodes_in_group("door"):
		if door.effective_access() != Door.Access.LOCKED and door.target_map != "":
			_check("door '%s' leads to a declared place" % door.name,
				WorldRouter.scene_path(door.target_map) != "", door.target_map)

	# ---------- giver presence ----------
	# Q02's giver is Anna, who is on the farm — her line must not play here.
	_check("a quest whose giver is elsewhere cannot start here",
		not Quests.giver_present("q02"),
		"anna on %s, player on %s" % [
			WorldRouter.map_of_location(WorldRouter.scheduled_location("npc_anna", 9.0)),
			WorldRouter.current_map])
	_check("an auto-given quest needs no giver", Quests.giver_present("q01"))

	print("--- scene acceptance complete, %d failure(s). ---" % _failures)
