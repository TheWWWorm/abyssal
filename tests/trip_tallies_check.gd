extends SceneTree
var checks := 0
var failures := 0
func expect(ok: bool, why: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(why)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var args := OS.get_cmdline_user_args()
	var content=load("res://native/content.gd").new()
	if args.is_empty() or not content.load_cache(args[0]):quit(1);return
	var session=preload("res://native/simulation/session.gd").new();session.new_game(content.data,"Tallies",314)
	expect(session.register_catch(0,1) and session.medals.catches==1 and session.counters.h==1,"One live catch increments both fishing records once")
	for species in range(13,18):
		session.ship.set_cargo([])
		expect(session.register_catch(species,1) and session.fish_found[species],"Alga %d is still collected and discovered"%species)
	expect(session.medals.catches==1 and session.counters.h==1,"Algae do not inflate the original fishing tallies or lifetime record")
	session.ship.set_cargo([])
	expect(session.register_catch(12,1) and session.medals.catches==2,"The last live fish species counts")
	var before: int=session.medals.catches
	expect(not session.register_catch(0,session.ship.capacity()+1) and session.medals.catches==before,"A catch that cannot fit is not scored")
	session.medals.kills=4
	var saves=preload("res://native/simulation/save_store.gd").new()
	var restored=saves.restore(content.data,JSON.parse_string(JSON.stringify(saves.capture(session))))
	expect(restored!=null and restored.medals.kills==4 and restored.medals.catches==2,"Saving and reloading retains the current departure's counters")
	session.campaign.chapter=9
	for value in [4,5,9,10,14,15]:
		session.medals.kills=value;session.medals.catches=value
		session.medals.evaluate(session,100)
		var tier: int=0 if value<5 else 3 if value<10 else 2 if value<15 else 1
		expect(session.medals.pending[9]==tier and session.medals.pending[10]==tier,"Both tally medals use the original 5/10/15 thresholds: %d"%value)
	session.arrive()
	expect(session.medals.kills==15 and session.medals.catches==15 and session.medals.levels[9]==1 and session.medals.levels[10]==1,"Docking commits awards before counters are cleared")
	expect(session.depart() and session.medals.kills==0 and session.medals.catches==0,"The next station departure clears both tallies")
	root.size=Vector2i(1280,720)
	var game=load("res://native/gameplay.gd").new();game.content=content;game.demo_mode=true
	game.settings_path="user://trip-tallies-check.cfg";game.save_path="user://trip-tallies-check.json"
	var config:=ConfigFile.new();config.set_value("input","touch",2);config.set_value("audio","music",0.0);config.save(game.settings_path)
	root.add_child(game);game.set_process(false);game.view.set_process(false);game.abyss.set_process(false)
	for i in 3:await process_frame
	game.apply_demo();game.close_page();game.view.departure_progress=-1;game.view.transit_progress=-1
	game.session.ship.passive_radar=1;game._process(0)
	expect(not game.trip_tallies.visible,"Zero tallies leave the HUD clear")
	var region=game.world.region;var enemy=region.enemies[0]
	enemy.events.append("killed");region.step(0)
	expect(game.session.medals.kills==1,"A defeated enemy increments the counter used by the HUD")
	region.step(0)
	expect(game.session.medals.kills==1,"A death event is counted only once")
	game.session.medals.catches=5;game._process(0)
	expect(game.trip_tallies.visible and game.trip_tallies.kills==1 and game.trip_tallies.catches==5,"The HUD reads the actual medal counters")
	region.player.health.hull=maxi(1,region.player.health.hull-1);region.loadout.fire_kind(region.player.pose,40,false)
	region.step(40);game._process(0)
	expect(game.session.medals.kills==1 and game.session.medals.catches==5,"Damage and a missed shot do not break a departure's tallies")
	game.trip_tallies.update(game.session.medals,true,0)
	expect(not game.trip_tallies.visible,"The original radar gate is preserved")
	var original_medals: Array=game.session.medals.levels.duplicate()
	game.session.ship.upgraded=false;game._process(0)
	expect(game.trip_tallies.icon_theme=="b","Colonist hulls use the original blue tally icons and ink")
	game.session.ship.upgraded=true;game._process(0)
	expect(game.trip_tallies.icon_theme=="g","Rebel hulls change to green even when counts have not changed")
	game.session.medals.levels.fill(1);game._process(0)
	expect(game.trip_tallies.icon_theme=="go","All gold medals override the Rebel green theme")
	game.session.ship.upgraded=false;game._process(0)
	expect(game.trip_tallies.icon_theme=="go","All gold medals also override the Colonist blue theme")
	game.session.medals.levels=original_medals;game._process(0)
	expect(game.trip_tallies.icon_theme=="b","A normal medal set restores the hull's colour")
	game.session.medals.kills=15;game.session.medals.catches=0;game._process(0)
	var first_row_height: float=game.trip_tallies.size.y
	game.session.medals.kills=16;game._process(0)
	expect(game.trip_tallies.size.y>first_row_height,"The sixteenth tally wraps instead of hiding all the marks")
	game.session.medals.kills=36;game._process(0)
	expect(game.trip_tallies.size.y>first_row_height+16,"The original subsequent rows hold twenty marks")
	game.session.medals.kills=12;game.session.medals.catches=15
	for retro in [false,true]:
		game.retro=retro
		for dimensions in [Vector2i(1280,720),Vector2i(844,390),Vector2i(390,844),Vector2i(320,568)]:
			root.size=dimensions;game.touch.mode=2 if dimensions.x==1280 else 1
			for i in 3:await process_frame
			game.layout();game._process(0);game.view._process(0);game.abyss._process(0)
			var area: Rect2=game.trip_tallies.get_global_rect()
			expect(game.trip_tallies.visible and game.ui.get_global_rect().encloses(area),"Both tallies fit %s with Retro HUD %s"%[dimensions,retro])
			var objective_bottom: float=game.objective_label.global_position.y+minf(game.objective_label.size.y,game.objective_label.get_content_height())*game.objective_label.scale.y
			expect(area.position.y>=objective_bottom,"Tallies leave the objective unobscured")
			for band in game.retro_hud.bands():expect(not area.intersects(band),"Tallies leave the retro gauges unobscured")
			if game.touch.enabled():
				for control in ["menu","map","stick","guns","hook","throttle","boost"]:
					var button: Rect2=game.touch.control_rect(control)
					expect(not game.trip_tallies.get_rect().intersects(button),"Tallies leave %s free at %s"%[control,dimensions])
			if args.size()>1 and DisplayServer.get_name()!="headless":
				await process_frame;await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(args[1].path_join("tallies-%dx%d-retro-%s.png"%[dimensions.x,dimensions.y,retro]))
			game.session.medals.kills=56;game.session.medals.catches=56;game._process(0)
			expect(game.ui.get_global_rect().encloses(game.trip_tallies.get_global_rect()),"Wrapped tallies remain inside %s with Retro HUD %s"%[dimensions,retro])
			if game.touch.enabled():
				for control in ["menu","map","stick","guns","hook","throttle","boost"]:
					expect(not game.trip_tallies.get_rect().intersects(game.touch.control_rect(control)),"Wrapped tallies leave %s free at %s"%[control,dimensions])
			game.session.medals.kills=12;game.session.medals.catches=15;game._process(0)
	game.show_pause();game._process(0)
	expect(not game.trip_tallies.visible,"Pause hides the tallies")
	game.close_page();game._process(0)
	expect(game.trip_tallies.visible,"Returning to the dive restores the tallies")
	game.show_action_freeze();game._process(0)
	expect(not game.trip_tallies.visible,"Action freeze hides the tallies")
	game.end_action_freeze(true);game._process(0)
	game.view.transit_emerging=true;game.view.transit_progress=.5;game.transit_exit_elapsed=0;game._process(0)
	expect(not game.trip_tallies.visible,"Gate cinematics hide the tallies without resetting them")
	game.view.transit_progress=-1;game.session.medals.kills=100000;game.session.medals.catches=0;game._process(0)
	expect(game.trip_tallies.visible and game.trip_tallies.kills==100000 and game.trip_tallies.size.y<=game.trip_tallies.ROW_HEIGHT+32,"Large tallies retain their exact number and bounded continuation marks")
	game.queue_free();await process_frame
	print("TRIP_TALLIES ",checks," checks; ",failures," failures");quit(1 if failures else 0)
