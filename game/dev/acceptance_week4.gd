extends Node
## Week 4 acceptance (GDD Part 10 §6) — the unit half.
## The 30-day load/starvation half is tools/simulate.py.
##
##   godot --headless res://dev/acceptance_week4.tscn

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
	print("--- Week 4 acceptance: language engine ---")
	WordStats.reset()

	# ---------- config comes from content, not code ----------
	_check("mastery weights loaded from YAML",
		is_equal_approx(float(Config.mastery("recognition", 0.0)), 0.35),
		"recognition=%s" % Config.mastery("recognition"))
	_check("thresholds loaded from YAML",
		int(Config.scheduler("wantlist_size", 0)) == 12,
		"wantlist_size=%s" % Config.scheduler("wantlist_size"))

	# ---------- mastery formula (Part 10 §4) ----------
	var s := WordStats.get_stat("kuh")
	s["times_correct"] = 8
	s["times_wrong"] = 2
	s["pron_avg"] = 80.0
	s["last_seen_day"] = 5
	var m := Mastery.compute(s, 5)
	# 0.35*0.8 + 0.25*0 + 0.25*0.8 + 0.15*1.0 = 0.28 + 0 + 0.20 + 0.15 = 0.63
	_check("mastery matches the spec formula", abs(m - 0.63) < 0.001, "mastery=%.4f" % m)

	var stale := Mastery.compute(s, 19)  # 14 days later: recency fully decayed
	_check("mastery decays with recency", abs(stale - 0.48) < 0.001, "stale=%.4f" % stale)
	_check("recency decay is bounded at 0",
		is_zero_approx(Mastery.recency(s, 99)), "recency=%.3f" % Mastery.recency(s, 99))

	_check("repair use drags recognition",
		Mastery.recognition({"times_correct": 8, "times_wrong": 2, "repair_uses": 4}) < 0.8,
		"recog=%.3f" % Mastery.recognition({"times_correct": 8, "times_wrong": 2, "repair_uses": 4}))

	# ---------- support tiers (Part 10 §4) ----------
	WordStats.reset()
	WordStats.get_stat("kuh")["mastery"] = 0.1
	WordStats.get_stat("heu")["mastery"] = 0.9
	_check("support tier uses the WEAKEST focus word",
		Mastery.support_tier(["kuh", "heu"]) == 0,
		"tier=%d" % Mastery.support_tier(["kuh", "heu"]))
	_check("mastered words reach L3", Mastery.support_tier(["heu"]) == 3,
		"tier=%d" % Mastery.support_tier(["heu"]))

	# ---------- SM-2 with the starvation cap ----------
	WordStats.reset()
	var w := WordStats.get_stat("kuh")
	w["ease"] = 2.5
	w["interval_days"] = 0.0
	Scheduler.apply_sm2(w, true, 1)
	_check("first pass schedules +1 day", is_equal_approx(float(w["interval_days"]), 1.0),
		"interval=%.1f" % w["interval_days"])
	Scheduler.apply_sm2(w, true, 2)
	_check("second pass schedules +3 days", is_equal_approx(float(w["interval_days"]), 3.0),
		"interval=%.1f" % w["interval_days"])

	# Drive many passes: unbounded SM-2 would run away to 50+ days.
	var day := 5
	for i in range(12):
		Scheduler.apply_sm2(w, true, day)
		day += int(w["interval_days"])
	var cap := float(Config.starvation_days() - 1)
	_check("interval is capped inside the starvation window",
		float(w["interval_days"]) <= cap + 0.001,
		"interval=%.1f cap=%.1f" % [w["interval_days"], cap])

	var before_ease := float(w["ease"])
	Scheduler.apply_sm2(w, false, day)
	_check("a fail resets the interval", is_equal_approx(float(w["interval_days"]), 1.0),
		"interval=%.1f" % w["interval_days"])
	_check("a fail lowers ease", float(w["ease"]) < before_ease,
		"%.2f -> %.2f" % [before_ease, w["ease"]])
	_check("ease has a floor", float(w["ease"]) >= float(Config.sm2("min_ease", 1.3)) - 0.001)

	# ---------- scheduler day plan ----------
	WordStats.reset()
	for word_id in ["kuh", "heu", "fuettern"]:
		WordStats.introduce(word_id, 1)
	var plan := Scheduler.plan_day(3, ["q02", "q03"])
	_check("plan returns a wantlist", (plan["wantlist"] as Array).size() > 0,
		str(plan["wantlist"]))
	_check("new words allowed when load is light", int(plan["new_budget"]) == 5,
		"budget=%d" % plan["new_budget"])

	# Heavy load must block new words — this is what stops the day snowballing.
	WordStats.reset()
	for i in range(10):
		WordStats.introduce("sim_%d" % i, 1)
	_check("new words blocked under heavy load",
		Scheduler.new_word_budget(5) == 0,
		"budget=%d due=%d" % [Scheduler.new_word_budget(5), Scheduler.due_words(5).size()])

	# ---------- template binder ----------
	WordStats.reset()
	var bound_early := TemplateBinder.bind("tpl_feed_animal", ["kuh"], 3)
	_check("binder refuses a word seen < 3 times (templates reinforce, never introduce)",
		bound_early.is_empty(), str(bound_early))

	WordStats.introduce("kuh", 1)
	WordStats.get_stat("kuh")["times_seen"] = 5
	var bound := TemplateBinder.bind("tpl_feed_animal", ["kuh"], 3)
	_check("binder fills the slot once the word is known",
		bound.get("bound_slots", {}).get("ANIMAL", "") == "kuh", str(bound))

	WordStats.get_stat("chunk_danke")["times_seen"] = 9
	var wrong_pos := TemplateBinder.bind("tpl_feed_animal", ["chunk_danke"], 3)
	_check("binder respects the slot's part-of-speech", wrong_pos.is_empty(), str(wrong_pos))

	_check("story quests are not bindable as templates",
		TemplateBinder.bind("q02", ["kuh"], 3).is_empty())

	# ---------- persistence ----------
	WordStats.reset()
	WordStats.introduce("kuh", 2)
	WordStats.record("kuh", true, 2)
	var snapshot := WordStats.to_dict()
	var mastery_before := float(WordStats.get_stat("kuh")["mastery"])
	WordStats.reset()
	_check("reset clears the model", WordStats.introduced_words().is_empty())
	WordStats.from_dict(snapshot)
	_check("word_stats survive a round trip",
		is_equal_approx(float(WordStats.get_stat("kuh")["mastery"]), mastery_before),
		"%.4f" % WordStats.get_stat("kuh")["mastery"])

	print("--- Week 4 acceptance complete, %d failure(s). ---" % _failures)
