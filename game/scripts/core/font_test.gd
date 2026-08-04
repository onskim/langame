extends Node2D
## Diacritics smoke test — GDD Part 11 §2 pins a day-1 "Brötchen" render check.
##
## Renders the German special characters at 8px and 16px. If ä ö ü ß render as
## boxes or blanks, the font is unusable for this game and must be replaced
## BEFORE any UI work.
##
## This is the one place a German string in engine code is correct: it is a font
## fixture, not game content. Everything else comes from content.db.

const SAMPLE := "Brötchen — füttern — größer — Straße"
const GLYPHS := "ä ö ü Ä Ö Ü ß"

@onready var _rows: VBoxContainer = $CanvasLayer/Rows


func _ready() -> void:
	_add_row("8px:  " + SAMPLE, 8)
	_add_row("8px:  " + GLYPHS, 8)
	_add_row("16px: " + SAMPLE, 16)
	_add_row("16px: " + GLYPHS, 16)
	_add_row("24px: " + GLYPHS, 24)
	_report()


func _add_row(text: String, size: int) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	_rows.add_child(label)


func _report() -> void:
	var font := ThemeDB.fallback_font
	var missing: Array[String] = []
	for ch in ["ä", "ö", "ü", "Ä", "Ö", "Ü", "ß", "—"]:
		if not font.has_char(ch.unicode_at(0)):
			missing.append(ch)
	if missing.is_empty():
		print("[font] OK — all German diacritics present in fallback font")
	else:
		printerr("[font] MISSING GLYPHS: %s" % ", ".join(missing))

	if Input.is_action_pressed("push_to_talk"):
		pass  # keeps the action referenced so a typo in the map fails loudly
