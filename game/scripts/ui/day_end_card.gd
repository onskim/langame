extends CanvasLayer
## The day-end payoff card. Part 3 §3 min 9–10 and §5, Addendum §6.
##
## "Day-end card: 5 words met (icons, no scores), reputation gained, tomorrow's
## task teased. Save. This card is the session-end ritual for the whole game."
##
## The hard rule it enforces: it shows WORDS MET, never a score, never a
## percentage, never the mastery number. The engine stays hidden (Part 3 §4);
## the player sees a day well spent.

signal dismissed()

@onready var _root: Control = $Root
@onready var _date: Label = $Root/Panel/Date
@onready var _words_title: Label = $Root/Panel/WordsTitle
@onready var _words: VBoxContainer = $Root/Panel/Words
@onready var _rep: Label = $Root/Panel/Rep
@onready var _tomorrow: Label = $Root/Panel/Tomorrow

var is_open: bool = false

## Words first met during the day now ending.
var _day_words: Array[String] = []
var _rep_at_day_start: int = 0
var _tracking_day: int = 0


func _ready() -> void:
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.visible = false
	begin_day(GameState.day)


## Start tracking a fresh day. Called at boot and after each sleep.
func begin_day(day: int) -> void:
	_tracking_day = day
	_day_words.clear()
	_rep_at_day_start = GameState.total_reputation()


## A word met today. Called by the dialogue runner on first exposure.
func note_word(word_id: String) -> void:
	if not _day_words.has(word_id):
		_day_words.append(word_id)


## Show the card for the day that just ended.
func show_card() -> void:
	_date.text = Calendar.date_string(_tracking_day)

	for child in _words.get_children():
		child.queue_free()

	_words_title.visible = not _day_words.is_empty()
	for word_id in _day_words:
		var word := ContentDB.get_word(word_id)
		var label := Label.new()
		# Article + lemma, article-coloured. No English, no score, no count of
		# how well it went — just the words the day contained.
		label.text = ("%s %s" % [word.get("article", ""), word.get("lemma", "")]).strip_edges()
		label.add_theme_color_override("font_color", ContentDB.article_color(word_id))
		label.add_theme_font_size_override("font_size", 15)
		_words.add_child(label)

	var gained := GameState.total_reputation() - _rep_at_day_start
	_rep.text = "★ +%d" % gained if gained > 0 else ""

	_tomorrow.text = _tease_tomorrow()

	_root.visible = true
	is_open = true


func _tease_tomorrow() -> String:
	# Tomorrow's hook, in this order of interest: a festival, then market day,
	# then whatever the weather will make of the farm, then the open task.
	var tomorrow := _tracking_day + 1
	var festival := Calendar.festival_today(tomorrow)
	if not festival.is_empty():
		return "★ %s" % festival.get("name", "")
	if Calendar.is_market_day(tomorrow):
		var markt := ContentDB.get_word("markt")
		return "→ %s" % markt.get("lemma", "")
	var weather_id := Calendar.weather_for(tomorrow)
	var word := ContentDB.get_word(weather_id)
	if not word.is_empty():
		return "→ %s %s" % [word.get("article", ""), word.get("lemma", "")]
	return ""


func dismiss() -> void:
	_root.visible = false
	is_open = false
	begin_day(GameState.day)
	dismissed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if is_open and (event.is_action_pressed("interact") or event.is_action_pressed("phone")):
		dismiss()
		get_viewport().set_input_as_handled()


## Words met today — exposed so the acceptance test can assert the card's
## contents rather than just that it opened.
func words_met_today() -> Array[String]:
	return _day_words.duplicate()
