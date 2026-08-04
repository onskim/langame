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

	# --- the sprite sheet actually shows four facings ---------------------
	# The generated character export could not be trusted: its "south" rotation
	# was not a walk cycle at all but the four VIEWS of the character — front,
	# profile, back, profile — so walking down would have shown the player's back
	# every third frame. Nothing in the engine can tell; it just indexes cells.
	# So measure it. How much of the head is FACE tells the facing apart: the
	# back of a head is hair, and shows almost none.
	var sheet: Image = (player.get_node("Sprite2D") as Sprite2D).texture.get_image()
	var face_by_row: Array[Array] = []
	for row in range(4):
		var per_frame: Array[float] = []
		for frame in range(4):
			per_frame.append(_face_fraction(sheet, frame * 16, row * 32))
		face_by_row.append(per_frame)

	for row in range(4):
		var values: Array = face_by_row[row]
		var spread: float = values.max() - values.min()
		# Within one direction every frame must show the SAME face. A big spread
		# means a stray back-of-head sitting in the middle of a walk cycle.
		_check("row %d holds one facing across its walk cycle" % row, spread < 0.12,
			"spread %.2f over %s" % [spread, str(values)])

	# Facing up must show markedly less face than facing down, or the rows are
	# swapped and the player moons the camera on the way north.
	var down_face: float = face_by_row[0][0]
	var up_face: float = face_by_row[1][0]
	_check("walking up shows the back of the head", up_face < down_face - 0.12,
		"down %.2f vs up %.2f" % [down_face, up_face])
	# A walk that never moves is a slide. Frames within a row must differ.
	_check("the walk cycle actually animates",
		_cells_differ(sheet, 0, 0, 2 * 16, 0), "frame 0 vs frame 2 of the down row")

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
	# Sleeping now shows the day-end payoff card and waits on it (Part 3 §3).
	if DayEndCard.is_open:
		DayEndCard.dismiss()
	await get_tree().process_frame
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


## How much of a 16x32 cell's head band is skin rather than hair. Cheap, but it
## separates front (a face), profile (half a face) and back (none) reliably at
## this sprite size — measured on the shipped sheet as 0.33 / 0.26 / 0.08.
func _face_fraction(sheet: Image, ox: int, oy: int) -> float:
	var skin := 0
	var total := 0
	for y in range(oy + 4, oy + 14):
		for x in range(ox, ox + 16):
			var c := sheet.get_pixel(x, y)
			if c.a < 0.5:
				continue
			total += 1
			var r := c.r * 255.0
			var g := c.g * 255.0
			var b := c.b * 255.0
			if r > 140.0 and g < r and b < g and (r - b) > 40.0:
				skin += 1
	return float(skin) / float(total) if total > 0 else 0.0


## Do two cells of the sheet differ enough to read as movement?
func _cells_differ(sheet: Image, ax: int, ay: int, bx: int, by: int) -> bool:
	var changed := 0
	for y in range(32):
		for x in range(16):
			if sheet.get_pixel(ax + x, ay + y) != sheet.get_pixel(bx + x, by + y):
				changed += 1
	return changed > 16
