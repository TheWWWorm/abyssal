extends RefCounted
## Ordered waypoints with a spherical arrival radius.
var points: Array = []
var reached: Array = []
var index := 0
var loop := false
var previous_position = null

func configure(coordinates: Array, repeating: bool = false) -> void:
	points=[]; index=0; loop=repeating; previous_position=null
	for i in range(0,coordinates.size(),3): points.append(coordinates.slice(i,i+3))
	reached.resize(points.size()); reached.fill(false)

func current():
	return points[index] if index < points.size() else null

func advance(position: Array) -> void:
	var finish := Vector3(position[0],position[1],position[2])
	var start: Vector3 = finish if previous_position==null else previous_position
	previous_position=finish
	var motion := finish-start
	var length_squared := motion.length_squared()
	var passed := 0.0
	# Sweep the travelled segment: boost or time acceleration must not jump
	# over a small arrival volume between simulation ticks.
	for _step in points.size():
		if index>=points.size():return
		var point: Array=points[index]
		var target := Vector3(point[0],point[1],point[2])
		var fraction := clampf((target-start).dot(motion)/length_squared,0,1) if length_squared>0 else 0.0
		if fraction<passed or target.distance_to(start+motion*fraction)>2200:return
		reached[index]=true;index+=1;passed=fraction
		if loop and index>=points.size():
			index=0;reached.fill(false);return

func complete() -> bool:
	return not reached.is_empty() and reached[-1]
