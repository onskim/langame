extends Node
## Save v0 — JSON at user://save.json. GDD Part 10 §6 Week 1.
##
## The SQLite player DB arrives Week 4 (Part 10 §3); this is deliberately the
## smallest thing that satisfies "day count and position survive quit+relaunch".

const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 0


func save_game(data: Dictionary) -> bool:
	data["version"] = SAVE_VERSION
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("SaveService: cannot open %s for write (%d)" % [SAVE_PATH, FileAccess.get_open_error()])
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	print("[save] wrote %s -> %s" % [SAVE_PATH, data])
	return true


func load_game() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		print("[save] no save file, starting fresh")
		return {}
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_error("SaveService: cannot open %s for read" % SAVE_PATH)
		return {}
	var text := file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("SaveService: save file corrupt, ignoring")
		return {}
	var data: Dictionary = parsed
	if data.get("version", -1) != SAVE_VERSION:
		push_warning("SaveService: save version %s != %d, ignoring" % [data.get("version"), SAVE_VERSION])
		return {}
	print("[save] loaded %s" % data)
	return data


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


## Absolute path, for the founder to inspect during Week 1 verification.
func absolute_path() -> String:
	return ProjectSettings.globalize_path(SAVE_PATH)
