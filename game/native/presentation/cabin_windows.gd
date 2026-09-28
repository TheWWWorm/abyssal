extends RefCounted
## Cabin spill follows the imported glass faces and their animated bone.
## The neighbouring grille, hull paint and faction symbols are not windows.
static func is_glass(polygon: Dictionary, slack: float=0.0) -> bool:
	"""Mapped inside the pane's tile; slack admits faces drawn a texel over it."""
	if int(polygon.texture)!=0 or int(polygon.blend)!=0:return false
	for j in polygon.indices.size():
		var u := float(polygon.attributes[j*5]);var v := float(polygon.attributes[j*5+1])
		if u<48-slack or u>61+slack or v<97-slack or v>110+slack:return false
	return true

## The pane is the black inside of a metal frame: frame u 48-61, v 97-110,
## glass u 50-59, v 99-108. Some hulls also spread a slice of that black over
## large panels as dark paint (the Triops' fins and belly, the Titan's flanks).
## A window shows its frame and the middle of the glass on both axes, is no
## larger than a cockpit pane and is not drawn out along one edge; a quarter
## pane still meets the middle at its corner. A sliver along the frame or a
## stretched slice of black lit as a cabin reads as an amber stripe or panel.
const LARGEST_PANE := 3.0
## Hull units per texel along any edge; real panes stay under 0.45.
const LONGEST_STRETCH := 0.5
static func is_pane(source: Dictionary, polygon: Dictionary) -> bool:
	if not is_glass(polygon):return false
	var low := Vector2(INF,INF);var high := -low
	for j in polygon.indices.size():
		var uv := Vector2(float(polygon.attributes[j*5]),float(polygon.attributes[j*5+1]))
		low=low.min(uv);high=high.max(uv)
	if not ((low.x<=49.5 or high.x>=59.5) and (low.y<=98.5 or high.y>=108.5)):return false
	if low.x>55.5 or high.x<53.5 or low.y>104.5 or high.y<102.5:return false
	var library=load("res://scripts/model_library.gd")
	var area := 0.0
	for triangle in range(0,polygon.indices.size()-2,3):
		var a: Vector3=library.point(source.vertices,int(polygon.indices[triangle])*3)
		var b: Vector3=library.point(source.vertices,int(polygon.indices[triangle+1])*3)
		var c: Vector3=library.point(source.vertices,int(polygon.indices[triangle+2])*3)
		area+=(b-a).cross(c-a).length()*.5
		for edge in [[0,1],[1,2],[2,0]]:
			var first: int=triangle+edge[0];var second: int=triangle+edge[1]
			var span: float=(library.point(source.vertices,int(polygon.indices[first])*3)-library.point(source.vertices,int(polygon.indices[second])*3)).length()
			var texels: float=Vector2(float(polygon.attributes[first*5])-float(polygon.attributes[second*5]),float(polygon.attributes[first*5+1])-float(polygon.attributes[second*5+1])).length()
			if span/maxf(texels,1.0)>LONGEST_STRETCH:return false
	return area<=LARGEST_PANE

## The cabins breathe: the glass and the light it spills on the hull rise and
## fall together, slowly and a little unevenly, each window on its own phase.
## The glass follows ocean_visual_time in model_library's shader and the
## lamps follow clock, which abyss.gd keeps equal to it; both take the phase
## from the window's place on the undeformed model.
const PHASE := Vector3(.35,.25,.3)
const ENERGY := .6
static var clock := 0.0
static func pulse(seconds: float, at: Vector3) -> float:
	var phase := at.dot(PHASE)
	return .7+.3*(.65*sin(seconds*.9+phase)+.35*sin(seconds*2.1+phase*1.6))

## A pane on the stern faces aft, where no cabin can be. Those are tail
## lamps: red and steady, as on a car, lighting the hull around them a little.
## "Aft" is judged on the posed hull, +z astern.
const TAIL_TINT := Color(1.0,.1,.06)
## What a stern pane shows: a tail lamp, plain hull, or an engine's glow.
const STERN_LAMP := 1
const STERN_ENGINE := 2
const STERN_PAINT := 3
const TAIL_ENERGY := .8
static func tail_faces(source: Dictionary, bones: Array) -> Dictionary:
	var library=load("res://scripts/model_library.gd")
	var bone_for_vertex: Array[int]=[]
	for i in source.bones.size():
		for j in int(source.bones[i].vertices):bone_for_vertex.append(i)
	var faces := {}
	for polygon_index in source.polygons.size():
		var polygon: Dictionary=source.polygons[polygon_index]
		if not is_pane(source,polygon):continue
		var normal := Vector3.ZERO
		for index in polygon.indices:
			var i := int(index)
			if i*3+2<source.normals.size():normal+=library.matrix(bones[bone_for_vertex[i]]).basis*library.point(source.normals,i*3)
		if normal.normalized().z>.5:faces[polygon_index]=true
	return faces

static func lamps(source: Dictionary, pattern: int, lenses: Dictionary={}, tails: Dictionary={}) -> Array:
	"""One amber lamp per cabin (per bone), up to two."""
	var result: Array=[]
	for cabin in clusters(source,pattern,func(index):return not lenses.has(index) and not tails.has(index) and is_pane(source,source.polygons[index]),false):
		# Move just outside the glazing's envelope, not into the cabin where
		# the hull would occlude the entire light. Shadowing stops the spill
		# reaching the far side of the vessel or a wall behind the cockpit.
		result.append({"centre":cabin.outside,"window":cabin.centre,"bone":cabin.bone,"radius":1.0,
			"tint":Color(1.0,.75,.5),"halo":false,"shadow":true,"energy":ENERGY,"specular":0.0,
			"range":clampf(sqrt(cabin.area)*1.2,3.5,5.0),"fade_begin":35.0,"fade_length":25.0,
			"shadow_normal_bias":.08,"fog_energy":0.0})
		if result.size()==2:break
	return result

static func tail_lamps(source: Dictionary, pattern: int, tails: Dictionary) -> Array:
	"""One red lamp per group of tail panes, each side apart, up to two. They
	cast no shadow: an extra shadowed light is another pass on phones."""
	var result: Array=[]
	if tails.is_empty():return result
	for cluster in clusters(source,pattern,func(index):return int(tails.get(index,0))==STERN_LAMP,true):
		result.append({"centre":cluster.outside,"bone":cluster.bone,"radius":1.0,"tint":TAIL_TINT,
			"halo":false,"shadow":false,"energy":TAIL_ENERGY,"specular":0.0,"tail":true,
			"range":clampf(sqrt(cluster.area)*1.5,3.5,6.0),"fade_begin":60.0,"fade_length":40.0,"fog_energy":0.0})
		if result.size()==2:break
	return result

static func clusters(source: Dictionary, pattern: int, accept: Callable, sides: bool) -> Array:
	"""Accepted faces gathered by bone (and by side of the centre line when asked):
	area-weighted centre, the point just outside the glass, and the area."""
	var library=load("res://scripts/model_library.gd")
	var bones: Array[int]=[]
	for i in source.bones.size():
		for j in int(source.bones[i].vertices):bones.append(i)
	var groups := {}
	for polygon_index in source.polygons.size():
		if not accept.call(polygon_index):continue
		var polygon: Dictionary=source.polygons[polygon_index]
		if int(polygon.pattern)!=0 and (int(polygon.pattern)&pattern)==0:continue
		var bone := bones[int(polygon.indices[0])]
		for triangle in range(0,polygon.indices.size(),3):
			var a: Vector3=library.point(source.vertices,int(polygon.indices[triangle])*3)
			var b: Vector3=library.point(source.vertices,int(polygon.indices[triangle+1])*3)
			var c: Vector3=library.point(source.vertices,int(polygon.indices[triangle+2])*3)
			var area := (b-a).cross(c-a).length()*.5
			if area<.0001:continue
			var key: Variant=[bone,signf(roundf((a.x+b.x+c.x)/3.0))] if sides else bone
			if not groups.has(key):groups[key]={"bone":bone,"centre":Vector3.ZERO,"normal":Vector3.ZERO,"area":0.0,"bounds":AABB(a,Vector3.ZERO)}
			var group: Dictionary=groups[key]
			group.centre+=(a+b+c)*(area/3.0);group.area+=area
			group.bounds=group.bounds.expand(b).expand(c).expand(a)
			for j in range(triangle,triangle+3):
				var index := int(polygon.indices[j])*3
				if index+2<source.normals.size():group.normal+=library.point(source.normals,index).normalized()*(area/3.0)
	var result: Array=[]
	for key in groups:
		var group: Dictionary=groups[key]
		var normal: Vector3=group.normal.normalized()
		group.centre=group.centre/group.area
		group.outside=group.centre+normal*(group.bounds.size.dot(normal.abs())*.5+.25)
		result.append(group)
	return result
