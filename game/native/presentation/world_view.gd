extends Node3D
const SpecialActor = preload("res://native/simulation/special_actor.gd")
const DRAW_DISTANCE := 10000.0
const DETAIL_DISTANCE := 2200.0
const DETAIL_RELEASE_DISTANCE := 2600.0
const STREAM_RELEASE_DISTANCE := 10500.0
const GATE_EFFECT_BOOST := 2.6
const STREAM_FADE_SECONDS := 1.2
## A creature set down anew comes in out of the haze over this long.
const CREATURE_FADE_SECONDS := 2.5

static func far_visibility(distance: float) -> float:
	return 1.0-smoothstep(7000.0,9600.0,distance)

const Model = preload("res://native/presentation/model.gd")
const Abyss = preload("res://native/presentation/abyss.gd")
const Library = preload("res://scripts/model_library.gd")
var world
var content
var camera: Camera3D
const CAMERA_NAMES := ["Chase","Front","Starboard","Port"]
var camera_mode := 0
var previous_camera_mode := -1
# Free look: the chase camera swung around the hull by the mouse while a
# modifier is held (yaw, pitch in radians), easing back when it is released.
var look_offset := Vector2.ZERO
var look_held := false
var library := Library.new()
var pack := preload("res://native/presentation/material_pack.gd").new()
var objects: Dictionary = {}
var station_nodes: Array = []
var gate_nodes: Array = []
var registry: Dictionary = {}
var modern_graphics := true
var revision := -1
var rendered_station := -1
var rendered_anchor := Vector3.ZERO
var rendered_modern := true
var rendered_pack := false
var neighbors: Dictionary = {}
var neighbor_clock := 0.0
var player_model
## The depth-limit barriers, after bb's two limiter panels (models 9993 and
## 9997) that ride with the submarine at its shallowest and deepest safe
## depth: here a drawn, hatched panel that fades in over the last stretch
## before each limit. Off unless asked for; the instruments show the limits.
var depth_limits := false
var limit_nodes: Array = []
const LIMIT_EXTENT := 60.0
## Metres of water, in the view's units, over which the panel fades in.
const LIMIT_FADE := 30.0
## Radiation waits above the shallow limit, pressure below the deep one.
const LIMIT_TINTS := [Color(1.0,0.82,0.25),Color(0.3,0.62,1.0)]
var banking := preload("res://native/simulation/ship_transform.gd").new()
var gate_preview := false
## A shot scripted from outside the view: its transform, and how far it has
## already given way to the ordinary camera (0 all its own, 1 all the chase's).
var cinematic_override := false
var cinematic_transform := Transform3D.IDENTITY
var cinematic_blend := 0.0
var departure_hangar
var departure_frame := Transform3D.IDENTITY
var departure_progress := -1.0
## The STREAM passage, framed from outside the submarine. Negative when no
## crossing is under way. Driven by how far the submarine has actually
## travelled rather than by a clock, so it cannot run ahead of the dive.
var transit_progress := -1.0
var transit_frame := Transform3D.IDENTITY
var transit_side := 1.0
## True once the submarine is on the far side, where the shot has to sit much
## closer to the aperture to keep it and the emerging hull in the same frame.
var transit_emerging := false
var departure_start := Vector3.ZERO
var departure_end := Vector3.ZERO
var portal_materials: Array=[]
var dock_orbit := .65
## The title menu's backdrop: the station circled as the phone game's ck path does.
var menu_backdrop := false
var previous_time := 0
var previous_particle_fraction := 0.0
var combat := preload("res://native/presentation/combat_effects.gd").new()
## An offscreen viewport that draws every model and effect surface once, so
## their shaders are compiled while the scene is being built rather than the
## first time each one swims into view. See bake_shaders().
var oven: SubViewport
var oven_frames := 0
func _ready() -> void:
	combat.owner_view=self; add_child(combat)
func configure(owner_world, owner_content, eye: Camera3D) -> void:
	world=owner_world; world.render_interpolation_enabled=true; content=owner_content; camera=eye; library.root=content.root; library.ocean_strength=0.12; library.effect_glow=0.65
	pack.enabled=false
	for record in content.registry: registry[int(record.id)]=record
	preload("res://native/presentation/replacement_geometry.gd").prefetch()
func model(id: int, frame_ms: int=32, parent: Node=null, full_detail: bool=true):
	if not registry.has(id): return null
	var visual := Model.new(); visual.library=library; visual.pack=pack;visual.use_replacement_geometry=full_detail; (self if parent==null else parent).add_child(visual); configure_model(visual,id,frame_ms)
	return visual
func configure_model(visual, id: int, frame_ms: int) -> void:
	if pack.enabled and preload("res://native/presentation/replacement_geometry.gd").entry_for(id).get("assembled_creature",false) and registry.has(id+1):
		visual.companion_resource=registry[id+1].model
	visual.modern_graphics=modern_graphics
	visual.configure(content.root,registry[id],frame_ms)
func release_object(entry: Dictionary) -> void:
	entry.visual.queue_free()
	if entry.secondary!=null: entry.secondary.queue_free()
func set_station_smoothing(value: bool) -> void:
	if library.station_smoothing==value:return
	library.station_smoothing=value
	refresh_station_filtering(self)

func refresh_station_filtering(parent: Node) -> void:
	for child in parent.get_children():
		if child is Model:child.refresh_station_filtering()
		else:refresh_station_filtering(child)

func rebuild() -> void:
	clear_player_clip()
	var keep_scene := revision>=0 and rendered_modern==modern_graphics and rendered_pack==pack.enabled
	var keep_player: bool=keep_scene and player_model!=null and int(player_model.record.id)==world.session.ship.id
	combat.reset(keep_player and not world.session.docked)
	previous_particle_fraction=world.accumulator
	if keep_scene:
		var shift: Vector3=rendered_anchor-world.geography.anchor
		for entry in neighbors.values():entry.root.position+=shift
		if rendered_station!=world.session.station_id:
			# Keep both the old station and its gate at their world positions.
			# Region entry changes the active gate, but a portal already in view
			# must not vanish and reappear on the other side of the station.
			var old_root:=Node3D.new();add_child(old_root);old_root.position=shift
			for node in station_nodes:node.reparent(old_root,false)
			for node in gate_nodes:
				if node.visible:
					node.reparent(old_root,false);node.set_meta("neighbor_gate",rendered_station)
					node.clock.frame=0;node.refresh()
					if node.has_meta("gate_surface"):
						node.get_meta("gate_surface").set_shader_parameter("opening",0.0)
						node.get_meta("gate_light").light_energy=0.0
				else:node.queue_free()
			gate_nodes=[]
			neighbors[rendered_station]={"root":old_root,"detail":true,"age":STREAM_FADE_SECONDS}
			station_nodes=[]
			if neighbors.has(world.session.station_id):
				var incoming: Dictionary=neighbors[world.session.station_id]
				for node in incoming.root.get_children():
					if not node is Model:continue
					if int(node.record.id)==15:node.queue_free();continue
					node.reparent(self,false);node.set_stream_visibility(1.0);station_nodes.append(node)
					node.set_full_detail(true)
					if not incoming.detail:
						add_station_collision(node);add_station_lights(node)
				incoming.root.queue_free();neighbors.erase(world.session.station_id)
	else:
		for entry in neighbors.values(): entry.root.queue_free()
		neighbors={}
		for node in station_nodes: node.queue_free()
		station_nodes=[]
	for node in gate_nodes: node.queue_free()
	gate_nodes=[]
	for entry in objects.values(): release_object(entry)
	objects={}
	if not keep_player:
		if player_model!=null: player_model.queue_free()
		player_model=model(world.session.ship.id)
	for node in limit_nodes: node.queue_free()
	limit_nodes=[]
	for i in 2:
		var panel := MeshInstance3D.new();var plane := PlaneMesh.new()
		plane.size=Vector2.ONE*LIMIT_EXTENT*2;panel.mesh=plane
		var surface := ShaderMaterial.new();surface.shader=preload("res://native/presentation/depth_limit.gdshader")
		surface.set_shader_parameter("half_extent",LIMIT_EXTENT);surface.set_shader_parameter("tint",LIMIT_TINTS[i]);panel.material_override=surface
		panel.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;panel.visible=false
		add_child(panel);limit_nodes.append(panel)
	if player_model!=null: player_model.apply_range(Model.ship_animation_range(world.session.ship.id,int(world.session.ship.upgraded)))
	for part in ([] if not station_nodes.is_empty() else world.region.station.parts):
		var visual=model(int(part.model_id),part.frame_ms)
		if visual==null: continue
		var pose=preload("res://native/simulation/ship_transform.gd").new(); pose.math.sine_table=world.region.sine; pose.origin=part.origin; pose.set_euler(0,part.yaw,0)
		visual.transform=Model.station_transform(pose.godot_transform())
		# The phone's modules overlap: bridges eighty metres long chained at a
		# sixty-three metre step, habitats sixty-nine metres tall stacked at
		# forty-five, a cap lying in the wall it meets. Its painter's order
		# never minded; a depth buffer sees the same plane twice and fights
		# over it. Each module is drawn a fraction smaller by a step that
		# differs from its neighbours', so no two overlapping faces share a
		# plane: at most a few centimetres over an eighty-metre module.
		visual.transform=visual.transform.scaled_local(Vector3.ONE*station_trim(station_nodes.size()))
		visual.configure_station(part)
		station_nodes.append(visual)
		add_station_collision(visual)
		if int(part.model_id)>=3300: add_station_lights(visual)
	for i in 2:
		var visual=model(15)
		if visual==null: continue
		var pose=preload("res://native/simulation/ship_transform.gd").new(); pose.math.sine_table=world.region.sine
		pose.origin=world.region.gates[i]; pose.set_euler(0,world.region.gate_yaw(i),0)
		visual.transform=pose.godot_transform(); gate_nodes.append(visual)
		visual.set_meta("gate_rest",visual.transform);visual.set_meta("gate_roll",0.0)
		build_gate_field(visual)
		visual.visible=world.region.gate_index(i)==i
	previous_time=world.region.elapsed_ms
	rendered_station=world.session.station_id;rendered_anchor=world.geography.anchor
	rendered_modern=modern_graphics;rendered_pack=pack.enabled
	revision=world.revision
	if not keep_scene: bake_shaders()

func bake_shaders() -> void:
	"""Every material variant the imported content can produce is compiled the
	first time something wearing it is drawn, and on a fresh install that is a
	stall of a tenth of a second to a second, paid mid-flight whenever a new
	kind of creature, shot or station module first turns up in view: it is the
	lag reported while looking around. Drawing the whole catalogue once, into a
	viewport nobody sees, moves all of that to the moment the scene is built.
	The lighting mode chooses the variants, so a mode change bakes again."""
	if oven!=null: oven.queue_free()
	oven=SubViewport.new();oven.size=Vector2i(32,32);oven.own_world_3d=true
	oven.render_target_update_mode=SubViewport.UPDATE_ALWAYS;oven.positional_shadow_atlas_size=256
	add_child(oven)
	var eye := Camera3D.new();oven.add_child(eye);eye.current=true;eye.fov=90;eye.far=4000;eye.position=Vector3(0,0,300)
	var surroundings := WorldEnvironment.new();surroundings.environment=get_viewport().find_world_3d().environment;oven.add_child(surroundings)
	# Shadowed lights of both kinds, so their shadow passes are baked too.
	var sun := DirectionalLight3D.new();sun.shadow_enabled=true;oven.add_child(sun)
	var lamp := OmniLight3D.new();lamp.shadow_enabled=true;lamp.omni_range=600;lamp.position=Vector3(0,80,120);oven.add_child(lamp)
	var spot := SpotLight3D.new();spot.shadow_enabled=true;spot.spot_range=600;spot.position=Vector3(0,0,200);oven.add_child(spot)
	for record in content.registry: model(int(record.id),32,oven,false)
	# The effect surfaces: shot trails and bursts, bubbles, the gate aperture,
	# lamp halos and the hull wake are drawn from pools that stay empty until
	# the first shot or the first station, and would compile then.
	var tube := CylinderMesh.new();tube.radial_segments=6;tube.rings=1
	var cone := CylinderMesh.new();cone.top_radius=0;cone.radial_segments=6;cone.rings=1
	for entry in [[tube,"combat_line"],[QuadMesh.new(),"combat_sprite"],[QuadMesh.new(),"bubble"],[QuadMesh.new(),"gate_field"],[QuadMesh.new(),"beacon"],[QuadMesh.new(),"vessel_wake"],[QuadMesh.new(),"particulate"],[cone,"headlight_beam"]]:
		var surface := MeshInstance3D.new();surface.mesh=entry[0]
		var material := ShaderMaterial.new();material.shader=load("res://native/presentation/%s.gdshader"%entry[1]);surface.material_override=material
		surface.custom_aabb=AABB(Vector3.ONE*-50,Vector3.ONE*100);oven.add_child(surface)
	var instanced := MultiMeshInstance3D.new();var pool := MultiMesh.new();pool.transform_format=MultiMesh.TRANSFORM_3D;pool.use_colors=true;pool.use_custom_data=true
	var quad := QuadMesh.new();var sprite := ShaderMaterial.new();sprite.shader=preload("res://native/presentation/combat_sprite.gdshader");quad.material=sprite;pool.mesh=quad
	pool.instance_count=1;instanced.multimesh=pool;instanced.custom_aabb=AABB(Vector3.ONE*-50,Vector3.ONE*100);oven.add_child(instanced)
	oven_frames=3

func _process(delta: float) -> void:
	if oven!=null:
		oven_frames-=1
		if oven_frames<=0: oven.queue_free();oven=null
	if world==null or world.region==null: return
	preload("res://native/presentation/replacement_geometry.gd").collect_ready()
	if revision!=world.revision: rebuild()
	var region=world.region
	camera.fov=lerpf(camera.fov,70.0 if region.player.boost_active and not region.cinematic() else 65.0,1-exp(-delta*5))
	neighbor_clock+=delta
	if neighbor_clock>0.1: neighbor_clock=0; stream_neighbors()
	shade_actor_beams()
	var ms: int = maxi(0,region.elapsed_ms-previous_time)
	previous_time=region.elapsed_ms
	camera.h_offset=0
	if player_model!=null: player_model.visible=not world.session.docked
	var player_pose: Transform3D = world.render_pose(region.player)
	if player_model!=null:
		# Brief steering bank is cosmetic; the camera uses the simulation attitude.
		banking.math.sine_table=region.sine; banking.set_euler(0,0,roundi(lerpf(world.previous_render_bank,region.player.visual_bank,clampf(world.accumulator/world.STEP_MS,0,1))))
		player_model.transform=player_pose*banking.godot_transform()
		animate_model(player_model,delta,region.player.throttle/100.0)
	place_depth_limits(player_pose.origin)
	var camera_scale: float=clampf(player_model.solid_bounds().size.x/24.0,.48,1.25) if player_model!=null else 1.0
	var camera_frame := player_pose
	if camera_mode==0:
		# Follow the simulation attitude through the poles. Reconstructing right
		# from world-up reverses it past 90 degrees and instantly flips the view.
		# Cosmetic steering bank remains confined to the model, not the camera.
		camera_frame.basis=player_pose.basis.orthonormalized()
		if player_model!=null:camera_frame.origin=player_model.global_transform*player_model.solid_bounds().get_center()
	if not look_held: look_offset=look_offset.lerp(Vector2.ZERO,1-exp(-delta*7))
	if look_offset.length_squared()>1e-6:
		camera_frame.basis=camera_frame.basis*Basis(Vector3.UP,look_offset.x)*Basis(Vector3.RIGHT,look_offset.y)
	var desired: Vector3 = camera_frame*([Vector3(0,18,45),Vector3(0,3,-56),Vector3(60,5,0),Vector3(-60,5,0)][camera_mode]*camera_scale)
	camera.global_position=desired
	camera.look_at(camera_frame*((Vector3(0,-24,-140) if camera_mode==0 else Vector3(0,3 if camera_mode==1 else 5,0))*camera_scale),camera_frame.basis.y.normalized())
	if not region.cinematic_camera.is_empty():
		camera.global_position=Library.point(region.cinematic_camera)
		var target: Vector3 = player_pose.origin
		match region.cinematic_target:
			"capsule": target=Library.point(region.enemies[-1].pose.origin)
			"station": target=Library.point(preload("res://native/simulation/fixed_math.gd").added(region.station.parts[0].origin,region.finale_station_offset))
			"friend0": target=Library.point(region.friends[0].pose.origin)
			"friend1": target=Library.point(region.friends[1].pose.origin)
		if camera.global_position.distance_squared_to(target)>0.01: camera.look_at(target,Vector3.UP)
	for i in station_nodes.size():
		station_nodes[i].position=Library.point(preload("res://native/simulation/fixed_math.gd").added(region.station.parts[i].origin,region.finale_station_offset))
		animate_model(station_nodes[i],delta,1.0)
	for i in gate_nodes.size():
		if not gate_nodes[i].visible:continue
		# at.a: a gate that is not open turns about its own axis, half a unit a
		# millisecond, a turn every eight seconds; it holds still while open.
		if world.gate_time[i]==0:
			var roll: float=fmod(float(gate_nodes[i].get_meta("gate_roll",0.0))+delta*512.0,4096.0)
			gate_nodes[i].set_meta("gate_roll",roll)
			var rest: Transform3D=gate_nodes[i].get_meta("gate_rest",gate_nodes[i].transform)
			gate_nodes[i].transform=Transform3D(rest.basis*Basis(Vector3(0,0,1),roll*TAU/4096.0),rest.origin)
		if gate_nodes[i].has_meta("gate_surface"):
			var distance: float=player_pose.origin.distance_to(gate_nodes[i].position)
			var opening := maxf(clampf(float(world.gate_frame(i))/20.0,0,1),clampf(1.0-distance/550.0,0,1)*.65)
			gate_nodes[i].get_meta("gate_surface").set_shader_parameter("opening",opening)
			gate_nodes[i].get_meta("gate_light").light_energy=opening*14.0
			gate_nodes[i].get_meta("gate_field_mesh").scale=Vector3.ONE*(1.0+opening*.45)
			# The gate carries the original's own effects: a flare at the aperture
			# and the trails that stream off the arms as they swing out. They are
			# drawn at the level the rest of the game's effects are toned to, which
			# leaves them invisible here, and the gate is the one place they are
			# the whole point. Set before the pose, and stepped, because a pose is
			# built once per key and cached under it.
			gate_nodes[i].effect_boost=snappedf(opening,.1)*GATE_EFFECT_BOOST
		gate_nodes[i].clock.frame=world.gate_frame(i); gate_nodes[i].refresh()
	for neighbor in neighbors.values():
		for node in neighbor.root.get_children():
			if not node is Model or not node.has_meta("neighbor_gate"):continue
			var roll: float=fmod(float(node.get_meta("gate_roll",0.0))+delta*512.0,4096.0)
			node.set_meta("gate_roll",roll)
			var rest: Transform3D=node.get_meta("gate_rest",node.transform)
			node.transform=Transform3D(rest.basis*Basis(Vector3(0,0,1),roll*TAU/4096.0),rest.origin)
			node.advance(ms)
	for neighbor in neighbors.values():
		neighbor.age=minf(STREAM_FADE_SECONDS,neighbor.age+delta)
		for part in neighbor.root.get_children():
			if part is Model:part.set_stream_visibility(smoothstep(0.0,STREAM_FADE_SECONDS,neighbor.age))
		if not neighbor.detail:continue
		for part in neighbor.root.get_children():
			if part is Model:
				animate_model(part,delta,1.0)
				if ms>0:part.advance(ms)
	if world.session.docked: update_docked_camera(delta)
	elif gate_preview and not gate_nodes.is_empty():
		var gate: Node3D=gate_nodes[world.departure_gate]
		# Framed on the gate at rest: its idle roll is the arms', not the shot's.
		var frame: Transform3D=gate.get_meta("gate_rest",gate.global_transform)
		camera.global_position=frame*Vector3(35,18,194)
		camera.look_at(frame.origin,Vector3.UP)
	if departure_progress>=0:
		var chase:=camera.global_transform
		camera.global_position=player_model.global_position+departure_frame.basis*Vector3(35,12,48)
		camera.look_at(player_pose.origin,Vector3.UP)
		camera.global_transform=camera.global_transform.interpolate_with(chase,smoothstep(.65,1.0,departure_progress))
	if transit_progress>=0 and player_model!=null:
		# Stand off to the side of the aperture so the submarine is seen entering
		# it, then hand the frame back to the ordinary chase once it is through.
		var following:=camera.global_transform
		# Coming out, start in front of the aperture so the submarine emerges
		# towards the viewer, then drift back beside the gate so it is seen
		# leaving for the station, which is where the chase camera takes over.
		var stand: Vector3=Vector3(96,28,transit_side*205)
		if transit_emerging:
			stand=Vector3(26,10,transit_side*105).lerp(Vector3(78,24,transit_side*40),smoothstep(0,.62,transit_progress))
			# A submarine thrown out of the aperture outruns a camera pinned to it
			# within a second, and the gate leaves frame while the shot is still
			# meant to be about it. Give up ground more slowly than the hull does,
			# so both stay in view for as long as the shot lasts.
			stand.z+=transit_side*absf((transit_frame.affine_inverse()*player_pose.origin).z)*.55
		camera.global_position=transit_frame.origin+transit_frame.basis*stand
		var subject: Vector3=player_pose.origin if transit_emerging else transit_frame.origin.lerp(player_pose.origin,.5)
		camera.look_at(subject,Vector3.UP)
		camera.global_transform=camera.global_transform.interpolate_with(following,smoothstep(.62,1.0,transit_progress))
	# A scripted shot (the opening) is laid over whatever the frame would have
	# been, and hands back to it by its blend, so the chase is where it lands.
	if cinematic_override:camera.global_transform=cinematic_transform.interpolate_with(camera.global_transform,cinematic_blend)
	previous_camera_mode=camera_mode
	var frustum: Array[Plane] = camera.get_frustum()
	for actor in region.creatures+region.enemies+region.friends:
		var id: int = actor.get_instance_id()
		if not objects.has(id) or objects[id].model_id!=actor.model_id:
			if objects.has(id): release_object(objects[id]); objects.erase(id)
			var visual=model(actor.model_id)
			if visual==null: continue
			objects[id]={"visual":visual,"model_id":actor.model_id,"secondary":null,"secondary_id":-1,"lamps":[],"reveal":0.0 if actor.is_creature else 1.0}
			# Headlights belong to vessels under way: a mine, a capsule, or the
			# wreck a ship becomes has nobody aboard to switch them on.
			if not actor.is_creature and actor.state<3 and (not (actor is SpecialActor) or actor.kind=="freighter"):
				objects[id].lamps=add_actor_lights(visual)
		var secondary_id: int = actor.secondary_model if actor.is_creature else -1
		if objects[id].visual.replacement!=null: secondary_id=-1
		if objects[id].secondary_id!=secondary_id:
			if objects[id].secondary!=null: objects[id].secondary.queue_free()
			objects[id].secondary=model(secondary_id) if secondary_id>=0 else null
			objects[id].secondary_id=secondary_id
		var node=objects[id].visual
		node.apply_actor_animation(actor)
		node.visible=actor.health.enabled or (actor.state==3 and not (actor is SpecialActor and actor.kind=="mine"))
		for lamp in objects[id].lamps:lamp.visible=actor.health.enabled and actor.state<3
		if actor.is_creature:
			# Newly set down, or new to the view, a creature is brought in out
			# of the haze the way a streamed station is, not switched on.
			if actor.fresh:objects[id].reveal=0.0;actor.fresh=false
			if objects[id].reveal<1.0:
				objects[id].reveal=minf(1.0,objects[id].reveal+delta/CREATURE_FADE_SECONDS)
				node.set_stream_visibility(smoothstep(0.0,1.0,objects[id].reveal))
				if objects[id].secondary!=null:objects[id].secondary.set_stream_visibility(smoothstep(0.0,1.0,objects[id].reveal))
		var pose: Transform3D = world.render_pose(actor)
		var rendered_body: Transform3D = pose
		if actor.is_creature and not actor.render_tilt.all(func(v):return v==0):
			# The swing is a turn in the game's own frame, as the second part's
			# is, so the two parts turn together.
			pose.basis=pose.basis*Library.SIM_FLIP*Basis.from_euler(Vector3(actor.render_tilt[0],actor.render_tilt[1],actor.render_tilt[2])*TAU/4096.0,EULER_ORDER_XYZ)*Library.SIM_FLIP
		if not (node.replacement!=null and actor.model_id==4422):
			pose.basis=pose.basis.scaled_local(Vector3(actor.render_scale[0],actor.render_scale[1],actor.render_scale[2])/4096.0)
		var travel_speed: float = node.position.distance_to(pose.origin)/maxf(delta,.001)
		if node.transform!=pose: node.transform=pose
		if not actor.is_creature:
			var moving: float=clampf(travel_speed/20.0,0,1) if actor.health.enabled and actor.state<3 else 0.0
			if camera.global_position.distance_to(node.global_position)>600: moving=0.0
			animate_model(node,delta,moving)
		var secondary=objects[id].secondary
		if secondary!=null:
			secondary.visible=node.visible
			# Enhanced graphics bend the part at the join rather than turning
			# it whole, which opened a wedge between a head and its body. The
			# game's yaw unit is a turn about -Y in Godot space, pitch about +X.
			var bent: bool=modern_graphics and actor.hinge_axis!=""
			# The part is placed from the body as rendered - interpolated
			# between steps like the body - by its turn relative to the body's
			# own pose, or a swimming fish's head lagged a step behind it.
			var body: Transform3D=actor.pose.godot_transform()
			var relative: Basis=body.basis.orthonormalized().inverse()*(actor.hinge_pose if bent else actor.secondary_pose).godot_transform().basis
			var secondary_pose := Transform3D(rendered_body.basis.orthonormalized()*relative,rendered_body.origin)
			secondary_pose.basis=secondary_pose.basis.scaled_local(Vector3(actor.secondary_scale[0],actor.secondary_scale[1],actor.secondary_scale[2])/4096.0)
			secondary.transform=secondary_pose
			if bent:secondary.set_hinge(1 if actor.hinge_axis=="yaw" else 0,(-1.0 if actor.hinge_axis=="yaw" else 1.0)*actor.hinge_angle*TAU/4096.0)
			else:secondary.set_hinge(1,0.0)
		if ms>0:
			var distance: float = camera.global_position.distance_to(node.global_position)
			var on_screen: bool = distance<150 or frustum.all(func(plane): return plane.distance_to(node.global_position)<150)
			# Clocks and movement stay exact. Small distant fin/thruster poses use
			# staggered 80 ms visual samples; nearby interaction poses use 40 ms.
			var sample_pose: bool = distance<250 or (region.elapsed_ms/40+id)%2==0
			node.advance(ms,node.visible and distance<1500 and on_screen and sample_pose)
			if secondary!=null: secondary.advance(ms,secondary.visible and distance<1500 and on_screen and sample_pose)
	if ms>0:
		for node in station_nodes: node.advance(ms)
		if player_model!=null: player_model.advance(ms)
	# The camera interpolates between fixed ticks; the wake must use the same
	# fractional clock or it stands still then jumps relative to the ship.
	var particle_ms := maxf(0,float(ms)+world.accumulator-previous_particle_fraction)
	previous_particle_fraction=world.accumulator
	combat.update(region,ms,delta*1000 if departure_progress>=0 else particle_ms)

static func station_trim(index: int) -> float:
	return 1.0-0.002*(1+(index%3))

func set_depth_limits(on: bool) -> void:
	depth_limits=on
	for node in limit_nodes: node.visible=false

func place_depth_limits(under: Vector3) -> void:
	"""As bb keeps its panels: at the submarine's own x and z, at the height
	where its depth reads the ship's limit. Shallower is up, so the panel for
	the minimum depth rides above the hull and the maximum's below it, and
	each shows only as the hull comes within the last stretch of water."""
	if limit_nodes.size()<2: return
	var player=world.region.player
	var limits: Array=[player.stats.minimum_depth,player.stats.maximum_depth]
	for i in 2:
		var node: MeshInstance3D=limit_nodes[i]
		var height: float=float(player.station_depth-limits[i])*8.0*Library.UNIT
		var strength: float=clampf(1.0-absf(height-under.y)/LIMIT_FADE,0.0,1.0)
		node.visible=depth_limits and not world.session.docked and strength>0.0
		if not node.visible: continue
		node.position=Vector3(under.x,height,under.z)
		node.material_override.set_shader_parameter("strength",strength)

func build_gate_field(node: Node3D) -> void:
	"""The lit aperture inside the gate frame. gate_field.gdshader has been in the
	tree since preview.2 with nothing to draw it on, which is why a gate has been
	a dark hole: the energy in the middle and the glow around it both come from
	here. The sheet lies in the gate's own plane, so it foreshortens with the
	frame; a camera-facing one keeps its full width when the gate is edge-on and
	stands out beside the aperture instead of inside it."""
	# Sized from the frame that is actually modelled; the crossing radius is a
	# generous gameplay tolerance, several times the visible opening. The opening
	# is centred on the model origin, which is what the arms turn about. Its
	# bounding box is not: housing hangs below the triangle and pulls the box
	# centre a half-radius low, which is where the glow was sitting.
	var span: AABB=node.solid_bounds()
	var reach: float=maxf(maxf(absf(span.position.x),absf(span.end.x)),maxf(absf(span.position.y),absf(span.end.y)))
	var radius: float=maxf(6.0,reach*.5)
	var mesh := QuadMesh.new()
	mesh.size=Vector2.ONE*radius*2.4
	var surface := MeshInstance3D.new()
	surface.mesh=mesh
	var material := ShaderMaterial.new()
	material.shader=preload("res://native/presentation/gate_field.gdshader")
	surface.material_override=material
	surface.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(surface)
	var light := OmniLight3D.new()
	light.light_color=Color("a9ecff")
	light.omni_range=460.0
	light.light_energy=0.0
	node.add_child(light)
	node.set_meta("gate_surface",material)
	node.set_meta("gate_light",light)
	node.set_meta("gate_field_mesh",surface)
func animate_model(node,delta: float,power: float,opening: float=0.0) -> void:
	if node.replacement!=null and node.replacement.has_meta("motion"):
		node.replacement.get_meta("motion").animate(delta,power,opening)

func stream_neighbors() -> void:
	var global_eye: Vector3 = camera.global_position+world.geography.anchor
	var wanted: Array = []
	var distances := {}
	for station in world.session.stations:
		if station.id==world.session.station_id: continue
		var distance := Library.point(world.station_origin(station.id)).distance_to(global_eye)
		distances[station.id]=distance
		if distance<=DRAW_DISTANCE or (neighbors.has(station.id) and distance<STREAM_RELEASE_DISTANCE):wanted.append(station.id)
	for id in neighbors.keys():
		if not id in wanted:neighbors[id].root.queue_free();neighbors.erase(id)
	# No four-station cap. Fill nearest-first, one station per update, and keep
	# detail changes outside a hysteresis band to avoid rebuilding on every turn.
	wanted.sort_custom(func(a,b):return distances[a]<distances[b])
	for id in wanted:
		var detailed: bool=distances[id]<DETAIL_DISTANCE or (neighbors.has(id) and neighbors[id].detail and distances[id]<DETAIL_RELEASE_DISTANCE)
		if neighbors.has(id):
			if neighbors[id].detail==detailed:continue
			# Retain the same imported mesh and animation on both sides of the band.
			# Only lighting/collision changes; no silhouette or material swap.
			for visual in neighbors[id].root.get_children():
				if visual is Model and int(visual.record.id)==15:continue
				if detailed:
					visual.set_full_detail(true)
					add_station_collision(visual)
					if int(visual.record.id)>=3300:add_station_lights(visual)
				else:
					# The lamp points keep their lights: those fade out with
					# distance on their own, and come back with the band.
					for detail in visual.find_children("*","StaticBody3D",true,false)+visual.find_children("*","Light3D",true,false):
						if detail.get_parent().name!="Lamp":detail.queue_free()
					visual.remove_meta("station_lights")
			neighbors[id].detail=detailed
			break
		var root := Node3D.new();add_child(root)
		root.position=Library.point(world.station_origin(id))-world.geography.anchor
		var body=preload("res://native/simulation/station_body.gd").new();body.configure(world.session.stations[id],world.session.is_colonist_station(id),world.region.sine,world.session.data.get("station_geometry",{}))
		for part in body.parts:
			# Distant stations reuse the compact source mesh with the selected
			# material pack. Full models, light rigs and triangle colliders are near-only.
			var visual=model(int(part.model_id),part.frame_ms,root,detailed)
			if visual==null:continue
			var pose=preload("res://native/simulation/ship_transform.gd").new();pose.math.sine_table=world.region.sine;pose.set_euler(0,part.yaw,0);pose.origin=part.origin
			visual.transform=Model.station_transform(pose.godot_transform())
			visual.set_stream_visibility(0.0)
			if detailed:
				add_station_collision(visual)
				if int(part.model_id)>=3300:add_station_lights(visual)
			visual.configure_station(part)
		var gates: Array=preload("res://native/simulation/region.gd").gate_positions(world.session.stations[id],world.region.sine)
		for i in gates.size():
			if i==1 and gates[i]==gates[0]:continue
			var portal=model(15,32,root,true)
			if portal==null:continue
			var pose=preload("res://native/simulation/ship_transform.gd").new()
			pose.math.sine_table=world.region.sine;pose.origin=gates[i]
			pose.set_euler(0,preload("res://native/simulation/region.gd").gate_yaw_for(world.session.stations[id],i),0)
			portal.transform=pose.godot_transform()
			portal.set_meta("neighbor_gate",id);portal.set_meta("gate_rest",portal.transform);portal.set_meta("gate_roll",0.0)
			portal.set_stream_visibility(0.0)
		if neighbors.has(id):neighbors[id].root.queue_free()
		neighbors[id]={"root":root,"detail":detailed,"age":0.0}
		break

func add_station_lights(visual) -> void:
	if not modern_graphics or visual.has_meta("station_lights"):return
	visual.set_meta("station_lights",true)
	# Habitats light the adjoining bridges as one structure. Avoid a pair of
	# overlapping lights on every small connector (especially on WebGL).
	if int(visual.record.id) not in [3305,3306,3307,3308,3309,3310]:return
	var box: AABB=visual.solid_bounds()
	var center := box.get_center()
	var reach := clampf(box.size.length()*.8,100.0,155.0)
	for side in [-1,1]:
		var lamp := OmniLight3D.new();visual.add_child(lamp)
		# One overhead work lamp, one lower service lamp: light the walls and
		# adjoining bridges instead of pooling both highlights on the roof.
		# Local space is the rolled module's: overhead in the world is local -y.
		lamp.position=center+Model.STATION_ROLL.basis*Vector3(side*box.size.x*.32,box.size.y*(.62 if side==-1 else -.12),side*box.size.z*.64)
		lamp.light_color=Color("ffd39a") if side==-1 else Color("ffbc76")
		lamp.light_energy=8.0 if side==-1 else 6.0
		# No light size: a size turns on contact-hardening (PCSS) shadows, which
		# add a blocker search per pixel for every lamp covering it. With a
		# dozen habitats in range that was a fifth of the frame at 5K, and the
		# plain soft filter is indistinguishable on these walls.
		lamp.light_size=0.0
		lamp.omni_range=reach;lamp.omni_attenuation=.85
		lamp.shadow_enabled=true;lamp.shadow_bias=.08;lamp.shadow_normal_bias=.6
		lamp.light_volumetric_fog_energy=.3
		lamp.distance_fade_enabled=true;lamp.distance_fade_begin=650;lamp.distance_fade_length=300
		var halo := MeshInstance3D.new();var quad := QuadMesh.new();quad.size=Vector2(4,4)
		var material := ShaderMaterial.new();material.shader=preload("res://native/presentation/beacon.gdshader")
		material.set_shader_parameter("tint",lamp.light_color);quad.material=material;halo.mesh=quad
		halo.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;lamp.add_child(halo)

# Other vessels carry the same lamps and beams as the player's hull. Their
# beams are shadowed one per frame in turn, which keeps the raycasts cheap.
var actor_beams: Array = []
var actor_beams_enabled := true
var actor_beam_phase := 0
func add_actor_lights(visual) -> Array:
	var lamps: Array=[]
	if not modern_graphics:return lamps
	var mounts: Array=visual.headlight_mounts()
	for i in mini(2,mounts.size()):
		var lamp: SpotLight3D=Abyss.create_headlight(0.0);visual.add_child(lamp)
		# A positive turn about +Y swings -Z towards -X: the port lamp turns outward.
		lamp.transform=Transform3D(Basis(Vector3.UP,deg_to_rad(12 if i==0 else -12)),mounts[i])
		lamp.shadow_enabled=false
		lamp.distance_fade_enabled=true;lamp.distance_fade_begin=400;lamp.distance_fade_length=200
		var beam: MeshInstance3D=Abyss.create_beam();lamp.add_child(beam)
		beam.material_override.set_shader_parameter("fade_begin",400.0);beam.material_override.set_shader_parameter("fade_length",200.0)
		beam.visible=actor_beams_enabled
		actor_beams.append({"lamp":lamp,"beam":beam});lamps.append(lamp)
	return lamps

func set_actor_beams(on: bool) -> void:
	actor_beams_enabled=on
	actor_beams=actor_beams.filter(func(entry):return is_instance_valid(entry.lamp) and is_instance_valid(entry.beam))
	for entry in actor_beams: entry.beam.visible=on

func shade_actor_beams() -> void:
	# One vessel's beam per frame, nearest the camera first would be nicer;
	# in turn is enough, a wall is current within a few frames.
	actor_beams=actor_beams.filter(func(entry):return is_instance_valid(entry.lamp) and is_instance_valid(entry.beam))
	if actor_beams.is_empty() or not actor_beams_enabled:return
	actor_beam_phase+=1
	var entry: Dictionary=actor_beams[actor_beam_phase%actor_beams.size()]
	if not entry.lamp.is_visible_in_tree() or entry.lamp.global_position.distance_to(camera.global_position)>700: return
	Abyss.shade_beam_in(get_world_3d().direct_space_state,entry.lamp,entry.beam,actor_beam_phase/actor_beams.size())

func add_station_collision(visual: Node3D) -> void:
	# Actual replacement triangles serve the reticle and light obstruction rays.
	var geometry: Node3D=visual.replacement if visual.replacement!=null else visual.figure
	if geometry==null:return
	for mesh in preload("res://native/presentation/replacement_geometry.gd").all_meshes(geometry):
		mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
		
		var body := StaticBody3D.new(); body.collision_layer=2; body.collision_mask=0
		var shape := CollisionShape3D.new(); shape.shape=mesh.mesh.create_trimesh_shape();shape.shape.backface_collision=true
		mesh.add_child(body);body.add_child(shape)

func looking_around() -> bool:
	return look_offset.length()>.02

func turn_look(relative: Vector2) -> void:
	# Mouse right swings the camera round to the hull's starboard side, mouse
	# up lifts it; the pitch stops short of the poles.
	look_offset.x=wrapf(look_offset.x+relative.x,-PI,PI)
	look_offset.y=clampf(look_offset.y+relative.y,-1.25,1.25)

func aim_point():
	# Only the chase camera looks where the launchers point. The front and
	# side views look back at, or across, the submarine: a shot converged on
	# their screen centre leaves the hull backwards or sideways. With no aim
	# the weapons fire straight ahead, which is what the original always did.
	if camera_mode!=0 or departure_progress>=0 or transit_progress>=0 or not world.region.cinematic_camera.is_empty() or looking_around(): return null
	var center := camera.get_viewport().get_visible_rect().size*.5
	var origin := camera.project_ray_origin(center)
	var direction := camera.project_ray_normal(center).normalized()
	# The chase camera sits behind the ship. Ignore intersections before the
	# launchers, including the near face of a nearby actor's collision bounds.
	var minimum_distance := camera.near
	# With nothing under the reticle, converge where the shots run out rather
	# than a kilometre beyond it, so a burst into open water ends on the
	# reticle instead of visibly short of it; the launchers sit under the eye.
	var distance := 0.0
	for weapon in world.region.loadout.all_weapons():
		var pose=world.region.player.pose
		var muzzle: Vector3=Library.point(preload("res://native/simulation/fixed_math.gd").added(pose.origin,pose.rotate_direction(weapon.mount)))
		minimum_distance=maxf(minimum_distance,(muzzle-origin).dot(direction)+1.0)
		distance=maxf(distance,weapon.speed*weapon.lifetime*.01)
	distance=clampf(distance,200.0,1800.0)
	var query := PhysicsRayQueryParameters3D.create(origin,origin+direction*distance,2)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() and origin.distance_to(hit.position)>=minimum_distance: distance=origin.distance_to(hit.position)
	# Actors use the exact same capture / damage bounds as the simulation.
	for actor in world.region.creatures+world.region.enemies+world.region.friends:
		if not actor.health.enabled: continue
		var point: Vector3 = world.render_pose(actor).origin
		var radius: float=maxf(.5,float(actor.radius)*.01)
		var hit_point = AABB(point-Vector3.ONE*radius,Vector3.ONE*radius*2).intersects_ray(origin,direction)
		if hit_point is Vector3:
			var t: float = (hit_point-origin).dot(direction)
			if t>=minimum_distance and t<distance: distance=t

	var point := origin+direction*distance
	return [roundi(point.x*100),roundi(-point.y*100),roundi(-point.z*100)]

func begin_transit(frame: Transform3D, side: float) -> void:
	transit_frame=frame;transit_side=side;transit_progress=0.0;transit_emerging=false
func end_transit() -> void:
	transit_progress=-1.0;transit_emerging=false
func begin_departure() -> void:
	departure_hangar=null
	for station in station_nodes:
		if station.is_hangar():departure_hangar=station;break
	if departure_hangar==null:return
	var aperture:AABB=departure_hangar.hangar_aperture()
	# The door's centre is read through the module's roll; the shot's frame
	# keeps the station's own upright basis, so the camera sits above the berth.
	departure_frame=Transform3D((departure_hangar.global_transform*Model.STATION_ROLL).basis,departure_hangar.global_transform*aperture.get_center())
	var direction:=departure_frame.basis.z.normalized()
	var hull:AABB=player_model.solid_bounds()
	# The whole hull starts inside the berth, its nose a little behind the
	# door, so the lamps on the nose come on as it crosses the sill, not
	# while the door is still opening.
	departure_start=departure_frame.origin-direction*hull.size.z*1.1
	# A few of the original's layouts hang a module across the berth's line
	# of exit. Run the shot up to the last clear water before it instead of
	# through it; the hull then starts its dive from there.
	var reach: float=105+hull.size.z
	var probe: float=hull.size.z
	while probe<reach:
		var point: Vector3=departure_frame.origin+direction*(probe+hull.size.z*.5)
		# The hangar's own box reaches past its door; only another module counts.
		if world.region.station.contains([roundi(point.x*100),roundi(-point.y*100),roundi(-point.z*100)]) and world.region.station.contact!=0:
			reach=maxf(hull.size.z,probe-4.0);break
		probe+=2.0
	departure_end=departure_frame.origin+direction*reach
	world.region.player.pose.face([roundi(direction.x*4096),roundi(-direction.y*4096),roundi(-direction.z*4096)])
	place_departure(0)
func place_departure(progress: float) -> void:
	departure_progress=progress
	if not is_instance_valid(departure_hangar):return
	departure_hangar.set_hangar_open(smoothstep(0,.18,progress)*(1.0-smoothstep(.72,1.0,progress)))
	var travel:=smoothstep(.18,1.0,progress)
	var at:=departure_start.lerp(departure_end,travel)
	world.region.player.pose.origin=[roundi(at.x*100),roundi(-at.y*100),roundi(-at.z*100)]
	# Hide only the portion still inside the hangar, until the stern clears.
	if progress<.72:clip_player_at_gate(departure_frame,1)
	else:clear_player_clip()
	world.previous_render_poses.clear()

func update_docked_camera(delta: float) -> void:
	var bounds := AABB();var first := true
	for station in station_nodes:
		var box: AABB=station.transform*station.solid_bounds()
		bounds=box if first else bounds.merge(box);first=false
	if first: return
	var focus := bounds.get_center()
	var radius := maxf(180,bounds.size.length()*.78)
	var height := radius*.23
	if menu_backdrop:
		# ck's first path: a circle of the station once a minute, two hundred
		# metres out, climbing and sinking by a quarter of that on the way.
		dock_orbit+=delta*TAU/60.0
		radius=maxf(200,bounds.size.length()*.9)
		height=sin(dock_orbit*2.0)*radius*.25
	else:dock_orbit+=delta*.055
	camera.global_position=focus+Vector3(sin(dock_orbit)*radius,height,cos(dock_orbit)*radius)
	camera.look_at(focus,Vector3.UP)
	# Leave the left side clear for the original-style dock menu.
	camera.h_offset=-radius*(.3 if menu_backdrop else .22)
	if player_model!=null: player_model.hide()

func assign_player_basis(basis: Basis) -> void:
	var pose=world.region.player.pose
	pose.right=[roundi(basis.x.x*4096),roundi(-basis.x.y*4096),roundi(-basis.x.z*4096)]
	pose.up=[roundi(-basis.y.x*4096),roundi(basis.y.y*4096),roundi(basis.y.z*4096)]
	pose.forward=[roundi(-basis.z.x*4096),roundi(basis.z.y*4096),roundi(basis.z.z*4096)]
# The gate or hangar plane the hull is clipped by while it passes through,
# for the headlight beams to be clipped by as well: no light without a lamp.
var player_clip_enabled := false
var player_clip_plane := Vector4.ZERO
func clear_player_clip() -> void:
	player_clip_enabled=false
	if player_model!=null:player_model.set_portal_clip(false)
	for entry in portal_materials:
		if is_instance_valid(entry.mesh):entry.mesh.set_surface_override_material(entry.index,entry.previous)
	portal_materials.clear()
func clip_player_at_gate(frame: Transform3D, side: float) -> void:
	if player_model==null:return
	var clip_normal:=frame.basis.z.normalized()*side
	player_clip_enabled=true;player_clip_plane=Vector4(clip_normal.x,clip_normal.y,clip_normal.z,-clip_normal.dot(frame.origin))
	if player_model.replacement==null:
		var normal:=frame.basis.z.normalized()*side
		player_model.set_portal_clip(true,Vector4(normal.x,normal.y,normal.z,-normal.dot(frame.origin)))
		return
	if portal_materials.is_empty():
		for mesh in preload("res://native/presentation/replacement_geometry.gd").all_meshes(player_model.replacement):
			for index in mesh.mesh.get_surface_count():
				var original=mesh.get_active_material(index)
				var material:=ShaderMaterial.new();material.shader=preload("res://native/presentation/portal_surface.gdshader")
				if original is ShaderMaterial:
					material.set_shader_parameter("tint",original.get_shader_parameter("surface_tint"))
					material.set_shader_parameter("albedo_map",original.get_shader_parameter("surface_albedo"));material.set_shader_parameter("textured",true)
				elif original is StandardMaterial3D:
					material.set_shader_parameter("tint",original.albedo_color);material.set_shader_parameter("textured",original.albedo_texture!=null)
					if original.albedo_texture!=null:material.set_shader_parameter("albedo_map",original.albedo_texture)
					material.set_shader_parameter("metallic_value",original.metallic);material.set_shader_parameter("roughness_value",original.roughness)
					if original.emission_enabled:material.set_shader_parameter("emission_color",original.emission*original.emission_energy_multiplier)
				portal_materials.append({"mesh":mesh,"index":index,"previous":mesh.get_surface_override_material(index),"material":material})
				mesh.set_surface_override_material(index,material)
	var normal:=frame.basis.z.normalized()*side
	for entry in portal_materials:entry.material.set_shader_parameter("clip_plane",Vector4(normal.x,normal.y,normal.z,-normal.dot(frame.origin)))
