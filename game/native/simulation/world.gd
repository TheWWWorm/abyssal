extends RefCounted
## Modernization: continuous world coordinates and safe, fixed-step time warp.
const Region = preload("res://native/simulation/region.gd")
const Math = preload("res://native/simulation/fixed_math.gd")
const StationBody = preload("res://native/simulation/station_body.gd")
const CollisionShape = preload("res://native/simulation/collision_shape.gd")
const SpecialActor = preload("res://native/simulation/special_actor.gd")
const STEP_MS := 40
const Spacing = preload("res://native/simulation/world_spacing.gd")
const SPEEDS := [1,2,4,8,16]
enum ObjectiveTravel { STREAM, OPEN_WATER }
var objective_travel_mode := ObjectiveTravel.STREAM
var ship_collisions := false
const COURSE_LOOKAHEAD := 60000.0
const REGION_APPROACH_DISTANCE := preload("res://native/simulation/world_layout.gd").REGION_APPROACH_DISTANCE
var session
var region
## The berth's own random sequence; see advance_docked.
var ambient_rng
var accumulator := 0.0
var speed := 1
var destination := -1
var stream_destination := -1
## The last station a route was set for, kept through manual control so the
## pilot can resume it; cleared on arriving there.
var resume_destination := -1
var resume_stream := false
var resume_objective := false
## An objective may need several gate crossings. Each leg still uses the
## ordinary gate approach, confirmation and arrival; manual control cancels
## continuation while retaining the final destination for Resume.
var objective_destination := -1
var objective_route: Array[int] = []
var objective_route_pending := false
var departure_gate := 0
var gate_time := [0,0]
var gate_closing := [0,0]
## at: a gate is a box of 15000 x 15000 x 8000 (cu halves it) that turns a hull
## entering it away from its centre. The arrival shot starts inside the gate
## it comes out of, so that one is left out until the ship is clear of it.
const GATE_REPEL_HALF := [7500,7500,4000]
## How far out from a station's walls the hull starts to be turned away, as a
## gate turns it: the hull's own radius (where the walls stop it) and four
## metres more. A ship flying in to dock is left alone until it is about to
## touch, and one already against a wall keeps turning until it is clear.
const STATION_REPEL_MARGIN := 1600
var station_repellers := {}
var arrival_exit := -1
## One frame of the gate's split. The whole opening is twenty of them, so this
## sets how sharply the gate snaps apart as a submarine runs at it.
const GATE_FRAME_MS := 32
const GATE_OPEN_MS := GATE_FRAME_MS*20
var local_target = null
## The water just outside the hangar door, where the departure shot leaves
## the hull (world_view.gd places it once the station is drawn); null until
## then. Autopilot docks there rather than at the docking box's edge.
var berth = null
## Water farther out along the door's line: the run-in starts there, so the
## hull arrives facing the door from whichever side it came.
var berth_lead = null
var autopilot := false
var encounter_autopilot := false
var gate_navigation := false
var obstacle_bodies := {}
var physical_neighbors := {}
var active_collision_bodies: Array = []
var collision_scan_origin: Array = []
var nearby_station_ids: Array = []
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
var previous_boost_timer: Dictionary = {}
var previous_reload_timers: Dictionary = {}
## The helm setting outlives any one region's player; see player.gd.
var smooth_steering := false
var manual_roll := false
## Apply at a new dive, never by moving stations around an active submarine.
var spacing_meters := Spacing.DEFAULT_METERS
## How near the berth autopilot docks, in world units.
const BERTH_REACH := 2500
## How much longer than the straight run into the docking box the line-up on
## the hangar door may be before autopilot just docks at the box instead.
const BERTH_DETOUR := 9000
func configure(owner_session) -> void:
	session=owner_session
	session.world_layout.spacing_meters=spacing_meters
func map_scale() -> int:
	return session.world_layout.spacing_meters*100
func map_kilometers(units: float) -> float:
	return units*session.world_layout.spacing_meters/1000.0
func set_smooth_steering(value: bool) -> void:
	smooth_steering=value
	if region!=null:region.player.smooth_steering=value
func set_manual_roll(value: bool) -> void:
	manual_roll=value
	if region!=null:region.player.manual_roll=value
func station_origin(id: int) -> Array:
	return session.world_layout.station_origin(session.stations[id])
func global_position() -> Array:
	return Math.added(station_origin(session.station_id),region.player.pose.origin) if region!=null else station_origin(session.station_id)
func depart() -> bool:
	if not session.depart(): message=session.text(session.depart_denial()); return false
	if region!=null: region.dispose()
	session.world_layout.spacing_meters=spacing_meters
	obstacle_bodies.clear();previous_render_poses.clear()
	region=Region.new(); region.configure(session); physical_neighbors.clear();station_repellers.clear();collision_scan_origin=[];nearby_station_ids=[];attach_geography(); revision+=1; accumulator=0;weapon_pending.clear(); cancel_autopilot(); reset_gates()
	# The departure berth is on the near side: face away from the station.
	region.player.pose.face(Math.normalize_vector(region.player.pose.origin))
	return true
func route_denial(id: int) -> String:
	if id<0 or id>=session.stations.size() or region==null:return tr("This destination is unavailable.")
	if id!=session.station_id:
		if tutorial_travel_locked():return session.text(291)
		if region.success!=null or region.failure!=null:return tr("Finish the active encounter before leaving this area.")
	return ""
func outside_safety(id: int) -> bool:
	"""A destination deeper or shallower than the hull's limits. The original
	still goes there, at the pilot's risk, after warning (255) and asking (247)."""
	if id<0 or id>=session.stations.size() or id==session.station_id:return false
	var target: Dictionary=session.stations[id]
	return target.depth<session.ship.minimum_depth or target.depth>session.ship.maximum_depth
func route_to_objective(id: int) -> bool:
	if objective_travel_mode==ObjectiveTravel.STREAM and id!=session.station_id:
		return plan_objective_stream(id)
	return route_to(id)
func objective_stream_route(id: int) -> Array[int]:
	# Fewest crossings, with total map distance breaking ties. Intermediate
	# stops stay inside the hull's limits and avoid unfinished encounters.
	# The final destination retains the usual travel/depth warning rules.
	var result: Array[int]=[]
	if id<0 or id>=session.stations.size() or id==session.station_id:return result
	var count: int=session.stations.size()
	var hops: Array[int]=[];hops.resize(count);hops.fill(2147483647)
	var distances: Array[float]=[];distances.resize(count);distances.fill(INF)
	var previous: Array[int]=[];previous.resize(count);previous.fill(-1)
	var pending: Array[int]=[session.station_id]
	hops[session.station_id]=0;distances[session.station_id]=0
	var reach := stream_range()
	while not pending.is_empty():
		var best := 0
		for index in range(1,pending.size()):
			var a: int=pending[index];var b: int=pending[best]
			if hops[a]<hops[b] or (hops[a]==hops[b] and distances[a]<distances[b]):best=index
		var current: int=pending.pop_at(best)
		if current==id:break
		var from: Dictionary=session.stations[current]
		for station in session.stations:
			var next: int=station.id
			if next==current:continue
			if next!=id:
				if outside_safety(next):continue
				if [session.campaign.primary,session.campaign.secondary].any(func(mission):return mission.destination==next and mission.kind in [0,1,2,3,4,5,6,7,9,10,11,12] and not mission.completed and not mission.failed):continue
			var leg := Vector2(from.x,from.y).distance_to(Vector2(station.x,station.y))
			if leg>=reach:continue
			var steps: int=hops[current]+1
			var length: float=distances[current]+leg
			if steps>hops[next] or (steps==hops[next] and length>=distances[next]):continue
			hops[next]=steps;distances[next]=length;previous[next]=current
			if not next in pending:pending.append(next)
	if previous[id]<0:return result
	var stop := id
	while stop!=session.station_id:
		result.push_front(stop);stop=previous[stop]
	return result
func plan_objective_stream(id: int) -> bool:
	message=route_denial(id)
	if not message.is_empty() or session.docked:return false
	if id==session.station_id:return route_to(id)
	var stops := objective_stream_route(id)
	if stops.is_empty():
		if not route_to(id):return false
		message=tr("No S.T.R.E.A.M. route available · travelling to %s through open water")%session.stations[id].name
		return true
	if not plan_stream(stops[0]):return false
	objective_destination=id;objective_route=stops;objective_route_pending=false
	resume_destination=id;resume_stream=true;resume_objective=true
	if stops.size()>1:message=tr("S.T.R.E.A.M. to %s · next stop %s · %d jumps")%[session.stations[id].name,session.stations[stops[0]].name,stops.size()]
	return true
func continue_objective_route() -> bool:
	if not objective_route_pending or objective_destination<0:return false
	var target := objective_destination
	objective_route_pending=false
	return plan_objective_stream(target)
func route_to(id: int) -> bool:
	if session.docked:return false
	message=route_denial(id)
	if not message.is_empty():return false
	objective_destination=-1;objective_route=[];objective_route_pending=false
	if id==session.station_id and encounter_navigation_point()!=null:
		return navigate_encounter()
	stream_destination=-1
	region.player.set_throttle(100)
	encounter_autopilot=false;gate_navigation=false;avoidance_path=[]
	if id!=session.station_id:resume_destination=id;resume_stream=false;resume_objective=false
	destination=id; autopilot=true; approach_path=[]; approach_planned=false; course_start=global_position()
	local_target=Math.subtracted(station_origin(id),station_origin(session.station_id))
	if id==session.station_id and berth!=null:local_target=berth.duplicate()
	region.player.autopilot_target=local_target; message=tr("Autopilot · %s")%session.stations[id].name
	update_approach()
	return true
func tutorial_travel_locked() -> bool:
	return false # Exploration is available from the start; active encounters gate exits.
func fly_to(point: Array) -> void:
	if region==null or session.docked: return
	objective_destination=-1;objective_route=[];objective_route_pending=false
	stream_destination=-1
	region.player.set_throttle(100)
	encounter_autopilot=false;gate_navigation=false;avoidance_path=[]
	destination=-1; approach_path=[]; approach_planned=false; course_start=[]; local_target=point.duplicate(); autopilot=true; region.player.autopilot_target=local_target
func cancel_autopilot(reason: String="", keep_objective: bool=false) -> void:
	if not keep_objective:objective_destination=-1;objective_route=[];objective_route_pending=false
	autopilot=false; encounter_autopilot=false; gate_navigation=false;avoidance_path=[]; speed=1; destination=-1; local_target=null; approach_path=[]; approach_planned=false; course_start=[]
	if region!=null: region.player.autopilot_target=null
	if not reason.is_empty(): message=reason
func cycle_speed() -> void:
	if region==null or session.docked:return
	var available: Array=SPEEDS if autopilot and not region.danger() else [1,2]
	speed=available[(available.find(speed)+1)%available.size()]
	message=tr("Time · %d×")%speed
func step_speed(direction: int) -> void:
	"""One time speed up or down, held at the ends rather than wrapping."""
	if region==null or session.docked:return
	var available: Array=SPEEDS if autopilot and not region.danger() else [1,2]
	var index: int=available.find(speed)
	if index<0:index=0
	speed=available[clampi(index+direction,0,available.size()-1)]
	message=tr("Time · %d×")%speed
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
	# A briefing stops the water until it is read; one held over an arrival
	# lets the water run until the hold is over.
	if region.radio_hold_ms<=0 and region.events.any(func(event):return event.kind=="briefing"):return
	if region.failed or region.pending_mission!=null or region.active_transmission!=null:
		accumulator=0; speed=1; return
	# Looking around / mouse jitter never disengages a plotted course.
	# Steering keys, throttle, weapons or the explicit Disengage button do.
	# The booster does not: bb.b only speeds the plotted run up.
	if not autopilot: mouse_pending+=Vector2(input.get("mouse_x",0.0),input.get("mouse_y",0.0))
	else: mouse_pending=Vector2.ZERO
	if (autopilot or objective_route_pending) and (input.get("yaw",0)!=0 or input.get("pitch",0)!=0 or input.get("strafe",0)!=0 or input.get("fire",false) or input.get("guns",false) or input.get("hook",false) or input.get("throttle",0)!=0): cancel_autopilot(tr("Manual control"))
	for action in ["fire","guns","hook"]:
		if input.get(action,false):weapon_pending[action]=true
	# Danger only changes accelerated time. At the ordinary 1x/2x rates there
	# is nothing to clamp, so do not rescan every nearby actor every frame.
	if speed>2 and region.danger(): speed=2
	# Bound wall-time debt after OS stalls, not simulation delta; no giant steps.
	accumulator+=minf(real_seconds,0.25)*1000.0
	while accumulator>=STEP_MS:
		accumulator-=STEP_MS
		capture_cooldown_timers()
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
			var wildlife_before: Array=region.creatures.map(func(actor):return actor.pose.origin.duplicate())
			update_collision_bodies()
			region.step(STEP_MS,tick_input)
			resolve_body_contact(before_step)
			keep_wildlife_outside_station(wildlife_before)
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
			if session.docked:
				accumulator=0; return
			if speed>2 and region.danger():speed=2
			if substeps>speed:break
func encounter_navigation_point():
	if region==null or (region.success==null and region.failure==null): return null
	if region.route.current()!=null: return region.route.current().duplicate()
	var actor=encounter_navigation_subject()
	return actor.pose.origin.duplicate() if actor!=null else null
func encounter_navigation_subject():
	if region==null or region.success==null or region.route.current()!=null:return null
	# The original's cb draws a route waypoint separately from enemy brackets.
	# The modern route helper may follow a mission subject after the route ends,
	# but a nearby escort or incidental pirate is not automatically that subject.
	var goal=region.success
	var candidates: Array=[]
	var recovery: bool=goal.metric in ["enemy_rescued","all_rescued","recover"]
	match goal.metric:
		"no_enemies":candidates=region.enemies
		"first_enemies_dead":candidates=region.enemies.slice(0,mini(goal.value,region.enemies.size()))
		"enemy_dead","enemy_rescued":
			if goal.value>=0 and goal.value<region.enemies.size():candidates=[region.enemies[goal.value]]
		"all_rescued":candidates=region.enemies
		"harvest":candidates=region.creatures.filter(func(actor):return actor.species==goal.species and actor.health.enabled and actor.state!=4)
		"clear_hostiles","recover":candidates=goal.subjects
	var nearest = null
	var distance := INF
	for actor in candidates:
		if not actor.is_creature and actor.excluded_from_objectives:continue
		if recovery:
			if not actor.capturable or actor.escaped or actor.state in [3,4] and not actor.health.enabled:continue
		elif actor.health.hull<=0 or actor.state in [3,4,999] or actor.health.special_kill:continue
		var delta := Math.subtracted(actor.pose.origin,region.player.pose.origin)
		var amount := Vector3(delta[0],delta[1],delta[2]).length_squared()
		if amount<distance: distance=amount; nearest=actor
	return nearest
func navigate_encounter() -> bool:
	var point = encounter_navigation_point()
	if point==null:return false
	fly_to(point)
	encounter_autopilot=true
	message=tr("Autopilot · mission waypoint")
	return true
func update_autopilot() -> void:
	if encounter_autopilot:
		var point = encounter_navigation_point()
		if point==null:
			cancel_autopilot(tr("Encounter complete · manual control")); return
		if point!=local_target:
			local_target=point; approach_path=[]; approach_planned=false
	if local_target==null: return
	# The berth is known once the station is drawn, which can follow the order.
	if destination==session.station_id and berth!=null and local_target!=berth:
		local_target=berth.duplicate();approach_path=[];approach_planned=false;region.player.autopilot_target=local_target
	if destination>=0 and destination!=session.station_id and remaining_distance()*100.0<REGION_APPROACH_DISTANCE:
		var arriving := destination
		cancel_autopilot()
		enter_region(arriving)
		if not navigate_encounter(): route_to(arriving)
		return
	var difference := Math.subtracted(local_target,region.player.pose.origin)
	var distance: float = Vector3(difference[0],difference[1],difference[2]).length()
	if distance<25000: speed=1
	# br.a docks a station autopilot as soon as the hull enters the docking
	# box (cy.b), where the dock key works too; touching the station's hull on
	# the way in docks as well, so a large station is never rounded.
	var dockable: bool = destination==session.station_id and (in_docking_area() or touching_station())
	if dockable:
		if dock(): message=tr("Docked · %s")%session.stations[session.station_id].name
		else: cancel_autopilot(message)
		return
	# Patrol waypoints use a strict 20 m trigger. Once the route ends, hand
	# control back within weapon range of the mission subject.
	var arrival_distance := 20000.0 if encounter_autopilot and region.route.current()==null else 1800.0 if destination<0 else 12000.0
	# Docking at the berth carries on until it is reached.
	if destination==session.station_id and berth!=null:arrival_distance=0.0
	if distance>arrival_distance and not dockable:
		update_approach(); avoid_cruise_stations(); return
	var arriving := destination
	cancel_autopilot(tr("Arrived · manual control"))
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
		var navigation=preload("res://native/simulation/station_navigation.gd").new()
		var berthing: bool=stream_destination<0 and berth_lead!=null
		approach_path=navigation.approach(region.station,position,region.gates[departure_gate] if stream_destination>=0 else berth_lead if berthing else [])
		approach_planned=not approach_path.is_empty() if stream_destination>=0 else true
		if berthing:
			approach_path.append(berth.duplicate())
			# Line up on the hangar door only when it is on the way; from behind
			# or beside the station, run straight into the docking box.
			var boxed: Array=navigation.approach(region.station,position,[])
			if not boxed.is_empty() and path_length(position,approach_path)>path_length(position,boxed)+BERTH_DETOUR:approach_path=boxed
	follow_approach(stream_destination<0 and berth_lead!=null)
func path_length(start: Array,path: Array) -> float:
	var length := 0.0; var previous := start
	for point in path:
		length+=Vector3(point[0]-previous[0],point[1]-previous[1],point[2]-previous[2]).length(); previous=point
	return length
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
	berth=null;berth_lead=null
	if id==resume_destination:resume_destination=-1
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
	physical_neighbors.clear();station_repellers.clear();collision_scan_origin=[];nearby_station_ids=[];attach_geography()
	region.player.depth=session.stations[id].depth+(int(pose.origin[1])>>3)
	revision+=1; speed=1; reset_gates()
	message=tr("Entered %s")%session.stations[id].name
	# A story trip to a station has no encounter goal, but the original still
	# plays its arrival exchange (br.c(), e.g. Talon hailing the sub in chapter
	# 12). Its flag is the chapter record's own (e), so it plays once.
	if region.mission.story and region.mission.briefing and (region.success!=null or region.mission.kind==8):
		region.events.append({"kind":"briefing","mission":region.mission})
		region.mission.briefing=false
func dock() -> bool:
	if session.docked: return true
	var bumped: bool=autopilot and destination==session.station_id and touching_station()
	if region==null or not (in_docking_area() or bumped): message=tr("Approach the station's docking area."); return false
	message=dock_denial()
	if not message.is_empty(): return false
	var hull_percent := int(Math.f32(Math.f32(float(region.player.health.hull)/float(region.player.health.max_hull))*100.0)) if region.player.health.max_hull>0 else 0
	session.medals.evaluate(session,hull_percent)
	# A milestone still in the completion wait is the station's to settle.
	if region.completion_candidate!=null:region.completion_candidate.completed=false;region.completion_candidate=null
	# The station panel says where you are; no notice repeats it over it.
	cancel_autopilot(); reset_gates(); session.arrive()
	return true
func in_docking_area() -> bool:
	"""Inside the original's docking box, or at the berth."""
	return region!=null and (region.station.can_dock(region.player.pose.origin) or at_berth())
func touching_station() -> bool:
	"""Against this region's station: inside the margin its walls turn the
	hull away at."""
	if region==null:return false
	for zone in repellers_of(region.station):
		if zone.contains(region.player.pose.origin):return true
	return false
func at_berth() -> bool:
	"""Within reach of the water outside the hangar door, which can lie a
	little beyond the docking box of a large station."""
	if berth==null or region==null:return false
	var d := Math.subtracted(berth,region.player.pose.origin)
	return Vector3(d[0],d[1],d[2]).length()<BERTH_REACH
func dock_denial() -> String:
	"""Why the station turns the ship away, or nothing. Besides a live
	encounter, br.a refuses with "Can't dock while in a mission." (269) while
	the area's assigned mission is anything but a journey (8): the first
	chapter's catch has to be aboard before Gosu takes the ship in. An
	equipment job (17) is only ever done docked, so it never bars the berth.
	The story also turns the ship away in two chapters (br.a): the fifth from
	Gosu, which it must flee through the S.T.R.E.A.M. (292), and the sixth
	from anywhere but Gosu (291)."""
	if region==null: return ""
	if session.campaign.chapter==5 and session.station_id==0: return session.text(292)
	if session.campaign.chapter==6 and session.station_id!=0: return session.text(291)
	if region.success!=null or region.failure!=null: return tr("Docking locked · finish the encounter. Open autopilot and choose the quest objective.")
	var mission=region.mission
	if mission!=null and mission.kind>=0 and not mission.kind in [8,17] and not mission.completed and not mission.failed: return session.text(269)
	return ""
func remaining_distance() -> float:
	if local_target==null or region==null: return 0
	var d := Math.subtracted(local_target,region.player.pose.origin)
	return Vector3(d[0],d[1],d[2]).length()*0.01
func dispose() -> void:
	if region!=null: region.dispose(); region=null

func attach_geography() -> void:
	geography=preload("res://native/simulation/geography.gd").new(); geography.configure(self)
	region.player.smooth_steering=smooth_steering;region.player.manual_roll=manual_roll
	keep_wildlife_outside_station()
	for hook in region.fishing:
		hook.capture_distance=1400; hook.tow_speed=24
	# The playable ocean is bottomless. Pressure protection limits descent;
	# no generated ground surface or invisible ground collider interrupts it.
	for weapon in region.weapons+region.loadout.all_weapons(): weapon.terrain_collision=func(p): return collides_station(p)

func build_docked_view() -> void:
	var state: int = session.rng.state
	region=Region.new(); region.configure(session); attach_geography(); revision+=1
	session.rng.state=state
	# Wildlife is set down heading anywhere, and at a berth or behind the menu
	# it is looked at from close by: a whale hanging head down past the window
	# reads as a dead or upside-down one. Their headings are brought near the
	# level here; the flight's own draws are untouched.
	for creature in region.creatures:
		if creature.stationary: continue
		var heading: Array=creature.pose.forward.duplicate()
		heading[1]=int(heading[1]*.25)
		creature.pose.face(heading);creature.secondary_pose=creature.pose.copy_pose()
	ambient_rng=preload("res://native/simulation/java_random.gd").new()
	ambient_rng.seed_from(session.station_id*7919+session.elapsed_ms)
	accumulator=0

func advance_docked(real_seconds: float) -> void:
	"""The water outside a berth keeps moving: the wildlife and the station's
	own ships go on as they would in the flight, on a random sequence of
	their own, so the game's draws stay where docking left them however
	long the player spends at the counter."""
	if region==null or not session.docked or ambient_rng==null: return
	accumulator+=minf(real_seconds,0.25)*1000.0
	while accumulator>=STEP_MS:
		accumulator-=STEP_MS
		if render_interpolation_enabled:
			previous_render_poses.clear()
			for actor in region.enemies+region.friends+region.creatures:
				previous_render_poses[actor.get_instance_id()]=actor.pose.godot_transform()
		var wildlife_before: Array=region.creatures.map(func(actor):return actor.pose.origin.duplicate())
		region.step_ambient(STEP_MS,ambient_rng)
		keep_wildlife_outside_station(wildlife_before)

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
	if id<0 or id>=session.stations.size(): return tr("Select a station.")
	if id==session.station_id: return tr("Already in this area.")
	if tutorial_travel_locked(): return session.text(291)
	if session.docked and session.depart_denial()>=0: return session.text(session.depart_denial())
	if not session.docked and region!=null and (region.success!=null or region.failure!=null): return tr("Complete the encounter before using S.T.R.E.A.M.")
	if stream_distance(id)>=stream_range(): return tr("Beyond S.T.R.E.A.M. reach. Fit a longer-range engine or use continuous autopilot.")
	return ""
func plan_stream(id: int) -> bool:
	message=stream_denial(id)
	if not message.is_empty() or session.docked or region==null: return false
	departure_gate=nearest_safe_gate()
	if departure_gate<0: message=tr("No S.T.R.E.A.M. gate in this area.");return false
	fly_to_gate(departure_gate); stream_destination=id; update_approach()
	resume_destination=id;resume_stream=true;resume_objective=false
	message=tr("Approach the S.T.R.E.A.M. gate for %s")%session.stations[id].name
	return true
func fly_to_gate(index: int) -> void:
	departure_gate=region.gate_index(index)
	fly_to(region.gates[departure_gate]);gate_navigation=true
func nearest_safe_gate() -> int:
	"""The gate a departure uses. Only the first slot sends ships out: a shared
	portal is that slot, and a separate second portal is where arrivals come
	in. Its depth is the pilot's risk, as every destination's is."""
	if region==null or region.gates.is_empty():return -1
	return 0
func reset_gates() -> void:
	previous_render_poses.clear(); mouse_pending=Vector2.ZERO
	# A docked departure creates a fresh, level player while simulation time is
	# paused for the hangar shot. Do not keep interpolating from the bank held
	# on approach, or the new hull appears to leave at that old angle.
	previous_render_bank=region.player.visual_bank if region!=null else 0
	stream_destination=-1; gate_time=[0,0]; gate_closing=[0,0]; arrival_exit=-1
func at_gate(index: int) -> bool:
	if region==null or session.docked: return false
	return Math.subtracted(region.player.pose.origin,region.gates[index]).all(func(v): return absi(v)<session.world_layout.GATE_ACTIVATION)
func update_gates(milliseconds: int) -> void:
	for i in 2:
		if region.gate_index(i)!=i:
			gate_time[i]=gate_time[0];gate_closing[i]=gate_closing[0];continue
		# A separate arrival gate stays open only until the ship arriving
		# through it has moved away; it takes no departures.
		var available: bool = gate_time[i]>0 if i==1 else not tutorial_travel_locked() and region.success==null and region.failure==null
		if at_gate(i) and available and (not autopilot or (gate_navigation and region.gate_index(departure_gate)==i)):
			if gate_time[i]==0: region.audio_event("gate",region.gates[i])
			gate_closing[i]=0; gate_time[i]+=milliseconds
			if gate_time[i]>=GATE_OPEN_MS+640: gate_time[i]=GATE_OPEN_MS
		else:
			if gate_time[i]>0: region.audio_event("gate",region.gates[i]); gate_closing[i]=gate_frame(i)*GATE_FRAME_MS; gate_time[i]=0
			gate_closing[i]=maxi(0,gate_closing[i]-milliseconds)
func gate_frame(index: int) -> int:
	if gate_closing[index]>0: return int(gate_closing[index]/GATE_FRAME_MS)
	return int(gate_time[index]/GATE_FRAME_MS) if gate_time[index]<GATE_OPEN_MS else 20+int((gate_time[index]-GATE_OPEN_MS)/GATE_FRAME_MS)
func stream_transfer() -> bool:
	if region==null or session.docked: return false
	if region.failed or region.pending_mission!=null or region.active_transmission!=null: return false
	message=stream_denial(stream_destination)
	if not message.is_empty(): return false
	if not at_gate(departure_gate): message=tr("Approach the S.T.R.E.A.M. gate's activation area."); return false
	if gate_time[departure_gate]<GATE_OPEN_MS: message=tr("S.T.R.E.A.M. gate opening…"); return false
	var target: int = stream_destination
	var onward := objective_destination
	var remaining := objective_route.duplicate()
	if not remaining.is_empty() and remaining[0]==target:remaining.pop_front()
	# bp.c's in-flight branch preserves health and f's expedition counters.
	# dj.d increments journeys; it does not call the departure/count-jump path.
	session.hull=region.player.health.hull; session.shield=region.player.health.shield; session.armor=region.player.health.armor
	cancel_autopilot(); enter_region(target)
	# br builds a new bb after the jump: the booster arrives charged and idle.
	region.player.boost_active=false;region.player.boost_timer=0;region.player.speed_factor=2
	var arrival_gate: int=region.gate_index(1)
	departure_gate=0
	region.player.pose.origin=region.gates[arrival_gate].duplicate()
	region.player.pose.set_euler(0,region.gate_yaw(arrival_gate),0)
	region.player.depth=session.stations[target].depth
	session.entered_gate=true; gate_time[arrival_gate]=GATE_OPEN_MS; accumulator=0; arrival_exit=arrival_gate
	objective_destination=onward;objective_route=remaining;objective_route_pending=onward>=0
	message=tr("S.T.R.E.A.M. arrival · %s")%session.stations[target].name
	return true

func capture_cooldown_timers() -> void:
	# Time warp runs several simulation steps together every 40 ms. The HUD
	# interpolates the whole batch, rather than jumping by 320 ms at 8x.
	previous_boost_timer={"player":region.player.get_instance_id(),"timer":region.player.boost_timer,"active":region.player.boost_active}
	previous_reload_timers.clear()
	for weapon in region.loadout.all_weapons():
		previous_reload_timers[weapon.get_instance_id()]={"elapsed":weapon.elapsed,"serial":weapon.launch_serial,"hook_busy":weapon.hook_busy}

func render_boost_timer() -> float:
	if region==null:return 0.0
	var player=region.player
	var current: float=player.boost_timer
	if previous_boost_timer.get("player",0)!=player.get_instance_id():return current
	var previous: float=previous_boost_timer.timer
	if player.boost_active:
		# A new boost must start full, including one started during a batch.
		if not previous_boost_timer.active or previous>current:previous=0.0
	elif current<0:
		# Finishing or cancelling a boost starts a fresh, empty charge bar.
		if previous>current:previous=-player.stats.boost_cooldown
	else:return current
	return lerpf(previous,current,cooldown_interpolation_weight())

func render_reload_elapsed(weapon) -> float:
	var current: float=weapon.elapsed
	var sample: Dictionary=previous_reload_timers.get(weapon.get_instance_id(),{})
	if sample.is_empty():return current
	# A shot or released hook resets the timer; never blend back from ready.
	var reset: bool=sample.serial!=weapon.launch_serial or sample.elapsed>current or sample.hook_busy and not weapon.hook_busy
	var previous: float=0.0 if reset else sample.elapsed
	return lerpf(previous,current,cooldown_interpolation_weight())

func cooldown_interpolation_weight() -> float:
	# A blocking transmission discards time debt; hold the actual charge
	# rather than rewinding its display when the accumulator is cleared.
	if region==null or session.docked or region.failed or region.pending_mission!=null or region.active_transmission!=null:return 1.0
	return clampf(accumulator/STEP_MS,0,1)

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

func keep_wildlife_outside_station(previous_positions: Array=[]) -> void:
	# The phone game allowed background fauna to spawn inside station volumes.
	# With solid buildings and occluded weapons, that makes a catch unreachable.
	for index in region.creatures.size():
		var actor=region.creatures[index]
		if not actor.health.enabled or actor.constrained or actor.towing or not region.station.contains(actor.pose.origin): continue
		if index<previous_positions.size() and not region.station.contains(previous_positions[index]):
			# A fish that swims into a wall, often while fleeing a shot, turns
			# away at its last free point instead of snapping across a module.
			var away: Array=region.station.avoidance_normal(actor.pose.origin)
			actor.pose.origin=previous_positions[index]
			if not actor.stationary:actor.pose.face(away)
			actor.secondary_pose=actor.pose.copy_pose()
			continue
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

func update_collision_bodies() -> void:
	active_collision_bodies=[region.station]
	var player_global: Array=global_position()
	var anchor: Array=station_origin(session.station_id)
	if collision_scan_origin.is_empty() or Math.vector(Math.subtracted(player_global,collision_scan_origin)).length_squared()>5000.0*5000.0:
		collision_scan_origin=player_global
		nearby_station_ids=[]
		for station in session.stations:
			if station.id==session.station_id:continue
			if Math.vector(Math.subtracted(station_origin(station.id),player_global)).length_squared()<300000.0*300000.0:
				nearby_station_ids.append(station.id)
	for id in nearby_station_ids:
		if not physical_neighbors.has(id):
			var station: Dictionary=session.stations[id]
			var body=StationBody.new()
			body.configure(station,session.is_colonist_station(id),region.sine,session.data.get("station_geometry",{}))
			var offset: Array=Math.subtracted(station_origin(id),anchor)
			for shape in body.shapes:shape.origin=Math.added(shape.origin,offset)
			physical_neighbors[id]=body
		var neighbor=physical_neighbors[id]
		var delta: Array=Math.subtracted(station_origin(id),player_global)
		if Vector3(delta[0],delta[1],delta[2]).length()<neighbor.extent+40000:
			active_collision_bodies.append(neighbor)
	for actor in region.enemies+region.friends:
		if not ship_collisions:break
		if not actor.collision_enabled or not actor.health.enabled or actor.health.hull<=0:continue
		if actor.shapes.is_empty() and (actor.model_id<12 or actor.model_id==19):
			var shape:=CollisionShape.new()
			shape.origin=actor.pose.origin.duplicate()
			shape.half_size=[actor.radius,actor.radius,actor.radius]
			actor.shapes=[shape]
		if not actor.shapes.is_empty():
			# A freighter's hull box turns with the freighter.
			if actor is SpecialActor and actor.kind=="freighter":
				for shape in actor.shapes:shape.origin=actor.pose.origin.duplicate();shape.basis=actor.pose.basis()
			active_collision_bodies.append(actor)
	var steering: Array=[]
	for body in active_collision_bodies:
		if body is StationBody:steering.append_array(repellers_of(body))
		else:steering.append(body)
	region.player.collision_groups=[steering,gate_repellers()]

func repellers_of(body) -> Array:
	"""A station's walls grown by the repel margin. A hull inside one is turned
	away from the nearest face instead of being stopped against the wall, where
	the walls themselves would only act once it was already stuck inside."""
	var id: int=body.get_instance_id()
	if not station_repellers.has(id):
		var zones: Array=[]
		for shape in body.shapes:
			var zone:=CollisionShape.new();zone.origin=shape.origin.duplicate();zone.offset=shape.offset.duplicate()
			zone.half_size=[shape.half_size[0]+STATION_REPEL_MARGIN,shape.half_size[1]+STATION_REPEL_MARGIN,shape.half_size[2]+STATION_REPEL_MARGIN]
			zones.append(zone)
		station_repellers[id]=zones
	return station_repellers[id]

func gate_repellers() -> Array:
	var result: Array=[]
	for i in region.gates.size():
		if region.gate_index(i)!=i:continue
		var shape:=CollisionShape.new();shape.origin=region.gates[i].duplicate();shape.half_size=GATE_REPEL_HALF.duplicate();shape.radial=true
		if i==arrival_exit:
			if shape.contains(region.player.pose.origin):continue
			arrival_exit=-1
		result.append(shape)
	return result

func collides_station(point: Array) -> bool:
	if region.station.contains(point):return true
	for body in active_collision_bodies:
		if body==region.station or not body is StationBody:continue
		if body.contains(point):return true
	return false

func collision_shapes() -> Array:
	var result: Array=[]
	for body in active_collision_bodies:
		# bb turns away from a vessel using its contact normal. Hard correction
		# belongs to stationary walls: correcting a moving hull's overlap every
		# step could carry a submarine along with that hull, even across depth limits.
		if body!=region.station and body is not StationBody:continue
		result.append_array(body.shapes)
	return result

func inside_any_body(point: Vector3, shapes: Array) -> bool:
	for shape in shapes:
		if shape.local_box(region.player.radius).has_point(shape.to_local(point)):return true
	return false

func resolve_body_contact(previous: Array) -> void:
	if region.cinematic():return
	var shapes: Array=collision_shapes()
	var start: Vector3=Math.vector(previous)
	var finish: Vector3=Math.vector(region.player.pose.origin)
	for shape in shapes:
		# In the box's own frame, so a turned hull is met at its hull.
		var box: AABB=shape.local_box(region.player.radius)
		var near: Vector3=shape.to_local(start);var far: Vector3=shape.to_local(finish)
		if box.has_point(near):
			if not box.has_point(far):continue
			var half: Vector3=box.size*0.5
			var best: Vector3=finish;var distance:=INF
			for axis in 3:
				for side in [-1.0,1.0]:
					var local: Vector3=far
					local[axis]=side*(half[axis]+2.0)
					var candidate: Vector3=shape.to_world(local)
					var travel: float=finish.distance_squared_to(candidate)
					if travel<distance and not inside_any_body(candidate,shapes):best=candidate;distance=travel
			if distance<INF:region.player.pose.origin=Math.array(best)
			region.player.contact=true
			return
		if box.has_point(far) or box.intersects_segment(near,far)!=null:
			# Revert the entire fixed step, including a fast crossing whose
			# endpoints lie on opposite sides of a thin hull or station wall.
			region.player.pose.origin=previous;region.player.contact=true
			return

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
			region.player.set_throttle(0);cancel_autopilot(tr("Route blocked by a station within safe depth · choose another approach"));return
	if not avoidance_path.is_empty():
		region.player.autopilot_target=math.array(avoidance_path[0]-anchor)
		# A detour uses the same collision-checked 40 ms steps at every rate.
		# Passing an unrelated station must not replace the selected time speed.
