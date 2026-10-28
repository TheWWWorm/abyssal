extends RefCounted
## Station positions in ocean metres and the anchor of the current region.
## The ocean is bottomless, as in the original: there is no seabed.
var stations: Array = []
var anchor := Vector3.ZERO
func configure(world) -> void:
	stations.clear()
	for station in world.session.stations:
		var origin: Array=world.station_origin(station.id)
		stations.append(Vector3(origin[0],-origin[1],-origin[2])*0.01)
	var p: Array = world.station_origin(world.session.station_id)
	anchor=Vector3(p[0],-p[1],-p[2])*0.01
