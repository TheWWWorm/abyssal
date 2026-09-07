extends RefCounted
## Newly authored surface design, adapted to locally imported geometry at runtime.
## Eye attachment samples a side ray; no source texture pixels are inspected.
const Library = preload("res://scripts/model_library.gd")
const FAMILIES := [
	[[4422],"405e69","c7d6cf"],[[4423],"3e969b","bacfc4"],
	[[4424,4425],"966653","d7baa0"],[[4426],"7d98b7","d2dce0"],
	[[4427,4428],"426476","b7cbca"],[[4429],"9d7854","d8cbb0"],
	[[4430,4431],"6d6576","b3aba4"],[[4432,4433],"536878","bec8c5"],
	[[4434,4435],"3d8b91","d2ddd2"],[[4436,4437],"a86456","d9b69b"],
	[[4438,4439],"66794e","c2bd91"],[[4440,4441],"536e7b","c9d4cc"],
	[[4442],"526b73","bccbc2"],[[4443],"a29145","d9bf65"],
	[[4444],"427d9c","72bfc4"],[[4445],"746449","ada07b"],
	[[4446],"8d4b50","cf7773"],[[4447],"438066","8bb982"]]
# Source-unit side-ray positions and independently chosen eye radii.
const EYES := {4422:[50,125,18],4424:[0,180,30],4427:[0,1800,65],4429:[0,220,22],4430:[-30,100,25],4432:[-20,600,24],4434:[0,280,12],4436:[0,100,20],4438:[0,600,18],4440:[-20,750,35],4442:[0,300,18]}
static func definition(id: int, source: Dictionary) -> Dictionary:
	var result := {}
	for family in FAMILIES:
		if id in family[0]: result={"dorsal":Color(family[1]),"ventral":Color(family[2])}; break
	if result.is_empty(): return result
	var low := INF; var high := -INF
	for i in range(1,source.vertices.size(),3):
		low=minf(low,-float(source.vertices[i])*0.01); high=maxf(high,-float(source.vertices[i])*0.01)
	result.low=low; result.high=maxf(low+0.01,high)
	result.eyes=[]
	if EYES.has(id):
		var choice: Array = EYES[id]
		var hits: Array[float] = []
		var origin := Vector3(100000,choice[0],choice[1]); var end := Vector3(-100000,choice[0],choice[1])
		for polygon in source.polygons:
			var points: Array[Vector3] = []
			for index in polygon.indices:
				points.append(Vector3(source.vertices[index*3],source.vertices[index*3+1],source.vertices[index*3+2]))
			var hit = Geometry3D.segment_intersects_triangle(origin,end,points[0],points[1],points[2])
			if hit!=null: hits.append(hit.x)
		if not hits.is_empty():
			for x in [hits.min(),hits.max()]: result.eyes.append(Vector4(float(x)*0.01,-choice[0]*0.01,-choice[1]*0.01,choice[2]*0.01))
	return result
