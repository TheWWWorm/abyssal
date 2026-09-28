extends Node3D
## Art direction only: light scattering, particulate and rising bubbles.
const OceanProfile=preload("res://native/presentation/ocean_profile.gd")
var atmosphere := preload("res://native/presentation/ocean_options.gd").defaults()
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
## The player's setting: 1 is full strength, as the lamps were designed.
var headlight_strength := 1.0
const HEADLIGHT_ENERGY := 32.0
const BEAM_ENERGY := .7
var daylight := DirectionalLight3D.new()
var water_gain := 1.0
var warm_sky := Vector3(.4,.4,.1)
var sun_color := Vector3.ONE
var upper_sky := Vector3(.018,.08,.16)
var water_tint := Vector3.ONE
var water_sun := 1.0
var sun_gain := 1.0
var haze_gain := 1.0
var snow_density := 1.0
var current := Vector3.ZERO
var drift_offset := Vector3.ZERO
var bloom_strength := 0.0
## Absolute positions and presentation time; never tied to the floating origin.
var luminous_trail: Array[Vector4] = []
var luminous_strength := PackedFloat32Array()
var trail_at := -1.0
var trail_region := 0
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
		# Two pooled lights cover the original hulls. Unused slots stay dark;
		# each cone follows the position and direction of its own source lamp.
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
	cloud.instance_count=1200
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

static var tested_beam: Shader
static func beam_shader(tested: bool) -> Shader:
	"""The beam as drawn from outside it: the cone's near surface, depth
	tested, so a beam behind a hull is hidden by the hardware on every GPU,
	not only where the scene depth reads back (some phones' Compatibility
	drivers return none, and another vessel's beams then showed over the
	player's hull). From inside the cone there is no near surface, so the
	far one is drawn untested, as the shader file itself does."""
	var untested: Shader=preload("res://native/presentation/headlight_beam.gdshader")
	if not tested: return untested
	if tested_beam==null:
		tested_beam=Shader.new()
		tested_beam.code=untested.code.replace("cull_front, depth_draw_never, depth_test_disabled","cull_back, depth_draw_never")
	return tested_beam
static func camera_near_beam(beam: Node3D, camera_position: Vector3, margin: float=1.5) -> bool:
	"""Whether the camera is inside the beam's cone or close enough to its
	surface that the near plane could cut the near side away."""
	var local: Vector3=beam.global_transform.affine_inverse()*camera_position
	var along: float=-local.z
	if along<-margin or along>BEAM_LENGTH+margin: return false
	return Vector2(local.x,local.y).length()<=BEAM_HALF_TANGENT*maxf(along,0.0)+margin
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
		# Godot's front faces wind clockwise. Keep the exterior facing out so
		# cull_front draws the far boundary, including from inside the volume.
		tool.add_vertex(Vector3.ZERO);tool.add_vertex(b);tool.add_vertex(a)
		tool.add_vertex(Vector3(0,0,-length));tool.add_vertex(a);tool.add_vertex(b)
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
	lamp.light_energy=HEADLIGHT_ENERGY
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
	var frozen: bool=view!=null and view.process_mode==Node.PROCESS_MODE_DISABLED
	var seconds := 0.0 if frozen else maxf(delta,0.0)
	ambient_clock+=seconds
	particle_material.set_shader_parameter("drift_time",ambient_clock)
	RenderingServer.global_shader_parameter_set("ocean_visual_time",ambient_clock)
	if world!=null and world.region!=null:
		update_water_light(world.region.player.depth,seconds)
		var pose: Transform3D = world.render_pose(world.region.player)
		var rig: Array=[]
		if view!=null and is_instance_valid(view.player_model):
			rig=view.player_model.headlight_rig();pose=view.player_model.global_transform
			view.player_model.set_headlight_lenses(headlights_enabled and not world.session.docked)
		for i in mini(lamps.size(),rig.size()):
			lamps[i].global_transform=pose*rig[i].frame
			lamps[i].light_color=view.player_model.headlight_tint(rig[i].tint)
			beams[i].material_override.set_shader_parameter("tint",lamps[i].light_color)
		for i in lamps.size():
			var lamp := lamps[i]
			lamp.visible=i<rig.size() and headlights_enabled and not world.session.docked and world.region.player.health.hull>0
			# A lamp still inside the berth or the gate, behind the plane the
			# hull is clipped by, lights nothing: it comes on crossing the sill.
			if lamp.visible and view!=null and view.player_clip_enabled:
				var plane: Vector4=view.player_clip_plane
				lamp.visible=Vector3(plane.x,plane.y,plane.z).dot(lamp.global_position)+plane.w>=0.0
			beams[i].visible=beams_enabled
			if lamp.visible and beams_enabled:
				var pass_shader: Shader=beam_shader(not camera_near_beam(beams[i],camera.global_position))
				if beams[i].material_override.shader!=pass_shader:beams[i].material_override.shader=pass_shader
			# Snow uses the same reach map even when the visible cone is hidden.
			if lamp.visible and (beams_enabled or enhanced()):
				shade_beam(lamp,beams[i],i)
				# Through a gate or a hangar door the hull is clipped to the far
				# side of the plane; the water its lamps light is clipped with it.
				var clipped: bool=view!=null and view.player_clip_enabled
				beams[i].material_override.set_shader_parameter("clip_enabled",clipped)
				if clipped: beams[i].material_override.set_shader_parameter("clip_plane",view.player_clip_plane)
	var boosting: bool = world!=null and world.region!=null and not world.session.docked and world.region.player.boost_active and not world.region.cinematic()
	boost_amount=move_toward(boost_amount,1.0 if boosting else 0.0,seconds*4)
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
	update_water_particles(seconds,anchor)

func enhanced() -> bool:
	return view!=null and view.modern_graphics

func set_atmosphere(choices: Dictionary) -> void:
	for key in atmosphere:atmosphere[key]=bool(choices.get(key,preload("res://native/presentation/ocean_options.gd").default_on(key)))
	# Settings are usable over a frozen dive: refresh the picture without
	# advancing particle ages, the luminous trail or the simulation clock.
	if world!=null and world.region!=null and is_node_ready():
		update_water_light(world.region.player.depth,0.0,true)
		if is_instance_valid(camera):update_water_particles(0.0,world.geography.anchor)
		if is_instance_valid(camera):_process(0.0)

func update_water_particles(seconds: float, anchor: Vector3) -> void:
	particle_material.set_shader_parameter("enhanced",1.0 if enhanced() else 0.0)
	particle_material.set_shader_parameter("snow_enabled",atmosphere.marine_snow)
	particle_material.set_shader_parameter("bioluminescence_enabled",atmosphere.bioluminescence)
	particles.multimesh.visible_instance_count=1200 if enhanced() else 720
	# The chase camera sits behind the hull. Bias the cloud ahead so its
	# densest part actually reaches the two lamps instead of ending at them.
	var focus := -camera.global_basis.z*24.0 if enhanced() else Vector3.ZERO
	particle_material.set_shader_parameter("focus_offset",focus)
	particles.custom_aabb=AABB(focus-Vector3.ONE*60,Vector3.ONE*120)
	drift_offset+=current*seconds
	particle_material.set_shader_parameter("current_offset",Vector3(fposmod(drift_offset.x,90),0,fposmod(drift_offset.z,90)))
	particle_material.set_shader_parameter("snow_density",snow_density)
	for i in lamps.size():
		var suffix := "_a" if i==0 else "_b"
		particle_material.set_shader_parameter("lamp_frame"+suffix,lamps[i].global_transform.affine_inverse())
		particle_material.set_shader_parameter("lamp_occlusion"+suffix,beams[i].get_meta("occlusion_map"))
		particle_material.set_shader_parameter("lamp_active"+suffix,1.0 if lamps[i].visible else 0.0)
		particle_material.set_shader_parameter("lamp_color"+suffix,lamps[i].light_color*headlight_strength)
	if world!=null and world.region!=null:
		var region_id: int=world.region.get_instance_id()
		var absolute: Vector3=world.render_pose(world.region.player).origin+anchor
		# A gate transfer or a new dive cannot leave a light streak joining two
		# distant points. A normal region rebase preserves the absolute trail.
		if trail_region!=region_id and not luminous_trail.is_empty():
			var last: Vector4=luminous_trail.back()
			if absolute.distance_to(Vector3(last.x,last.y,last.z))>100: luminous_trail.clear();luminous_strength.clear()
		trail_region=region_id
		bloom_strength=OceanProfile.bloom(absolute) if enhanced() and not world.session.docked else 0.0
		if not world.session.docked and seconds>0 and (trail_at<0 or ambient_clock-trail_at>=.24):
			var moved := true
			if not luminous_trail.is_empty():
				var last: Vector4=luminous_trail.back()
				moved=absolute.distance_to(Vector3(last.x,last.y,last.z))>1.0
			if moved:
				luminous_trail.append(Vector4(absolute.x,absolute.y,absolute.z,ambient_clock));luminous_strength.append(bloom_strength)
				if luminous_trail.size()>10:luminous_trail.pop_front();luminous_strength.remove_at(0)
			trail_at=ambient_clock
	var trail := PackedVector4Array()
	var strengths := PackedFloat32Array()
	for i in 10:
		var point: Vector4=luminous_trail[i] if i<luminous_trail.size() else Vector4(0,0,0,-100)
		trail.append(Vector4(point.x-anchor.x,point.y-anchor.y,point.z-anchor.z,point.w))
		strengths.append(luminous_strength[i] if i<luminous_strength.size() else 0.0)
	particle_material.set_shader_parameter("disturbance",trail)
	particle_material.set_shader_parameter("disturbance_strength",strengths)

func set_headlights(on: bool) -> void:
	headlights_enabled=on
	var active: bool=on and world!=null and not world.session.docked
	for lamp in lamps: lamp.visible=active
	particle_material.set_shader_parameter("lamps_on",1.0 if on else 0.0)
	if is_node_ready() and is_instance_valid(camera):_process(0.0)

var occlusion_phase := 0
func shade_beam(lamp: SpotLight3D, beam: MeshInstance3D, index: int) -> void:
	# The player's own hull stands round its lamps and must not stop them.
	var own: Array[RID]=[]
	if view!=null and is_instance_valid(view.player_occluder): own.append(view.player_occluder.get_rid())
	shade_beam_in(get_world_3d().direct_space_state,lamp,beam,occlusion_phase+index,own)
	if index==lamps.size()-1: occlusion_phase+=1

static func shade_beam_in(space: PhysicsDirectSpaceState3D, lamp: SpotLight3D, beam: MeshInstance3D, phase: int, exclude: Array[RID]=[]) -> void:
	"""Light does not pass through a station wall, a creature or another
	vessel, and neither may the drawn beam beyond it. The cone is sampled from
	the lens on a small grid of directions against those colliders, less the
	lamp's own hull, and the distance each ray gets
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
			var ray := PhysicsRayQueryParameters3D.create(frame.origin,frame.origin+direction*(BEAM_LENGTH+2),2|4)
			ray.hit_back_faces=true;ray.hit_from_inside=true;ray.exclude=exclude
			var hit := space.intersect_ray(ray)
			reach.set_pixel(column,row,Color(BEAM_LENGTH+10 if hit.is_empty() else -(inverse*hit.position).z,0,0))
	map.update(reach)

func set_headlight_strength(value: float) -> void:
	"""Dims the lamps, the lit water in their beams and the snow they catch."""
	headlight_strength=value
	for i in lamps.size():
		lamps[i].light_energy=HEADLIGHT_ENERGY*value
		beams[i].material_override.set_shader_parameter("energy",BEAM_ENERGY*value)

func set_shadow_level(level: int) -> void:
	"""Shadow quality Off leaves the headlights and the overhead light unshadowed."""
	shadows=level>0
	daylight.shadow_enabled=shadows
	for lamp in lamps:lamp.shadow_enabled=shadows

func set_headlight_beams(on: bool) -> void:
	beams_enabled=on
	for beam in beams: beam.visible=on

func import_sky_ramp(cache: String) -> void:
	var path:=cache.path_join("data/textures/skybox.bmp.png")
	if not FileAccess.file_exists(path):return
	var pixels:=Image.load_from_file(path)
	if pixels==null:return
	# Original sky geometry uses the right-hand ramp at rows 1..9 for the
	# bright opening, with warmer rows below. Average that opening, scaled
	# for compatible replacement textures, rather than inventing a sun hue.
	var scale := Vector2(pixels.get_size())/Vector2(8,64)
	var opening := Vector3.ZERO
	for y in range(1,10):
		var color := pixels.get_pixelv(Vector2i(Vector2(6,y)*scale)).srgb_to_linear()
		opening+=Vector3(color.r,color.g,color.b)/9.0
	sun_color=opening
	var warm := pixels.get_pixelv(Vector2i(Vector2(6,16)*scale)).srgb_to_linear()
	warm_sky=Vector3(warm.r,warm.g,warm.b)*.45
static func sky_profile(depth: float, warm: Vector3=Vector3(.4,.4,.1)) -> Vector3:
	var shallow:=exp(-maxf(depth-8000,0)/12000.0)
	var blue:=Vector3(.004,.013,.03).lerp(Vector3(.055,.20,.42),shallow)
	var warm_band:=exp(-pow((depth-11000.0)/6500.0,2.0))
	return blue.lerp(warm,warm_band*.75)

static func sunlight_profile(depth: float) -> float:
	# The original's water has illuminated upper layers even at its stylised
	# kilometre depths. Keep those openings, then lose them in the abyss.
	return exp(-pow(maxf(depth-11000.0,0.0)/14000.0,2.0))

static func light_profile(depth: float) -> Vector3:
	# Independent art-direction curve in the engine's depth units. Shelter
	# lights take over gradually as daylight is absorbed by the water column.
	var transmission := exp(-maxf(depth-8000.0,0.0)/15000.0)
	return Vector3(.095+.22*transmission,.025+.8*transmission*transmission,.3+.8*transmission)

func update_water_light(depth: float, delta: float, immediate: bool=false) -> void:
	var profile := light_profile(depth)
	var blend := 1.0 if immediate else 1.0-exp(-maxf(delta,0.0)*2.0)
	var regional_blend := 1.0 if immediate else blend*.35
	var sky := sky_profile(depth,warm_sky)
	var sun := sunlight_profile(depth)
	var water := {"tint":Vector3.ONE,"haze":1.0,"snow":1.0,"current":Vector3.ZERO,"sun":1.0}
	if enhanced() and atmosphere.regional_water and world!=null:
		var point: Array=world.global_position()
		water=OceanProfile.sample(Vector2(point[0],point[2])/world.map_scale(),world.session.data)
	if not enhanced() or not atmosphere.deep_darkness:
		# The classic presentation retains its original sky and particle light.
		var transmission := exp(-maxf(depth-8000.0,0.0)/15000.0)
		profile=Vector3(.065+.25*transmission,.06+.85*transmission,.32+1.2*transmission)
		var shallow := exp(-maxf(depth-8000,0)/13000.0)
		sky=Vector3(.012,.045,.1).lerp(Vector3(.055,.19,.38),shallow).lerp(warm_sky,exp(-pow((depth-11000.0)/6500.0,2.0))*.85)
	if not enhanced():sun=1.0
	water_tint=water_tint.lerp(water.tint,regional_blend)
	water_sun=lerpf(water_sun,water.sun,regional_blend)
	sun_gain=lerpf(sun_gain,sun*water_sun,blend)
	if enhanced() and atmosphere.filtered_sunlight:profile.y+=sun_gain*.24
	haze_gain=lerpf(haze_gain,water.haze,regional_blend)
	snow_density=lerpf(snow_density,water.snow,regional_blend)
	current=current.lerp(water.current,regional_blend)
	environment.environment.ambient_light_energy=lerpf(environment.environment.ambient_light_energy,profile.x,blend)
	daylight.light_energy=lerpf(daylight.light_energy,profile.y,blend)
	# A reversible art-direction experiment: tint the existing illumination,
	# retaining its depth fade, shadows and the imported surface colours.
	var cool: bool=enhanced() and atmosphere.cool_lighting
	environment.environment.ambient_light_color=Color("8eb4c0") if cool else Color("bfc2c1")
	daylight.light_color=Color("68babc") if cool else Color("e0ded2")
	water_gain=lerpf(water_gain,profile.z,blend)
	RenderingServer.global_shader_parameter_set("ocean_light_gain",water_gain)
	RenderingServer.global_shader_parameter_set("ocean_haze_gain",haze_gain)
	RenderingServer.global_shader_parameter_set("ocean_water_tint",water_tint)
	RenderingServer.global_shader_parameter_set("ocean_sun_gain",sun_gain)
	RenderingServer.global_shader_parameter_set("ocean_sun_color",sun_color)
	RenderingServer.global_shader_parameter_set("ocean_shaft_gain",sun_gain if enhanced() and atmosphere.filtered_sunlight else 0.0)
	upper_sky=upper_sky.lerp(sky*water_tint,blend)
	RenderingServer.global_shader_parameter_set("ocean_upper_color",upper_sky)
	environment.environment.volumetric_fog_density=.00024*haze_gain
