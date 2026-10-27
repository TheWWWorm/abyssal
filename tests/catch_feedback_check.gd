extends SceneTree
var checks:=0
var failures:=0
func expect(ok: bool, why: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(why)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var args:=OS.get_cmdline_user_args()
	var content=load("res://native/content.gd").new()
	if args.is_empty() or not content.load_cache(args[0]):quit(1);return
	root.size=Vector2i(1280,720)
	var game=load("res://native/gameplay.gd").new();game.content=content;game.demo_mode=true
	game.settings_path="user://catch-feedback-check.cfg";game.save_path="user://catch-feedback-check.json"
	var config:=ConfigFile.new();config.set_value("input","touch",2);config.set_value("audio","music",0.0);config.save(game.settings_path)
	root.add_child(game);game.set_process(false);game.view.set_process(false);game.abyss.set_process(false)
	for i in 3:await process_frame
	game.apply_demo();game.close_page();game._process(0);game.view._process(0);game.abyss._process(0)
	expect(game.fishing_feedback==game.SettingsMenu.FishingFeedback.BOTH,"Both the on-fish counter and animated fishing line are enabled by default")
	game.fishing_feedback=game.SettingsMenu.FishingFeedback.BOTH
	var region=game.world.region;var hook=region.fishing[0];var weapon=hook.weapon;var fish=region.creatures[0]
	fish.pose.origin=region.player.pose.origin.duplicate();fish.pose.origin[2]-=20000;weapon.targets=[fish]
	weapon.launch(region.player.pose,40,fish)
	weapon.advance(80);game.update_catch_feedback(region,true)
	var first: float=game.struggle.hook_position().x
	expect(game.struggle.visible and game.struggle.stage=="flight" and game.struggle.target_kind=="fish" and not game.struggle.timer.visible,"A cast shows the hook and fish without promising a struggle time before attachment")
	weapon.advance(80);game.update_catch_feedback(region,true)
	expect(game.struggle.hook_position().x>first,"The HUD hook advances with the actual shot")
	var state: Array=weapon.values().duplicate(true)
	game.update_catch_feedback(region,true)
	expect(weapon.values()==state,"The cast diagram does not change weapon physics")
	weapon.remaining.fill(-1);weapon.active=false;hook.attach(fish)
	fish.struggle_total=5000;fish.struggle_remaining=5000;fish.struggle_time=0
	await check_counter(game,hook,fish,args)
	fish.struggle_total=5000;fish.struggle_remaining=5000;fish.struggle_time=0
	game.update_catch_feedback(region,true)
	var far: Vector2=game.struggle.target_position();first=game.struggle.value
	fish.struggle_time=840;game.update_catch_feedback(region,true)
	expect(game.struggle.value>first and game.struggle.stage=="struggle" and game.struggle.timer.text=="9.2 s","The struggle advances continuously and its timer counts down inside the strength interval")
	expect(is_equal_approx(game.struggle.target_position().x,far.x),"A struggling fish is not shown being reeled in early")
	fish.subdued=true;hook.towing=true;hook.capture_distance=400;hook.tow_start_distance=0;hook.tow_speed=10
	game.update_catch_feedback(region,true)
	expect(is_zero_approx(game.struggle.value),"The first tow frame starts at zero before its initial distance is recorded")
	hook.tow_start_distance=10000;fish.pose.origin=region.player.pose.origin.duplicate();fish.pose.origin[0]+=5200
	game.update_catch_feedback(region,true)
	expect(game.struggle.stage=="reel" and absf(game.struggle.value-50)<.1,"The reel diagram uses the same actual distance as its progress")
	expect(game.struggle.target_position().x<far.x and game.struggle.hook_position().x<far.x-16,"The fish and attached hook move together toward the submarine")
	expect(game.struggle.timer.text=="0.5 s" and game.struggle.timer.position.y>game.struggle.target_position().y+10 and absf(game.struggle.timer.get_rect().get_center().x-game.struggle.target_position().x-3.5)<.1,"The collection countdown follows directly below the moving fish")
	var held: Vector2=game.struggle.target_position();game.update_catch_feedback(region,true)
	expect(game.struggle.target_position()==held,"A paused catch does not creep toward collection")
	game.update_catch_feedback(region,false)
	expect(not game.struggle.visible and not game.struggle.timer.is_visible_in_tree(),"Menus and hidden flight HUD hide the complete catch display")
	for dimensions in [Vector2i(1280,720),Vector2i(844,390),Vector2i(390,844)]:
		root.size=dimensions;game.touch.mode=2 if dimensions.x==1280 else 1
		for i in 3:await process_frame
		game._process(0);game.view._process(0);game.abyss._process(0)
		game.layout();game.update_catch_feedback(region,true)
		expect(game.ui.get_global_rect().encloses(game.struggle.get_global_rect()),"The catch diagram fits the safe UI at "+str(dimensions))
		expect(game.struggle.get_global_rect().encloses(game.struggle.timer.get_global_rect()),"The timer fits within the catch display at "+str(dimensions))
		if game.touch.enabled():
			for control in ["stick","guns","hook"]:
				expect(not game.struggle.get_rect().intersects(game.touch.control_rect(control)),"The catch diagram leaves "+control+" free at "+str(dimensions))
		if args.size()>1 and DisplayServer.get_name()!="headless":
			await process_frame;await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(args[1].path_join("reel-%dx%d.png"%[dimensions.x,dimensions.y]))
	hook.release();game.update_catch_feedback(region,true)
	expect(not game.struggle.visible,"Releasing the catch clears its diagram")
	weapon.targets=[];weapon.launch(region.player.pose,40);weapon.advance(80);game.update_catch_feedback(region,true)
	expect(game.struggle.visible and game.struggle.target_kind.is_empty(),"An empty cast does not promise a fish")
	weapon.remaining.fill(-1);weapon.active=false;game.update_catch_feedback(region,true)
	expect(not game.struggle.visible,"A missed or expired hook clears the diagram")
	game.queue_free();await process_frame
	print("CATCH_FEEDBACK ",checks," checks; ",failures," failures");quit(1 if failures else 0)

func place_fish(game, fish, at: Vector3) -> void:
	fish.pose.origin=[roundi(at.x*100),roundi(-at.y*100),roundi(-at.z*100)]
	game.world.previous_render_poses.clear()

func check_counter(game, hook, fish, args: PackedStringArray) -> void:
	var region=game.world.region
	var fishing=game.SettingsMenu.FishingFeedback
	var pose: Array=fish.pose.origin.duplicate()
	var in_front: Vector3=game.camera.global_position-game.camera.global_basis.z*80+game.camera.global_basis.x*12+game.camera.global_basis.y*5
	place_fish(game,fish,in_front)
	fish.struggle_total=2100;fish.struggle_remaining=2100;fish.struggle_time=0;fish.subdued=false
	game.update_catch_counter()
	expect(game.catch_counter.visible and game.catch_counter.text=="3","A hooked fish shows the original remaining struggle count beside its rendered position")
	var before: Vector2=game.catch_counter.position
	var point: Vector2=game.ui.get_global_transform().affine_inverse()*game.camera.unproject_position(in_front)
	expect(game.catch_counter.get_rect().end.y<point.y and game.catch_counter.position.x>point.x,"The counter sits above and to the right of the fish")
	fish.advance(2000,game.session.rng,region.player.pose.origin,region.player.pose.forward)
	place_fish(game,fish,in_front);game.update_catch_counter()
	expect(game.catch_counter.text=="2" and fish.struggle_remaining==1100,"The counter decreases with the fish's actual two-second struggle step")
	fish.advance(2000,game.session.rng,region.player.pose.origin,region.player.pose.forward)
	place_fish(game,fish,in_front);game.update_catch_counter()
	expect(game.catch_counter.text=="1" and fish.struggle_remaining==100,"A partial final struggle keeps the original last count")
	for i in 5:game.update_catch_counter()
	expect(fish.struggle_remaining==100 and fish.struggle_time==0,"Rendering the counter never advances the struggle")
	place_fish(game,fish,in_front+game.camera.global_basis.x*8);game.update_catch_counter()
	expect(game.catch_counter.position.x>before.x+10,"The counter follows the fish instead of staying at the scanner centre")
	place_fish(game,fish,game.camera.global_position+game.camera.global_basis.z*80);game.update_catch_counter()
	expect(not game.catch_counter.visible,"A fish behind the camera has no counter")
	place_fish(game,fish,in_front+game.camera.global_basis.x*1000);game.update_catch_counter()
	expect(not game.catch_counter.visible,"An off-screen fish has no edge-pinned counter")
	place_fish(game,fish,in_front)
	var blocker:=StaticBody3D.new();blocker.collision_layer=2;blocker.collision_mask=0
	var shape:=CollisionShape3D.new();var bounds:=BoxShape3D.new();bounds.size=Vector3(8,8,8);shape.shape=bounds;blocker.add_child(shape)
	game.view.add_child(blocker);blocker.global_position=game.camera.global_position.lerp(in_front,.5)
	await physics_frame;await physics_frame;game.update_catch_counter()
	expect(not game.catch_counter.visible,"Station walls occlude the counter with the fish")
	blocker.queue_free();await physics_frame;await physics_frame
	game.show_pause();game.update_catch_counter()
	expect(not game.catch_counter.visible,"Pause hides the counter")
	game.close_page();game.show_action_freeze();game.update_catch_counter()
	expect(not game.catch_counter.visible and fish.struggle_remaining==100,"Action freeze hides the counter without changing the remaining struggle")
	game.end_action_freeze(true)
	for mode in [fishing.LINE,fishing.TIMER,fishing.BOTH,fishing.NONE]:
		game.show_settings("gameplay");await process_frame;await process_frame
		var option: Button=game.settings_panel.find_option(game.settings_panel.column,"fishing_feedback")
		var choices: OptionButton=option.get_node("List")
		expect(choices.item_count==4 and choices.get_item_text(mode)==["Fishing line","Timer on fish","Both","None"][mode],"Fishing feedback offers the requested choice "+str(mode))
		choices.select(mode);choices.item_selected.emit(mode);await process_frame
		game.close_page();game.update_catch_feedback(region,true);game.update_catch_counter()
		expect(game.struggle.visible==(mode in [fishing.LINE,fishing.BOTH]) and game.catch_counter.visible==(mode in [fishing.TIMER,fishing.BOTH]),"Selecting fishing feedback immediately controls both displays: "+str(mode))
		game.fishing_feedback=-1;game.read_settings()
		expect(game.fishing_feedback==mode,"Fishing feedback survives a settings reload: "+str(mode))
	game.fishing_feedback=fishing.BOTH;game.save_settings()
	for dimensions in [Vector2i(1280,720),Vector2i(844,390),Vector2i(390,844),Vector2i(320,568)]:
		root.size=dimensions;game.touch.mode=2 if dimensions.x==1280 else 1
		for i in 3:await process_frame
		game._process(0);game.view._process(0);game.abyss._process(0);game.layout()
		in_front=game.camera.global_position-game.camera.global_basis.z*80+game.camera.global_basis.y*5
		place_fish(game,fish,in_front);game.view._process(0);game.update_catch_counter()
		expect(game.catch_counter.visible and game.ui.get_global_rect().encloses(game.catch_counter.get_global_rect()),"The on-fish counter fits at "+str(dimensions))
		if args.size()>1 and DisplayServer.get_name()!="headless":
			await process_frame;await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(args[1].path_join("fish-counter-%dx%d.png"%[dimensions.x,dimensions.y]))
		game.show_settings("gameplay")
		for i in 3:await process_frame
		var panel=game.settings_panel
		var option: Button=panel.find_option(panel.column,"fishing_feedback")
		panel.scroll.ensure_control_visible(option)
		for i in 2:await process_frame
		expect(game.ui.get_global_rect().encloses(panel.get_global_rect()),"Settings fit the safe UI at "+str(dimensions))
		expect(panel.get_global_rect().encloses(option.get_global_rect()),"The fishing dropdown row fits at "+str(dimensions))
		var choices: OptionButton=option.get_node("List")
		for selected in choices.item_count:
			panel.show_value(option,choices.get_item_text(selected))
			await process_frame
			expect(option.get_rect().size.x>=option.get_combined_minimum_size().x and option.size.y>=option.get_combined_minimum_size().y,"The fishing row fits its title and "+choices.get_item_text(selected)+" at "+str(dimensions))
		panel.show_value(option,choices.get_item_text(choices.selected))
		option.pressed.emit();await process_frame
		var popup:=choices.get_popup()
		expect(popup.visible and root.get_visible_rect().encloses(Rect2(popup.position,popup.size)),"All four dropdown choices fit on screen at "+str(dimensions)+": "+str(Rect2(popup.position,popup.size))+" in "+str(root.get_visible_rect()))
		if args.size()>1 and DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(args[1].path_join("fishing-settings-%dx%d.png"%[dimensions.x,dimensions.y]))
		popup.hide();game.close_page()
	fish.subdued=true;game.update_catch_counter()
	expect(not game.catch_counter.visible,"The struggle counter ends when the fish is subdued, before reeling starts")
	fish.subdued=false;hook.towing=true;game.update_catch_counter()
	expect(not game.catch_counter.visible,"Reeling never leaves a stale struggle count beside the fish")
	hook.towing=false;hook.hooked=false;game.update_catch_counter()
	expect(not game.catch_counter.visible,"Releasing a fish clears the counter")
	hook.hooked=true;fish.pose.origin=pose;game.world.previous_render_poses.clear()
	root.size=Vector2i(1280,720);game.touch.mode=2
	for i in 3:await process_frame
	game._process(0);game.view._process(0);game.abyss._process(0);game.layout()
