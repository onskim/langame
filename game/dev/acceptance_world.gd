extends Node
## Split-world acceptance — GDD Part 14 §2, and the half of Part 10 §6 Week 1
## I originally skipped ("walk farm→village", not just "walk farm").
##
##   godot --headless res://dev/acceptance_world.tscn

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
	print("--- split world acceptance ---")

	# ---------- the world layout is content, not code ----------
	_check("two maps declared in content", WorldRouter.maps().size() == 2,
		str(WorldRouter.maps().keys()))
	_check("farm locations map to the farm",
		WorldRouter.map_of_location("field") == "farm",
		WorldRouter.map_of_location("field"))
	_check("shops map to the village",
		WorldRouter.map_of_location("bakery") == "village",
		WorldRouter.map_of_location("bakery"))

	# ---------- Part 14 §2: farm is private, village is social ----------
	# Anna is the mentor exception; nobody else may be on the farm at any hour.
	var offenders: Array[String] = []
	for hour in [7.0, 10.0, 13.0, 16.0, 20.0, 23.0]:
		for npc_id in WorldRouter.npcs_on_map("farm", hour):
			if npc_id != "npc_anna" and not offenders.has(npc_id):
				offenders.append(npc_id)
	_check("farm is private — only Anna is ever there", offenders.is_empty(),
		"offenders=%s" % str(offenders))

	var village_cast: Array[String] = []
	for hour in [7.0, 10.0, 13.0, 16.0, 20.0]:
		for npc_id in WorldRouter.npcs_on_map("village", hour):
			if not village_cast.has(npc_id):
				village_cast.append(npc_id)
	_check("village is social — the cast is there", village_cast.size() >= 4,
		"cast=%s" % str(village_cast))

	# ---------- the farm map itself ----------
	DayCycle.running = false
	DayCycle.hour = 9.0
	var farm: Node2D = load("res://scenes/world/farm.tscn").instantiate()
	add_child(farm)
	await get_tree().process_frame

	var farm_npcs := get_tree().get_nodes_in_group("npc")
	_check("farm spawns only Anna at 09:00", farm_npcs.size() == 1,
		"count=%d" % farm_npcs.size())
	if farm_npcs.size() == 1:
		_check("and that one is Anna", (farm_npcs[0] as NPC).npc_id == "npc_anna",
			(farm_npcs[0] as NPC).npc_id)

	_check("farm has a gate out", farm.get_node("Gates").get_child_count() >= 1)
	var gate: MapGate = farm.get_node("Gates/ToVillage")
	_check("the gate points at the village", gate.target_map == "village",
		gate.target_map)

	# The fence must have a gap on the gate side, or the gate is unreachable.
	var fence: TileMapLayer = farm.get_node("Fence")
	var mid := WorldBuilder.FARM_H / 2
	_check("fence has a gap at the gate",
		fence.get_cell_source_id(Vector2i(WorldBuilder.FARM_W - 1, mid)) == -1,
		"cell=%d" % fence.get_cell_source_id(Vector2i(WorldBuilder.FARM_W - 1, mid)))

	farm.queue_free()
	await get_tree().process_frame

	# ---------- the village map ----------
	var village: Node2D = load("res://scenes/world/village.tscn").instantiate()
	add_child(village)
	await get_tree().process_frame

	var vill_npcs := get_tree().get_nodes_in_group("npc")
	_check("village is populated at 09:00", vill_npcs.size() >= 3,
		"count=%d" % vill_npcs.size())
	var present: Array[String] = []
	for npc: NPC in vill_npcs:
		present.append(npc.npc_id)
	_check("Anna is NOT in the village at 09:00", not present.has("npc_anna"),
		str(present))
	_check("Karl is in the village", present.has("npc_karl"), str(present))

	_check("village has buildings, not bare markers",
		village.get_node("Buildings").get_child_count() >= 4,
		"count=%d" % village.get_node("Buildings").get_child_count())
	_check("village has a way back", village.get_node("Gates/ToFarm").target_map == "farm")

	# Each shop marker must sit at its building, or "Karl is in the Bäckerei"
	# is still just a coordinate.
	var bakery_marker: Marker2D = village.get_node("Locations/bakery")
	var bakery_sprite: Sprite2D = village.get_node("Buildings/Bakery")
	_check("the bakery marker is at the bakery",
		bakery_marker.global_position.distance_to(bakery_sprite.global_position) < 64.0,
		"%.0f px apart" % bakery_marker.global_position.distance_to(bakery_sprite.global_position))

	# ---------- NPCs move between maps as the day turns ----------
	DayCycle.hour = 13.0
	var weber_at_1 := WorldRouter.scheduled_location("npc_weber", 9.0)
	var weber_at_2 := WorldRouter.scheduled_location("npc_weber", 13.0)
	_check("Weber changes building across the day", weber_at_1 != weber_at_2,
		"%s -> %s" % [weber_at_1, weber_at_2])

	# Anna crosses INTO the village in the evening — the maps are connected,
	# not two sealed worlds.
	_check("Anna visits the village in the evening",
		WorldRouter.map_of_location(WorldRouter.scheduled_location("npc_anna", 18.0)) == "village",
		"at=%s" % WorldRouter.scheduled_location("npc_anna", 18.0))

	# ---------- current map persists ----------
	GameState.current_map = "village"
	GameState.save_state()
	var reloaded := SaveService.load_game()
	_check("current map is saved", reloaded.get("current_map", "") == "village",
		str(reloaded.get("current_map", "")))

	print("--- split world acceptance complete, %d failure(s). ---" % _failures)
