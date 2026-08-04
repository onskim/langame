extends Node
## Template binder. GDD Part 10 §4 (scheduler "plan" step), §5.3 side-quests.
##
## A template quest is a shape with holes: `deliver {ITEM} to {NPC}`,
## `fetch {N} {ITEM}`, `feed {ANIMAL}`. The binder fills the holes from the
## day's wantlist, so a side quest is always *about* a word that is fading.
##
## The "seen>=3 rule" (Part 10 §4): a word may only be bound into a template
## once the player has actually met it three times. Templates reinforce; they
## never introduce.

const MIN_SEEN_TO_BIND := 3


## Bind one template against the wantlist. Returns {} when nothing fits —
## a template with no eligible word must not be offered rather than fall back
## to a random word, which would break the "always about a fading word" rule.
func bind(template_id: String, want: Array, day: int) -> Dictionary:
	var quest := ContentDB.get_quest(template_id)
	if quest.is_empty() or quest.get("kind", "") != "template":
		return {}

	var slots: Variant = quest.get("slots")
	if not (slots is Dictionary):
		return {}

	var bound := {}
	var used: Array[String] = []
	for slot_name in (slots as Dictionary):
		var spec: Dictionary = (slots as Dictionary)[slot_name]
		var choice := _pick(spec, want, used, day)
		if choice == "":
			return {}    # unfillable slot -> do not offer this template today
		bound[slot_name] = choice
		used.append(choice)

	return {
		"quest_id": "%s__%s" % [template_id, "_".join(bound.values())],
		"template_id": template_id,
		"bound_slots": bound,
		"day_bound": day,
	}


## Pick the most urgent eligible word for a slot.
func _pick(spec: Dictionary, want: Array, used: Array[String], day: int) -> String:
	var pool: Array[String] = []
	for word_id in want:
		if used.has(word_id):
			continue
		if not _eligible(word_id, spec):
			continue
		pool.append(word_id)
	if pool.is_empty():
		return ""
	pool.sort_custom(func(a: String, b: String) -> bool:
		return Scheduler.urgency(a, day) > Scheduler.urgency(b, day))
	return pool[0]


func _eligible(word_id: String, spec: Dictionary) -> bool:
	var word := ContentDB.get_word(word_id)
	if word.is_empty():
		return false

	# seen>=3 rule: templates reinforce, they never introduce.
	var s := WordStats.get_stat(word_id)
	if int(s.get("times_seen", 0)) < MIN_SEEN_TO_BIND:
		return false

	var want_pos: Variant = spec.get("pos")
	if want_pos != null and word.get("pos", "") != want_pos:
		return false
	var want_family: Variant = spec.get("family")
	if want_family != null and word.get("family", "") != want_family:
		return false
	return true


## How many template side-quests to offer today (Part 10 §4: 2–3).
func daily_template_count() -> int:
	return 3
