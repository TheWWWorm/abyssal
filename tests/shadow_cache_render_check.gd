extends SceneTree
## Render with a window: --rendering-method forward_plus or gl_compatibility.
## Compare cached shadows with a newly allocated light after each scene change.
var failures := 0
var stage: Node3D
var light: OmniLight3D
var caster: MeshInstance3D
var camera: Camera3D

func _initialize() -> void:run.call_deferred()

func box(size: Vector3, position: Vector3, colour: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new();var mesh := BoxMesh.new();mesh.size=size;node.mesh=mesh;node.position=position
	var material := StandardMaterial3D.new();material.albedo_color=colour;material.roughness=.7;node.material_override=material
	stage.add_child(node);return node

func frame() -> Image:
	for i in 8:await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func difference(a: Image, b: Image) -> float:
	var left := a.get_data();var right := b.get_data();var changed := 0
	if left.size()!=right.size():return 1.0
	for i in left.size():
		if absi(int(left[i])-int(right[i]))>3:changed+=1
	return float(changed)/left.size()

func compare_fresh(label: String) -> void:
	var cached := await frame()
	var replacement := light.duplicate() as OmniLight3D
	stage.remove_child(light);light.free();light=replacement;stage.add_child(light)
	var fresh := await frame()
	var error := difference(cached,fresh)
	if error>.001:
		failures+=1;push_error("%s: cached shadow differs from a new light (%f)"%[label,error])
		DirAccess.make_dir_recursive_absolute("user://shadow-cache-check")
		cached.save_png("user://shadow-cache-check/"+label+"-cached.png")
		fresh.save_png("user://shadow-cache-check/"+label+"-fresh.png")
	print("SHADOW_CACHE_CASE ",label," difference=",error)

func check_light_batching() -> void:
	var material := ShaderMaterial.new();var shader := Shader.new()
	var body := "shader_type spatial;\nvoid fragment(){ALBEDO=vec3(.4,.5,.6);ROUGHNESS=.6;}"
	shader.code=body;material.shader=shader
	for child in stage.get_children():
		if child is MeshInstance3D:child.material_override=material
	for i in 6:
		var extra := light.duplicate() as OmniLight3D
		extra.position=Vector3(-4.0+i*1.6,3.5,4);extra.light_energy=1.5
		extra.light_color=Color(.2+i*.12,.8-i*.08,.5);stage.add_child(extra)
	var original := await frame()
	var original_draws := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	shader.code=body.replace("void fragment()","uniform float normal_deviation_limit=0.0;\nvoid fragment()")
	var batched := await frame()
	var batched_draws := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var error := difference(original,batched)
	# Grouped writes can differ by a few quantization steps from repeated
	# writes to an 8-bit target, but must retain the same lighting and colour.
	if error>.005:
		failures+=1;push_error("Batched light colour differs from ordinary additive lighting (%f)"%error)
	print("SHADOW_BATCH_CASE difference=",error," draws=",original_draws,"->",batched_draws)

func run() -> void:
	if DisplayServer.get_name()=="headless":
		push_error("Shadow cache verification needs a rendered window");quit(2);return
	root.size=Vector2i(640,480);root.content_scale_size=root.size
	root.use_taa=false;root.msaa_3d=Viewport.MSAA_DISABLED
	root.positional_shadow_atlas_size=2048
	stage=Node3D.new();root.add_child(stage)
	var world := WorldEnvironment.new();world.environment=Environment.new()
	world.environment.background_mode=Environment.BG_COLOR;world.environment.background_color=Color(.03,.04,.05)
	world.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color=Color.WHITE;world.environment.ambient_light_energy=.08;stage.add_child(world)
	camera=Camera3D.new();stage.add_child(camera);camera.position=Vector3(9,7,14);camera.look_at(Vector3(0,1,0))
	box(Vector3(24,.2,24),Vector3(0,-.1,0),Color(.6,.65,.7))
	box(Vector3(24,8,.2),Vector3(0,4,-6),Color(.6,.65,.7))
	caster=box(Vector3(2,3,2),Vector3(0,1.5,0),Color(.7,.3,.2))
	box(Vector3(2,2,2),Vector3(4,1,2),Color(.2,.4,.7))
	light=OmniLight3D.new();light.position=Vector3(-3,5,3);light.omni_range=24;light.light_energy=6
	light.omni_shadow_mode=OmniLight3D.SHADOW_CUBE;light.shadow_enabled=true
	light.shadow_bias=.02;light.shadow_normal_bias=.5;stage.add_child(light)
	await compare_fresh("initial")
	var before := await frame()
	caster.position.x=2;caster.rotation.y=.8
	var moved := await frame()
	if difference(before,moved)<.005:failures+=1;push_error("The moving caster must visibly change the scene")
	await compare_fresh("moved")
	caster.visible=false;await compare_fresh("hidden")
	caster.visible=true;caster.layers=2;light.shadow_caster_mask=1;await compare_fresh("excluded_layer")
	light.shadow_caster_mask=3;await compare_fresh("included_layer")
	light.position.x=2;light.omni_range=18;await compare_fresh("light_moved_and_resized")
	root.positional_shadow_atlas_size=1024;await compare_fresh("atlas_resized")
	# LOD meshes must use the uncached fallback when view-dependent LODs are enabled.
	var source := BoxMesh.new();var arrays := source.get_mesh_arrays();var lod := ArrayMesh.new()
	var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
	lod.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{2.0:indices.slice(0,indices.size()/2)})
	caster.mesh=lod;camera.position=Vector3(5,4,8);camera.look_at(Vector3(0,1,0))
	await compare_fresh("lod_and_camera")
	await check_light_batching()
	stage.queue_free();await process_frame
	print("SHADOW_CACHE_RENDER_CHECK ","OK" if failures==0 else "FAIL")
	quit(0 if failures==0 else 1)
