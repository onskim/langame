extends Node
## Week 3 acceptance (GDD Part 10 §6):
## "5 NPCs walk schedules; Q01–Q03 chain completes; tasks visible on phone."
##
##   godot --headless res://dev/acceptance_week3.tscn

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
	print("--- Week 3 acceptance ---")

	# The cast lives in the village (Part 14 §2), so schedules are exercised
	# there; the farm hosts the quest chain.
	DayCycle.running = false
	DayCycle.hour = 9.0
	var village: Node2D = load("res://scenes/world/village.tscn").instantiate()
	add_child(village)
	await get_tree().process_frame

	var npcs := get_tree().get_nodes_in_group("npc")
	_check("village populated at 09:00", npcs.size() >= 4, "found %d" % npcs.size())

	var named := {}
	for npc: NPC in npcs:
		named[npc.npc_id] = npc
		_check("%s loaded from content" % npc.npc_id, not npc.data.is_empty(),
			"name=%s" % npc.data.get("name", ""))

	# All five are schedulable, whichever map they are on right now.
	_check("all five NPCs exist in content", ContentDB.npcs.size() == 5,
		"count=%d" % ContentDB.npcs.size())

	# Every NPC's scheduled location must actually change across the day, or the
	# "schedule" is decoration. Checked from content so it covers the whole cast.
	for npc_id in ContentDB.npcs.keys():
		var seen := {}
		for hour in [7.0, 12.0, 15.0, 20.0, 23.0]:
			var loc: String = WorldRouter.scheduled_location(npc_id, hour)
			if loc != "":
				seen[loc] = true
		_check("%s visits multiple places" % npc_id, seen.size() >= 2,
			"locations=%s" % str(seen.keys()))

	# Drive the clock and confirm they actually move, not just retarget.
	var weber: NPC = named["npc_weber"]
	var before := weber.global_position
	_check("Weber starts at the Rathaus", weber.current_location == "rathaus",
		"at=%s" % weber.current_location)

	DayCycle.hour = 13.0
	DayCycle.time_changed.emit(13.0)
	await get_tree().process_frame
	_check("Weber retargets to the bakery at 13:00", weber.current_location == "bakery",
		"at=%s" % weber.current_location)
	_check("Weber is walking", weber.is_walking())

	for i in range(240):
		await get_tree().physics_frame
	var moved := weber.global_position.distance_to(before)
	_check("Weber physically moved", moved > 40.0, "moved %.1f px" % moved)

	var karl: NPC = named["npc_karl"]
	_check("Karl is elsewhere than Weber started",
		karl.current_location != "rathaus",
		"karl=%s" % karl.current_location)

	village.queue_free()
	await get_tree().process_frame
	DayCycle.hour = 9.0

	# ---------- the farm hosts the quest chain ----------
	var farm: Node2D = load("res://scenes/world/farm.tscn").instantiate()
	add_child(farm)
	await get_tree().process_frame
	var quests: Node = Quests
	var phone: CanvasLayer = Phone

	_check("Q01 available at start", quests.is_available("q01"))
	_check("Q02 gated behind Q01", not quests.is_available("q02"))
	_check("Q03 gated behind Q02", not quests.is_available("q03"))
	_check("Q01 started automatically", quests.active_quest == "q01",
		"active=%s" % quests.active_quest)

	# ---------- phone shows the task ----------
	phone.open()
	await get_tree().process_frame
	_check("phone opens", phone.is_open)
	var rows: Array = phone._task_rows()
	_check("phone lists the active task", rows.size() >= 1, str(rows))
	_check("task names the giver", rows.size() > 0 and (rows[0] as String).contains("Anna"),
		str(rows))
	phone.close()

	# ---------- Q01 -> Q02 -> Q03 chain ----------
	await _finish_quest(farm, quests, "q01")
	_check("Q01 complete", GameState.completed_quests.has("q01"))
	_check("Q02 auto-started after Q01", quests.active_quest == "q02",
		"active=%s" % quests.active_quest)

	await _finish_quest(farm, quests, "q02")
	_check("Q02 complete", GameState.completed_quests.has("q02"))
	_check("Q03 auto-started after Q02", quests.active_quest == "q03",
		"active=%s" % quests.active_quest)

	# Q03 needs 4 waterings — the counted objective must not complete early.
	_check("Q03 objective needs 4", quests.objective_needed() == 4,
		"needed=%d" % quests.objective_needed())
	var runner: CanvasLayer = Dialogue
	GameState.carrying = "wasser"
	for i in range(3):
		runner.submit_action("water", "obj_field", "wasser")
		await get_tree().process_frame
	_check("Q03 still active after 3 of 4", quests.active_quest == "q03",
		"count=%d" % quests.objective_count)
	_check("water was not consumed", GameState.carrying == "wasser")

	runner.submit_action("water", "obj_field", "wasser")
	await get_tree().process_frame
	await get_tree().process_frame
	runner.close()
	await get_tree().process_frame
	_check("Q03 complete after the 4th", GameState.completed_quests.has("q03"),
		str(GameState.completed_quests))

	_check("chain paid out cumulatively to the giver",
		GameState.reputation_of("npc_anna") == 8,
		"anna=%d (1+3+4)" % GameState.reputation_of("npc_anna"))
	# Part 10 §5.3 gates are per-giver: Anna's chores must not raise Karl.
	_check("reputation does not leak to other NPCs",
		GameState.reputation_of("npc_karl") == 0,
		"karl=%d" % GameState.reputation_of("npc_karl"))

	phone.open()
	await get_tree().process_frame
	_check("phone shows three finished quests", phone._task_rows().size() == 3,
		str(phone._task_rows()))

	print("--- Week 3 acceptance complete, %d failure(s). ---" % _failures)


## Drive whatever objective the current quest wants until it completes.
func _finish_quest(farm: Node2D, quests: Node, quest_id: String) -> void:
	var runner: CanvasLayer = Dialogue
	var guard := 0
	while quests.active_quest == quest_id and guard < 24:
		guard += 1
		var objective: Dictionary = runner.current_objective
		if objective.is_empty():
			runner.close()
		else:
			GameState.carrying = _item_for(quest_id)
			runner.submit_action(objective.get("action", ""), objective.get("target", ""),
				GameState.carrying)
		await get_tree().process_frame


func _item_for(quest_id: String) -> String:
	match quest_id:
		"q02": return "heu"
		"q03": return "wasser"
	return ""
