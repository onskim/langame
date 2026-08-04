extends Node
## Week 1 acceptance test (GDD Part 10 §6):
## "Walk farm; interact with cow; sleep; day count persists across restart."
##
## Run twice — pass 1 plays, pass 2 (after a real process exit) checks persistence:
##   godot --headless res://dev/acceptance_week1.tscn -- pass1
##   godot --headless res://dev/acceptance_week1.tscn -- pass2

var _failures: int = 0


func _ready() -> void:
	var pass_name := "pass1"
	for arg in OS.get_cmdline_user_args():
		pass_name = arg
	if pass_name == "pass1":
		await _pass1()
	else:
		await _pass2()
	get_tree().quit(1 if _failures > 0 else 0)


func _check(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("  PASS  %s %s" % [label, detail])
	else:
		_failures += 1
		printerr("  FAIL  %s %s" % [label, detail])


func _pass1() -> void:
	print("--- Week 1 acceptance, pass 1 (play) ---")
	var farm: Node2D = load("res://scenes/world/farm.tscn").instantiate()
	add_child(farm)
	await get_tree().process_frame

	var player: CharacterBody2D = farm.get_node("Player")
	var cow: Node2D = farm.get_node("Cow")
	# The bed moved indoors with the interior split, so sleeping is tested
	# in the farmhouse where a bed actually belongs.
	var house: Node2D = load("res://scenes/world/interiors/farmhouse.tscn").instantiate()
	add_child(house)
	await get_tree().process_frame
	var bed: Node2D = house.get_node("Furniture/Bed")
	var dialogue: CanvasLayer = Dialogue

	_check("starts on day 1", GameState.day == 1, "day=%d" % GameState.day)

	# --- walk the farm: drive real physics, not a teleport ----------------
	var start := player.global_position
	Input.action_press("move_right")
	for i in range(30):
		await get_tree().physics_frame
	Input.action_release("move_right")
	await get_tree().physics_frame
	var moved := player.global_position.distance_to(start)
	_check("player walks", moved > 20.0, "moved %.1f px" % moved)
	_check("faces right after walking right", player.facing == 3, "facing=%d" % player.facing)

	# --- fence collision: walk hard into the west fence -------------------
	player.global_position = Vector2(24, 320)
	Input.action_press("move_left")
	for i in range(60):
		await get_tree().physics_frame
	Input.action_release("move_left")
	await get_tree().physics_frame
	_check("fence blocks player", player.global_position.x > 8.0,
		"stopped at x=%.1f" % player.global_position.x)

	# --- interact with the cow --------------------------------------------
	player.global_position = cow.global_position + Vector2(-26, 4)
	player.facing = 3
	await get_tree().physics_frame
	await get_tree().physics_frame
	var target: Node = player.current_interactable()
	_check("cow is in interact range", target == cow,
		"found=%s" % (target.name if target else "<none>"))
	# From Week 2 the cow is a quest objective, so "interacting works" means the
	# dialogue runner is showing Anna's line, not a placeholder box.
	_check("cow interaction drives dialogue", dialogue.is_open,
		"line=%s" % dialogue.current_line_id)
	dialogue.close()

	# --- day/night curve ---------------------------------------------------
	DayCycle.running = false
	DayCycle.hour = 12.0
	_check("noon is untinted", is_zero_approx(DayCycle.darkness()),
		"darkness=%.2f" % DayCycle.darkness())
	DayCycle.hour = 23.5
	_check("late night is dark", DayCycle.darkness() > 0.6,
		"darkness=%.2f" % DayCycle.darkness())

	# --- sleep -------------------------------------------------------------
	bed.interact()
	await get_tree().process_frame
	_check("sleep advances the day", GameState.day == 2, "day=%d" % GameState.day)
	_check("sleep resets clock to morning", is_equal_approx(DayCycle.hour, DayCycle.START_HOUR),
		"hour=%.2f" % DayCycle.hour)
	_check("save file written", SaveService.has_save(), SaveService.absolute_path())

	print("--- pass 1 complete, %d failure(s). Now relaunch for pass 2. ---" % _failures)


func _pass2() -> void:
	print("--- Week 1 acceptance, pass 2 (fresh process) ---")
	# GameState._ready() already loaded from disk before this ran.
	_check("day survived relaunch", GameState.day == 2, "day=%d" % GameState.day)

	# You sleep in the farmhouse, so you wake in the farmhouse. What matters is
	# that the saved position round-trips, not that it is any fixed coordinate.
	var saved := SaveService.load_game()
	var expected := Vector2(float(saved.get("player_x", 0.0)), float(saved.get("player_y", 0.0)))
	_check("saved position round-trips", GameState.player_position.distance_to(expected) < 1.0,
		"saved=%s loaded=%s" % [expected, GameState.player_position])
	_check("you wake where you slept", GameState.current_map == "interior_farmhouse",
		GameState.current_map)
	print("--- pass 2 complete, %d failure(s). ---" % _failures)
