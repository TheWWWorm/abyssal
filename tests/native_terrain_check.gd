extends SceneTree
const Horizon = preload("res://native/presentation/terrain_horizon.gd")
var failures := 0
func expect(ok: bool, why: String) -> void:
	if not ok:
		failures+=1
		if failures<15: push_error(why)
func _initialize() -> void: call_deferred("run")
func settle(terrain) -> void:
	for frame in 150:
		terrain._process(0)
		await process_frame
		if terrain.horizon_job==null and terrain.has_active: return
	expect(false,"Terrain stream finishes its bounded work")
func run() -> void:
	var content=load("res://native/content.gd").new(); expect(content.load_cache(OS.get_cmdline_user_args()[0]),"Content loads")
	var app=load("res://native/gameplay.gd").new(); app.content=content; app.save_path="user://terrain-test.json"; app.settings_path="user://terrain-test.cfg"; root.add_child(app)
	await process_frame
	app.set_process(false); app.view.set_process(false); app.terrain.set_process(false)
	# Bottomless ocean is the shipping default. Retain the optional terrain
	# builder regression below by explicitly opting into its developer fixture.
	expect(not app.world.geography.seafloor_enabled,"Shipping ocean is bottomless")
	app.terrain._process(0)
	expect(not app.terrain.visible and app.terrain.tiles.is_empty(),"No sea floor meshes stream during gameplay")
	expect(not app.world.geography.contains([0,10000000,0]),"No reachable bottom collision")
	app.world.geography.seafloor_enabled=true
	app.camera.far=4000
	var terrain=app.terrain; app.camera.global_position=Vector3(0,-430,0)
	var random_before: int = app.session.rng.state
	var pose_before: Array = app.world.region.player.pose.values().duplicate(true)
	await settle(terrain)
	var tile_ids: Array = terrain.tiles.values().map(func(tile): return tile.get_instance_id())
	app.graphics.materials=false; app.apply_graphics()
	expect(terrain.material.get_shader_parameter("sediment_enabled")==false,"Material toggle restores procedural terrain")
	app.graphics.materials=true; app.apply_graphics()
	expect(terrain.material.get_shader_parameter("sediment_enabled")==false,"Engine terrain uses no bundled sediment texture")
	expect(tile_ids==terrain.tiles.values().map(func(tile): return tile.get_instance_id()),"Material switching does not rebuild or move terrain geometry")
	expect(terrain.tiles.size()==25 and terrain.horizon!=null,"Complete surface has 25 detailed tiles and one distant mesh")
	var builder := Horizon.new(); builder.configure(app.world.geography,terrain.world_anchor,terrain.active_center,terrain.horizon_distance())
	builder.advance(10000)
	expect(builder.finished() and builder.vertices.size()<(builder.radius*2+1)*(builder.radius*2+1)*6,"Distant terrain uses a bounded coarse mesh")
	var seam := {}
	for i in builder.vertices.size():
		var point: Vector3 = builder.vertices[i]+terrain.world_anchor
		seam[Vector2(point.x,point.z)]={"height":point.y,"normal":builder.normals[i]}
	var start := Vector2(terrain.active_center-Vector2i(2,2))*360
	var end := start+Vector2.ONE*1800
	var seam_samples := 0
	for tile in terrain.tiles.values():
		var arrays: Array = tile.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for i in vertices.size():
			var point: Vector3 = vertices[i]+terrain.world_anchor
			if point.x not in [start.x,end.x] and point.z not in [start.y,end.y]: continue
			var key := Vector2(point.x,point.z); seam_samples+=1
			expect(seam.has(key),"Every detailed boundary vertex is present in the distant mesh")
			if seam.has(key):
				expect(absf(seam[key].height-point.y)<0.01,"Both resolutions share the same boundary height")
				expect(seam[key].normal.distance_to(normals[i])<0.001,"Both resolutions share the same boundary normal")
	expect(seam_samples>=360,"All four detailed boundaries are checked")
	for i in range(0,builder.indices.size(),3):
		var p := Vector3.ZERO
		for j in 3: p+=builder.vertices[builder.indices[i+j]]+terrain.world_anchor
		p/=3
		expect(not (p.x>start.x and p.x<end.x and p.z>start.y and p.z<end.y),"Distant triangles never overlap the detailed surface")
	var extent: AABB = terrain.horizon.mesh.get_aabb()
	var eye: Vector3 = app.camera.position
	expect(eye.x-extent.position.x>app.camera.far and extent.end.x-eye.x>app.camera.far and eye.z-extent.position.z>app.camera.far and extent.end.z-eye.z>app.camera.far,"Outer terrain edge lies beyond the camera clip distance")
	var rotation_before: Vector3 = app.camera.rotation
	app.camera.fov=70
	for yaw in [0,45,90,135]:
		for pitch in [-75,-25,25]:
			app.camera.rotation_degrees=Vector3(pitch,yaw,0)
			var viewport: Vector2 = root.get_visible_rect().size
			for corner in [Vector2.ZERO,Vector2(viewport.x,0),viewport,Vector2(0,viewport.y)]:
				var p: Vector3 = app.camera.project_position(corner,app.camera.far)
				expect(p.x>extent.position.x and p.x<extent.end.x and p.z>extent.position.z and p.z<extent.end.z,"The distant mesh covers rotated widescreen far-plane corners")
	app.camera.rotation=rotation_before; app.camera.fov=65
	var previous_range: float = terrain.target_distance
	app.camera.far=4500; terrain._process(0)
	expect(terrain.horizon_job!=null and terrain.target_distance>previous_range,"A longer view range rebuilds the horizon even without camera movement")
	await settle(terrain); app.camera.far=4000
	var previous=terrain.horizon; var old_center: Vector2i = terrain.active_center
	app.camera.position.x+=360; terrain._process(0)
	expect(terrain.horizon==previous and terrain.active_center==old_center,"Travel retains the previous complete horizon while streaming")
	for tile in terrain.tiles:
		if not terrain.near(tile,old_center): expect(not terrain.tiles[tile].visible,"Pending detail stays hidden to prevent overlapping surfaces")
	# Crossing another cell must not discard a nearly built horizon forever.
	for frame in 90:
		app.camera.position.x+=9; terrain._process(0); await process_frame
	expect(terrain.horizon!=previous,"Moving camera still completes and commits a horizon")
	await settle(terrain)
	expect(terrain.tiles.size()==25,"Completed travel releases old detailed tiles")
	app.camera.position+=Vector3(6000,0,-6000); terrain._process(0); await settle(terrain)
	expect(terrain.tiles.size()==25,"A distant camera cut abandons stale pending tiles")
	expect(app.session.rng.state==random_before and app.world.region.player.pose.values()==pose_before,"Terrain streaming cannot mutate gameplay or its random sequence")
	var retained=terrain.tiles.values()[0]
	var first_vertex: Vector3 = retained.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX][0]
	var old_anchor: Vector3 = terrain.world_anchor
	var absolute_point: Vector3 = retained.global_transform*first_vertex+old_anchor
	previous=terrain.horizon
	app.world.enter_region(1); app.camera.position+=old_anchor-app.world.geography.anchor
	terrain._process(0)
	expect(terrain.horizon==previous and retained.visible,"Region entry retains the complete terrain while rebasing")
	expect((retained.global_transform*first_vertex+terrain.world_anchor).distance_to(absolute_point)<0.01,"Region rebasing preserves the rendered world position")
	await settle(terrain)
	expect(terrain.tiles.size()==25 and terrain.horizon.position==Vector3.ZERO,"Rebased replacement returns to local mesh coordinates")
	app.queue_free(); await process_frame; await create_timer(0.1).timeout
	print("NATIVE_TERRAIN ",failures," failures; ",seam_samples," seam samples, horizon coverage, movement and bounded replacement")
	quit(1 if failures else 0)
