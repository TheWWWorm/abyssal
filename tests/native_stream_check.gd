extends SceneTree
const Session=preload("res://native/simulation/session.gd")
const World=preload("res://native/simulation/world.gd")
const Save=preload("res://native/simulation/save_store.gd")
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
	expect(is_equal_approx(base*400,6666.6666667),"Base STREAM radius is one sixth of the 40 km atlas")
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
	expect(world.region.player.health.hull==31 and world.region.player.health.shield==7 and world.region.player.health.armor==11,"Transfer preserves all damage layers")
	expect(world.region.player.boost_timer==-4321 and world.region.loadout.all_weapons()[0].elapsed==234,"Transfer preserves live flight cooldowns")
	expect(owner.medals.pirates==3 and owner.medals.catches==4 and owner.credits==credits,"Transfer neither settles nor resets the expedition")
	expect(owner.counters.q==journey_count+1 and owner.campaign.secondary.jumps==jumps and owner.elapsed_ms==time,"Transfer counts one journey without an extra departure or elapsed time")
	expect(world.stream_destination<0 and not world.autopilot and world.speed==1 and not world.stream_transfer(),"Arrival clears the plan and cannot repeat the jump")
	expect(world.gate_time[world.region.gate_index(1)]==world.GATE_OPEN_MS,"Arrival opens the visible shared portal")
	# Leave the arrival portal and let it close before testing a fresh opening.
	world.region.player.pose.origin[0]+=16000;world.update_gates(1000)
	expect(world.plan_stream(0),"Return transfer is in range")
	world.region.player.pose.origin=world.region.gates[0].duplicate(); world.update_gates(400)
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
	expect(not app.stream_button.disabled and app.map_info.text.contains("STREAM"),"Atlas exposes the reachable transfer and engine range")
	expect(root.get_visible_rect().encloses(app.map_widget.get_global_rect()),"Atlas fits the viewport with transfer controls")
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
	expect(app.view.gate_nodes.filter(func(node):return node.visible).size()==1 and app.view.gate_nodes[0].record.id==15,"Nearby STREAM pair displays one imported portal")
	app.world.region.player.pose.origin=app.world.region.gates[0].duplicate(); app.world.update_gates(640); app.view._process(0.04)
	expect(app.view.gate_nodes[0].sampled_frame==app.world.gate_frame(0),"Gate model follows simulation opening state")
	app.update_markers()
	expect(app.markers.any(func(marker): return marker.visible and marker.text.contains("STREAM · Transit control")),"Ready gate advertises its transit control menu")
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
	app.queue_free(); await process_frame
	print("NATIVE_STREAM ",failures," failures · reachable stations ",reachable)
	quit(1 if failures else 0)
