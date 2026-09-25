extends SceneTree
const Session=preload("res://native/simulation/session.gd")
const World=preload("res://native/simulation/world.gd")
const Region=preload("res://native/simulation/region.gd")
const Layout=preload("res://native/simulation/world_layout.gd")
const Body=preload("res://native/simulation/station_body.gd")
const Math=preload("res://native/simulation/fixed_math.gd")
var checks:=0
var failures:=0
var data: Dictionary
func expect(ok: bool,why: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(why)
func _initialize():call_deferred("run")
func run() -> void:
	data=JSON.parse_string(FileAccess.get_file_as_string(OS.get_cmdline_user_args()[0]))
	for split in [false,true]:
		Region.split_gates=split
		for spacing in [400,600,1000,2000,18850,1234]:check_atlas(spacing)
		check_transit()
	Region.split_gates=false
	check_crowded_map()
	print("GATE_CLEARANCE %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)
func session_fixture():
	var session:=Session.new();session.new_game(data,"Gate clearance",91)
	session.world_layout.spacing_meters=400
	while session.campaign.chapter<48:session.campaign.next_chapter(session.counters)
	session.campaign.primary.kind=-1
	return session
func check_atlas(spacing: int) -> void:
	var session=session_fixture()
	session.world_layout.spacing_meters=spacing
	var sine: Array=data.constants.dt["a:[S"]
	var modules: Array[AABB]=[]
	for station in session.stations:
		var body:=Body.new();body.configure(station,false,sine,data.get("station_geometry",{}))
		for shape in body.shapes:
			var center:=Math.vector(session.world_layout.station_origin(station))+Math.vector(shape.origin)+Math.vector(shape.offset)
			var half:=Math.vector(shape.half_size)
			modules.append(AABB(center-half,half*2.0))
	var state: int=session.rng.state
	var changed:=0
	for station in session.stations:
		var authored: Array=Region.gate_positions(station,sine)
		var placed: Array=session.world_layout.clear_gates(session,station,authored,sine)
		if placed!=authored:changed+=1
		expect(placed==session.world_layout.clear_gates(session,station,authored,sine),"Station %d retains its gate across region rebuilds"%station.id)
		if Region.split_gates:
			# Each portal's 150 m activation cube must not reach the other's.
			expect(Math.subtracted(placed[0],placed[1]).any(func(v):return absi(v)>=30000),"Separate IN and OUT gates do not overlap at station %d"%station.id)
		else:
			expect(placed[0]==placed[1],"Shared arrival and departure slots stay together at station %d"%station.id)
		for gate in (placed if Region.split_gates else [placed[0]]):
			expect(gate[1]==authored[0][1],"Gate relocation preserves safe arrival depth at station %d"%station.id)
			var point:=Math.vector(gate)
			var anchor:=Math.vector(session.world_layout.station_origin(station))
			var heading:=point.normalized()
			# Check the complete 600 m transit segment against the independently
			# assembled imported modules, allowing 180 m for activation and hulls.
			var start:=anchor+point-heading*30000.0
			var finish:=anchor+point+heading*30000.0
			var clear:=true
			for box: AABB in modules:
				if box.grow(18000.0).intersects_segment(start,finish)!=null:clear=false;break
			expect(clear,"Gate and transit corridor clear every station module at station %d"%station.id)
	expect(session.rng.state==state,"Gate placement leaves campaign and encounter randomness unchanged")
	if spacing==400:expect(changed>0,"The compact atlas exercises gate relocation")
	var previous=session.world_layout
	session.new_game(data,"Another import session",17)
	expect(session.world_layout!=previous and session.world_layout.station_bounds.is_empty(),"New sessions cannot inherit another content profile's geometry cache")
	print("GATE_CLEARANCE %d m%s: relocated %d/%d station portals"%[spacing," split" if Region.split_gates else "",changed,session.stations.size()])
func check_crowded_map() -> void:
	# A clear centre is insufficient: a corner of the activation cube can
	# enter a neighbour's 600 m region while the portal remains unobstructed.
	var neighbour:=Vector3(56000,56000,90000)
	var small:=AABB(neighbour-Vector3.ONE*1000,Vector3.ONE*2000)
	var near: Array=[{"id":1,"origin":neighbour,"bounds":small,"parts":[small]}]
	var safe:=Math.vector(Layout.place_gate(Vector3(0,0,90000),Vector3.ZERO,0,near))
	for x in [-15000,15000]:
		for y in [-15000,15000]:
			for z in [-15000,15000]:
				expect((safe+Vector3(x,y,z)).distance_to(neighbour)>=60000,"Activation corners cannot hand off to a neighbouring station")
	# A synthetic compatible map can fill every normal search ring. Exercise
	# the bounded fallback and ensure it does not return an obstructed point.
	var wall:=AABB(Vector3(-400000,-10000,-400000),Vector3(800000,20000,800000))
	var obstacles: Array=[{"id":1,"origin":Vector3.ZERO,"bounds":wall,"parts":[wall]}]
	var point:=Math.vector(Layout.place_gate(Vector3(0,0,90000),Vector3.ZERO,0,obstacles))
	var direction:=point.normalized()
	expect(wall.grow(18000).intersects_segment(point-direction*30000,point+direction*30000)==null,"Crowded-map fallback clears the wall for the entire passage")
	expect(point.y==0,"Crowded-map fallback does not push a gate past pressure limits")
func clear_actors(world) -> void:
	for actor in world.region.enemies+world.region.friends+world.region.creatures:
		actor.health.hull=0;actor.health.enabled=false
func check_transit() -> void:
	# Darhoven's authored gate used to occupy a Salty Void habitat. Travel to
	# the relocated portal, linger there, dock, and fly back to the same gate.
	var session=session_fixture();session.prepare_station(0)
	var world:=World.new();world.spacing_meters=400;world.configure(session);world.depart();clear_actors(world)
	expect(world.plan_stream(1),"Darhoven is available for the arrival regression")
	world.region.player.pose.origin=world.region.gates[world.departure_gate].duplicate()
	world.update_gates(world.GATE_OPEN_MS)
	expect(world.stream_transfer(),"STREAM arrival uses the relocated Darhoven gate")
	clear_actors(world)
	var gate: Array=world.region.gates[world.region.gate_index(1)].duplicate()
	var pose: Transform3D=world.region.player.pose.godot_transform()
	expect((-pose.basis.z).dot(-pose.origin.normalized())>.999,"Relocated arrival faces its own station")
	world.region.player.set_throttle(0);world.region.player.throttle=0
	for tick in 60:world.advance(.04)
	expect(session.station_id==1 and world.region.gates[world.region.gate_index(1)]==gate,"Lingering at Darhoven's gate does not switch to the neighbour's region")
	expect(not world.collides_station(world.region.player.pose.origin),"The arrival hull is outside every station")
	expect(world.route_to(1),"Autopilot can dock after relocated arrival")
	for tick in 3000:
		world.advance(.04)
		if not world.autopilot:break
	expect(session.docked and session.station_id==1,"Real flight from the relocated gate reaches Darhoven's berth")
	expect(world.depart(),"Departing rebuilds the same region")
	clear_actors(world)
	expect(world.region.gates[world.region.gate_index(1)]==gate,"Departure and arrival agree on the portal position")
	expect(world.plan_stream(0),"A return trip targets the relocated portal")
	for tick in 3000:
		world.advance(.04)
		if world.at_gate(0) and world.gate_time[0]>=world.GATE_OPEN_MS:break
	expect(world.at_gate(0) and world.gate_time[0]>=world.GATE_OPEN_MS and session.station_id==1,"Real departure flight reaches the relocated gate without a region handoff")
	world.dispose()
