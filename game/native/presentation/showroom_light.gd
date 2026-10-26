extends RefCounted
## Lighting for the isolated previews (the shipyard's vessel, the chart's
## station). One strong ambient and one lamp beside the camera lit every face
## almost the same, so hulls read as flat cut-outs. Studio lighting instead: a
## warm key from high on one side that throws shadows across the modules, a
## weak cool fill from the other, and a rim from behind that picks out the
## silhouette against the water.

static func apply_antialiasing(viewport: SubViewport) -> void:
	# Showrooms render at their own native size. Follow the main view's edge
	# treatment without inheriting its resolution scale or upscaling buffers.
	var tree := Engine.get_main_loop() as SceneTree
	if tree==null:return
	var main := tree.root
	if viewport.msaa_3d!=main.msaa_3d:viewport.msaa_3d=main.msaa_3d
	# Temporal upscalers turn the main view's use_taa flag off because they
	# already reconstruct edges. Native-size previews still need temporal AA.
	var temporal := main.use_taa or main.scaling_3d_mode in [Viewport.SCALING_3D_MODE_FSR2,Viewport.SCALING_3D_MODE_METALFX_TEMPORAL,preload("res://native/presentation/amd.gd").mode()]
	var taa := temporal and RenderingServer.get_current_rendering_method()=="forward_plus"
	if viewport.use_taa!=taa:viewport.use_taa=taa

static func apply(viewport: SubViewport, env: Environment) -> void:
	apply_antialiasing(viewport)
	# A reference preview may open without a dive behind it. Its sky and
	# surface haze still need the same ocean texture used by every showroom.
	if DisplayServer.get_name()!="headless":
		preload("res://native/presentation/ocean_radiance_map.gd").ensure(viewport.get_tree())
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color=Color("9fb8c4");env.ambient_light_energy=.22
	env.tonemap_mode=Environment.TONE_MAPPER_ACES;env.tonemap_exposure=1.1
	# Only the Forward+ renderer has it; elsewhere the setting is ignored.
	env.ssao_enabled=true;env.ssao_radius=1.2;env.ssao_intensity=1.2
	var key:=DirectionalLight3D.new();key.name="Key"
	key.rotation_degrees=Vector3(-42,-58,0);key.light_color=Color("ffe2b8");key.light_energy=1.9
	key.shadow_enabled=true;key.directional_shadow_mode=DirectionalLight3D.SHADOW_ORTHOGONAL
	key.directional_shadow_max_distance=2000;key.shadow_bias=.06;key.shadow_normal_bias=1.5
	viewport.add_child(key)
	var fill:=DirectionalLight3D.new();fill.name="Fill"
	fill.rotation_degrees=Vector3(-12,62,0);fill.light_color=Color("7fa8d6");fill.light_energy=.45
	viewport.add_child(fill)
	var rim:=DirectionalLight3D.new();rim.name="Rim"
	rim.rotation_degrees=Vector3(-28,172,0);rim.light_color=Color("9fe3ff");rim.light_energy=1.1
	viewport.add_child(rim)
