extends Node3D
## Art direction only: light scattering, particulate and rising bubbles.
var camera: Camera3D
var world
var view
var boost_amount := 0.0
var ambient_clock := 0.0
var lamps: Array[SpotLight3D] = []
var beam_lamps: Array[SpotLight3D] = []
var particles := MultiMeshInstance3D.new()
var particle_material := ShaderMaterial.new()
var environment := WorldEnvironment.new()
var shadows := true
var headlights_enabled := true
var headlight_medium := FogVolume.new()
var daylight := DirectionalLight3D.new()
var water_gain := 1.0
var warm_sky := Vector3(.4,.4,.1)
var upper_sky := Vector3(.018,.08,.16)

func _ready() -> void:
	process_priority=1
	var env := Environment.new()
	var sky := Sky.new()
	var sky_material := ShaderMaterial.new()
	sky_material.shader=preload("res://native/presentation/abyss_sky.gdshader")
	sky.sky_material=sky_material
	sky.radiance_size=Sky.RADIANCE_SIZE_64
	env.background_mode=Environment.BG_SKY
	env.sky=sky
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color=Color("bfc2c1")
	env.ambient_light_energy=.22
	env.reflected_light_source=Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode=Environment.TONE_MAPPER_ACES
	env.tonemap_exposure=1.15
	env.glow_enabled=true
	env.glow_intensity=0.85
	env.ssao_enabled=true
	env.ssao_radius=1.3
	env.ssao_intensity=0.9
	env.fog_enabled=false
	env.fog_light_color=Color("02070e")
	env.fog_light_energy=0.7
	env.fog_density=0.0015
	env.fog_sky_affect=0.0
	env.volumetric_fog_enabled=RenderingServer.get_current_rendering_method()=="forward_plus"
	env.volumetric_fog_density=0.00024
	env.volumetric_fog_ambient_inject=0.0
	env.volumetric_fog_sky_affect=1.0
	env.volumetric_fog_length=850
	env.volumetric_fog_albedo=Color("88a6ae")
	env.volumetric_fog_anisotropy=0.08
	env.volumetric_fog_emission_energy=0
	environment.environment=env
	add_child(environment)
	var moon := daylight
	moon.basis=Basis.looking_at(-Vector3(-.25,.95,-.15).normalized(),Vector3.UP)
	moon.light_color=Color("e0ded2")
	moon.light_energy=.48;moon.light_volumetric_fog_energy=.03
	moon.light_angular_distance=0.0
	# Filtered sunlight and the nearby work lights illuminate actual surfaces.
	moon.shadow_enabled=true; moon.directional_shadow_max_distance=450; moon.shadow_normal_bias=1.0;moon.shadow_bias=.12
	add_child(moon)
	for x in [-1.8,1.8]:
		var lamp := create_headlight(x)
		lamp.shadow_enabled=shadows
		add_child(lamp)
		lamps.append(lamp)
		var shaft := SpotLight3D.new()
		shaft.visible=false
		# Cull masks exclude surface illumination, not shadow casters. This light
		# contributes only scattering, and is disabled on non-volumetric renderers.
		shaft.light_cull_mask=0
		shaft.light_color=lamp.light_color;shaft.light_energy=18
		shaft.spot_angle=lamp.spot_angle;shaft.spot_attenuation=.25
		shaft.light_volumetric_fog_energy=.8;shaft.shadow_enabled=true
		shaft.shadow_bias=.005;shaft.shadow_normal_bias=.02
		add_child(shaft);beam_lamps.append(shaft)
	# The shafts are real spotlight scattering in suspended water particles.
	# A local density volume keeps them legible without fogging the whole scene.
	headlight_medium.shape=RenderingServer.FOG_VOLUME_SHAPE_ELLIPSOID;headlight_medium.size=Vector3(60,50,180)
	add_child(headlight_medium)
	if RenderingServer.get_current_rendering_method()=="forward_plus":
		var medium := ShaderMaterial.new();medium.shader=preload("res://native/presentation/suspended_water.gdshader");medium.set_shader_parameter("density",.006)
		headlight_medium.material=medium
	particle_material.shader=preload("res://native/presentation/particulate.gdshader")
	var mesh := QuadMesh.new()
	mesh.size=Vector2.ONE
	mesh.material=particle_material
	var cloud := MultiMesh.new()
	cloud.transform_format=MultiMesh.TRANSFORM_3D
	cloud.use_custom_data=true
	cloud.mesh=mesh
	cloud.instance_count=720
	var rng := RandomNumberGenerator.new()
	rng.seed=902602
	for i in cloud.instance_count:
		var bubble := i%3==0
		var radius := rng.randf_range(0.16,0.48) if bubble else rng.randf_range(0.025,0.065)
		cloud.set_instance_transform(i,Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*radius),Vector3(rng.randf_range(-45,45),rng.randf_range(-45,45),rng.randf_range(-45,45))))
		cloud.set_instance_custom_data(i,Color(rng.randf(),1 if bubble else 0,radius,1))
	particles.multimesh=cloud
	# Shader-wrapped motes occupy a camera-centred 90 m cell. Keep the CPU
	# bounds there too, including room for billboard corners and boost streaks.
	particles.custom_aabb=AABB(Vector3.ONE*-60,Vector3.ONE*120)
	particles.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(particles)

static func create_headlight(x: float) -> SpotLight3D:
	var lamp := SpotLight3D.new()
	lamp.position=Vector3(x,-0.7,-1.5)
	lamp.light_color=Color("b4e9f2")
	# Broad work lights preserve surface texture at docking distances.
	lamp.light_energy=10.0
	lamp.spot_range=550
	lamp.spot_angle=18.0
	lamp.spot_angle_attenuation=2.0
	lamp.spot_attenuation=1.15
	lamp.light_volumetric_fog_energy=0.0
	lamp.shadow_enabled=true
	lamp.shadow_bias=0.1
	lamp.shadow_normal_bias=0.4
	return lamp

func _process(delta: float) -> void:
	if not is_instance_valid(camera): return
	ambient_clock+=maxf(delta,0.0)
	particle_material.set_shader_parameter("drift_time",ambient_clock)
	if world!=null and world.region!=null:
		update_water_light(world.region.player.depth,delta)
		var pose: Transform3D = world.render_pose(world.region.player)
		var box := AABB(Vector3(-10,-4,-12),Vector3(20,8,24))
		if view!=null and is_instance_valid(view.player_model):
			box=view.player_model.solid_bounds();pose=view.player_model.global_transform
		var mounts: Array = []
		if view!=null and is_instance_valid(view.player_model) and view.player_model.replacement!=null:
			mounts=view.player_model.replacement.get_meta("headlight_mounts",[]); pose=view.player_model.global_transform
		for i in lamps.size():
			var local := box.get_center()+Vector3(box.size.x*(0.18 if i==0 else -0.18),-box.size.y*0.08,-box.size.z*0.53)
			if mounts.size()>i: local=mounts[i]
			local.z=minf(local.z,box.position.z-.4)
			lamps[i].global_transform=pose*Transform3D(Basis(Vector3.UP,deg_to_rad(3 if i==0 else -3)),local)
		for i in lamps.size():
			var lamp := lamps[i]
			lamp.visible=headlights_enabled and not world.session.docked
			var shaft := beam_lamps[i];shaft.global_transform=lamp.global_transform
			shaft.visible=lamp.visible and environment.environment.volumetric_fog_enabled
			if shaft.visible:
				shaft.spot_range=beam_clearance(lamp.global_transform,lamp.spot_angle)
				shaft.visible=shaft.spot_range>.3

		headlight_medium.global_transform=pose*Transform3D(Basis.IDENTITY,Vector3(0,0,-85))
	var boosting: bool = world!=null and world.region!=null and not world.session.docked and world.region.player.boost_active and not world.region.cinematic()
	boost_amount=move_toward(boost_amount,1.0 if boosting else 0.0,delta*4)
	particle_material.set_shader_parameter("boost_amount",boost_amount)
	var anchor: Vector3=world.geography.anchor if world!=null and world.region!=null else Vector3.ZERO
	particles.global_position=camera.global_position
	var absolute_eye: Vector3=camera.global_position+anchor
	# Reduce the world phase on the CPU; WebGL never subtracts large world
	# coordinates to recover centimetre-size billboards during open-world travel.
	particle_material.set_shader_parameter("eye_phase",Vector3(fposmod(absolute_eye.x,90),fposmod(absolute_eye.y,90),fposmod(absolute_eye.z,90)))
	particle_material.set_shader_parameter("cloud_origin",particles.global_position)
	particle_material.set_shader_parameter("eye",camera.global_position)
	particle_material.set_shader_parameter("lamp_origin",(lamps[0].global_position+lamps[1].global_position)*.5)
	particle_material.set_shader_parameter("lamp_forward",-lamps[0].global_basis.z)
	particle_material.set_shader_parameter("lamps_on",1.0 if headlights_enabled and world!=null and not world.session.docked else 0.0)

func set_headlights(on: bool) -> void:
	headlights_enabled=on
	var active: bool=on and world!=null and not world.session.docked
	for lamp in lamps: lamp.visible=active
	for shaft in beam_lamps: shaft.visible=active and environment.environment.volumetric_fog_enabled
	particle_material.set_shader_parameter("lamps_on",1.0 if on else 0.0)

func beam_clearance(frame: Transform3D, angle: float) -> float:
	# Sample the cone, not just its centre. A finite fog voxel must not straddle
	# the far side of a thin dock wall. Surface spots are never range-clipped.
	var reach := 220.0
	for i in 17:
		var radial := 0.0 if i==0 else (.5 if i<=8 else 1.0)
		var phase := float((i-1)%8)*TAU/8.0
		var direction := (frame.basis*Vector3(cos(phase)*tan(deg_to_rad(angle))*radial,sin(phase)*tan(deg_to_rad(angle))*radial,-1)).normalized()
		var ray := PhysicsRayQueryParameters3D.create(frame.origin,frame.origin+direction*220,2)
		ray.hit_back_faces=true;ray.hit_from_inside=true
		var hit := get_world_3d().direct_space_state.intersect_ray(ray)
		if not hit.is_empty(): reach=minf(reach,maxf(.1,frame.origin.distance_to(hit.position)-2.5))
	return reach

func import_sky_ramp(cache: String) -> void:
	var path:=cache.path_join("data/textures/skybox.bmp.png")
	if not FileAccess.file_exists(path):return
	var pixels:=Image.load_from_file(path)
	if pixels==null or pixels.get_width()<8 or pixels.get_height()<64:return
	# The owner's sky atlas contains a warm vertical ramp. Use its hue for
	# shallow-water scattering; the depth transition is independently authored.
	var color:=pixels.get_pixel(6,16).srgb_to_linear()
	warm_sky=Vector3(color.r,color.g,color.b)*.45
static func sky_profile(depth: float, warm: Vector3=Vector3(.4,.4,.1)) -> Vector3:
	var shallow:=exp(-maxf(depth-8000,0)/13000.0)
	var blue:=Vector3(.012,.045,.1).lerp(Vector3(.055,.19,.38),shallow)
	var warm_band:=exp(-pow((depth-11000.0)/6500.0,2.0))
	return blue.lerp(warm,warm_band*.85)

static func light_profile(depth: float) -> Vector3:
	# Independent art-direction curve in the engine's depth units. Shelter
	# lights take over gradually as daylight is absorbed by the water column.
	var transmission := exp(-maxf(depth-8000.0,0.0)/15000.0)
	return Vector3(.065+.25*transmission,.06+.85*transmission,.32+1.2*transmission)

func update_water_light(depth: float, delta: float) -> void:
	var profile := light_profile(depth)
	var blend := 1.0-exp(-maxf(delta,0.0)*2.0)
	environment.environment.ambient_light_energy=lerpf(environment.environment.ambient_light_energy,profile.x,blend)
	daylight.light_energy=lerpf(daylight.light_energy,profile.y,blend)
	water_gain=lerpf(water_gain,profile.z,blend)
	RenderingServer.global_shader_parameter_set("ocean_light_gain",water_gain)
	upper_sky=upper_sky.lerp(sky_profile(depth,warm_sky),blend)
	RenderingServer.global_shader_parameter_set("ocean_upper_color",upper_sky)
