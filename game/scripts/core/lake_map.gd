extends WorldMap
## The lake shore — GDD Part 14 §2, the end of the village -> forest -> lake
## chain and Jonas's home water.
##
## Grass on the near bank, open water reaching the far edge. The point of the
## place is that the world visibly continues past it.


func build_ground() -> void:
	WorldBuilder.paint_lake($Ground, $Water, self)
