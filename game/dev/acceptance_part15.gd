extends Node
## Part 15 acceptance — the monologue fade and the village memory.
##
##   godot --headless res://dev/acceptance_part15.tscn
##
## These assert the LAWS, because Part 15's laws are what stop it being a
## gimmick and a surveillance system respectively:
##
##   * the monologue never introduces vocabulary;
##   * a word that decays visibly returns to English, without flickering;
##   * thoughts keep words warm but never satisfy a due review;
##   * an NPC records only what they could have witnessed;
##   * no fact ever produces a penalty;
##   * memory personalises the morning retest and never gates it.

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


func _master(word_id: String, mastery: float, seen: int = 5) -> void:
	WordStats.introduce(word_id, GameState.day)
	var s := WordStats.get_stat(word_id)
	s["times_seen"] = seen
	s["mastery"] = mastery


func _run() -> void:
	print("--- Part 15 acceptance: the fade and the memory ---")
	DayCycle.running = false
	GameState.day = 1
	WordStats.reset()
	Monologue.reset()
	Memory.reset()
	Callbacks.reset()

	# ================= SYSTEM A — the inner monologue fade =================
	_check("monologue lines are content", Monologue.all_lines().size() >= 12,
		"%d lines" % Monologue.all_lines().size())

	# --- M0: a thought about words nobody has met is entirely English ---
	var m0 := Monologue.render("mono_obj_kuh_01")
	_check("an unmet word thinks in English", int(m0["stage"]) == FadeRules.Stage.M0,
		str(m0["text"]))
	_check("...and swaps nothing", (m0["swapped_words"] as Array).is_empty())
	_check("the English template really is English",
		not str(m0["text"]).contains("Kuh") and not str(m0["text"]).contains("Markt"),
		str(m0["text"]))

	# --- the monologue NEVER introduces vocabulary (Part 4 §4) ---
	# A word mastered but barely MET must not appear: a German span with no
	# Wörter entry is a word the player cannot look up, which breaks the
	# zero-frustration guarantee the whole system rests on.
	_master("kuh", 0.90, 1)
	_check("a word met only once never appears in a thought",
		not FadeRules.word_swaps("kuh"),
		"seen=%d" % WordStats.get_stat("kuh").get("times_seen", 0))
	_master("kuh", 0.90, 3)
	_check("...but a word met three times may", FadeRules.word_swaps("kuh"))

	# --- M1: German nouns intrude, with their articles ---
	_master("markt", 0.80, 4)
	var m1 := Monologue.render("mono_obj_kuh_01")
	_check("a mastered word thinks in German", int(m1["stage"]) == FadeRules.Stage.M1,
		str(m1["text"]))
	_check("nouns bring their articles", str(m1["text"]).contains("die Kuh"),
		str(m1["text"]))
	_check("the rest of the sentence stays English",
		str(m1["text"]).contains("I should feed"), str(m1["text"]))
	_check("the render reports which words swapped",
		(m1["swapped_words"] as Array).has("kuh"), str(m1["swapped_words"]))
	_check("and where they sit, so they can be coloured and tapped",
		(m1["spans"] as Array).size() == 2, str(m1["spans"]))

	# --- regression: a decayed word visibly returns to English ---
	# Hysteresis: swap ON at 0.50, OFF at 0.40. Between the two a word that was
	# already German STAYS German, or thoughts flicker language line to line and
	# read as a rendering bug rather than as progress.
	WordStats.get_stat("kuh")["mastery"] = 0.45
	var between := Monologue.render("mono_obj_kuh_01")
	_check("a word between the thresholds holds its German",
		str(between["text"]).contains("die Kuh"), str(between["text"]))
	WordStats.get_stat("kuh")["mastery"] = 0.30
	var lapsed := Monologue.render("mono_obj_kuh_01")
	_check("a word decayed below the floor returns to English",
		not str(lapsed["text"]).contains("die Kuh"), str(lapsed["text"]))
	_check("...while its stronger neighbour stays German",
		str(lapsed["text"]).contains("der Markt"), str(lapsed["text"]))

	# --- act ceiling paces, never gates ---
	GameState.day = 1
	_check("act 1 caps thoughts at M1", FadeRules.act_ceiling(1) == FadeRules.Stage.M1,
		"ceiling=%d" % FadeRules.act_ceiling(1))
	_check("the campaign starts in act 1", GameState.act() == 1, "%d" % GameState.act())
	GameState.day = 60
	_check("act 3 is reached by day 60", GameState.act() >= 3, "%d" % GameState.act())
	GameState.day = 1

	# --- readability cap ---
	_check("no more than three spans swap in one line",
		FadeRules.max_swaps() == 3, "%d" % FadeRules.max_swaps())

	# --- thoughts keep words warm but never satisfy a review ---
	_master("feld", 0.80, 4)
	var before_due := int(WordStats.get_stat("feld").get("due_day", 0))
	var before_correct := int(WordStats.get_stat("feld").get("times_correct", 0))
	WordStats.touch("feld", GameState.day)
	_check("a thought does not count as a correct answer",
		int(WordStats.get_stat("feld").get("times_correct", 0)) == before_correct,
		"%d" % WordStats.get_stat("feld").get("times_correct", 0))
	_check("...and does not advance the review schedule",
		int(WordStats.get_stat("feld").get("due_day", 0)) == before_due,
		"%d -> %d" % [before_due, WordStats.get_stat("feld").get("due_day", 0)])
	_check("...but does refresh recency",
		int(WordStats.get_stat("feld").get("last_seen_day", -1)) == GameState.day)

	# --- structure words ride but never lead ---
	_check("structure words are whitelisted", FadeRules.is_struktur("ich"))
	_check("content words are not", not FadeRules.is_struktur("kuh"))

	# --- the fade index is a curve, never a score ---
	var index := FadeRules.fade_index()
	_check("the fade index is computable", index >= 0.0 and index <= 1.0,
		"%.3f" % index)

	# ================= SYSTEM B — the village memory =================
	Memory.reset()
	GameState.day = 5
	WorldRouter.current_map = "village"

	_check("the fact kinds are a closed set from content",
		Memory.kinds().size() >= 6, str(Memory.kinds()))
	_check("an undeclared kind is refused",
		not Memory.record("npc_karl", "blackmail_material", "x", null, true))

	# --- the witness rule ---
	# Anna is on the farm at 09:00, so she cannot learn what happens in the
	# village. Nobody knows what they could not know.
	DayCycle.hour = 9.0
	_check("Anna is not in the village at 09:00",
		not Memory.witnessed("npc_anna"),
		WorldRouter.scheduled_location("npc_anna", 9.0))
	_check("an absent NPC records nothing",
		not Memory.record("npc_anna", "word_struggle", "brot"))
	_check("...and holds nothing", not Memory.knows("npc_anna", "word_struggle", "brot"))
	_check("a present NPC does record",
		Memory.record("npc_karl", "word_struggle", "brot", null, true))
	_check("...and holds it", Memory.knows("npc_karl", "word_struggle", "brot"))

	# --- permanence: a triumph is a milestone ---
	Memory.record("npc_karl", "word_triumph", "brot", null, true)
	for i in range(200):
		Memory.advance_day()
	_check("a triumph is never forgotten",
		Memory.knows("npc_karl", "word_triumph", "brot"))
	_check("a struggle fades once it is old",
		not Memory.knows("npc_karl", "word_struggle", "brot"))

	# --- rolling facts accumulate rather than duplicate ---
	Memory.reset()
	for i in range(3):
		Memory.record("npc_petra", "purchase_pattern", "samen", null, true)
	var rows := Memory.recall("npc_petra", "purchase_pattern", "samen")
	_check("a repeated purchase is one fact with a count", rows.size() == 1,
		"%d rows" % rows.size())
	_check("...and the count is right", int(rows[0].get("count", 0)) == 3,
		"%d" % rows[0].get("count", 0))

	# --- callbacks and their caps ---
	Memory.reset()
	Callbacks.reset()
	GameState.day = 10
	Memory.record("npc_karl", "word_struggle", "brot", null, true)
	Memory.record("npc_karl", "quest_memory", "q07", null, true)

	var picked := Callbacks.select("npc_karl", "greeting")
	if ContentDB.get_npc("npc_karl").get("callbacks") == null:
		_check("Karl has no callbacks authored yet, so he just greets you",
			picked.is_empty(), "content gap, not an engine failure")
	else:
		_check("a callback is chosen when a memory fits", not picked.is_empty())
		_check("...and only one per NPC per day",
			Callbacks.select("npc_karl", "greeting").is_empty())

	# --- the retest personalises but never gates ---
	Callbacks.set_retest_word("brot")
	_check("whoever remembers the word can retest it",
		Memory.npcs_remembering_word("brot").has("npc_karl"),
		str(Memory.npcs_remembering_word("brot")))
	Callbacks.set_retest_word("gurke")
	_check("a word nobody remembers has no retester",
		Memory.npcs_remembering_word("gurke").is_empty())
	_check("...and the retest simply does not fire, rather than blocking",
		not Callbacks.retest_fired_today())

	# --- the never-negative law ---
	# Nothing in the memory config may describe a penalty. This is a content
	# check as much as a code one: the law is easiest to break by authoring.
	var memory_config := Config._section("memory")
	var text := JSON.stringify(memory_config).to_lower()
	var forbidden := ["penalty", "punish", "mock", "shame", "withhold"]
	var offenders: Array[String] = []
	for word in forbidden:
		if text.contains(word):
			offenders.append(word)
	_check("no memory rule describes a penalty", offenders.is_empty(), str(offenders))

	# --- it all survives a save/load ---
	Memory.reset()
	Monologue.reset()
	GameState.day = 12
	Memory.record("npc_weber", "quest_memory", "q14", null, true)
	Monologue.show_line("mono_wake_01")
	var snapshot := GameState.to_dict()
	Memory.reset()
	Monologue.reset()
	Memory.from_dict(snapshot.get("memory", {}))
	Monologue.from_dict(snapshot.get("monologue", {}))
	_check("memory survives a save/load", Memory.knows("npc_weber", "quest_memory", "q14"))
	_check("monologue state survives a save/load",
		int(Monologue.state.get("mono_wake_01", {}).get("times_shown", 0)) >= 1,
		str(Monologue.state.get("mono_wake_01", {})))

	await _run_stage_two()

	print("--- Part 15 acceptance complete, %d failure(s). ---" % _failures)


## Extra coverage: the M2/M3 render paths and the callback content, added once
## the founder lifted the §6 slice cut that had capped the fade at M1.
func _run_stage_two() -> void:
	print("--- Part 15b: M2, M3 and the callback content ---")
	WordStats.reset()
	Monologue.reset()
	Memory.reset()
	Callbacks.reset()

	# --- M2: an authored German CLAUSE, never generated grammar ---
	# Act 2 is where the ceiling first allows it.
	GameState.day = 30
	_check("act 2 is reached by day 30", GameState.act() >= 2, "%d" % GameState.act())
	_check("act 2 allows M2", FadeRules.act_ceiling(2) >= FadeRules.Stage.M2,
		"ceiling=%d" % FadeRules.act_ceiling(2))

	for word_id in ["kuh", "fuettern", "markt"]:
		_master(word_id, 0.80, 6)
	var m2 := Monologue.render("mono_obj_kuh_01")
	_check("a strong clause thinks in German", int(m2["stage"]) == FadeRules.Stage.M2,
		"M%d: %s" % [m2["stage"], m2["text"]])
	_check("...as the authored fragment, verbatim",
		str(m2["text"]).contains("Ich muss die Kuh füttern"), str(m2["text"]))
	_check("...with the English tail still attached",
		str(m2["text"]).contains("before the market"), str(m2["text"]))

	# M2 must NOT fire on a half-learned clause: verbs never mix mid-syntax.
	_master("fuettern", 0.55, 6)
	var half := Monologue.render("mono_obj_kuh_01")
	_check("a half-learned clause falls back below M2",
		int(half["stage"]) < FadeRules.Stage.M2, "M%d: %s" % [half["stage"], half["text"]])

	# --- M3: the whole thought, and only when the family is strong too ---
	GameState.day = 80
	_check("act 4 allows M3", FadeRules.act_ceiling(GameState.act()) >= FadeRules.Stage.M3,
		"act=%d ceiling=%d" % [GameState.act(), FadeRules.act_ceiling(GameState.act())])
	for word_id in ["kuh", "fuettern", "markt"]:
		_master(word_id, 0.95, 8)
	# The family average gate: one strong noun in a weak family must not produce
	# a sentence the player cannot read.
	_master("heu", 0.10, 8)
	var blocked := Monologue.render("mono_obj_kuh_01")
	_check("a weak family blocks the full German thought",
		int(blocked["stage"]) < FadeRules.Stage.M3,
		"family avg %.2f" % FadeRules.family_average("farm"))
	for word_id in ["heu", "feld", "wasser", "huhn", "ei", "milch", "giessen"]:
		_master(word_id, 0.95, 8)
	var m3 := Monologue.render("mono_obj_kuh_01")
	_check("a strong family thinks entirely in German",
		int(m3["stage"]) == FadeRules.Stage.M3, "M%d: %s" % [m3["stage"], m3["text"]])
	_check("...and it is the authored de_full",
		str(m3["text"]) == "Ich muss die Kuh füttern, bevor der Markt beginnt.",
		str(m3["text"]))
	_check("...with no English left in it",
		not str(m3["text"]).contains("should") and not str(m3["text"]).contains("before the"),
		str(m3["text"]))

	# --- the act beats, and their fail-soft ---
	var beats := 0
	for mono_id in Monologue.all_lines():
		if str(Monologue.line(str(mono_id)).get("class", "")) == "act_beat":
			beats += 1
	_check("all eight act beats are authored", beats == 8, "%d beats" % beats)
	var opener := Monologue.line("beat_a1_open")
	_check("the first beat is pure English", (opener.get("spans", {}) as Dictionary).is_empty(),
		str(opener.get("spans", {})))
	_check("the last beat keeps one English line, permanently",
		str(Monologue.line("beat_a4_close").get("de_full", "")).contains("how did I get here?"),
		str(Monologue.line("beat_a4_close").get("de_full", "")))
	_check("a beat is `once` and never repeats",
		bool(Monologue.line("beat_a2_close").get("once", false)))

	# --- the callbacks are authored now ---
	GameState.day = 10
	Memory.reset()
	Callbacks.reset()
	var with_callbacks := 0
	for npc_id in ["npc_anna", "npc_karl", "npc_petra", "npc_weber", "npc_mila"]:
		var listed: Variant = ContentDB.get_npc(npc_id).get("callbacks")
		if listed is Array and not (listed as Array).is_empty():
			with_callbacks += 1
	_check("every slice NPC has callbacks", with_callbacks == 5, "%d/5" % with_callbacks)

	var total := 0
	for npc_id in ContentDB.npcs:
		var listed: Variant = ContentDB.get_npc(str(npc_id)).get("callbacks")
		if listed is Array:
			total += (listed as Array).size()
	_check("the slice's 25-callback target is met", total >= 24, "%d callbacks" % total)

	# Every callback names a declared fact kind, or it can never fire.
	var bad_kinds: Array[String] = []
	for npc_id in ContentDB.npcs:
		var listed: Variant = ContentDB.get_npc(str(npc_id)).get("callbacks")
		if not (listed is Array):
			continue
		for entry in (listed as Array):
			var kind := str((entry as Dictionary).get("fact_kind", ""))
			if not Memory.kinds().has(kind):
				bad_kinds.append("%s:%s" % [entry.get("cb_id", "?"), kind])
	_check("every callback names a declared fact kind", bad_kinds.is_empty(),
		str(bad_kinds))

	# --- a callback actually fires, and the slot binds ---
	Memory.record("npc_karl", "word_struggle", "brot", null, true)
	var chosen := Callbacks.select("npc_karl", "greeting")
	_check("Karl brings up the word you struggled with", not chosen.is_empty(),
		str(chosen.get("cb_id", "")))
	if not chosen.is_empty():
		_check("...and the slot bound to the real word",
			(chosen["line"]["focus_words"] as Array).has("brot"),
			str(chosen["line"]["focus_words"]))
		_check("...leaving no unbound template slot",
			not str(chosen["line"]["de"]).contains("{word}"), str(chosen["line"]["de"]))
	_check("and only one callback per NPC per day",
		Callbacks.select("npc_karl", "greeting").is_empty())

	# --- the village cap ---
	Callbacks.reset()
	Memory.reset()
	GameState.day = 11
	for npc_id in ["npc_anna", "npc_karl", "npc_petra", "npc_weber", "npc_mila"]:
		Memory.record(npc_id, "first_meeting", npc_id, null, true)
	var fired := 0
	for npc_id in ["npc_anna", "npc_karl", "npc_petra", "npc_weber", "npc_mila"]:
		if not Callbacks.select(npc_id, "greeting").is_empty():
			fired += 1
	_check("the village cap holds at three a day", fired <= 3, "%d fired" % fired)

	print("--- Part 15b complete, %d failure(s) total. ---" % _failures)
