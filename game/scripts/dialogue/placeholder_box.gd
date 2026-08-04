extends CanvasLayer
## Placeholder dialogue box for Week 1 only.
##
## The real dialogue runner (Tier I support, gestures, recasts) lands Week 2 per
## GDD Part 10 §6. This displays a caller-supplied string and closes on interact.
##
## REPO RULE: engine code never contains a German string. Week 1 callers pass
## English placeholder text; from Week 2 all lines come from content.db.

signal closed()

@onready var _panel: Panel = $Panel
@onready var _speaker: Label = $Panel/Speaker
@onready var _line: Label = $Panel/Line

var is_open: bool = false


func _ready() -> void:
	_panel.visible = false


func show_line(speaker: String, text: String) -> void:
	_speaker.text = speaker
	_line.text = text
	_panel.visible = true
	is_open = true


func close() -> void:
	_panel.visible = false
	is_open = false
	closed.emit()
