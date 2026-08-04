extends CanvasLayer
## The player's inner voice. GDD Part 15 §2.1, §2.9.
##
## Deliberately unlike the dialogue bar: this is not someone talking to you, it
## is you thinking. Italic, unboxed, no continue prompt, fades on its own. The
## player should never have to acknowledge a thought — the moment it needs a
## keypress it stops being interior.
##
## German spans render in their ARTICLE COLOUR (Part 3 §6 hues), which is what
## makes "feed die Kuh" a free gender rep every time it appears rather than just
## a translated noun.

const SHOW_SECONDS := 4.2
const FADE_SECONDS := 0.8

var _label: RichTextLabel
var _timer: float = 0.0
var _spans: Array = []

## Words the player tapped for a gloss. A tap means the German was NOT
## understood, so it is a weak-signal miss on that word (Part 15 §2.6) — the
## scheduler should hear about it.
signal gloss_requested(word_id: String)


func _ready() -> void:
	layer = 4
	_build()
	Monologue.thought_ready.connect(_on_thought)


func _build() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.fit_content = true
	_label.scroll_active = false
	_label.mouse_filter = Control.MOUSE_FILTER_PASS
	_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_label.anchor_left = 0.12
	_label.anchor_right = 0.88
	_label.offset_top = 44.0
	_label.offset_bottom = 96.0
	_label.add_theme_font_size_override("normal_font_size", 8)
	_label.add_theme_color_override("default_color", Color(0.93, 0.93, 0.88))
	_label.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.08))
	_label.add_theme_constant_override("outline_size", 3)
	_label.modulate.a = 0.0
	_label.meta_clicked.connect(_on_meta)
	root.add_child(_label)


func _on_thought(text: String, spans: Array, _mono_id: String) -> void:
	_spans = spans
	_label.text = "[i]%s[/i]" % _markup(text, spans)
	_label.modulate.a = 1.0
	_timer = SHOW_SECONDS


## Wrap each German span in its article colour and make it tappable. Built by
## walking the marks BACK TO FRONT so inserting markup never shifts the offsets
## of the marks still to be processed.
func _markup(text: String, spans: Array) -> String:
	var ordered := spans.duplicate()
	ordered.sort_custom(func(a, b): return int(a["start"]) > int(b["start"]))
	for span in ordered:
		var start := int(span["start"])
		var length := int(span["length"])
		if start < 0 or start + length > text.length():
			continue
		var words: Array = span.get("words", [])
		var colour := Color(0.95, 0.85, 0.55)
		if not words.is_empty():
			colour = ContentDB.article_color(str(words[0]))
		var piece := text.substr(start, length)
		var wrapped := "[url=%s][color=#%s]%s[/color][/url]" % [
			str(words[0]) if not words.is_empty() else "", colour.to_html(false), piece]
		text = text.substr(0, start) + wrapped + text.substr(start + length)
	return text


func _on_meta(meta: Variant) -> void:
	var word_id := str(meta)
	if word_id == "":
		return
	# The gloss always exists, because only words met three times ever swap.
	gloss_requested.emit(word_id)
	var word := ContentDB.get_word(word_id)
	HUD.set_prompt("%s %s — %s" % [word.get("article", ""), word.get("lemma", ""),
		word.get("english", "")])
	WordStats.record_repair(word_id, GameState.day)


func _process(delta: float) -> void:
	if _timer <= 0.0:
		return
	_timer -= delta
	if _timer <= FADE_SECONDS:
		_label.modulate.a = clampf(_timer / FADE_SECONDS, 0.0, 1.0)


func is_showing() -> bool:
	return _timer > 0.0


func current_text() -> String:
	return _label.text
