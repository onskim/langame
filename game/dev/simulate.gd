extends Node
## 30-day bot player — GDD Part 10 §6 Week 4 acceptance:
## "simulate.py 30-day bot run: review load stays 5–15/day, no starved words."
##
## Runs inside Godot on purpose. The scheduler, mastery and SM-2 code the bot
## exercises is the SAME code the game runs — a Python reimplementation would
## drift from the engine and prove nothing.
##
## Driven by tools/simulate.py, which parses the JSON on stdout.
##
##   godot --headless res://dev/simulate.tscn -- --days=30 --accuracy=0.8

var days: int = 30
## Probability the bot answers a review correctly. A perfect bot would hide
## exactly the starvation the acceptance test exists to catch.
var accuracy: float = 0.8
var seed_value: int = 12345

var _rng := RandomNumberGenerator.new()
var _log: Array = []


func _ready() -> void:
	_parse_args()
	_rng.seed = seed_value
	_run()
	get_tree().quit(0)


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--days="):
			days = int(arg.trim_prefix("--days="))
		elif arg.begins_with("--accuracy="):
			accuracy = float(arg.trim_prefix("--accuracy="))
		elif arg.begins_with("--seed="):
			seed_value = int(arg.trim_prefix("--seed="))


func _run() -> void:
	WordStats.reset()

	# The full A1 word list is not authored yet (that is Week 8), so the bot
	# learns a synthetic pool the same size as the slice target. Every word
	# still flows through the real WordStats/Mastery/Scheduler code.
	var pool := _word_pool()

	var introduced: Array[String] = []
	var day := 1

	while day <= days:
		# --- morning: the scheduler decides what today is about -------------
		var plan := Scheduler.plan_day(day, [])
		var want: Array = plan["wantlist"]
		var review_load: int = want.size()

		# --- the day's encounters: the bot meets every wanted word ----------
		for word_id in want:
			var correct := _rng.randf() < accuracy
			WordStats.record(word_id, correct, day)

		# --- new words, only if the scheduler allows them -------------------
		var budget: int = plan["new_budget"]
		var added := 0
		for word_id in pool:
			if added >= budget:
				break
			if introduced.has(word_id):
				continue
			WordStats.introduce(word_id, day)
			# Being introduced IS an encounter — this is the first exposure.
			WordStats.record(word_id, true, day)
			introduced.append(word_id)
			added += 1

		var starved := Scheduler.starved_words(day)
		_log.append({
			"day": day,
			"review_load": review_load,
			"new_words": added,
			"introduced_total": introduced.size(),
			"starved": starved.size(),
			"starved_ids": starved,
			"mean_mastery": _mean_mastery(introduced),
		})
		day += 1

	_report(introduced)


func _word_pool() -> Array[String]:
	# Real content words first, then synthetic filler to reach the slice size,
	# so the run exercises the same code path at realistic scale (Part 10 §5:
	# 84-word slice).
	var pool: Array[String] = []
	var ids := ContentDB.words.keys()
	ids.sort()
	for word_id in ids:
		pool.append(word_id)
	var i := pool.size()
	while pool.size() < 84:
		pool.append("sim_word_%02d" % i)
		i += 1
	return pool


func _mean_mastery(introduced: Array) -> float:
	if introduced.is_empty():
		return 0.0
	var total := 0.0
	for word_id in introduced:
		total += float(WordStats.get_stat(word_id).get("mastery", 0.0))
	return total / float(introduced.size())


func _report(introduced: Array) -> void:
	var loads: Array[int] = []
	for row in _log:
		loads.append(int(row["review_load"]))

	# Day 1 has nothing introduced yet, so its load is trivially 0. The band
	# applies once the run is warm.
	var warm: Array[int] = []
	for i in range(loads.size()):
		if i >= 2:
			warm.append(loads[i])

	var result := {
		"days": days,
		"accuracy": accuracy,
		"seed": seed_value,
		"introduced_total": introduced.size(),
		"review_load_min": warm.min() if warm.size() > 0 else 0,
		"review_load_max": warm.max() if warm.size() > 0 else 0,
		"review_load_mean": _mean_int(warm),
		"starved_total": _log[-1]["starved"] if _log.size() > 0 else 0,
		"starved_ids": _log[-1]["starved_ids"] if _log.size() > 0 else [],
		"mean_mastery_final": _log[-1]["mean_mastery"] if _log.size() > 0 else 0.0,
		"daily": _log,
	}
	print("SIMULATION_JSON_BEGIN")
	print(JSON.stringify(result))
	print("SIMULATION_JSON_END")


func _mean_int(values: Array[int]) -> float:
	if values.is_empty():
		return 0.0
	var total := 0
	for v in values:
		total += v
	return float(total) / float(values.size())
