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
## Per-NPC reputation (Part 10 §3 `npc_state`). A single global number meant
## doing Anna's farm chores unlocked the mayor's festival — Part 10 §5.3 gates
## are per-giver (Q07 = Karl 10, Q10 = Petra 15, Q14 = Weber 25).
var reputation_by_npc: Dictionary = {}
var money: int = 0
var completed_quests: Array = []
## Which map the player is standing on (Part 14 §2 split world).
var current_map: String = "farm"
## Per-NPC affection tiers (Part 12). Week 7 fills these; doors read them now.
var affection: Dictionary = {}
## Silent path (Part 3 §1): the game must be completable mute.
var quiet_mode: bool = false

var _loaded_position: Variant = null


func _ready() -> void:
	load_state()


func to_dict() -> Dictionary:
	return {
		"day": day,
		"player_x": player_position.x,
		"player_y": player_position.y,
		"carrying": carrying,
		"reputation_by_npc": reputation_by_npc,
		"money": money,
		"completed_quests": completed_quests,
		"word_stats": WordStats.to_dict(),
		"current_map": current_map,
		"affection": affection,
		"quiet_mode": quiet_mode,
		"drills": DrillSpawner.to_dict(),
	}


func save_state() -> void:
	SaveService.save_game(to_dict())


func load_state() -> void:
	var data := SaveService.load_game()
	if data.is_empty():
		return
	day = int(data.get("day", 1))
	carrying = str(data.get("carrying", ""))
	reputation_by_npc = data.get("reputation_by_npc", {})
	money = int(data.get("money", 0))
	completed_quests = data.get("completed_quests", [])
	WordStats.from_dict(data.get("word_stats", {}))
	current_map = str(data.get("current_map", "farm"))
	affection = data.get("affection", {})
	quiet_mode = bool(data.get("quiet_mode", false))
	DrillSpawner.from_dict(data.get("drills", {}))
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
			add_reputation(npc_id, int(rep[npc_id]))
	money += int(rewards.get("money", 0))
	save_state()
	print("[state] quest %s complete — rep %s, money %d" % [quest_id, reputation_by_npc, money])
	HUD.refresh()


## Bed interaction: advance the day, reset the clock, autosave.
func sleep(spawn_position: Vector2) -> void:
	day += 1
	player_position = spawn_position
	DayCycle.reset_to_morning()
	save_state()
	day_advanced.emit(day)
	print("[state] slept -> day %d" % day)
	HUD.refresh()


## Affection tier with an NPC, 0 if never met (Part 12 §affection).
func affection_of(npc_id: String) -> int:
	if npc_id == "":
		return 0
	return int(affection.get(npc_id, 0))


## Reputation with one NPC (Part 12 §1: clamped 0-100).
func reputation_of(npc_id: String) -> int:
	if npc_id == "" or npc_id == "auto":
		return 0
	return int(reputation_by_npc.get(npc_id, 0))


func add_reputation(npc_id: String, amount: int) -> void:
	if npc_id == "" or npc_id == "auto":
		return
	reputation_by_npc[npc_id] = clampi(reputation_of(npc_id) + amount, 0, 100)


## Total standing in the village — display only, never a gate.
func total_reputation() -> int:
	var total := 0
	for npc_id in reputation_by_npc:
		total += int(reputation_by_npc[npc_id])
	return total
