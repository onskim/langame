extends Area2D
class_name Door
## A way into a building. GDD Part 14 §3 (MVP enterable policy).
##
## Interiors are locked at start. MVP enterable: the player's own farmhouse and
## the commercial ground floors. Every other home gives a blackout interior —
## furniture as dark silhouettes and an inner-monologue line — rather than an
## invisible wall, because "you may not go in" should feel like a place you are
## not yet welcome, not like level geometry.
##
## Pre-wired for the post-MVP unlock: at 3 hearts the NPC invites you in and the
## lights come on. Intimacy as literal illumination.

enum Access { OPEN, BLACKOUT, LOCKED }

@export var target_map: String = ""
@export var arrival_marker: String = "from_outside"
@export var access: Access = Access.OPEN
## Shown on the HUD when the player is standing here.
@export var sign_text: String = ""
## Affection tier at which a BLACKOUT home opens up (post-MVP hook).
@export var unlock_at_affection: int = 3

var player_in_range: bool = false


func _ready() -> void:
	add_to_group("door")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	player_in_range = true
	HUD.set_prompt(prompt_text())


func _on_body_exited(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	player_in_range = false
	HUD.set_prompt("")


func prompt_text() -> String:
	match effective_access():
		Access.OPEN:
			return "E   %s" % sign_text
		Access.BLACKOUT:
			return "E   %s" % sign_text
		_:
			return "%s — zu" % sign_text   # closed


## BLACKOUT homes open once the relationship does (pre-wired, not yet reachable
## in MVP because affection lands in Week 7).
func effective_access() -> int:
	if access == Access.BLACKOUT and GameState.affection_of(owner_npc()) >= unlock_at_affection:
		return Access.OPEN
	return access


## Which NPC's home this is, derived from the target map id (interior_karl -> npc_karl).
func owner_npc() -> String:
	if not target_map.begins_with("interior_"):
		return ""
	return "npc_" + target_map.trim_prefix("interior_")


func use() -> void:
	match effective_access():
		Access.OPEN:
			HUD.set_prompt("")
			WorldRouter.travel_to(target_map, arrival_marker)
		Access.BLACKOUT:
			HUD.set_prompt("")
			WorldRouter.enter_blackout(target_map, sign_text)
		_:
			# Locked doors still answer, so the world never feels like scenery.
			Dialogue.play_inner_monologue("Es ist zu.")
