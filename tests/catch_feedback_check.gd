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
