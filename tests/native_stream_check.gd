extends SceneTree
const Session=preload("res://native/simulation/session.gd")
const World=preload("res://native/simulation/world.gd")
const Save=preload("res://native/simulation/save_store.gd")
const Region=preload("res://native/simulation/region.gd")
const Map=preload("res://native/presentation/overworld_map.gd")
var failures := 0
func expect(value: bool, why: String) -> void:
	if not value: failures+=1; push_error(why)
func _initialize() -> void: call_deferred("checks")
func checks() -> void:
	var content=load("res://native/content.gd").new()
	expect(content.load_cache(OS.get_cmdline_user_args()[0]),"Content loads")
	var owner=Session.new(); owner.new_game(content.data,"STREAM test",91)
	while owner.campaign.chapter<48: owner.campaign.next_chapter(owner.counters)
	owner.campaign.primary.kind=-1; owner.prepare_station(0)
	var world=World.new(); world.configure(owner); world.depart()
	var base: float = world.stream_range()
	expect(is_equal_approx(world.map_kilometers(base),10.0),"Medium short spacing gives a 10 km base STREAM radius")
	var reachable: Array = []
	for engine in [-1,29,30,31]:
		if engine>=0: owner.ship.equip(owner.make_equipment(engine))
		var count := 0
		for station in owner.stations:
			if world.stream_distance(station.id)<world.stream_range(): count+=1
		reachable.append(count)
		expect(is_equal_approx(world.stream_range()/base,1.0 if engine<0 else {29:1.3,30:1.6,31:2.3}[engine]),"Engine percentage scales actual transfer reach")
		if engine>=0:
			for item in owner.ship.equipment.duplicate():
				if item!=null and item.id==engine:owner.ship.remove(item)
	expect(reachable[0]<reachable[1] and reachable[1]<reachable[2] and reachable[2]<reachable[3],"Each engine reaches more actual stations")
	var target := -1
	var distant := -1
	for station in owner.stations:
		if target<0 and station.id!=0 and world.stream_denial(station.id).is_empty(): target=station.id
		if station.id!=0 and station.depth>=owner.ship.minimum_depth and station.depth<=owner.ship.maximum_depth and world.stream_distance(station.id)>base*2.3: distant=station.id
	expect(target>=0 and distant>=0,"Atlas has usable near and far destinations")
	var before: Dictionary = Save.capture(owner)
	expect(not world.plan_stream(distant) and not world.plan_stream(-1),"Out-of-range and invalid STREAM plans are rejected")
	expect(Save.capture(owner)==before and world.stream_destination<0,"Rejected plans preserve the expedition")
	expect(world.route_to(distant),"Continuous autopilot still allows travel beyond engine reach")
	expect(world.plan_stream(target),"Available transfer guides to the exit gate")
	expect(world.local_target==world.region.gates[0] and world.destination<0,"STREAM approach is local rather than a flight to the destination station")
	# Isolate the navigation/transfer mechanism from separately tested ambient AI.
	for actor in world.region.enemies+world.region.friends:
		actor.health.hull=0; actor.health.enabled=false
	var start: Array = world.region.player.pose.origin.duplicate()
	for tick in 3000:
		world.advance(0.04)
		if world.at_gate(0) and world.gate_time[0]>=world.GATE_OPEN_MS: break
	expect(world.at_gate(0) and world.gate_time[0]>=world.GATE_OPEN_MS and world.region.player.pose.origin!=start,"Real fixed-step flight reaches and opens the gate")
	world.cancel_autopilot()
	expect(world.stream_destination==target,"Manual approach keeps the selected transfer")
	# Transfer at a controlled damaged state: no departure repair, extra contract
	# jump, payment, mission acknowledgement or fabricated elapsed travel time.
	world.region.player.health.hull=31; world.region.player.health.shield=7; world.region.player.health.armor=11
	world.region.player.boost_timer=-4321; world.region.loadout.all_weapons()[0].elapsed=234
	owner.medals.pirates=3; owner.medals.catches=4
	var journey_count: int = owner.counters.q; var jumps: int = owner.campaign.secondary.jumps
	var time: int = owner.elapsed_ms; var credits: int = owner.credits
	expect(world.stream_transfer(),"Ready exit gate transfers to the selected station")
	expect(owner.station_id==target and not owner.docked and owner.entered_gate,"Transfer arrives in flight in the destination region")
	expect(world.region.player.pose.origin==world.region.gates[1] and world.region.player.depth==owner.stations[target].depth,"Arrival uses the source entry gate and correct depth")
	var arrival: Transform3D=world.region.player.pose.godot_transform()
	expect((-arrival.basis.z).dot(-arrival.origin.normalized())>.999,"The arriving ship points through the gate toward its station")
	expect(world.region.player.health.hull==31 and world.region.player.health.shield==7 and world.region.player.health.armor==11,"Transfer preserves all damage layers")
	expect(world.region.player.boost_timer==-4321 and world.region.loadout.all_weapons()[0].elapsed==234,"Transfer preserves live flight cooldowns")
	expect(owner.medals.pirates==3 and owner.medals.catches==4 and owner.credits==credits,"Transfer neither settles nor resets the expedition")
	expect(owner.counters.q==journey_count+1 and owner.campaign.secondary.jumps==jumps and owner.elapsed_ms==time,"Transfer counts one journey without an extra departure or elapsed time")
	expect(world.stream_destination<0 and not world.autopilot and world.speed==1 and not world.stream_transfer(),"Arrival clears the plan and cannot repeat the jump")
	expect(world.gate_time[world.region.gate_index(1)]==world.GATE_OPEN_MS,"Arrival opens the visible shared portal")
	# Leave the arrival portal and let it close before testing a fresh opening.
	world.region.player.pose.origin[0]+=16000;world.update_gates(1000)
	expect(world.plan_stream(0),"Return transfer is in range")
	world.region.player.pose.origin=world.region.gates[0].duplicate(); world.update_gates(world.GATE_OPEN_MS/2)
	expect(not world.stream_transfer() and owner.station_id==target,"Partly opened gate cannot transfer early")
	expect(world.gate_frame(0)>0 and world.gate_frame(0)<20,"Gate has intermediate opening frames")
	world.region.player.pose.origin[0]+=15000; world.update_gates(40)
	expect(not world.at_gate(0) and world.gate_closing[0]>0,"Strict 150 m boundary starts the closing animation")
	world.update_gates(1000); expect(world.gate_frame(0)==0,"Gate returns to its closed pose")
	world.region.player.pose.origin=world.region.gates[0].duplicate()
	world.region.success={"kind":1}; world.update_gates(1000)
	expect(world.gate_time[0]==0 and not world.plan_stream(0),"Active encounter locks transfers and the exit gate")
	world.region.success=null; owner.campaign.chapter=1
	expect(not world.tutorial_travel_locked(),"Open-world travel is available from the start")
	world.dispose()
	var tutorial=Session.new(); tutorial.new_game(content.data,"STREAM tutorial destination",91)
	while tutorial.campaign.chapter<5: tutorial.campaign.next_chapter(tutorial.counters)
	tutorial.prepare_station(0)
	var choice=World.new(); choice.configure(tutorial); choice.depart()
	var alternate := -1
	for station in tutorial.stations:
		if station.id not in [0,1] and choice.stream_denial(station.id).is_empty(): alternate=station.id; break
	expect(alternate>=0 and choice.plan_stream(alternate),"First combat tutorial permits another reachable destination")
	choice.region.player.pose.origin=choice.region.gates[0].duplicate(); choice.update_gates(640)
	expect(choice.stream_transfer(),"Tutorial gate accepts the selected destination")
	expect(tutorial.campaign.primary.destination==1 and choice.region.success==null,"Exploration leaves the imported mission at its intended destination")
	choice.dispose()
	check_split_gates(content)
	# Exercise the production atlas action and render model binding, including
	# layout and remapped interaction keys. Test saves/settings are isolated.
	var app=load("res://native/gameplay.gd").new(); app.content=content
	app.save_path="user://test-stream.json"; app.settings_path="user://test-stream-settings.cfg"; root.add_child(app)
	await process_frame; app.set_process(false); app.view.set_process(false); app.close_page()
	while app.session.campaign.chapter<48: app.session.campaign.next_chapter(app.session.counters)
	app.session.campaign.primary.kind=-1; app.session.campaign.active=load("res://native/simulation/mission.gd").new()
	app.world.region.success=null; app.world.region.failure=null
	app.key_bindings.dock=KEY_R; app.map_destination=target; app.show_map()
	for _i in 3: await process_frame
	expect(not app.stream_button.disabled and app.map_info.text.contains("S.T.R.E.A.M."),"Atlas exposes the reachable transfer and engine range")
	expect(root.get_visible_rect().encloses(app.map_widget.get_global_rect()),"Atlas fits the viewport with transfer controls")
	await check_zone(app,target)
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED
	for size in [Vector2i(800,600),Vector2i(1280,720),Vector2i(1920,1080)]:
		root.size=size
		for _i in 3: await process_frame
		expect(root.get_visible_rect().encloses(app.map_widget.get_global_rect()),"STREAM map fits "+str(size))
	root.size=Vector2i(1280,720)
	for _i in 3: await process_frame
	app.stream_button.pressed.emit()
	expect(app.page.is_empty() and app.world.stream_destination==target,"Atlas button starts the actual gate approach")
	app.view._process(0.04)
	var portals: int=2 if Region.split_gates else 1
	expect(app.view.gate_nodes.filter(func(node):return node.visible).size()==portals and app.view.gate_nodes[0].record.id==15,"The STREAM gates display as imported portals, one per physical gate")
	var portal: Transform3D=app.view.gate_nodes[0].transform
	expect((-portal.basis.z).dot(-portal.origin.normalized())>.999,"The visible portal faces its station in the same frame as arriving ships")
	app.world.region.player.pose.origin=app.world.region.gates[0].duplicate(); app.world.update_gates(640); app.view._process(0.04)
	expect(app.view.gate_nodes[0].sampled_frame==app.world.gate_frame(0),"Gate model follows simulation opening state")
	app.update_markers()
	expect(app.markers.any(func(marker): return marker.visible and marker.text.begins_with("S.T.R.E.A.M.") and marker.text.contains("· Transit control")),"Ready gate advertises its transit control menu")
	# br.a: at the open gate the pilot is told which key enters (text 270);
	# only the autopilot's own approach goes on to the chart by itself.
	app.world.cancel_autopilot();app.stream_prompted=false
	app.check_stream_proximity()
	expect(app.page.is_empty(),"A pilot at an open gate is not pulled into the chart")
	app.gameplay_hints=false;app._process(0)
	expect(app.dock_prompt.visible and app.dock_prompt.text.contains("Enter the S.T.R.E.A.M.") and app.dock_prompt.text.contains(OS.get_keycode_string(app.key_bindings.dock)),"The gate says which key enters it")
	app.perform("dock")
	expect(app.page=="stream","The dock key at the gate opens transit control")
	app.close_page()
	expect(app.world.plan_stream(target) and app.world.gate_navigation,"The atlas plan flies to the gate")
	app.stream_prompted=false;app.check_stream_proximity()
	expect(app.page=="stream","An autopilot approach goes straight on to the chart")
	app.close_page()
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name()!="headless":
		app.map_destination=target; app.show_map()
		for _i in 4: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_cmdline_user_args()[2]+"-atlas.png")
		app.close_page(); app.world.region.player.pose.origin=app.world.region.gates[0].duplicate(); app.world.region.player.pose.origin[2]-=24000
		app.world.region.player.pose.face(load("res://native/simulation/fixed_math.gd").normalize_vector(load("res://native/simulation/fixed_math.gd").subtracted(app.world.region.gates[0],app.world.region.player.pose.origin)))
		app.view.previous_camera_mode=-1; app.view._process(0.04); app._process(0)
		for _i in 4: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_cmdline_user_args()[2]+"-gate.png")
	var old_station: int=app.session.station_id
	var old_gate_world: Vector3=app.view.gate_nodes[0].global_position+app.world.geography.anchor
	app.world.enter_region(target);app.view._process(0.04)
	var former: Array=app.view.neighbors[old_station].root.get_children().filter(func(node):return node.has_meta("neighbor_gate"))
	expect(former.size()==portals and (former[0].global_position+app.world.geography.anchor).distance_to(old_gate_world)<0.1,"Crossing a region boundary leaves the previous gates at their world positions")
	expect((app.view.gate_nodes[0].global_position+app.world.geography.anchor).distance_to(old_gate_world)>100.0,"The new station has a separate physical gate")
	# E opens the chart as soon as the gate is in range; nothing advances
	# while it is up, so confirming must not wait for the opening to finish.
	app.view.end_transit();app.stream_exit_active=false
	app.world.region.success=null;app.world.region.failure=null
	app.world.region.player.pose.origin=app.world.region.gates[0].duplicate();app.world.gate_time[0]=app.world.GATE_OPEN_MS/4
	app.show_stream_menu();app.stream_selection=old_station
	expect(app.page=="stream" and app.world.gate_time[0]<app.world.GATE_OPEN_MS,"The chart opens at a gate that is still opening")
	app.begin_stream_transit()
	expect(app.session.station_id==old_station,"Confirming at a part-open gate crosses")
	app.queue_free(); await process_frame
	print("NATIVE_STREAM ",failures," failures · reachable stations ",reachable)
	quit(1 if failures else 0)

func check_split_gates(content) -> void:
	"""The original's two portals: the ship comes out of the IN gate and must
	cross to the OUT gate to leave again. The arrival gate stays shut after the
	ship has left it."""
	var shared: bool=Region.split_gates;Region.split_gates=true
	var owner=Session.new(); owner.new_game(content.data,"STREAM split gates",91)
	while owner.campaign.chapter<48: owner.campaign.next_chapter(owner.counters)
	owner.campaign.primary.kind=-1; owner.prepare_station(0)
	var world=World.new(); world.configure(owner); world.depart()
	var gates: Array=world.region.gates
	expect(gates[0]!=gates[1] and world.region.gate_index(1)==1,"Separate gates keep two portals")
	var target := -1
	for station in owner.stations:
		if station.id!=0 and world.stream_denial(station.id).is_empty(): target=station.id; break
	expect(world.plan_stream(target) and world.local_target==world.region.gates[0],"A departure heads for the OUT gate")
	for actor in world.region.enemies+world.region.friends:
		actor.health.hull=0; actor.health.enabled=false
	world.cancel_autopilot()
	world.region.player.pose.origin=world.region.gates[1].duplicate(); world.update_gates(world.GATE_OPEN_MS+40)
	expect(world.gate_time[1]==0 and not world.stream_transfer(),"The IN gate takes no departures")
	world.region.player.pose.origin=world.region.gates[0].duplicate(); world.update_gates(world.GATE_OPEN_MS+40)
	expect(world.stream_transfer() and owner.station_id==target,"The OUT gate sends the ship on")
	expect(world.region.player.pose.origin==world.region.gates[1] and world.gate_time[1]==world.GATE_OPEN_MS,"Arrival comes out of the open IN gate")
	expect(world.departure_gate==0 and not world.at_gate(0),"The next departure is from the OUT gate, away from the arrival")
	# at/bb.a: each gate turns a hull out of its box, but the ship coming out
	# of the arrival gate starts inside it and is let go.
	var repellers: Array=world.gate_repellers()
	expect(world.arrival_exit==1 and repellers.size()==1 and repellers[0].origin==world.region.gates[0],"The arrival gate does not push back the ship leaving it")
	var inbound: Array=world.region.gates[0].duplicate();inbound[2]+=3000
	world.region.player.pose.origin=inbound;world.region.player.pose.face([0,0,-4096]);world.region.player.set_throttle(100);world.region.player.throttle=100
	world.region.player.collision_groups=[[],world.gate_repellers()]
	var closest: float=INF
	for step in 60:
		world.region.player.advance(40)
		closest=minf(closest,Vector3(world.region.player.pose.origin[0]-world.region.gates[0][0],world.region.player.pose.origin[1]-world.region.gates[0][1],world.region.player.pose.origin[2]-world.region.gates[0][2]).length())
	var away:=Vector3(world.region.player.pose.origin[0]-world.region.gates[0][0],world.region.player.pose.origin[1]-world.region.gates[0][1],world.region.player.pose.origin[2]-world.region.gates[0][2])
	expect(closest>1000 and Vector3(world.region.player.pose.forward[0],world.region.player.pose.forward[1],world.region.player.pose.forward[2]).dot(away)>0,"A hull flown into a gate is turned away from its centre")
	check_station_repel(world)
	world.region.player.pose.origin[0]+=16000; world.update_gates(1000)
	world.region.player.pose.origin=world.region.gates[1].duplicate(); world.update_gates(1000)
	expect(world.gate_time[1]==0,"The IN gate stays shut once the ship has left it")
	expect(world.nearest_safe_gate()==0,"Gate approach picks the OUT gate")
	expect(owner.trail.slice(-2)==[0,target],"The trail records the trip")
	var saved: Dictionary=Save.capture(owner)
	var restored=Save.new().restore(content.data,JSON.parse_string(JSON.stringify(saved)))
	expect(restored!=null and restored.trail==owner.trail,"The trail survives a save")
	var older: Dictionary=JSON.parse_string(JSON.stringify(saved));older.erase("trail")
	var upgraded=Save.new().restore(content.data,older)
	expect(upgraded!=null and upgraded.trail==[owner.station_id],"A save from before the trail still loads, starting it at its station")
	for step in 8: owner.prepare_station(step+1)
	expect(owner.trail.size()==owner.TRAIL_LENGTH and owner.trail.back()==8,"The trail keeps the last six areas")
	world.dispose()
	Region.split_gates=shared
func check_station_repel(world) -> void:
	"""A station turns a hull away as a gate does, a few metres out from where
	its walls would stop it, and leaves a ship coming in to dock alone."""
	var player=world.region.player
	var top=null;var top_z:=-INF
	for shape in world.region.station.shapes:
		var z: float=shape.origin[2]+shape.offset[2]+shape.half_size[2]
		if z>top_z:top_z=z;top=shape
	var wall: float=top_z+player.radius
	var center: Array=[top.origin[0]+top.offset[0],top.origin[1]+top.offset[1],0]
	# Parked just outside the zone, facing the wall, nothing turns the ship.
	player.pose.origin=[center[0],center[1],roundi(wall+world.STATION_REPEL_MARGIN-player.radius+400)]
	player.pose.face([0,0,-4096]);player.set_throttle(0);player.throttle=0
	for step in 10:world.advance(.04,{})
	expect(player.pose.forward[2]<-4000,"A ship close to a station but clear of its walls is not turned")
	# Flown straight at the wall it is turned back out instead of stopping on it.
	player.pose.origin=[center[0],center[1],roundi(wall+6000)];player.pose.face([0,0,-4096]);player.set_throttle(100);player.throttle=100
	var touched:=0
	for step in 150:
		world.advance(.04,{})
		if player.contact and player.pose.origin[2]<=wall+2:touched+=1
	expect(player.pose.forward[2]>0 and player.pose.origin[2]>wall+2000,"A hull flown into a station is turned away and leaves it")
	expect(touched<5,"The hull is not held against the wall")
func check_zone(app, target: int) -> void:
	"""The original's chart: a tap moves a zone, and the side view lists only
	what the zone covers; at the gate the zone stays inside the reach."""
	var chart=app.map_widget
	var inside:=func(): return app.map_slice.ids.all(func(id): return Vector2(app.session.stations[id].x,app.session.stations[id].y).distance_to(chart.lens_center)<=app.ZONE_RADIUS+.001)
	var far: Dictionary={}
	var home: Dictionary=app.session.stations[app.session.station_id]
	for station in app.session.stations:
		if far.is_empty() or Vector2(station.x,station.y).distance_to(Vector2(home.x,home.y))>Vector2(far.x,far.y).distance_to(Vector2(home.x,home.y)):far=station
	chart.select_at(chart.point(far.x,far.y))
	expect(app.map_destination==far.id and far.id in app.map_slice.ids and inside.call(),"Tapping a station moves the zone onto it and the side view lists only the zone")
	# Open water beside stations: the zone moves, but nothing is chosen for the
	# player until they pick one in the side view.
	var water:=Vector2(-1,-1)
	for x in range(2,99,2):
		for y in range(2,99,2):
			var spot:=Vector2(x,y)
			var clear: bool=app.session.stations.all(func(station): return chart.point(station.x,station.y).distance_to(chart.point(spot.x,spot.y))>30)
			if clear and not app.zone_stations(spot).is_empty():water=spot;break
		if water.x>=0:break
	chart.select_at(chart.point(water.x,water.y))
	expect(water.x>=0 and app.map_unchosen and chart.selected_id==-1 and app.map_route_button.disabled,"A zone moved onto open water chooses no station by itself")
	chart.lens_limit=app.world.stream_range()-app.ZONE_RADIUS
	chart.place_lens(Vector2(far.x,far.y))
	expect(chart.lens_center.distance_to(Vector2(home.x,home.y))<=chart.lens_limit+.001,"A bounded zone stops at the edge of the reach")
	chart.lens_limit=-1.0
	# Holding the left button on the zone drags it; letting go settles the choice.
	var start: Vector2=chart.point(chart.lens_center.x,chart.lens_center.y)
	var moved: Array=[]
	chart.zone_moved.connect(func(center,near):moved.append(center),CONNECT_ONE_SHOT)
	var press:=InputEventMouseButton.new();press.button_index=MOUSE_BUTTON_LEFT;press.pressed=true;press.position=start;chart._gui_input(press)
	var motion:=InputEventMouseMotion.new();motion.position=start+Vector2(40,0);chart._gui_input(motion)
	expect(chart.zone_grabbed and chart.lens_center.distance_to(chart.chart_at(start+Vector2(40,0)))<.01,"The zone follows a left-button drag")
	var release:=InputEventMouseButton.new();release.button_index=MOUSE_BUTTON_LEFT;release.pressed=false;release.position=start+Vector2(40,0);chart._gui_input(release)
	expect(not chart.zone_grabbed and moved.size()==1 and inside.call(),"Letting go of the zone updates the side view")
	# A finger on the ring drags the zone; elsewhere it pans; held still it grabs.
	var ring: Vector2=chart.point(chart.lens_center.x,chart.lens_center.y)
	var before_pan: Vector2=chart.pan
	var finger:=InputEventScreenTouch.new();finger.index=0;finger.pressed=true;finger.position=ring;chart._gui_input(finger)
	var slide:=InputEventScreenDrag.new();slide.index=0;slide.position=ring+Vector2(0,30);slide.relative=Vector2(0,30);chart._gui_input(slide)
	expect(chart.zone_grabbed and chart.pan==before_pan and chart.lens_center.distance_to(chart.chart_at(ring+Vector2(0,30)))<.01,"A finger on the zone drags it")
	finger.pressed=false;finger.position=slide.position;chart._gui_input(finger)
	var lens_before: Vector2=chart.lens_center
	var outside: Vector2=chart.point(chart.lens_center.x,chart.lens_center.y)+Vector2(chart.lens_radius*minf(chart.size.x,chart.size.y)*0.0085*chart.zoom+60,0)
	finger.pressed=true;finger.position=outside;chart._gui_input(finger)
	slide.position=outside+Vector2(0,30);chart._gui_input(slide)
	expect(not chart.zone_grabbed and chart.pan!=before_pan and chart.lens_center==lens_before,"A finger off the zone pans the chart")
	finger.pressed=false;finger.position=slide.position;chart._gui_input(finger)
	finger.pressed=true;finger.position=outside;chart._gui_input(finger)
	chart._process(chart.HOLD_MS/1000.0+.05)
	expect(chart.zone_grabbed and chart.lens_center.distance_to(chart.chart_at(outside))<.01,"A finger held still picks the zone up where it rests")
	finger.pressed=false;chart._gui_input(finger)
	# A contract's destination is marked on the chart as the story's is (bp).
	var contract=load("res://native/simulation/mission.gd").new();contract.kind=1;contract.destination=target;contract.destination_name=app.session.stations[target].name
	app.session.campaign.secondary=contract
	expect(Map.marker(app.world,app.session.stations[target]).objective and Map.objectives(app.world,target).size()>=1,"An accepted contract marks its destination")
	app.session.campaign.secondary=load("res://native/simulation/mission.gd").new()
	app.select_station(target)
