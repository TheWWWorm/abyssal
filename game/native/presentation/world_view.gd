extends Node3D
const SpecialActor = preload("res://native/simulation/special_actor.gd")
const DRAW_DISTANCE := 10000.0
const DETAIL_DISTANCE := 2200.0
const DETAIL_RELEASE_DISTANCE := 2600.0
const STREAM_RELEASE_DISTANCE := 10500.0
const STREAM_FADE_SECONDS := 1.2

static func far_visibility(distance: float) -> float:
	return 1.0-smoothstep(7000.0,9600.0,distance)

const Model = preload("res://native/presentation/model.gd")
const Library = preload("res://scripts/model_library.gd")
var world
var content
var camera: Camera3D
const CAMERA_NAMES := ["Chase","Front","Starboard","Port"]
var camera_mode := 0
var previous_camera_mode := -1
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
var banking := preload("res://native/simulation/ship_transform.gd").new()
var gate_preview := false
var departure_hangar
var departure_frame := Transform3D.IDENTITY
var departure_progress := -1.0
var departure_start := Vector3.ZERO
var departure_end := Vector3.ZERO
var portal_materials: Array=[]
var dock_orbit := .65
var previous_time := 0
var previous_particle_fraction := 0.0
var combat := preload("res://native/presentation/combat_effects.gd").new()
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
			# Transfer the old local station into the streamed set, retaining its
			# meshes and opacity. Do not clear the entire ocean on region entry.
			var old_root:=Node3D.new();add_child(old_root);old_root.position=shift
			for node in station_nodes:node.reparent(old_root,false)
			neighbors[rendered_station]={"root":old_root,"detail":true,"age":STREAM_FADE_SECONDS}
			station_nodes=[]
			if neighbors.has(world.session.station_id):
				var incoming: Dictionary=neighbors[world.session.station_id]
				for node in incoming.root.get_children():
					if not node is Model:continue
					node.reparent(self,false);node.set_stream_visibility(1.0);station_nodes.append(node)
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
	if player_model!=null: player_model.apply_range(Model.ship_animation_range(world.session.ship.id,int(world.session.ship.upgraded)))
	for part in ([] if not station_nodes.is_empty() else world.region.station.parts):
		var visual=model(int(part.model_id),part.frame_ms)
		if visual==null: continue
		var pose=preload("res://native/simulation/ship_transform.gd").new(); pose.math.sine_table=world.region.sine; pose.origin=part.origin; pose.set_euler(0,part.yaw,0)
		visual.transform=pose.godot_transform()
		visual.configure_station(part)
		station_nodes.append(visual)
		add_station_collision(visual)
		if int(part.model_id)>=3300: add_station_lights(visual)
	for i in 2:
		var visual=model(15)
		if visual==null: continue
		var pose=preload("res://native/simulation/ship_transform.gd").new(); pose.math.sine_table=world.region.sine
		pose.origin=world.region.gates[i]; pose.set_euler(0,(300 if world.session.stations[world.session.station_id].tech>4 else -300)*(i+1)+2048,0)
		visual.transform=pose.godot_transform(); gate_nodes.append(visual)
		visual.visible=world.region.gate_index(i)==i
	previous_time=world.region.elapsed_ms
	rendered_station=world.session.station_id;rendered_anchor=world.geography.anchor
	rendered_modern=modern_graphics;rendered_pack=pack.enabled
	revision=world.revision
func _process(delta: float) -> void:
	if world==null or world.region==null: return
	preload("res://native/presentation/replacement_geometry.gd").collect_ready()
	if revision!=world.revision: rebuild()
	var region=world.region
	camera.fov=lerpf(camera.fov,70.0 if region.player.boost_active and not region.cinematic() else 65.0,1-exp(-delta*5))
	neighbor_clock+=delta
	if neighbor_clock>0.1: neighbor_clock=0; stream_neighbors()
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
	var camera_scale: float=clampf(player_model.solid_bounds().size.x/24.0,.48,1.25) if player_model!=null else 1.0
	var camera_frame := player_pose
	if camera_mode==0:
		# Follow the simulation attitude through the poles. Reconstructing right
		# from world-up reverses it past 90 degrees and instantly flips the view.
		# Cosmetic steering bank remains confined to the model, not the camera.
		camera_frame.basis=player_pose.basis.orthonormalized()
		if player_model!=null:camera_frame.origin=player_model.global_transform*player_model.solid_bounds().get_center()
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
		gate_nodes[i].clock.frame=world.gate_frame(i); gate_nodes[i].refresh()
		var gate=gate_nodes[i].replacement
		if gate!=null and gate.has_meta("gate_surface"):
			var distance: float=player_pose.origin.distance_to(gate_nodes[i].position)
			var opening := maxf(clampf(float(world.gate_frame(i))/20.0,0,1),clampf(1.0-distance/550.0,0,1)*.65)
			gate.get_meta("gate_surface").set_shader_parameter("opening",opening)
			gate.get_meta("gate_light").light_energy=opening*14.0
			if gate.has_meta("gate_field_mesh"):gate.get_meta("gate_field_mesh").scale=Vector3.ONE*(1.0+opening*.45)
			animate_model(gate_nodes[i],delta,1.0,opening)
			gate.rotation.z+=delta*(.10+opening*.55)
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
		var frame := gate.global_transform
		camera.global_position=frame*Vector3(35,18,194)
		camera.look_at(frame.origin,Vector3.UP)
	if departure_progress>=0:
		var chase:=camera.global_transform
		camera.global_position=player_model.global_position+departure_frame.basis*Vector3(35,12,48)
		camera.look_at(player_pose.origin,Vector3.UP)
		camera.global_transform=camera.global_transform.interpolate_with(chase,smoothstep(.65,1.0,departure_progress))
	previous_camera_mode=camera_mode
	var frustum: Array[Plane] = camera.get_frustum()
	for actor in region.creatures+region.enemies+region.friends:
		var id: int = actor.get_instance_id()
		if not objects.has(id) or objects[id].model_id!=actor.model_id:
			if objects.has(id): release_object(objects[id]); objects.erase(id)
			var visual=model(actor.model_id)
			if visual==null: continue
			objects[id]={"visual":visual,"model_id":actor.model_id,"secondary":null,"secondary_id":-1}
			if not actor.is_creature: add_actor_lights(visual)
		var secondary_id: int = actor.secondary_model if actor.is_creature else -1
		if objects[id].visual.replacement!=null: secondary_id=-1
		if objects[id].secondary_id!=secondary_id:
			if objects[id].secondary!=null: objects[id].secondary.queue_free()
			objects[id].secondary=model(secondary_id) if secondary_id>=0 else null
			objects[id].secondary_id=secondary_id
		var node=objects[id].visual
		node.apply_actor_animation(actor)
		node.visible=actor.health.enabled or (actor.state==3 and not (actor is SpecialActor and actor.kind=="mine"))
		var pose: Transform3D = world.render_pose(actor)
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
			var secondary_pose: Transform3D = actor.secondary_pose.godot_transform()
			secondary_pose.basis=secondary_pose.basis.scaled_local(Vector3(actor.secondary_scale[0],actor.secondary_scale[1],actor.secondary_scale[2])/4096.0)
			secondary.transform=secondary_pose
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
				if detailed:
					add_station_collision(visual)
					if int(visual.record.id)>=3300:add_station_lights(visual)
				else:
					for detail in visual.find_children("*","StaticBody3D",true,false)+visual.find_children("*","Light3D",true,false):detail.queue_free()
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
			visual.transform=pose.godot_transform()
			visual.set_stream_visibility(0.0)
			if detailed:
				add_station_collision(visual)
				if int(part.model_id)>=3300:add_station_lights(visual)
			visual.configure_station(part)
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
		lamp.position=center+Vector3(side*box.size.x*.32,box.size.y*(.62 if side==-1 else -.12),side*box.size.z*.64)
		lamp.light_color=Color("ffd39a") if side==-1 else Color("ffbc76")
		lamp.light_energy=8.0 if side==-1 else 6.0
		lamp.light_size=1.5
		lamp.omni_range=reach;lamp.omni_attenuation=.85
		lamp.shadow_enabled=true;lamp.shadow_bias=.08;lamp.shadow_normal_bias=.6
		lamp.light_volumetric_fog_energy=.3
		lamp.distance_fade_enabled=true;lamp.distance_fade_begin=650;lamp.distance_fade_length=300
		var halo := MeshInstance3D.new();var quad := QuadMesh.new();quad.size=Vector2(4,4)
		var material := ShaderMaterial.new();material.shader=preload("res://native/presentation/beacon.gdshader")
		material.set_shader_parameter("tint",lamp.light_color);quad.material=material;halo.mesh=quad
		halo.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;lamp.add_child(halo)

func add_actor_lights(visual) -> void:
	if not modern_graphics:return
	var mounts: Array=visual.replacement.get_meta("headlight_mounts",[]) if visual.replacement!=null else []
	if mounts.is_empty():
		var box: AABB=visual.solid_bounds()
		for side in [-1,1]:mounts.append(Vector3(box.get_center().x+side*box.size.x*.34,box.get_center().y,box.position.z-.5))
	for point in mounts.slice(0,2):
		var lamp := SpotLight3D.new();visual.add_child(lamp);lamp.position=point
		lamp.light_color=Color("b4e9f2");lamp.light_energy=9.0;lamp.spot_range=200
		lamp.spot_angle=8;lamp.spot_attenuation=1.4;lamp.light_volumetric_fog_energy=.5
		lamp.distance_fade_enabled=true;lamp.distance_fade_begin=220;lamp.distance_fade_length=100

func add_station_collision(visual: Node3D) -> void:
	# Actual replacement triangles serve the reticle and light obstruction rays.
	var geometry: Node3D=visual.replacement if visual.replacement!=null else visual.figure
	if geometry==null:return
	for mesh in preload("res://native/presentation/replacement_geometry.gd").all_meshes(geometry):
		mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
		
		var body := StaticBody3D.new(); body.collision_layer=2; body.collision_mask=0
		var shape := CollisionShape3D.new(); shape.shape=mesh.mesh.create_trimesh_shape();shape.shape.backface_collision=true
		mesh.add_child(body);body.add_child(shape)

func aim_point() -> Array:
	var center := camera.get_viewport().get_visible_rect().size*.5
	var origin := camera.project_ray_origin(center)
	var direction := camera.project_ray_normal(center).normalized()
	# The chase camera sits behind the ship. Ignore intersections before the
	# launchers, including the near face of a nearby actor's collision bounds.
	var minimum_distance := camera.near
	for weapon in world.region.loadout.all_weapons():
		var pose=world.region.player.pose
		var muzzle: Vector3=Library.point(preload("res://native/simulation/fixed_math.gd").added(pose.origin,pose.rotate_direction(weapon.mount)))
		minimum_distance=maxf(minimum_distance,(muzzle-origin).dot(direction)+1.0)
	var distance := 1800.0
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

func begin_departure() -> void:
	departure_hangar=null
	for station in station_nodes:
		if int(station.record.id)==3308:departure_hangar=station;break
	if departure_hangar==null:return
	var aperture:AABB=departure_hangar.hangar_aperture()
	departure_frame=departure_hangar.global_transform*Transform3D(Basis.IDENTITY,aperture.get_center())
	var direction:=departure_frame.basis.z.normalized()
	var hull:AABB=player_model.solid_bounds()
	departure_start=departure_frame.origin-direction*hull.size.z*.5
	departure_end=departure_frame.origin+direction*(105+hull.size.z)
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
	dock_orbit+=delta*.055
	var bounds := AABB();var first := true
	for station in station_nodes:
		var box: AABB=station.transform*station.solid_bounds()
		bounds=box if first else bounds.merge(box);first=false
	if first: return
	var focus := bounds.get_center()
	var radius := maxf(180,bounds.size.length()*.78)
	camera.global_position=focus+Vector3(sin(dock_orbit)*radius,radius*.23,cos(dock_orbit)*radius)
	camera.look_at(focus,Vector3.UP)
	# Leave the left side clear for the original-style dock menu.
	camera.h_offset=-radius*.22
	if player_model!=null: player_model.hide()

func assign_player_basis(basis: Basis) -> void:
	var pose=world.region.player.pose
	pose.right=[roundi(basis.x.x*4096),roundi(-basis.x.y*4096),roundi(-basis.x.z*4096)]
	pose.up=[roundi(-basis.y.x*4096),roundi(basis.y.y*4096),roundi(basis.y.z*4096)]
	pose.forward=[roundi(-basis.z.x*4096),roundi(basis.z.y*4096),roundi(basis.z.z*4096)]
func clear_player_clip() -> void:
	if player_model!=null:player_model.set_portal_clip(false)
	for entry in portal_materials:
		if is_instance_valid(entry.mesh):entry.mesh.set_surface_override_material(entry.index,entry.previous)
	portal_materials.clear()
func clip_player_at_gate(frame: Transform3D, side: float) -> void:
	if player_model==null:return
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
