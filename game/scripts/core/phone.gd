extends CanvasLayer
## The smartphone (Addendum v0.2 §smartphone). Week 3 ships one app: Aufgaben.
##
## Wörter / Wetter / Karte arrive Week 6, Kalender / Leute later (Part 13).
## The app list is built here so adding one is a row, not a redesign.
##
## App names are German because they are diegetic UI the player learns to read —
## they come from `app_names` below rather than content.db only because they are
## chrome, not curriculum. Everything inside an app comes from content.

signal opened()
signal closed()

@onready var _root: Control = $Root
@onready var _panel: Panel = $Root/Panel
@onready var _title: Label = $Root/Panel/Title
@onready var _list: VBoxContainer = $Root/Panel/List
@onready var _empty: Label = $Root/Panel/Empty

var is_open: bool = false
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


func refresh() -> void:
	_title.text = "Aufgaben"
	for child in _list.get_children():
		child.queue_free()

	var rows := _task_rows()
	_empty.visible = rows.is_empty()
	for row in rows:
		var label := Label.new()
		label.text = row
		label.add_theme_font_size_override("font_size", 14)
		_list.add_child(label)


func _task_rows() -> Array[String]:
	var rows: Array[String] = []
	if _quests == null:
		return rows
	if _quests.active_quest != "":
		var label: String = _quests.active_task_label()
		var giver := _giver_name(_quests.active_quest, _quests.current_step())
		rows.append("• %s — %s" % [giver, label] if giver != "" else "• %s" % label)
	for quest_id in GameState.completed_quests:
		var q := ContentDB.get_quest(quest_id)
		var tags: Variant = q.get("vocab_tags")
		var count := (tags as Array).size() if tags is Array else 0
		rows.append("✓ %s  (%d)" % [_giver_name(quest_id, {}), count])
	return rows


## Who the player should go to. Quests given by `auto` (Q01 onboarding) still
## have a speaking NPC — naming them beats showing a task with no one attached.
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
