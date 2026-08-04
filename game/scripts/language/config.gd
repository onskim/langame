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
