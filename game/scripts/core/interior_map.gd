extends WorldMap
## An interior room. GDD Part 14 §3.
##
## Small, lamplit, one screen. The door back out is always visible from the
## spawn point — an interior the player has to search for the exit in is a
## trap, not a shop.

@export var room_width: int = 20
@export var room_height: int = 14


func build_ground() -> void:
	WorldBuilder.paint_interior($Ground, self, room_width, room_height)
