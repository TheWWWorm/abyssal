extends SceneTree
const Options=preload("res://native/presentation/ocean_options.gd")
const Headlights=preload("res://native/presentation/headlight_options.gd")
var failures := 0
const SETTINGS := "user://ocean-options-check/settings.cfg"
const SAVE := "user://ocean-options-check/campaign.json"

func expect(ok: bool, why: String) -> void:
	if not ok:failures+=1;push_error(why)
func _initialize() -> void:call_deferred("run")

func press(panel, key: String) -> void:
	var button := panel.find_child("Row_"+key,true,false) as Button
	expect(button!=null and not button.disabled,"The %s option is reachable"%key)
	if button!=null and not button.disabled:
		var list := button.get_node_or_null("List") as OptionButton
		# A dropdown row: take the next choice from its list.
		if list!=null:
			var next := (list.selected+1)%list.item_count
			list.select(next);list.item_selected.emit(next)
		else:button.pressed.emit()
	await process_frame;await process_frame

func dark_cabin(model) -> bool:
	var mesh: MeshInstance3D=model.figure.get_node("Mesh")
	for i in mesh.mesh.get_surface_count():
		if mesh.get_surface_override_material(i).get_shader_parameter("cabin_windows"):return false
	for point in model.figure.get_meta("lamps",[]):
		if point.lamp.get("cabin",false) and point.node.get_node("Light").light_energy>0:return false
	return true

func app_from(cache: String):
	var app=load("res://scenes/native_main.tscn").instantiate()
	app.save_path=SAVE;app.settings_path=SETTINGS
	root.add_child(app)
	if not app.ready_for_preview:app.open_cache(cache)
	await process_frame;await process_frame
	return app

func run() -> void:
	DirAccess.remove_absolute(SETTINGS);DirAccess.remove_absolute(SAVE)
	check_headlight_migration()
	await check_scroll_position()
	var cache := OS.get_cmdline_user_args()[0]
	var app=await app_from(cache)
	app.show_settings("graphics");await process_frame;await process_frame
	expect(Headlights.read(app.settings_panel.load_config())==Headlights.Mode.LIGHT_BEAMS,"New settings default to Light + beams")
	expect(app.settings_panel.find_child("Row_beams",true,false)==null,"A separate contradictory beam switch is no longer shown")
	for mode in [Headlights.Mode.CLASSIC,Headlights.Mode.OFF,Headlights.Mode.LIGHT_ONLY,Headlights.Mode.LIGHT_BEAMS]:
		await press(app.settings_panel,"headlight_mode")
		expect(app.title_dock.view.library.headlight_mode==mode,"Title traffic follows the headlight mode immediately")
	expect(not app.title_dock.view.library.ship_smoothing and not app.title_dock.view.library.station_smoothing,"New settings default to pixelated ship and station textures")
	await press(app.settings_panel,"ship_smoothing")
	expect(app.title_dock.view.library.ship_smoothing and not app.title_dock.view.library.station_smoothing,"Ship smoothing can be enabled independently from its pixelated default")
	await press(app.settings_panel,"ship_smoothing")
	expect(not app.title_dock.view.library.ship_smoothing and not app.title_dock.view.library.station_smoothing,"Ship filtering updates the title independently of station filtering")
	for key in Options.VISUALS:
		expect(app.title_dock.abyss.atmosphere[key]==(key!="blue_headlights"),"Fresh settings enable %s; White/Blue remains a colour choice"%key)
		if not Options.default_on(key):
			expect(not Options.flag(ConfigFile.new(),"graphics",key) and not app.title_dock.abyss.atmosphere[key],"The optional %s experiment starts off"%key)
			await press(app.settings_panel,key)
			expect(app.title_dock.abyss.atmosphere[key],"The title can enable the %s experiment"%key)
		await press(app.settings_panel,key)
		var saved := ConfigFile.new();saved.load(SETTINGS)
		expect(not Options.flag(saved,"graphics",key),"Title saves %s immediately"%key)
		expect(not app.title_dock.abyss.atmosphere[key],"Title water follows %s immediately"%key)
	expect(not app.title_dock.view.library.cabin_lights and not app.title_dock.view.library.bioluminescence,"Title models use the selected lighting")
	# The Classic preset is the original lighting; any other preset returns to Enhanced.
	app.settings_panel.choose_preset(0);await process_frame;await process_frame
	expect(not app.settings_panel.find_child("Row_ship_smoothing",true,false).disabled and not app.title_dock.view.library.ship_smoothing,"Ship filtering remains available and preserves its choice in Classic lighting")
	for key in Options.VISUALS:
		expect(app.settings_panel.find_child("Row_"+key,true,false).disabled,"Classic disables %s"%key)
	app.settings_panel.choose_preset(4);await process_frame;await process_frame
	for key in Options.VISUALS:
		expect(not app.settings_panel.flag("graphics",key,true),"Returning to Enhanced preserves %s"%key)
	app.settings_panel.back();app.launch_game(false,"Options check")
	await process_frame;await process_frame
	var game=current_scene
	expect(game!=null,"The configured title launches a dive")
	if game==null:quit(1);return
	game.set_process(false);game.close_page();game.view._process(0)
	game.view.process_mode=Node.PROCESS_MODE_DISABLED
	game.abyss.set_process(false);game.dive_audio.set_process(false)
	game.show_settings("graphics");await process_frame;await process_frame
	for key in Options.VISUALS:expect(not game.graphics[key],"A new dive reads the saved %s choice"%key)
	expect(dark_cabin(game.view.player_model),"A hull first created with cabins off has no emission or spill")
	var model_id: int=game.view.player_model.get_instance_id()
	expect(not game.graphics.ship_smoothing and not game.view.library.ship_smoothing,"A new dive restores the saved ship filter")
	var ship=game.view.player_model
	var mesh: MeshInstance3D=ship.figure.get_node("Mesh")
	var geometry: Mesh=mesh.mesh
	var neighbor_ship=game.view.model(5)
	for smoothing in [true,false]:
		await press(game.settings_panel,"ship_smoothing")
		expect(game.graphics.ship_smoothing==smoothing and game.view.player_model==ship and mesh.mesh==geometry,"Ship filtering changes immediately without replacing the hull or its collision geometry")
		for hull in [ship,neighbor_ship]:
			var hull_mesh: MeshInstance3D=hull.figure.get_node("Mesh")
			for i in hull_mesh.mesh.get_surface_count():
				var material: ShaderMaterial=hull_mesh.get_surface_override_material(i)
				if material.shader.code.contains("blend_add") or material.shader.code.contains("blend_sub"):continue
				expect(material.shader.code.contains("uniform sampler2D albedo : source_color, "+("filter_linear_mipmap_anisotropic" if smoothing else "filter_nearest_mipmap")),"Player and existing nearby hulls use the chosen texture sampler")
		expect(not game.view.library.station_smoothing,"Ship smoothing leaves the station filter untouched")
	neighbor_ship.queue_free()
	var elapsed: int=game.world.region.elapsed_ms
	var clock: float=game.abyss.ambient_clock
	game.world.region.player.depth=35000
	game.abyss.set_atmosphere(game.graphics)
	var brighter: float=game.abyss.water_gain
	await press(game.settings_panel,"deep_darkness")
	expect(game.abyss.water_gain<brighter,"Depth lighting changes immediately even while frozen")
	await press(game.settings_panel,"regional_water")
	expect(game.abyss.water_tint!=Vector3.ONE and game.abyss.current.length()>0,"Regional water is applied without unpausing")
	await press(game.settings_panel,"filtered_sunlight")
	var day: float=game.abyss.daylight.light_energy
	await press(game.settings_panel,"filtered_sunlight")
	expect(game.abyss.daylight.light_energy<day and game.graphics.deep_darkness,"Sunlight can be disabled independently of deep darkness")
	await press(game.settings_panel,"filtered_sunlight")
	await press(game.settings_panel,"marine_snow")
	expect(game.abyss.particle_material.get_shader_parameter("snow_enabled") and not game.abyss.particle_material.get_shader_parameter("bioluminescence_enabled"),"Snow works with bioluminescence disabled")
	await press(game.settings_panel,"bioluminescence")
	await press(game.settings_panel,"marine_snow")
	expect(not game.abyss.particle_material.get_shader_parameter("snow_enabled") and game.abyss.particle_material.get_shader_parameter("bioluminescence_enabled"),"Bioluminescence works with snow disabled")
	await press(game.settings_panel,"marine_snow")
	await press(game.settings_panel,"cabin_lights")
	expect(not dark_cabin(game.view.player_model) and game.view.player_model.get_instance_id()==model_id,"The existing hull gains light without being replaced")
	await press(game.settings_panel,"cabin_lights")
	game.view.player_model.apply_range([1,2]);game.view.player_model.advance(400)
	expect(dark_cabin(game.view.player_model),"Animation and cached poses cannot restore disabled window lights")
	var another=game.view.model(0)
	expect(dark_cabin(another),"Newly streamed hulls inherit the cabin choice")
	another.queue_free()
	await press(game.settings_panel,"cabin_lights")
	await press(game.settings_panel,"explosion_aftermath")
	var region=game.world.region
	region.visual_event({"kind":"explosion","position":region.player.pose.origin.duplicate(),"creature":false,"delays":[0],"offsets":[],"duration":4000})
	game.view.combat.update(region,0,0)
	expect(not game.view.combat.wrecks.events.is_empty(),"Aftermath is visible when enabled")
	await press(game.settings_panel,"explosion_aftermath")
	expect(game.view.combat.wrecks.events.is_empty() and game.view.combat.wrecks.clouds.multimesh.visible_instance_count==0,"Turning aftermath off clears it while frozen")
	await press(game.settings_panel,"explosion_aftermath")
	var original_tint: Color=game.abyss.daylight.light_color
	var white: Color=game.abyss.lamps[0].light_color
	var neighbor=game.view.model(8);var neighbor_lamps: Array=game.view.add_actor_lights(neighbor)
	expect(game.settings_panel.find_child("Row_blue_headlights",true,false).get_node("Value").text=="White","Headlight colour starts with the existing white presentation")
	await press(game.settings_panel,"blue_headlights")
	var blue: Color=game.abyss.lamps[0].light_color
	expect(blue.b>blue.r*2 and blue.r<white.r and game.view.library.blue_headlights,"Blue headlight colour applies to a frozen dive immediately")
	expect(neighbor_lamps[0].light_color.b>neighbor_lamps[0].light_color.r*2,"Already visible other vessels immediately take the selected headlight colour")
	var neighbor_mesh: MeshInstance3D=neighbor.figure.get_node("Mesh")
	for i in neighbor_mesh.mesh.get_surface_count():
		var material: ShaderMaterial=neighbor_mesh.get_surface_override_material(i)
		if material.get_shader_parameter("headlight_lens"):
			var tint: Color=material.get_shader_parameter("headlight_lens_color")
			expect(tint.b>tint.r*2,"The other vessel's lens changes colour with its beam")
	await press(game.settings_panel,"blue_headlights")
	expect(game.abyss.lamps[0].light_color.is_equal_approx(white),"White headlight colour restores the existing tint")
	expect(neighbor_lamps[0].light_color.is_equal_approx(white),"Other vessels also return to white")
	neighbor.queue_free()
	await press(game.settings_panel,"blue_headlights")
	var rig=load("res://native/presentation/headlight_rig.gd")
	var red := Color(1,.3,.33)
	expect(rig.display_tint(red,false)==red and rig.display_tint(red,true)==red,"Aquarius's red beam colour survives both settings")
	var original_energy: float=game.abyss.daylight.light_energy
	await press(game.settings_panel,"cool_lighting")
	expect(game.abyss.daylight.light_color!=original_tint and is_equal_approx(game.abyss.daylight.light_energy,original_energy),"Cool lighting changes the illumination tint without overriding the depth-based light level")
	await press(game.settings_panel,"cool_lighting")
	expect(game.abyss.daylight.light_color==original_tint,"Turning cool lighting off restores the neutral light")
	await press(game.settings_panel,"cool_lighting")
	expect(region.elapsed_ms==elapsed and game.abyss.ambient_clock==clock,"Comparing every option does not advance a frozen dive")
	await check_headlight_modes(game)
	game.queue_free();await process_frame;await process_frame
	app=await app_from(cache)
	expect(app.title_dock.view.library.headlight_mode==Headlights.Mode.CLASSIC,"A fresh title restores Classic headlights")
	expect(not app.title_dock.view.library.ship_smoothing,"A fresh launch preserves the disabled ship smoothing choice")
	for key in Options.VISUALS:expect(app.title_dock.abyss.atmosphere[key],"A fresh title restores the enabled %s choice"%key)
	app.queue_free();await process_frame;await process_frame
	print("OCEAN_OPTIONS %d failures"%failures);quit(1 if failures else 0)

func check_headlight_migration() -> void:
	for lights in [false,true]:
		for beams in [false,true]:
			var config := ConfigFile.new();config.set_value("graphics","headlights",lights);config.set_value("graphics","beams",beams)
			var expected := Headlights.Mode.OFF if not lights else (Headlights.Mode.LIGHT_BEAMS if beams else Headlights.Mode.LIGHT_ONLY)
			expect(Headlights.read(config)==expected,"Legacy headlight preferences preserve what was actually visible")
			expect(Headlights.previous(config)==(Headlights.Mode.LIGHT_BEAMS if beams else Headlights.Mode.LIGHT_ONLY),"Switching legacy headlights back on preserves the previous beam preference")
			Headlights.write(config,Headlights.Mode.CLASSIC)
			expect(Headlights.read(config)==Headlights.Mode.CLASSIC and not config.has_section_key("graphics","beams"),"One saved mode replaces the old independent flags")
			Headlights.write(config,Headlights.Mode.OFF)
			expect(Headlights.previous(config)==Headlights.Mode.CLASSIC,"Switching off remembers Classic for the light shortcut")

func check_headlight_modes(game) -> void:
	game.session.docked=false;game.view._process(0)
	var neighbor=game.view.model(5);var lamps: Array=game.view.add_actor_lights(neighbor)
	var actor=load("res://native/simulation/npc.gd").new()
	actor.configure(1,2,true,game.world.region.player.pose.origin.duplicate(),game.content.data,game.session.campaign.chapter,game.session.rng)
	actor.state=1;game.world.region.enemies.append(actor)
	for mode in [Headlights.Mode.CLASSIC,Headlights.Mode.OFF,Headlights.Mode.LIGHT_ONLY,Headlights.Mode.LIGHT_BEAMS,Headlights.Mode.CLASSIC]:
		await press(game.settings_panel,"headlight_mode")
		game.view._process(0)
		var light := Headlights.casts_light(mode)
		expect(game.headlight_mode==mode and game.settings_panel.find_child("Row_headlight_mode",true,false).get_node("Value").text==Headlights.NAMES[mode],"Headlights displays its actual mode")
		expect(game.abyss.headlights_enabled==light and game.abyss.beams_enabled==(mode==Headlights.Mode.LIGHT_BEAMS),"Player light and beam state match the single choice")
		for lamp in lamps:
			expect(lamp.visible==light,"Existing nearby ships use the same headlight mode")
		for lamp in game.view.objects[actor.get_instance_id()].lamps:
			expect(lamp.visible==light,"Normal traffic updates cannot restore lights disabled by the mode")
		var newcomer=game.view.model(8);var new_lamps: Array=game.view.add_actor_lights(newcomer)
		for lamp in new_lamps:expect(lamp.visible==light,"Newly streamed ships inherit the headlight mode")
		for hull in [game.view.player_model,neighbor,newcomer]:
			var mesh: MeshInstance3D=hull.figure.get_node("Mesh")
			var source_beams := 0
			for i in mesh.mesh.get_surface_count():
				var material: ShaderMaterial=mesh.get_surface_override_material(i)
				if material.get_shader_parameter("headlight_lens"):
					expect(material.get_shader_parameter("headlight_lens_enabled")==light,"Off and Classic cannot retain the enhanced lens glow")
				if material.get_meta("source_headlight",false):
					source_beams+=1
					expect(material.get_shader_parameter("source_glow_visible")== (mode==Headlights.Mode.CLASSIC),"Classic alone draws the source beam surfaces")
					expect(material.shader.code.contains("filter_nearest, repeat_disable"),"Classic beams keep the original texture sampling")
				elif material.shader.code.contains("blend_add"):
					expect(not material.get_shader_parameter("source_glow_visible"),"Classic headlights do not restore unrelated ship glow")
			expect(source_beams>0,"The imported vessel contains original headlight surfaces")
		newcomer.queue_free()
		# Cached poses and a colour change must not revive another mode's beams.
		neighbor.advance(64);neighbor.apply_stream_visibility();neighbor.apply_headlight_lenses()
		expect(neighbor.headlight_lenses_on==light,"A cached ship pose preserves the headlight state")
	neighbor.queue_free()
	actor.state=3;actor.health.enabled=false;game.view._process(0)
	var wreck=game.view.objects[actor.get_instance_id()].visual
	var wreck_mesh: MeshInstance3D=wreck.figure.get_node("Mesh")
	for i in wreck_mesh.mesh.get_surface_count():
		var material: ShaderMaterial=wreck_mesh.get_surface_override_material(i)
		if material.get_meta("source_headlight",false):expect(not material.get_shader_parameter("source_glow_visible"),"A sunken ship cannot retain Classic beams")
	game.perform("lights")
	expect(game.headlight_mode==Headlights.Mode.OFF,"The light shortcut switches Classic off")
	game.perform("lights")
	expect(game.headlight_mode==Headlights.Mode.CLASSIC,"The light shortcut restores the previous mode")
	game.world.region.enemies.erase(actor)

func check_scroll_position() -> void:
	var previous_size := root.size;root.size=Vector2i(1280,900)
	var ui := Control.new();root.add_child(ui);ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel=load("res://native/presentation/settings_menu.gd").new()
	panel.configure("user://ocean-options-check/scroll.cfg",{});ui.add_child(panel);panel.open("graphics")
	for i in 6:await process_frame
	for offset in [0,100]:
		panel.scroll.scroll_vertical=offset
		for i in 2:await process_frame
		var row: Button=panel.find_child("Row_blue_headlights",true,false)
		var visible_part: Rect2=row.get_global_rect().intersection(panel.scroll.get_global_rect())
		expect(visible_part.has_area(),"The pointer test clicks a visible part of Headlight colour")
		var before: int=panel.scroll.scroll_vertical
		var choice: bool=panel.flag("graphics","blue_headlights",false)
		for down in [true,false]:
			var event := InputEventMouseButton.new();event.position=root.get_final_transform()*visible_part.get_center();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down
			Input.parse_input_event(event);await process_frame
		for i in 4:await process_frame
		expect(panel.flag("graphics","blue_headlights",false)!=choice,"The pointer click actually changes Headlight colour")
		expect(panel.scroll.scroll_vertical==before,"Toggling a visible lower option preserves the exact scroll position")
		expect(root.gui_get_focus_owner()==panel.find_child("Row_blue_headlights",true,false),"The replacement row retains keyboard/controller focus")
	# Keyboard navigation must still reveal offscreen controls after a rebuild.
	panel.scroll.scroll_vertical=0
	for i in 2:await process_frame
	var bottom: Button=panel.find_child("Row_ship_smoothing",true,false);bottom.grab_focus()
	for i in 4:await process_frame
	expect(panel.scroll.follow_focus and panel.scroll.scroll_vertical>0 and panel.scroll.get_global_rect().encloses(bottom.get_global_rect()),"Focus navigation still scrolls an offscreen option into view")
	ui.queue_free();await process_frame;root.size=previous_size
