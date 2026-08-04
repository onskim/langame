extends Node
## Farm-simulation acceptance — GDD Part 14 §4 (crops, growing rules, animals)
## and Part 10 §5.3 Q13 (Milch → Butter).
##
##   godot --headless res://dev/acceptance_farm.tscn
##
## These assert the RULES, not the happy path. Anyone can plant a seed and watch
## a number go up; what matters is that a crop nobody waters stalls, that four
## dry days kill it, that rain substitutes for the watering can, that an unfed
## animal gives nothing, and that a failed craft never eats the ingredients.

var _failures: int = 0


func _ready() -> void:
	await _run()
	get_tree().quit(1 if _failures > 0 else 0)


func _check(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("  PASS  %s %s" % [label, detail])
	else:
		_failures += 1
		printerr("  FAIL  %s %s" % [label, detail])


## The weather is deterministic but not ours to choose, so find a stretch of days
## with no rain rather than pretending the calendar says what we want. A dry-day
## test run on a rainy day would pass for the wrong reason.
func _dry_run_start(length: int) -> int:
	for start in range(1, 400):
		var dry := true
		for offset in range(length + 1):
			if Farm.rain_waters_on(start + offset):
				dry = false
				break
		if dry:
			return start
	return -1


func _first_rainy_day(after: int) -> int:
	for day in range(after, after + 400):
		if Farm.rain_waters_on(day):
			return day
	return -1


func _sleep_to(day: int) -> void:
	while GameState.day < day:
		GameState.day += 1
		Farm.advance_day(GameState.day)


func _run() -> void:
	print("--- farm simulation acceptance ---")
	DayCycle.running = false
	Farm.reset()
	Livestock.reset()
	Inventory.clear()

	# ---------- the roster is content, not code ----------
	_check("the crop table is loaded from content", Farm.crop_table().size() >= 10,
		"%d crops" % Farm.crop_table().size())
	for required in ["kartoffel", "karotte", "salat", "erdbeere"]:
		_check("Frühling roster has %s" % required,
			not Farm.crop_def(required).is_empty())
	_check("Erdbeere regrows (Part 14 §4.3)",
		bool(Farm.crop_def("erdbeere").get("regrows", false)))
	_check("Kartoffel does not regrow",
		not bool(Farm.crop_def("kartoffel").get("regrows", false)))

	# ---------- you can only plant in your own field ----------
	var plot := Vector2i(8, 28)
	var outside := Vector2i(40, 6)   # Anna's plot — hers, not the player's
	_check("the player's field is plantable", Farm.is_plot(plot))
	_check("Anna's field is not the player's to plant", not Farm.is_plot(outside))
	_check("planting outside the field is refused",
		not Farm.plant(outside, "kartoffel"))

	# ---------- planting ----------
	GameState.day = maxi(1, _dry_run_start(6))
	_check("found a dry stretch to test against", GameState.day > 0,
		"starting day %d" % GameState.day)
	_check("a seed can be sown", Farm.plant(plot, "kartoffel"))
	_check("and the plot is now planted", Farm.is_planted(plot))
	_check("sowing the same plot twice is refused",
		not Farm.plant(plot, "karotte"))
	_check("an unknown crop is refused", not Farm.plant(Vector2i(9, 28), "drachen"))
	_check("a fresh crop is not ready", not Farm.is_ready(plot))
	_check("a fresh crop counts as watered today", Farm.is_watered_today(plot))

	# ---------- growth is counted in WATERED days ----------
	var start_day := GameState.day
	_sleep_to(start_day + 1)
	var grown_after_one := int(Farm.plot(plot).get("grown_days", 0))
	_check("a watered crop grows overnight", grown_after_one == 1,
		"grown_days=%d" % grown_after_one)

	# Skip watering entirely from here. Growth must STOP, not continue.
	_sleep_to(start_day + 2)
	_check("an unwatered crop does not grow",
		int(Farm.plot(plot).get("grown_days", 0)) == grown_after_one,
		"grown_days=%d" % Farm.plot(plot).get("grown_days", 0))
	_check("...and it is not wilted after one dry day", not Farm.is_wilted(plot))

	_sleep_to(start_day + 3)
	_check("two dry days wilt it", Farm.is_wilted(plot),
		"dry_days=%d" % Farm.plot(plot).get("dry_days", 0))
	_check("but wilted is not dead", not Farm.is_dead(plot))

	# Reviving costs a day of growth — neglect has a price, never a wipe.
	var before_revive := int(Farm.plot(plot).get("grown_days", 0))
	_check("watering revives a wilted crop", Farm.water(plot))
	_check("...and it is no longer wilted", not Farm.is_wilted(plot))
	_check("...at the cost of a day's growth",
		int(Farm.plot(plot).get("grown_days", 0)) == maxi(0, before_revive - 1),
		"%d -> %d" % [before_revive, Farm.plot(plot).get("grown_days", 0)])
	_check("watering twice in a day is refused", not Farm.water(plot))

	# ---------- four dry days kill it ----------
	var dead_plot := Vector2i(10, 28)
	GameState.day = maxi(1, _dry_run_start(6))
	Farm.plant(dead_plot, "salat")
	_sleep_to(GameState.day + 5)
	_check("four dry days kill a crop", Farm.is_dead(dead_plot),
		"dry_days=%d" % Farm.plot(dead_plot).get("dry_days", 0))
	_check("a dead crop cannot be watered back", not Farm.water(dead_plot))
	_check("a dead crop is never ready", not Farm.is_ready(dead_plot))
	_check("a dead plot can be cleared", Farm.clear_plot(dead_plot))

	# ---------- RAIN WATERS EVERYTHING (Part 12 §5 — the forecast has stakes) --
	# This is the rule the Wetter app exists to make actionable. Without it,
	# reading tomorrow's weather is trivia.
	var rainy := _first_rainy_day(2)
	_check("the calendar does actually rain", rainy > 0, "first rain day %d" % rainy)
	GameState.day = rainy - 1
	var rain_plot := Vector2i(12, 28)
	Farm.reset()
	Farm.plant(rain_plot, "karotte")
	# Deliberately do NOT water: go to bed dry and let the sky do it.
	Farm.plots[Farm._key(rain_plot)]["watered_on"] = -99
	_sleep_to(rainy)
	_check("rain grows a crop nobody watered",
		int(Farm.plot(rain_plot).get("grown_days", 0)) == 1,
		"grown_days=%d" % Farm.plot(rain_plot).get("grown_days", 0))
	_check("...and it is not dry after rain",
		int(Farm.plot(rain_plot).get("dry_days", 0)) == 0)

	# ---------- harvest ----------
	Farm.reset()
	Inventory.clear()
	GameState.day = maxi(1, _dry_run_start(12))
	var crop_plot := Vector2i(6, 26)
	Farm.plant(crop_plot, "salat")
	var needed := int(Farm.crop_def("salat").get("days", 3))
	for i in range(needed):
		Farm.water(crop_plot)
		_sleep_to(GameState.day + 1)
	_check("a fully grown crop is ready", Farm.is_ready(crop_plot),
		"grown=%d/%d" % [Farm.plot(crop_plot).get("grown_days", 0), needed])
	_check("stage tops out when ripe", Farm.stage_of(crop_plot) >= Farm.stages() - 1,
		"stage=%d of %d" % [Farm.stage_of(crop_plot), Farm.stages()])
	_check("harvesting yields the crop", Farm.harvest(crop_plot) == "salat")
	_check("...into the inventory", Inventory.count("salat") == 1,
		"%d" % Inventory.count("salat"))
	_check("a harvested non-regrowing plot is cleared", not Farm.is_planted(crop_plot))
	_check("an empty plot cannot be harvested", Farm.harvest(crop_plot) == "")

	# A regrowing crop stays in the ground — that is what its seed price buys.
	var berry := Vector2i(7, 26)
	Farm.plant(berry, "erdbeere")
	for i in range(int(Farm.crop_def("erdbeere").get("days", 7))):
		Farm.water(berry)
		_sleep_to(GameState.day + 1)
	_check("Erdbeere is ready", Farm.is_ready(berry))
	_check("harvesting it yields a berry", Farm.harvest(berry) == "erdbeere")
	_check("...and the plant stays in the ground", Farm.is_planted(berry))
	_check("...but is not instantly ready again", not Farm.is_ready(berry))

	# ---------- animals: feed today, collect tomorrow ----------
	Livestock.reset()
	Inventory.clear()
	GameState.day = 20
	_check("the cow is a declared animal", Livestock.is_animal("obj_cow"))
	_check("the hen is a declared animal", Livestock.is_animal("obj_hen"))
	_check("the pig is a declared animal", Livestock.is_animal("obj_pig"))
	_check("a fence is not an animal", not Livestock.is_animal("obj_field"))
	_check("the cow gives Milch", Livestock.product("obj_cow") == "milch")
	_check("the hen gives das Ei", Livestock.product("obj_hen") == "ei")
	_check("the pig gives Fleisch", Livestock.product("obj_pig") == "fleisch")

	_check("an animal nobody fed gives nothing",
		not Livestock.can_collect("obj_cow"))
	_check("...and says why", Livestock.refusal_reason("obj_cow") == "animal_hungry",
		Livestock.refusal_reason("obj_cow"))
	_check("feeding with an empty bag is refused", not Livestock.feed("obj_cow"))
	_check("...and costs nothing", Inventory.count("heu") == 0)

	Inventory.add("heu", 2)
	_check("feeding works with hay in hand", Livestock.feed("obj_cow"))
	_check("...and eats exactly one bale", Inventory.count("heu") == 1,
		"%d left" % Inventory.count("heu"))
	_check("feeding twice in a day is refused", not Livestock.feed("obj_cow"))
	_check("...and does not eat a second bale", Inventory.count("heu") == 1)
	_check("a cow fed today has nothing today",
		not Livestock.can_collect("obj_cow"))
	_check("...and says so", Livestock.refusal_reason("obj_cow") == "animal_not_yet",
		Livestock.refusal_reason("obj_cow"))

	GameState.day += 1
	_check("a cow fed yesterday can be milked", Livestock.can_collect("obj_cow"))
	_check("milking gives Milch", Livestock.collect("obj_cow") == "milch")
	_check("...into the inventory", Inventory.count("milch") == 1)
	_check("milking twice in a day is refused", Livestock.collect("obj_cow") == "")
	_check("...and says so",
		Livestock.refusal_reason("obj_cow") == "animal_already_collected",
		Livestock.refusal_reason("obj_cow"))

	# The pig is on a long cycle, so its interval must actually be respected.
	Inventory.add("heu", 1)
	_check("the pig can be fed", Livestock.feed("obj_pig"))
	GameState.day += 1
	_check("the pig gives meat once", Livestock.collect("obj_pig") == "fleisch")
	GameState.day += 1
	_check("the pig does not give meat again the next day",
		Livestock.collect("obj_pig") == "", "interval=%d"
			% Livestock.definition("obj_pig").get("interval_days", 0))
	GameState.day += int(Livestock.definition("obj_pig").get("interval_days", 6))
	_check("...but does once its interval has passed",
		Livestock.can_collect("obj_pig"))

	# ---------- crafting: Milch -> Butter (Q13) ----------
	Inventory.clear()
	var recipe_inputs := Crafting.inputs_of("butter")
	_check("the butter recipe is content", not recipe_inputs.is_empty(),
		str(recipe_inputs))
	_check("the churn is where butter is made",
		Crafting.recipes_at("obj_butterfass").has("butter"),
		str(Crafting.recipes_at("obj_butterfass")))
	_check("butter cannot be made from nothing", not Crafting.can_craft("butter"))
	_check("...and the game can say what is missing",
		Crafting.missing_for("butter").has("milch"),
		str(Crafting.missing_for("butter")))
	_check("a refused craft consumes nothing", Crafting.craft("butter") == "")
	_check("...leaving the bag untouched", Inventory.total_items() == 0)

	Inventory.add("milch", int(recipe_inputs.get("milch", 2)))
	_check("with enough milk, butter can be made", Crafting.can_craft("butter"))
	_check("crafting yields butter", Crafting.craft("butter") == "butter")
	_check("...one of them", Inventory.count("butter") == 1)
	_check("...and the milk is gone", Inventory.count("milch") == 0,
		"%d left" % Inventory.count("milch"))

	# ---------- the inventory keeps the hands honest ----------
	Inventory.clear()
	Inventory.add("heu", 1)
	_check("picking something up puts it in hand", GameState.carrying == "heu",
		GameState.carrying)
	Inventory.add("milch", 1)
	_check("a second pickup does not swap what is in hand",
		GameState.carrying == "heu", GameState.carrying)
	Inventory.remove("heu", 1)
	_check("running out empties the hand", GameState.carrying == "",
		GameState.carrying)
	_check("removing more than you own is refused",
		not Inventory.remove("milch", 5))
	_check("...and changes nothing", Inventory.count("milch") == 1)

	# ---------- all of it survives a save/load ----------
	Farm.reset()
	Livestock.reset()
	Inventory.clear()
	GameState.day = 30
	Farm.plant(Vector2i(6, 27), "kartoffel")
	Inventory.add("heu", 1)
	Livestock.feed("obj_cow")
	Inventory.add("butter", 3)
	var snapshot := GameState.to_dict()

	Farm.reset()
	Livestock.reset()
	Inventory.clear()
	Farm.from_dict(snapshot.get("plots", {}))
	Livestock.from_dict(snapshot.get("animals", {}))
	Inventory.from_dict(snapshot.get("inventory", {}))
	_check("plots survive a save/load", Farm.is_planted(Vector2i(6, 27)))
	_check("...with their crop", str(Farm.plot(Vector2i(6, 27)).get("crop", "")) == "kartoffel")
	_check("fed animals survive a save/load", Livestock.was_fed_today("obj_cow"))
	_check("the inventory survives a save/load", Inventory.count("butter") == 3,
		"%d" % Inventory.count("butter"))

	# ---------- every crop and product is a word the player can meet ----------
	# A crop with no vocabulary entry is a thing the game hands you and cannot
	# name, which defeats the entire point of growing it.
	for crop_id in ["kartoffel", "karotte", "salat", "erdbeere"]:
		_check("crop '%s' is a known word" % crop_id,
			not ContentDB.get_word(crop_id).is_empty())
	for object_id in ["obj_cow", "obj_hen", "obj_pig"]:
		var item := Livestock.product(object_id)
		_check("product '%s' is a known word" % item,
			not ContentDB.get_word(item).is_empty())
	for recipe_id in ["butter", "kaese"]:
		_check("craft '%s' is a known word" % recipe_id,
			not ContentDB.get_word(recipe_id).is_empty())

	print("--- farm acceptance complete, %d failure(s). ---" % _failures)
