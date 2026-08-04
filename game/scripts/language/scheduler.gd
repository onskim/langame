extends Node
## Adaptive scheduler v0. GDD Part 10 §4:
##
##   due      = words where due_day <= today
##              urgency = overdue_days * (1.2 - mastery)
##   wantlist = top 12 by urgency
##   plan     = bind wantlist into offered story quests, 2-3 template side
##              quests, ambient line variants
##   new      = up to N new words, only if len(due) < 8
##   on result: SM-2 update
##
## This is the "world is the SRS" engine. It never surfaces a review queue to
## the player — it decides what the day's quests are *about* (Part 2 §7).

signal day_planned(plan: Dictionary)


func due_words(day: int) -> Array[String]:
	var out: Array[String] = []
	for word_id in WordStats.introduced_words():
		var s := WordStats.get_stat(word_id)
		if int(s.get("due_day", 0)) <= day:
			out.append(word_id)
	return out


func urgency(word_id: String, day: int) -> float:
	var s := WordStats.get_stat(word_id)
	var overdue := float(day - int(s.get("due_day", day)))
	return max(overdue, 0.0) * (1.2 - float(s.get("mastery", 0.0)))


## Top-N due words by urgency — what today's content should be about.
##
## When fewer words are due than the day needs, the list is topped up with the
## words falling due soonest. A cozy day with two things to talk about is a
## thin day; the village should always have enough to say.
func wantlist(day: int) -> Array[String]:
	var due := due_words(day)
	due.sort_custom(func(a: String, b: String) -> bool:
		return urgency(a, day) > urgency(b, day))

	var floor_size := int(Config.scheduler("review_target_min", 5))
	if due.size() < floor_size:
		var upcoming: Array[String] = []
		for word_id in WordStats.introduced_words():
			if not due.has(word_id):
				upcoming.append(word_id)
		upcoming.sort_custom(func(a: String, b: String) -> bool:
			return int(WordStats.get_stat(a).get("due_day", 0)) \
				< int(WordStats.get_stat(b).get("due_day", 0)))
		for word_id in upcoming:
			if due.size() >= floor_size:
				break
			due.append(word_id)

	var limit := int(Config.scheduler("wantlist_size", 12))
	return due.slice(0, min(limit, due.size()))


## Words eligible to be introduced today. New words are held back when the
## review load is already heavy — this is what keeps the day from snowballing.
func new_word_budget(day: int) -> int:
	var due_count := due_words(day).size()
	var block_at := int(Config.scheduler("new_words_blocked_at", 8))
	if due_count >= block_at:
		return 0
	return int(Config.scheduler("new_words_per_day", 5))


## Plan a day: what to review, how many new words we can afford, and which
## quests carry them.
func plan_day(day: int, available_quests: Array) -> Dictionary:
	var want := wantlist(day)
	var budget := new_word_budget(day)
	var plan := {
		"day": day,
		"wantlist": want,
		"new_budget": budget,
		"review_load": want.size(),
		"quests": _rank_quests(available_quests, want),
	}
	day_planned.emit(plan)
	return plan


## Quests whose vocab_tags overlap the wantlist come first — the day's tasks
## are chosen to re-expose what is fading.
func _rank_quests(available: Array, want: Array) -> Array:
	var scored: Array = []
	for quest_id in available:
		var tags: Variant = ContentDB.get_quest(quest_id).get("vocab_tags")
		var overlap := 0
		if tags is Array:
			for t in tags:
				if want.has(t):
					overlap += 1
		scored.append({"quest_id": quest_id, "overlap": overlap})
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["overlap"] > b["overlap"])
	return scored


## SM-2 update after an encounter (Part 10 §4).
## pass: interval *= ease, ease += bonus. hard fail: interval resets.
func apply_sm2(s: Dictionary, correct: bool, day: int) -> void:
	var ease := float(s.get("ease", Config.sm2("initial_ease", 2.5)))
	var interval := float(s.get("interval_days", 0.0))
	var first := float(Config.sm2("first_interval_days", 1.0))
	var second := float(Config.sm2("second_interval_days", 3.0))

	if correct:
		ease += float(Config.sm2("ease_bonus", 0.10))
		if interval <= 0.0:
			interval = first
		elif is_equal_approx(interval, first):
			interval = second
		else:
			interval = interval * ease
	else:
		ease -= float(Config.sm2("ease_penalty", 0.20))
		interval = first

	ease = max(ease, float(Config.sm2("min_ease", 1.3)))

	# DEVIATION from textbook SM-2, forced by the simulation (Part 10 §6 Week 4).
	#
	# Unbounded SM-2 intervals grow 1 -> 3 -> 8 -> 21 -> 55 days. A 30-day run
	# starved 19 words: they were "scheduled" far beyond the horizon and simply
	# stopped appearing. In a flashcard app that is correct behaviour. Here the
	# world IS the review system (Part 2 §7) — a word the player never meets
	# again is a word the village has forgotten, which breaks the fiction as
	# well as the pedagogy.
	#
	# So the interval is capped just inside the starvation window. Mastery still
	# rises and urgency still falls; the word just stays in the world.
	var cap := float(Config.starvation_days() - 1)
	interval = min(interval, cap)

	s["ease"] = ease
	s["interval_days"] = interval
	s["due_day"] = day + int(ceil(interval))


## Words introduced but not seen for longer than the starvation window.
## The acceptance test (Part 10 §6 Week 4) requires this to stay empty.
func starved_words(day: int) -> Array[String]:
	var limit := Config.starvation_days()
	var out: Array[String] = []
	for word_id in WordStats.introduced_words():
		var s := WordStats.get_stat(word_id)
		if day - int(s.get("last_seen_day", day)) > limit:
			out.append(word_id)
	return out
