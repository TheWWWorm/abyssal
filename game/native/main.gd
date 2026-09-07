extends Node3D
## Campaign title screen with an optional, isolated content inspection workbench.
const Content = preload("res://native/content.gd")
const Model = preload("res://native/presentation/model.gd")
const Health = preload("res://native/simulation/health.gd")
const Trade = preload("res://native/simulation/trade.gd")
var content := Content.new()
var camera := Camera3D.new()
var abyss := preload("res://native/presentation/abyss.gd").new()
var model: Node3D
var canvas := CanvasLayer.new()
var ui := Control.new()
var panel := PanelContainer.new()
var column := VBoxContainer.new()
var status: Label
var model_name: Label
var details: Label
var catalog := OptionButton.new()
var modal := preload("res://native/presentation/instrument_panel.gd").new()
var scrim := ColorRect.new()
var chooser := FileDialog.new()
var importer := Thread.new()
var portable := preload("res://native/platform/file_access.gd").new()
var pack_importer := preload("res://native/platform/content_pack.gd").new()
var import_busy := false
var bundled_import := false
var import_output := ""
var import_progress := ""
var project_root := ""
var python_executable := "python3"
var selected_jar := ""
var orbit := Vector2(0.5,0.13)
var distance := 30.0
var focus := Vector3.ZERO
var dragging := false
var elapsed_fraction := 0.0
var ready_for_preview := false
var light_enabled := true
var health := Health.new()
var trade := Trade.new()
var health_label: Label
var trade_label: Label
var credits := 1000
var face_layers: Array = [85,65,75,16,43,-1]
var face_art := preload("res://native/presentation/imported_art.gd").new()
var face_preview: TextureRect
var capture_path := ""
var capture_frames := 0
var title_menu := preload("res://native/presentation/title_menu.gd").new()
var inspector_open := false
var save_path := "user://native/campaign.json"
var settings_path := "user://native/settings.cfg"
var inspector_environment: Environment
var tools_status: Label
var title_dock := preload("res://native/presentation/title_dock.gd").new()

func label(text: String, font_size: int, color: Color=Color("d6e8ee")) -> Label:
	var node := Label.new()
	node.text=text
	node.add_theme_font_size_override("font_size",font_size)
	node.add_theme_color_override("font_color",color)
	return node

func style(color: Color, border: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color=color
	box.border_color=border
	box.set_border_width_all(1)
	box.set_corner_radius_all(0)
	box.content_margin_left=22
	box.content_margin_right=22
	box.content_margin_top=20
	box.content_margin_bottom=20
	return box

func button(text: String, action: Callable, parent: Node=column) -> Button:
	var node := Button.new()
	node.text=text
	node.alignment=HORIZONTAL_ALIGNMENT_LEFT
	node.custom_minimum_size.y=36
	node.add_theme_font_size_override("font_size",17)
	for state in ["normal","hover","focus","pressed"]:
		var box := style(Color("0b1b22") if state=="normal" else Color("172a2c"),Color("4f5345") if state=="normal" else Color("c39b62"))
		box.content_margin_top=8
		box.content_margin_bottom=8
		node.add_theme_stylebox_override(state,box)
	node.pressed.connect(action)
	parent.add_child(node)
	return node

func _ready() -> void:
	project_root=ProjectSettings.globalize_path("res://").get_base_dir().get_base_dir()
	get_viewport().disable_3d=false
	add_child(camera)
	camera.current=true
	camera.fov=52
	camera.near=0.1
	camera.far=3000
	abyss.camera=camera
	add_child(abyss)
	abyss.process_mode=Node.PROCESS_MODE_DISABLED
	abyss.hide()
	inspector_environment=abyss.environment.environment;abyss.environment.environment=null
	add_child(title_dock)
	add_child(canvas)
	canvas.add_child(ui)
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter=Control.MOUSE_FILTER_IGNORE
	ui.add_child(title_menu)
	title_menu.continued.connect(func(): launch_game(true))
	title_menu.started.connect(show_start)
	title_menu.settings_requested.connect(show_settings)
	title_menu.tools_requested.connect(choose_content)
	title_menu.quit_requested.connect(func(): get_tree().quit())
	ui.add_child(panel)
	panel.add_theme_stylebox_override("panel",style(Color("091720f5"),Color("254451")))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	column.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	column.add_theme_constant_override("separation",8)
	column.add_child(label("CONTENT",26,Color("8bd6ee")))
	column.add_child(label("LOCAL GAME RESOURCES",13,Color("73a6b3")))
	column.add_child(HSeparator.new())
	column.add_child(label("Model inspector",22))
	status=title_menu.status
	tools_status=label("",14,Color("89a6a6"));tools_status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;column.add_child(tools_status)
	catalog.custom_minimum_size.y=44
	catalog.add_theme_font_size_override("font_size",17)
	catalog.item_selected.connect(show_model)
	column.add_child(catalog)
	button("Back to main menu",hide_tools)
	button("Ship systems · native rule checks",show_systems)
	button("Headlights  ·  L",toggle_lights)
	button("Choose a JAR",func(): chooser.popup_centered_ratio(0.65))
	
	column.add_child(HSeparator.new())
	details=label("Orbit: drag right mouse / right stick\nZoom: mouse wheel\nFullscreen: F11",14,Color("81a2b0"))
	column.add_child(details)
	panel.hide()
	model_name=label("",24)
	ui.add_child(model_name)
	model_name.hide()
	ui.add_child(scrim)
	scrim.color=Color(0,0.025,0.045,0.78)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.hide()
	ui.add_child(modal)
	modal.add_theme_stylebox_override("panel",style(Color("07151df5"),Color("409bbd")))
	modal.hide()
	add_child(portable)
	portable.selected.connect(import_pack)
	portable.failed.connect(func(message):status.text=message)
	portable.progress.connect(func(message):status.text=message)
	portable.busy_changed.connect(func(active):
		title_menu.footer.text="Cancel import" if active else content_picker_label()
		refresh_title())
	add_child(chooser)
	chooser.file_mode=FileDialog.FILE_MODE_OPEN_FILE
	chooser.access=FileDialog.ACCESS_FILESYSTEM
	chooser.filters=PackedStringArray(["*.jar,*.abyss ; Game JAR or private content pack"])
	chooser.file_selected.connect(func(path):import_pack(path) if path.get_extension().to_lower()=="abyss" else import_jar(path))
	ui.resized.connect(layout_ui)
	layout_ui()
	var args := OS.get_cmdline_user_args()
	var config := ConfigFile.new();config.load(settings_path)
	var jar_path := str(config.get_value("content","jar",""))
	var cache_path := str(config.get_value("content","cache",""))
	for i in args.size():
		if i+1>=args.size(): continue
		match args[i]:
			"--jar": jar_path=args[i+1];cache_path=""
			"--python": python_executable=args[i+1]
			"--cache": cache_path=args[i+1]
			"--capture": capture_path=args[i+1]
	if "--lights-off" in args: toggle_lights()
	if not cache_path.is_empty():
		selected_jar=jar_path
		open_cache(cache_path)
	elif "--choose-jar" in args: status.text="Choose your DEEP JAR to begin."; chooser.popup_centered_ratio(0.65)
	elif source_import_available() and FileAccess.file_exists(jar_path): import_jar(jar_path)
	else: status.text="Choose your DEEP JAR to begin."
	title_menu.footer.text=content_picker_label()
	if not ready_for_preview:status.text="Choose your private .abyss content pack." if not source_import_available() and not OS.has_feature("web") else "Choose your JAR or private .abyss content pack."
	refresh_title()

func content_picker_label() -> String:
	return "Choose JAR / content pack…" if source_import_available() or OS.has_feature("web") else "Choose content pack…"

func desktop_importer_root() -> String:
	var folder:=OS.get_executable_path().get_base_dir()
	return folder.path_join("../Resources/importer").simplify_path() if OS.has_feature("macOS") else folder.path_join("importer")

func desktop_importer_command() -> String:
	var platform:="macos-arm64" if OS.has_feature("macOS") else "windows" if OS.has_feature("Windows") else "linux"
	return desktop_importer_root().path_join("bin/"+platform+"/"+("node.exe" if OS.has_feature("Windows") else "node"))

func bundled_import_available() -> bool:
	return not OS.has_feature("web") and not OS.has_feature("Android") and FileAccess.file_exists(desktop_importer_command()) and FileAccess.file_exists(desktop_importer_root().path_join("import.js"))

func source_import_available() -> bool:
	return bundled_import_available() or (not OS.has_feature("web") and not OS.has_feature("Android") and FileAccess.file_exists(project_root.path_join("tools/import_native.py")))

func choose_content() -> void:
	if import_busy:return
	if source_import_available():chooser.popup_centered_ratio(.8)
	else:portable.choose()

func import_pack(path: String) -> void:
	if import_busy:return
	status.text="Installing local content…"
	var cache:=pack_importer.install(path)
	if cache.is_empty():status.text=pack_importer.failure;return
	selected_jar="";open_cache(cache)

func layout_ui() -> void:
	panel.position=Vector2(24,24)
	panel.size=Vector2(minf(350,ui.size.x-48),maxf(200,ui.size.y-48))
	model_name.position=Vector2(410,ui.size.y-76)
	modal.size=Vector2(minf(640,ui.size.x-48),minf(560,ui.size.y-40))
	modal.position=(ui.size-modal.size)*0.5

func import_jar(path: String) -> void:
	if import_busy: return
	if not source_import_available():status.text="Prepare a .abyss content pack on desktop first.";return
	import_busy=true
	selected_jar=path
	status.text="Importing your game content…"
	title_menu.new_button.disabled=true
	title_menu.continue_button.disabled=true
	# The packaged converter runs offline in its own process. Developer source
	# launches retain the optional Python/JDK conversion path.
	bundled_import=bundled_import_available()
	var executable:=desktop_importer_command() if bundled_import else python_executable
	var arguments:=PackedStringArray([project_root.path_join("tools/import_native.py"),path])
	if bundled_import:
		var unique:="jar-import-"+str(OS.get_process_id())+"-"+str(Time.get_ticks_usec())
		import_output=ProjectSettings.globalize_path("user://"+unique+".abyss")
		import_progress=ProjectSettings.globalize_path("user://"+unique+".txt")
		arguments=PackedStringArray([desktop_importer_root().path_join("import.js"),path,import_output,import_progress])
	importer.start(func():
		var output: Array=[]
		var code:=OS.execute(executable,arguments,output,true)
		return {"code":code,"text":"\n".join(output)})

func open_cache(path: String) -> void:
	if not content.load_cache(path): status.text=content.failure; return
	status.text=""
	set_preference("content","cache",path)
	if not selected_jar.is_empty():set_preference("content","jar",selected_jar)
	catalog.clear()
	for record: Dictionary in content.registry: catalog.add_item(content.record_name(record))
	ready_for_preview=true
	title_menu.load_content(content.root)
	var initial := 0
	for i in content.registry.size():
		if int(content.registry[i].id)==0: initial=i; break
	catalog.select(initial)
	if inspector_open: show_model(initial)
	refresh_title()
	if "--gameplay-capture" in OS.get_cmdline_user_args(): launch_game.call_deferred()

func show_model(index: int) -> void:
	if not ready_for_preview: return
	if model!=null: remove_child(model); model.queue_free()
	model=Model.new()
	add_child(model)
	model.configure(content.root,content.registry[index])
	var bounds: AABB = model.bounds()
	focus=bounds.get_center()
	distance=maxf(6.0,bounds.size.length()*0.85)
	for lamp in abyss.lamps: lamp.spot_range=maxf(30,distance*3); lamp.position.x=signf(lamp.position.x)*distance*0.055
	model_name.text=content.record_name(content.registry[index])
	update_camera()

func update_camera() -> void:
	camera.position=focus+Vector3(sin(orbit.x)*cos(orbit.y),sin(orbit.y),cos(orbit.x)*cos(orbit.y))*distance
	camera.look_at(focus)
	# Shift the inspected model to the unobstructed portion of the viewport.
	camera.h_offset=-distance*0.14

func toggle_lights() -> void:
	light_enabled=not light_enabled
	abyss.set_headlights(light_enabled)

func _process(delta: float) -> void:
	if tools_status.text!=status.text: tools_status.text=status.text
	if import_busy and bundled_import and FileAccess.file_exists(import_progress):
		var progress:=FileAccess.get_file_as_string(import_progress)
		if not progress.is_empty():status.text=progress
	if import_busy and not importer.is_alive():
		var result: Dictionary = importer.wait_to_finish()
		import_busy=false
		if int(result.code)==0:
			if bundled_import:
				var cache:=pack_importer.install(import_output)
				if cache.is_empty():status.text=pack_importer.failure
				else:open_cache(cache)
			else:open_cache(str(result.text).strip_edges().split("\n")[-1])
		else:
			status.text="Import failed. "+str(result.text).strip_edges().split("\n")[-1] if bundled_import else "Import failed. Check your JAR and local converter dependencies."
			push_error(result.text)
		if bundled_import:
			for temporary in [import_output,import_output+".partial",import_progress]:
				if FileAccess.file_exists(temporary):DirAccess.remove_absolute(temporary)
		refresh_title()
	if ready_for_preview and inspector_open and model!=null:
		elapsed_fraction+=delta*1000.0
		var milliseconds := int(elapsed_fraction)
		elapsed_fraction-=milliseconds
		model.advance(milliseconds)
		if not modal.visible:
			for device in Input.get_connected_joypads():
				var stick := Vector2(Input.get_joy_axis(device,JOY_AXIS_RIGHT_X),Input.get_joy_axis(device,JOY_AXIS_RIGHT_Y))
				if stick.length()>0.18:
					orbit+=stick*delta*1.5
					orbit.y=clampf(orbit.y,-1.2,1.2)
					update_camera()
	if not capture_path.is_empty() and ready_for_preview:
		capture_frames+=1
		if capture_frames==50: save_capture.call_deferred()

func save_capture() -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(capture_path)
	print("NATIVE_CAPTURE ",capture_path)
	get_tree().quit()

func _input(event: InputEvent) -> void:
	if modal.visible and event is InputEventJoypadButton and event.pressed and event.button_index==JOY_BUTTON_B:
		close_modal()
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if modal.visible and event.is_action_pressed("ui_cancel"):
		close_modal()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE: hide_tools() if inspector_open else close_modal()
			KEY_L: toggle_lights()
			KEY_F11: DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN)
	if modal.visible or not inspector_open: return
	if event is InputEventMouseButton:
		if event.button_index==MOUSE_BUTTON_RIGHT: dragging=event.pressed
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			distance=clampf(distance*(0.9 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1.1),2,1500)
			update_camera()
	if event is InputEventMouseMotion and dragging:
		orbit+=event.relative*0.005
		orbit.y=clampf(orbit.y,-1.2,1.2)
		update_camera()
	if event is InputEventScreenDrag:
		orbit+=event.relative*0.005
		orbit.y=clampf(orbit.y,-1.2,1.2)
		update_camera()

func show_systems() -> void:
	if not ready_for_preview: return
	for child in modal.get_children(): modal.remove_child(child); child.queue_free()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation",16)
	modal.add_child(box)
	box.add_child(label("Native ship systems",28))
	var explanation := label("Verification workbench: isolated test inputs.\nThese are ported rules, not a playable campaign.",16,Color("93b4c1"))
	box.add_child(explanation)
	health.configure(75,30,20)
	health_label=label("",20)
	box.add_child(health_label)
	button("Apply 35 combined damage",func(): health.damage(35); refresh_systems(),box)
	button("Restore test hull",func(): health.configure(75,30,20); refresh_systems(),box)
	trade.price=100; trade.owned=0; trade.stock=3; credits=1000
	trade_label=label("",18)
	box.add_child(trade_label)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation",12)
	box.add_child(actions)
	button("Buy one",func(): credits+=trade.transact(true,credits,trade.owned,2); refresh_systems(),actions)
	button("Sell one",func(): credits+=trade.transact(false,credits,trade.owned,2); refresh_systems(),actions)
	var ok := button("OK  ·  Enter / Esc",close_modal,box)
	refresh_systems()
	scrim.show()
	modal.show()
	layout_ui()
	ok.grab_focus.call_deferred()

func refresh_systems() -> void:
	health_label.text="Hull %d    Shield %d    Armor %d" % [health.hull,health.shield,health.armor]
	trade_label.text="Credits %d  ·  Cargo %d / 2  ·  Stock %d\nTest item: 100 credits each" % [credits,trade.owned,trade.stock]

func close_modal() -> void:
	modal.hide()
	scrim.hide()
	if inspector_open: catalog.grab_focus()
	else: focus_title()

func _exit_tree() -> void:
	if importer.is_started(): importer.wait_to_finish()

func show_start() -> void:
	if not ready_for_preview: return
	face_art.root=content.root
	for child in modal.get_children(): modal.remove_child(child); child.queue_free()
	var box := VBoxContainer.new();box.add_theme_constant_override("separation",12); modal.add_child(box)
	box.add_child(label("CREATE YOUR DIVER",26,Color("8bd6ee")))
	box.add_child(label("Choose your name and portrait for this expedition.",15))
	var row := HBoxContainer.new();row.add_theme_constant_override("separation",24);box.add_child(row)
	face_preview=TextureRect.new();face_preview.custom_minimum_size=Vector2(160,160);face_preview.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;face_preview.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;face_preview.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;row.add_child(face_preview)
	var choices := VBoxContainer.new();choices.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(choices)
	var name_field := LineEdit.new(); name_field.placeholder_text="Your name"; name_field.text="Diver"; name_field.max_length=32;name_field.custom_minimum_size.y=40; choices.add_child(name_field)
	var sets := [["Backdrop",0,range(84,88)],["Face",1,range(58,72)],["Suit",2,range(74,84)],["Eyes",3,range(9,28)],["Hair",4,[-1]+range(30,55)],["Accessory",5,[-1]+range(0,9)]]
	for entry in sets:
		var line := HBoxContainer.new();choices.add_child(line)
		var caption := label(entry[0],14);caption.custom_minimum_size.x=85;line.add_child(caption)
		var picker := OptionButton.new();picker.size_flags_horizontal=Control.SIZE_EXPAND_FILL;picker.custom_minimum_size.y=32;line.add_child(picker)
		for i in entry[2].size(): picker.add_item("None" if entry[2][i]<0 else "%s %02d"%[entry[0],i+1])
		picker.select(maxi(0,entry[2].find(face_layers[entry[1]])))
		picker.item_selected.connect(func(index): face_layers[entry[1]]=entry[2][index]; refresh_face())
	refresh_face()
	box.add_child(label("Your previous checkpoint is kept as a backup.",12,Color("89a6a6")))
	button("BEGIN EXPEDITION >",func(): launch_game(false,name_field.text.strip_edges()),box)
	button("Back",close_modal,box)
	scrim.show(); modal.show();layout_ui();name_field.grab_focus.call_deferred()
func refresh_face() -> void:
	if is_instance_valid(face_preview): face_preview.texture=face_art.portrait(face_layers)

func focus_title() -> void:
	if not title_menu.continue_button.disabled: title_menu.continue_button.grab_focus.call_deferred()
	elif not title_menu.new_button.disabled: title_menu.new_button.grab_focus.call_deferred()
	else: title_menu.footer.grab_focus.call_deferred()

func refresh_title() -> void:
	title_menu.new_button.disabled=not ready_for_preview or import_busy or portable.busy
	title_menu.continue_button.disabled=true
	if ready_for_preview and not import_busy and not portable.busy:
		if FileAccess.file_exists(save_path):
			var store := preload("res://native/simulation/save_store.gd").new()
			var saved = store.read(save_path,content.data)
			if saved!=null:
				title_menu.continue_button.disabled=false
				status.text="%s · %s credits\nReturn to your last checkpoint" % [saved.name,saved.credits]
			else: status.text=store.failure
		else: status.text="A new expedition awaits."
	focus_title()

func show_tools() -> void:
	get_viewport().disable_3d=false
	title_dock.hide();title_dock.process_mode=Node.PROCESS_MODE_DISABLED;title_dock.environment.environment=null;abyss.environment.environment=inspector_environment;camera.current=true
	inspector_open=true;title_menu.hide();panel.show();model_name.show()
	abyss.show();abyss.process_mode=Node.PROCESS_MODE_INHERIT
	if ready_for_preview: show_model(maxi(0,catalog.selected))
	catalog.grab_focus()

func hide_tools() -> void:
	get_viewport().disable_3d=false
	abyss.environment.environment=null
	title_dock.show();title_dock.process_mode=Node.PROCESS_MODE_INHERIT;title_dock.environment.environment=title_dock.dock_environment;title_dock.camera.current=true
	inspector_open=false;dragging=false;panel.hide();model_name.hide();title_menu.show()
	if model!=null: remove_child(model);model.queue_free();model=null
	abyss.hide();abyss.process_mode=Node.PROCESS_MODE_DISABLED
	close_modal()

func set_preference(section: String, key: String, value: Variant) -> void:
	var config := ConfigFile.new();config.load(settings_path);config.set_value(section,key,value)
	DirAccess.make_dir_recursive_absolute(settings_path.get_base_dir())
	if config.save(settings_path)!=OK: status.text="Could not save settings. Check your user folder."

func show_settings() -> void:
	for child in modal.get_children(): modal.remove_child(child);child.queue_free()
	var box := VBoxContainer.new();box.add_theme_constant_override("separation",14);modal.add_child(box)
	box.add_child(label("EXPEDITION SETTINGS",26,Color("8bd6ee")))
	box.add_child(label("Changes are saved for your next dive.",14,Color("89a6a6")))
	var config := ConfigFile.new();config.load(settings_path)
	var modern := bool(config.get_value("graphics","modern",config.get_value("graphics","materials",true)))
	var mode := button("Lighting · "+("ENHANCED LIGHTING" if modern else "CLASSIC LIGHTING")+"  ⇄",func():
		if not config.has_section_key("graphics","modern") and not bool(config.get_value("graphics","materials",true)):set_preference("graphics","materials",true)
		set_preference("graphics","modern",not modern);show_settings(),box)
	mode.name="GraphicsMode"
	var row := HBoxContainer.new();box.add_child(row)
	var caption := label("Render resolution",16);caption.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(caption)
	var resolution := OptionButton.new();row.add_child(resolution)
	for name in ["1080p · performance","1440p · balanced","Native · sharpest"]: resolution.add_item(name)
	resolution.disabled=not modern
	resolution.select(clampi(int(config.get_value("view","resolution_v5",2)),0,2) if modern else 2)
	resolution.item_selected.connect(func(index): set_preference("view","resolution_v5",index))
	var taa := CheckButton.new();taa.text="Temporal antialiasing";taa.button_pressed=bool(config.get_value("view","temporal_aa",false));box.add_child(taa)
	taa.disabled=not modern
	taa.button_pressed=modern and taa.button_pressed
	taa.tooltip_text="Off preserves sharper detail in motion. On smooths jagged edges."
	taa.toggled.connect(func(value): set_preference("view","temporal_aa",value))
	for item in [["Music","audio","music",0.65,0.0,1.0,0.05],["Sound effects","audio","effects",0.75,0.0,1.0,0.05],["Mouse sensitivity","keys","mouse_sensitivity",0.8,0.2,2.0,0.1]]:
		var line := HBoxContainer.new();line.add_theme_constant_override("separation",16);box.add_child(line)
		var text := label(item[0],16);text.custom_minimum_size.x=180;line.add_child(text)
		var slider := HSlider.new();slider.size_flags_horizontal=Control.SIZE_EXPAND_FILL;slider.min_value=item[4];slider.max_value=item[5];slider.step=item[6];slider.value=float(config.get_value(item[1],item[2],item[3]));line.add_child(slider)
		var amount := label("%.2f" % slider.value,15);amount.custom_minimum_size.x=46;line.add_child(amount)
		slider.value_changed.connect(func(value): amount.text="%.2f" % value;set_preference(item[1],item[2],value))
	var invert := CheckButton.new();invert.text="Invert vertical mouse";invert.button_pressed=bool(config.get_value("keys","invert_mouse",false));box.add_child(invert)
	invert.toggled.connect(func(value): set_preference("keys","invert_mouse",value))
	button("Toggle fullscreen  ·  F11",func(): DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN),box)
	var back := button("Back",close_modal,box)
	scrim.show();modal.show();layout_ui();back.grab_focus.call_deferred()

func launch_game(resume: bool=false, player_name: String="Diver") -> void:
	if not ready_for_preview: return
	if resume:
		var store=preload("res://native/simulation/save_store.gd").new()
		if store.read(save_path,content.data)==null: status.text=store.failure; return
	get_viewport().disable_3d=false
	var gameplay=load("res://native/gameplay.gd").new()
	gameplay.save_path=save_path;gameplay.settings_path=settings_path
	gameplay.content=content; gameplay.continue_save=resume; gameplay.player_face=face_layers.duplicate(); gameplay.player_name="Diver" if player_name.is_empty() else player_name
	get_tree().root.add_child(gameplay); get_tree().current_scene=gameplay; queue_free()
