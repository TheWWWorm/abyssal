extends SceneTree
const Shadow = preload("res://native/presentation/station_shadow.gd")
const Model = preload("res://native/presentation/model.gd")
const Library = preload("res://scripts/model_library.gd")
var failures := 0
func expect(ok: bool, message: String) -> void:
	if not ok:failures+=1;push_error(message)
func _initialize() -> void:call_deferred("run")

func panel(mesh: ArrayMesh, x: float, bone: int) -> void:
	var tool := SurfaceTool.new();tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for uv in [Vector2(0,0),Vector2(0,1),Vector2(1,1),Vector2(0,0),Vector2(1,1),Vector2(1,0)]:
		tool.set_normal(Vector3.FORWARD);tool.set_uv(Vector2(49.5,98.5)+uv*10)
		tool.set_uv2(Vector2(bone,0));tool.add_vertex(Vector3(x+(uv.y-.5)*6,(uv.x-.5)*6,0))
	tool.commit(mesh)

func transforms() -> Array[Transform3D]:
	var bones: Array[Transform3D]=[]
	bones.resize(64);bones.fill(Transform3D.IDENTITY)
	return bones

func frame(viewport: SubViewport) -> Color:
	for i in 6:await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image().get_pixel(64,64)

func check_coverage() -> void:
	var library := Library.new();var mesh := ArrayMesh.new()
	panel(mesh,0,0);panel(mesh,12,0);panel(mesh,100,1)
	var surfaces := [{"blend":0,"texture":-1,"alpha":true,"door":true},{"blend":0,"texture":-1,"alpha":true,"door":true},{"blend":4,"texture":-1,"alpha":false,"door":false}]
	var shadow := Shadow.new()
	shadow.configure(library,{"resource":"test-station","pattern":0,"textures":[]},[mesh,surfaces,[]])
	var bones := transforms();shadow.pose(bones)
	expect(shadow.mesh.get_surface_count()==1 and shadow.mesh.surface_get_array_len(0)==12,"Solid surfaces sharing an atlas and cutout mode merge; additive sprites do not cast shadows")
	expect(shadow.bone_bounds.size()==1 and not shadow.bone_bounds.has(1),"Decorative lamp bones are excluded from the shadow pose")
	var old_pose: Array=shadow.materials[0].get_shader_parameter("source_bones")
	var old_bounds := shadow.custom_aabb
	bones[1].origin=Vector3(500,0,0);shadow.pose(bones)
	expect(shadow.materials[0].get_shader_parameter("source_bones")==old_pose and shadow.custom_aabb==old_bounds,"Lamp animation leaves solid shadow uniforms and bounds unchanged")
	bones[0].origin=Vector3(4,0,0);shadow.pose(bones)
	expect(shadow.custom_aabb.position.is_equal_approx(old_bounds.position+Vector3(4,0,0)),"Moving solid bones update the shadow bounds")
	if DisplayServer.get_name()=="headless":shadow.mesh=null;shadow.free();return
	var viewport := SubViewport.new();viewport.size=Vector2i(128,128);viewport.own_world_3d=true
	viewport.positional_shadow_atlas_size=1024;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var camera := Camera3D.new();camera.position=Vector3(0,0,20);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=20;viewport.add_child(camera)
	var environment := WorldEnvironment.new();environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color.BLACK
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_energy=.02;viewport.add_child(environment)
	var wall := MeshInstance3D.new();var quad := QuadMesh.new();quad.size=Vector2(30,30);wall.mesh=quad
	wall.material_override=StandardMaterial3D.new();wall.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;viewport.add_child(wall)
	var light := OmniLight3D.new();light.position=Vector3(0,0,8);light.omni_range=30;light.light_energy=4
	light.shadow_enabled=true;light.shadow_normal_bias=0;light.shadow_bias=.01;viewport.add_child(light)
	viewport.add_child(shadow);shadow.position.z=4;bones[0]=Transform3D.IDENTITY;shadow.pose(bones)
	var pixels := Image.create(128,128,true,Image.FORMAT_RGBA8);pixels.fill(Color(.2,.2,.2));pixels.generate_mipmaps()
	var texture := ImageTexture.create_from_image(pixels)
	shadow.materials[0].set_shader_parameter("albedo_crisp",texture);shadow.materials[0].set_shader_parameter("albedo_smooth",texture)
	shadow.materials[0].set_shader_parameter("texture_size",Vector2(128,128))
	var closed := await frame(viewport)
	shadow.set_coverage("hangar_open",1.0)
	var opened := await frame(viewport)
	expect(opened.r>closed.r+.15,"An opening hangar door invalidates the cached shadow and lets light through")
	shadow.set_coverage("hangar_open",0.0)
	expect(absf((await frame(viewport)).r-closed.r)<.03,"Closing the door restores its shadow")
	shadow.set_coverage("stream_visibility",0.0)
	expect((await frame(viewport)).r>closed.r+.15,"A streamed-out station casts no shadow")
	shadow.set_coverage("stream_visibility",1.0)
	expect(absf((await frame(viewport)).r-closed.r)<.03,"Restoring stream visibility restores its shadow")
	bones[0].origin=Vector3(20,0,0);shadow.pose(bones)
	expect((await frame(viewport)).r>closed.r+.15,"Moving machinery updates cached shadows")
	bones[0]=Transform3D.IDENTITY;shadow.pose(bones)
	pixels.fill(Color.WHITE);pixels.generate_mipmaps();texture.update(pixels)
	for smoothed in [false,true]:
		shadow.set_coverage("smoothed",smoothed);shadow.invalidate_shadows()
		expect((await frame(viewport)).r>closed.r+.15,"White palette cutouts transmit light with either station filter")
	shadow.mesh=null;viewport.queue_free();await process_frame

func check_imported(content) -> void:
	var library := Library.new();library.root=content.root
	for entry in content.registry:
		if int(entry.id)<3300 or int(entry.id)>=3400:continue
		var model := Model.new();model.library=library;root.add_child(model);model.configure(content.root,entry)
		var shadow: MeshInstance3D=model.figure.get_node("StationShadow")
		expect(shadow!=null and model.figure.get_node("Mesh").cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,"Imported station shadows are separate from the visible animated material")
		var groups: Array=library.mesh_for(entry.model,model.last_pattern,entry.textures[0])[1]
		var expected := 0;var actual := 0
		for group in groups:
			if int(group.blend)==0:
				for face in group.faces:expected+=face.indices.size()
		for i in shadow.mesh.get_surface_count():actual+=shadow.mesh.surface_get_array_len(i)
		expect(actual==expected,"Every imported solid triangle remains in the shadow mesh for %s"%entry.model)
		var view=load("res://native/presentation/world_view.gd").new();root.add_child(view);view.set_process(false)
		view.add_station_collision(model)
		expect(shadow.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY and shadow.get_child_count()==0,"Collision setup excludes the shadow proxy")
		expect(model.figure.get_node("Mesh").cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,"Collision setup does not restore expensive visible-material shadows")
		model.set_stream_visibility(.4);model.set_hangar_open(.6)
		expect(shadow.coverage.stream_visibility==.4,"Imported station fades propagate to the shadow caster")
		if model.is_hangar():expect(is_equal_approx(shadow.coverage.hangar_open,.6),"Imported hangar opening propagates to its shadow caster")
		library.station_smoothing=true;model.refresh_station_filtering()
		expect(shadow.coverage.smoothed,"Station smoothing updates the shadow palette filter")
		library.station_smoothing=false
		model.queue_free();view.queue_free();await process_frame

func run() -> void:
	await check_coverage()
	var content=load("res://native/content.gd").new()
	if not content.load_cache(OS.get_cmdline_user_args()[0]):push_error(content.failure);quit(1);return
	await check_imported(content)
	print("STATION_SHADOW_CHECK %d failures"%failures);quit(1 if failures else 0)
