extends Node
## Global run state. GDD Part 10 §6 Weeks 1–2.
##
## Still deliberately narrow: day, spawn, carried item, reputation, completed
## quests. The full meter set (Part 12) and word_stats (Week 4) are not here yet.

signal day_advanced(day: int)
signal state_loaded()

var day: int = 1
var player_position: Vector2 = Vector2(384, 336)
## word_id of the carried item, or "" — matches content ids, not engine names.
var carrying: String = ""
var reputation: int = 0
var money: int = 0
var completed_quests: Array = []

var _loaded_position: Variant = null


func _ready() -> void:
	load_state()


func to_dict() -> Dictionary:
	return {
		"day": day,
		"player_x": player_position.x,
		"player_y": player_position.y,
		"carrying": carrying,
		"reputation": reputation,
		"money": money,
		"completed_quests": completed_quests,
	}


func save_state() -> void:
	SaveService.save_game(to_dict())


func load_state() -> void:
	var data := SaveService.load_game()
	if data.is_empty():
		return
	day = int(data.get("day", 1))
	carrying = str(data.get("carrying", ""))
	reputation = int(data.get("reputation", 0))
	money = int(data.get("money", 0))
	completed_quests = data.get("completed_quests", [])
	if data.has("player_x") and data.has("player_y"):
		_loaded_position = Vector2(float(data["player_x"]), float(data["player_y"]))
		player_position = _loaded_position
	state_loaded.emit()


## Returns the spawn point a scene should use, consuming any loaded position.
func consume_spawn_position(default_position: Vector2) -> Vector2:
	if _loaded_position != null:
		var p: Vector2 = _loaded_position
		_loaded_position = null
		return p
	return default_position


func complete_quest(quest_id: String, rewards: Dictionary) -> void:
	if not completed_quests.has(quest_id):
		completed_quests.append(quest_id)
	var rep: Variant = rewards.get("rep")
	if rep is Dictionary:
		for npc_id in rep:
			reputation += int(rep[npc_id])
	money += int(rewards.get("money", 0))
	save_state()
	print("[state] quest %s complete — rep %d, money %d" % [quest_id, reputation, money])


## Bed interaction: advance the day, reset the clock, autosave.
func sleep(spawn_position: Vector2) -> void:
	day += 1
	player_position = spawn_position
	DayCycle.reset_to_morning()
	save_state()
	day_advanced.emit(day)
	print("[state] slept -> day %d" % day)
