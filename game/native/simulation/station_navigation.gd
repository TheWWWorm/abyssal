extends RefCounted
## Visibility-graph approaches around the imported station module bounds.
const CLEARANCE := 2500

func approach(station, start: Array, finish: Array=[]) -> Array:
	if absi(start[1])>=14000: return []
	var obstacles: Array[Rect2] = []
	for shape in station.shapes:
		if absi(start[1]-(shape.origin[1]+shape.offset[1]))>=shape.half_size[1]+CLEARANCE: continue
		obstacles.append(Rect2(Vector2((shape.origin[0]+shape.offset[0])-shape.half_size[0]-CLEARANCE,(shape.origin[2]+shape.offset[2])-shape.half_size[2]-CLEARANCE),Vector2(2*(shape.half_size[0]+CLEARANCE),2*(shape.half_size[2]+CLEARANCE))))
	var origin := Vector2(start[0],start[2])
	if blocked(origin,obstacles): return []
	var points: Array[Vector2] = [origin]
	var goals: Dictionary = {}
	if not finish.is_empty():
		var point := Vector2(finish[0],finish[2])
		if not blocked(point,obstacles): goals[points.size()]=true; points.append(point)
	else:
		for x in [-14000,-7000,0,7000,14000]:
			for z in [-14000,-7000,0,7000,14000]:
				var point := Vector2(x,z)
				if not blocked(point,obstacles) and station.can_dock([roundi(point.x),start[1],roundi(point.y)]):
					goals[points.size()]=true; points.append(point)
	for box in obstacles:
		for x in [box.position.x-1,box.end.x+1]:
			for z in [box.position.y-1,box.end.y+1]:
				var point := Vector2(x,z)
				if not blocked(point,obstacles): points.append(point)
	var costs := {0:0.0}; var parents := {}; var open := {0:true}
	while not open.is_empty():
		var current: int = open.keys()[0]
		for index in open:
			if costs[index]<costs[current]: current=index
		open.erase(current)
		if goals.has(current):
			var path: Array = []
			while current!=0:
				path.push_front([int(points[current].x),start[1],int(points[current].y)])
				current=parents[current]
			if not finish.is_empty() and not path.is_empty(): path[-1]=finish.duplicate()
			return path
		for next in range(1,points.size()):
			var cost: float = costs[current]+points[current].distance_to(points[next])
			if cost>=costs.get(next,INF) or not clear_segment(points[current],points[next],obstacles): continue
			costs[next]=cost; parents[next]=current; open[next]=true
	return []

func blocked(point: Vector2, obstacles: Array[Rect2]) -> bool:
	for box in obstacles:
		if box.has_point(point): return true
	return false

func clear_segment(a: Vector2, b: Vector2, obstacles: Array[Rect2]) -> bool:
	for box in obstacles:
		var low := 0.0; var high := 1.0
		for axis in 2:
			var delta := b[axis]-a[axis]
			if absf(delta)<0.001:
				if a[axis]<box.position[axis] or a[axis]>box.end[axis]: high=-1; break
			else:
				var first := (box.position[axis]-a[axis])/delta
				var last := (box.end[axis]-a[axis])/delta
				low=maxf(low,minf(first,last)); high=minf(high,maxf(first,last))
		if low<=high: return false
	return true

# Cruise obstacles use full world-space volumes. A two-bend vertical bypass
# keeps the ship above/below the whole station instead of threading its modules.
static func cruise_detour(start: Vector3, finish: Vector3, obstacles: Array, minimum_y: float, maximum_y: float) -> Array:
	var delta:=finish-start
	var horizontal:=Vector3(delta.x,0,delta.z).normalized()
	if horizontal.length_squared()<.5:return []
	var nearest: AABB
	var nearest_distance:=INF
	for box: AABB in obstacles:
		var hit=box.intersects_segment(start,finish)
		if hit!=null and start.distance_squared_to(hit)<nearest_distance:
			nearest=box;nearest_distance=start.distance_squared_to(hit)
	if nearest_distance==INF:return []
	var middle:=nearest.get_center()
	var radius: float=(nearest.size*.5).dot(horizontal.abs())+5000.0
	var along: float=(middle-start).dot(horizontal)
	var entry:=start+horizontal*maxf(0.0,along-radius)
	var leave:=start+horizontal*(along+radius)
	var best: Array=[];var best_length:=INF
	for height in [nearest.position.y-3500.0,nearest.end.y+3500.0]:
		if height<minimum_y or height>maximum_y:continue
		var a:=Vector3(entry.x,height,entry.z);var b:=Vector3(leave.x,height,leave.z)
		var clear:=true
		for box: AABB in obstacles:
			if box.intersects_segment(start,a)!=null or box.intersects_segment(a,b)!=null:clear=false;break
		var length:=start.distance_to(a)+a.distance_to(b)+b.distance_to(finish)
		if clear and length<best_length:best=[a,b];best_length=length
	return best
