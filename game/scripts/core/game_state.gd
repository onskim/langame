extends Node2D
## Boot smoke test. Confirms the project runs and the pinned viewport is in effect.
## Replaced in Week 1 proper by the real game_state singleton (GDD Part 10 §6).

func _ready() -> void:
	var vp := get_viewport().get_visible_rect().size
	print("langame boot OK — viewport %d x %d" % [vp.x, vp.y])
	assert(vp.x == 640 and vp.y == 360, "Viewport must be 640x360 (GDD Part 11 §2)")
