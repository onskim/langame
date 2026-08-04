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
	var maps := WorldRouter.maps()
	_check("five places declared", maps.size() == 5, str(maps.keys()))
	for map_id in maps:
		var path: String = WorldRouter.scene_path(map_id)
		_check("%s has a scene file" % map_id, ResourceLoader.exists(path), path)

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

	var rathaus: Door = village.get_node("Doors/RathausDoor")
	_check("a private home is blackout, not an invisible wall",
		rathaus.effective_access() == Door.Access.BLACKOUT,
		"access=%d" % rathaus.effective_access())

	# Pre-wired unlock: at 3 hearts the door opens (Part 14 §3).
	GameState.affection["npc_weber"] = 3
	_check("blackout opens at 3 hearts (pre-wired)",
		rathaus.effective_access() == Door.Access.OPEN,
		"access=%d" % rathaus.effective_access())
	GameState.affection.erase("npc_weber")

	# ---------- giver presence ----------
	# Q02's giver is Anna, who is on the farm — her line must not play here.
	_check("a quest whose giver is elsewhere cannot start here",
		not Quests.giver_present("q02"),
		"anna on %s, player on %s" % [
			WorldRouter.map_of_location(WorldRouter.scheduled_location("npc_anna", 9.0)),
			WorldRouter.current_map])
	_check("an auto-given quest needs no giver", Quests.giver_present("q01"))

	print("--- scene acceptance complete, %d failure(s). ---" % _failures)
