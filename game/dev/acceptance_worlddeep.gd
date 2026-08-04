extends Node
## World-deepening acceptance — Addendum §10 Week 4 / Part 10 §6 row 4:
##
##   "New word auto-appears in Wörter; pet follows and obeys tapped command;
##    day ends with payoff card; Q05 market trip completes silently."
##
##   godot --headless res://dev/acceptance_worlddeep.tscn

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
	print("--- Week 4 acceptance: world deepening ---")
	WordStats.reset()
	DayEndCard.begin_day(1)
	DayCycle.running = false
	DayCycle.hour = 9.0

	# ================= calendar + weather (Part 12 §5) =================
	_check("season is 24 days", Calendar.days_per_season() == 24,
		"%d" % Calendar.days_per_season())
	_check("year is 96 days",
		Calendar.days_per_season() * Calendar.season_names().size() == 96)
	_check("day 1 is early Frühling", Calendar.season_name(1) == "Frühling",
		Calendar.season_name(1))
	_check("day 25 rolls into Sommer", Calendar.season_name(25) == "Sommer",
		Calendar.season_name(25))
	_check("day 97 starts year 2", Calendar.year_of(97) == 2, "%d" % Calendar.year_of(97))

	var weekdays: Array[String] = []
	for d in range(1, 8):
		weekdays.append(Calendar.weekday_name(d))
	_check("a full Montag–Sonntag week cycles", weekdays.size() == 7 and weekdays[0] != weekdays[6],
		str(weekdays))
	var market_days := 0
	for d in range(1, 15):
		if Calendar.is_market_day(d):
			market_days += 1
	_check("market day falls once a week", market_days == 2, "%d in 14 days" % market_days)

	# A forecast that changes when you re-check it is not a forecast.
	var first := Calendar.weather_for(9)
	var second := Calendar.weather_for(9)
	_check("weather is deterministic", first == second, "%s / %s" % [first, second])
	_check("tomorrow's forecast matches tomorrow's weather",
		Calendar.weather_tomorrow() == Calendar.weather_for(GameState.day + 1))
	# Winter can snow, Sommer cannot.
	var summer_snow := false
	for d in range(25, 49):
		if Calendar.weather_for(d) == "schnee":
			summer_snow = true
	_check("it never snows in Sommer", not summer_snow)

	# ================= the phone (Addendum §4) =================
	_check("the phone has four apps", Phone.APPS.size() == 4)
	Phone.open_app("words")
	_check("Wörter opens", Phone.current_app_key() == "words")

	# --- a new word auto-appears in Wörter (the acceptance criterion) ---
	_check("Wörter is empty before anything is met", Phone._word_rows().is_empty())
	WordStats.introduce("kuh", 1)
	var rows: Array = Phone._word_rows()
	var found := false
	for row: Dictionary in rows:
		if str(row.get("text", "")).contains("Kuh"):
			found = true
	_check("a newly met word auto-appears in Wörter", found, str(rows))

	# --- Part 3 §4: translation is EARNED, not given ---
	_check("no English on first meeting", not Phone.translation_unlocked("kuh"),
		"meetings=%d" % Phone.meetings("kuh"))
	var kuh := WordStats.get_stat("kuh")
	kuh["times_seen"] = 3
	_check("English unlocks after 3 meetings", Phone.translation_unlocked("kuh"),
		"meetings=%d" % Phone.meetings("kuh"))
	var unlocked_row := Phone._word_row("kuh")
	_check("and the row then carries it",
		str(unlocked_row.get("text", "")).contains("cow"), str(unlocked_row))

	# --- the dog-ear is the engine's ONLY visible surface, and never a score ---
	kuh["due_day"] = GameState.day + 99
	_check("a fresh word has no dog-ear", not Phone.is_fading("kuh"))
	kuh["due_day"] = GameState.day
	_check("a fading word gets a dog-ear", Phone.is_fading("kuh"))
	var all_text := ""
	for row: Dictionary in Phone._word_rows():
		all_text += str(row.get("text", ""))
	_check("Wörter never shows a score or 'review'",
		not all_text.to_lower().contains("review") and not all_text.contains("%"),
		all_text)

	# --- Wetter reads out German weather words ---
	Phone.open_app("weather")
	var weather_rows: Array = Phone._weather_rows()
	_check("Wetter shows today and tomorrow", weather_rows.size() >= 2, str(weather_rows))
	var weather_text := str((weather_rows[0] as Dictionary).get("text", ""))
	var today_word := ContentDB.get_word(Calendar.weather_today())
	_check("the forecast is in German, from content",
		weather_text.contains(str(today_word.get("lemma", "@"))), weather_text)

	Phone.open_app("map")
	_check("Karte lists the outdoor places", Phone._map_rows().size() >= 2,
		str(Phone._map_rows()))
	Phone.open_app("tasks")

	# ================= pets (Addendum §6) =================
	var farm: Node2D = load("res://scenes/world/farm.tscn").instantiate()
	add_child(farm)
	await get_tree().process_frame

	var pets := get_tree().get_nodes_in_group("pet")
	_check("dog AND cat are both in the world", pets.size() == 2, "%d" % pets.size())
	var ids: Array[String] = []
	for pet: Pet in pets:
		ids.append(pet.pet_id)
	_check("they are the dog and the cat", ids.has("hund") and ids.has("katze"), str(ids))

	var dog: Pet = pets[0] if (pets[0] as Pet).pet_id == "hund" else pets[1]
	var player: CharacterBody2D = farm.get_node("Player")

	# --- follows ---
	dog.global_position = player.global_position + Vector2(140, 0)
	var start_distance := dog.global_position.distance_to(player.global_position)
	for i in range(120):
		await get_tree().physics_frame
	var end_distance := dog.global_position.distance_to(player.global_position)
	_check("the pet follows the player", end_distance < start_distance - 40.0,
		"%.0f -> %.0f px" % [start_distance, end_distance])

	# --- obeys a TAPPED command (Addendum §10 constraint 4) ---
	_check("obeys Sitz!", dog.obey("sitz"))
	_check("and actually sits", dog.is_sitting(), "state=%d" % dog.state)
	var sat_at := dog.global_position
	for i in range(60):
		await get_tree().physics_frame
	_check("a sitting pet stays put", dog.global_position.distance_to(sat_at) < 2.0)

	_check("obeys Komm!", dog.obey("komm"))
	_check("and starts following again", dog.is_following())
	_check("refuses a word it does not know", not dog.obey("brot"))

	# Hearing the command and seeing it obeyed IS the comprehension event.
	_check("obeying a command is logged against the word",
		int(WordStats.get_stat("sitz").get("times_seen", 0)) > 0,
		"seen=%d" % WordStats.get_stat("sitz").get("times_seen", 0))

	# A pet that body-blocks the player is infuriating.
	_check("pets do not block the player",
		(dog.collision_layer & player.collision_mask) == 0,
		"pet layer=%d player mask=%d" % [dog.collision_layer, player.collision_mask])

	# ================= the day-end payoff card =================
	DayEndCard.begin_day(GameState.day)
	DayEndCard.note_word("kuh")
	DayEndCard.note_word("heu")
	_check("the card collects the day's words",
		DayEndCard.words_met_today().size() == 2, str(DayEndCard.words_met_today()))

	DayEndCard.show_card()
	await get_tree().process_frame
	_check("sleeping raises the payoff card", DayEndCard.is_open)
	_check("it names the date", DayEndCard._date.text != "", DayEndCard._date.text)
	_check("it teases tomorrow", DayEndCard._tomorrow.text != "", DayEndCard._tomorrow.text)

	# Part 3 §3/§4: icons and words, never scores.
	var card_text := DayEndCard._date.text + DayEndCard._rep.text + DayEndCard._tomorrow.text
	for child in DayEndCard._words.get_children():
		card_text += (child as Label).text
	_check("the card shows no score or percentage",
		not card_text.contains("%") and not card_text.to_lower().contains("mastery"),
		card_text)
	DayEndCard.dismiss()
	_check("dismissing starts a fresh day's collection",
		DayEndCard.words_met_today().is_empty())

	farm.queue_free()
	await get_tree().process_frame

	# ================= Q05 completes SILENTLY =================
	_check("Q04 exists", not ContentDB.get_quest("q04").is_empty())
	_check("Q05 exists", not ContentDB.get_quest("q05").is_empty())
	_check("Q05 is gated behind Q04",
		(ContentDB.get_quest("q05").get("prereq", []) as Array).has("q04"))
	_check("Q05 needs reputation with Anna",
		int(ContentDB.get_quest("q05").get("rep_gate", 0)) == 8)

	# The Week 4 criterion is that the market trip completes with NO speech.
	GameState.completed_quests = ["q01", "q02", "q03", "q04"]
	GameState.reputation_by_npc = {"npc_anna": 12}
	Quests.active_quest = ""
	MicCapture.set_quiet_mode(true)

	var village: Node2D = load("res://scenes/world/village.tscn").instantiate()
	add_child(village)
	await get_tree().process_frame

	# Anna gives Q05 but is on the farm at 09:00, so it must NOT start here.
	_check("Q05 waits for its giver", Quests.active_quest != "q05",
		"active=%s" % Quests.active_quest)

	# Evening: Anna comes into the village, so the quest can be handed over.
	DayCycle.hour = 18.0
	DayCycle.time_changed.emit(18.0)
	await get_tree().process_frame
	_check("Q05 starts once Anna is in the village", Quests.active_quest == "q05",
		"active=%s anna=%s" % [Quests.active_quest,
			WorldRouter.scheduled_location("npc_anna", 18.0)])

	var stall: Node2D = village.get_node("MarketStall")
	_check("the market stall exists", stall != null)
	GameState.carrying = "samen"
	var bought: bool = Dialogue.submit_action("buy", "obj_market_stall", "samen")
	_check("buying works with the mic off", bought)
	Dialogue.close()
	await get_tree().process_frame
	await get_tree().process_frame
	Dialogue.close()
	await get_tree().process_frame
	await get_tree().process_frame
	Dialogue.close()
	await get_tree().process_frame
	_check("Q05 completes silently", GameState.completed_quests.has("q05"),
		str(GameState.completed_quests))
	MicCapture.set_quiet_mode(false)

	print("--- Week 4 acceptance complete, %d failure(s). ---" % _failures)
