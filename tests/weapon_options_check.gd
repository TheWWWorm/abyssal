extends SceneTree
const Menu=preload("res://native/presentation/settings_menu.gd")
var checks:=0
var failures:=0
var output:=""
func expect(ok: bool, why: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(why)
func _initialize() -> void:call_deferred("run")
func settle() -> void:
	for i in 5:await process_frame
func capture(name: String) -> void:
	if output.is_empty() or DisplayServer.get_name()=="headless":return
	await settle();await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(name+".png"))
func run() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()>1:output=args[1]
	var content=preload("res://native/content.gd").new()
	if args.is_empty() or not content.load_cache(args[0]):quit(1);return
	root.size=Vector2i(1280,720)
	var path:="user://weapon-options/settings.cfg"
	DirAccess.make_dir_recursive_absolute(path.get_base_dir());DirAccess.remove_absolute(path)
	var game=preload("res://native/gameplay.gd").new()
	game.content=content;game.demo_mode=true;game.settings_path=path;game.save_path="user://weapon-options/unused.json"
	root.add_child(game);current_scene=game;await settle()
	expect(game.view.combat.enhanced_weapons and game.dive_audio.weapon_sounds_enabled,"A fresh profile enables both weapon enhancements")
	game.apply_demo();await settle()
	for visuals in [false,true]:
		for sounds in [false,true]:
			game.show_settings("graphics");await settle()
			game.settings_panel.put("graphics","weapon_effects",visuals)
			game.settings_panel.put("audio","weapon_sounds",sounds);await settle()
			expect(game.view.combat.enhanced_weapons==visuals and game.dive_audio.weapon_sounds_enabled==sounds,"Each combination applies independently in flight")
			for preset in [0,3]:
				game.settings_panel.choose_preset(preset);await settle()
				expect(game.view.combat.enhanced_weapons==visuals and game.dive_audio.weapon_sounds_enabled==sounds,"Changing lighting preserves both weapon choices")
			game.save_settings()
			game.view.combat.set_enhanced_weapons(not visuals);game.dive_audio.set_weapon_sounds_enabled(not sounds)
			game.read_settings()
			expect(game.view.combat.enhanced_weapons==visuals and game.dive_audio.weapon_sounds_enabled==sounds,"Both choices survive a settings reload")
	# Exercise the actual controls, including focus after the page rebuild.
	game.show_settings("graphics");await settle()
	var effects: Button=game.settings_panel.find_option(game.settings_panel,"weapon_effects")
	expect(effects!=null and not effects.disabled,"The visual control is usable independently of the lighting preset")
	effects.pressed.emit();await settle()
	expect(not game.view.combat.enhanced_weapons and game.dive_audio.weapon_sounds_enabled,"The graphics control changes visuals alone")
	await capture("weapon-options-graphics")
	game.show_settings("audio");await settle()
	var audio: Button=game.settings_panel.find_option(game.settings_panel,"weapon_sounds")
	expect(audio!=null and not audio.disabled,"The audio control is available in Audio settings")
	audio.pressed.emit();await settle()
	expect(not game.dive_audio.weapon_sounds_enabled and not game.view.combat.enhanced_weapons,"The audio control changes sound alone")
	await capture("weapon-options-audio")
	root.size=Vector2i(844,390);game.touch.mode=1;game.update_render_resolution()
	game.show_settings("audio");await settle()
	audio=game.settings_panel.find_option(game.settings_panel,"weapon_sounds")
	expect(audio!=null and audio.get_rect().size.y>=44,"The audio switch retains a touch-sized target")
	await capture("weapon-options-phone")
	var config:=ConfigFile.new();config.set_value("audio","weapon_sounds","false")
	expect(Menu.config_flag(config,"audio","weapon_sounds",true),"An invalid preference falls back safely")
	game.queue_free();await settle()
	print("WEAPON_OPTIONS ",checks," checks; ",failures," failures");quit(1 if failures else 0)
