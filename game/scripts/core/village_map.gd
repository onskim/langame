extends WorldMap
## The village — the SOCIAL space (GDD Part 14 §2).
##
## All shops, all people, all talk. Buildings are placed here rather than being
## bare markers on a field, because "Karl is in the Bäckerei" has to be
## something the player can see before it can be something they understand.


func build_ground() -> void:
	WorldBuilder.paint_village($Ground)
