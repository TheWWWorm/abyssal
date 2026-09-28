extends RefCounted
## Cabin spill follows the imported glass faces and their animated bone.
## The neighbouring grille, hull paint and faction symbols are not windows.
static func is_glass(polygon: Dictionary) -> bool:
	if int(polygon.texture)!=0 or int(polygon.blend)!=0:return false
	for j in polygon.indices.size():
		var u := float(polygon.attributes[j*5]);var v := float(polygon.attributes[j*5+1])
		if u<48 or u>61 or v<97 or v>110:return false
	return true

static func lamps(source: Dictionary, pattern: int, lenses: Dictionary={}) -> Array:
	var library=load("res://scripts/model_library.gd")
	var bones: Array[int]=[]
	for i in source.bones.size():
		for j in int(source.bones[i].vertices):bones.append(i)
	var cabins := {}
	for polygon_index in source.polygons.size():
		if lenses.has(polygon_index):continue
		var polygon: Dictionary=source.polygons[polygon_index]
		if not is_glass(polygon):continue
		if int(polygon.pattern)!=0 and (int(polygon.pattern)&pattern)==0:continue
		var bone := bones[int(polygon.indices[0])]
		for triangle in range(0,polygon.indices.size(),3):
			var a: Vector3=library.point(source.vertices,int(polygon.indices[triangle])*3)
			var b: Vector3=library.point(source.vertices,int(polygon.indices[triangle+1])*3)
			var c: Vector3=library.point(source.vertices,int(polygon.indices[triangle+2])*3)
			var area := (b-a).cross(c-a).length()*.5
			if area<.0001:continue
			if not cabins.has(bone):cabins[bone]={"centre":Vector3.ZERO,"normal":Vector3.ZERO,"area":0.0,"bounds":AABB(a,Vector3.ZERO)}
			var cabin: Dictionary=cabins[bone]
			cabin.centre+=(a+b+c)*(area/3.0);cabin.area+=area
			cabin.bounds=cabin.bounds.expand(b).expand(c).expand(a)
			for j in range(triangle,triangle+3):
				var index := int(polygon.indices[j])*3
				if index+2<source.normals.size():cabin.normal+=library.point(source.normals,index).normalized()*(area/3.0)
	var result: Array=[]
	for bone in cabins:
		var cabin: Dictionary=cabins[bone]
		var normal: Vector3=cabin.normal.normalized()
		var size: Vector3=cabin.bounds.size
		# Move just outside the glazing's envelope, not into the cabin where
		# the hull would occlude the entire light. Shadowing stops the spill
		# reaching the far side of the vessel or a wall behind the cockpit.
		var centre: Vector3=cabin.centre/cabin.area
		var reach := size.dot(normal.abs())*.5+.25
		result.append({"centre":centre+normal*reach,"bone":bone,"radius":1.0,
			"tint":Color(1.0,.75,.5),"halo":false,"shadow":true,"energy":.015,
			"range":clampf(sqrt(cabin.area)*.5,2.0,3.0),"fade_begin":35.0,"fade_length":25.0,
			"shadow_normal_bias":.08,"fog_energy":0.0})
		if result.size()==2:break
	return result
