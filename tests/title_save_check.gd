extends SceneTree
## The title's save transfer must work on a fresh device as well as an existing
## expedition. Run with a privately imported cache; no game data is shipped.
const Main = preload("res://native/main.gd")
const Save = preload("res://native/simulation/save_store.gd")
const Session = preload("res://native/simulation/session.gd")

class SaveFilesProbe extends "res://native/platform/save_file.gd":
	var chosen_count := 0
	var suggested_name := ""
	var enabled := true
	func available() -> bool:return enabled
	func choose_import() -> void:chosen_count+=1
	func export_text(filename: String, text: String) -> void:
		suggested_name=filename;pending_text=text

var failures := 0
var menu: Node
const DIRECTORY := "user://title-save-check"

func expect(ok: bool, message: String) -> void:
	if not ok:failures+=1;push_error(message)

func _initialize() -> void:run.call_deferred()

func control(node_name: String) -> Button:
	return menu.modal.find_child(node_name,true,false) as Button

func settled() -> void:
	await process_frame;await process_frame

func run() -> void:
	var cleanup := preload("res://native/platform/content_pack.gd").new()
	cleanup.remove_tree(DIRECTORY)
	# The three named slots are global. Preserve them when a contributor runs
	# this check outside a temporary user directory.
	var slots := {}
	for path in Save.SLOT_PATHS:
		for target in [path,path+".bak"]:
			if FileAccess.file_exists(target):
				slots[target]=FileAccess.get_file_as_bytes(target);DirAccess.remove_absolute(target)
	menu=Main.new();menu.save_path=DIRECTORY.path_join("campaign.json");menu.settings_path=DIRECTORY.path_join("settings.cfg")
	menu.save_files.open_dialog.free();menu.save_files.save_dialog.free();menu.save_files.free();menu.save_files=SaveFilesProbe.new()
	root.add_child(menu);await settled()
	expect(menu.title_menu.continue_button.disabled,"Load waits for compatible imported game content")
	await menu.open_cache(OS.get_cmdline_user_args()[0]);await settled()
	expect(not menu.title_menu.continue_button.disabled,"Load stays enabled on a fresh device with no saves")
	expect(root.gui_get_focus_owner()==menu.title_menu.new_button,"A fresh title still defaults to starting a new game")
	menu.title_menu.continue_button.pressed.emit();await settled()
	expect(menu.modal.visible and control("ImportSave")!=null and control("ExportSave")!=null,"Load exposes both save transfer actions without a checkpoint")
	expect(not control("ImportSave").disabled and control("ExportSave").disabled,"Import is available with no saves and export explains its empty state")
	expect(root.gui_get_focus_owner()==control("ImportSave"),"An empty Load screen focuses its usable import action")
	for index in 4:expect(control("SaveSlot%d"%index).disabled,"Empty save slots cannot be loaded")
	control("ImportSave").pressed.emit()
	expect(menu.save_files.chosen_count==1,"Import opens the shared platform picker")
	menu.save_files.received(["cancel",""]);await settled()
	expect(menu.modal.visible and root.gui_get_focus_owner()==control("ImportSave"),"Cancelling the browser picker leaves Load and its focus intact")
	menu.save_files.failed.emit("Picker error")
	expect(menu.load_note.visible and menu.load_note.text=="Picker error","Picker errors appear inside the active Load screen")
	menu.save_files.enabled=false;menu.show_load();await settled()
	expect(control("ImportSave").disabled and control("ExportSave").disabled,"A platform without save file access shows disabled transfer controls")
	menu.save_files.enabled=true;menu.show_load();await settled()
	var session := Session.new();session.new_game(menu.content.data,"Transferred Pilot",4455);session.prepare_station(0)
	var store := Save.new()
	var source := DIRECTORY.path_join("source.json")
	var imported := DIRECTORY.path_join("source.abyssave")
	expect(store.write(source,session),"A portable checkpoint is prepared")
	var record: Dictionary=menu.transfer.collect(menu.content.data,source)
	expect(menu.transfer.write(imported,record),"The portable checkpoint is exported")
	menu.save_files.chosen.emit(imported);await settled()
	expect(store.read(menu.save_path,menu.content.data).name=="Transferred Pilot","Import installs a readable expedition without first starting a new game")
	expect(not control("SaveSlot3").disabled and control("SaveSlot3").text.contains("Transferred Pilot"),"The imported autosave immediately appears in Load")
	expect(root.gui_get_focus_owner()==control("SaveSlot3"),"The imported autosave is ready to load with one confirmation")
	expect(menu.load_note.visible and menu.load_note.text.contains(Save.slot_title(3)),"Import confirms which save slot was replaced")
	expect(not control("ExportSave").disabled,"The imported save can be exported immediately")
	control("ExportSave").pressed.emit();await settled()
	expect(menu.load_exporting and not control("SaveSlot3").disabled,"Export offers the available save slots")
	menu.close_modal();await settled()
	expect(menu.modal.visible and not menu.load_exporting and root.gui_get_focus_owner()==control("ExportSave"),"Back from export returns to Load and its export action")
	session.name="Manual Pilot";expect(store.write(Save.slot_path(1),session),"A manual save is available independently of the autosave")
	control("ExportSave").pressed.emit();await settled();control("SaveSlot1").pressed.emit()
	var exported: Dictionary=JSON.parse_string(menu.save_files.pending_text)
	expect(exported.save.name=="Manual Pilot" and menu.save_files.suggested_name.begins_with("manual-pilot-"),"Exporting a manual slot delivers that expedition with a suitable filename")
	var export_path := DIRECTORY.path_join("manual.abyssave")
	menu.save_files.write_chosen(export_path);await settled()
	expect(menu.transfer.read_export(menu.content.data,export_path).save.name=="Manual Pilot","The native export writes a portable file that reads back")
	expect(not menu.load_exporting and menu.load_note.text.contains("manual.abyssave"),"A successful export returns to Load with visible delivery feedback")
	menu.save_files.chosen.emit(export_path);await settled()
	expect(store.read(menu.save_path,menu.content.data).name=="Manual Pilot" and store.read(menu.save_path+".bak",menu.content.data).name=="Transferred Pilot","Import replaces the autosave and preserves its prior checkpoint")
	var before := FileAccess.get_file_as_string(menu.save_path)
	var bad_path := DIRECTORY.path_join("invalid.abyssave")
	var bad := FileAccess.open(bad_path,FileAccess.WRITE);bad.store_string("{}");bad.close()
	menu.save_files.chosen.emit(bad_path);await settled()
	expect(FileAccess.get_file_as_string(menu.save_path)==before and menu.load_note.text==menu.transfer.failure,"An invalid import reports its failure without altering the save")
	var foreign: Dictionary=record.duplicate(true);foreign.content_id="0".repeat(64);foreign.save.jar_sha256="0".repeat(64);foreign.save.rules_id="0".repeat(64)
	expect(menu.transfer.write(bad_path,foreign),"A foreign-content export can be checked")
	menu.save_files.chosen.emit(bad_path);await settled()
	expect(FileAccess.get_file_as_string(menu.save_path)==before and menu.load_note.text.contains("JAR"),"An incompatible export explains the JAR mismatch in Load")
	for dimensions in [Vector2i(800,600),Vector2i(1280,720),Vector2i(600,960)]:
		var config := ConfigFile.new();config.load(menu.settings_path);config.set_value("input","touch",1 if dimensions.y>dimensions.x else 2);config.save(menu.settings_path)
		root.size=dimensions;menu.fit_window();menu.show_load();await settled()
		expect(root.get_visible_rect().encloses(menu.modal.get_global_rect()),"Load stays within %s"%dimensions)
		for node_name in ["ImportSave","ExportSave"]:
			expect(menu.modal.get_global_rect().encloses(control(node_name).get_global_rect()),"Transfer action fits %s: %s"%[dimensions,node_name])
	root.size=Vector2i(1280,720);menu.show_load();await settled()
	# Loading the imported slot goes through the real scene transition and save
	# reader, not a replacement callback.
	control("SaveSlot3").pressed.emit();await settled()
	var game := current_scene
	expect(game!=null and game.session.name=="Manual Pilot","The imported autosave launches the actual expedition from Load")
	if game!=null:game.queue_free();await settled()
	for frame in 6:await process_frame
	cleanup.remove_tree(DIRECTORY)
	for path in Save.SLOT_PATHS:
		for target in [path,path+".bak"]:
			DirAccess.remove_absolute(target)
			if slots.has(target):
				var file := FileAccess.open(target,FileAccess.WRITE);file.store_buffer(slots[target]);file.close()
	print("TITLE_SAVE ",failures," failures");quit(1 if failures else 0)
