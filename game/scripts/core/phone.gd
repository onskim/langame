extends CanvasLayer
## The smartphone. Addendum §4 — it REPLACES the Notebook of Part 3 §4 and
## inherits all of that section's rules.
##
## The world is isekai-modern: the player keeps their phone, but it has no
## connection home. Four diegetic apps:
##
##   Wörter    the vocabulary app (Part 3 §4: auto-capture, article colours,
##             translations EARNED after 3 meetings, dog-ear on fading words)
##   Aufgaben  quest log / task board — the re-entry hook
##   Wetter    tomorrow's forecast; reading it is forecast vocabulary practice
##   Karte     map
##
## App names are German because the phone belongs to the village. The app list
## is data, so a fifth app (Kalender, Leute — Part 13 §17) really is one row.

signal opened()
signal closed()

const APPS := [
	{"key": "tasks", "fallback": "Aufgaben"},
	{"key": "words", "fallback": "Wörter"},
	{"key": "weather", "fallback": "Wetter"},
	{"key": "map", "fallback": "Karte"},
]

## Part 3 §4: no English until the word has been met 3+ times.
const TRANSLATION_UNLOCK_MEETINGS := 3

@onready var _root: Control = $Root
@onready var _title: Label = $Root/Panel/Title
@onready var _subtitle: Label = $Root/Panel/Subtitle
@onready var _tabs: HBoxContainer = $Root/Panel/Tabs
@onready var _list: VBoxContainer = $Root/Panel/List
@onready var _empty: Label = $Root/Panel/Empty

var is_open: bool = false
var current_app: int = 0

var _quests: Node = null


func _ready() -> void:
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.visible = false


## Idempotent — the phone persists across places, the quest engine does too.
func setup(quest_engine: Node) -> void:
	if _quests == quest_engine:
		return
	_quests = quest_engine
	_quests.quest_started.connect(func(_q: String) -> void: refresh())
	_quests.step_advanced.connect(func(_q: String, _i: int) -> void: refresh())
	_quests.objective_progress.connect(func(_q: String, _d: int, _n: int) -> void: refresh())
	_quests.quest_completed.connect(func(_q: String, _r: Dictionary) -> void: refresh())
	_quests.quest_started.connect(func(_q: String) -> void: HUD.refresh())


func toggle() -> void:
	if is_open:
		close()
	else:
		open()


func open() -> void:
	refresh()
	_root.visible = true
	is_open = true
	opened.emit()


func close() -> void:
	_root.visible = false
	is_open = false
	closed.emit()


func next_app() -> void:
	current_app = (current_app + 1) % APPS.size()
	refresh()


func open_app(key: String) -> void:
	for i in APPS.size():
		if APPS[i]["key"] == key:
			current_app = i
			break
	refresh()


func current_app_key() -> String:
	return str(APPS[current_app]["key"])


func _unhandled_input(event: InputEvent) -> void:
	if is_open and event.is_action_pressed("phone_next_app"):
		next_app()
		get_viewport().set_input_as_handled()


func refresh() -> void:
	var app: Dictionary = APPS[current_app]
	_title.text = Config.app_name(app["key"], app["fallback"])
	_rebuild_tabs()

	for child in _list.get_children():
		child.queue_free()

	var rows: Array = []
	match str(app["key"]):
		"tasks":
			_subtitle.text = ""
			rows = _task_rows()
		"words":
			# A count of words met — never a score. The player sees knowledge,
			# not numbers (Part 3 §4).
			_subtitle.text = "%d" % WordStats.introduced_words().size()
			rows = _word_rows()
		"weather":
			_subtitle.text = Calendar.date_string(GameState.day)
			rows = _weather_rows()
		"map":
			_subtitle.text = ""
			rows = _map_rows()

	_empty.visible = rows.is_empty()
	for row in rows:
		_list.add_child(_make_row(row))


func _rebuild_tabs() -> void:
	for child in _tabs.get_children():
		child.queue_free()
	for i in APPS.size():
		var tab := Label.new()
		tab.text = Config.app_name(APPS[i]["key"], APPS[i]["fallback"])
		tab.add_theme_font_size_override("font_size", 11)
		var active := i == current_app
		tab.add_theme_color_override("font_color",
			Color(1, 0.95, 0.75) if active else Color(0.55, 0.58, 0.66))
		_tabs.add_child(tab)


## A row is {text, color?, dim?, size?} — the apps stay declarative.
func _make_row(row: Dictionary) -> Label:
	var label := Label.new()
	label.text = str(row.get("text", ""))
	label.add_theme_font_size_override("font_size", int(row.get("size", 14)))
	if row.has("color"):
		label.add_theme_color_override("font_color", row["color"])
	elif bool(row.get("dim", false)):
		label.add_theme_color_override("font_color", Color(0.62, 0.66, 0.74))
	return label


# ------------------------------------------------------------------ Aufgaben

func _task_rows() -> Array:
	var rows: Array = []
	if _quests == null:
		return rows
	if _quests.active_quest != "":
		var label: String = _quests.active_task_label()
		var giver := _giver_name(_quests.active_quest, _quests.current_step())
		rows.append({"text": "• %s — %s" % [giver, label] if giver != "" else "• %s" % label})
	for quest_id in GameState.completed_quests:
		var q := ContentDB.get_quest(quest_id)
		var tags: Variant = q.get("vocab_tags")
		var count := (tags as Array).size() if tags is Array else 0
		rows.append({"text": "✓ %s  (%d)" % [_giver_name(quest_id, {}), count], "dim": true})
	return rows


## Who to go to. Quests given by `auto` still have a speaking NPC — naming them
## beats showing a task with nobody attached.
func _giver_name(quest_id: String, step: Dictionary) -> String:
	var quest := ContentDB.get_quest(quest_id)
	var giver: String = quest.get("giver", "")
	if giver != "" and giver != "auto":
		return ContentDB.npc_name(giver)
	var line_id: String = step.get("line", "")
	if line_id == "":
		var steps: Variant = quest.get("steps")
		if steps is Array and (steps as Array).size() > 0:
			line_id = (steps as Array)[0].get("line", "")
	return ContentDB.npc_name(ContentDB.get_line(line_id).get("npc_id", ""))


# -------------------------------------------------------------------- Wörter

## Part 3 §4: auto-populates on first meeting; article-coloured; NO English
## until met 3+ times (earned, not given); fading words get a dog-ear — the only
## visible surface of the adaptive engine, and it never says "review due";
## grouped by vocabulary family.
func _word_rows() -> Array:
	var rows: Array = []
	var by_family: Dictionary = {}
	for word_id in WordStats.introduced_words():
		var word := ContentDB.get_word(word_id)
		if word.is_empty():
			continue
		var family := str(word.get("family", "?"))
		if not by_family.has(family):
			by_family[family] = []
		by_family[family].append(word_id)

	var families := by_family.keys()
	families.sort()
	for family in families:
		rows.append({"text": str(family).capitalize(), "dim": true, "size": 11})
		var ids: Array = by_family[family]
		ids.sort()
		for word_id in ids:
			rows.append(_word_row(word_id))
	return rows


func _word_row(word_id: String) -> Dictionary:
	var word := ContentDB.get_word(word_id)
	var stat := WordStats.get_stat(word_id)

	var article := str(word.get("article", ""))
	var lemma := str(word.get("lemma", word_id))
	var text := ("%s %s" % [article, lemma]).strip_edges()

	# Translation is earned by meeting the word, not handed over on day one.
	if meetings(word_id) >= TRANSLATION_UNLOCK_MEETINGS:
		text += "   %s" % word.get("english", "")

	# Dog-ear = this word is fading. Never the word "review", never a number.
	if is_fading(word_id):
		text = "⌐ " + text

	return {"text": text, "color": ContentDB.article_color(word_id)}


func meetings(word_id: String) -> int:
	var stat := WordStats.get_stat(word_id)
	return int(stat.get("times_seen", 0)) + int(stat.get("times_heard", 0))


func translation_unlocked(word_id: String) -> bool:
	return meetings(word_id) >= TRANSLATION_UNLOCK_MEETINGS


## Fading = due today or overdue. The engine's only visible surface.
func is_fading(word_id: String) -> bool:
	if not WordStats.has_word(word_id):
		return false
	return int(WordStats.get_stat(word_id).get("due_day", 0)) <= GameState.day


# -------------------------------------------------------------------- Wetter

func _weather_rows() -> Array:
	var rows: Array = []
	rows.append(_forecast_row(GameState.day, "heute"))
	rows.append(_forecast_row(GameState.day + 1, "morgen"))
	if Calendar.is_market_day(GameState.day + 1):
		rows.append({"text": "★ Markt", "color": Color(1, 0.9, 0.6)})
	var festival := Calendar.festival_today(GameState.day)
	if not festival.is_empty():
		rows.append({"text": "★ %s" % festival.get("name", ""), "color": Color(1, 0.9, 0.6)})
	return rows


func _forecast_row(day: int, when: String) -> Dictionary:
	var weather_id := Calendar.weather_for(day)
	var word := ContentDB.get_word(weather_id)
	var lemma := str(word.get("lemma", weather_id))
	var article := str(word.get("article", ""))
	return {
		"text": "%-8s %s %s" % [when, article, lemma],
		"color": ContentDB.article_color(weather_id),
	}


# --------------------------------------------------------------------- Karte

func _map_rows() -> Array:
	var rows: Array = []
	var maps := WorldRouter.maps()
	var ids := maps.keys()
	ids.sort()
	for map_id in ids:
		if str(map_id).begins_with("interior_"):
			continue
		var here: bool = map_id == WorldRouter.current_map
		rows.append({
			"text": "%s %s" % ["▸" if here else " ", WorldRouter.display_name(map_id)],
			"color": Color(1, 0.95, 0.75) if here else Color(0.78, 0.82, 0.9),
		})
	return rows
