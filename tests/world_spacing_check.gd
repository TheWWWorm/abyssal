extends SceneTree
const Spacing=preload("res://native/simulation/world_spacing.gd")
const Session=preload("res://native/simulation/session.gd")
const World=preload("res://native/simulation/world.gd")
const Save=preload("res://native/simulation/save_store.gd")
const Math=preload("res://native/simulation/fixed_math.gd")
const RangeText=preload("res://native/presentation/range_text.gd")
var checks:=0
var failures:=0
var data: Dictionary
func expect(ok: bool,why: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(why)
func _initialize():call_deferred("run")
func run() -> void:
	var cache: String=OS.get_cmdline_user_args()[0]
	data=JSON.parse_string(FileAccess.get_file_as_string(cache.path_join("native-data.json")))
	check_preferences()
	check_distance_labels()
	check_geometry()
	check_flight()
	await check_ui(cache)
	print("WORLD_SPACING %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)
func check_preferences() -> void:
	var settings:=Spacing.new();var config:=ConfigFile.new();settings.read_config(config)
	expect(settings.meters()==600,"New and existing profiles without a spacing preference default to Medium short")
	for pair in [[0,400],[1,1000],[2,2000],[3,18850],[4,2345],[5,600]]:
		config.set_value("world","spacing_preset",pair[0]);config.set_value("world","custom_spacing_meters",2345);settings.read_config(config)
		expect(settings.meters()==pair[1],"Stored preset %d keeps its distance when Medium short is inserted"%pair[0])
	for invalid in [null,"2000",NAN,INF,-INF,1e30]:
		config.set_value("world","custom_spacing_meters",invalid);settings.read_config(config)
		expect(settings.custom_meters==600,"Invalid custom preference safely falls back to Medium short")
	for invalid in [-1,6,1.0,"3",null]:
		config.set_value("world","spacing_preset",invalid);settings.read_config(config)
		expect(settings.preset==Spacing.Preset.MEDIUM_SHORT,"Invalid preset falls back to Medium short")
	for below in [-10000,0,399]:expect(Spacing.valid_meters(below)==400,"Custom spacing cannot be less than Short")
	settings.preset=Spacing.Preset.CUSTOM;settings.custom_meters=2345;settings.write_config(config)
	var restored:=Spacing.new();restored.read_config(config)
	expect(restored.preset==Spacing.Preset.CUSTOM and restored.meters()==2345,"Custom selection and distance round-trip together")
func check_distance_labels() -> void:
	for pair in [[0.0,"0 m"],[24.0,"24 m"],[285.0,"285 m"],[995.0,"995 m"],[999.9,"999 m"],[1000.0,"1.00 km"],[1234.0,"1.23 km"],[18850.0,"18.85 km"],[260170.0,"260.17 km"]]:
		expect(RangeText.format_distance(pair[0])==pair[1],"Distance label handles near ranges, the kilometre boundary and long journeys")
func fixture(spacing: int=600):
	var session:=Session.new();session.new_game(data,"Spacing check",91)
	while session.campaign.chapter<48:session.campaign.next_chapter(session.counters)
	session.campaign.primary.kind=-1;session.prepare_station(0)
	var world:=World.new();world.spacing_meters=spacing;world.configure(session);world.depart()
	return world
func check_geometry() -> void:
	var reference=fixture(400)
	var local_parts: Array=reference.region.station.parts.duplicate(true)
	var reach: float=reference.stream_range()
	var denials: Array=reference.session.stations.map(func(station):return reference.stream_denial(station.id))
	reference.dispose()
	for spacing in [400,600,1000,2000,18850,2345]:
		var world=fixture(spacing)
		for station in world.session.stations:
			var origin: Array=world.station_origin(station.id)
			expect(origin==[station.x*spacing*100,station.depth*8,station.y*spacing*100],"World placement uses %d m while preserving depth"%spacing)
			expect(world.geography.stations[station.id].is_equal_approx(Vector3(origin[0],-origin[1],-origin[2])*.01),"Terrain anchors use the same world spacing")
			expect(world.stream_denial(station.id)==denials[station.id],"Scaling preserves STREAM connectivity and engine upgrades")
		expect(world.region.station.parts==local_parts,"Station modules retain their original local dimensions")
		expect(is_equal_approx(world.map_kilometers(reach),reach*spacing/1000.0),"STREAM readout uses active spacing")
		var current: Array=world.global_position();var origin: Array=world.station_origin(1)
		world.spacing_meters=3456
		expect(world.station_origin(1)==origin and world.global_position()==current,"Changing a preference never shifts an active dive")
		world.enter_region(1)
		expect(world.global_position()==current and world.session.world_layout.spacing_meters==spacing,"Ordinary region handoff keeps the dive's existing scale")
		world.session.docked=true
		expect(world.depart(),"A fresh departure can apply pending spacing")
		expect(world.session.world_layout.spacing_meters==3456,"The new spacing takes effect on departure")
		var bounds: Array=world.session.world_layout.volumes(world.session,world.session.data.constants.dt["a:[S"])
		expect(bounds[1].origin==Math.vector(world.station_origin(1)),"Gate geometry cache is rebuilt at the new scale")
		world.dispose()
func clear_ambient(world) -> void:
	for actor in world.region.enemies+world.region.friends:
		actor.health.hull=0;actor.health.enabled=false;actor.state=4
func check_flight() -> void:
	var world=fixture();clear_ambient(world)
	expect(world.route_to(113),"Medium short spacing supports a continuous route to a nearby station")
	for tick in 8000:
		if not world.region.danger():world.speed=16
		world.advance(.04)
		if world.session.docked or not world.autopilot or world.region.failed:break
	expect(world.session.station_id==113 and world.session.docked and not world.region.failed,"Real fixed-step flight reaches and docks at Medium short spacing")
	world.dispose()
func select(control, preset: int) -> void:
	var index: int=control.get_item_index(preset)
	control.select(index);control.item_selected.emit(index)
func check_ui(cache: String) -> void:
	var app=load("res://scenes/native_main.tscn").instantiate()
	app.settings_path="user://world-spacing-check.cfg";app.save_path="user://world-spacing-check.json"
	for path in [app.settings_path,app.save_path,app.save_path+".bak"]:DirAccess.remove_absolute(path)
	root.add_child(app);await process_frame;root.size=Vector2i(800,600);await process_frame
	app.open_cache(cache);app.show_world_settings();await process_frame;await process_frame
	var controls=app.modal.find_child("WorldSpacingPreset",true,false).get_parent()
	expect(controls.selector.get_selected_id()==Spacing.Preset.MEDIUM_SHORT,"Title settings initially select Medium short")
	expect(controls.selector.item_count==6 and controls.selector.get_item_text(1)=="Medium short · 600 m","Medium short appears between Short and Normal")
	select(controls.selector,Spacing.Preset.CUSTOM);controls.custom.value=3456
	select(controls.selector,Spacing.Preset.ORIGINAL);select(controls.selector,Spacing.Preset.CUSTOM)
	expect(controls.custom.visible and controls.custom.value==3456,"Switching presets remembers the custom number")
	controls.custom.get_line_edit().text="399";controls.custom.get_line_edit().text_submitted.emit("399")
	await process_frame;await process_frame
	expect(controls.custom.value==400,"Typed values below Short are clamped to 400")
	controls.custom.value=3456
	for preset in Spacing.ORDER:
		select(controls.selector,preset);await process_frame;await process_frame
		expect(root.get_visible_rect().encloses(app.modal.get_global_rect()),"Spacing option %d fits the title screen: viewport %s, dialog %s"%[preset,root.get_visible_rect(),app.modal.get_global_rect()])
		var stored:=ConfigFile.new();stored.load(app.settings_path);var preference:=Spacing.new();preference.read_config(stored)
		expect(preference.preset==preset and preference.custom_meters==3456,"Title choices persist without losing the custom number")
	select(controls.selector,Spacing.Preset.MEDIUM_SHORT);app.close_modal();app.launch_game(false,"Spacing test")
	await process_frame;await process_frame
	var game=current_scene;game.set_process(false)
	game.view.set_process(false);game.view._process(0)
	for i in 20:game.view.stream_neighbors()
	var old_neighbors: Array=game.view.neighbors.values().map(func(entry):return entry.root)
	expect(not old_neighbors.is_empty(),"Spacing fixture includes visible neighbouring stations")
	expect(game.world.session.world_layout.spacing_meters==600,"Starting an expedition uses the saved Medium short setting")
	game.show_world_settings();await process_frame;await process_frame
	controls=game.column.find_child("WorldSpacingPreset",true,false).get_parent()
	var checkpoint: Dictionary=Save.capture(game.session)
	var position: Array=game.world.global_position();select(controls.selector,Spacing.Preset.HIGH)
	expect(Save.capture(game.session)==checkpoint and game.world.global_position()==position,"Changing settings preserves the expedition and current position")
	expect(game.world.session.world_layout.spacing_meters==600 and game.world.spacing_meters==2000,"High waits for the next departure")
	expect(game.column.find_children("*","Label",true,false).any(func(node):return node.text.contains("Next departure: 2.00 km")),"Settings make pending changes visible in kilometres")
	game.reload_game()
	game.view.rebuild()
	expect(old_neighbors.all(func(node):return node.is_queued_for_deletion()),"Changing scale discards streamed station positions from the old dive")
	expect(game.world.session.world_layout.spacing_meters==2000,"Checkpoint reload uses the saved spacing preference")
	game.world.depart();game.show_map();await process_frame;game.select_station(1)
	expect(game.map_info.text.contains("%.1f / %.1f km"%[game.world.map_kilometers(game.world.stream_distance(1)),game.world.map_kilometers(game.world.stream_range())]),"Map distance and reach match the active scale")
	game.close_page()
	var mission=game.session.campaign.primary;mission.kind=8;mission.completed=false;mission.failed=false;mission.destination=1;mission.destination_name=game.session.stations[1].name
	var target: Array=Math.subtracted(game.world.station_origin(1),game.world.station_origin(game.session.station_id))
	game.world.region.player.pose.origin=Math.added(target,[26017000,0,0]);game.view._process(0);game.update_markers()
	var marker_id: int=game.marker_by_contact.get("station:1",-1)
	expect(marker_id>=0 and game.markers[marker_id].text.contains("260.17 km"),"The actual distant quest marker displays kilometres")
	game.queue_free();await process_frame
	for path in ["user://world-spacing-check.cfg","user://world-spacing-check.json","user://world-spacing-check.json.bak"]:DirAccess.remove_absolute(path)
