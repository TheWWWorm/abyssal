extends SceneTree
## Graphical integration with a privately imported compatible JAR cache.
## No content fixtures are shipped. Run with CACHE [CAPTURE_DIRECTORY].
const Main = preload("res://native/main.gd")
const Reconstruction = preload("res://native/textures/reconstructed_textures.gd")
const Dialog = preload("res://native/presentation/reconstruction_dialog.gd")
const Quality = preload("res://native/presentation/graphics_quality.gd")
const Pack = preload("res://native/platform/content_pack.gd")
const DIRECTORY := "user://reconstruction-startup-check"
const CONFIG := DIRECTORY+"/settings.cfg"
var failures := 0
var menu
var output := ""
var opening := false
var return_verifications := 0

func _initialize() -> void:run.call_deferred()
func expect(ok: bool, message: String) -> void:
	if not ok:failures+=1;push_error(message)
func wait_for(condition: Callable, seconds := 20.0) -> bool:
	var end := Time.get_ticks_msec()+seconds*1000
	while Time.get_ticks_msec()<end:
		if condition.call():return true
		await process_frame
	return false
func settle() -> void:
	for i in 5:await process_frame
func capture(name: String) -> void:
	if output.is_empty():return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(name+".png"))
func open_menu() -> void:
	menu=Main.new();menu.settings_path=CONFIG;menu.save_path=DIRECTORY+"/save.json";root.add_child(menu)
func import_cache(path: String) -> void:
	opening=true;await menu.open_cache(path);opening=false
func close_menu() -> void:
	menu.queue_free();await settle()
func run() -> void:
	if DisplayServer.get_name()=="headless":print("RECONSTRUCTION_STARTUP requires a graphical run");quit();return
	var args := OS.get_cmdline_user_args()
	if args.size()>1:output=args[1];DirAccess.make_dir_recursive_absolute(output)
	var cleanup := Pack.new();cleanup.remove_tree(DIRECTORY);DirAccess.make_dir_recursive_absolute(DIRECTORY)
	Reconstruction.cache_base=DIRECTORY+"/generated"
	preload("res://native/presentation/mods.gd").only_root=DIRECTORY+"/mods"
	var config := ConfigFile.new();config.set_value("interface","language","en");config.set_value("graphics","detection",Quality.DETECTION_VERSION);config.save(CONFIG)
	open_menu();await settle();import_cache(args[0])
	if not await wait_for(Dialog.is_open):expect(false,"A completed import offers reconstruction");await close_menu();quit(1);return
	expect(menu.ready_for_preview and not menu.content_starting,"The offer appears after the successful import")
	expect(not menu.probing(),"Graphics detection does not run behind the reconstruction offer")
	await capture("after-import")
	Dialog.current.get_ref().choose("later")
	expect(await wait_for(func():return not opening and not Dialog.is_open()),"Not now returns to a usable title")
	await close_menu();open_menu()
	expect(await wait_for(func():return menu.ready_for_preview and not menu.content_starting),"An existing import reopens")
	await settle();expect(not Dialog.is_open(),"A declined offer does not recur on every launch")
	# Remove only the feature's decision to model the first launch of an update
	# that introduced reconstruction, while retaining the installed import.
	await close_menu();config=ConfigFile.new();config.load(CONFIG);config.erase_section("texture_reconstruction");config.save(CONFIG)
	open_menu();expect(await wait_for(Dialog.is_open),"First launch after an update offers reconstruction for an existing import")
	Dialog.current.get_ref().choose("enable")
	expect(await wait_for(func():return Dialog.is_open() and Dialog.current.get_ref().bar.value>0,10),"Accepting starts real reconstruction with progress")
	await capture("generating")
	expect(await wait_for(func():return not Dialog.is_open(),150),"Reconstruction completes and the title resumes")
	var library=menu.title_dock.view.library
	expect(library.texture("data/textures/deep.bmp").get_width()==1024 and library.normal_map("data/textures/deep.bmp").get_width()==1024,"The running title uses reconstructed colour and normals")
	await capture("enabled")
	await close_menu();open_menu()
	expect(await wait_for(func():return menu.ready_for_preview and not menu.content_starting,40),"Enabled reconstruction reopens from the cache")
	await settle();expect(not Dialog.is_open(),"A completed cache needs no prompt or rebuild")
	expect(menu.title_dock.view.library.texture("data/textures/deep.bmp").get_width()==1024,"Cached reconstruction is active on launch")
	menu.show_settings("graphics");await settle()
	var row=menu.settings_panel.find_option(menu.settings_panel,"reconstructed_textures")
	row.grab_focus();await settle();await capture("settings")
	row.pressed.emit();await settle()
	expect(menu.title_dock.view.library.texture("data/textures/deep.bmp").get_width()==128,"The actual title settings restore originals immediately")
	row=menu.settings_panel.find_option(menu.settings_panel,"reconstructed_textures");row.pressed.emit()
	expect(await wait_for(func():return not Dialog.is_open()),"Title settings reuse the generated cache")
	menu.settings_panel.hide();menu.launch_game(false,"Reconstruction check")
	expect(await wait_for(func():return current_scene!=null and current_scene.get_script()==preload("res://native/gameplay.gd"),40),"The reconstructed title launches into gameplay")
	var game=current_scene
	if game!=null:
		game.set_process(false);game.show_settings("graphics");await settle()
		expect(game.view.library.texture("data/textures/deep.bmp").get_width()==1024 and game.view.library.normal_map("data/textures/deep.bmp").get_width()==1024,"Reconstruction carries into the gameplay materials")
		row=game.settings_panel.find_option(game.settings_panel,"reconstructed_textures");row.pressed.emit();await settle()
		expect(game.view.library.texture("data/textures/deep.bmp").get_width()==128,"In-game settings restore originals immediately")
		row=game.settings_panel.find_option(game.settings_panel,"reconstructed_textures");row.pressed.emit()
		expect(await wait_for(func():return not Dialog.is_open()),"In-game settings reuse the generated cache")
		expect(game.view.library.texture("data/textures/deep.bmp").get_width()==1024 and game.view.library.normal_map("data/textures/deep.bmp").get_width()==1024,"In-game settings reapply reconstructed colour and normals")
		await capture("gameplay-settings")
		# Model a graphics recommendation interrupted by entering the game.
		# Returning must not restart that benchmark or re-verify the live import.
		var live_content=game.content
		var active_directory: String=Reconstruction.active.get(live_content.root,"")
		config=ConfigFile.new();config.load(CONFIG);config.erase_section_key("graphics","detection");config.save(CONFIG)
		var saved_settings := FileAccess.get_file_as_string(CONFIG)
		game.return_to_menu()
		expect(await wait_for(func():return current_scene!=null and current_scene.get_script()==Main),"Return to main menu installs the actual title scene")
		menu=current_scene
		if menu!=null:
			menu.pack_importer.progress.connect(func(_done,_total):return_verifications+=1)
			expect(await wait_for(func():return menu.ready_for_preview and not menu.content_starting),"The returned title becomes usable")
			await settle()
			expect(menu.content==live_content and return_verifications==0,"Returning reuses the loaded content without rereading or verifying the import")
			expect(menu.settings_path==CONFIG and menu.save_path==DIRECTORY+"/save.json","Returning preserves the expedition's settings and save paths")
			expect(Reconstruction.active.get(live_content.root,"")==active_directory and not Dialog.is_open(),"Returning retains reconstruction without another offer or validation")
			expect(menu.title_dock.view.library.texture("data/textures/deep.bmp").get_width()==1024 and menu.title_dock.view.library.normal_map("data/textures/deep.bmp").get_width()==1024,"Reconstructed colour and normals remain enabled on return")
			expect(not menu.probing() and not menu.title_dock.view.backdrop_close,"An interrupted graphics benchmark does not restart on return")
			expect(FileAccess.get_file_as_string(CONFIG)==saved_settings,"Returning does not rewrite the saved reconstruction or graphics choices")
			await capture("returned-title")
			await close_menu()
	cleanup.remove_tree(DIRECTORY);Reconstruction.active.clear()
	print("RECONSTRUCTION_STARTUP ",failures," failures");quit(1 if failures else 0)
