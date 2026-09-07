extends RefCounted
## Authored world terrain, independent of the source random stream.
var stations: Array = []
var anchor := Vector3.ZERO
var contact := Vector3.ZERO
var prop_cache: Dictionary = {}
var height_cache: Dictionary = {}
var rock_normal := Vector3.ZERO
var seafloor_enabled := false
# Keep the source encounter volume navigable. Ordinary actor spawns span
# +/-300 m vertically and scripted routes extend about 3 km from a station.
# Capsules cycle down the central 750 m shaft at every rescue location.
const ENCOUNTER_RADIUS := 3500.0
const ENCOUNTER_FLOOR := 480.0
const CAPSULE_RADIUS := 180.0
const CAPSULE_FLOOR := 900.0
func configure(world) -> void:
	for station in world.session.stations: stations.append(Vector3(station.x*400,-station.depth*0.08, -station.y*400))
	var p: Array = world.station_origin(world.session.station_id)
	anchor=Vector3(p[0],-p[1],-p[2])*0.01
func base_height(key: Vector2i) -> float:
	if height_cache.has(key): return height_cache[key]
	var numerator := 0.0; var denominator := 0.0
	var ceiling := INF
	for station in stations:
		var dx: float = key.x*400-station.x; var dz: float = key.y*400-station.z
		var squared := maxf(6400,dx*dx+dz*dz)
		var weight := 1.0/(squared*squared)
		numerator+=(station.y-180)*weight; denominator+=weight
		var distance := sqrt(dx*dx+dz*dz)
		ceiling=minf(ceiling,station.y-ENCOUNTER_FLOOR+maxf(0,distance-ENCOUNTER_RADIUS))
		ceiling=minf(ceiling,station.y-CAPSULE_FLOOR+maxf(0,distance-CAPSULE_RADIUS))
	var result := numerator/denominator if denominator>0 else 1600.0
	result=minf(result,ceiling)
	if height_cache.size()>4096: height_cache.erase(height_cache.keys()[0])
	height_cache[key]=result
	return result
func height(x: float,z: float) -> float:
	var cell := Vector2i(floori(x/400),floori(z/400))
	var fx := x/400-cell.x; var fz := z/400-cell.y
	var a := lerpf(base_height(cell),base_height(cell+Vector2i(1,0)),fx)
	var b := lerpf(base_height(cell+Vector2i(0,1)),base_height(cell+Vector2i(1,1)),fx)
	return lerpf(a,b,fz)+sin(x*0.011)*cos(z*0.007)*24+sin(x*0.027+z*0.019)*8
func contains(point: Array) -> bool:
	if not seafloor_enabled: return false
	contact=Vector3(point[0],-point[1],-point[2])*0.01+anchor
	rock_normal=Vector3.ZERO
	if contact.y<height(contact.x,contact.z)+14: return true
	for prop in props(Vector2i(floori(contact.x/360),floori(contact.z/360))):
		var relative: Vector3 = contact-prop.position
		if absf(relative.x)<6*prop.scale+6 and absf(relative.z)<6*prop.scale+6 and relative.y<float(prop.height)*prop.scale+8 and relative.y>0:
			rock_normal=Vector3(relative.x,2,relative.z).normalized(); return true
	return false
func avoidance_normal(_point: Array) -> Array:
	if rock_normal!=Vector3.ZERO: return [int(rock_normal.x*4096),int(-rock_normal.y*4096),int(-rock_normal.z*4096)]
	var dx := height(contact.x+2,contact.z)-height(contact.x-2,contact.z)
	var dz := height(contact.x,contact.z+2)-height(contact.x,contact.z-2)
	var n := Vector3(-dx,4,-dz).normalized()
	return [int(n.x*4096),int(-n.y*4096),int(-n.z*4096)]

func props(key: Vector2i) -> Array:
	if prop_cache.has(key): return prop_cache[key]
	var rng := RandomNumberGenerator.new(); rng.seed=absi(key.x*73856093^key.y*19349663)^78213
	var result: Array = []
	for i in 5:
		var x: float = key.x*360+rng.randf_range(30,330); var z: float = key.y*360+rng.randf_range(30,330)
		if stations.any(func(station): return Vector2(x-station.x,z-station.z).length()<120): continue
		var variant := posmod(key.x*13+key.y*17+i*7,8)
		var model_id: int = [10000,10003,10004,10003,10005,10004,10003,10005][variant]
		var top: float = {10000:12.0,10003:3.0,10004:4.5,10005:5.5}[model_id]
		result.append({"position":Vector3(x,height(x,z),z),"scale":rng.randf_range(1.5,3.8),"model_id":model_id,"height":top,"yaw":float(posmod(key.x*31+key.y*23+i*59,360))})
	if prop_cache.size()>64: prop_cache.erase(prop_cache.keys()[0])
	prop_cache[key]=result
	return result
