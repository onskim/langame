extends WorldMap
## The player's farm — the PRIVATE space (GDD Part 14 §2).
##
## Labour, quiet, no NPCs except Anna next door. Nothing social happens here:
## that is the point. Going to the village has to be a choice with a reason.


func build_ground() -> void:
	WorldBuilder.paint_ground($Ground)
	WorldBuilder.build_fence($Fence, self, WorldBuilder.GateSide.EAST)
