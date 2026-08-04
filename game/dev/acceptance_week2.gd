extends Node
## Week 2 acceptance (GDD Part 10 §6):
## "Q02 playable end-to-end from YAML with pointing gesture."
##
##   godot --headless res://dev/acceptance_week2.tscn

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
	print("--- Week 2 acceptance: Q02 end-to-end from YAML ---")

	# --- content pipeline --------------------------------------------------
	_check("content bundle loaded", ContentDB.loaded)
	_check("Q02 exists in compiled content", not ContentDB.get_quest("q02").is_empty())
	var line := ContentDB.get_line("anna_q02_ask")
	_check("Q02's line came from YAML", line.get("de", "") != "",
		"de=%s" % line.get("de", ""))
	_check("line is flagged draft (native gate)", ContentDB.is_draft("anna_q02_ask"))
	_check("gesture points at the cow",
		(line.get("gestures", [])[0]).get("point_at", "") == "obj_cow")

	# No German may be hardcoded in engine code — the line must match content.
	_check("article colour comes from content",
		ContentDB.article_color("kuh").is_equal_approx(Color("#D94A6A")),
		"die Kuh -> %s" % ContentDB.article_color("kuh").to_html(false))

	var farm: Node2D = load("res://scenes/world/farm.tscn").instantiate()
	add_child(farm)
	await get_tree().process_frame

	var runner: CanvasLayer = farm.get_node("DialogueRunner")
	var cow: Node2D = farm.get_node("Cow")
	var pig: Node2D = farm.get_node("Pig")
	var hay: Node2D = farm.get_node("Hay")

	# From Week 3 the engine chains from Q01, so clear Q01 before testing Q02.
	var quests: Node = farm.quests
	var guard := 0
	while quests.active_quest == "q01" and guard < 24:
		guard += 1
		var objective: Dictionary = runner.current_objective
		if objective.is_empty():
			runner.close()
		else:
			runner.submit_action(objective.get("action", ""), objective.get("target", ""), "")
		await get_tree().process_frame

	# --- step 1: Anna asks, and points --------------------------------------
	_check("quest auto-started", runner.is_open, "line=%s" % runner.current_line_id)
	_check("playing the YAML line", runner.current_line_id == "anna_q02_ask")
	_check("objective is Tier I feed-the-cow",
		runner.current_objective.get("action", "") == "feed"
		and runner.current_objective.get("target", "") == "obj_cow",
		str(runner.current_objective))
	await get_tree().process_frame
	_check("gesture highlighted the cow", cow._highlighted)
	_check("gesture did NOT highlight the pig", not pig._highlighted)

	# --- wrong action: feeding the pig is a comprehension miss --------------
	GameState.carrying = "heu"
	var wrong: bool = runner.submit_action("feed", "obj_pig", "heu")
	_check("feeding the pig is rejected", not wrong)
	_check("wrong action triggers a recast",
		runner._line_label.text.contains("KUH"), runner._line_label.text)
	_check("objective stays open after a miss", not runner.current_objective.is_empty())

	# --- pick up the hay ----------------------------------------------------
	GameState.carrying = ""
	hay.interact()
	await get_tree().process_frame
	_check("hay pickup grants the item", GameState.carrying == "heu",
		"carrying=%s" % GameState.carrying)

	# --- right action: feed the cow ----------------------------------------
	cow.interact()
	await get_tree().process_frame
	_check("feeding the cow is accepted", runner.current_objective.is_empty())
	_check("item consumed", GameState.carrying == "")
	_check("gesture cleared after success", not cow._highlighted)

	# --- step 2 + completion ------------------------------------------------
	await get_tree().process_frame
	await get_tree().process_frame
	_check("advanced to the thank-you line", runner.current_line_id == "anna_q02_done",
		"line=%s" % runner.current_line_id)

	runner.close()
	await get_tree().process_frame
	_check("Q02 recorded complete", GameState.completed_quests.has("q02"),
		str(GameState.completed_quests))
	# Q01 pays 1 rep, Q02 pays 3 more and 5 money.
	_check("rewards applied from YAML", GameState.reputation == 4 and GameState.money == 5,
		"rep=%d money=%d" % [GameState.reputation, GameState.money])

	print("--- Week 2 acceptance complete, %d failure(s). ---" % _failures)
