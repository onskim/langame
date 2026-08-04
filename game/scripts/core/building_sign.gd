extends Label
class_name BuildingSign
## The name painted on a shop's signboard, drawn at runtime instead of baked in.
##
## The founder's shopfront references arrived with "Bäckerei" and "Café" painted
## on the boards. Shipped that way, those buildings are German forever — a French
## or Spanish edition would need every sprite repainted. So `tools/blank_sign.py`
## erases the lettering from the sprite, leaving a blank plank, and this draws
## the name over it from the strings table (Part 5 §7).
##
## `sign_key` is the SAME key the building's door uses, so the board and the
## door prompt are one fact with one spelling.

@export var sign_key: String = ""
## The blank plank in the parent sprite's local pixels, found once by eye and
## checked against the art. Text is centred in it.
@export var plank: Rect2 = Rect2()


func _ready() -> void:
	if sign_key == "":
		push_error("[sign] a BuildingSign with no key draws nothing")
		return
	text = Config.sign_text(sign_key)
	if text == "":
		push_error("[sign] no strings entry for sign key '%s'" % sign_key)

	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# A longer word in another language must not spill onto the brickwork.
	clip_text = true
	add_theme_font_size_override("font_size", 8)

	# The plank is about 9px tall and a font's line box is nearly twice that, so
	# sizing the Label to the plank does not shrink the text — it just makes the
	# box overflow downward, printing the name on the awning below. Give the
	# Label a box tall enough for its own line and CENTRE that on the plank.
	var box := Vector2(plank.size.x, 16.0)
	custom_minimum_size = box
	size = box
	position = plank.position + plank.size * 0.5 - box * 0.5
	# Cream, like the painted original, with a dark rim so it reads against the
	# grain of the plank rather than dissolving into it.
	add_theme_color_override("font_color", Color(0.96, 0.92, 0.78))
	add_theme_color_override("font_outline_color", Color(0.15, 0.08, 0.04))
	add_theme_constant_override("outline_size", 2)
