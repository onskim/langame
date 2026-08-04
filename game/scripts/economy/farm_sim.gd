extends Node
## The crop simulation. GDD Part 14 §4.3–§4.4.
##
## Rules, and why they are these rules:
##
##   * Growth is counted in WATERED days, not calendar days. Missing a day
##     pauses a crop, it does not kill it. The farm exists to generate reasons to
##     go and talk to people (Part 14 §4.5); a farm that punishes you for
##     spending a day in the village is working against the game.
##   * Two dry days wilt a plot, four kill it, and watering a wilted plot brings
##     it back for the price of a day. Gentle, not Stardew-brutal — §4.4 says so
##     explicitly.
##   * RAIN WATERS EVERYTHING. This is the load-bearing one. It is what makes
##     reading tomorrow's forecast in the Wetter app and deciding not to water
##     an act of comprehension with real stakes (Part 12 §5). Without it the
##     weather is set dressing.
##
## Every number is read from `config/economy.yaml`. Nothing about crops is
## hardcoded here, so balancing is a content edit.

signal plot_changed(cell: Vector2i)
signal day_report(watered_by_rain: bool, grown: int, wilted: int, died: int)

## "x,y" -> {crop, grown_days, dry_days, watered_on, dead}
## Keyed by string because the save file is JSON and JSON has no Vector2i.
var plots: Dictionary = {}


func _key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]


func _growth() -> Dictionary:
	var block: Variant = Config._section("economy").get("growth")
	return block if block is Dictionary else {}


func crop_table() -> Dictionary:
	var block: Variant = Config._section("economy").get("crops")
	return block if block is Dictionary else {}


func crop_def(crop_id: String) -> Dictionary:
	var found: Variant = crop_table().get(crop_id)
	return found if found is Dictionary else {}


func stages() -> int:
	return int(_growth().get("stages", 4))


## Only the player's own field is plantable — Anna's plot is hers (Part 14 §3).
func is_plot(cell: Vector2i) -> bool:
	return WorldBuilder.in_player_field(cell.x, cell.y)


func plot(cell: Vector2i) -> Dictionary:
	var found: Variant = plots.get(_key(cell))
	return found if found is Dictionary else {}


func is_planted(cell: Vector2i) -> bool:
	return not plot(cell).is_empty()


## Sow a seed. Fails on a cell outside the field or one already growing
## something, rather than silently overwriting a crop the player was waiting on.
func plant(cell: Vector2i, crop_id: String) -> bool:
	if not is_plot(cell) or is_planted(cell):
		return false
	if crop_def(crop_id).is_empty():
		push_error("[farm] no such crop '%s' in economy.yaml" % crop_id)
		return false
	plots[_key(cell)] = {
		"crop": crop_id,
		"grown_days": 0,
		"dry_days": 0,
		# Seed day counts as watered: sowing into damp soil is the norm, and
		# starting a crop already one day dry is a trap the player cannot see.
		"watered_on": GameState.day,
		"dead": false,
	}
	plot_changed.emit(cell)
	return true


func water(cell: Vector2i) -> bool:
	var record := plot(cell)
	if record.is_empty() or bool(record.get("dead", false)):
		return false
	if int(record.get("watered_on", -1)) == GameState.day:
		return false  # already watered today; let the caller say so
	record["watered_on"] = GameState.day
	# Reviving a wilted plot costs a day of growth rather than nothing, so
	# neglect has a price without ever being unrecoverable.
	if int(record.get("dry_days", 0)) >= wilt_after():
		var penalty := int(_growth().get("revive_growth_penalty_days", 1))
		record["grown_days"] = max(0, int(record.get("grown_days", 0)) - penalty)
	record["dry_days"] = 0
	plot_changed.emit(cell)
	return true


func wilt_after() -> int:
	return int(_growth().get("wilt_after_dry_days", 2))


func die_after() -> int:
	return int(_growth().get("die_after_dry_days", 4))


func is_watered_today(cell: Vector2i) -> bool:
	return int(plot(cell).get("watered_on", -1)) == GameState.day


func is_wilted(cell: Vector2i) -> bool:
	var record := plot(cell)
	if record.is_empty() or bool(record.get("dead", false)):
		return false
	return int(record.get("dry_days", 0)) >= wilt_after()


func is_dead(cell: Vector2i) -> bool:
	return bool(plot(cell).get("dead", false))


func is_ready(cell: Vector2i) -> bool:
	var record := plot(cell)
	if record.is_empty() or bool(record.get("dead", false)):
		return false
	var needed := int(crop_def(str(record.get("crop", ""))).get("days", 99))
	return int(record.get("grown_days", 0)) >= needed


## 0..stages(); the sprite frame to draw.
func stage_of(cell: Vector2i) -> int:
	var record := plot(cell)
	if record.is_empty():
		return 0
	var needed := int(crop_def(str(record.get("crop", ""))).get("days", 1))
	if needed <= 0:
		return stages()
	var fraction := float(record.get("grown_days", 0)) / float(needed)
	return clampi(int(floor(fraction * stages())), 0, stages())


## Harvest a ready plot into the inventory. Returns the crop id, or "".
func harvest(cell: Vector2i) -> String:
	if not is_ready(cell):
		return ""
	var record := plot(cell)
	var crop_id := str(record.get("crop", ""))
	Inventory.add(crop_id, 1)
	if bool(crop_def(crop_id).get("regrows", false)):
		# A regrowing crop goes back a stage rather than clearing the plot —
		# that is what makes Erdbeere worth its higher seed price.
		record["grown_days"] = 0
		record["dry_days"] = 0
	else:
		plots.erase(_key(cell))
	plot_changed.emit(cell)
	return crop_id


## Clear a dead plot so the tile can be used again.
func clear_plot(cell: Vector2i) -> bool:
	if not is_planted(cell):
		return false
	plots.erase(_key(cell))
	plot_changed.emit(cell)
	return true


func rain_waters_on(day: int) -> bool:
	var wet: Variant = _growth().get("rain_waters", [])
	if not (wet is Array):
		return false
	return (wet as Array).has(Calendar.weather_for(day))


## Roll the whole field forward one night. Called by the sleep path AFTER the
## day number has advanced, so `new_day` is the day being woken into.
func advance_day(new_day: int) -> void:
	var rained := rain_waters_on(new_day)
	var grown := 0
	var wilted := 0
	var died := 0

	for key in plots.keys():
		var record: Dictionary = plots[key]
		if bool(record.get("dead", false)):
			continue
		# Rain overnight counts exactly as a watering can does. The player who
		# read the forecast and stayed in the village loses nothing.
		var had_water: bool = rained \
			or int(record.get("watered_on", -1)) >= new_day - 1
		if had_water:
			record["dry_days"] = 0
			record["grown_days"] = int(record.get("grown_days", 0)) + 1
			grown += 1
			if rained:
				record["watered_on"] = new_day
		else:
			var dry := int(record.get("dry_days", 0)) + 1
			record["dry_days"] = dry
			if dry >= die_after():
				record["dead"] = true
				died += 1
			elif dry >= wilt_after():
				wilted += 1

	day_report.emit(rained, grown, wilted, died)
	print("[farm] day %d — rain=%s grown=%d wilted=%d died=%d"
		% [new_day, rained, grown, wilted, died])


func planted_count() -> int:
	return plots.size()


func ready_count() -> int:
	var total := 0
	for key in plots:
		var parts := str(key).split(",")
		if is_ready(Vector2i(int(parts[0]), int(parts[1]))):
			total += 1
	return total


func reset() -> void:
	plots.clear()


func to_dict() -> Dictionary:
	return plots.duplicate(true)


func from_dict(data: Variant) -> void:
	plots.clear()
	if data is Dictionary:
		for key in (data as Dictionary):
			var record: Variant = (data as Dictionary)[key]
			if record is Dictionary:
				plots[str(key)] = (record as Dictionary).duplicate()
