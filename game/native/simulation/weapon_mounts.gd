extends RefCounted
## Launch points follow the imported solid hull, excluding headlight cones.
## Derived at cache load so firing has the same geometry without a renderer.
const CLEARANCE := 35.0

static func read(directory: String, registry: Array) -> Dictionary:
	var result := {}
	for entry in registry:
		var id := int(entry.id)
		if not (id<=19 or (id>=6754 and id<=6767)):continue
		var path := directory.path_join(str(entry.model)+".json")
		if not FileAccess.file_exists(path):continue
		var mesh = JSON.parse_string(FileAccess.get_file_as_string(path))
		if mesh is not Dictionary:continue
		var box := source_bounds(mesh,id<=11)
		result[str(id)]={"low":[box.position.x,box.position.y,box.position.z],"high":[box.end.x,box.end.y,box.end.z]}
	return result

static func source_bounds(mesh: Dictionary, opaque_only: bool) -> AABB:
	var used := {}
	for polygon in mesh.polygons:
		if opaque_only and int(polygon.blend)!=0:continue
		for index in polygon.indices:used[int(index)]=true
	var transforms: Array[Transform3D]=[]
	var cursor := 0
	var first := true
	var box := AABB()
	for bone in mesh.bones:
		var m: Array=bone.matrix
		var local := Transform3D(Basis(Vector3(m[0],m[4],m[8]),Vector3(m[1],m[5],m[9]),Vector3(m[2],m[6],m[10])),Vector3(m[3],m[7],m[11]))
		var transform: Transform3D=transforms[int(bone.parent)]*local if int(bone.parent)>=0 else local
		transforms.append(transform)
		for _vertex in int(bone.vertices):
			var at := cursor*3
			if used.has(cursor):
				var point := transform*Vector3(mesh.vertices[at],mesh.vertices[at+1],mesh.vertices[at+2])
				if first:box=AABB(point,Vector3.ZERO);first=false
				else:box=box.expand(point)
			cursor+=1
	return box

static func muzzle(data: Dictionary, hull: int, slot: int=0, count: int=1) -> Array:
	var box: Dictionary=data.get("weapon_geometry",{}).get(str(hull),{})
	# Data-only fixtures without decoded meshes still have a forward launcher.
	var low: Array=box.get("low",[-600,-300,-1200])
	var high: Array=box.get("high",[600,300,2400])
	var spacing := minf(700.0,(float(high[0])-float(low[0]))*.65/maxi(1,count-1))
	var x := (slot-(count-1)*.5)*spacing
	return [roundi(x),roundi(clampf(0.0,float(low[1]),float(high[1]))),ceili(float(high[2])+CLEARANCE)]

static func rear_clearance(data: Dictionary, weapon) -> float:
	if weapon.fishing:return 200.0 # The hook tip leads its two-metre shaft.
	if weapon.beam:return 0.0 # The travelling line grows from the muzzle.
	var box: Dictionary=data.get("weapon_geometry",{}).get(str(weapon.model_id),{})
	var low: Array=box.get("low",[0,0,0]);var high: Array=box.get("high",[0,0,0])
	var radius := Vector2(maxf(absf(low[0]),absf(high[0])),maxf(absf(low[1]),absf(high[1]))).length()
	# A converged shot can leave up to twenty degrees off the hull's heading.
	return (maxf(0,-float(low[2]))+radius*.342)*(2.0 if weapon.homing else 1.0)

static func fit(weapon, data: Dictionary, hull: int, slot: int=0, count: int=1) -> void:
	weapon.muzzle=muzzle(data,hull,slot,count)
	weapon.mount=weapon.muzzle.duplicate();weapon.mount[2]+=ceili(rear_clearance(data,weapon))

static func for_actor(weapon, data: Dictionary, hull: int) -> Array:
	var result := muzzle(data,hull)
	result[2]+=ceili(rear_clearance(data,weapon))
	return result
