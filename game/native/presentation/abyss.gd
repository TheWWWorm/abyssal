extends Node3D
## Art direction only: light scattering, particulate and rising bubbles.
const OceanProfile=preload("res://native/presentation/ocean_profile.gd")
const CabinWindows=preload("res://native/presentation/cabin_windows.gd")
const OceanOptions=preload("res://native/presentation/ocean_options.gd")
const Habitat=preload("res://native/simulation/habitat.gd")
var atmosphere := OceanOptions.defaults()
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
var sun_color := Vector3.ONE
## The region colour (cy.b) as shown, easing towards region_target after a
## gate or a dive into another station's water; sRGB bytes over 255.
var region_color := FALLBACK_REGION
var region_target := FALLBACK_REGION
var region_station := -1
var region_data: Dictionary
var region_known := false
## The water column in front of the scene (water_column.gdshader): a
## full-screen pass shown with enhanced graphics and volumetric light.
var column_material := ShaderMaterial.new()
var column_volume := MeshInstance3D.new()
## The density's repeat in metres along each axis (the shader's SCALE).
const COLUMN_PERIOD := Vector3(1.0/.0017,1.0/.0045,1.0/.0017)
## The same density at a finer scale, as the suspended matter the headlight
## beams scatter off and the marine snow follows (SUSPENSION_SCALE in
## headlight_beam.gdshader and particulate.gdshader). It drifts with the
## current, and slowly of its own accord, as in the Deeper project.
const SUSPENSION_PERIOD := Vector3(1.0/.014,1.0/.032,1.0/.014)
const SUSPENSION_DRIFT := Vector3(.0011/.014,0.0,.0005/.014)
## Marine snow settles at about this rate, metres a second, on average.
const SNOW_SINKING := .28
static var suspension: NoiseTexture3D
## The camera's own velocity in the open world, smoothed over a few frames;
## the enhanced snow is stretched along the water's movement past it.
var camera_velocity := Vector3.ZERO
## The camera's turning, radians a second about a world axis, smoothed the
## same way; with motion cues the snow streaks across the view in a turn.
var camera_spin := Vector3.ZERO
var previous_view := Basis.IDENTITY
## Motion cues' faint plankton clouds a few hundred metres out
## (distant_plankton.gdshader), anchored in the open world.
var plankton := MultiMeshInstance3D.new()
var plankton_material := ShaderMaterial.new()
const PLANKTON_COUNT := 40
## The snow and bubbles, and after them the motes only motion cues show
## (NEAR_CELL in particulate.gdshader).
const MOTES := 1200
const NEAR_MOTES := 360
## The block of water the clouds repeat over (PERIOD in the shader).
const PLANKTON_PERIOD := Vector3(960.0,360.0,960.0)
var previous_eye := [0.0,0.0,0.0]
var eye_known := false
## The noise lattices of ocean_radiance.gdshaderinc, metres to cells along
## each axis, and the cells after which their hash repeats (OCEAN_CELLS there).
const OCEAN_LATTICES := {"ocean_veil_phase":[.0019,.0009,.0019],"ocean_veil_fine_phase":[.0019*2.63,.0009*2.63,.0019*2.63],"ocean_bank_phase":[.0007,.0021,.0007],"ocean_column_phase":[.0034,.00032,.0034],"ocean_column_fine_phase":[.0034*1.9,.00032*.5,.0034*1.9]}
const OCEAN_CELLS := 256.0
## region_base per station of region_data, which a blend asks for often.
var region_cache := {}
## How gradually, in chart units, the water turns from one station's colour
## to the next: the mix runs over about a unit either side of half way, and
## neighbouring stations lie about three and a half apart.
const REGION_BLEND := 1.0
## Gates move the ship at once; the colour then follows over a few seconds.
const REGION_EASE := .8
var upper_sky := FALLBACK_REGION
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
## Another vessel's beam is drawn only from this many metres beyond the
## camera (headlight_beam.gdshader's clearance); the player's lamps are
## further off than this from the chase camera.
const BEAM_CLEARANCE := 20.0
## A cache imported before the palette was (or a station no alga reaches):
## plain water, WATER_HUE in sRGB, at the brightness of a typical region.
## Guessing an alga would paint every station of an older import alike.
const FALLBACK_REGION := Vector3(.3228,.5847,.8127)
## The surface light, on this engine's scale, that the phone's strongest
## light (ambient 2048, directional 4096 of 4096) corresponds to.
const SURFACE_AMBIENT := .315
const SURFACE_DAYLIGHT := .85

func _ready() -> void:
	process_priority=1
	preload("res://native/presentation/ocean_radiance_map.gd").ensure(get_tree())
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
	set_tight_glow(env)
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
	column_material.shader=preload("res://native/presentation/water_column.gdshader")
	column_material.render_priority=-125
	column_material.set_shader_parameter("density_texture",suspension_density())
	var screen := QuadMesh.new();screen.size=Vector2(2,2)
	column_volume.name="WaterColumn";column_volume.mesh=screen;column_volume.material_override=column_material
	column_volume.extra_cull_margin=16384;column_volume.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;column_volume.visible=false
	add_child(column_volume)
	particle_material.shader=preload("res://native/presentation/particulate.gdshader")
	particle_material.set_shader_parameter("suspension",suspension_density())
	var mesh := QuadMesh.new()
	mesh.size=Vector2.ONE
	mesh.material=particle_material
	var cloud := MultiMesh.new()
	cloud.transform_format=MultiMesh.TRANSFORM_3D
	cloud.use_custom_data=true
	cloud.mesh=mesh
	cloud.instance_count=MOTES+NEAR_MOTES
	var rng := RandomNumberGenerator.new()
	rng.seed=902602
	for i in MOTES:
		var bubble := i%3==0
		var radius := rng.randf_range(0.16,0.48) if bubble else rng.randf_range(0.025,0.065)
		cloud.set_instance_transform(i,Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*radius),Vector3(rng.randf_range(-45,45),rng.randf_range(-45,45),rng.randf_range(-45,45))))
		cloud.set_instance_custom_data(i,Color(rng.randf(),1 if bubble else 0,radius,1))
	# Motion cues' own motes, close round the camera, drawn after the rest.
	var near := RandomNumberGenerator.new();near.seed=290417
	for i in range(MOTES,MOTES+NEAR_MOTES):
		var radius := near.randf_range(0.025,0.06)
		cloud.set_instance_transform(i,Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*radius),Vector3(near.randf_range(-15,15),near.randf_range(-15,15),near.randf_range(-15,15))))
		cloud.set_instance_custom_data(i,Color(near.randf(),0,radius,2))
	particles.multimesh=cloud
	# Shader-wrapped motes occupy a camera-centred 90 m cell. Keep the CPU
	# bounds there too, including room for billboard corners and boost streaks.
	particles.custom_aabb=AABB(Vector3.ONE*-60,Vector3.ONE*120)
	particles.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(particles)
	plankton_material.shader=preload("res://native/presentation/distant_plankton.gdshader")
	# Drawn before the water column, which hazes them as it hazes distant hulls.
	plankton_material.render_priority=-126
	var card := QuadMesh.new();card.size=Vector2.ONE;card.material=plankton_material
	var clouds := MultiMesh.new()
	clouds.transform_format=MultiMesh.TRANSFORM_3D;clouds.use_custom_data=true;clouds.mesh=card
	clouds.instance_count=PLANKTON_COUNT
	var scatter := RandomNumberGenerator.new();scatter.seed=513077
	for i in PLANKTON_COUNT:
		var spot := Vector3(scatter.randf(),scatter.randf(),scatter.randf())*PLANKTON_PERIOD
		clouds.set_instance_transform(i,Transform3D(Basis.IDENTITY,spot))
		# Seed, half height in metres, width over height.
		clouds.set_instance_custom_data(i,Color(scatter.randf(),scatter.randf_range(16.0,34.0),scatter.randf_range(1.4,2.4),0.0))
	plankton.name="DistantPlankton";plankton.multimesh=clouds;plankton.top_level=true;plankton.visible=false
	plankton.custom_aabb=AABB(-PLANKTON_PERIOD*.5-Vector3.ONE*90.0,PLANKTON_PERIOD+Vector3.ONE*180.0)
	plankton.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(plankton)

static func suspension_density() -> NoiseTexture3D:
	"""The drifting density of the water, one texture for the water column,
	the headlight beams and the snow, so they show the same banks."""
	if suspension==null:
		var noise := FastNoiseLite.new();noise.seed=1413;noise.frequency=.052;noise.fractal_octaves=3
		suspension=NoiseTexture3D.new();suspension.width=64;suspension.height=64;suspension.depth=64;suspension.seamless=true;suspension.noise=noise
	return suspension

static var tested_beam: Shader
## Glow for highlights only. With Godot's defaults (threshold 1, a wide
## fourth level, no luminance cap) a plasma bolt or an explosion flash
## spread into a white cloud that hid its own shape and the ship beside it.
## A higher threshold leaves lit paint alone; the small levels keep a tight
## halo round lamps and bolts, and the cap stops one flash flooding the view.
static func set_tight_glow(env: Environment) -> void:
	env.glow_hdr_threshold=1.25
	env.glow_hdr_luminance_cap=6.0
	env.set_glow_level(0,0.3)
	env.set_glow_level(1,0.8)
	env.set_glow_level(2,0.3)
	env.set_glow_level(3,0.0)

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
	material.set_shader_parameter("suspension",suspension_density())
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
	CabinWindows.clock=ambient_clock
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
	# The open-world eye in double precision: at the original chart's spacing
	# the anchor is thousands of kilometres out, where a float steps by metres.
	var eye: Array=absolute_eye()
	# A gate or a new dive moves the camera at once; that is not movement
	# through the water.
	if eye_known and seconds>0.0:
		var moved := Vector3(eye[0]-previous_eye[0],eye[1]-previous_eye[1],eye[2]-previous_eye[2])/seconds
		if moved.length()<400.0:camera_velocity=camera_velocity.lerp(moved,1.0-exp(-seconds*10.0))
		var turn: Quaternion=(camera.global_basis.orthonormalized()*previous_view.inverse()).get_rotation_quaternion()
		if turn.w<0.0:turn=-turn
		# The rotation vector, exact at small angles as well.
		var axis := Vector3(turn.x,turn.y,turn.z)
		var angle := 2.0*asin(minf(axis.length(),1.0))
		# A cut to another camera or view is not a turn.
		if angle<.6:camera_spin=camera_spin.lerp(axis*(angle/maxf(axis.length(),.000001)/seconds),1.0-exp(-seconds*10.0))
	previous_eye=eye;eye_known=true;previous_view=camera.global_basis.orthonormalized()
	update_plankton(eye)
	# Reduce the world phase on the CPU; WebGL never subtracts large world
	# coordinates to recover centimetre-size billboards during open-world travel.
	particle_material.set_shader_parameter("eye_phase",Vector3(fposmod(eye[0],90),fposmod(eye[1],90),fposmod(eye[2],90)))
	# The water's veil and light columns are anchored in the open world. Each
	# noise lattice gets the eye's cell already reduced to its repeat: a
	# shader given the eye itself lost the hash's precision kilometres out and
	# drew seams and broken banks across the water.
	for uniform in OCEAN_LATTICES:
		var scale: Array=OCEAN_LATTICES[uniform]
		RenderingServer.global_shader_parameter_set(uniform,Vector3(fposmod(eye[0]*scale[0],OCEAN_CELLS),fposmod(eye[1]*scale[1],OCEAN_CELLS),fposmod(eye[2]*scale[2],OCEAN_CELLS)))
	update_water_column(anchor)
	particle_material.set_shader_parameter("cloud_origin",particles.global_position)
	particle_material.set_shader_parameter("eye",camera.global_position)
	particle_material.set_shader_parameter("lamp_origin",(lamps[0].global_position+lamps[1].global_position)*.5)
	particle_material.set_shader_parameter("lamp_forward",-lamps[0].global_basis.z)
	particle_material.set_shader_parameter("lamps_on",1.0 if headlights_enabled and world!=null and not world.session.docked else 0.0)
	update_water_particles(seconds,anchor)

func absolute_eye() -> Array:
	"""The camera in the open world, in metres, summed as doubles: the region
	anchor is rounded once per region, but the camera's place in it is not
	lost to the anchor's thousands of kilometres."""
	var anchor: Vector3=world.geography.anchor if world!=null and world.region!=null else Vector3.ZERO
	var at: Vector3=camera.global_position
	return [float(anchor.x)+float(at.x),float(anchor.y)+float(at.y),float(anchor.z)+float(at.z)]

func update_water_column(anchor: Vector3) -> void:
	var env: Environment=environment.environment
	column_volume.visible=enhanced() and env.volumetric_fog_enabled
	if not column_volume.visible:return
	column_volume.global_position=camera.global_position
	column_material.set_shader_parameter("visual_time",ambient_clock)
	column_material.set_shader_parameter("phase",Vector3(fposmod(anchor.x,COLUMN_PERIOD.x),fposmod(anchor.y,COLUMN_PERIOD.y),fposmod(anchor.z,COLUMN_PERIOD.z)))
	var albedo: Color=env.volumetric_fog_albedo
	column_material.set_shader_parameter("water_color",Vector3(albedo.r,albedo.g,albedo.b)*Vector3(.45,.62,.55))
	var depth: float=world.region.player.depth if world!=null and world.region!=null else 0.0
	column_material.set_shader_parameter("depth_fade",lerpf(.33,1.0,direct_light(depth)))
	column_material.set_shader_parameter("density_gain",COLUMN_DENSITY*haze_gain)

## Suspended matter in the water column, per metre at full density.
const COLUMN_DENSITY := .001

func enhanced() -> bool:
	return view!=null and view.modern_graphics

func set_atmosphere(choices: Dictionary) -> void:
	for key in atmosphere:atmosphere[key]=bool(choices.get(key,OceanOptions.default_on(key)))
	update_station_lights()
	# Settings are usable over a frozen dive: refresh the picture without
	# advancing particle ages, the luminous trail or the simulation clock.
	if world!=null and world.region!=null and is_node_ready():
		update_water_light(world.region.player.depth,0.0,true)
		if is_instance_valid(camera):update_water_particles(0.0,world.geography.anchor)
		if is_instance_valid(camera):_process(0.0)

func set_water_colour(value: float) -> void:
	"""How strongly each region's algae colour the enhanced water."""
	if is_equal_approx(region_strength,value):return
	region_strength=value
	if world!=null and world.region!=null and is_node_ready():update_water_light(world.region.player.depth,0.0,true)

func update_water_particles(seconds: float, anchor: Vector3) -> void:
	particle_material.set_shader_parameter("enhanced",1.0 if enhanced() else 0.0)
	particle_material.set_shader_parameter("snow_enabled",atmosphere.marine_snow)
	particle_material.set_shader_parameter("bioluminescence_enabled",atmosphere.bioluminescence)
	particle_material.set_shader_parameter("motion_cues",motion_cues())
	particle_material.set_shader_parameter("camera_spin",camera_spin)
	particles.multimesh.visible_instance_count=(MOTES+NEAR_MOTES if motion_cues() else MOTES) if enhanced() else 720
	# The chase camera sits behind the hull. Bias the cloud ahead so its
	# densest part actually reaches the two lamps instead of ending at them.
	var focus := -camera.global_basis.z*24.0 if enhanced() else Vector3.ZERO
	particle_material.set_shader_parameter("focus_offset",focus)
	particles.custom_aabb=AABB(focus-Vector3.ONE*60,Vector3.ONE*120)
	drift_offset+=current*seconds
	particle_material.set_shader_parameter("current_offset",Vector3(fposmod(drift_offset.x,90),0,fposmod(drift_offset.z,90)))
	# The suspended matter is carried with the snow, anchored in the open
	# world and reduced to its repeat on the CPU, as the water column is.
	var matter: Vector3=anchor-drift_offset+SUSPENSION_DRIFT*ambient_clock
	RenderingServer.global_shader_parameter_set("ocean_suspension_phase",Vector3(fposmod(matter.x,SUSPENSION_PERIOD.x),fposmod(matter.y,SUSPENSION_PERIOD.y),fposmod(matter.z,SUSPENSION_PERIOD.z)))
	particle_material.set_shader_parameter("water_motion",current+Vector3(0,-SNOW_SINKING,0)-camera_velocity)
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

func motion_cues() -> bool:
	"""Motion cues are an enhanced departure from the original's empty water."""
	return enhanced() and atmosphere.motion_cues

func update_plankton(eye: Array) -> void:
	"""The distant clouds, in open water only: not from a berth or a dock."""
	plankton.visible=motion_cues() and world!=null and world.region!=null and world.session!=null and not world.session.docked
	if not plankton.visible:return
	plankton.global_transform=Transform3D(Basis.IDENTITY,camera.global_position)
	plankton_material.set_shader_parameter("cloud_origin",camera.global_position)
	plankton_material.set_shader_parameter("eye_phase",Vector3(fposmod(eye[0],PLANKTON_PERIOD.x),fposmod(eye[1],PLANKTON_PERIOD.y),fposmod(eye[2],PLANKTON_PERIOD.z)))
	plankton_material.set_shader_parameter("drift",Vector3(fposmod(drift_offset.x,PLANKTON_PERIOD.x),fposmod(drift_offset.y,PLANKTON_PERIOD.y),fposmod(drift_offset.z,PLANKTON_PERIOD.z)))

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
	# The pale end of the original subtractive ramp supplies the enhanced
	# sunlight's tint, scaled for compatible replacement textures. This is a
	# presentation choice; the source opening uses the left-hand additive ramp.
	var scale := Vector2(pixels.get_size())/Vector2(8,64)
	var opening := Vector3.ZERO
	for y in range(1,10):
		var color := pixels.get_pixelv(Vector2i(Vector2(6,y)*scale)).srgb_to_linear()
		opening+=Vector3(color.r,color.g,color.b)/9.0
	sun_color=opening

static func depth_factor(depth: float) -> float:
	"""bb.c: 1 down to 15000, then falling by one per further 15000 with no
	floor; below 30000 it is negative and the region colour is black."""
	return 1.0-maxf(0.0,depth-15000.0)/15000.0

static func region_base(data: Dictionary, station_id: int) -> Vector3:
	"""cy.b: the first alga in the station's prevalence list colours its
	water, at 1.5 times its share of the palette colour (sRGB over 255, so
	it may exceed 1 before the depth factor and the clamp)."""
	var palette: Array=data.get("water_palette",[])
	var alga: Dictionary=Habitat.alga(data,station_id)
	if alga.is_empty():return FALLBACK_REGION
	var index: int=int(alga.species)-13
	if index<0 or index>=palette.size() or palette[index].size()!=3:return FALLBACK_REGION
	var colour: Array=palette[index]
	return Vector3(float(colour[0]),float(colour[1]),float(colour[2]))*1.5*float(alga.percent)/100.0/255.0

static func sky_profile(depth: float, base: Vector3=FALLBACK_REGION) -> Vector3:
	"""cy.c: the clear colour, the region colour times the depth factor, each
	channel clamped to a byte. The skybox is composited over it in
	ocean_radiance.gdshaderinc."""
	return (base*depth_factor(depth)).clamp(Vector3.ZERO,Vector3.ONE)

static func direct_light(depth: float) -> float:
	"""cy.c: setDirIntensity(min(4096, 4096·(f+0.25))) as a fraction of 4096."""
	return clampf(depth_factor(depth)+.25,0.0,1.0)

static func ambient_light(depth: float) -> float:
	"""cy.c: setAmbientIntensity(min(2048, 1024+1024·(f+0.25))) over 4096.
	The phone's value reaches zero below any station; a small floor keeps
	the deepest water readable."""
	return clampf(.25+.25*(depth_factor(depth)+.25),.04,.5)

static func sunlight_profile(depth: float) -> float:
	# The enhanced sunlight shafts: illuminated upper layers even at the
	# original's stylised kilometre depths, lost in the abyss.
	return exp(-pow(maxf(depth-11000.0,0.0)/14000.0,2.0))

static func light_profile(depth: float) -> Vector3:
	"""The ambient energy, daylight energy and water gain at a depth: the
	phone's light curves on this engine's scale, so the surface keeps its
	brightness and the deep is as much darker as it was on the phone."""
	return Vector3(SURFACE_AMBIENT*ambient_light(depth)/.5,SURFACE_DAYLIGHT*direct_light(depth),1.0)

## The enhanced open water's hue: the previous art-directed water colour
## (.055, .2, .42) at unit luminance. A little of it stays under every
## region's colour, so each still reads as water.
const WATER_HUE := Vector3(.2957,1.0753,2.2581)
## How much of the alga's own chroma the enhanced water keeps, and how much
## the region's hue outweighs the plain water colour, at full water colour
## (Settings: Water colour). The default share keeps .45 of the chroma at .9
## of the weight: a muted tint, not flat paint.
const REGION_CHROMA := .75
const REGION_HUE_WEIGHT := 1.5
## The Water colour setting (OceanOptions.water_colour).
static var region_strength := OceanOptions.WATER_COLOUR_DEFAULT
## How much of the hue the suspended haze takes: a trace, so distant water
## stays water-coloured.
const REGION_HAZE := .2
## Luminance of the enhanced water overhead at the surface, and what is left
## below 30000 where the phone's sky has gone black.
const ENHANCED_UPPER := .08
const ENHANCED_FLOOR := .035
const FOG_ALBEDO := Vector3(.36,.5,.52)

static func modern_hue(base: Vector3) -> Vector3:
	"""The alga's colour as a hue for the enhanced water, at unit luminance.
	The palette colour is taken at full strength (the phone's share and
	byte clamp only brighten it, and washed a golden sky out to cream),
	softened towards grey and laid over a little of the water's blue-green,
	so a region reads as tinted water rather than flat paint."""
	var peak := maxf(base.x,maxf(base.y,base.z))
	if peak<=.0001:return WATER_HUE
	var colour := Color(base.x/peak,base.y/peak,base.z/peak).srgb_to_linear()
	var linear := Vector3(colour.r,colour.g,colour.b)
	var luminance := linear.dot(Vector3(.2126,.7152,.0722))
	if luminance<=.0001:return WATER_HUE
	var tinted := Vector3.ONE.lerp(linear/luminance,REGION_CHROMA*region_strength)
	var weight := minf(1.0,REGION_HUE_WEIGHT*region_strength)
	var hue := WATER_HUE.lerp(tinted,weight).clamp(Vector3.ZERO,Vector3.ONE*2.3)
	# The blue-green water bends a muted hue on the way: gold went green and
	# red pink. The mix keeps its lightness and chroma but turns to the alga's
	# own hue by the same weight, as the strong setting and the phone's water
	# show it; at 0% the water keeps its own.
	var mixed := oklab(hue);var own := oklab(linear)
	var chroma := Vector2(mixed.y,mixed.z).length()
	var angle := lerp_angle(atan2(mixed.z,mixed.y),atan2(own.z,own.y),weight)
	hue=from_oklab(Vector3(mixed.x,chroma*cos(angle),chroma*sin(angle))).clamp(Vector3.ZERO,Vector3.ONE*2.3)
	return hue/maxf(.0001,hue.dot(Vector3(.2126,.7152,.0722)))

static func oklab(c: Vector3) -> Vector3:
	"""Linear sRGB to Oklab (Björn Ottosson's matrices)."""
	var l := 0.4122214708*c.x+0.5363325363*c.y+0.0514459929*c.z
	var m := 0.2119034982*c.x+0.6806995451*c.y+0.1073969566*c.z
	var s := 0.0883024619*c.x+0.2817188376*c.y+0.6299787005*c.z
	l=signf(l)*pow(absf(l),1.0/3.0);m=signf(m)*pow(absf(m),1.0/3.0);s=signf(s)*pow(absf(s),1.0/3.0)
	return Vector3(0.2104542553*l+0.7936177850*m-0.0040720468*s,1.9779984951*l-2.4285922050*m+0.4505937099*s,0.0259040371*l+0.7827717662*m-0.8086757660*s)

static func from_oklab(c: Vector3) -> Vector3:
	var l := pow(c.x+0.3963377774*c.y+0.2158037573*c.z,3.0)
	var m := pow(c.x-0.1055613458*c.y-0.0638541728*c.z,3.0)
	var s := pow(c.x-0.0894841775*c.y-1.2914855480*c.z,3.0)
	return Vector3(4.0767416621*l-3.3077115913*m+0.2309699292*s,-1.2684380046*l+2.6097574011*m-0.3413193965*s,-0.0041960863*l-0.7034186147*m+1.7076147010*s)

static func modern_upper(depth: float, base: Vector3) -> Vector3:
	"""The enhanced water overhead: the region hue dimmed by the phone's
	depth factor, with a faint remainder in the deep."""
	return modern_hue(base)*(ENHANCED_UPPER*clampf(depth_factor(depth),0.0,1.0)+ENHANCED_FLOOR)

func update_region(delta: float, immediate: bool) -> void:
	"""The water colour where the ship is. The phone switched it with the
	region; here it shades from one station's colour into the next across
	the water between them, and eases in after a gate."""
	if world==null or world.session==null:return
	var data: Dictionary=world.session.data
	var station: int=world.session.station_id
	if not is_same(data,region_data):region_data=data;region_cache.clear()
	region_station=station
	var chart=null
	if world.has_method("global_position") and world.get("region")!=null:
		var point: Array=world.global_position()
		chart=Vector2(point[0],point[2])/float(world.map_scale())
	region_target=region_blend(data,chart,station,region_cache)
	if not region_known:region_color=region_target;region_known=true
	if immediate:region_color=region_target
	else:region_color=region_color.lerp(region_target,1.0-exp(-maxf(delta,0.0)*REGION_EASE))

static func region_blend(data: Dictionary, chart, station: int, cache: Dictionary={}) -> Vector3:
	"""The stations' colours weighted by nearness: the nearest one's alone
	close to it, an even mix half way to a neighbour of another colour."""
	var stations: Array=data.get("tables",{}).get("stations",[])
	if chart==null or stations.is_empty():return region_base(data,station)
	var distances: Array[float]=[];var nearest := INF
	for entry in stations:
		var distance: float=(chart as Vector2).distance_to(Vector2(float(entry[2]),float(entry[3])))
		distances.append(distance);nearest=minf(nearest,distance)
	var colour := Vector3.ZERO;var total := 0.0
	for id in stations.size():
		var excess: float=distances[id]-nearest
		if excess>REGION_BLEND*8.0:continue
		var weight := exp(-excess/REGION_BLEND)
		if not cache.has(id):cache[id]=region_base(data,id)
		colour+=cache[id]*weight;total+=weight
	return colour/total

func update_water_light(depth: float, delta: float, immediate: bool=false) -> void:
	# The first region seen sets the water at once rather than easing in.
	if not region_known and world!=null:immediate=true
	update_region(delta,immediate)
	var profile := light_profile(depth)
	var blend := 1.0 if immediate else 1.0-exp(-maxf(delta,0.0)*2.0)
	var regional_blend := 1.0 if immediate else blend*.35
	var sky := sky_profile(depth,region_color)
	var sun := sunlight_profile(depth)
	var water := {"tint":Vector3.ONE,"haze":1.0,"snow":1.0,"current":Vector3.ZERO,"sun":1.0}
	if enhanced() and atmosphere.regional_water and world!=null:
		var point: Array=world.global_position()
		water=OceanProfile.sample(Vector2(point[0],point[2])/world.map_scale(),world.session.data)
	if enhanced() and atmosphere.deep_darkness:
		# Past the phone's own curve: the ambient keeps falling with the
		# directional light, and the open water above dims with it.
		var dusk := lerpf(.7,1.0,direct_light(depth))
		profile.x*=dusk;profile.z=lerpf(.45,1.0,direct_light(depth))
	if enhanced():
		# Enhanced hulls are physically lit; below the phone's curve a little
		# ambient and overhead light stays, as it did before the curve, so
		# the deep remains readable beyond the headlights.
		profile.x=maxf(profile.x,.14);profile.y=maxf(profile.y,.05)
	# The classic presentation draws the original sky and its glow only.
	if not enhanced():sun=0.0
	water_tint=water_tint.lerp(water.tint,regional_blend)
	water_sun=lerpf(water_sun,water.sun,regional_blend)
	sun_gain=lerpf(sun_gain,sun*water_sun,blend)
	if enhanced() and atmosphere.filtered_sunlight:profile.y+=sun_gain*.24
	haze_gain=lerpf(haze_gain,water.haze,regional_blend)
	snow_density=lerpf(snow_density,water.snow,regional_blend)
	current=current.lerp(water.current,regional_blend)
	environment.environment.ambient_light_energy=lerpf(environment.environment.ambient_light_energy,profile.x,blend)
	daylight.light_energy=lerpf(daylight.light_energy,profile.y,blend)
	# The phone dims its one white light with depth (cy.c). Classic models
	# shade with their own Lambert term; scale its ambient and directional
	# parts by the same curves.
	RenderingServer.global_shader_parameter_set("ocean_model_light",Vector2(ambient_light(depth)/.5,direct_light(depth)))
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
	# The depth already changes continuously and the region colour eases in.
	# Classic shows the phone's sky itself; the enhanced water takes the
	# region's hue into layered water and tints the suspended haze with it.
	upper_sky=sky if not enhanced() else modern_upper(depth,region_color)
	RenderingServer.global_shader_parameter_set("ocean_classic_sky",0.0 if enhanced() else 1.0)
	RenderingServer.global_shader_parameter_set("ocean_region_strength",region_strength)
	RenderingServer.global_shader_parameter_set("ocean_upper_color",upper_sky)
	var haze_tint := (modern_hue(region_color)/WATER_HUE).clamp(Vector3.ONE*.4,Vector3.ONE*2.5)
	var albedo := (FOG_ALBEDO*Vector3.ONE.lerp(haze_tint,REGION_HAZE)).clamp(Vector3.ZERO,Vector3.ONE)
	environment.environment.volumetric_fog_albedo=Color(albedo.x,albedo.y,albedo.z)
	environment.environment.volumetric_fog_density=.00024*haze_gain

func update_station_lights() -> void:
	"""Station lamps and windows follow the warm station lights choice."""
	OceanOptions.warm_station=atmosphere.warm_station_lights
	RenderingServer.global_shader_parameter_set("ocean_station_warmth",OceanOptions.station_window_warmth(OceanOptions.warm_station))
	if not is_inside_tree():return
	for lamp in get_tree().get_nodes_in_group("station_work_lamps"):
		lamp.light_color=OceanOptions.station_lamp_color(lamp.get_meta("overhead",true),OceanOptions.warm_station)
