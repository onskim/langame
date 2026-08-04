extends Node
## The fading inner monologue. GDD Part 15 §2.
##
## The player character's thoughts are the only English voice in the game, and
## they lose that English word by word as the player's own mastery grows. This
## is the output half of a loop whose input half already exists: NPC lines shed
## English support per-word (Part 4 §5); now the player's own head does too.
##
## Three rules keep it from feeling like a gimmick, and all three live in the
## render below rather than in the content:
##
##   * Nouns bring their articles, article-gender-coloured even inside English
##     syntax — "feed die Kuh" is authentic learner code-switching AND a free
##     article rep every time it renders.
##   * Chunks swap WHOLE. "Guten Morgen" is one thing to know, never three.
##   * It never introduces vocabulary. Only words met three times can swap, so
##     every German span the player sees has a Wörter entry to tap.
##
## Slice cut (§6, binding): M0–M1 only. The M2/M3 paths are gated by the act
## ceiling in config, not stubbed out, so raising the ceiling is a content edit.

signal thought_ready(text: String, spans: Array, mono_id: String)

## mono_id -> {times_shown, last_day, max_stage_shown}
var state: Dictionary = {}

## Starts far in the past so the FIRST thought of a session is never swallowed
## by the cooldown — at boot `get_ticks_msec()` is smaller than the gap itself,
## which silently ate the wake thought on day one.
var _last_shown_msec: int = -10_000_000
## Words currently rendering in German, so hysteresis can hold them there.
var _german_now: Dictionary = {}


func _cfg() -> Dictionary:
	return Config._section("monologue_fade")


func _cooldowns() -> Dictionary:
	var block: Variant = _cfg().get("cooldowns")
	return block if block is Dictionary else {}


func all_lines() -> Dictionary:
	var block: Variant = ContentDB.section("monologue")
	return block if block is Dictionary else {}


func line(mono_id: String) -> Dictionary:
	var found: Variant = all_lines().get(mono_id)
	return found if found is Dictionary else {}


func _record(mono_id: String) -> Dictionary:
	if not state.has(mono_id):
		state[mono_id] = {"times_shown": 0, "last_day": -1, "max_stage_shown": 0}
	return state[mono_id]


## Fire the best-matching thought for a trigger, or nothing at all.
##
## Nothing at all is a legitimate outcome and happens often — a thought that
## fires on every footstep stops being a thought and becomes chatter.
func trigger(trigger_class: String, subkey: String = "") -> String:
	if not _off_cooldown():
		return ""
	var candidates := _candidates(trigger_class, subkey)
	if candidates.is_empty():
		return ""
	var chosen := _pick(candidates)
	if chosen == "":
		return ""
	show_line(chosen)
	return chosen


func _off_cooldown() -> bool:
	var gap := float(_cooldowns().get("min_seconds_between", 25.0))
	return (Time.get_ticks_msec() - _last_shown_msec) / 1000.0 >= gap


func _candidates(trigger_class: String, subkey: String) -> Array[String]:
	var found: Array[String] = []
	var min_days := int(_cooldowns().get("same_line_min_days", 2))
	for mono_id in all_lines():
		var entry := line(str(mono_id))
		if str(entry.get("class", "")) != trigger_class:
			continue
		var want := str(entry.get("subkey", ""))
		if want != "" and want != subkey:
			continue
		var record := _record(str(mono_id))
		# `once` lines are the scripted beats — they must never repeat.
		if bool(entry.get("once", false)) and int(record.get("times_shown", 0)) > 0:
			continue
		var last := int(record.get("last_day", -1))
		if last >= 0 and GameState.day - last < min_days:
			continue
		found.append(str(mono_id))
	return found


## Least-recently-thought wins, weight breaking ties. Picking at random would
## let one line dominate a session; the player would notice their own head
## repeating itself long before they noticed the fade.
func _pick(candidates: Array[String]) -> String:
	var best := ""
	var best_key := INF
	for mono_id in candidates:
		var record := _record(mono_id)
		var key := float(int(record.get("times_shown", 0))) \
			/ maxf(0.01, float(line(mono_id).get("weight", 1.0)))
		if key < best_key:
			best_key = key
			best = mono_id
	return best


## Render one line at the highest stage its words and the act ceiling allow,
## then hand the pieces to whatever is drawing thoughts.
func show_line(mono_id: String) -> void:
	var rendered := render(mono_id)
	if str(rendered.get("text", "")) == "":
		return
	var record := _record(mono_id)
	record["times_shown"] = int(record.get("times_shown", 0)) + 1
	record["last_day"] = GameState.day
	record["max_stage_shown"] = maxi(int(record.get("max_stage_shown", 0)),
		int(rendered.get("stage", 0)))
	_last_shown_msec = Time.get_ticks_msec()

	# Rendered German is a recency TOUCH, never a correctness event: thoughts
	# keep hot words warm, they never satisfy a due review. No free rides —
	# production still rules (Part 9 m3/m5).
	for word_id in rendered.get("swapped_words", []):
		WordStats.touch(str(word_id), GameState.day)

	thought_ready.emit(rendered["text"], rendered["spans"], mono_id)
	print("[monologue] %s at M%d, swapped %s"
		% [mono_id, rendered["stage"], str(rendered["swapped_words"])])


## The render algorithm from Part 15 §2.6.
##
## Returns {text, spans, stage, swapped_words}. `spans` describes where the
## German sits in the string so the bubble can colour it by article gender and
## make it tappable — the zero-frustration guarantee depends on every German
## span having a gloss behind it.
func render(mono_id: String) -> Dictionary:
	var entry := line(mono_id)
	if entry.is_empty():
		return {"text": "", "spans": [], "stage": 0, "swapped_words": []}

	var ceiling := FadeRules.act_ceiling(GameState.act())
	var spans: Dictionary = entry.get("spans", {})
	var focus: Array = entry.get("focus_words", [])

	# M3 — the whole thought in German.
	if ceiling >= FadeRules.Stage.M3:
		var family := str(entry.get("family", ""))
		if str(entry.get("de_full", "")) != "" and FadeRules.m3_ready(focus, family):
			return {"text": str(entry["de_full"]), "spans": [],
				"stage": FadeRules.Stage.M3, "swapped_words": focus}

	# M2 — an authored German clause takes over, with the rest still English.
	if ceiling >= FadeRules.Stage.M2 and entry.has("m2_template"):
		var m2_spans: Dictionary = entry.get("m2_spans", {})
		var ready: Array[String] = []
		for key in m2_spans:
			var span: Dictionary = m2_spans[key]
			if FadeRules.m2_ready(span.get("words", [])):
				ready.append(str(key))
		if not ready.is_empty():
			return _fill(str(entry["m2_template"]), m2_spans, ready,
				FadeRules.Stage.M2)

	# M0/M1 — English syntax, German nouns and chunks intruding.
	var swappable: Array[String] = []
	for key in spans:
		var span: Dictionary = spans[key]
		var words: Array = span.get("words", [])
		var was_german := false
		for word_id in words:
			if _german_now.has(str(word_id)):
				was_german = true
		if FadeRules.span_swaps(words, was_german):
			swappable.append(str(key))
	# Readability cap: past three swaps a thought stops being effortless to
	# read, and an unreadable thought teaches nothing (§2.10).
	if swappable.size() > FadeRules.max_swaps():
		swappable.resize(FadeRules.max_swaps())
	var stage: int = FadeRules.Stage.M1 if not swappable.is_empty() else FadeRules.Stage.M0
	return _fill(str(entry.get("en_template", "")), spans, swappable, stage)


## Substitute the chosen spans into a template, recording where each German
## piece landed so the bubble can colour and gloss it.
func _fill(template: String, spans: Dictionary, chosen: Array, stage: int) -> Dictionary:
	var text := template
	var marks: Array = []
	var swapped: Array[String] = []
	for key in spans:
		var span: Dictionary = spans[key]
		var token := "{%s}" % key
		if not text.contains(token):
			continue
		if chosen.has(str(key)):
			var german := str(span.get("de", ""))
			var at := text.find(token)
			text = text.replace(token, german)
			marks.append({"start": at, "length": german.length(),
				"words": span.get("words", [])})
			for word_id in span.get("words", []):
				swapped.append(str(word_id))
				_german_now[str(word_id)] = true
		else:
			# A span that has not earned German renders its English, and any
			# word in it stops being held German — this is where a decayed word
			# visibly returns to English.
			text = text.replace(token, str(span.get("en", "")))
			for word_id in span.get("words", []):
				_german_now.erase(str(word_id))
	return {"text": text, "spans": marks, "stage": stage, "swapped_words": swapped}


func reset() -> void:
	state.clear()
	_german_now.clear()
	_last_shown_msec = -10_000_000


func to_dict() -> Dictionary:
	return state.duplicate(true)


func from_dict(data: Variant) -> void:
	state.clear()
	if data is Dictionary:
		for mono_id in (data as Dictionary):
			var record: Variant = (data as Dictionary)[mono_id]
			if record is Dictionary:
				state[str(mono_id)] = (record as Dictionary).duplicate()
