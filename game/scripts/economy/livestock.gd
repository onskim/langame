extends Node
## Animals and what they give. GDD Part 14 §4, Part 10 §5.3 (Q04, Q13).
##
## One contract for every animal, and the contract IS the lesson: FEED IT AND IT
## GIVES. An animal fed today has something for you tomorrow; an unfed animal
## has nothing. The cow gives Milch, the hen gives das Ei, and because both are
## daily rituals those two words get met more often than any dialogue could
## arrange. Part 3's whole premise is that comprehension is proved by doing —
## this is the farm's version of it.
##
## Every animal, its feed and its product come from `config/economy.yaml`. This
## script does not know what a cow is.

signal produced(object_id: String, item_id: String)
signal fed(object_id: String, item_id: String)

## object_id -> {fed_on: day, collected_on: day}
var animals: Dictionary = {}


func _table() -> Dictionary:
	var block: Variant = Config._section("economy").get("animals")
	return block if block is Dictionary else {}


func definition(object_id: String) -> Dictionary:
	var found: Variant = _table().get(object_id)
	return found if found is Dictionary else {}


func is_animal(object_id: String) -> bool:
	return not definition(object_id).is_empty()


func _record(object_id: String) -> Dictionary:
	if not animals.has(object_id):
		animals[object_id] = {"fed_on": -1, "collected_on": -1}
	return animals[object_id]


func feed_item(object_id: String) -> String:
	return str(definition(object_id).get("feed_item", ""))


func product(object_id: String) -> String:
	return str(definition(object_id).get("product", ""))


func was_fed_today(object_id: String) -> bool:
	return int(_record(object_id).get("fed_on", -1)) == GameState.day


## Feed an animal from the inventory. Returns false — and consumes nothing — if
## the player has no feed or the animal has already eaten today, so a mistimed
## E-press can never quietly cost the player a bale of hay.
func feed(object_id: String) -> bool:
	if not is_animal(object_id) or was_fed_today(object_id):
		return false
	var needed := feed_item(object_id)
	if needed != "" and not Inventory.remove(needed, 1):
		return false
	_record(object_id)["fed_on"] = GameState.day
	fed.emit(object_id, needed)
	return true


## An animal produces the day AFTER it is fed, and only once per interval. The
## delay is deliberate: it turns feeding into a habit with a payoff you come
## back for, which is exactly the retention shape the daily word ritual needs.
func can_collect(object_id: String) -> bool:
	if not is_animal(object_id):
		return false
	var record := _record(object_id)
	var fed_on := int(record.get("fed_on", -1))
	if fed_on < 0 or fed_on >= GameState.day:
		return false
	var last := int(record.get("collected_on", -1))
	var interval := maxi(1, int(definition(object_id).get("interval_days", 1)))
	return last < 0 or GameState.day - last >= interval


## Take the product. Returns the item id, or "" if there was nothing to take.
func collect(object_id: String) -> String:
	if not can_collect(object_id):
		return ""
	var item := product(object_id)
	if item == "":
		return ""
	_record(object_id)["collected_on"] = GameState.day
	Inventory.add(item, 1)
	produced.emit(object_id, item)
	print("[livestock] %s gave %s on day %d" % [object_id, item, GameState.day])
	return item


## Why nothing happened, as a content key the UI can look up. Returning a reason
## rather than a bare false is what lets the game TEACH here instead of just
## refusing — an animal that stays silent when you press E teaches nothing.
func refusal_reason(object_id: String) -> String:
	if not is_animal(object_id):
		return ""
	var record := _record(object_id)
	if int(record.get("fed_on", -1)) < 0:
		return "animal_hungry"
	if int(record.get("fed_on", -1)) >= GameState.day:
		return "animal_not_yet"
	return "animal_already_collected"


func animals_with_product() -> Array[String]:
	var ready: Array[String] = []
	for object_id in _table():
		if can_collect(str(object_id)):
			ready.append(str(object_id))
	return ready


func reset() -> void:
	animals.clear()


func to_dict() -> Dictionary:
	return animals.duplicate(true)


func from_dict(data: Variant) -> void:
	animals.clear()
	if data is Dictionary:
		for object_id in (data as Dictionary):
			var record: Variant = (data as Dictionary)[object_id]
			if record is Dictionary:
				animals[str(object_id)] = (record as Dictionary).duplicate()
