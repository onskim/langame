extends Node
## Per-word learner state. GDD Part 10 §3 (player.db `word_stats`).
##
## Week 4 keeps this in memory and saves it as JSON alongside the rest of the
## run state. It mirrors the player.db columns exactly so the Week 5+ move to
## SQLite is a storage swap, not a redesign.
##
## The player NEVER sees these numbers. The Notebook shows knowledge, never
## scores (Part 3 §4) — this is the hidden engine behind it.

const FIELDS := {
	"times_seen": 0, "times_heard": 0, "times_correct": 0, "times_wrong": 0,
	"times_spoken": 0, "pron_avg": 0.0, "pron_fails_row": 0, "repair_uses": 0,
	"prod_attempts": 0, "prod_successes": 0,
	"mastery": 0.0, "ease": 2.5, "interval_days": 0.0,
	"due_day": 0, "last_seen_day": 0, "intro_day": 0, "drill_cycles": 0,
}

var stats: Dictionary = {}


func has_word(word_id: String) -> bool:
	return stats.has(word_id)


func get_stat(word_id: String) -> Dictionary:
	if not stats.has(word_id):
		stats[word_id] = FIELDS.duplicate(true)
	return stats[word_id]


## First encounter. A word is only "introduced" once.
func introduce(word_id: String, day: int) -> void:
	if stats.has(word_id):
		return
	var s := get_stat(word_id)
	s["intro_day"] = day
	s["last_seen_day"] = day
	s["due_day"] = day + 1
	s["interval_days"] = 1.0
	s["ease"] = float(Config.sm2("initial_ease", 2.5))
	print("[words] introduced %s on day %d" % [word_id, day])


func introduced_words() -> Array:
	return stats.keys()


## Log one encounter. `spoken` successes count double into recognition
## (Addendum §1); production is tracked on its own counters so the double-count
## cannot distort the success rate.
##
## `credit` scales how much this encounter advances the schedule. A silent
## answer is a legitimate answer at REDUCED credit (Addendum §1) — it must not
## push the word's next appearance out as far as a spoken one.
func record(word_id: String, correct: bool, day: int, spoken: bool = false,
		credit: float = 1.0) -> void:
	var s := get_stat(word_id)
	s["times_seen"] += 1
	s["last_seen_day"] = day
	var weight := int(Config.mastery("spoken_multiplier", 2.0)) if spoken else 1
	if spoken:
		s["times_spoken"] += 1
		s["prod_attempts"] += 1
		if correct:
			s["prod_successes"] += 1
	if correct:
		s["times_correct"] += weight
		s["pron_fails_row"] = 0
	else:
		s["times_wrong"] += 1
	Mastery.update(s, day)
	Scheduler.apply_sm2(s, correct, day, credit)


## Recency only — no correctness, no SM-2 advance. A German word rendered in a
## thought keeps that word warm, but a thought must never satisfy a due review:
## reading your own mind is not retrieval (Part 15 §2.6, Part 9 m3/m5).
func touch(word_id: String, day: int) -> void:
	if not has_word(word_id):
		return
	var s := get_stat(word_id)
	s["last_seen_day"] = day
	Mastery.update(s, day)


func record_repair(word_id: String, day: int) -> void:
	# Repair use is never penalised, but it is a weak-signal miss (Part 3 §2).
	var s := get_stat(word_id)
	s["repair_uses"] += 1
	s["last_seen_day"] = day
	Mastery.update(s, day)


func to_dict() -> Dictionary:
	return stats.duplicate(true)


func from_dict(data: Dictionary) -> void:
	stats = {}
	for word_id in data:
		var s := FIELDS.duplicate(true)
		for key in data[word_id]:
			if s.has(key):
				s[key] = data[word_id][key]
		stats[word_id] = s


func reset() -> void:
	stats = {}
