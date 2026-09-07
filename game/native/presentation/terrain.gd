extends Node3D
const TILE := 360
const GRID := 18
const Horizon = preload("res://native/presentation/terrain_horizon.gd")
var world
var camera: Camera3D
var tiles: Dictionary = {}
var pending: Array = []
var material := ShaderMaterial.new()
var world_anchor := Vector3.ZERO
var revision := -1
var prop_scene: PackedScene
var prop_scenes := {}
var horizon: MeshInstance3D
var horizon_job
var active_center := Vector2i.ZERO
var target_center := Vector2i.ZERO
var has_active := false
var has_target := false
var target_distance := 0.0
func apply_pack(_pack) -> void:
	material.set_shader_parameter("sediment_enabled",false)
func _ready() -> void:
	material.shader=preload("res://native/presentation/terrain.gdshader")
func _process(_delta: float) -> void:
	if world==null or world.region==null: return
	visible=world.geography.seafloor_enabled
	if not visible: return
	if revision!=world.revision:
		if has_active:
			# Terrain is fixed in ocean coordinates. Rebase the existing complete
			# surface instead of exposing an empty seabed during a region entry.
			var shift: Vector3 = world_anchor-world.geography.anchor
			for tile in tiles.values(): tile.position+=shift
			horizon.position+=shift
		else:
			for tile in tiles.values(): tile.queue_free()
			tiles={}
		pending=[]; revision=world.revision
		horizon_job=null; has_target=false
		world_anchor=world.geography.anchor
	var eye: Vector3 = camera.global_position+world_anchor
	var center := Vector2i(floori(eye.x/TILE),floori(eye.z/TILE))
	# Finish nearby work even if accelerated flight crosses another cell; do
	# not perpetually restart a horizon that the camera is moving through.
	if not has_target or horizon_distance()>target_distance+1 or center!=target_center and (horizon_job==null or (center-target_center).length_squared()>9): begin_stream(center)
	# Keep the previous complete surface until both resolutions for the new
	# center are ready. One detailed tile or a bounded coarse batch per frame.
	if not pending.is_empty(): build(pending.pop_front())
	elif horizon_job!=null:
		horizon_job.advance()
		if horizon_job.finished(): commit_stream()
func near(key: Vector2i, center: Vector2i) -> bool:
	return absi(key.x-center.x)<=2 and absi(key.y-center.y)<=2
func horizon_distance() -> float:
	# The far plane's corners extend farther than camera.far, especially on
	# widescreen displays. Cover their radius at the maximum boost FOV.
	var viewport: Vector2 = camera.get_viewport().get_visible_rect().size
	var aspect: float = viewport.x/maxf(1,viewport.y)
	var tangent := tan(deg_to_rad(maxf(70,camera.fov)*0.5))
	return camera.far*sqrt(1+tangent*tangent*(1+aspect*aspect))
func begin_stream(center: Vector2i) -> void:
	target_center=center; has_target=true; pending=[]
	for key in tiles.keys():
		if not near(key,center) and (not has_active or not near(key,active_center)):
			tiles[key].queue_free(); tiles.erase(key)
	for x in range(center.x-2,center.x+3):
		for z in range(center.y-2,center.y+3):
			var key := Vector2i(x,z)
			if not tiles.has(key): pending.append(key)
	pending.sort_custom(func(a,b): return (a-center).length_squared()<(b-center).length_squared())
	target_distance=horizon_distance()
	horizon_job=Horizon.new(); horizon_job.configure(world.geography,world_anchor,center,target_distance)
func commit_stream() -> void:
	var replacement := MeshInstance3D.new(); replacement.mesh=horizon_job.mesh(material); add_child(replacement)
	if horizon!=null: horizon.queue_free()
	horizon=replacement; horizon_job=null; active_center=target_center; has_active=true
	for key in tiles.keys():
		if near(key,active_center): tiles[key].visible=true
		else: tiles[key].queue_free(); tiles.erase(key)
func build(key: Vector2i) -> void:
	var vertices := PackedVector3Array(); var normals := PackedVector3Array(); var uv := PackedVector2Array(); var indices := PackedInt32Array()
	var heights: Array = []
	# A one-sample border gives neighboring tiles identical edge normals.
	for z in range(-1,GRID+2):
		for x in range(-1,GRID+2):
			var wx: float = key.x*TILE+float(x)*TILE/GRID; var wz: float = key.y*TILE+float(z)*TILE/GRID
			heights.append(world.geography.height(wx,wz))
	for z in GRID+1:
		for x in GRID+1:
			var i := z*(GRID+1)+x
			var h := (z+1)*(GRID+3)+x+1
			var wx: float = key.x*TILE+float(x)*TILE/GRID; var wz: float = key.y*TILE+float(z)*TILE/GRID
			vertices.append(Vector3(wx,heights[h],wz)-world_anchor)
			var dx: float = heights[h+1]-heights[h-1]
			var dz: float = heights[h+GRID+3]-heights[h-GRID-3]
			normals.append(Vector3(-dx,float(TILE)/GRID*2,-dz).normalized()); uv.append(Vector2(wx,wz)*0.03)
			if x<GRID and z<GRID: indices.append_array(PackedInt32Array([i,i+1,i+GRID+1,i+1,i+GRID+2,i+GRID+1]))
	var arrays := []; arrays.resize(Mesh.ARRAY_MAX); arrays[Mesh.ARRAY_VERTEX]=vertices; arrays[Mesh.ARRAY_NORMAL]=normals; arrays[Mesh.ARRAY_TEX_UV]=uv; arrays[Mesh.ARRAY_INDEX]=indices
	var mesh := ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays); mesh.surface_set_material(0,material)
	var node := MeshInstance3D.new(); node.mesh=mesh; add_child(node); tiles[key]=node
	node.visible=not has_active or near(key,active_center)
