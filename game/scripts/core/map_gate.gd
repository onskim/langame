extends Area2D
class_name MapGate
## The path between maps (GDD Part 14 §2). Walking onto it travels.
##
## A short path walk is the load transition — the player never sees a loading
## screen, they see themselves leaving the farm.

@export var target_map: String = ""
@export var arrival_marker: String = ""
## Shown as the player approaches, so leaving is always a deliberate choice.
@export var label_text: String = ""

var _armed: bool = true


func _ready() -> void:
	add_to_group("map_gate")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node2D) -> void:
	if not _armed or not body.is_in_group("player"):
		return
	_armed = false
	WorldRouter.travel_to(target_map, arrival_marker)


func _on_body_exited(_body: Node2D) -> void:
	_armed = true
