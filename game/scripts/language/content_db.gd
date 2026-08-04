extends Node
## Read-only content access. GDD Part 4 §architecture.
##
## Loads the bundle compiled from content/*.yaml by tools/compile_db.py.
## Engine code NEVER contains a German string — every German byte in the game
## comes through here (repo CLAUDE.md hard rule).

const BUNDLE_PATH := "res://assets/content/content.json"

var words: Dictionary = {}
var npcs: Dictionary = {}
var lines: Dictionary = {}
var quests: Dictionary = {}

var loaded: bool = false


func _ready() -> void:
	load_bundle()


func load_bundle() -> bool:
	if not FileAccess.file_exists(BUNDLE_PATH):
		push_error("ContentDB: %s missing — run tools/compile_db.py" % BUNDLE_PATH)
		return false
	var file := FileAccess.open(BUNDLE_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("ContentDB: bundle is not a JSON object")
		return false

	var bundle: Dictionary = parsed
	words = bundle.get("words", {})
	npcs = bundle.get("npcs", {})
	lines = bundle.get("lines", {})
	quests = bundle.get("quests", {})
	loaded = true
	print("[content] %d words, %d npcs, %d lines, %d quests"
		% [words.size(), npcs.size(), lines.size(), quests.size()])
	return true


func get_line(line_id: String) -> Dictionary:
	return lines.get(line_id, {})


func get_word(word_id: String) -> Dictionary:
	return words.get(word_id, {})


func get_quest(quest_id: String) -> Dictionary:
	return quests.get(quest_id, {})


func get_npc(npc_id: String) -> Dictionary:
	return npcs.get(npc_id, {})


## Display name for an NPC — from content, never hardcoded.
func npc_name(npc_id: String) -> String:
	return get_npc(npc_id).get("name", "")


## True when this line's German has not passed the native-review gate.
## Dev builds watermark it so unreviewed content is impossible to miss.
func is_draft(line_id: String) -> bool:
	return bool(get_line(line_id).get("draft", true))


## Article-gender hue, Part 11 §2 reserved colors.
func article_color(word_id: String) -> Color:
	match get_word(word_id).get("article", ""):
		"der": return Color("#4A90D9")
		"die": return Color("#D94A6A")
		"das": return Color("#4AB57A")
	return Color.WHITE
