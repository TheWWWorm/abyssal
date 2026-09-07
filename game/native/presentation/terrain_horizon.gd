extends RefCounted
## Coarse seabed beyond the detailed tiles. Boundary edges share their exact
## 20 m samples, so the two resolutions meet without skirts or overlapping faces.
const TILE := 360
const DETAIL_GRID := 18
const NEAR_RADIUS := 2
var geography
var anchor := Vector3.ZERO
var center := Vector2i.ZERO
var radius := 14
var cursor := 0
var vertices := PackedVector3Array()
var normals := PackedVector3Array()
var uv := PackedVector2Array()
var indices := PackedInt32Array()
var samples := {}
func configure(source, origin: Vector3, cell: Vector2i, distance: float) -> void:
	geography=source; anchor=origin; center=cell
	# Leave room for the camera to travel while the next horizon is built.
	radius=ceili(distance/TILE)+4
func finished() -> bool:
	return cursor>=(radius*2+1)*(radius*2+1)
func advance(max_cells: int=32) -> void:
	var width := radius*2+1
	for _i in max_cells:
		if finished(): return
		var key := center+Vector2i(cursor%width-radius,cursor/width-radius)
		cursor+=1
		if near(key): continue
		build_cell(key)
func near(key: Vector2i) -> bool:
	return absi(key.x-center.x)<=NEAR_RADIUS and absi(key.y-center.y)<=NEAR_RADIUS
func height(point: Vector2) -> float:
	if not samples.has(point): samples[point]=geography.height(point.x,point.y)
	return samples[point]
func vertex(point: Vector2) -> int:
	var index := vertices.size()
	vertices.append(Vector3(point.x,height(point),point.y)-anchor)
	var relative := (point-(Vector2(center)+Vector2(0.5,0.5))*TILE).abs()
	var outside := maxf(relative.x,relative.y)-(NEAR_RADIUS+0.5)*TILE
	var sample_step := clampf(20+outside*0.2,20,180)
	var dx := height(point+Vector2(sample_step,0))-height(point-Vector2(sample_step,0))
	var dz := height(point+Vector2(0,sample_step))-height(point-Vector2(0,sample_step))
	normals.append(Vector3(-dx,sample_step*2,-dz).normalized()); uv.append(point*0.03)
	return index
func build_cell(key: Vector2i) -> void:
	var corners := [Vector2(key.x,key.y),Vector2(key.x+1,key.y),Vector2(key.x+1,key.y+1),Vector2(key.x,key.y+1)]
	var neighbors := [Vector2i(0,-1),Vector2i(1,0),Vector2i(0,1),Vector2i(-1,0)]
	var middle := vertex((Vector2(key)+Vector2(0.5,0.5))*TILE)
	var border := PackedInt32Array()
	for edge in 4:
		var segments := DETAIL_GRID if near(key+neighbors[edge]) else 1
		for step in segments:
			# Calculate integer metre offsets before adding the world origin;
			# interpolating large cell coordinates first loses seam precision.
			var direction: Vector2 = corners[(edge+1)%4]-corners[edge]
			border.append(vertex(corners[edge]*TILE+direction*(step*TILE/segments)))
	for i in border.size(): indices.append_array(PackedInt32Array([middle,border[i],border[(i+1)%border.size()]]))
func mesh(material: Material) -> ArrayMesh:
	var arrays := []; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices; arrays[Mesh.ARRAY_NORMAL]=normals; arrays[Mesh.ARRAY_TEX_UV]=uv; arrays[Mesh.ARRAY_INDEX]=indices
	var result := ArrayMesh.new(); result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays); result.surface_set_material(0,material)
	return result
