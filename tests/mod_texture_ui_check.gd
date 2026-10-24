extends SceneTree
## Exercise the actual Mods screen and shared picker with synthetic PNGs only.
const Main = preload("res://native/main.gd")
const Mods = preload("res://native/presentation/mods.gd")
const Language = preload("res://native/presentation/engine_language.gd")
const DIRECTORY := "user://mod-texture-ui-check"

class ImagePickerProbe extends "res://native/platform/image_file.gd":
	var chosen_count := 0
	var enabled := true
	func available() -> bool:return enabled
	func choose() -> void:chosen_count+=1

var menu: Node
var failures := 0

func _initialize() -> void:run.call_deferred()
func expect(ok: bool, message: String) -> void:
	if not ok:failures+=1;push_error(message)
func control(name: String) -> Button:return menu.modal.find_child(name,true,false) as Button
func settled() -> void:
	for frame in 4:await process_frame
func click(name: String) -> void:
	var found := control(name)
	expect(found!=null and not found.disabled,"Action is available: "+name)
	if found!=null and not found.disabled:found.pressed.emit()
	await settled()

func run() -> void:
	preload("decline_reconstruction.gd").attach(self)
	var args := OS.get_cmdline_user_args()
	var cleanup := preload("res://native/platform/content_pack.gd").new();cleanup.remove_tree(DIRECTORY)
	DirAccess.make_dir_recursive_absolute(DIRECTORY)
	Mods.only_root=DIRECTORY.path_join("mods")
	menu=Main.new();menu.settings_path=DIRECTORY.path_join("settings.cfg");menu.save_path=DIRECTORY.path_join("save.json")
	menu.images.open_dialog.free();menu.images.free();menu.images=ImagePickerProbe.new()
	root.add_child(menu);await settled();await menu.open_cache(args[0]);await settled()
	menu.show_mod_textures();await settled()
	for atlas in ["deep","fx"]:
		expect(not control("NormalImport_"+atlas).disabled and control("NormalView_"+atlas).disabled and control("NormalRemove_"+atlas).disabled,"Empty normal slots expose import and disable view/removal: "+atlas)
	var source := Image.create(64,64,false,Image.FORMAT_RGBA8);source.fill(Color(.65,.5,.975,.75));source.set_pixel(0,0,Color.WHITE)
	var selected := DIRECTORY.path_join("normal.png");source.save_png(selected)
	var library=menu.title_dock.view.library
	var texture: Texture2D=library.normal_map("data/textures/deep.bmp")
	await click("NormalImport_deep")
	expect(menu.images.chosen_count==1 and menu.mods_normal and menu.mods_target=="deep" and not menu.photo_pick and not menu.images.any_image,"Normal import routes the shared PNG picker to the selected normal slot")
	menu.images.chosen.emit(selected);await settled()
	expect(FileAccess.file_exists(selected),"Selecting a player-owned file never deletes it")
	expect(Mods.texture_path("data/textures/deep.bmp").is_empty(),"Importing a normal does not require or create a colour replacement")
	expect(Mods.normal_texture_path("data/textures/deep.bmp")==Mods.user_texture_path("deep",true),"The normal goes into its separate atlas slot")
	expect(texture==library.normal_map("data/textures/deep.bmp") and texture.get_size()==Vector2(64,64),"A visible model's existing normal texture updates immediately")
	var loaded: Image=library.normal_image("data/textures/deep.bmp")
	expect(loaded.get_pixel(0,0)==Color.WHITE and loaded.get_pixel(1,1).is_equal_approx(source.get_pixel(1,1)),"Upload preserves normal vectors, alpha and white data without colour processing")
	expect(root.gui_get_focus_owner()==control("NormalImport_deep"),"Import returns focus to the normal slot")
	await click("NormalView_deep")
	expect(menu.modal.find_child("TexturePreview",true,false)!=null,"The normal has a full-size preview")
	await click("TexturePreviewBack")
	expect(root.gui_get_focus_owner()==control("NormalView_deep"),"Preview returns focus to its view action")
	# Re-importing a file already installed must not remove it during cleanup.
	await click("NormalImport_deep");menu.images.chosen.emit(Mods.user_texture_path("deep",true));await settled()
	expect(FileAccess.file_exists(Mods.user_texture_path("deep",true)),"An installed normal can be picked again safely")
	var before := FileAccess.get_file_as_bytes(Mods.user_texture_path("deep",true))
	menu.images.chosen.emit(DIRECTORY.path_join("missing.png"));await settled()
	expect(FileAccess.get_file_as_bytes(Mods.user_texture_path("deep",true))==before and not menu.mods_notice.is_empty(),"A failed import keeps the installed normal and explains the failure")
	menu.images.failed.emit("Picker unavailable");await settled()
	expect(menu.mods_notice=="Picker unavailable" and root.gui_get_focus_owner()==control("NormalImport_deep"),"Platform picker failures stay on the normal upload screen")
	await click("TextureImport_deep");menu.images.chosen.emit(selected);await settled()
	expect(not menu.mods_normal and not Mods.texture_path("data/textures/deep.bmp").is_empty(),"Colour upload still targets the colour slot")
	await click("TextureRemove_deep")
	expect(Mods.texture_path("data/textures/deep.bmp").is_empty() and texture.get_size()==Vector2(64,64),"Restoring original colour leaves the independently installed normal active")
	library.texture("data/textures/fx.bmp")
	await click("NormalImport_fx");menu.images.chosen.emit(selected);await settled()
	expect(not Mods.normal_texture_path("data/textures/fx.bmp").is_empty() and FileAccess.get_file_as_bytes(Mods.user_texture_path("deep",true))==before,"The effects normal has its own independent upload slot")
	# Browser and Android staging copies are released after consumption.
	var staged := DIRECTORY.path_join("staged.png");source.save_png(staged);menu.images.staged_path=staged
	menu.images.chosen.emit(staged);await settled()
	expect(not FileAccess.file_exists(staged) and FileAccess.file_exists(Mods.user_texture_path("fx",true)),"Only the picker-created temporary copy is removed")
	menu.images.enabled=false;menu.show_mod_textures();await settled()
	expect(control("NormalImport_deep").disabled and control("TextureImport_deep").disabled and not control("NormalView_deep").disabled,"Unavailable pickers disable imports while installed maps remain viewable")
	menu.images.enabled=true
	for dimensions in [Vector2i(1280,720),Vector2i(800,600),Vector2i(600,960)]:
		var config := ConfigFile.new();config.load(menu.settings_path);config.set_value("input","touch",1 if dimensions.y>dimensions.x else 2);config.save(menu.settings_path)
		root.size=dimensions;menu.fit_window();menu.mods_notice="";menu.show_mod_textures();await settled()
		expect(root.get_visible_rect().encloses(menu.modal.get_global_rect()),"Textures dialog fits "+str(dimensions))
		for name in ["NormalImport_deep","NormalImport_fx","TexturesBack"]:
			control(name).grab_focus();await settled()
			expect(menu.modal.get_global_rect().encloses(control(name).get_global_rect()),"Focus scrolls the action into the dialog: "+name+" at "+str(dimensions))
		if args.size()>1 and DisplayServer.get_name()!="headless":
			DirAccess.make_dir_recursive_absolute(args[1]);await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(args[1].path_join("mods-%dx%d.png"%[dimensions.x,dimensions.y]))
		await click("NormalView_deep")
		expect(root.get_visible_rect().encloses(menu.modal.get_global_rect()),"Normal preview fits "+str(dimensions))
		await click("TexturePreviewBack")
	root.size=Vector2i(1280,720);menu.fit_window()
	for code in ["de","fr","ru","pl","zh","ja","ko"]:
		Language.apply(code);menu.show_mod_textures();await settled()
		expect(root.get_visible_rect().encloses(menu.modal.get_global_rect()),"Translated dialog fits: "+code)
	Language.apply("en");menu.show_mod_textures();await settled()
	await click("NormalRemove_deep")
	expect(Mods.normal_texture_path("data/textures/deep.bmp").is_empty() and texture.get_size()==Vector2(2,2) and texture.get_image().get_pixel(0,0).a==0,"Removing the normal immediately restores inferred shading")
	expect(control("NormalRemove_deep").disabled and control("NormalView_deep").disabled,"Removed normal returns to the empty state")
	menu.queue_free();await settled();cleanup.remove_tree(DIRECTORY);Mods.only_root=""
	print("MOD_TEXTURE_UI ",failures," failures");quit(1 if failures else 0)
