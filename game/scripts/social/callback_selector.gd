extends Node
## Which memory an NPC brings up, and when. GDD Part 15 §3.4.
##
## The scoring exists to stop the village becoming a quiz. Retesting a word the
## player is actually forgetting outranks celebrating one they nailed, which
## outranks small talk — and every fact gets less interesting the more often it
## has been mentioned, so nobody develops a catchphrase.
##
## The caps matter as much as the scoring. One callback per NPC per day and
## three across the village: past that the cast stops feeling observant and
## starts feeling scripted. The morning retest is exempt, because it IS the
## curriculum rather than flavour.

signal callback_selected(npc_id: String, cb_id: String, kind: String, ref_id: String)

## day -> {npc_id: count, "_village": count}
var _used_today: Dictionary = {}
## The word the scheduler wants retested today, if any.
var retest_word: String = ""
var _retest_done_day: int = -1


func _cfg() -> Dictionary:
	return Config._section("memory")


func _caps() -> Dictionary:
	var block: Variant = _cfg().get("caps")
	return block if block is Dictionary else {}


func _relevance(kind: String, is_due_word: bool) -> float:
	var block: Variant = _cfg().get("relevance")
	if not (block is Dictionary):
		return 1.0
	var table: Dictionary = block
	if is_due_word and (kind == "word_struggle" or kind == "drill_coached"):
		return float(table.get("word_due_retest", 3.0))
	return float(table.get(kind, table.get("default", 1.0)))


func _today() -> Dictionary:
	var key := str(GameState.day)
	if not _used_today.has(key):
		_used_today[key] = {}
	return _used_today[key]


func _under_caps(npc_id: String) -> bool:
	var used := _today()
	var per_npc := int(_caps().get("per_npc_per_day", 1))
	var per_village := int(_caps().get("per_village_per_day", 3))
	if int(used.get(npc_id, 0)) >= per_npc:
		return false
	return int(used.get("_village", 0)) < per_village


func _spend(npc_id: String) -> void:
	var used := _today()
	used[npc_id] = int(used.get(npc_id, 0)) + 1
	used["_village"] = int(used.get("_village", 0)) + 1


## Callbacks an NPC has authored for a context, from their content entry.
func _authored(npc_id: String, context: String) -> Array:
	var listed: Variant = ContentDB.get_npc(npc_id).get("callbacks")
	if not (listed is Array):
		return []
	var found: Array = []
	for entry in listed:
		if entry is Dictionary and str(entry.get("context", "")) == context:
			found.append(entry)
	return found


## The best callback for this NPC right now, or {} for "just greet them".
##
## Returning {} is the common case and must stay cheap: most greetings are
## ordinary, and an NPC who references a memory every single time you speak to
## them is not warm, they are unnerving.
func select(npc_id: String, context: String = "greeting") -> Dictionary:
	var is_retest := _is_retest_candidate(npc_id)
	if not is_retest and not _under_caps(npc_id):
		return {}

	var best: Dictionary = {}
	var best_score := float(_cfg().get("score_threshold", 0.8))
	for entry in _authored(npc_id, context):
		var kind := str(entry.get("fact_kind", ""))
		for fact in Memory.recall(npc_id, kind):
			var ref_id := str(fact.get("ref_id", ""))
			var due := retest_word != "" and ref_id == retest_word
			# Recency: a fact from today is fresh; one from a season ago is not.
			var age := maxi(1, GameState.day - int(fact.get("day", GameState.day)))
			var recency := 1.0 / (1.0 + float(age) * 0.05)
			# Novelty: the more often it has been raised, the less it is worth.
			var novelty := 1.0 / (1.0 + float(fact.get("times_referenced", 0)))
			var score := _relevance(kind, due) * recency * novelty \
				* float(fact.get("strength", 1.0))
			if score > best_score:
				best_score = score
				best = {"cb_id": str(entry.get("cb_id", "")), "npc_id": npc_id,
					"kind": kind, "ref_id": ref_id, "line": entry,
					"score": score, "retest": due}

	if best.is_empty():
		return {}
	Memory.mark_referenced(npc_id, str(best["kind"]), str(best["ref_id"]))
	if bool(best.get("retest", false)):
		_retest_done_day = GameState.day
	else:
		_spend(npc_id)
	best["line"] = bind_slots(best["line"], str(best["ref_id"]))
	callback_selected.emit(npc_id, str(best["cb_id"]), str(best["kind"]),
		str(best["ref_id"]))
	return best


## Fill `{word}`-class slots from the fact's ref_id (Part 15 §3.7).
##
## One authored template covers a whole family — the side-quest template
## economics applied to memory. Karl's "Na? Sag's noch mal!" works for every
## bakery word he ever coached the player through, and the gesture points at
## whatever that word's object is.
func bind_slots(entry: Dictionary, ref_id: String) -> Dictionary:
	if ref_id == "":
		return entry
	var word := ContentDB.get_word(ref_id)
	var bound := entry.duplicate(true)
	var article := str(word.get("article", ""))
	var lemma := str(word.get("lemma", ref_id))
	var replacements := {
		"{word}": ref_id,
		"{word_lemma}": lemma,
		"{word_with_article}": ("%s %s" % [article, lemma]).strip_edges(),
		"{word_family}": str(word.get("family", "")),
	}
	for field in ["de", "en"]:
		if bound.has(field):
			var text := str(bound[field])
			for token in replacements:
				text = text.replace(token, str(replacements[token]))
			bound[field] = text
	# focus_words is what the scheduler credits, so an unbound "{word}" here
	# would credit a word that does not exist.
	var focus: Variant = bound.get("focus_words")
	if focus is Array:
		var resolved: Array[String] = []
		for item in (focus as Array):
			resolved.append(ref_id if str(item) == "{word}" else str(item))
		bound["focus_words"] = resolved
	return bound


## The morning retest (§3.4): the day's weakest word gets asked by somebody who
## remembers you struggling with it. Memory PERSONALISES the retest — it never
## gates it, so a player who meets nobody holding that memory is still reviewed
## through the ordinary scheduler.
func _is_retest_candidate(npc_id: String) -> bool:
	if retest_word == "" or _retest_done_day == GameState.day:
		return false
	if not bool(_caps().get("retest_exempt", true)):
		return false
	return Memory.npcs_remembering_word(retest_word).has(npc_id)


## Called at day start with the scheduler's weakest reviewed word.
func set_retest_word(word_id: String) -> void:
	retest_word = word_id
	_retest_done_day = -1


func retest_fired_today() -> bool:
	return _retest_done_day == GameState.day


func reset() -> void:
	_used_today.clear()
	retest_word = ""
	_retest_done_day = -1
