extends Node
## Calendar and weather. GDD Part 12 §5.
##
## Maps the flat day counter onto season / day-in-season / weekday, and derives
## the weather deterministically from the save seed so tomorrow's forecast is
## honest — the Wetter app must not be able to lie to a player who checks it
## twice.
##
## Season = 24 days, year = 96. All names come from content, because the
## weekdays and weather words ARE curriculum (Part 12 §5), not chrome.

signal weather_changed(weather_id: String)


func _cal() -> Dictionary:
	var section: Variant = ContentDB.config.get("calendar")
	return section if section is Dictionary else {}


func days_per_season() -> int:
	return int(_cal().get("days_per_season", 24))


func season_names() -> Array:
	var s: Variant = _cal().get("seasons")
	return s if s is Array else ["Frühling", "Sommer", "Herbst", "Winter"]


func weekday_names() -> Array:
	var w: Variant = _cal().get("weekdays")
	return w if w is Array else []


## 0-based season index for a day number (day 1 = first day of Frühling).
func season_index(day: int) -> int:
	var names := season_names()
	if names.is_empty():
		return 0
	return int(floor((day - 1) / float(days_per_season()))) % names.size()


func season_name(day: int) -> String:
	var names := season_names()
	return "" if names.is_empty() else str(names[season_index(day)])


## 1-based day within the current season.
func day_in_season(day: int) -> int:
	return ((day - 1) % days_per_season()) + 1


func weekday_index(day: int) -> int:
	var names := weekday_names()
	if names.is_empty():
		return 0
	return (day - 1) % names.size()


func weekday_name(day: int) -> String:
	var names := weekday_names()
	return "" if names.is_empty() else str(names[weekday_index(day)])


func year_of(day: int) -> int:
	var year_length: int = days_per_season() * max(season_names().size(), 1)
	return int(floor((day - 1) / float(year_length))) + 1


## Market day is Samstag — the weekly speaking-heavy event (Part 12 §5).
func is_market_day(day: int) -> bool:
	return weekday_name(day) == str(_cal().get("market_day", "Samstag"))


## Shops shut Sonntag, which teaches the weekday without a lesson.
func is_rest_day(day: int) -> bool:
	return weekday_name(day) == str(_cal().get("rest_day", "Sonntag"))


func festival_today(day: int) -> Dictionary:
	var festivals: Variant = _cal().get("festivals")
	if not (festivals is Dictionary):
		return {}
	var entry: Variant = (festivals as Dictionary).get(season_name(day))
	if entry is Dictionary and int((entry as Dictionary).get("day_in_season", -1)) == day_in_season(day):
		return entry
	return {}


## Deterministic weather for any day, so tomorrow's forecast is the weather
## that actually arrives. A forecast that can change is not a forecast.
func weather_for(day: int) -> String:
	var table: Variant = _cal().get("weather")
	if not (table is Dictionary):
		return "sonne"
	var weights: Variant = (table as Dictionary).get(season_name(day))
	if not (weights is Dictionary):
		return "sonne"

	var total := 0
	for key in (weights as Dictionary):
		total += int((weights as Dictionary)[key])
	if total <= 0:
		return "sonne"

	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d:%d" % [GameState.weather_seed, day])
	var roll := rng.randi_range(0, total - 1)

	var keys := (weights as Dictionary).keys()
	keys.sort()
	for key in keys:
		roll -= int((weights as Dictionary)[key])
		if roll < 0:
			return str(key)
	return "sonne"


func weather_today() -> String:
	return weather_for(GameState.day)


func weather_tomorrow() -> String:
	return weather_for(GameState.day + 1)


## Regen auto-waters the crops — a reward day, not a punishment (Part 12 §5).
func rain_waters_crops(day: int) -> bool:
	return weather_for(day) == "regen"


## "Montag, 3. Frühling" — display built from content words only.
func date_string(day: int) -> String:
	return "%s, %d. %s" % [weekday_name(day), day_in_season(day), season_name(day)]
