extends RefCounted
## Lighting for the isolated previews (the shipyard's vessel, the chart's
## station). One strong ambient and one lamp beside the camera lit every face
## almost the same, so hulls read as flat cut-outs. Studio lighting instead: a
## warm key from high on one side that throws shadows across the modules, a
## weak cool fill from the other, and a rim from behind that picks out the
## silhouette against the water.

static func apply(viewport: SubViewport, env: Environment) -> void:
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
