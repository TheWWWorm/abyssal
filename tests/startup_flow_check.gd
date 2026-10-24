extends SceneTree
## Run in an English locale with a privately prepared non-English .abyss pack.
## No game data is shipped.
const Main = preload("res://native/main.gd")
const Pack = preload("res://native/platform/content_pack.gd")
var failures:=0
var menu: Node
const SETTINGS:="user://startup-check/settings.cfg"
func expect(ok: bool, message: String) -> void:
	if not ok:failures+=1;push_error(message)
func _initialize() -> void:run.call_deferred()
func wait_for(condition: Callable, frames: int=600) -> bool:
	for frame in frames:
		if condition.call():return true
		await process_frame
	return false
func open_title() -> void:
	menu=Main.new();menu.settings_path=SETTINGS;menu.save_path="user://startup-check/campaign.json"
	root.add_child(menu)
func close_title() -> void:
	menu.queue_free();await process_frame;await process_frame
func run() -> void:
	preload("decline_reconstruction.gd").attach(self)
	var pack:=Pack.new()
	pack.remove_tree("user://startup-check")
	var cache:=await pack.install(OS.get_cmdline_user_args()[0],"user://startup-check/content",self)
	expect(not cache.is_empty(),"Localized pack installs")
	if cache.is_empty():quit(1);return
	var config:=ConfigFile.new();config.set_value("content","cache",cache);config.save(SETTINGS)
	var sentinel:=FileAccess.open("user://startup-check/preserved-save.txt",FileAccess.WRITE)
	sentinel.store_string("keep campaign data");sentinel.close()
	open_title()
	expect(await wait_for(func():return menu.waiting_for_language),"First startup reaches the language choice")
	expect(not menu.title_dock.built and menu.title_dock.view.oven==null,"Language choice runs before 3D construction or shader warm-up")
	for frame in 6:await process_frame
	expect(menu.waiting_for_language and not menu.title_dock.built,"Frames continue while the language choice waits")
	menu.close_modal()
	expect(menu.modal.visible,"Back cannot dismiss a required choice and strand startup")
	var buttons: Array=menu.modal.find_children("*","Button",true,false)
	if buttons.is_empty():expect(false,"Language buttons exist");await close_title();quit(1);return
	buttons[0].pressed.emit()
	expect(await wait_for(func():return menu.ready_for_preview and not menu.content_starting),"Answering continues to the title")
	expect(menu.title_dock.built and menu.title_dock.view.oven==null,"The title uses its station without warming the entire catalogue")
	await close_title()
	open_title()
	expect(await wait_for(func():return menu.ready_for_preview and not menu.content_starting),"Saved import reopens without reimporting")
	expect(not menu.waiting_for_language,"The language answer survives reopening")
	await close_title()
	var broken:=FileAccess.open(cache.path_join("bindings.json"),FileAccess.WRITE);broken.store_string("{}");broken.close()
	open_title()
	expect(await wait_for(func():return not menu.content_starting),"A damaged restored cache returns control")
	expect(not menu.ready_for_preview and not menu.loading.visible and not menu.scrim.visible,"Recovery leaves the content picker accessible")
	expect(not menu.status.text.is_empty(),"Recovery explains why reimport is needed")
	config=ConfigFile.new();config.load(SETTINGS)
	expect(not config.has_section_key("content","cache"),"The damaged cache is not retried on every startup")
	expect(FileAccess.get_file_as_string("user://startup-check/preserved-save.txt")=="keep campaign data","Recovery keeps campaign data")
	await close_title();pack.remove_tree("user://startup-check")
	print("STARTUP_FLOW ",failures," failures");quit(1 if failures else 0)
