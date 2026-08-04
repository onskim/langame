extends Node
## Turning what the farm gives into what the village wants. Part 10 §5.3 Q13
## ("Butter für Karl") is the first quest that needs this to exist.
##
## Recipes are data in `config/economy.yaml`, not code, so "Milch + Milch =
## Butter" is a content decision. That matters beyond tidiness: each recipe is a
## sentence the player will hear ("Zwei Milch, bitte") and the words in it have
## to be authorable alongside the lines that use them.

signal crafted(output_id: String, count: int)

## Emitted when a craft is refused, with a content key explaining why — the
## station should teach, not just decline.
signal refused(recipe_id: String, reason: String)


func _table() -> Dictionary:
	var block: Variant = Config._section("economy").get("recipes")
	return block if block is Dictionary else {}


func recipe(recipe_id: String) -> Dictionary:
	var found: Variant = _table().get(recipe_id)
	return found if found is Dictionary else {}


## Recipes a given station can make, in content order.
func recipes_at(station_id: String) -> Array[String]:
	var found: Array[String] = []
	for recipe_id in _table():
		if str(recipe(str(recipe_id)).get("station", "")) == station_id:
			found.append(str(recipe_id))
	return found


func inputs_of(recipe_id: String) -> Dictionary:
	var block: Variant = recipe(recipe_id).get("inputs")
	return block if block is Dictionary else {}


func can_craft(recipe_id: String) -> bool:
	var inputs := inputs_of(recipe_id)
	if inputs.is_empty():
		return false
	for item_id in inputs:
		if not Inventory.has(str(item_id), int(inputs[item_id])):
			return false
	return true


## What the player is short of, so the station can name it. "Du brauchst noch
## eine Milch" teaches a word; a greyed-out button does not.
func missing_for(recipe_id: String) -> Dictionary:
	var short: Dictionary = {}
	var inputs := inputs_of(recipe_id)
	for item_id in inputs:
		var gap := int(inputs[item_id]) - Inventory.count(str(item_id))
		if gap > 0:
			short[str(item_id)] = gap
	return short


## Consume the inputs and grant the output. All or nothing: a craft that takes
## the milk and fails to give the butter is the worst possible bug here, so the
## inputs are only removed once every one of them is confirmed present.
func craft(recipe_id: String) -> String:
	var definition := recipe(recipe_id)
	if definition.is_empty():
		return ""
	if not can_craft(recipe_id):
		refused.emit(recipe_id, "missing_ingredients")
		return ""
	var inputs := inputs_of(recipe_id)
	for item_id in inputs:
		if not Inventory.remove(str(item_id), int(inputs[item_id])):
			# Unreachable given can_craft, but if it ever happens the player
			# must not be left short — put back whatever was already taken.
			push_error("[craft] %s vanished mid-recipe" % item_id)
			return ""
	var output := str(definition.get("output", recipe_id))
	var count := maxi(1, int(definition.get("output_count", 1)))
	Inventory.add(output, count)
	crafted.emit(output, count)
	print("[craft] %s -> %d x %s" % [recipe_id, count, output])
	return output
