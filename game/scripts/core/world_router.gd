extends Node
## Which map is which, who is on it, and how the player moves between them.
## GDD Part 14 §2 (the split map).
##
## NPCs exist only on the map the player is currently standing in. An NPC
## scheduled elsewhere is not simulated as a body — only its `current_location`
## matters, and that is derived from content on demand. This keeps the village
## alive without paying for two maps of physics.

signal map_changed(map_id: String)

var current_map: String = "farm"
## The place scene currently loaded, so systems can ask it to resync.
var current_world: Node = null
## Which arrival marker the player should spawn on after a transition.
var pending_arrival: String = ""


func _world() -> Dictionary:
	var section: Variant = ContentDB.config.get("world")
	return section if section is Dictionary else {}


func maps() -> Dictionary:
	var m: Variant = _world().get("maps")
	return m if m is Dictionary else {}


func scene_path(map_id: String) -> String:
	return maps().get(map_id, {}).get("scene", "")


func display_name(map_id: String) -> String:
	return maps().get(map_id, {}).get("display", map_id)


## Which map a named schedule location sits on ("" if content never says).
func map_of_location(location: String) -> String:
	var locations: Variant = _world().get("locations")
	if locations is Dictionary:
		return (locations as Dictionary).get(location, "")
	return ""


## Is this NPC physically present on `map_id` at `hour`?
func npc_is_on_map(npc_id: String, map_id: String, hour: float) -> bool:
	var location := scheduled_location(npc_id, hour)
	if location == "":
		return false
	return map_of_location(location) == map_id


## Where content says this NPC is right now, regardless of which map is loaded.
func scheduled_location(npc_id: String, hour: float) -> String:
	var npc := ContentDB.get_npc(npc_id)
	var schedule: Variant = npc.get("schedule")
	if not (schedule is Array):
		return ""
	for window in schedule:
		var from_h := _parse_hour(window.get("from", "00:00"))
		var to_h := _parse_hour(window.get("to", "24:00"))
		if hour >= from_h and hour < to_h:
			return window.get("at", "")
	return ""


static func _parse_hour(text: String) -> float:
	var parts := text.split(":")
	if parts.size() != 2:
		return 0.0
	return float(parts[0]) + float(parts[1]) / 60.0


## Every NPC content says is on this map at this hour.
func npcs_on_map(map_id: String, hour: float) -> Array[String]:
	var out: Array[String] = []
	var ids := ContentDB.npcs.keys()
	ids.sort()
	for npc_id in ids:
		if npc_is_on_map(npc_id, map_id, hour):
			out.append(npc_id)
	return out


## Walk the player to another map, arriving at `arrival_marker`.
func travel_to(map_id: String, arrival_marker: String) -> void:
	var path := scene_path(map_id)
	if path == "":
		push_error("WorldRouter: no scene for map '%s'" % map_id)
		return
	current_map = map_id
	pending_arrival = arrival_marker
	GameState.current_map = map_id
	GameState.save_state()
	map_changed.emit(map_id)
	print("[world] travel -> %s (arrive at %s)" % [map_id, arrival_marker])
	get_tree().change_scene_to_file(path)


## A home the player is not welcome in yet (Part 14 §3). Rather than an
## invisible wall, they get the dark room and an inner-monologue line.
func enter_blackout(map_id: String, sign_text: String) -> void:
	print("[world] blackout interior: %s" % map_id)
	Dialogue.play_diegetic(Config.diegetic("interior_dark"))


## Consume the arrival marker set by the last transition.
func consume_arrival() -> String:
	var arrival := pending_arrival
	pending_arrival = ""
	return arrival
