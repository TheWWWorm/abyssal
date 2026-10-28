extends RefCounted
## The phone's modules overlap: bridges eighty metres long chained at a
## sixty-three metre step, habitats sixty-nine metres tall stacked at
## forty-five, a cap lying in the wall it meets. Its painter's order never
## minded; a depth buffer sees the same plane twice and fights over it.
## Each module is drawn a fraction smaller about its own origin. A fixed
## step left some planes together: two copies of one module at the same
## height take the same step whenever their places in the layout do, and
## a face near both origins barely moves. So the fraction is chosen module
## by module, in layout order, to stand every face clear of the coplanar
## faces already placed that it overlaps; where no fraction can, the module
## also moves a few centimetres along an axis.
const Library = preload("res://scripts/model_library.gd")
## Clear of a 24-bit depth buffer's step a few hundred metres out.
const CLEARANCE := 0.02
## The usual steps first; at most one per cent, a few tens of centimetres
## at the end of the longest module, which its overlap hides.
const TRIMS := [0.998,0.996,0.994,0.997,0.995,0.993,0.999,0.992,0.991,0.99]
## Moves tried in turn, nearest first. Every face plane is at least 0.58
## across one of the axes.
const SHIFTS := [
	Vector3.ZERO,Vector3(0,0.015,0),Vector3(0,-0.015,0),Vector3(0.015,0,0),Vector3(-0.015,0,0),
	Vector3(0,0,0.015),Vector3(0,0,-0.015),Vector3(0,0.03,0),Vector3(0,-0.03,0),Vector3(0.03,0,0),
	Vector3(-0.03,0,0),Vector3(0,0,0.03),Vector3(0,0,-0.03),Vector3(0,0.045,0),Vector3(0,-0.045,0),
	Vector3(0.045,0,0),Vector3(-0.045,0,0),Vector3(0,0,0.045),Vector3(0,0,-0.045),Vector3(0,0.06,0),
	Vector3(0,-0.06,0),Vector3(0.06,0,0),Vector3(-0.06,0,0),Vector3(0,0,0.06),Vector3(0,0,-0.06)]
## The longest move.
const REACH := 0.06
## Cells per unit across a plane direction. Faces this side of parallel,
## at most 1.8 degrees apart, differ by under a third of a cell.
const CELLS := 10.0
## Placed faces by plane direction and metre of plane offset, both read
## for one way of facing: [normal, plane offset, bounds].
var placed := {}
var count := 0
## The smallest gap each module was left with to a face it overlaps; INF
## when it overlaps none.
var gaps: Array[float] = []
## Each module's trim and move.
var trims: Array[float] = []
var shifts: Array[Vector3] = []

static func default_trim(index: int) -> float:
	return 1.0-0.002*(1+(index%3))

static func model_faces(source: Dictionary) -> Array:
	"""The solid triangles of a module in its own frame, at rest: each one's
	normal, a corner and its bounds. Every configuration pattern is
	included, since a module may change pattern. Kept with the source, so a
	different content cache never reads another's faces."""
	if source.has("separation_faces"):return source.separation_faces
	var transforms: Array[Transform3D]=[];var owner:=PackedInt32Array()
	for bone in source.bones:
		var pose:=Library.matrix(bone.matrix)
		if int(bone.parent)>=0:pose=transforms[int(bone.parent)]*pose
		transforms.append(pose)
		for i in int(bone.vertices):owner.append(transforms.size()-1)
	var faces: Array=[]
	for polygon in source.polygons:
		if int(polygon.blend)!=0:continue
		var ids: Array=polygon.indices
		for t in range(0,ids.size()-2,3):
			var corners: Array[Vector3]=[]
			for j in 3:corners.append(transforms[owner[int(ids[t+j])]]*Library.point(source.vertices,int(ids[t+j])*3))
			var normal:=(corners[1]-corners[0]).cross(corners[2]-corners[0])
			if normal.length()<1e-6:continue
			faces.append([normal.normalized(),corners[0],AABB(corners[0],Vector3.ZERO).expand(corners[1]).expand(corners[2])])
	source["separation_faces"]=faces
	return faces

static func way(cell: Vector3i) -> int:
	"""-1 for a direction cell read the other way along its planes."""
	return -1 if cell.x<0 or (cell.x==0 and (cell.y<0 or (cell.y==0 and cell.z<0))) else 1

static func cells_near(normal: Vector3) -> Array[Vector3i]:
	"""The direction cells a face parallel to this one may fall in."""
	var spans: Array=[]
	for axis in 3:
		var across: float=normal[axis]*CELLS
		spans.append(range(roundi(across-.33),roundi(across+.33)+1))
	var cells: Array[Vector3i]=[]
	for x in spans[0]:
		for y in spans[1]:
			for z in spans[2]:cells.append(Vector3i(x,y,z))
	return cells

func place(source: Dictionary, placement: Transform3D) -> Transform3D:
	"""Where the next module of the layout is drawn, given where it stands;
	its faces are kept for the modules after it."""
	var faces:=model_faces(source)
	var low: float=TRIMS.min();var reach: float=CLEARANCE+REACH
	# The layout's fixed-point turns leave the basis a hair from orthonormal.
	var to_normal:=placement.basis.inverse().transposed()
	var near: Array=[]
	var drawn: Array=[]
	for face in faces:
		var normal: Vector3=(to_normal*face[0]).normalized()
		var base:=normal.dot(placement.origin);var height:=normal.dot(placement.basis*face[1])
		var bounds: AABB=placement*face[2]
		drawn.append([normal,base,height,bounds])
		var lowest:=base+minf(height,low*height)-reach;var highest:=base+maxf(height,low*height)+reach
		# Trimmed and moved, the face may travel this far, across its plane or along it.
		var nearby: AABB=bounds.grow(.05+reach+(1.0-low)*((bounds.get_center()-placement.origin).length()+bounds.size.length()*.5))
		for cell in cells_near(normal):
			var side:=way(cell)
			var key:=cell*side;var first:=floori(minf(lowest*side,highest*side));var last:=floori(maxf(lowest*side,highest*side))
			for metre in range(first,last+1):
				for other in placed.get(Vector4i(key.x,key.y,key.z,metre),[]):
					var along: float=normal.dot(other[0])
					if absf(along)<.9995:continue
					var plane: float=signf(along)*other[1]
					if plane<lowest or plane>highest or not nearby.intersects(other[2]):continue
					near.append([base,height,plane,normal])
	var choice:=default_trim(count);var offset:=Vector3.ZERO;var gap:=-1.0
	for step in SHIFTS:
		for candidate in [default_trim(count)]+TRIMS:
			var clear:=INF
			for pair in near:clear=minf(clear,absf(pair[0]+candidate*pair[1]+step.dot(pair[3])-pair[2]))
			if clear>gap:gap=clear;choice=candidate;offset=step
			if clear>=CLEARANCE:break
		if gap>=CLEARANCE:break
	var origin: Vector3=placement.origin
	for face in drawn:
		var normal: Vector3=face[0]
		var plane: float=face[1]+choice*face[2]+normal.dot(offset)
		var cell:=Vector3i(roundi(normal.x*CELLS),roundi(normal.y*CELLS),roundi(normal.z*CELLS));var side:=way(cell)
		var key:=Vector4i(cell.x*side,cell.y*side,cell.z*side,floori(plane*side))
		if not placed.has(key):placed[key]=[]
		var bounds: AABB=face[3]
		placed[key].append([normal,plane,AABB(origin+offset+(bounds.position-origin)*choice,bounds.size*choice)])
	gaps.append(gap);trims.append(choice);shifts.append(offset);count+=1
	return placement.scaled_local(Vector3.ONE*choice).translated(offset)
