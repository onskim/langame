extends CanvasLayer
## Tier I dialogue runner — GDD Part 3 §1 (Action-as-Answer).
##
## The NPC speaks German; the player proves comprehension by DOING, not by
## producing language. No translation is shown. The pointing gesture is the
## comprehension scaffold: when the line names an object, the NPC points and
## the object highlights, so meaning arrives from the world, not from English.
##
## Wrong action -> diegetic recast that reteaches rather than punishes
## (Part 3 §2 repair loop). Repair use is never penalized.

signal line_finished(line_id: String)
signal objective_set(objective: Dictionary)
signal objective_resolved(correct: bool, target: String)

@onready var _panel: Panel = $Panel
@onready var _speaker: Label = $Panel/Speaker
@onready var _line_label: RichTextLabel = $Panel/Line
@onready var _draft_mark: Label = $Panel/DraftMark
@onready var _repair: Label = $Panel/Repair

var is_open: bool = false
var current_line_id: String = ""
var current_objective: Dictionary = {}

## Nodes that can be pointed at, keyed by the object id used in content
## (obj_cow, obj_hay …). Registered by the scene, not hardcoded here.
var _targets: Dictionary = {}


func _ready() -> void:
	_panel.visible = false


func register_target(object_id: String, node: Node2D) -> void:
	_targets[object_id] = node


## Play one line by id. Returns immediately; listen to line_finished.
func play_line(line_id: String) -> void:
	var line := ContentDB.get_line(line_id)
	if line.is_empty():
		push_error("DialogueRunner: unknown line '%s'" % line_id)
		return

	current_line_id = line_id
	_speaker.text = ContentDB.npc_name(line.get("npc_id", ""))
	_line_label.text = _render_german(line)
	_draft_mark.visible = ContentDB.is_draft(line_id)
	_repair.text = "E continue"
	_panel.visible = true
	is_open = true

	_apply_gestures(line)

	var response: Dictionary = line.get("response", {}) if line.get("response") != null else {}
	var tier_1: Dictionary = response.get("tier_1", {}) if response.get("tier_1") != null else {}
	if not tier_1.is_empty():
		current_objective = tier_1.duplicate()
		objective_set.emit(current_objective)

	print("[dialogue] %s: %s" % [line_id, line.get("de", "")])


## Focus words get their article-gender hue (Part 11 §2). This is the only
## place German text is styled, and it is driven entirely by content.
func _render_german(line: Dictionary) -> String:
	var text: String = line.get("de", "")
	var focus: Array = line.get("focus_words", []) if line.get("focus_words") != null else []
	for word_id in focus:
		var word := ContentDB.get_word(word_id)
		var lemma: String = word.get("lemma", "")
		if lemma == "" or not text.contains(lemma):
			continue
		var hex := ContentDB.article_color(word_id).to_html(false)
		text = text.replace(lemma, "[color=#%s]%s[/color]" % [hex, lemma])
	return text


func _apply_gestures(line: Dictionary) -> void:
	var gestures: Array = line.get("gestures", []) if line.get("gestures") != null else []
	for g in gestures:
		var object_id: String = g.get("point_at", "")
		if not _targets.has(object_id):
			continue
		var node: Node2D = _targets[object_id]
		if node.has_method("highlight"):
			node.highlight(ContentDB.article_color(g.get("word", "")))
		print("[gesture] point at %s (word %s)" % [object_id, g.get("word", "")])


func clear_gestures() -> void:
	for object_id in _targets:
		var node: Node2D = _targets[object_id]
		if node.has_method("clear_highlight"):
			node.clear_highlight()


## The player acted on something. Judge it against the open Tier I objective.
func submit_action(action: String, target: String, item: String = "") -> bool:
	if current_objective.is_empty():
		return false

	var want_action: String = current_objective.get("action", "")
	var want_target: String = current_objective.get("target", "")
	var correct := action == want_action and target == want_target

	# Wrong-action detection logs a miss on the focus word (Part 3 §1) —
	# feeding the pig instead of the cow is a comprehension failure, not noise.
	if not correct:
		_show_recast()
		objective_resolved.emit(false, target)
		return false

	current_objective = {}
	clear_gestures()
	objective_resolved.emit(true, target)
	return true


func _show_recast() -> void:
	var line := ContentDB.get_line(current_line_id)
	var recasts: Dictionary = line.get("recasts", {}) if line.get("recasts") != null else {}
	var text: String = recasts.get("wrong_action", "")
	if text == "":
		return
	_line_label.text = text
	_draft_mark.visible = ContentDB.is_draft(current_line_id)
	_panel.visible = true
	is_open = true
	print("[recast] %s" % text)


func close() -> void:
	_panel.visible = false
	is_open = false
	var finished := current_line_id
	current_line_id = ""
	line_finished.emit(finished)
