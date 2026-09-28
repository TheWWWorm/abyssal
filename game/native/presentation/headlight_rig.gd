extends RefCounted
## Recover the headlights from the owner's original additive beam geometry.
## Hull width cannot identify their number, position or arrangement: some
## vessels have one light, and a pair can be vertical rather than side by side.
const Library=preload("res://scripts/model_library.gd")
const SURFACE_CLEARANCE := .02
const DEFAULT_TINT := Color(.72,.9,1.0)

static func display_tint(original: Color, blue: bool) -> Color:
	return DEFAULT_TINT if not blue and original.b>original.r and original.b>original.g else original

static func sample_tint(image: Image, region: Rect2, atlas_size: Vector2) -> Color:
	# A cone's apex uses the white centre of a glow sprite. Average its whole
	# UV footprint to recover the coloured halo, including compatible atlases
	# and higher-resolution replacements, instead of assigning hues by ship ID.
	var scale := Vector2(image.get_size())/atlas_size
	var low := Vector2i((region.position*scale).floor())
	var high := Vector2i(((region.end+Vector2.ONE)*scale).ceil())
	var step_x := maxi(1,ceili(float(high.x-low.x)/64.0))
	var step_y := maxi(1,ceili(float(high.y-low.y)/64.0))
	var rgb := Vector3.ZERO
	for y in range(maxi(0,low.y),mini(image.get_height(),high.y),step_y):
		for x in range(maxi(0,low.x),mini(image.get_width(),high.x),step_x):
			var pixel := image.get_pixel(x,y)
			rgb+=Vector3(pixel.r,pixel.g,pixel.b)*pixel.a
	var peak := maxf(rgb.x,maxf(rgb.y,rgb.z))
	return Color(rgb.x/peak,rgb.y/peak,rgb.z/peak) if peak>.0001 else DEFAULT_TINT

static func tint(regions: Dictionary, library, atlases: Array) -> Color:
	var rgb := Vector3.ZERO
	for index in regions:
		if index<0 or index>=atlases.size():continue
		var texture: Texture2D=library.texture(atlases[index])
		if texture==null:continue
		var color := sample_tint(texture.get_image(),regions[index],library.texture_size(atlases[index]))
		rgb+=Vector3(color.r,color.g,color.b)
	var peak := maxf(rgb.x,maxf(rgb.y,rgb.z))
	return Color(rgb.x/peak,rgb.y/peak,rgb.z/peak) if peak>.0001 else DEFAULT_TINT

static func posed_vertices(source: Dictionary, bones: Array) -> Array[Vector3]:
	var points: Array[Vector3]=[];var cursor := 0
	for bone in source.bones.size():
		var pose := Library.matrix(bones[bone])
		for vertex in int(source.bones[bone].vertices):
			points.append(pose*Library.point(source.vertices,cursor*3));cursor+=1
	return points

static func closest_on_triangle(point: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var normal := (b-a).cross(c-a)
	if normal.length_squared()>1e-10:
		var projected := point-normal*normal.dot(point-a)/normal.length_squared()
		if normal.dot((b-a).cross(projected-a))>=-.00001 and normal.dot((c-b).cross(projected-b))>=-.00001 and normal.dot((a-c).cross(projected-c))>=-.00001:
			return projected
	var best := a;var distance := INF
	for edge in [[a,b],[b,c],[c,a]]:
		var delta: Vector3=edge[1]-edge[0]
		var candidate: Vector3=edge[0]+delta*clampf((point-edge[0]).dot(delta)/maxf(delta.length_squared(),1e-10),0.0,1.0)
		if point.distance_squared_to(candidate)<distance:best=candidate;distance=point.distance_squared_to(candidate)
	return best

static func hull_surface(point: Vector3, points: Array[Vector3], polygons: Array) -> Vector3:
	var best := point;var distance := INF
	for polygon in polygons:
		if int(polygon.blend)!=0:continue
		for at in range(0,polygon.indices.size(),3):
			var candidate := closest_on_triangle(point,points[int(polygon.indices[at])],points[int(polygon.indices[at+1])],points[int(polygon.indices[at+2])])
			if point.distance_squared_to(candidate)<distance:best=candidate;distance=point.distance_squared_to(candidate)
	return best

static func is_lamp_panel(polygon: Dictionary) -> bool:
	# Some panels span glazing, a grille and adjoining plate in one UV face.
	# Nymphe uses both framed tiles; Ino uses the grille and plate. Proximity
	# to a source beam is still required, so an intake never becomes a lamp.
	if int(polygon.texture)!=0 or int(polygon.blend)!=0:return false
	var a: Array=polygon.attributes
	var left := INF
	for i in polygon.indices.size():
		if a[i*5]<47 or a[i*5]>75 or a[i*5+1]<96 or a[i*5+1]>127:return false
		left=minf(left,a[i*5])
	# A face using only the adjacent metal tile contains no lamp opening.
	return left<61

static func lens_faces(source: Dictionary, bones: Array, lamps: Array) -> Dictionary:
	# Cockpits and lamp covers reuse the same dark atlas tile. Classify whole
	# connected panes by their proximity to the original beam, not by UV alone.
	var glass=preload("res://native/presentation/cabin_windows.gd")
	var points := posed_vertices(source,bones)
	var panes: Array=[]
	for index in source.polygons.size():
		var polygon: Dictionary=source.polygons[index]
		if int(polygon.get("texture",-1))!=0:continue
		var glass_only: bool=glass.is_glass(polygon)
		var panel := not glass_only and is_lamp_panel(polygon)
		if not panel and not glass_only:continue
		var corners: Array=polygon.indices.map(func(vertex):return points[int(vertex)].snapped(Vector3.ONE*.001))
		panes.append({"faces":[index],"edges":corners,"panel":panel})
	var merged := true
	while merged:
		merged=false
		for a in panes.size():
			for b in range(panes.size()-1,a,-1):
				if panes[a].panel!=panes[b].panel:continue
				if panes[a].edges.filter(func(point):return panes[b].edges.has(point)).size()<2:continue
				panes[a].faces.append_array(panes[b].faces)
				for point in panes[b].edges:
					if not panes[a].edges.has(point):panes[a].edges.append(point)
				panes.remove_at(b);merged=true
	var result := {}
	for i in lamps.size():
		var best: Array=[];var distance := .45
		for pane in panes:
			for index in pane.faces:
				var ids: Array=source.polygons[index].indices
				for at in range(0,ids.size(),3):
					var point := closest_on_triangle(lamps[i].original_origin,points[int(ids[at])],points[int(ids[at+1])],points[int(ids[at+2])])
					var gap: float=lamps[i].original_origin.distance_to(point)
					if gap<distance:distance=gap;best=pane.faces
		for index in best:result[index]=i+1
	return result

static func aperture_centre(source: Dictionary, points: Array[Vector3], faces: Array, origin: Vector3) -> Dictionary:
	# A source beam can begin at a panel's edge. Map the centre of its visible
	# opening through the same UV triangles as the hull, including mirrored
	# and sloping panels. Prefer the clear lens when glass and grille share a
	# face; a grille-only work lamp uses the second tile instead.
	for centre in [Vector2(54.5,103.5),Vector2(54.5,119.5)]:
		var best := {};var distance := INF
		for index in faces:
			var polygon: Dictionary=source.polygons[index]
			var attributes: Array=polygon.attributes
			for at in range(0,polygon.indices.size(),3):
				var uv: Array[Vector2]=[]
				for j in 3:uv.append(Vector2(attributes[(at+j)*5],attributes[(at+j)*5+1]))
				var a := uv[1]-uv[0];var b := uv[2]-uv[0];var target: Vector2=centre-uv[0]
				var determinant := a.cross(b)
				if absf(determinant)<.000001:continue
				var v := target.cross(b)/determinant;var w := a.cross(target)/determinant;var u := 1.0-v-w
				if minf(u,minf(v,w))<-.00001:continue
				var point: Vector3=points[int(polygon.indices[at])]*u+points[int(polygon.indices[at+1])]*v+points[int(polygon.indices[at+2])]*w
				var gap := point.distance_squared_to(origin)
				if gap<distance:distance=gap;best={"point":point}
		if not best.is_empty():return best
	return {}

static func describe(source: Dictionary, bones: Array) -> Array:
	var points := posed_vertices(source,bones)
	var cones := {}
	for polygon_index in source.polygons.size():
		var polygon: Dictionary=source.polygons[polygon_index]
		if int(polygon.blend)!=4 or polygon.indices.size()!=3:continue
		for raw in polygon.indices:
			var vertex := int(raw)
			var others: Array=polygon.indices.filter(func(index):return int(index)!=vertex)
			# A beam opens forward (-Z) from a shared rear apex. Exhaust and
			# lamp sprites do not form this fan of long, forward-facing sides.
			if not others.all(func(index):return points[vertex].z>points[int(index)].z+1.0):continue
			if not cones.has(vertex):cones[vertex]={"faces":0,"ends":{},"texture_regions":{},"polygons":[]}
			cones[vertex].faces+=1
			cones[vertex].polygons.append(polygon_index)
			for index in others:cones[vertex].ends[int(index)]=true
			var attributes: Array=polygon.get("attributes",[])
			for i in attributes.size()/5:
				var uv := Vector2(attributes[i*5],attributes[i*5+1])
				var texture: int=polygon.texture
				var regions: Dictionary=cones[vertex].texture_regions
				regions[texture]=regions[texture].expand(uv) if regions.has(texture) else Rect2(uv,Vector2.ZERO)
	var result: Array=[]
	for vertex in cones:
		if cones[vertex].faces<4:continue
		var end_z := INF
		for index in cones[vertex].ends:end_z=minf(end_z,points[index].z)
		var end := Vector3.ZERO;var count := 0
		for index in cones[vertex].ends:
			if points[index].z<=end_z+.01:end+=points[index];count+=1
		if count==0:continue
		var origin: Vector3=points[vertex]
		var direction := (end/count-origin).normalized()
		# Original low-resolution cones can begin a little outside or inside
		# their housing. Attach to the nearest actual triangle, never to a
		# guessed bounding-box front or a neighbouring vertex's depth.
		var surface := hull_surface(origin,points,source.polygons)
		result.append({"original_origin":origin,"surface":surface,"direction":direction,"texture_regions":cones[vertex].texture_regions,"polygons":cones[vertex].polygons,
			"frame":Transform3D(Basis.looking_at(direction,Vector3.UP),surface+direction*SURFACE_CLEARANCE)})
	result.sort_custom(func(a,b):return a.original_origin.y>b.original_origin.y if is_equal_approx(a.original_origin.x,b.original_origin.x) else a.original_origin.x<b.original_origin.x)
	var lenses := lens_faces(source,bones,result)
	for i in result.size():
		var faces: Array=lenses.keys().filter(func(index):return lenses[index]==i+1)
		var aperture := aperture_centre(source,points,faces,result[i].original_origin)
		if aperture.is_empty():continue
		result[i].surface=aperture.point
		result[i].frame.origin=aperture.point+result[i].direction*SURFACE_CLEARANCE
	return result
