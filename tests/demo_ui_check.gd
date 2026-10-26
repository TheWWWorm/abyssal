extends SceneTree
var checks:=0
var failures:=0
var capture_root:=""
func expect(ok: bool, why: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(why)
func _initialize() -> void:call_deferred("run")
func settle(count: int=3) -> void:
	for i in count:await process_frame
func click_at(point: Vector2, touch: bool=false) -> void:
	point=root.get_final_transform()*point
	for pressed in [true,false]:
		var event: InputEvent
		if touch:
			event=InputEventScreenTouch.new();event.index=0;event.position=point;event.pressed=pressed
		else:
			event=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.position=point;event.pressed=pressed
		Input.parse_input_event(event);await process_frame
func capture(name: String) -> void:
	if capture_root.is_empty() or DisplayServer.get_name()=="headless":return
	await settle(5);await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(capture_root.path_join(name+".png"))
func key(code: int, pressed: bool=true) -> void:
	var event:=InputEventKey.new();event.physical_keycode=code;event.keycode=code;event.pressed=pressed
	Input.parse_input_event(event);await process_frame
func tap_key(code: int) -> void:
	await key(code);await key(code,false)
func buttons(game) -> Array:
	return game.column.find_children("*","Button",true,false)
func choose(game, id: int) -> void:
	for node in buttons(game):
		if node.get_meta("demo_item",-1)==id:node.pressed.emit();return
	expect(false,"Picker includes requested imported item %d"%id)
func run() -> void:
	preload("decline_reconstruction.gd").attach(self)
	var args:=OS.get_cmdline_user_args()
	if args.size()>1:capture_root=args[1]
	root.size=Vector2i(1280,720)
	var app=load("res://scenes/native_main.tscn").instantiate()
	app.save_path="user://demo-ui/campaign.json";app.settings_path="user://demo-ui/settings.cfg"
	DirAccess.remove_absolute(app.settings_path)
	root.add_child(app);current_scene=app;await settle()
	var menu=app.title_menu
	for i in 6:menu.tap_edition(1000+i*100)
	expect(not app.launching and menu.demo_taps==6,"Six title taps do not launch the secret mode")
	menu.tap_edition(5000)
	expect(menu.demo_taps==1,"A long gap resets the title sequence")
	for i in 6:menu.tap_edition(5100+i*100)
	expect(not app.launching,"The secret cannot bypass the compatible-content requirement")
	await app.open_cache(args[0]);await settle()
	var session=preload("res://native/simulation/session.gd").new();session.new_game(app.content.data,"Keep this campaign",54321)
	var store=preload("res://native/simulation/save_store.gd").new()
	store.write(app.save_path,session);store.write(app.save_path,session)
	var path: String=app.save_path;var bytes:=FileAccess.get_file_as_bytes(path);var backup:=FileAccess.get_file_as_bytes(path+".bak")
	var edition: Vector2=menu.demo_hotspot.get_global_rect().get_center()
	menu.demo_last_tap=-1;menu.demo_taps=0
	for i in 3:await click_at(edition,true)
	expect(menu.demo_taps==3 and not app.launching,"Real touch taps count once, including mouse emulation")
	for i in 3:await click_at(edition)
	expect(menu.demo_taps==6 and not app.launching,"Mouse clicks and touch share the hidden sequence")
	await click_at(edition)
	await settle(40)
	var game=current_scene
	expect(game!=app and game.get_script().resource_path.ends_with("gameplay.gd"),"Seventh activation launches the gameplay scene")
	if game==app:quit(1);return
	expect(game.session.demo_mode and game.page=="demo" and not game.session.docked,"Secret entry opens the range loadout without an opening or station")
	expect(game.session.name!="Keep this campaign","Demo creates a fresh session without loading the campaign")
	expect(game.graphics.depth_limits and not game.graphics.depth_limits_always and game.view.depth_limits and not game.view.depth_limits_always,"A fresh settings file enables depth markers only near the limits")
	var outfit_buttons:=buttons(game).filter(func(b):return b.has_meta("option") and str(b.get_meta("option")).begins_with("demo_"))
	expect(outfit_buttons.all(func(b):return b.icon!=null),"The initial test loadout shows an imported icon for its hull and every equipped system")
	game.show_demo_picker(-1);await settle()
	expect(buttons(game).filter(func(b):return b.has_meta("demo_item")).size()==game.content.data.tables.ships.size(),"Ship selector exposes every imported playable hull")
	expect(buttons(game).filter(func(b):return b.has_meta("demo_item")).all(func(b):return b.icon!=null and b.icon==game.imported_art.item(int(b.get_meta("demo_item")),"ships")),"Every ship selector row displays its own imported hull icon")
	choose(game,10);await settle()
	expect(game.demo_outfit.ship_id==10 and game.demo_outfit.equipment.size()==10 and game.session.ship.id==0,"Ship changes are staged and use the selected hull's slots")
	game.show_demo_picker(0);await settle()
	expect(buttons(game).filter(func(b):return b.has_meta("demo_item")).size()==game.content.data.tables.equipment.size(),"Equipment selector includes all imported systems, including the story weapon")
	expect(buttons(game).filter(func(b):return b.has_meta("demo_item")).all(func(b):return b.icon!=null and b.icon==game.imported_art.item(int(b.get_meta("demo_item")),"equipment")),"Every equipment selector row displays its own imported system icon")
	var search:=game.column.find_child("*",true,false) as LineEdit
	for child in game.column.get_children():
		if child is LineEdit:search=child;break
	search.text="no such equipment 123";search.text_changed.emit(search.text);await settle()
	expect(buttons(game).filter(func(b):return b.has_meta("demo_item") and b.is_visible_in_tree()).is_empty(),"Search filters the complete equipment list")
	search.text="";search.text_changed.emit("");choose(game,42);await settle()
	game.apply_demo();await settle(10)
	expect(game.page.is_empty() and game.session.ship.id==10 and game.session.ship.equipment[0].id==42,"Apply enters flight with the selected real hull and story weapon")
	expect(game.world.region.player.throttle==0 and game.world.region.player.throttle_target==0,"The range starts stopped for immediate inspection")
	game.view.combat.player_wake.append({"at":Vector3.ZERO,"velocity":Vector3.ZERO,"age":.1,"power":.5,"size":.1,"boost":true})
	game.reset_demo()
	expect(game.view.combat.player_wake.is_empty(),"Restarting the same hull clears the previous run's boost wake")
	await capture("range")
	game.touch.mode=2;game.update_render_resolution();await settle()
	game.show_pause();await settle()
	var quick: Array=buttons(game).filter(func(b):return b.text=="Quick weapon test")
	expect(quick.size()==1,"Demo pause offers a quick weapon test")
	quick[0].pressed.emit();await settle()
	var region=game.world.region;var outfit: Array=game.session.ship.equipment.duplicate()
	expect(game.page.is_empty() and game.demo_weapon_bar.visible and game.demo_outfit.quick_weapon==42,"Quick test starts in flight with the fitted weapon selected")
	await capture("quick-desktop")
	await tap_key(KEY_BRACKETRIGHT)
	expect(game.demo_outfit.quick_weapon==0 and game.world.region==region,"Next key wraps to the first weapon without resetting the range")
	await tap_key(KEY_BRACKETLEFT)
	expect(game.demo_outfit.quick_weapon==42,"Previous key returns to the last weapon")
	await tap_key(KEY_TAB)
	expect(game.demo_outfit.quick_weapon==0,"The normal bank key also advances comparison")
	for pressed in [true,false]:
		var pad:=InputEventJoypadButton.new();pad.button_index=JOY_BUTTON_DPAD_LEFT;pad.pressed=pressed;Input.parse_input_event(pad);await process_frame
	expect(game.demo_outfit.quick_weapon==1,"The standard controller bank button cycles test weapons")
	await key(KEY_SPACE);await settle(5)
	expect(region.loadout.all_weapons()[0].launch_serial>0,"Normal fire launches the selected test weapon")
	await tap_key(KEY_BRACKETRIGHT);await settle(5)
	expect(region.loadout.all_weapons()[0].launch_serial==0,"Switching with fire held does not launch the new weapon")
	await key(KEY_SPACE,false);await settle(2);await key(KEY_SPACE);await settle(4);await key(KEY_SPACE,false)
	expect(region.loadout.all_weapons()[0].launch_serial>0,"Releasing and pressing fire auditions the new weapon")
	expect(game.dive_audio.played_log.any(func(entry):return entry.get("bank","")=="gun-iii"),"The first shot after switching plays that weapon's prepared sound")
	game.release_flight_mouse();await settle(2)
	var before_click=region.loadout.all_weapons()[0];var serial_before: int=before_click.launch_serial
	var click:=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT;click.pressed=true;click.position=root.get_final_transform()*game.demo_weapon_bar.next.get_global_rect().get_center()
	Input.parse_input_event(click);await settle(8)
	expect(before_click.launch_serial==serial_before,"Holding the mouse on a selector does not fire the old gun")
	click.pressed=false;Input.parse_input_event(click);await settle(4)
	expect(game.demo_outfit.quick_weapon==3 and region.loadout.all_weapons()[0].launch_serial==0,"A mouse arrow selects once without firing the new gun")
	await tap_key(KEY_BACKSPACE);await settle()
	expect(not game.demo_weapon_bar.visible and game.session.ship.equipment==outfit and region.loadout.all_weapons().size()==2,"Closing comparison restores the fitted weapon banks without changing the outfit")
	game.show_pause();await settle()
	var labels: Array=buttons(game).map(func(b):return b.text)
	expect("Test loadout" in labels and "Reset test area" in labels and not "Transfer save" in labels and not "Reload station checkpoint" in labels,"Demo pause offers testing actions without campaign save operations")
	game.show_demo();await settle();await capture("loadout-desktop")
	for dimensions in [Vector2i(852,393),Vector2i(393,852)]:
		root.size=dimensions;game.touch.mode=1;game.update_render_resolution();await settle()
		game.show_demo();await settle(6)
		expect(game.ui.get_global_rect().encloses(game.overlay.get_global_rect()),"Demo panel fits touch viewport %s"%dimensions)
		var apply: Button=game.overlay.find_child("DemoApply",true,false)
		game.page_scroll.scroll_vertical=10000;await settle()
		expect(apply!=null and game.overlay.get_global_rect().encloses(apply.get_global_rect()) and not game.page_scroll.get_global_rect().intersects(apply.get_global_rect()),"Apply stays visible outside the scrolling outfit at %s"%dimensions)
		game.page_scroll.scroll_vertical=0;await settle()
		expect(game.page_scroll.get_v_scroll_bar().max_value>game.page_scroll.size.y,"Long outfits remain scrollable at %s"%dimensions)
		for node in buttons(game):expect(node.size.y>=44,"Touch target is at least 44 px")
		await capture("loadout-%dx%d"%[dimensions.x,dimensions.y])
		game.start_demo_weapon_test();await settle(6)
		var bar=game.demo_weapon_bar
		expect(game.ui.get_global_rect().encloses(bar.get_global_rect()),"Quick weapon bar fits touch viewport %s"%dimensions)
		expect(bar.title.size.y>=bar.title.get_line_height() and not bar.title.text.is_empty(),"The selected weapon name has a visible line at %s"%dimensions)
		for control in [bar.previous,bar.next,bar.restore]:
			var pixels: Rect2=root.get_final_transform()*control.get_global_rect()
			expect(pixels.size.x>=44 and pixels.size.y>=44,"Quick test has finger-sized targets at %s"%dimensions)
		var before: int=game.demo_outfit.quick_weapon
		var camera_before: Vector2=game.view.look_offset
		var screen: Transform2D=root.get_final_transform()*game.touch.get_global_transform_with_canvas()
		var stick:=InputEventScreenTouch.new();stick.index=4;stick.pressed=true;stick.position=screen*game.touch.stick_home;Input.parse_input_event(stick)
		var looking:=InputEventScreenTouch.new();looking.index=5;looking.pressed=true;looking.position=screen*Vector2(game.ui.size.x*.5,game.ui.size.y*.4);Input.parse_input_event(looking);await settle(1)
		var owners: Dictionary=game.touch.fingers.duplicate()
		await click_at(bar.next.get_global_rect().get_center(),true);await settle(3)
		expect(game.demo_outfit.quick_weapon!=before and game.touch.fingers==owners and game.view.look_offset==camera_before,"Switching preserves concurrent steering and camera fingers at %s"%dimensions)
		stick.pressed=false;looking.pressed=false;Input.parse_input_event(stick);Input.parse_input_event(looking);await settle(1)
		expect(region.loadout.all_weapons()[0].launch_serial==0,"A touch selector tap does not fire at %s"%dimensions)
		await capture("quick-%dx%d"%[dimensions.x,dimensions.y])
		before=game.demo_outfit.quick_weapon
		var point: Vector2=root.get_final_transform()*bar.previous.get_global_rect().get_center()
		var down:=InputEventScreenTouch.new();down.index=9;down.pressed=true;down.position=point;Input.parse_input_event(down);await settle(1)
		var drag:=InputEventScreenDrag.new();drag.index=9;drag.position=point+Vector2(0,65);Input.parse_input_event(drag);await settle(1)
		down.pressed=false;down.position=drag.position;Input.parse_input_event(down);await settle(1)
		expect(game.demo_outfit.quick_weapon==before and game.touch.fingers.is_empty(),"Dragging off a selector cancels without steering at %s"%dimensions)
		await click_at(bar.restore.get_global_rect().get_center(),true);await settle()
		expect(not bar.visible and not game.demo_outfit.quick_test,"Touch close restores fitted weapons at %s"%dimensions)
		game.show_demo_picker(0);await settle(6)
		expect(game.ui.get_global_rect().encloses(game.overlay.get_global_rect()),"Searchable picker fits touch viewport %s"%dimensions)
		await capture("picker-%dx%d"%[dimensions.x,dimensions.y])
	root.size=Vector2i(1280,720);game.touch.mode=2;game.update_render_resolution();await settle()
	# Every exposed route is exercised, including signals arriving late from
	# a picker and save hotkeys outside the normal pause menu.
	game.session.docked=true;game.save_game(false);game.write_slot(path)
	game.show_save_slots();game.show_load_slots();game.show_transfer()
	game.import_transfer("user://must-not-be-read.json")
	game.reload_game(path);await settle()
	expect(game.session.demo_mode and game.session.ship.id==10,"Reload in a demo resets the range without loading a campaign")
	expect(FileAccess.get_file_as_bytes(path)==bytes and FileAccess.get_file_as_bytes(path+".bak")==backup,"Launch, UI, reset, save and transfer routes preserve checkpoint and backup bytes")
	game.return_to_menu();await settle(10)
	expect(current_scene.get_script().resource_path.ends_with("main.gd") and FileAccess.get_file_as_bytes(path)==bytes,"Returning to the title does not save the demo")
	expect(current_scene.title_menu.demo_taps==0,"Hidden entry is not permanently unlocked")
	print("DEMO_UI ",checks," checks; ",failures," failures");quit(1 if failures else 0)
