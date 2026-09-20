extends Node3D
## Art direction only: light scattering, particulate and rising bubbles.
var camera: Camera3D
var world
var view
var boost_amount := 0.0
var ambient_clock := 0.0
var lamps: Array[SpotLight3D] = []
var beams: Array[MeshInstance3D] = []
var particles := MultiMeshInstance3D.new()
var particle_material := ShaderMaterial.new()
var environment := WorldEnvironment.new()
var shadows := true
var headlights_enabled := true
var beams_enabled := true
var daylight := DirectionalLight3D.new()
var water_gain := 1.0
var warm_sky := Vector3(.4,.4,.1)
var upper_sky := Vector3(.018,.08,.16)
# The cone reads as two beams beside each other for the first ten metres and
# is absorbed by seventy, as in the original's shot from above the hull.
const BEAM_LENGTH := 70.0
const OCCLUSION_SIZE := 12
const BEAM_HALF_TANGENT := .249

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
	# The fog is not reprojected from the previous frame. The headlight beam
	# and its glow move with the hull, and after a sharp turn or a pitch the
	# reprojected history left the lit water where the beam used to be: a
	# station part sitting in that stale volume was drawn as a bright blue
	# box for seconds while the water beside it was not. Without history the
	# scattering is computed fresh each frame; it is smooth enough not to need
	# the smoothing.
	env.volumetric_fog_temporal_reprojection_enabled=false
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
		# The visible cone of each lamp, a child so it follows the mount. Two
		# distinct beams as in the original, on either renderer; the earlier
		# fog-only spotlights blurred into one blob at the fog grid's resolution.
		var beam := create_beam()
		lamp.add_child(beam);beams.append(beam)
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

static func create_beam() -> MeshInstance3D:
	var beam := MeshInstance3D.new()
	beam.mesh=beam_mesh(BEAM_LENGTH,BEAM_LENGTH*BEAM_HALF_TANGENT)
	var material := ShaderMaterial.new();material.shader=preload("res://native/presentation/headlight_beam.gdshader")
	material.set_shader_parameter("beam_length",BEAM_LENGTH);material.set_shader_parameter("half_tangent",BEAM_HALF_TANGENT)
	# The beam's own shadow map: how far the light gets along each direction
	# of the cone before a station wall stops it, cast from the lens each frame.
	var reach := Image.create(OCCLUSION_SIZE,OCCLUSION_SIZE,false,Image.FORMAT_RF);reach.fill(Color(BEAM_LENGTH+10,0,0))
	var map := ImageTexture.create_from_image(reach)
	material.set_shader_parameter("occlusion",map)
	beam.set_meta("occlusion_image",reach);beam.set_meta("occlusion_map",map)
	beam.material_override=material
	beam.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Drawn after the opaque scene it reads the depth of, and never culled
	# while its lamp is in front of the camera, even when the camera is inside.
	beam.custom_aabb=AABB(Vector3(-BEAM_LENGTH*BEAM_HALF_TANGENT-2,-BEAM_LENGTH*BEAM_HALF_TANGENT-2,-BEAM_LENGTH-1),Vector3(BEAM_LENGTH*BEAM_HALF_TANGENT*2+4,BEAM_LENGTH*BEAM_HALF_TANGENT*2+4,BEAM_LENGTH+2))
	return beam

static func beam_mesh(length: float, radius: float, segments: int=24) -> ArrayMesh:
	"""A closed cone: apex at the origin, opening along -Z, so the beam shader
	shades each pixel exactly once from the far side of the volume."""
	var tool := SurfaceTool.new();tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ring: Array[Vector3]=[]
	for i in segments:
		var angle := TAU*i/segments;ring.append(Vector3(cos(angle)*radius,sin(angle)*radius,-length))
	for i in segments:
		var a: Vector3=ring[i];var b: Vector3=ring[(i+1)%segments]
		tool.add_vertex(Vector3.ZERO);tool.add_vertex(a);tool.add_vertex(b)
		tool.add_vertex(Vector3(0,0,-length));tool.add_vertex(b);tool.add_vertex(a)
	tool.generate_normals()
	return tool.commit()

static func create_headlight(x: float) -> SpotLight3D:
	var lamp := SpotLight3D.new()
	lamp.position=Vector3(x,-0.7,-1.5)
	lamp.light_color=Color("b4e9f2")
	# Work lights strong enough to read as lamps on a wall forty metres off:
	# the falloff is pow(distance,-attenuation), so at ten metres this is a
	# fifth of the energy and at forty about a thirtieth. The cone matches
	# the visible beam (BEAM_HALF_TANGENT), so the lit patch is the beam's end.
	lamp.light_energy=32.0
	lamp.spot_range=550
	lamp.spot_angle=rad_to_deg(atan(BEAM_HALF_TANGENT))
	lamp.spot_angle_attenuation=1.6
	lamp.spot_attenuation=.9
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
		if view!=null and is_instance_valid(view.player_model):
			mounts=view.player_model.headlight_mounts(); pose=view.player_model.global_transform
		for i in lamps.size():
			# On the noses of the two side pods, toed out, as the original's
			# beams leave the hull: two separate cones for their first length.
			var local := box.get_center()+Vector3(box.size.x*(-0.4 if i==0 else 0.4),0,-box.size.z*0.53)
			if mounts.size()>i: local=mounts[i]
			# A positive turn about +Y swings -Z towards -X: the port lamp (i==0) turns outward.
			lamps[i].global_transform=pose*Transform3D(Basis(Vector3.UP,deg_to_rad(12 if i==0 else -12)),local)
		for i in lamps.size():
			var lamp := lamps[i]
			lamp.visible=headlights_enabled and not world.session.docked
			# A lamp still inside the berth or the gate, behind the plane the
			# hull is clipped by, lights nothing: it comes on crossing the sill.
			if lamp.visible and view!=null and view.player_clip_enabled:
				var plane: Vector4=view.player_clip_plane
				lamp.visible=Vector3(plane.x,plane.y,plane.z).dot(lamp.global_position)+plane.w>=0.0
			beams[i].visible=beams_enabled
			if lamp.visible and beams_enabled:
				shade_beam(lamp,beams[i],i)
				# Through a gate or a hangar door the hull is clipped to the far
				# side of the plane; the water its lamps light is clipped with it.
				var clipped: bool=view!=null and view.player_clip_enabled
				beams[i].material_override.set_shader_parameter("clip_enabled",clipped)
				if clipped: beams[i].material_override.set_shader_parameter("clip_plane",view.player_clip_plane)
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
	particle_material.set_shader_parameter("lamps_on",1.0 if on else 0.0)

var occlusion_phase := 0
func shade_beam(lamp: SpotLight3D, beam: MeshInstance3D, index: int) -> void:
	shade_beam_in(get_world_3d().direct_space_state,lamp,beam,occlusion_phase+index)
	if index==lamps.size()-1: occlusion_phase+=1

static func shade_beam_in(space: PhysicsDirectSpaceState3D, lamp: SpotLight3D, beam: MeshInstance3D, phase: int) -> void:
	"""Light does not pass through a station wall, and neither may the drawn
	beam beyond it. The cone is sampled from the lens on a small grid of
	directions against the station colliders, and the distance each ray gets
	is written to the beam's occlusion map; the shader darkens the water past
	it. Half the rows are cast per call, alternating with the phase, so a
	wall ahead is current within two calls at a hundred and some rays each."""
	var reach: Image=beam.get_meta("occlusion_image");var map: ImageTexture=beam.get_meta("occlusion_map")
	var frame := lamp.global_transform;var inverse := frame.affine_inverse()
	var n := OCCLUSION_SIZE
	for row in n:
		if (row+phase)%2!=0: continue
		for column in n:
			var u := ((column+.5)/n*2.0-1.0);var v := ((row+.5)/n*2.0-1.0)
			if u*u+v*v>1.15: reach.set_pixel(column,row,Color(BEAM_LENGTH+10,0,0)); continue
			var direction: Vector3=(frame.basis*Vector3(u*BEAM_HALF_TANGENT,v*BEAM_HALF_TANGENT,-1.0)).normalized()
			var ray := PhysicsRayQueryParameters3D.create(frame.origin,frame.origin+direction*(BEAM_LENGTH+2),2)
			ray.hit_back_faces=true;ray.hit_from_inside=true
			var hit := space.intersect_ray(ray)
			reach.set_pixel(column,row,Color(BEAM_LENGTH+10 if hit.is_empty() else -(inverse*hit.position).z,0,0))
	map.update(reach)

func set_headlight_beams(on: bool) -> void:
	beams_enabled=on
	for beam in beams: beam.visible=on

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
