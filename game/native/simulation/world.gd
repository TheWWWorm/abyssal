extends RefCounted
## Modernization: continuous world coordinates and safe, fixed-step time warp.
const Region = preload("res://native/simulation/region.gd")
const Math = preload("res://native/simulation/fixed_math.gd")
const STEP_MS := 40
const MAP_SCALE := 40000
const SPEEDS := [1,2,4,8,16]
const COURSE_LOOKAHEAD := 60000.0
const REGION_APPROACH_DISTANCE := 60000.0 # Activate encounters before reaching station walls.
var session
var region
var accumulator := 0.0
var speed := 1
var destination := -1
var stream_destination := -1
var departure_gate := 0
var gate_time := [0,0]
var gate_closing := [0,0]
const GATE_OPEN_MS := 608
var local_target = null
var autopilot := false
var encounter_autopilot := false
var gate_navigation := false
var obstacle_bodies := {}
var passage_check := Callable()
var avoidance_path: Array = []
var approach_path: Array = []
var approach_planned := false
var course_start: Array = []
var message := ""
var revision := 0
var travelled := 0.0
var geography = preload("res://native/simulation/geography.gd").new()
var render_interpolation_enabled := false
var mouse_pending := Vector2.ZERO
var weapon_pending: Dictionary={}
var previous_render_poses := {}
var previous_render_bank := 0
func configure(owner_session) -> void:
	session=owner_session
func station_origin(id: int) -> Array:
	var station: Dictionary = session.stations[id]
	return [station.x*MAP_SCALE,station.depth*8,station.y*MAP_SCALE]
func global_position() -> Array:
	return Math.added(station_origin(session.station_id),region.player.pose.origin) if region!=null else station_origin(session.station_id)
func depart() -> bool:
	if not session.depart(): message=session.text(session.depart_denial()); return false
	if region!=null: region.dispose()
	region=Region.new(); region.configure(session); attach_geography(); revision+=1; accumulator=0;weapon_pending.clear(); cancel_autopilot(); reset_gates()
	# The departure berth is on the near side: face away from the station.
	region.player.pose.face(Math.normalize_vector(region.player.pose.origin))
	return true
func route_denial(id: int) -> String:
	if id<0 or id>=session.stations.size() or region==null:return "This destination is unavailable."
	if id!=session.station_id:
		if tutorial_travel_locked():return session.text(291)
		if region.success!=null or region.failure!=null:return "Finish the active encounter before leaving this area."
		var target: Dictionary = session.stations[id]
		if target.depth<session.ship.minimum_depth or target.depth>session.ship.maximum_depth:
			return "Destination exceeds this ship’s safe depth. Upgrade pressure protection."
	return ""
func route_to(id: int) -> bool:
	if session.docked:return false
	message=route_denial(id)
	if not message.is_empty():return false
	if id==session.station_id and encounter_navigation_point()!=null:
		return navigate_encounter()
	stream_destination=-1
	region.player.set_throttle(100)
	encounter_autopilot=false;gate_navigation=false;avoidance_path=[]
	destination=id; autopilot=true; approach_path=[]; approach_planned=false; course_start=global_position()
	local_target=Math.subtracted(station_origin(id),station_origin(session.station_id))
	region.player.autopilot_target=local_target; message="Autopilot · "+session.stations[id].name
	update_approach()
	return true
func tutorial_travel_locked() -> bool:
	return false # Exploration is available from the start; active encounters gate exits.
func fly_to(point: Array) -> void:
	if region==null or session.docked: return
	stream_destination=-1
	region.player.set_throttle(100)
	encounter_autopilot=false;gate_navigation=false;avoidance_path=[]
	destination=-1; approach_path=[]; approach_planned=false; course_start=[]; local_target=point.duplicate(); autopilot=true; region.player.autopilot_target=local_target
func cancel_autopilot(reason: String="") -> void:
	autopilot=false; encounter_autopilot=false; gate_navigation=false;avoidance_path=[]; speed=1; destination=-1; local_target=null; approach_path=[]; approach_planned=false; course_start=[]
	if region!=null: region.player.autopilot_target=null
	if not reason.is_empty(): message=reason
func cycle_speed() -> void:
	if region==null or session.docked:return
	var available: Array=SPEEDS if autopilot and not region.danger() else [1,2]
	speed=available[(available.find(speed)+1)%available.size()]
	message="Time · %d×"%speed
func refresh_local_encounter() -> void:
	if region==null or session.docked or region.failed or region.pending_mission!=null or region.active_transmission!=null:return
	if region.success!=null or region.failure!=null or not region.events.is_empty():return
	for mission in [session.campaign.primary,session.campaign.secondary]:
		if mission.destination!=session.station_id or mission.completed or mission.failed:continue
		if mission.kind in [0,1,2,3,4,5,6,7,9,10,11,12] and not (mission.jump_limit>=0 and mission.expired()):
			enter_region(session.station_id);return
func advance(real_seconds: float, input: Dictionary={}) -> void:
	if region==null or session.docked: return
	refresh_local_encounter()
	if region.events.any(func(event):return event.kind=="briefing"):return
	if region.failed or region.pending_mission!=null or region.active_transmission!=null:
		accumulator=0; speed=1; return
	# Looking around / mouse jitter never disengages a plotted course.
	# Steering keys, throttle, weapons or the explicit Disengage button do.
	if not autopilot: mouse_pending+=Vector2(input.get("mouse_x",0.0),input.get("mouse_y",0.0))
	else: mouse_pending=Vector2.ZERO
	if autopilot and (input.get("yaw",0)!=0 or input.get("pitch",0)!=0 or input.get("strafe",0)!=0 or input.get("fire",false) or input.get("boost",false) or input.get("guns",false) or input.get("hook",false) or input.get("throttle",0)!=0): cancel_autopilot("Manual control")
	for action in ["fire","guns","hook"]:
		if input.get(action,false):weapon_pending[action]=true
	if region.danger(): speed=mini(speed,2)
	# Bound wall-time debt after OS stalls, not simulation delta; no giant steps.
	accumulator+=minf(real_seconds,0.25)*1000.0
	while accumulator>=STEP_MS:
		accumulator-=STEP_MS
		var substeps: int = speed
		for _i in substeps:
			if render_interpolation_enabled:
				previous_render_poses.clear()
				for actor in [region.player]+region.enemies+region.friends+region.creatures:
					previous_render_poses[actor.get_instance_id()]=actor.pose.godot_transform()
				previous_render_bank=region.player.visual_bank
			var tick_input := input.duplicate()
			for action in weapon_pending:tick_input[action]=true
			weapon_pending.clear()
			tick_input.mouse_x=mouse_pending.x; tick_input.mouse_y=mouse_pending.y; mouse_pending=Vector2.ZERO
			var before_step: Array=region.player.pose.origin.duplicate()
			region.step(STEP_MS,tick_input)
			resolve_station_contact(before_step)
			keep_wildlife_outside_station()
			update_gates(STEP_MS)
			var previous_revision := revision
			if passage_check.is_valid():passage_check.call()
			if revision!=previous_revision:return
			if region.failed or region.pending_mission!=null or region.active_transmission!=null:
				# The UI owns acknowledgement. Discard the rest of this wall frame
				# so neither other outer ticks nor a later resume run past the pause.
				accumulator=0; speed=1; return
			if autopilot: update_autopilot()
			else: explore()
			if region.danger():speed=mini(speed,2)
			if substeps>speed:break
func encounter_navigation_point():
	if region==null or (region.success==null and region.failure==null): return null
	if region.route.current()!=null: return region.route.current().duplicate()
	# Encounters without a patrol route still need an actionable destination.
	var nearest = null
	var distance := INF
	for actor in region.enemies:
		if actor.health.hull<=0 or actor.state in [3,4,999]: continue
		var delta := Math.subtracted(actor.pose.origin,region.player.pose.origin)
		var amount := Vector3(delta[0],delta[1],delta[2]).length_squared()
		if amount<distance: distance=amount; nearest=actor.pose.origin.duplicate()
	return nearest
func navigate_encounter() -> bool:
	var point = encounter_navigation_point()
	if point==null:return false
	fly_to(point)
	encounter_autopilot=true
	message="Autopilot · mission waypoint"
	return true
func update_autopilot() -> void:
	if encounter_autopilot:
		var point = encounter_navigation_point()
		if point==null:
			cancel_autopilot("Encounter complete · manual control"); return
		if point!=local_target:
			local_target=point; approach_path=[]; approach_planned=false
	if local_target==null: return
	if destination>=0 and destination!=session.station_id and remaining_distance()*100.0<REGION_APPROACH_DISTANCE:
		var arriving := destination
		cancel_autopilot()
		enter_region(arriving)
		if not navigate_encounter(): route_to(arriving)
		return
	var difference := Math.subtracted(local_target,region.player.pose.origin)
	var distance: float = Vector3(difference[0],difference[1],difference[2]).length()
	if distance<25000: speed=1
	var dockable: bool = destination==session.station_id and region.station.can_dock(region.player.pose.origin)
	# Mission predicates use a strict 20 m waypoint cube. Stopping at 120 m
	# left the player outside the trigger, so its radio/script never ran.
	var arrival_distance := 1800.0 if destination<0 else 12000.0
	if distance>arrival_distance and not dockable:
		update_approach(); avoid_cruise_stations(); return
	var arriving := destination
	cancel_autopilot("Arrived · manual control")
	if arriving>=0 and arriving!=session.station_id: enter_region(arriving)
func update_approach() -> void:
	if destination<0 and stream_destination<0 and local_target!=null:
		var local_position: Array=region.player.pose.origin
		if not approach_planned and absi(local_position[1])<14000 and Vector3(local_position[0],0,local_position[2]).length()<region.station.extent+60000:
			approach_path=preload("res://native/simulation/station_navigation.gd").new().approach(region.station,local_position,local_target)
			approach_planned=not approach_path.is_empty()
		follow_approach(true)
		if approach_path.is_empty():region.player.autopilot_target=local_target
		return
	if destination!=session.station_id and stream_destination<0:
		update_course()
		if destination>=0:
			var position: Array = region.player.pose.origin
			if not approach_planned and absi(position[1])<14000 and Vector3(position[0],0,position[2]).length()<region.station.extent+60000:
				approach_path=preload("res://native/simulation/station_navigation.gd").new().approach(region.station,position,region.player.autopilot_target)
				approach_planned=not approach_path.is_empty()
				# A clear course keeps its moving look-ahead target. Hold only real detours.
				if approach_path.size()==1: approach_path.clear()
			follow_approach(true)
		return
	var position: Array = region.player.pose.origin
	if not approach_planned and absi(position[1])<14000 and Vector3(position[0],0,position[2]).length()<region.station.extent+60000:
		approach_path=preload("res://native/simulation/station_navigation.gd").new().approach(region.station,position,region.gates[departure_gate] if stream_destination>=0 else [])
		approach_planned=not approach_path.is_empty() if stream_destination>=0 else true
	follow_approach()
func follow_approach(consume_end: bool=false) -> void:
	if approach_path.is_empty(): return
	var delta := Math.subtracted(approach_path[0],region.player.pose.origin)
	if (consume_end or approach_path.size()>1) and Vector3(delta[0],delta[1],delta[2]).length()<1800: approach_path.pop_front()
	if not approach_path.is_empty(): region.player.autopilot_target=approach_path[0]
func update_course() -> void:
	if destination<0 or course_start.is_empty(): return
	# Source Q12 steering was designed for local targets. A distant endpoint
	# leaves small cross-track errors below its integer correction threshold,
	# allowing depth drift over kilometres. Track the actual course nearby.
	var end: Array = station_origin(destination)
	var position: Array = global_position()
	var start := Vector3(course_start[0],course_start[1],course_start[2])
	var segment := Vector3(end[0],end[1],end[2])-start
	var length := segment.length()
	if length<=COURSE_LOOKAHEAD: return
	var direction := segment/length
	var progress := (Vector3(position[0],position[1],position[2])-start).dot(direction)
	var next := start+direction*minf(length,maxf(0,progress)+COURSE_LOOKAHEAD)
	var anchor: Array = station_origin(session.station_id)
	region.player.autopilot_target=[roundi(next.x)-anchor[0],roundi(next.y)-anchor[1],roundi(next.z)-anchor[2]]
func explore() -> void:
	if region.success!=null or region.failure!=null or tutorial_travel_locked(): return
	var position := global_position()
	for station in session.stations:
		if station.id==session.station_id: continue
		var difference := Math.subtracted(position,station_origin(station.id))
		if Vector3(difference[0],difference[1],difference[2]).length()<REGION_APPROACH_DISTANCE:
			var current_delta := Math.subtracted(position,station_origin(session.station_id))
			if Vector3(difference[0],difference[1],difference[2]).length()+15000<Vector3(current_delta[0],current_delta[1],current_delta[2]).length():
				enter_region(station.id); return
func enter_region(id: int) -> void:
	var position := global_position(); var pose=region.player.pose.copy_pose()
	var flight: Dictionary = {}
	for key in ["throttle","throttle_target","stopped","bank","visual_bank","yaw_step","pitch_total","speed_factor","boost_active","boost_timer","shield_timer","repair_timer"]: flight[key]=region.player.get(key)
	var bank: int = region.loadout.selected
	var cooldowns: Array = region.loadout.all_weapons().map(func(weapon): return weapon.elapsed)
	region.dispose()
	if id!=session.station_id:session.counters.q+=1
	session.prepare_station(id)
	region=Region.new(); region.configure(session)
	pose.origin=Math.subtracted(position,station_origin(id)); region.player.pose=pose
	for key in flight: region.player.set(key,flight[key])
	region.loadout.selected=bank
	var equipped: Array = region.loadout.all_weapons()
	for i in mini(equipped.size(),cooldowns.size()): equipped[i].elapsed=cooldowns[i]
	attach_geography()
	region.player.depth=session.stations[id].depth+(int(pose.origin[1])>>3)
	revision+=1; speed=1; reset_gates()
	message="Entered "+session.stations[id].name
	if region.mission.story and region.mission.briefing and region.success!=null:
		region.events.append({"kind":"briefing","mission":region.mission})
		region.mission.briefing=false
func dock() -> bool:
	if session.docked: return true
	if region==null or not region.station.can_dock(region.player.pose.origin): message="Approach the station to dock (within 160 m)."; return false
	if region.success!=null or region.failure!=null: message="Docking locked · finish the encounter. Open autopilot and choose the quest objective."; return false
	var hull_percent := int(Math.f32(Math.f32(float(region.player.health.hull)/float(region.player.health.max_hull))*100.0)) if region.player.health.max_hull>0 else 0
	session.medals.evaluate(session,hull_percent)
	cancel_autopilot(); reset_gates(); session.arrive(); message="Docked at "+session.stations[session.station_id].name
	return true
func remaining_distance() -> float:
	if local_target==null or region==null: return 0
	var d := Math.subtracted(local_target,region.player.pose.origin)
	return Vector3(d[0],d[1],d[2]).length()*0.01
func dispose() -> void:
	if region!=null: region.dispose(); region=null

func attach_geography() -> void:
	geography=preload("res://native/simulation/geography.gd").new(); geography.configure(self)
	region.player.depth_direction=1
	keep_wildlife_outside_station()
	for hook in region.fishing:
		hook.capture_distance=1400; hook.tow_speed=24
	# The playable ocean is bottomless. Pressure protection limits descent;
	# no generated ground surface or invisible ground collider interrupts it.
	for weapon in region.weapons+region.loadout.all_weapons(): weapon.terrain_collision=func(p): return region.station.contains(p)

func build_docked_view() -> void:
	var state: int = session.rng.state
	region=Region.new(); region.configure(session); attach_geography(); revision+=1
	session.rng.state=state

# bp's range is a fraction of its map width, multiplied by be.p. The square
# continuous-world atlas uses the same 1/6 base radius and engine percentage,
# without making reachable stations depend on phone resolution/aspect ratio.
func stream_range() -> float:
	return (100.0/6.0)*(100.0+session.ship.engine_bonus)/100.0
func stream_distance(id: int) -> float:
	var a: Dictionary = session.stations[session.station_id]
	var b: Dictionary = session.stations[id]
	return Vector2(a.x,a.y).distance_to(Vector2(b.x,b.y))
func stream_denial(id: int) -> String:
	if id<0 or id>=session.stations.size(): return "Select a station."
	if id==session.station_id: return "Already in this area."
	if tutorial_travel_locked(): return session.text(291)
	if session.docked and session.depart_denial()>=0: return session.text(session.depart_denial())
	if not session.docked and region!=null and (region.success!=null or region.failure!=null): return "Complete the encounter before using STREAM."
	if stream_distance(id)>=stream_range(): return "Beyond STREAM reach. Fit a longer-range engine or use continuous autopilot."
	var target: Dictionary = session.stations[id]
	if target.depth<session.ship.minimum_depth or target.depth>session.ship.maximum_depth: return "Destination exceeds this ship’s safe depth. Upgrade pressure protection."
	return ""
func plan_stream(id: int) -> bool:
	message=stream_denial(id)
	if not message.is_empty() or session.docked or region==null: return false
	departure_gate=nearest_safe_gate()
	if departure_gate<0: message="No STREAM gate within safe depth.";return false
	fly_to_gate(departure_gate); stream_destination=id; update_approach()
	message="Approach the STREAM gate for "+session.stations[id].name
	return true
func fly_to_gate(index: int) -> void:
	departure_gate=region.gate_index(index)
	fly_to(region.gates[departure_gate]);gate_navigation=true
func nearest_safe_gate() -> int:
	if region==null:return -1
	var best := -1;var distance := INF
	for i in region.gates.size():
		if region.gate_index(i)!=i:continue
		var depth: int=session.stations[session.station_id].depth+(int(region.gates[i][1])>>3)
		if depth<session.ship.minimum_depth or depth>session.ship.maximum_depth:continue
		var delta: Array=Math.subtracted(region.gates[i],region.player.pose.origin)
		var length := Vector3(delta[0],delta[1],delta[2]).length_squared()
		if length<distance:distance=length;best=i
	return best
func reset_gates() -> void:
	previous_render_poses.clear(); mouse_pending=Vector2.ZERO
	stream_destination=-1; gate_time=[0,0]; gate_closing=[0,0]
func at_gate(index: int) -> bool:
	if region==null or session.docked: return false
	return Math.subtracted(region.player.pose.origin,region.gates[index]).all(func(v): return absi(v)<15000)
func update_gates(milliseconds: int) -> void:
	for i in 2:
		if region.gate_index(i)!=i:
			gate_time[i]=gate_time[0];gate_closing[i]=gate_closing[0];continue
		var available: bool = i==1 or not tutorial_travel_locked() and region.success==null and region.failure==null
		if at_gate(i) and available and (not autopilot or (gate_navigation and region.gate_index(departure_gate)==i)):
			if gate_time[i]==0: region.audio_event("gate",region.gates[i])
			gate_closing[i]=0; gate_time[i]+=milliseconds
			if gate_time[i]>=GATE_OPEN_MS+640: gate_time[i]=GATE_OPEN_MS
		else:
			if gate_time[i]>0: region.audio_event("gate",region.gates[i]); gate_closing[i]=gate_frame(i)*32; gate_time[i]=0
			gate_closing[i]=maxi(0,gate_closing[i]-milliseconds)
func gate_frame(index: int) -> int:
	if gate_closing[index]>0: return int(gate_closing[index]/32)
	return int(gate_time[index]/32) if gate_time[index]<GATE_OPEN_MS else 20+int((gate_time[index]-GATE_OPEN_MS)/32)
func stream_transfer() -> bool:
	if region==null or session.docked: return false
	if region.failed or region.pending_mission!=null or region.active_transmission!=null: return false
	message=stream_denial(stream_destination)
	if not message.is_empty(): return false
	if not at_gate(departure_gate): message="Approach the STREAM gate (within 160 m)."; return false
	if gate_time[departure_gate]<GATE_OPEN_MS: message="STREAM gate opening…"; return false
	var target: int = stream_destination
	# bp.c's in-flight branch preserves health and f's expedition counters.
	# dj.d increments journeys; it does not call the departure/count-jump path.
	session.hull=region.player.health.hull; session.shield=region.player.health.shield; session.armor=region.player.health.armor
	cancel_autopilot(); enter_region(target)
	var arrival_gate: int=region.gate_index(1)
	departure_gate=arrival_gate
	region.player.pose.origin=region.gates[arrival_gate].duplicate()
	region.player.pose.set_euler(0,(300 if session.stations[target].tech>4 else -300)*(arrival_gate+1)+2048,0)
	region.player.depth=session.stations[target].depth
	session.entered_gate=true; gate_time[arrival_gate]=GATE_OPEN_MS; accumulator=0
	region.audio_event("signal")
	message="STREAM arrival · "+session.stations[target].name
	return true

func render_pose(actor) -> Transform3D:
	var current: Transform3D = actor.pose.godot_transform()
	var previous: Transform3D = previous_render_poses.get(actor.get_instance_id(),current)
	if previous.origin.distance_to(current.origin)>100: return current
	var weight := clampf(accumulator/STEP_MS,0,1)
	# Original actors can briefly have a collapsed axis when facing vertically.
	# Preserve those matrices without attempting an undefined quaternion.
	if absf(previous.basis.determinant())<0.00001 or absf(current.basis.determinant())<0.00001:
		return Transform3D(Basis(previous.basis.x.lerp(current.basis.x,weight),previous.basis.y.lerp(current.basis.y,weight),previous.basis.z.lerp(current.basis.z,weight)),previous.origin.lerp(current.origin,weight))
	return previous.interpolate_with(current,weight)

func keep_wildlife_outside_station() -> void:
	# The phone game allowed background fauna to spawn inside station volumes.
	# With solid buildings and occluded weapons, that makes a catch unreachable.
	for actor in region.creatures:
		if not actor.health.enabled or actor.constrained or actor.towing or not region.station.contains(actor.pose.origin): continue
		var best: Array=[];var distance := INF
		for shape in region.station.shapes:
			for axis in [0,2]:
				for sign_value in [-1,1]:
					var candidate: Array=actor.pose.origin.duplicate()
					candidate[axis]=shape.origin[axis]+shape.offset[axis]+sign_value*(shape.half_size[axis]+actor.radius+250)
					var amount: int=absi(candidate[axis]-actor.pose.origin[axis])
					if amount<distance and not region.station.contains(candidate): best=candidate;distance=amount
		if not best.is_empty():
			if not actor.stationary: actor.pose.face(Math.normalize_vector(Math.subtracted(best,actor.pose.origin)))
			actor.pose.origin=best;actor.secondary_pose=actor.pose.copy_pose()

func resolve_station_contact(previous: Array) -> void:
	if region.cinematic() or not region.station.contains(region.player.pose.origin): return
	if not region.station.contains(previous):
		# Keep the hull outside the wall. The next tick can still turn freely,
		# even at zero throttle, rather than becoming trapped in avoidance.
		region.player.pose.origin=previous;region.player.contact=true
		return
	var best: Array=[];var distance := INF
	for shape in region.station.shapes:
		for axis in [0,2]:
			for side in [-1,1]:
				var candidate: Array=previous.duplicate()
				candidate[axis]=shape.origin[axis]+shape.offset[axis]+side*(shape.half_size[axis]+region.player.radius+100)
				var amount: int=absi(candidate[axis]-previous[axis])
				if amount<distance and not region.station.contains(candidate):best=candidate;distance=amount
	if not best.is_empty():region.player.pose.origin=best

func avoid_cruise_stations() -> void:
	if region.player.autopilot_target==null:return
	var math=preload("res://native/simulation/fixed_math.gd")
	var start: Vector3=math.vector(global_position())
	var anchor: Vector3=math.vector(station_origin(session.station_id))
	while not avoidance_path.is_empty() and start.distance_to(avoidance_path[0])<1800:avoidance_path.pop_front()
	if avoidance_path.is_empty():
		var finish: Vector3=anchor+math.vector(region.player.autopilot_target)
		var obstacles: Array=[]
		for station in session.stations:
			if station.id==session.station_id or station.id==destination:continue
			if not obstacle_bodies.has(station.id):
				var body=preload("res://native/simulation/station_body.gd").new()
				body.configure(station,session.is_colonist_station(station.id),region.sine,session.data.get("station_geometry",{}))
				var box:=AABB();var first:=true
				for shape in body.shapes:
					var center: Vector3=math.vector(shape.origin)+math.vector(shape.offset)+math.vector(station_origin(station.id))
					var half: Vector3=math.vector(shape.half_size)
					var part:=AABB(center-half,half*2)
					box=part if first else box.merge(part);first=false
				obstacle_bodies[station.id]=box.grow(4000)
			obstacles.append(obstacle_bodies[station.id])
		avoidance_path=preload("res://native/simulation/station_navigation.gd").cruise_detour(start,finish,obstacles,session.ship.minimum_depth*8+1000,session.ship.maximum_depth*8-1000)
		if avoidance_path.is_empty() and obstacles.any(func(box):return box.intersects_segment(start,finish)!=null):
			region.player.set_throttle(0);cancel_autopilot("Route blocked by a station within safe depth · choose another approach");return
	if not avoidance_path.is_empty():
		region.player.autopilot_target=math.array(avoidance_path[0]-anchor)
		speed=mini(speed,2)
