extends Node
## Typed access to the tuning config compiled from content/config/*.yaml.
##
## Pedagogy constants live in content so they can be retuned from simulation
## without an engine change (GDD Part 4 §architecture).


func _section(config_id: String) -> Dictionary:
	var section: Variant = ContentDB.config.get(config_id)
	return section if section is Dictionary else {}


func mastery(key: String, fallback: Variant = null) -> Variant:
	return _section("mastery_weights").get(key, fallback)


func threshold_group(group: String) -> Dictionary:
	var g: Variant = _section("thresholds").get(group)
	return g if g is Dictionary else {}


func scheduler(key: String, fallback: Variant = null) -> Variant:
	return threshold_group("scheduler").get(key, fallback)


func sm2(key: String, fallback: Variant = null) -> Variant:
	return threshold_group("sm2").get(key, fallback)


func drill(key: String, fallback: Variant = null) -> Variant:
	return threshold_group("drill").get(key, fallback)


func starvation_days() -> int:
	return int(_section("thresholds").get("starvation_days", 12))


## UI chrome string (the player's own language). Part 5 §7 strings table.
func ui(key: String, fallback: String = "") -> String:
	var chrome: Variant = _section("ui_strings").get("chrome")
	if chrome is Dictionary:
		return str((chrome as Dictionary).get(key, fallback))
	return fallback


## Diegetic app name — German, because the phone belongs to the village.
func app_name(key: String, fallback: String = "") -> String:
	var apps: Variant = _section("ui_strings").get("apps")
	if apps is Dictionary:
		return str((apps as Dictionary).get(key, fallback))
	return fallback


## The language the world speaks — what the player is here to learn.
func world_language() -> String:
	return str(_section("ui_strings").get("world_language", "de"))


## A building's name, in the world's language. ONE record drives both the
## painted signboard and the door prompt, so the two cannot drift apart, and
## switching the world language rewrites both without repainting any art.
## Named `sign_record`, not `sign`: GDScript already has a global `sign()`, and a
## method that shadows it resolves to the built-in at the call site — returning a
## number where a Dictionary was expected.
func sign_record(key: String) -> Dictionary:
	var block: Variant = _section("ui_strings").get("signs")
	if block is Dictionary:
		var entry: Variant = (block as Dictionary).get(key)
		if entry is Dictionary:
			return entry
	return {}


func sign_text(key: String) -> String:
	var entry := sign_record(key)
	if entry.is_empty():
		return ""
	# Fall back to German rather than to nothing: an unlocalised sign should
	# still name its building.
	return str(entry.get(world_language(), entry.get("de", "")))


## World-facing German (signs, the locked-door line). Returns the whole record
## so callers can honour its draft flag.
func diegetic(key: String) -> Dictionary:
	var block: Variant = _section("ui_strings").get("diegetic")
	if block is Dictionary:
		var entry: Variant = (block as Dictionary).get(key)
		if entry is Dictionary:
			return entry
	return {}
