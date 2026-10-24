extends SceneTree
## Synthetic originals only: cache isolation, cancellation, live replacement,
## mod precedence, recovery, and the actual settings/progress interface.
const Reconstruction = preload("res://native/textures/reconstructed_textures.gd")
const Dialog = preload("res://native/presentation/reconstruction_dialog.gd")
const Settings = preload("res://native/presentation/settings_menu.gd")
const Library = preload("res://scripts/model_library.gd")
const Mods = preload("res://native/presentation/mods.gd")
const Pack = preload("res://native/platform/content_pack.gd")
const Language = preload("res://native/presentation/engine_language.gd")
const DIRECTORY := "user://reconstruction-check"
const CONTENT := DIRECTORY+"/content"
const CONFIG := DIRECTORY+"/settings.cfg"
var failures := 0
var ticks := 0
var previous := -1.0
var output := ""

func _initialize() -> void:run.call_deferred()
func expect(ok: bool, message: String) -> void:
	if not ok:failures+=1;push_error(message)
func settle() -> void:
	for i in 4:await process_frame
func wait_for(condition: Callable, seconds := 10.0) -> bool:
	var end := Time.get_ticks_msec()+seconds*1000
	while Time.get_ticks_msec()<end:
		if condition.call():return true
		await process_frame
	return false
func screenshot(name: String) -> void:
	if output.is_empty() or DisplayServer.get_name()=="headless":return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(name+".png"))
func config() -> ConfigFile:
	var file := ConfigFile.new();file.load(CONFIG);return file
func fixture() -> void:
	DirAccess.make_dir_recursive_absolute(CONTENT.path_join("data/textures"))
	var image := Image.create(128,128,false,Image.FORMAT_RGBA8)
	for y in 128:
		for x in 128:image.set_pixel(x,y,Color(.1+.7*x/128.0,.1+.7*y/128.0,.4,1))
	for kind in ["deep","fx"]:image.save_png(CONTENT.path_join("data/textures/"+kind+".bmp.png"))
	var file := FileAccess.open(CONTENT.path_join("native-data.json"),FileAccess.WRITE);file.store_string('{"jar_sha256":"synthetic-first-jar"}');file.close()

func run() -> void:
	if not OS.get_cmdline_user_args().is_empty():output=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output)
	var cleanup := Pack.new();cleanup.remove_tree(DIRECTORY);fixture()
	Reconstruction.cache_base=DIRECTORY+"/generated";Mods.only_root=DIRECTORY+"/mods"
	Language.apply("en");process_frame.connect(func():ticks+=1)
	var info := Reconstruction.inspect(CONTENT)
	expect(not info.is_empty() and not Reconstruction.ready(info),"Compatible original atlases require generation")
	expect(not Reconstruction.offered(config(),info),"Existing imports see the feature offer once")
	expect(Reconstruction.save_choice(CONFIG,info,false)==OK and Reconstruction.offered(config(),info),"Not now persists the offer decision")
	var job := Reconstruction.new();var cancel_early := func(value,_stage):if value>.03:job.cancel()
	job.progress.connect(cancel_early)
	var originals := [FileAccess.get_sha256(CONTENT+"/data/textures/deep.bmp.png"),FileAccess.get_sha256(CONTENT+"/data/textures/fx.bmp.png")]
	expect(not await job.generate(info,self) and job.cancelled,"Cancellation returns without publishing a partial set")
	job.progress.disconnect(cancel_early);cancel_early=Callable()
	expect(not Reconstruction.ready(info) and not Reconstruction.active.has(CONTENT),"Cancelled files cannot become active")
	job=Reconstruction.new();ticks=0
	job.progress.connect(func(value,_stage):expect(value>=previous,"Progress never moves backwards");previous=value)
	var started := Time.get_ticks_msec()
	expect(await job.generate(info,self),"The native renderer creates a complete set")
	print("RECONSTRUCTION_TIME ",(Time.get_ticks_msec()-started)/1000.0," seconds; responsive frames ",ticks)
	expect(ticks>30 and previous==1,"Real progress and UI frames continue throughout generation")
	expect(Reconstruction.ready(info),"A verified completion manifest permits reuse")
	expect(not Reconstruction.enabled(config()),"Generation alone does not silently opt in")
	expect(Reconstruction.save_choice(CONFIG,info,true)==OK,"Completed reconstruction can be enabled")
	var library := Library.new();library.root=CONTENT
	var texture := library.texture("data/textures/deep.bmp");var normal := library.normal_map("data/textures/deep.bmp")
	expect(texture.get_size()==Vector2(1024,1024) and library.texture_size("data/textures/deep.bmp")==Vector2(128,128),"Generated colour preserves original UV coordinates")
	var glass := normal.get_image().get_pixel(55*8,104*8)
	expect(normal.get_size()==Vector2(1024,1024) and glass==Color8(128,128,255),"Generated normals keep the cockpit glass flat")
	var status := Mods.texture_status(CONTENT,Mods.ATLASES[0])
	expect(status.reconstructed and not status.replaced,"Mods identifies generated art without offering to remove its cache as a mod")
	Reconstruction.save_choice(CONFIG,info,false);library.reload_textures()
	expect(texture.get_size()==Vector2(128,128) and normal.get_size()==Vector2(2,2),"Disabling updates existing materials back to originals")
	Reconstruction.save_choice(CONFIG,info,true);library.reload_textures()
	var custom := Image.create(32,32,false,Image.FORMAT_RGBA8);custom.fill(Color.BLUE)
	DirAccess.make_dir_recursive_absolute(Mods.user_texture_path("deep").get_base_dir());custom.save_png(Mods.user_texture_path("deep"));library.reload_textures()
	expect(texture.get_size()==Vector2(32,32) and normal.get_size()==Vector2(2,2),"Custom colour overrides reconstruction without borrowing its normal")
	custom.fill(Color8(128,128,255));custom.save_png(Mods.user_texture_path("deep",true));library.reload_textures()
	expect(normal.get_size()==Vector2(32,32),"A custom normal still overrides independently")
	Mods.remove_texture("deep");Mods.remove_texture("deep",true);library.reload_textures()
	expect(texture.get_size()==Vector2(1024,1024),"Removing a custom pack restores enabled reconstruction")
	Reconstruction.active.clear();Reconstruction.restore(CONTENT,config())
	expect(Reconstruction.active.has(CONTENT),"An enabled complete cache restores on next launch")
	var second := FileAccess.open(CONTENT+"/native-data.json",FileAccess.WRITE);second.store_string('{"jar_sha256":"synthetic-second-jar"}');second.close()
	var other := Reconstruction.inspect(CONTENT)
	expect(other.directory!=info.directory and not Reconstruction.offered(config(),other),"Another JAR has an isolated cache and offer")
	second=FileAccess.open(CONTENT+"/native-data.json",FileAccess.WRITE);second.store_string('{"jar_sha256":"synthetic-first-jar"}');second.close()
	await ui_checks(info)
	expect(originals==[FileAccess.get_sha256(CONTENT+"/data/textures/deep.bmp.png"),FileAccess.get_sha256(CONTENT+"/data/textures/fx.bmp.png")],"Generation and UI choices never overwrite the imported originals")
	var altered := Image.load_from_file(CONTENT+"/data/textures/deep.bmp.png");altered.set_pixel(0,0,Color.RED);altered.save_png(CONTENT+"/data/textures/deep.bmp.png")
	expect(Reconstruction.inspect(CONTENT).directory!=info.directory,"Changed originals invalidate the cached reconstruction")
	fixture()
	var corrupt := FileAccess.open(str(info.directory).path_join("fx.png"),FileAccess.WRITE);corrupt.store_string("damaged");corrupt.close()
	expect(not Reconstruction.ready(info),"A damaged generated image triggers regeneration")
	Reconstruction.restore(CONTENT,config());expect(not Reconstruction.active.has(CONTENT),"A damaged set is never partially activated")
	cleanup.remove_tree(DIRECTORY);Reconstruction.cache_base="user://native/reconstructed";Reconstruction.active.clear();Mods.only_root=""
	print("RECONSTRUCTION_CHECK ",failures," failures");quit(1 if failures else 0)

func ui_checks(info: Dictionary) -> void:
	var ui := Control.new();root.add_child(ui);ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var settings := Settings.new();ui.add_child(settings);settings.configure(CONFIG,{"content_root":func():return CONTENT})
	settings.open("graphics");await settle()
	var row := settings.find_option(settings,"reconstructed_textures")
	expect(row!=null and row.get_node("Value").text=="On","Shared Graphics settings exposes the requested toggle")
	row.pressed.emit();await settle()
	expect(not Reconstruction.enabled(config()),"Settings turns reconstruction off immediately")
	row=settings.find_option(settings,"reconstructed_textures");row.pressed.emit()
	expect(await wait_for(func():return not Dialog.is_open()),"Re-enabling a valid cache finishes without rebuilding")
	expect(Reconstruction.enabled(config()),"The cached set is enabled from settings")
	Reconstruction.save_choice(CONFIG,info,false);Reconstruction.cache_base=DIRECTORY+"/uncached"
	settings.rebuild();await settle();row=settings.find_option(settings,"reconstructed_textures");row.pressed.emit()
	expect(await wait_for(func():return Dialog.is_open() and Dialog.current.get_ref().bar.value>0),"Enabling without a cache opens a working progress dialog")
	await screenshot("progress")
	if Dialog.is_open():Dialog.current.get_ref().choose("cancel")
	expect(await wait_for(func():return not Dialog.is_open()),"Progress cancellation returns to Settings")
	expect(not Reconstruction.enabled(config()),"Cancelling generation leaves the toggle off")
	Reconstruction.cache_base=DIRECTORY+"/generated"
	var dialog := Dialog.new();ui.add_child(dialog)
	var finished := [false];offer_and_finish(dialog,finished)
	await settle()
	expect(settings.focus_behavior_recursive==Control.FOCUS_BEHAVIOR_DISABLED,"Underlying settings cannot receive navigation through the modal")
	for size in [Vector2i(1280,720),Vector2i(800,600),Vector2i(540,960),Vector2i(960,540)]:
		root.content_scale_size=size;root.size=size;settings.touch=size.y>size.x;await settle()
		expect(root.get_visible_rect().encloses(dialog.panel.get_global_rect()),"Reconstruction prompt fits "+str(size))
		for button in dialog.actions.get_children():expect(dialog.panel.get_global_rect().encloses(button.get_global_rect()),"Prompt actions fit "+str(size))
		await screenshot("prompt-%dx%d"%[size.x,size.y])
	root.content_scale_size=Vector2i(1280,720);root.size=Vector2i(1280,720);await settle()
	var event := InputEventKey.new();event.keycode=KEY_ESCAPE;event.pressed=true;Input.parse_input_event(event)
	expect(await wait_for(func():return finished[0]),"Escape safely declines the offer")
	ui.remove_child(dialog);dialog.queue_free();await settle()
	expect(not Dialog.is_open() and settings.focus_behavior_recursive!=Control.FOCUS_BEHAVIOR_DISABLED,"Closing restores keyboard/controller focus scope")
	# Exercise missing/unsupported-source recovery through the same UI.
	dialog=Dialog.new();ui.add_child(dialog);finished=[false];failure_and_finish(dialog,finished)
	await settle();expect(dialog.status.text.contains("128"),"Unsupported reconstruction explains the problem without changing import acceptance")
	await screenshot("unsupported-source")
	dialog.choose("later");expect(await wait_for(func():return finished[0]),"Failure has an exit back to the game")
	ui.remove_child(dialog);dialog.queue_free();ui.queue_free();await settle()
	Reconstruction.save_choice(CONFIG,info,true)

func offer_and_finish(dialog, finished: Array) -> void:
	await dialog.run(CONTENT,CONFIG,true);finished[0]=true
func failure_and_finish(dialog, finished: Array) -> void:
	await dialog.run(DIRECTORY+"/missing",CONFIG,false);finished[0]=true
