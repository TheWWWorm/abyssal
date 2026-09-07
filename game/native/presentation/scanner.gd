extends RefCounted
## cb radar visibility and close-range detail; projection belongs to the UI.
static func describe(actor, role: String, radar: int, mission_kind: int, player_position: Array) -> Dictionary:
	var result := {"visible":false,"edge":false,"identify":false,"hull":-1.0,"recoverable":false,"role":role}
	if not actor.health.enabled: return result
	if role=="creature":
		if actor.subdued or actor.state==4 and not actor.meat: return result
		result.visible=mission_kind==6 or radar in [3,4]
		result.edge=mission_kind==6 and radar>0
		result.identify=radar in [3,4]
		return result
	if radar<=0 or actor.state==3 and (role=="friend" or not actor.capturable): return result
	if actor.state==4 and not actor.capturable: return result
	result.visible=true; result.edge=true
	result.identify=role=="enemy" and radar in [2,4]
	result.recoverable=actor.capturable and actor.state in [3,4]
	var close := true
	for axis in 3:
		if absi(player_position[axis]-actor.pose.origin[axis])>24000: close=false
	if close and actor.model_id not in [13,9996]:
		result.hull=clampf(float(actor.health.hull)/maxi(1,actor.health.max_hull)*100.0,0,100)
	return result

static func in_scan_window(point: Vector2, size: Vector2) -> bool:
	return point.x>size.x/3 and point.x<size.x*2/3 and absf(point.y-size.y/2)<size.x/6

static func edge_position(point: Vector2, size: Vector2, behind: bool, compact: bool=false) -> Vector2:
	var direction := edge_direction(point,size,behind)
	# Reserve the status area and keep the full label within the viewport.
	var bounds := Rect2(Vector2(20,160),Vector2(maxf(1,size.x-(40 if compact else 200)),maxf(1,size.y-315)))
	var center := size/2
	var scale := INF
	if direction.x>0: scale=minf(scale,(bounds.end.x-center.x)/direction.x)
	elif direction.x<0: scale=minf(scale,(bounds.position.x-center.x)/direction.x)
	if direction.y>0: scale=minf(scale,(bounds.end.y-center.y)/direction.y)
	elif direction.y<0: scale=minf(scale,(bounds.position.y-center.y)/direction.y)
	return center+direction*maxf(0,scale)

static func edge_direction(point: Vector2, size: Vector2, behind: bool) -> Vector2:
	var direction := point-size/2
	if behind: direction=-direction
	return Vector2.DOWN if direction.length_squared()<0.01 else direction

static func edge_symbol(point: Vector2, size: Vector2, behind: bool) -> String:
	var octant := posmod(roundi(edge_direction(point,size,behind).angle()/(PI/4)),8)
	return ["→","↘","↓","↙","←","↖","↑","↗"][octant]
