extends Node
## Pronunciation drill gate. Addendum v0.2 §2, GDD Part 10 §4.
##
##   pron_fails_row >= 2        -> flag the word, spawn a drill quest
##   2 consecutive passes       -> clear the flag, unlock
##   drill_cycles >= 3          -> auto-clear, but keep the word hot
##   a word may block main progression for at most 1 game-day
##
## The caps are the whole point. A pronunciation gate without a mercy rule is a
## wall a real learner hits and quits at; the founder decision is explicitly a
## 3-cycle cap plus a one-day block ceiling. This file is where "speech-first"
## stops being a slogan and stays humane.

signal word_flagged(word_id: String)
signal drill_spawned(word_id: String, quest_id: String)
signal word_cleared(word_id: String, reason: String)

## word_id -> {consecutive_passes, flagged_on_day}
var flagged: Dictionary = {}


func fails_to_flag() -> int:
	return int(Config.drill("pron_fails_to_flag", 2))


func passes_to_clear() -> int:
	return int(Config.drill("passes_to_clear", 2))


func max_cycles() -> int:
	return int(Config.drill("max_cycles", 3))


func is_flagged(word_id: String) -> bool:
	return flagged.has(word_id)


## Called by SpeechService on every spoken failure.
func on_pronunciation_fail(word_id: String) -> void:
	var s := WordStats.get_stat(word_id)
	if is_flagged(word_id):
		flagged[word_id]["consecutive_passes"] = 0
		return
	if int(s.get("pron_fails_row", 0)) < fails_to_flag():
		return
	_flag(word_id)


## Called on every spoken success.
func on_pronunciation_pass(word_id: String) -> void:
	if not is_flagged(word_id):
		return
	var entry: Dictionary = flagged[word_id]
	entry["consecutive_passes"] = int(entry.get("consecutive_passes", 0)) + 1
	if int(entry["consecutive_passes"]) >= passes_to_clear():
		_record_triumph(word_id)
		_clear(word_id, "passed")


func _flag(word_id: String) -> void:
	var s := WordStats.get_stat(word_id)
	var cycles := int(s.get("drill_cycles", 0))

	# Mercy cap: after three cycles the word stops gating anything. It stays
	# "hot" in the scheduler so it keeps coming back in the world, but it will
	# never again stand between the player and the rest of the game.
	if cycles >= max_cycles():
		s["pron_fails_row"] = 0
		_clear(word_id, "cycle_cap")
		return

	s["drill_cycles"] = cycles + 1
	flagged[word_id] = {
		"consecutive_passes": 0,
		"flagged_on_day": GameState.day,
	}
	# Everyone present sees you struggle. The drill's giver additionally becomes
	# your COACH — which is the fact the celebration later hangs off, so the
	# right person gets to be proud of you (Part 15 §3.6.2).
	for npc_id in WorldRouter.npcs_on_map(WorldRouter.current_map, DayCycle.hour):
		Memory.record(str(npc_id), "word_struggle", word_id)
	word_flagged.emit(word_id)
	print("[drill] flagged %s (cycle %d/%d)" % [word_id, cycles + 1, max_cycles()])
	_spawn_drill(word_id)


## A triumph is permanent. The day you finally said it right is the one thing
## the village is never allowed to forget (Part 15 §3.2).
func _record_triumph(word_id: String) -> void:
	for npc_id in Memory.npcs_remembering_word(word_id):
		Memory.record(str(npc_id), "word_triumph", word_id, null, true)


func _clear(word_id: String, reason: String) -> void:
	flagged.erase(word_id)
	var s := WordStats.get_stat(word_id)
	s["pron_fails_row"] = 0
	# Keep it hot: due tomorrow regardless of how the SM-2 interval had grown.
	s["due_day"] = GameState.day + 1
	word_cleared.emit(word_id, reason)
	print("[drill] cleared %s (%s)" % [word_id, reason])


## Bind a drill-tagged template around the flagged word.
func _spawn_drill(word_id: String) -> void:
	var quest_id := ""
	var ids := ContentDB.quests.keys()
	ids.sort()
	for candidate in ids:
		if ContentDB.get_quest(candidate).get("kind", "") == "drill":
			quest_id = candidate
			break
	if quest_id == "":
		push_warning("[drill] no drill-kind quest authored; word flagged but no quest spawned")
		return
	drill_spawned.emit(word_id, quest_id)
	print("[drill] spawned %s for %s" % [quest_id, word_id])


## A flagged word may block main progression for at most one game-day.
## After that the gate lifts on its own, whatever the player's accuracy.
func blocks_progression(word_id: String) -> bool:
	if not is_flagged(word_id):
		return false
	var flagged_on: int = int(flagged[word_id].get("flagged_on_day", GameState.day))
	if GameState.day > flagged_on:
		_clear(word_id, "one_day_cap")
		return false
	return true


## Any flagged word still gating progression today.
func blocking_words() -> Array[String]:
	var out: Array[String] = []
	for word_id in flagged.keys():
		if blocks_progression(word_id):
			out.append(word_id)
	return out


func to_dict() -> Dictionary:
	return flagged.duplicate(true)


func from_dict(data: Dictionary) -> void:
	flagged = data.duplicate(true)


func reset() -> void:
	flagged = {}
