extends Node2D
class_name Interactable
## Anything the player can press E on. Week 1: the cow and the bed.

## Emitted when the player interacts. The farm scene decides what happens so
## that no engine-level node has to know about dialogue or saving.
signal interacted(who: Interactable)

@export var speaker_name: String = ""
## English placeholder only — real lines come from content.db from Week 2.
@export var placeholder_line: String = ""
@export var is_bed: bool = false


func interact() -> void:
	interacted.emit(self)
