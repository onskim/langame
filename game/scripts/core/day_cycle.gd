extends Node
## Day clock and day/night tint. GDD Part 10 §6 Week 1 / Part 12 §time.
##
## Clock runs 06:00 -> 24:00 across ~7 real minutes, then the day is over.
## Sleeping (bed) is what advances the day counter — see GameState.sleep().

signal time_changed(hour: float)
signal day_changed(day: int)

const START_HOUR := 6.0
const END_HOUR := 24.0
const REAL_SECONDS_PER_DAY := 420.0  ## ~7 real minutes for 18 in-game hours

var hour: float = START_HOUR
var running: bool = true

var _hours_per_second: float = (END_HOUR - START_HOUR) / REAL_SECONDS_PER_DAY


func _process(delta: float) -> void:
	if not running:
		return
	var previous := hour
	hour = min(hour + delta * _hours_per_second, END_HOUR)
	if not is_equal_approx(previous, hour):
		time_changed.emit(hour)


func reset_to_morning() -> void:
	hour = START_HOUR
	time_changed.emit(hour)


func is_day_over() -> bool:
	return hour >= END_HOUR


## "07:42" — display only. Never a German string in engine code (repo rule);
## digits and a colon are language-neutral.
func clock_string() -> String:
	var h := int(hour)
	var m := int((hour - h) * 60.0)
	return "%02d:%02d" % [h, m]


## Darkness 0.0 (noon) .. 1.0 (midnight), for the day/night tint.
func darkness() -> float:
	if hour <= 8.0:
		return remap(hour, START_HOUR, 8.0, 0.45, 0.0)
	if hour >= 18.0:
		return remap(hour, 18.0, END_HOUR, 0.0, 0.75)
	return 0.0
