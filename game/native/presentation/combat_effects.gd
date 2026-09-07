extends Node3D
## Presentation-only pools. All positions and ages come from fixed simulation ticks.
const Library = preload("res://scripts/model_library.gd")
const Pose = preload("res://native/simulation/ship_transform.gd")
const Math = preload("res://native/simulation/fixed_math.gd")
var owner_view
var projectile_nodes: Dictionary = {}
var segments := MultiMeshInstance3D.new()
var bursts := MultiMeshInstance3D.new()
var bubbles := MultiMeshInstance3D.new()
var lights: Array[OmniLight3D] = []
var segment_count := 0
var burst_count := 0
var bubble_count := 0
var projectile_count := 0
var light_count := 0
var pose := Pose.new()
var player_wake: Array=[]
var wake_timer := 0.0
var wake_serial := 0
var wake_previous: Array[Vector3]=[]
var effect_bounds: Dictionary={}

func pool(node: MultiMeshInstance3D, mesh: Mesh, capacity: int) -> void:
	var instances := MultiMesh.new(); instances.transform_format=MultiMesh.TRANSFORM_3D
	instances.use_colors=true; instances.use_custom_data=true; instances.mesh=mesh
	instances.instance_count=capacity; instances.visible_instance_count=0; node.multimesh=instances
	node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.custom_aabb=AABB(Vector3.ONE*-1,Vector3.ONE*2); add_child(node)

func include_bounds(node: MultiMeshInstance3D, at: Vector3, radius: float) -> void:
	var box := AABB(at-Vector3.ONE*radius,Vector3.ONE*radius*2)
	effect_bounds[node]=box if not effect_bounds.has(node) else effect_bounds[node].merge(box)

func refresh_bounds() -> void:
	for node in [segments,bursts,bubbles]:
		node.custom_aabb=effect_bounds.get(node,AABB(Vector3.ONE*-1,Vector3.ONE*2))
func _ready() -> void:
	var tube := CylinderMesh.new(); tube.top_radius=1; tube.bottom_radius=1; tube.height=1; tube.radial_segments=6; tube.rings=1
	var glow := ShaderMaterial.new(); glow.shader=preload("res://native/presentation/combat_line.gdshader")
	tube.material=glow; pool(segments,tube,128)
	var quad := QuadMesh.new(); quad.size=Vector2.ONE
	var material := ShaderMaterial.new(); material.shader=preload("res://native/presentation/combat_sprite.gdshader"); quad.material=material
	pool(bursts,quad,256)
	var bubble_quad := QuadMesh.new();bubble_quad.size=Vector2.ONE
	var bubble_material := ShaderMaterial.new();bubble_material.shader=preload("res://native/presentation/bubble.gdshader")
	bubble_quad.material=bubble_material;pool(bubbles,bubble_quad,1024)
	for i in 4:
		var light := OmniLight3D.new(); light.shadow_enabled=false; light.omni_range=55; light.light_volumetric_fog_energy=0.2; light.hide(); add_child(light); lights.append(light)
func reset(keep_player_wake: bool=false) -> void:
	effect_bounds.clear()
	if not keep_player_wake:player_wake.clear();wake_previous.clear();wake_timer=0.0;wake_serial=0
	for node in projectile_nodes.values(): node.queue_free()
	projectile_nodes.clear()
	for node in [segments,bursts,bubbles]: node.multimesh.visible_instance_count=0
	refresh_bounds()
	for light in lights: light.hide()
	segment_count=0; burst_count=0; bubble_count=0; projectile_count=0; light_count=0
static func segment_pose(start: Vector3, end: Vector3, width: float) -> Transform3D:
	var delta := end-start
	if delta.length_squared()<0.000001: return Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO),start)
	var direction := delta.normalized()
	var right := direction.cross(Vector3.RIGHT if absf(direction.y)>0.99 else Vector3.UP).normalized()
	return Transform3D(Basis(right*width,delta,right.cross(direction)*width),(start+end)/2)
func segment(start: Vector3, end: Vector3, width: float, color: Color) -> void:
	if segment_count>=segments.multimesh.instance_count: return
	include_bounds(segments,start,maxf(width,0.1));include_bounds(segments,end,maxf(width,0.1))
	segments.multimesh.set_instance_transform(segment_count,segment_pose(start,end,width))
	segments.multimesh.set_instance_color(segment_count,color); segment_count+=1
func sprite(node: MultiMeshInstance3D, index: int, at: Vector3, diameter: float, age: float, kind: float, color: Color) -> void:
	# Quads expand in the vertex shader, beyond their unit-mesh bounds.
	# Include billboard corners and the minimum on-screen bubble diameter.
	var radius := maxf(diameter,1.0)
	if owner_view!=null and is_instance_valid(owner_view.camera):
		var eye: Camera3D=owner_view.camera
		radius=maxf(radius,at.distance_to(eye.global_position)*20.0/maxf(1.0,eye.get_viewport().get_visible_rect().size.y))
	include_bounds(node,at,radius)
	node.multimesh.set_instance_transform(index,Transform3D(Basis.IDENTITY,at))
	node.multimesh.set_instance_color(index,color)
	node.multimesh.set_instance_custom_data(index,Color(diameter,clampf(age,0,1),kind,0))
func burst(at: Vector3, radius: float, age: float, color: Color, debris: bool=false) -> void:
	if burst_count>=bursts.multimesh.instance_count: return
	sprite(bursts,burst_count,at,radius*2,age,0,color); burst_count+=1
	if debris and age<0.65:
		for j in 8:
			var direction := Vector3(cos(j*2.399),sin(j*1.83)*0.6,sin(j*2.399)).normalized()
			var start := at+direction*radius*(0.05+age)*1.2
			segment(start,start+direction*radius*0.22*(1-age),0.045*(1-age),Color(color,1-age/0.65))
	if age<0.25 and light_count<lights.size() and at.distance_to(owner_view.camera.global_position)<300:
		var light := lights[light_count]; light.position=at; light.light_color=color; light.light_energy=3*(1-age*4); light.show(); light_count+=1
func bubble(at: Vector3, scale: float, opacity: float) -> void:
	if bubble_count>=bubbles.multimesh.instance_count or at.distance_squared_to(owner_view.camera.global_position)>160000: return
	var distance: float=at.distance_to(owner_view.camera.global_position)
	var visibility: float=(1.0-smoothstep(240.0,400.0,distance))*smoothstep(0.0,.12,1.0-opacity)
	sprite(bubbles,bubble_count,at,maxf(0.04,scale),1-opacity*visibility,1,Color("8bbbc8")); bubble_count+=1
func update_player_wake(region, milliseconds: float) -> void:
	var dt := maxf(0,milliseconds*.001)
	var anchor: Vector3=owner_view.world.geography.anchor
	for particle in player_wake:
		particle.age+=dt;particle.at+=particle.velocity*dt
	player_wake=player_wake.filter(func(particle):return particle.age<2.4)
	if owner_view.world.session.docked:
		player_wake.clear();wake_previous.clear();wake_timer=0;return
	var model=owner_view.player_model
	if model==null:return
	var bounds: AABB=model.solid_bounds()
	var frame: Transform3D=model.global_transform
	var outlets: Array[Vector3]=[]
	for side in [-1,1]:
		var local := bounds.get_center()+Vector3(bounds.size.x*.36*side,-bounds.size.y*.08,0)
		local.z=bounds.end.z+.5
		outlets.append(frame*local+anchor)
	if wake_previous.is_empty():wake_previous=outlets.duplicate()
	if dt>0:
		var power: float=clampf(region.player.throttle/100.0,0,1)
		var interval := lerpf(.24,.035,power)
		wake_timer=minf(wake_timer+dt,interval*8)
		while wake_timer>=interval:
			wake_timer-=interval
			for side in 2:
				var at := wake_previous[side].lerp(outlets[side],clampf(1.0-wake_timer/dt,0,1))
				# Deterministic turbulence is sampled once at birth, never per frame.
				var phase := float(wake_serial)*2.399963
				var scatter := frame.basis.x*cos(phase)+frame.basis.y*sin(phase)
				var size := .16+.22*(sin(phase*1.7)*.5+.5)
				player_wake.append({"at":at+scatter*.22,"velocity":frame.basis.z*(3+power*4)+scatter*.85+Vector3.UP*.9,"age":0.0,"power":power,"size":size})
				wake_serial+=1
		wake_previous=outlets.duplicate()
	for particle in player_wake:
		var age: float=particle.age/2.4
		var opacity: float=smoothstep(0.0,.02,age)*pow(1.0-age,1.4)*lerpf(.28,.8,particle.power)
		var at: Vector3=particle.at-anchor
		var distance: float=at.distance_to(owner_view.camera.global_position)
		opacity*=smoothstep(4.0,12.0,distance)*(1.0-smoothstep(240.0,400.0,distance))
		if opacity<=.001 or bubble_count>=bubbles.multimesh.instance_count:continue
		sprite(bubbles,bubble_count,at,particle.size*(1.0+age*1.8),1-opacity,2,Color("c4e3e9"));bubble_count+=1
func update(region, milliseconds: int, render_milliseconds: float=-1.0) -> void:
	effect_bounds.clear()
	segment_count=0; burst_count=0; bubble_count=0; projectile_count=0; light_count=0
	update_player_wake(region,float(milliseconds) if render_milliseconds<0 else render_milliseconds)
	for light in lights: light.hide()
	for node in projectile_nodes.values(): node.hide()
	pose.math.sine_table=region.sine
	var weapons: Array = region.weapons.duplicate()
	for weapon in region.loadout.all_weapons():
		if not weapon in weapons: weapons.append(weapon)
	for weapon in weapons:
		for i in weapon.remaining.size():
			if weapon.remaining[i]<=0: continue
			var at := Library.point(weapon.positions[i])
			var velocity := Library.point(weapon.velocities[i])
			if weapon.beam:
				# bc.f renders the travelling segment, two velocity steps long.
				var color: Color = [Color("83e2c2"),Color("b9beff"),Color("ffc77b")][clampi(weapon.equipment_id-3,0,2)]
				segment(at-velocity*2,at,0.10,color)
			elif weapon.fishing:
				segment(Library.point(region.player.pose.origin),at,0.035,Color("649a9b"))
			elif weapon.model_id>=0:
				var key := str(weapon.get_instance_id())+":"+str(i)
				if not projectile_nodes.has(key):
					var visual=owner_view.model(weapon.model_id,32,self)
					if visual==null: continue
					projectile_nodes[key]=visual
				var visual=projectile_nodes[key]
				pose.origin=weapon.positions[i]; pose.face(Math.normalize_vector(weapon.velocities[i]))
				visual.transform=pose.godot_transform()
				if weapon.homing: visual.basis=visual.basis.scaled_local(Vector3.ONE*2)
				visual.show(); visual.advance(milliseconds); projectile_count+=1
				if weapon.homing:
					for j in 14:
						var side := Vector3(sin(j*2.4+region.elapsed_ms*.002),cos(j*1.7),0)*float(j)*.035
						bubble(at-velocity*float(j)/5+side,.12+float(j)*.014,.36-float(j)*.023)
	for hook in region.fishing:
		if hook.target!=null:
			segment(owner_view.world.render_pose(region.player).origin,owner_view.world.render_pose(hook.target).origin,0.035,Color("649a9b"))
	for actor in region.enemies+region.friends:
		if actor.state in [3,4] and not (actor.capturable and actor.health.enabled): continue
		if owner_view.pack.enabled: continue
		for i in actor.trail.life.size():
			var fraction: float=owner_view.world.accumulator
			var remaining: float=maxf(0,float(actor.trail.life[i])-fraction)
			if remaining>0:
				var at: Vector3=Library.point(actor.trail.position[i])+Vector3.UP*float(actor.trail.rise[i])*.01*fraction*.001
				bubble(at,remaining/1800.0*1.4,remaining/1800.0)
	for event in region.visual_events:
		var age_ms: int = region.elapsed_ms-event.time
		if event.kind=="impact":
			if age_ms<400: burst(Library.point(event.position),3.0,float(age_ms)/400,Color("d2dfd7"),true)
		else:
			for i in event.delays.size():
				var age: float = float(age_ms-int(event.delays[i]))/(1000.0 if event.delays.size()>1 else 4000.0)
				if age<0 or age>=1: continue
				var offset: Array = event.offsets[i] if i<event.offsets.size() else [0,0,0]
				burst(Library.point(Math.added(event.position,offset)),14 if event.creature else (36 if event.delays.size()>1 else 24),age,Color("82d6ad") if event.creature else Color("ffbe85"),not event.creature)
	segments.multimesh.visible_instance_count=segment_count
	bursts.multimesh.visible_instance_count=burst_count
	bubbles.multimesh.visible_instance_count=bubble_count
	refresh_bounds()
func _exit_tree() -> void:
	for node in [segments,bursts,bubbles]: node.multimesh=null
