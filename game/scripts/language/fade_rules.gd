extends Node
class_name FadeRules
## Gate math for the fading inner monologue. GDD Part 15 §2.1–§2.2.
##
## Pure decisions, no rendering and no state: given a word (or a span of words),
## may it think in German yet? Kept separate from the engine so the thresholds
## can be tested directly, which matters because these numbers ARE the felt
## pacing of the whole game.
##
## Every threshold comes from `config/monologue_fade.yaml`. Nothing here is a
## literal.

enum Stage { M0 = 0, M1 = 1, M2 = 2, M3 = 3 }


static func _cfg() -> Dictionary:
	return Config._section("monologue_fade")


static func _gates() -> Dictionary:
	var block: Variant = _cfg().get("gates")
	return block if block is Dictionary else {}


static func swap_on_mastery() -> float:
	return float(_gates().get("m1_mastery", 0.50))


static func swap_off_mastery() -> float:
	return float(_cfg().get("swap_off_mastery", 0.40))


static func min_times_seen() -> int:
	return int(_gates().get("m1_times_seen", 3))


static func max_swaps() -> int:
	return int(_cfg().get("max_swaps_per_line", 3))


static func act_ceiling(act: int) -> int:
	var block: Variant = _cfg().get("act_ceilings")
	if block is Dictionary:
		var found: Variant = (block as Dictionary).get(act)
		if found == null:
			found = (block as Dictionary).get(str(act))
		if found != null:
			return int(found)
	return int(Stage.M1)


static func is_struktur(word_id: String) -> bool:
	var listed: Variant = _cfg().get("struktur_whitelist")
	return listed is Array and (listed as Array).has(word_id)


## May this word appear in German inside a thought?
##
## `already_german` implements the hysteresis: a word that swapped last time
## keeps its German down to `swap_off`, rather than flipping back the instant it
## dips under the swap-on threshold. Without the gap a word sitting near the
## line would alternate language between renders, which reads as a rendering bug
## instead of as progress.
static func word_swaps(word_id: String, already_german: bool = false) -> bool:
	if word_id == "":
		return false
	# `get_stat` creates a blank row on demand, so emptiness never signals
	# "unmet" — has_word does. A word the player has never met must never
	# appear in a thought, whatever its default mastery reads as.
	if not WordStats.has_word(word_id):
		return false
	var stat := WordStats.get_stat(word_id)
	var mastery := float(stat.get("mastery", 0.0))
	var floor_value := swap_off_mastery() if already_german else swap_on_mastery()
	if mastery < floor_value:
		return false
	# The monologue NEVER introduces vocabulary (Part 4 §4, restated in §2.1
	# rule 5): a German span the player has not met would be a word with no
	# gloss and no way in. Structure words are the deliberate exception, and
	# only inside authored fragments, because quests cannot teach them.
	if is_struktur(word_id):
		return true
	return int(stat.get("times_seen", 0)) >= min_times_seen()


## Every word in a span must clear the gate — a half-German noun phrase is not
## code-switching, it is a bug.
static func span_swaps(word_ids: Array, already_german: bool = false) -> bool:
	if word_ids.is_empty():
		return false
	for word_id in word_ids:
		if not word_swaps(str(word_id), already_german):
			return false
	return true


static func span_swaps_at(word_ids: Array, threshold: float) -> bool:
	if word_ids.is_empty():
		return false
	for word_id in word_ids:
		var word := str(word_id)
		if is_struktur(word):
			continue
		if not WordStats.has_word(word):
			return false
		if float(WordStats.get_stat(word).get("mastery", 0.0)) < threshold:
			return false
	return true


static func m2_ready(word_ids: Array) -> bool:
	return span_swaps_at(word_ids, float(_gates().get("m2_mastery", 0.75)))


## The whole thought goes German only when every content word is strong AND the
## family as a whole is — one mastered noun in a sea of unknowns should not
## produce a sentence the player cannot read.
static func m3_ready(word_ids: Array, family: String) -> bool:
	if not span_swaps_at(word_ids, float(_gates().get("m3_mastery", 0.75))):
		return false
	return family_average(family) >= float(_gates().get("m3_family_average", 0.80))


static func family_average(family: String) -> float:
	if family == "":
		return 0.0
	var total := 0.0
	var count := 0
	for word_id in WordStats.introduced_words():
		var word := ContentDB.get_word(str(word_id))
		if str(word.get("family", "")) != family:
			continue
		total += float(WordStats.get_stat(str(word_id)).get("mastery", 0.0))
		count += 1
	return total / float(count) if count > 0 else 0.0


## One number, never shown to the player (§2.2). It selects which authored
## variant of a scripted act beat plays, and it is the analytics curve that
## answers "how fast does English retreat" — the game's signature KPI.
static func fade_index() -> float:
	var known := WordStats.introduced_words()
	if known.size() < int((_cfg().get("fade_index", {}) as Dictionary).get("min_words", 5)):
		return 0.0
	var total := 0.0
	for word_id in known:
		total += float(WordStats.get_stat(str(word_id)).get("mastery", 0.0))
	return total / float(known.size())
