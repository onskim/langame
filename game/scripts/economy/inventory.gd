extends Node
## What the player owns. GDD Part 14 §4–§5.
##
## Until now the game tracked ONE carried item as a bare string on GameState,
## which was enough for "pick up hay, feed the cow" and nothing else. Harvesting
## a field, milking a cow and churning butter all need counts.
##
## `GameState.carrying` survives as the item currently IN HAND — the thing a
## Tier I action uses — and every quest written against it keeps working. The
## store of record is here. The two are kept in step in one place, `_sync_hands`,
## because two systems that each think they own "what the player has" is exactly
## how an item gets duplicated or silently eaten.
##
## Item ids are content word_ids (milch, ei, kartoffel). The engine never knows
## what any of them mean.

signal changed(item_id: String, count: int)

## item_id -> count. Absent means zero; nothing is ever stored as 0.
var items: Dictionary = {}


func count(item_id: String) -> int:
	return int(items.get(item_id, 0))


func has(item_id: String, amount: int = 1) -> bool:
	return count(item_id) >= amount


func add(item_id: String, amount: int = 1) -> void:
	if item_id == "" or amount <= 0:
		return
	items[item_id] = count(item_id) + amount
	changed.emit(item_id, count(item_id))
	_sync_hands(item_id)


## Returns false and changes nothing if the player does not have that many —
## a partial removal would leave the caller believing a trade succeeded.
func remove(item_id: String, amount: int = 1) -> bool:
	if amount <= 0:
		return true
	if not has(item_id, amount):
		return false
	var left := count(item_id) - amount
	if left > 0:
		items[item_id] = left
	else:
		items.erase(item_id)
	changed.emit(item_id, left)
	_sync_hands(item_id)
	return true


## Everything owned, most-held first — for the day-end card and the phone.
func contents() -> Array:
	var rows: Array = []
	for item_id in items:
		rows.append({"item": item_id, "count": int(items[item_id])})
	rows.sort_custom(func(a, b): return int(a["count"]) > int(b["count"]))
	return rows


func total_items() -> int:
	var sum := 0
	for item_id in items:
		sum += int(items[item_id])
	return sum


func clear() -> void:
	items.clear()
	GameState.carrying = ""


## Keep the in-hand item honest. Picking something up puts it in hand; running
## out of it empties the hand. Without this the player can "carry" hay they
## spent, and the cow gets fed forever off one bale.
func _sync_hands(item_id: String) -> void:
	if count(item_id) > 0:
		if GameState.carrying == "":
			GameState.carrying = item_id
	elif GameState.carrying == item_id:
		GameState.carrying = ""


func to_dict() -> Dictionary:
	return items.duplicate()


func from_dict(data: Variant) -> void:
	items.clear()
	if data is Dictionary:
		for item_id in (data as Dictionary):
			var amount := int((data as Dictionary)[item_id])
			if amount > 0:
				items[str(item_id)] = amount
