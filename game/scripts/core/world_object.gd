extends Node2D
class_name WorldObject
## A thing in the world that content can point at and the player can act on.
##
## The `object_id` matches the ids used in content YAML (obj_cow, obj_hay …),
## which is how a gesture written by a content author reaches a real sprite
## without engine code knowing anything about cows.

## Emitted on E. The scene decides what it means, so this node stays dumb.
signal interacted(who: WorldObject)

@export var object_id: String = ""
## Tier I action this object accepts: feed, approach, water …
@export var action: String = ""
## Item the player must be carrying for the action to count ("" = none).
@export var requires_item: String = ""
## False for repeatable actions like watering, where the item is not used up.
@export var consumes_item: bool = true
@export var is_pickup: bool = false
## Word this pickup grants when collected (content word_id).
@export var grants_item: String = ""

@onready var _sprite: Sprite2D = $Sprite2D

var _pulse: float = 0.0
var _highlighted: bool = false
var _highlight_color: Color = Color.WHITE


func _ready() -> void:
	add_to_group("world_object")


func _process(delta: float) -> void:
	if not _highlighted:
		return
	# A gentle pulse rather than a hard outline: the gesture should read as
	# "look here", not as a quest marker.
	_pulse += delta * 4.0
	var t := (sin(_pulse) + 1.0) * 0.5
	_sprite.modulate = Color.WHITE.lerp(_highlight_color, 0.35 + t * 0.45)


func interact() -> void:
	interacted.emit(self)


func highlight(color: Color) -> void:
	_highlighted = true
	_highlight_color = color
	_pulse = 0.0


func clear_highlight() -> void:
	_highlighted = false
	_sprite.modulate = Color.WHITE
