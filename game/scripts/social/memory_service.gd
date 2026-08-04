extends Node
## The village memory. GDD Part 15 §3.
##
## NPCs remember what happened *with them* — who saw you struggle with a word,
## who coached you through it, what you always order — and use it to retest,
## celebrate and reward. This is the mechanical answer to "the village likes me
## more this week", and it turns the scheduler from a system into a person:
## not "a review was scheduled" but "Karl remembers, and Karl asks."
##
## Two laws are enforced here rather than trusted to content:
##
##   THE WITNESS RULE — `record()` refuses a fact for an NPC who was not there.
##   Nobody knows what they could not know. Break this and the cast stops being
##   characters and starts being surveillance.
##
##   THE NEVER-NEGATIVE LAW — nothing in this file returns a penalty, and
##   `word_struggle` exists only so somebody can warmly offer you another go.
##
## Replaces Part 10 §3's `npc_state.memory_flags` blob, which could hold
## anything and be read by anyone.

signal fact_recorded(npc_id: String, kind: String, ref_id: String)

## npc_id -> Array[fact]. A fact is
## {kind, ref_id, value, day, strength, source, times_referenced, last_referenced_day}
var facts: Dictionary = {}


func _cfg() -> Dictionary:
	return Config._section("memory")


func kinds() -> Array:
	var listed: Variant = _cfg().get("kinds")
	return listed if listed is Array else []


func is_permanent(kind: String) -> bool:
	var listed: Variant = _cfg().get("permanent")
	return listed is Array and (listed as Array).has(kind)


func for_npc(npc_id: String) -> Array:
	var found: Variant = facts.get(npc_id)
	return found if found is Array else []


## Every fact of one kind that an NPC holds.
func recall(npc_id: String, kind: String, ref_id: String = "") -> Array:
	var found: Array = []
	for fact in for_npc(npc_id):
		if str(fact.get("kind", "")) != kind:
			continue
		if ref_id != "" and str(fact.get("ref_id", "")) != ref_id:
			continue
		found.append(fact)
	return found


func knows(npc_id: String, kind: String, ref_id: String = "") -> bool:
	return not recall(npc_id, kind, ref_id).is_empty()


## Was this NPC actually there? The witness rule in one function.
##
## An NPC witnesses what happens on the map they are currently on. Everything
## else has to come through gossip, which the slice deliberately does not build
## (§6 cut list) — so for now, if they were not there, they do not know.
func witnessed(npc_id: String) -> bool:
	if npc_id == "":
		return false
	var where := WorldRouter.scheduled_location(npc_id, DayCycle.hour)
	return WorldRouter.map_of_location(where) == WorldRouter.current_map


## Record a fact against an NPC. Refuses silently-wrong input loudly.
func record(npc_id: String, kind: String, ref_id: String = "",
		value: Variant = null, force: bool = false) -> bool:
	if npc_id == "" or npc_id == "auto":
		return false
	if not kinds().has(kind):
		push_error("[memory] '%s' is not a declared fact kind" % kind)
		return false
	# `force` is for facts the NPC is definitionally party to — their own quest
	# completing, their own shop being bought from — where presence is implied
	# by the event itself rather than by where they happen to be standing.
	if not force and not witnessed(npc_id):
		return false

	var existing := recall(npc_id, kind, ref_id)
	if not existing.is_empty():
		# Rolling kinds accumulate rather than duplicate: "you have ordered this
		# three times" is one fact with a count, not three facts.
		var fact: Dictionary = existing[0]
		fact["value"] = value if value != null else fact.get("value")
		fact["day"] = GameState.day
		fact["strength"] = 1.0
		fact["count"] = int(fact.get("count", 1)) + 1
		fact_recorded.emit(npc_id, kind, ref_id)
		return true

	if not facts.has(npc_id):
		facts[npc_id] = []
	facts[npc_id].append({
		"kind": kind, "ref_id": ref_id, "value": value,
		"day": GameState.day, "strength": 1.0, "count": 1,
		"source": "direct", "times_referenced": 0, "last_referenced_day": -1,
	})
	fact_recorded.emit(npc_id, kind, ref_id)
	print("[memory] %s now remembers %s(%s)" % [npc_id, kind, ref_id])
	return true


func mark_referenced(npc_id: String, kind: String, ref_id: String) -> void:
	for fact in recall(npc_id, kind, ref_id):
		fact["times_referenced"] = int(fact.get("times_referenced", 0)) + 1
		fact["last_referenced_day"] = GameState.day


## Nightly decay and prune. Permanent kinds are untouched — a triumph is a
## milestone, and a village that forgets the day you finally got it right is
## working against the only reward the game really has.
func advance_day() -> void:
	var multiplier := float((_cfg().get("decay", {}) as Dictionary).get("nightly_multiplier", 0.98))
	var floor_value := float((_cfg().get("decay", {}) as Dictionary).get("prune_below", 0.15))
	var pruned := 0
	for npc_id in facts:
		var keep: Array = []
		for fact in facts[npc_id]:
			if is_permanent(str(fact.get("kind", ""))):
				keep.append(fact)
				continue
			fact["strength"] = float(fact.get("strength", 1.0)) * multiplier
			if float(fact["strength"]) >= floor_value:
				keep.append(fact)
			else:
				pruned += 1
		facts[npc_id] = keep
	if pruned > 0:
		print("[memory] pruned %d faded fact(s)" % pruned)


## Which NPCs hold any memory of a word — used by the morning retest to find
## somebody who has a reason to ask.
func npcs_remembering_word(word_id: String) -> Array[String]:
	var found: Array[String] = []
	for npc_id in facts:
		for kind in ["word_struggle", "drill_coached", "word_triumph"]:
			if knows(str(npc_id), kind, word_id) and not found.has(str(npc_id)):
				found.append(str(npc_id))
	return found


func total_facts() -> int:
	var total := 0
	for npc_id in facts:
		total += (facts[npc_id] as Array).size()
	return total


func reset() -> void:
	facts.clear()


func to_dict() -> Dictionary:
	return facts.duplicate(true)


func from_dict(data: Variant) -> void:
	facts.clear()
	if data is Dictionary:
		for npc_id in (data as Dictionary):
			var listed: Variant = (data as Dictionary)[npc_id]
			if listed is Array:
				facts[str(npc_id)] = (listed as Array).duplicate(true)
