extends CharacterBody2D
class_name Pet
## Dog AND cat, one shared behaviour system (Addendum §6). Two sprite sets is
## the whole cost difference; the retention value is the daily ritual.
##
## Addendum §10 constraint 4: pets ship this week with TAP-INPUT commands only.
## Spoken "Sitz!" retrofits in Week 6 with the speech layer — the command path
## below is deliberately input-agnostic so that retrofit is a new caller, not a
## rewrite. ("Sitz!" is pronunciation practice wearing a costume.)

signal command_obeyed(command_id: String)

const FOLLOW_SPEED := 46.0
const FOLLOW_DISTANCE := 26.0
const STOP_DISTANCE := 20.0

enum State { FOLLOW, SIT, STAY }

@export var pet_id: String = ""
## Commands this pet understands, as content word_ids.
@export var commands: Array[String] = ["sitz", "komm", "hier"]

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _mood: Label = $Mood

var state: int = State.FOLLOW
var _player: Node2D = null
var _frame: int = 0
var _frame_timer: float = 0.0
var _facing: int = 0
var _frame_height: int = 24


func _ready() -> void:
	add_to_group("pet")
	_frame_height = int(_sprite.texture.get_height() / 4.0) if _sprite.texture else 24
	_mood.text = ""


func set_player(player: Node2D) -> void:
	_player = player


## The single command entry point. Week 4 calls it from a tap; Week 6 will call
## it from a scored utterance. The pet does not care which.
func obey(command_id: String) -> bool:
	if not commands.has(command_id):
		return false
	match command_id:
		"sitz":
			state = State.SIT
		"komm", "hier":
			state = State.FOLLOW
	_show_mood(command_id)
	command_obeyed.emit(command_id)
	# Hearing the word and seeing it obeyed IS the comprehension event — the
	# dog sitting is the feedback. So the command word is introduced here if the
	# player has not met it yet, exactly as an NPC line would introduce it.
	if not WordStats.has_word(command_id):
		WordStats.introduce(command_id, GameState.day)
		DayEndCard.note_word(command_id)
	WordStats.record(command_id, true, GameState.day)
	print("[pet] %s obeyed %s" % [pet_id, command_id])
	return true


func _show_mood(command_id: String) -> void:
	var word := ContentDB.get_word(command_id)
	_mood.text = str(word.get("lemma", ""))
	await get_tree().create_timer(1.6).timeout
	if is_instance_valid(self):
		_mood.text = ""


func _physics_process(delta: float) -> void:
	if state == State.SIT or state == State.STAY or _player == null:
		velocity = Vector2.ZERO
		_frame = 0
		_apply_frame()
		return

	var to_player := _player.global_position - global_position
	if to_player.length() <= STOP_DISTANCE:
		velocity = Vector2.ZERO
		_frame = 0
		_apply_frame()
		return

	var direction := to_player.normalized()
	velocity = direction * FOLLOW_SPEED
	move_and_slide()
	_update_facing(direction)
	_advance_walk_cycle(delta)
	_apply_frame()


func _update_facing(direction: Vector2) -> void:
	if abs(direction.x) > abs(direction.y):
		_facing = 3 if direction.x > 0.0 else 2
	else:
		_facing = 0 if direction.y > 0.0 else 1


func _advance_walk_cycle(delta: float) -> void:
	_frame_timer += delta
	if _frame_timer >= 0.12:
		_frame_timer -= 0.12
		_frame = (_frame + 1) % 4


func _apply_frame() -> void:
	_sprite.frame = _facing * 4 + _frame


func is_following() -> bool:
	return state == State.FOLLOW


func is_sitting() -> bool:
	return state == State.SIT
