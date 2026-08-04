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
## Seeds deterministic weather so tomorrow's forecast is honest (Part 12 §5).
var weather_seed: int = 20260804

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
		"weather_seed": weather_seed,
		"drills": DrillSpawner.to_dict(),
		"monologue": Monologue.to_dict(),
		"memory": Memory.to_dict(),
		"inventory": Inventory.to_dict(),
		"plots": Farm.to_dict(),
		"animals": Livestock.to_dict(),
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
	weather_seed = int(data.get("weather_seed", 20260804))
	DrillSpawner.from_dict(data.get("drills", {}))
	Monologue.from_dict(data.get("monologue", {}))
	Memory.from_dict(data.get("memory", {}))
	Inventory.from_dict(data.get("inventory", {}))
	Farm.from_dict(data.get("plots", {}))
	Livestock.from_dict(data.get("animals", {}))
	# The inventory is the store of record. An item "in hand" the player does
	# not actually own would let them feed the cow with hay that is not there.
	if carrying != "" and not Inventory.has(carrying):
		carrying = ""
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
	# The field grows overnight, so it must roll forward AFTER the day number
	# advances and BEFORE the save — otherwise a reload replays or skips a night.
	Farm.advance_day(day)
	# The village sleeps too: weak memories fade, milestones do not.
	Memory.advance_day()
	# The scheduler names tomorrow's weakest word; whoever remembers you
	# struggling with it gets to ask (Part 15 §3.4).
	Callbacks.set_retest_word(Scheduler.weakest_due_word())
	save_state()
	day_advanced.emit(day)
	# You wake thinking. The wake thought is the first thing the fade shows the
	# player each day, which is why it is the class with the most templates.
	Monologue.trigger("wake")
	print("[state] slept -> day %d" % day)
	HUD.refresh()


## Which act of the campaign we are in (Part 6 §2). Boundaries are content, and
## the act is a PACING ceiling for the monologue fade (Part 15 §2.1 rule 6) —
## never a gate on what the player has actually earned.
func act() -> int:
	var block: Variant = Config._section("calendar").get("acts")
	if not (block is Dictionary):
		return 1
	var current := 1
	for key in (block as Dictionary):
		if day >= int((block as Dictionary)[key]):
			current = maxi(current, int(str(key)))
	return current


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
