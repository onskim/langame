extends CanvasLayer
## Persistent HUD. Autoloaded, so it survives every scene change — the player
## should not watch their own interface flicker when they walk through a door.

@onready var _day: Label = $Root/Day
@onready var _place: Label = $Root/Place
@onready var _clock: Label = $Root/Clock
@onready var _carry: Label = $Root/Carry
@onready var _task: Label = $Root/Task
@onready var _prompt: Label = $Root/Prompt
@onready var _hint: Label = $Root/Hint


func _ready() -> void:
	_root().set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_prompt.text = ""
	DayCycle.time_changed.connect(func(_h: float) -> void: refresh())


func _root() -> Control:
	return $Root


func refresh() -> void:
	# Talfeld does not use euros. Money is Münzen — gold coins — per Part 12's
	# meter table, and the symbol comes from the strings table so it can become
	# a sprite later without touching this file.
	_day.text = "%s %d   ★%d   %d%s" % [
		Config.ui("day_label"), GameState.day, GameState.total_reputation(),
		GameState.money, Config.ui("coin")]
	_clock.text = DayCycle.clock_string()
	_place.text = WorldRouter.display_name(WorldRouter.current_map)
	_task.text = Quests.active_task_label()
	_hint.text = default_hint()
	if GameState.carrying == "":
		_carry.text = ""
	else:
		# The carried item is shown by its German lemma from content, never a
		# hardcoded string — this label is passive exposure, not chrome.
		var word := ContentDB.get_word(GameState.carrying)
		_carry.text = "%s %s" % [word.get("article", ""), word.get("lemma", "")]


## Contextual prompt ("E  Bäckerei") shown when standing at a door.
func set_prompt(text: String) -> void:
	_prompt.text = text


func set_hint(text: String) -> void:
	_hint.text = text


func default_hint() -> String:
	return Config.ui("hint_controls")
