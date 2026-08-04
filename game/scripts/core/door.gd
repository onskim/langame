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
## Which building this is, as a key into the strings table's `signs` block. It
## names the door prompt AND the painted signboard from one record, so a change
## of world language rewrites both and they can never disagree.
@export var sign_key: String = ""
## Literal fallback for doors that have no strings entry yet. A German literal
## here is a Part 4 §2 violation waiting to happen — prefer `sign_key`.
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


## The building's name in the world's language, from content.
func label() -> String:
	if sign_key != "":
		var from_content := Config.sign_text(sign_key)
		if from_content != "":
			return from_content
		push_error("[door] no strings entry for sign key '%s'" % sign_key)
	return sign_text


func prompt_text() -> String:
	var shown := label()
	match effective_access():
		Access.OPEN, Access.BLACKOUT:
			return "E   %s" % shown
		_:
			return shown


## BLACKOUT homes open once the relationship does (pre-wired, not yet reachable
## in MVP because affection lands in Week 7).
func effective_access() -> int:
	if access == Access.BLACKOUT and GameState.affection_of(owner_npc()) >= unlock_at_affection:
		return Access.OPEN
	return access


## Which NPC's home this is. Declared explicitly rather than derived from the
## map id: `interior_anna_kitchen` would have produced `npc_anna_kitchen`, and
## most of Part 14 §3's interiors are named for the room, not the person.
@export var owner_npc_id: String = ""

func owner_npc() -> String:
	return owner_npc_id


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
			Dialogue.play_diegetic(Config.diegetic("door_locked"))
