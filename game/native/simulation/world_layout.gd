extends RefCounted
## Continuous-world placement in fixed simulation units. Geometry caches belong
## to one session, so another imported JAR never inherits these station bounds.
const Math = preload("res://native/simulation/fixed_math.gd")
const StationBody = preload("res://native/simulation/station_body.gd")
const Spacing = preload("res://native/simulation/world_spacing.gd")
const REGION_APPROACH_DISTANCE := 60000.0
## Room for the 150 m activation area, hull, opening arms and both transit ends.
const GATE_CLEARANCE := 18000.0
const GATE_PASSAGE := 30000.0
## Half the side of the cube a gate opens for (World.at_gate).
const GATE_ACTIVATION := 15000.0
var station_bounds := {}
var spacing_meters := Spacing.DEFAULT_METERS:
	set(value):
		var valid:=Spacing.valid_meters(value)
		if spacing_meters==valid:return
		spacing_meters=valid
		station_bounds.clear()

func station_origin(station: Dictionary) -> Array:
	return [station.x*spacing_meters*100,station.depth*8,station.y*spacing_meters*100]

func volumes(session, sine: Array) -> Array:
	var result: Array=[]
	for station in session.stations:
		var signature: Array=[station.x,station.y,station.depth,station.percent,station.tech]
		if not station_bounds.has(station.id) or station_bounds[station.id].signature!=signature:
			var body:=StationBody.new()
			body.configure(station,false,sine,session.data.get("station_geometry",{}))
			var origin:=Math.vector(station_origin(station))
			var parts: Array[AABB]=[]
			var bounds:=AABB()
			for shape in body.shapes:
				var center:=origin+Math.vector(shape.origin)+Math.vector(shape.offset)
				var half:=Math.vector(shape.half_size)
				var box:=AABB(center-half,half*2.0)
				bounds=box if parts.is_empty() else bounds.merge(box)
				parts.append(box)
			station_bounds[station.id]={"id":station.id,"signature":signature,"origin":origin,"bounds":bounds,"parts":parts}
		result.append(station_bounds[station.id])
	return result

func clear_gates(session, station: Dictionary, gates: Array, sine: Array) -> Array:
	var obstacles:=volumes(session,sine)
	var anchor:=Math.vector(station_origin(station))
	var result: Array=[]
	for index in gates.size():
		# Arrival and departure can be two logical slots of the same portal.
		var shared: int=gates.find(gates[index])
		if shared<index:
			result.append(result[shared].duplicate())
			continue
		result.append(place_gate(Math.vector(gates[index]),anchor,station.id,obstacles,result.map(func(gate):return Math.vector(gate))))
	return result

static func passage_clear(point: Vector3, anchor: Vector3, owner_id: int, obstacles: Array) -> bool:
	var direction:=Vector3(point.x,0,point.z).normalized()
	var start:=anchor+point-direction*GATE_PASSAGE
	var finish:=anchor+point+direction*GATE_PASSAGE
	for entry in obstacles:
		# A portal must not hand the player to a neighbouring region during
		# activation or the exit shot, even if no wall occupies its centre.
		if entry.id!=owner_id:
			var nearest:=Geometry3D.get_closest_point_to_segment(entry.origin,start,finish)
			# Activation is a cube, so its corners need the diagonal margin.
			if nearest.distance_to(entry.origin)<REGION_APPROACH_DISTANCE+sqrt(3.0)*GATE_CLEARANCE:return false
		if entry.bounds.grow(GATE_CLEARANCE).intersects_segment(start,finish)==null:continue
		for box: AABB in entry.parts:
			if box.grow(GATE_CLEARANCE).intersects_segment(start,finish)!=null:return false
	return true

static func apart(point: Vector3, taken: Array) -> bool:
	"""Whether a portal here keeps its activation cube out of the ones already
	placed, so separate IN and OUT gates never open together."""
	for other: Vector3 in taken:
		var gap:=(point-other).abs()
		if maxf(gap.x,maxf(gap.y,gap.z))<2*GATE_ACTIVATION:return false
	return true

static func place_gate(preferred: Vector3, anchor: Vector3, owner_id: int, obstacles: Array, taken: Array=[]) -> Array:
	if apart(preferred,taken) and passage_clear(preferred,anchor,owner_id,obstacles):return Math.array(preferred)
	# Keep the station's depth and usual gate radius. Try nearby headings
	# first, then wider rings; no gameplay random draws or named exceptions.
	var radius:=Vector2(preferred.x,preferred.z).length()
	var heading:=atan2(preferred.x,preferred.z)
	for ring in 12:
		for step in 32:
			var offset: int=(step+1)/2*(1 if step%2==1 else -1)
			var angle:=heading+offset*TAU/32.0
			var reach:=radius+ring*20000.0
			var candidate:=Math.vector(Math.array(Vector3(sin(angle)*reach,preferred.y,cos(angle)*reach)))
			if apart(candidate,taken) and passage_clear(candidate,anchor,owner_id,obstacles):return Math.array(candidate)
	# Unusually crowded compatible maps still get a clear portal. A point
	# beyond every station's bounds and activation volume has a safe passage.
	var edge:=anchor.x
	for entry in obstacles:edge=maxf(edge,maxf(entry.bounds.end.x,entry.origin.x+REGION_APPROACH_DISTANCE))
	# A second portal there steps along the edge, clear of the first.
	return Math.array(Vector3(edge-anchor.x+sqrt(3.0)*GATE_CLEARANCE+GATE_PASSAGE+100,preferred.y,preferred.z+taken.size()*2*(GATE_ACTIVATION+1)))
