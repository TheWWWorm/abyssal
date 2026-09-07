extends SceneTree
const Session = preload("res://native/simulation/session.gd")
const World = preload("res://native/simulation/world.gd")
const Timeline = preload("res://native/simulation/timeline.gd")
var data: Dictionary
var failures := 0
func expect(ok: bool, why: String) -> void:
	if not ok: failures+=1; push_error(why)
func clear_ambient(world) -> void:
	# Controlled travel fixture: terrain, pressure and player movement remain live.
	for actor in world.region.enemies+world.region.friends:
		actor.health.hull=0; actor.health.enabled=false; actor.state=4
func traveler(station_id: int=0, armour: int=-1):
	var session := Session.new(); session.new_game(data,"Sustained travel",91)
	while session.campaign.chapter<48: session.campaign.next_chapter(session.counters)
	if armour>=0:
		for item in session.ship.equipment.duplicate():
			if item!=null and item.kind==4: session.ship.remove(item)
		session.ship.equip(session.make_equipment(armour))
	session.campaign.primary.kind=-1; session.prepare_station(station_id)
	var world := World.new(); world.configure(session); world.depart(); clear_ambient(world)
	return world
func _initialize() -> void:
	data=JSON.parse_string(FileAccess.get_file_as_string(OS.get_cmdline_user_args()[0]))
	var manual=traveler();manual.region.player.pose.origin=[0,0,60000]
	manual.cycle_speed();var manual_time: int=manual.session.elapsed_ms
	manual.advance(.04,{"yaw":1,"throttle":1})
	expect(manual.speed==2 and manual.session.elapsed_ms-manual_time==80 and not manual.autopilot,"Manual steering and throttle retain two fixed ticks at 2x")
	manual.cycle_speed();expect(manual.speed==1,"Manual time cycles back to 1x")
	var slide=traveler();slide.region.player.pose.origin=[0,0,60000];slide.fly_to([900000,0,900000])
	expect(slide.autopilot,"A plotted course engages before the strafe test")
	slide.advance(.04,{"strafe":1})
	expect(not slide.autopilot,"Sliding sideways counts as manual control and drops the course")
	slide.dispose()
	manual.region.player.pose.origin=manual.region.gates[0].duplicate();manual.fly_to([900000,0,900000]);manual.update_gates(1000)
	expect(manual.gate_time[0]==0,"Passing a gate on an unrelated route does not open it")
	manual.fly_to_gate(0);manual.update_gates(1000)
	expect(manual.gate_time[0]>=manual.GATE_OPEN_MS,"Explicit gate navigation opens the intended gate")
	manual.dispose()
	var navigation=preload("res://native/simulation/station_navigation.gd")
	var obstruction:=AABB(Vector3(40000,-4000,-10000),Vector3(20000,8000,20000))
	var detour: Array=navigation.cruise_detour(Vector3.ZERO,Vector3(100000,0,0),[obstruction],-20000,20000)
	expect(detour.size()==2,"A station across the cruise route produces a vertical bypass")
	var previous:=Vector3.ZERO
	for point in detour+[Vector3(100000,0,0)]:
		expect(obstruction.intersects_segment(previous,point)==null,"Every cruise bypass segment clears the entire station")
		previous=point
	var below: Array=navigation.cruise_detour(Vector3.ZERO,Vector3(100000,0,0),[obstruction],-1000,20000)
	expect(not below.is_empty() and below[0].y>obstruction.end.y,"Pressure ceiling selects the lower bypass")
	var slow=traveler(); var fast=traveler()
	for world in [slow,fast]:
		world.region.player.pose.origin=[0,0,60000]; world.fly_to([0,0,400000])
	for frame in 40:
		fast.speed=16
		var before: int = fast.session.elapsed_ms
		fast.advance(0.04)
		for tick in (fast.session.elapsed_ms-before)/40: slow.advance(0.04)
		expect(fast.region.player.pose.values()==slow.region.player.pose.values(),"Sustained warp preserves fixed-step flight")
		expect(fast.session.rng.state==slow.session.rng.state and fast.session.elapsed_ms==slow.session.elapsed_ms,"Sustained warp preserves time and random sequence")
	expect(fast.session.elapsed_ms>=16000,"Warp equivalence covers more than sixteen seconds of simulation")
	for world in [slow,fast]: world.dispose()
	var course_slow=traveler(169,23); var course_fast=traveler(169,23)
	for world in [course_slow,course_fast]: expect(world.route_to(6),"Course equivalence route is permitted")
	for frame in 32:
		course_fast.speed=16
		var before: int = course_fast.session.elapsed_ms
		course_fast.advance(0.04)
		for tick in (course_fast.session.elapsed_ms-before)/40: course_slow.advance(0.04)
		expect(course_fast.region.player.pose.values()==course_slow.region.player.pose.values(),"Course following has identical flight at 1x and 16x")
		expect(course_fast.region.player.autopilot_target==course_slow.region.player.autopilot_target and course_fast.session.rng.state==course_slow.session.rng.state,"Accelerated course targets preserve tick order and randomness")
	for world in [course_slow,course_fast]: world.dispose()
	# A transmission appearing inside a long frame is an immediate pause boundary.
	var paused=traveler(); paused.region.player.pose.origin=[0,0,60000]; paused.fly_to([0,0,400000]); paused.speed=16
	var line := Timeline.new(); line.kind=5; line.values=[120]; paused.region.timeline=[line]
	paused.advance(0.24)
	expect(paused.region.active_transmission==line and paused.session.elapsed_ms==120,"Transmission stops all remaining substeps in a long frame")
	var position: Array = paused.global_position()
	paused.advance(0.24)
	expect(paused.session.elapsed_ms==120 and paused.global_position()==position,"Unacknowledged transmission holds the simulation")
	paused.region.acknowledge_transmission(); paused.region.events=[]; paused.advance(0.04)
	expect(paused.session.elapsed_ms==160 and paused.speed==1,"Acknowledgement resumes at normal speed without old frame debt")
	paused.dispose()
	var completed=traveler(); completed.region.player.pose.origin=[0,0,60000]; completed.fly_to([0,0,400000]); completed.speed=16
	completed.session.campaign.primary.kind=22; completed.region.elapsed_ms=9960; completed.session.elapsed_ms=9960
	completed.advance(0.24)
	expect(completed.region.pending_mission==completed.session.campaign.primary and completed.session.elapsed_ms==10040,"Persistent objective completion stops the current accelerated frame")
	completed.dispose()
	var danger=traveler(); danger.region.player.pose.origin=[0,0,60000]; danger.region.player.pose.set_euler(0,0,0); danger.fly_to([0,0,400000]); danger.speed=16
	var hostile=preload("res://native/simulation/npc.gd").new()
	hostile.configure(2,0,true,[0,0,115100],data,48,danger.session.rng); hostile.health.configure(100,0,0); hostile.state=5; hostile.target_position=[-1000000,0,115100]
	danger.region.enemies=[hostile]; danger.advance(0.04)
	expect(danger.speed==2 and danger.session.elapsed_ms==80 and danger.autopilot,"Entering hostile range interrupts warp inside its substep batch")
	danger.dispose()
	# Mission deadlines consume accelerated simulation time, then stop at failure.
	var timed=traveler(); timed.region.player.pose.origin=[0,0,60000]; timed.fly_to([0,0,400000]); timed.speed=16
	timed.region.time_limit=100; timed.advance(0.24)
	expect(timed.region.failed and timed.session.elapsed_ms==120,"Mission deadline stops at the first fixed tick after expiry")
	expect(timed.region.events.filter(func(event): return event.kind=="mission_failed").size()==1,"Deadline emits one failure event")
	timed.dispose()
	# Three complete continuous legs, with live terrain and original ship limits.
	var journey=traveler(); journey.region.player.health.hull=31; journey.session.hull=31
	journey.session.campaign.secondary.jump_limit=10; journey.session.campaign.secondary.jumps=0
	var total_ms := 0
	for destination in [113,134,0]:
		expect(journey.route_to(destination),"Multi-leg route is inside pressure protection")
		var start: int = journey.session.elapsed_ms
		journey.speed=16
		for tick in 6500:
			journey.advance(0.04)
			if not journey.autopilot or journey.region.failed: break
		expect(journey.session.station_id==destination and not journey.autopilot,"Continuous route reaches station "+str(destination))
		expect(journey.region.player.health.hull<=31 and journey.region.player.health.hull>0,"Travel preserves damage and remains survivable")
		expect(journey.session.elapsed_ms>start,"Each leg consumes simulation time")
		expect(journey.session.campaign.secondary.jumps==0,"Region entries do not charge extra departures")
		total_ms=journey.session.elapsed_ms; clear_ambient(journey)
	expect(total_ms>120000,"Multi-leg journey covers more than two simulated minutes")
	expect(journey.dock(),"Multi-leg arrival permits docking")
	var arrived: int = journey.session.elapsed_ms; journey.advance(0.24)
	expect(journey.session.elapsed_ms==arrived,"Docked journey freezes mission clocks")
	journey.dispose()
	# The original local-target steering drifts vertically over this 19 km
	# course. Actual Crust AMR protection must suffice for the safe destination;
	# expanded pressure limits would conceal the regression.
	var pressure_routes := []
	for leg in [[169,6],[6,169]]:
		var protected=traveler(leg[0],23)
		var state: int = protected.session.rng.state
		expect(protected.route_to(leg[1]),"Long station route is within actual equipment limits")
		for _i in 20: protected.update_course()
		expect(protected.session.rng.state==state,"Course following does not consume gameplay randomness")
		var deepest := 0
		var shallowest := 2147483647
		for frame in 5000:
			if not protected.region.danger(): protected.speed=16
			protected.advance(0.04)
			var depth: int = protected.region.player.depth
			deepest=maxi(deepest,depth); shallowest=mini(shallowest,depth)
			if depth<protected.session.ship.minimum_depth or depth>protected.session.ship.maximum_depth: break
			if not protected.autopilot or protected.region.failed: break
		expect(shallowest>=20000 and deepest<=26800,"Long course remains inside original pressure protection")
		expect(protected.session.station_id==leg[1] and not protected.autopilot and not protected.region.failed,"Protected long course reaches its destination")
		expect(protected.course_start.is_empty() and protected.region.player.autopilot_target==null,"Arrival clears the course follower")
		expect(protected.dock(),"Protected long course permits docking")
		pressure_routes.append({"from":leg[0],"to":leg[1],"minimum":shallowest,"maximum":deepest,"milliseconds":protected.session.elapsed_ms})
		protected.dispose()
	var crossing_ms := 0
	for destination in [29,36]:
		var crossing=traveler(); var r=crossing.region
		# Isolate long-distance terrain avoidance. Expanded protection is a test
		# fixture; the real equipment/pressure gates remain separately covered.
		crossing.session.ship.minimum_depth=500; crossing.session.ship.maximum_depth=50000
		r.dispose(); r.enemies=[]; r.friends=[]; r.creatures=[]; r.fishing=[]; r.weapons=[]; r.loadout.groups=[]
		r.player.collision_groups=[[r.station]]; crossing.attach_geography()
		expect(crossing.route_to(destination),"Long terrain crossing can begin")
		var contacts := 0
		for frame in 40000:
			# Emulate the user re-enabling acceleration after each safe passage.
			if not crossing.region.danger(): crossing.speed=16
			crossing.advance(0.04)
			if crossing.region.player.contact: contacts+=1
			if not crossing.autopilot or crossing.region.failed: break
		expect(not crossing.geography.seafloor_enabled and contacts==0,"Bottomless ocean route has no hidden terrain collisions")
		expect(crossing.session.station_id==destination and not crossing.autopilot and not crossing.region.failed,"Autopilot crosses open water and reaches station "+str(destination))
		expect(crossing.dock(),"Terrain-crossing arrival permits docking")
		crossing_ms+=crossing.session.elapsed_ms; crossing.dispose()
	print("NATIVE_TRAVEL ",failures," failures; multi-leg simulated milliseconds ",total_ms,"; terrain crossings ",crossing_ms,"; pressure routes ",pressure_routes)
	quit(1 if failures else 0)
