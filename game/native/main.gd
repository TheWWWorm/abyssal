extends Node3D
## Campaign title screen with an optional, isolated content inspection workbench.
const Content = preload("res://native/content.gd")
const Model = preload("res://native/presentation/model.gd")
const Health = preload("res://native/simulation/health.gd")
const Trade = preload("res://native/simulation/trade.gd")
const StationTheme = preload("res://native/presentation/station_theme.gd")
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
## The portrait pickers: every part of every set in the JAR's portrait table,
## so a generated face can always be shown in them.
const FACE_PARTS := [["Backdrop",0,[84,85,86,87]],["Face",1,[29,58,59,60,61,62,63,64,65,66,67,68,69,70,71,94]],["Suit",2,[28,74,75,76,77,78,79,80,81,82,83]],["Eyes",3,[9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,88]],["Hair",4,[-1,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51,52,53,54,89,90,91,92,93]],["Accessory",5,[-1,0,1,2,3,4,5,6,7,8,72]]]
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
var launching := false
var loading := PanelContainer.new()
var loading_caption: Label
var loading_spinner: Label
var loading_tip: Label
## The menu entry a modal was opened from, for a pad to come back to.
var modal_origin: Control=null
## The Mods page: its picker, the atlas a chosen PNG is for, and its last word.
var images := preload("res://native/platform/image_file.gd").new()
var mods_target := ""
var mods_notice := ""
var load_path := ""
## The shared settings screen (settings_menu.gd), made on first use.
var settings_panel
## Browser build only: the corner fullscreen switch over the main menu.
var fullscreen_button
const FullscreenButton = preload("res://native/presentation/fullscreen_button.gd")
const SettingsMenu = preload("res://native/presentation/settings_menu.gd")
const TouchControls = preload("res://native/input/touch_controls.gd")
const Display = preload("res://native/presentation/display_settings.gd")

func label(text: String, font_size: int, color: Color=Color("d6e8ee")) -> Label:
	var node := Label.new()
	node.text=text
	node.add_theme_font_size_override("font_size",font_size)
	node.add_theme_color_override("font_color",color)
	return node

func style(color: Color, border: Color) -> StyleBoxFlat:
	# The station menus' glass; the colours asked for are kept only as a hint
	# of opacity, so every dialog reads as one interface.
	var box := StationTheme.panel(false);box.bg_color.a=maxf(color.a,.9)
	box.content_margin_left=24;box.content_margin_right=24;box.content_margin_top=20;box.content_margin_bottom=20
	return box

func button(text: String, action: Callable, parent: Node=column) -> Button:
	var node := Button.new()
	node.text=text
	node.alignment=HORIZONTAL_ALIGNMENT_LEFT
	node.custom_minimum_size.y=40
	node.add_theme_font_size_override("font_size",17)
	var palette := StationTheme.palette(false)
	for state in ["normal","hover","focus","pressed","disabled"]:
		node.add_theme_stylebox_override(state,StationTheme.button_state(false,state))
	node.add_theme_color_override("font_color",palette.text);node.add_theme_color_override("font_focus_color",Color.WHITE);node.add_theme_color_override("font_hover_color",Color.WHITE)
	node.add_theme_color_override("font_disabled_color",palette.faint)
	node.pressed.connect(action)
	parent.add_child(node)
	return node

func _ready() -> void:
	get_tree().quit_on_go_back=false
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
	title_menu.continued.connect(show_load)
	title_menu.started.connect(show_start)
	title_menu.settings_requested.connect(show_settings)
	title_menu.tools_requested.connect(choose_content)
	title_menu.quit_requested.connect(func(): get_tree().quit())
	title_menu.help_requested.connect(show_help)
	title_menu.mods_requested.connect(show_mods)
	fullscreen_button=FullscreenButton.new(func(): FullscreenButton.toggle(func(text): status.text=text))
	var start_config := ConfigFile.new();start_config.load(settings_path)
	Display.apply_orientation(clampi(int(start_config.get_value("view","orientation",0)),0,2))
	add_child(images)
	images.chosen.connect(install_texture)
	images.failed.connect(func(message):mods_notice=message;show_mod_textures())
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
	button("Choose game content",choose_content)
	
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
	# The scrim blocks pointer clicks; also keep keyboard/controller focus inside
	# the dialog instead of navigating to the title buttons behind it.
	modal.visibility_changed.connect(func():
		var behavior := Control.FOCUS_BEHAVIOR_DISABLED if modal.visible else Control.FOCUS_BEHAVIOR_INHERITED
		title_menu.focus_behavior_recursive=behavior;panel.focus_behavior_recursive=behavior)
	modal.add_theme_stylebox_override("panel",style(Color("07151df5"),Color("409bbd")))
	modal.minimum_size_changed.connect(func():layout_ui.call_deferred())
	modal.hide()
	ui.add_child(loading);loading.add_theme_stylebox_override("panel",style(Color("07151df5"),Color("409bbd")));loading.hide()
	ui.add_child(fullscreen_button)
	var loading_row := HBoxContainer.new();loading_row.add_theme_constant_override("separation",18);loading.add_child(loading_row)
	loading_spinner=label("◐",30,Color("8bd6ee"));loading_row.add_child(loading_spinner)
	loading_caption=label("",19);loading_caption.vertical_alignment=VERTICAL_ALIGNMENT_CENTER;loading_row.add_child(loading_caption)
	# The phone game's loading screen carries a tip from its Tips & Tricks
	# under the bubbles; this panel carries one under the caption.
	var loading_column := VBoxContainer.new();loading_column.add_theme_constant_override("separation",12)
	loading.remove_child(loading_row);loading.add_child(loading_column);loading_column.add_child(loading_row)
	loading_tip=label("",14,Color("a2c3d3"));loading_tip.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;loading_tip.custom_minimum_size.x=420;loading_column.add_child(loading_tip)
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
	# A window that ignores a dropped JAR looks broken. Only the desktop builds
	# have a filesystem to drop from; the browser and Android reach their files
	# through their own pickers.
	if not OS.has_feature("web") and not OS.has_feature("android"): get_window().files_dropped.connect(dropped_files)
	ui.resized.connect(layout_ui)
	get_window().size_changed.connect(fit_window);fit_window()
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
	if not ready_for_preview:status.text="Choose your private .abyss content pack." if not source_import_available() and not OS.has_feature("web") and portable.android==null else "Choose your JAR or private .abyss content pack."
	refresh_title()

func dropped_files(paths: PackedStringArray) -> void:
	"""A dropped file is the same request the picker makes, so it takes the same
	two routes. Anything else is said out loud rather than quietly ignored."""
	if paths.is_empty() or import_busy or portable.busy: return
	var path: String = paths[0]
	match path.get_extension().to_lower():
		"abyss": import_pack(path)
		"jar": import_jar(path)
		_: status.text="Drop a DEEP .jar, or an .abyss content pack prepared on a computer."

func content_picker_label() -> String:
	return "Choose JAR / content pack…" if source_import_available() or OS.has_feature("web") or portable.android!=null else "Choose content pack…"

func desktop_importer_root() -> String:
	var folder:=OS.get_executable_path().get_base_dir()
	return folder.path_join("../Resources/importer").simplify_path() if OS.has_feature("macos") else folder.path_join("importer")

func desktop_importer_command() -> String:
	var platform:="macos-arm64" if OS.has_feature("macos") else "windows" if OS.has_feature("windows") else "linux"
	if platform=="linux" and OS.has_feature("arm64"):platform="linux-arm64"
	return desktop_importer_root().path_join("bin/"+platform+"/"+("node.exe" if OS.has_feature("windows") else "node"))

func bundled_import_available() -> bool:
	return not OS.has_feature("web") and not OS.has_feature("android") and FileAccess.file_exists(desktop_importer_command()) and FileAccess.file_exists(desktop_importer_root().path_join("import.js"))

func source_import_available() -> bool:
	return bundled_import_available() or (not OS.has_feature("web") and not OS.has_feature("android") and FileAccess.file_exists(project_root.path_join("tools/import_native.py")))

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

func fit_window() -> void:
	"""The title uses the dive's canvas rule, so an upright phone gets an upright
	title rather than a letterboxed landscape one."""
	var pixels := get_window().size
	if pixels.x>0 and pixels.y>0:
		var config := ConfigFile.new();config.load(settings_path)
		# The dive's rule (touch_controls.enabled), read before any dive exists.
		var mode:=clampi(int(config.get_value("input","touch",0)),0,2)
		var last:=TouchControls.last_input
		var touch: bool=mode==1 or (mode==0 and (last=="touch" or (last.is_empty() and DisplayServer.is_touchscreen_available())))
		Display.apply(get_window(),Display.valid(str(config.get_value("view","aspect_ratio","auto"))),Display.responsive_size(pixels,touch))
	apply_side_margins()
func apply_side_margins() -> void:
	# The title menus keep clear of a phone's notch as the flight interface does.
	var margin: Dictionary=preload("res://native/platform/safe_margins.gd").margins(get_viewport().get_visible_rect().size,get_window().size,DisplayServer.is_touchscreen_available())
	ui.offset_left=margin.side;ui.offset_right=-margin.side;ui.offset_top=margin.top;ui.offset_bottom=-margin.bottom
func layout_ui() -> void:
	panel.position=Vector2(24,24)
	panel.size=Vector2(minf(350,ui.size.x-48),maxf(200,ui.size.y-48))
	model_name.position=Vector2(410,ui.size.y-76)
	# The character screen needs more room than the other dialogs.
	var wide: bool=modal.get_node_or_null("CharacterSheet")!=null
	modal.size=Vector2(minf(900 if wide else 640,ui.size.x-48),minf(700 if wide else 560,ui.size.y-40))
	modal.position=(ui.size-modal.size)*0.5
	loading.size=loading.get_combined_minimum_size();loading.position=(ui.size-loading.size)*0.5

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
	title_dock.load_content(content,save_path,settings_path)
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
	var settings_open: bool=is_instance_valid(settings_panel) and settings_panel.visible
	fullscreen_button.place(title_menu.visible and not inspector_open and not modal.visible and not loading.visible and not settings_open)
	if loading.visible:loading_spinner.text=["◐","◓","◑","◒"][int(Time.get_ticks_msec()/160)%4]
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
	preload("res://native/input/touch_controls.gd").record_input(event)
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
	elif is_instance_valid(modal_origin) and modal_origin.is_visible_in_tree() and not modal_origin.disabled: modal_origin.grab_focus.call_deferred();modal_origin=null
	else: focus_title()

func _exit_tree() -> void:
	if importer.is_started(): importer.wait_to_finish()

func show_start(player_name: String="Pilot") -> void:
	if not ready_for_preview: return
	face_art.root=content.root
	for child in modal.get_children(): modal.remove_child(child); child.queue_free()
	var shell := VBoxContainer.new();shell.name="CharacterSheet";shell.add_theme_constant_override("separation",12); modal.add_child(shell)
	shell.add_child(label("CREATE YOUR CHARACTER",26,Color("8bd6ee")))
	shell.add_child(label("Choose your name and portrait.",15))
	# Scrolls only where a phone's height cannot hold it all.
	var scroll:=ScrollContainer.new();scroll.follow_focus=true;scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;shell.add_child(scroll)
	# Inset so a focused field's outline is not cut by the scroller's edge.
	var inset:=MarginContainer.new();inset.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(inset)
	for edge in ["margin_top","margin_bottom","margin_left","margin_right"]: inset.add_theme_constant_override(edge,4)
	var box := VBoxContainer.new();box.size_flags_horizontal=Control.SIZE_EXPAND_FILL;box.add_theme_constant_override("separation",12);inset.add_child(box)
	var row := HBoxContainer.new();row.add_theme_constant_override("separation",24);box.add_child(row)
	var portrait := VBoxContainer.new();portrait.add_theme_constant_override("separation",8);row.add_child(portrait)
	face_preview=TextureRect.new();face_preview.custom_minimum_size=Vector2(160,160);face_preview.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;face_preview.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;face_preview.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;portrait.add_child(face_preview)
	var choices := VBoxContainer.new();choices.size_flags_horizontal=Control.SIZE_EXPAND_FILL;choices.add_theme_constant_override("separation",8);row.add_child(choices)
	var name_field := LineEdit.new(); name_field.placeholder_text="Your name"; name_field.text=player_name; name_field.max_length=32;name_field.custom_minimum_size.y=40; choices.add_child(name_field)
	var random := button(content.text(302) if not content.text(302).is_empty() else "Generate face",func(): random_face();show_start(name_field.text),portrait)
	random.alignment=HORIZONTAL_ALIGNMENT_CENTER
	var grid := GridContainer.new();grid.columns=4;grid.add_theme_constant_override("h_separation",10);grid.add_theme_constant_override("v_separation",8);choices.add_child(grid)
	for entry in FACE_PARTS:
		var caption := label(entry[0],14);caption.custom_minimum_size.x=80;grid.add_child(caption)
		var picker := OptionButton.new();picker.size_flags_horizontal=Control.SIZE_EXPAND_FILL;picker.custom_minimum_size=Vector2(150,32);grid.add_child(picker)
		for i in entry[2].size(): picker.add_item("None" if entry[2][i]<0 else "%s %02d"%[entry[0],i+1])
		picker.select(maxi(0,entry[2].find(face_layers[entry[1]])))
		picker.item_selected.connect(func(index): face_layers[entry[1]]=entry[2][index]; refresh_face())
	refresh_face()
	box.add_child(label("WORLD SPACING",18,Color("8bd6ee")))
	var config:=ConfigFile.new();config.load(settings_path)
	var spacing:=preload("res://native/simulation/world_spacing.gd").new();spacing.read_config(config)
	var controls:=preload("res://native/presentation/world_settings.gd").new();controls.configure(spacing);box.add_child(controls)
	controls.changed.connect(func():
		var saved:=ConfigFile.new();saved.load(settings_path);spacing.write_config(saved)
		DirAccess.make_dir_recursive_absolute(settings_path.get_base_dir())
		if saved.save(settings_path)!=OK:status.text="Could not save settings. Check your user folder.")
	box.add_child(label("Change later in Options → Gameplay.",14,Color("89a6a6")))
	shell.add_child(label("Your previous checkpoint is kept as a backup.",12,Color("89a6a6")))
	button("START GAME",func(): launch_game(false,name_field.text.strip_edges()),shell)
	button("Back",close_modal,shell)
	scrim.show(); modal.show();layout_ui();name_field.grab_focus.call_deferred()
func random_face() -> void:
	"""The original's "Generate face" (ch: 302). Every part comes from one
	matched set of the JAR's portrait table, so a random face still hangs
	together: the phone's own two sets, the second at its own odds, and the
	third set its crew portraits draw on, offered here as well. The accessory
	comes at the table's own odds; the chosen backdrop is kept."""
	var parts: Dictionary=content.data.constants.ab
	var table: Array=parts["a:[[[B"]
	var category: int=2 if randi()%3==0 else (1 if randi()%100<int(parts["c:byte"]) else 0)
	var pick:=func(layer: int) -> int:
		var options: Array=table[layer][category]
		return int(options[randi()%options.size()])
	# The table's second layer is the suit and its third the face; this
	# screen keeps them the other way round.
	face_layers=[face_layers[0],pick.call(2),pick.call(1),pick.call(3),pick.call(4),pick.call(5) if randi()%100<int(parts["d:byte"]) else -1]
func refresh_face() -> void:
	if is_instance_valid(face_preview): face_preview.texture=face_art.portrait(face_layers)

func show_loading(text: String, chapter: int=1) -> void:
	modal.hide();scrim.show();loading_caption.text=text;loading_tip.text=loading_hint(chapter);loading_tip.visible=not loading_tip.text.is_empty();loading.show();layout_ui()
	title_menu.focus_behavior_recursive=Control.FOCUS_BEHAVIOR_DISABLED

func loading_hint(chapter: int) -> String:
	"""One of the game's seventeen tips (cr.a): before the twelfth chapter
	the first four, about production and trade, are held back."""
	if not ready_for_preview or content.data.is_empty():return ""
	var config:=ConfigFile.new();config.load(settings_path)
	if not bool(config.get_value("interface","hints",true)):return ""
	var tips: Array=range(146,163)
	var first: int=4 if chapter<12 else 0
	var line: String=content.text(int(tips[first+randi()%(tips.size()-first)]))
	return "" if line.is_empty() else content.text(305)+"\n"+line

func show_load() -> void:
	"""The four saves of the phone game's Load screen: three of the player's
	own and the autosave, each with who and where it is."""
	if not ready_for_preview:return
	for child in modal.get_children():modal.remove_child(child);child.queue_free()
	var box := VBoxContainer.new();box.add_theme_constant_override("separation",10);modal.add_child(box)
	box.add_child(label(content.text(1).to_upper(),26,Color("8bd6ee")))
	var store := preload("res://native/simulation/save_store.gd")
	var first: Button=null
	for index in 4:
		var path: String=save_path if index==3 else store.slot_path(index)
		var entry: Dictionary=store.summary(path,content.data) if FileAccess.file_exists(path) else {}
		var choice := button("%d.  %s  ·  %s"%[index+1,store.slot_title(index),store.describe(entry)],func():launch_game(true,"Pilot",path),box)
		choice.alignment=HORIZONTAL_ALIGNMENT_LEFT;choice.disabled=entry.is_empty()
		if first==null and not entry.is_empty():first=choice
	var back := button("Back",close_modal,box)
	scrim.show();modal.show();layout_ui()
	(first if first!=null else back).grab_focus.call_deferred()

func show_help(topic: int=-1) -> void:
	"""The phone game's Help from the title: Instructions by topic, the
	controls, and the credits. Without content there are only the keys."""
	if not modal.visible:modal_origin=get_viewport().gui_get_focus_owner()
	for child in modal.get_children():modal.remove_child(child);child.queue_free()
	var box := VBoxContainer.new();box.add_theme_constant_override("separation",10);modal.add_child(box)
	var guide=preload("res://native/presentation/instructions.gd")
	var topics: Array=guide.topics(content) if ready_for_preview else []
	if topic>=0 and topic<topics.size():
		box.add_child(label(topics[topic].title.to_upper(),24,Color("8bd6ee")))
		var scroller := ScrollContainer.new();scroller.custom_minimum_size=Vector2(560,320);scroller.size_flags_vertical=Control.SIZE_EXPAND_FILL;box.add_child(scroller)
		var body := VBoxContainer.new();body.size_flags_horizontal=Control.SIZE_EXPAND_FILL;body.add_theme_constant_override("separation",12);scroller.add_child(body)
		var text := label(topics[topic].text,15);text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;text.custom_minimum_size.x=540;body.add_child(text)
		if topic==0:
			var keys := label(guide.key_note(),13,Color("a2c3d3"));keys.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;keys.custom_minimum_size.x=540;body.add_child(keys)
		var back := button("Back",func():show_help(),box)
		scrim.show();modal.show();layout_ui();back.grab_focus.call_deferred();return
	box.add_child(label(("HELP" if not ready_for_preview else content.text(4).to_upper()),24,Color("8bd6ee")))
	var first: Button=null
	if not topics.is_empty():box.add_child(label(content.text(18),16,Color("aedbec")))
	var grid := GridContainer.new();grid.columns=2;grid.add_theme_constant_override("h_separation",10);grid.add_theme_constant_override("v_separation",6);box.add_child(grid)
	for index in topics.size():
		var row := button(topics[index].title,func():show_help(index),grid);row.custom_minimum_size.x=270
		if first==null:first=row
	var keys := label(title_menu.help.text,13,Color("b2d5e5"));keys.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;keys.custom_minimum_size.x=550;box.add_child(keys)
	if ready_for_preview:
		var credits := button(content.text(20),func():
			for child in modal.get_children():modal.remove_child(child);child.queue_free()
			var roll := VBoxContainer.new();roll.add_theme_constant_override("separation",10);modal.add_child(roll)
			var scroller := ScrollContainer.new();scroller.custom_minimum_size=Vector2(560,340);roll.add_child(scroller)
			var text := label(content.text(26)+"\n\n"+content.text(28)+"\n\n"+content.text(25),15);text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;text.custom_minimum_size.x=540;scroller.add_child(text)
			var back := button("Back",func():show_help(),roll);layout_ui();back.grab_focus.call_deferred(),box)
		credits.alignment=HORIZONTAL_ALIGNMENT_LEFT
	var back := button("Back",close_modal,box)
	if ready_for_preview:
		# Credits and Back share a row to keep the page inside a 720p window.
		var last := HBoxContainer.new();last.add_theme_constant_override("separation",10);box.add_child(last)
		for entry in [box.get_child(box.get_child_count()-3),back]:
			box.remove_child(entry);last.add_child(entry);entry.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	scrim.show();modal.show();layout_ui()
	(first if first!=null else back).grab_focus.call_deferred()

func show_mods() -> void:
	"""Mods: the sections of player-supplied art. Textures for now."""
	if not modal.visible:modal_origin=get_viewport().gui_get_focus_owner()
	for child in modal.get_children():modal.remove_child(child);child.queue_free()
	var box := VBoxContainer.new();box.add_theme_constant_override("separation",10);modal.add_child(box)
	box.add_child(label("MODS",24,Color("8bd6ee")))
	var intro := label("Replace the game's textures with your own PNGs. Remove a replacement to restore the original.",13,Color("a2c3d3"))
	intro.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;intro.custom_minimum_size.x=560;box.add_child(intro)
	var textures := button("Textures",show_mod_textures,box)
	box.add_child(label("The two texture atlases used by all models.",12,Color("89a6a6")))
	var back := button("Back",close_modal,box)
	scrim.show();modal.show();layout_ui();textures.grab_focus.call_deferred()

func checkered(image: Image, side: float) -> Control:
	"""An image over a checkerboard, so what is transparent shows as such."""
	var frame := Control.new();frame.custom_minimum_size=Vector2(side,side)
	var board := TextureRect.new();board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);board.stretch_mode=TextureRect.STRETCH_TILE
	var cells := Image.create(16,16,false,Image.FORMAT_RGBA8)
	for y in 16:
		for x in 16:cells.set_pixel(x,y,Color("3a3f45") if ((x>>3)+(y>>3))%2==0 else Color("6a7078"))
	board.texture=ImageTexture.create_from_image(cells);board.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;frame.add_child(board)
	var picture := TextureRect.new();picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;picture.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	if image!=null:picture.texture=ImageTexture.create_from_image(image)
	frame.add_child(picture)
	return frame

func show_mod_textures() -> void:
	"""Mods · Textures: each atlas the game is drawn with, as painted and as
	the cut-out polygons see it (pure white see-through, the phone's rule),
	what stands for it now, and the ways to see it, replace it, or have the
	original back; on desktop, the folders themselves. A replacement is one
	PNG of any size in the original's layout."""
	if not modal.visible:modal_origin=get_viewport().gui_get_focus_owner()
	for child in modal.get_children():modal.remove_child(child);child.queue_free()
	var box := VBoxContainer.new();box.add_theme_constant_override("separation",8);modal.add_child(box)
	box.add_child(label("MODS · TEXTURES",22,Color("8bd6ee")))
	var Mods=preload("res://native/presentation/mods.gd")
	if not ready_for_preview:
		box.add_child(label("Import your DEEP JAR first; the textures come from it.",15))
		var only := button("Back",show_mods,box);scrim.show();modal.show();layout_ui();only.grab_focus.call_deferred();return
	var intro := label("A PNG of any size replaces an atlas; keep the original layout. Pure white or transparent areas are see-through. Changes apply immediately.",12,Color("a2c3d3"))
	intro.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;intro.custom_minimum_size.x=580;box.add_child(intro)
	var first: Button=null
	for atlas in Mods.ATLASES:
		var status: Dictionary=Mods.texture_status(content.root,atlas)
		var card := PanelContainer.new();card.add_theme_stylebox_override("panel",style(Color("0b1b22aa"),Color("2f4d57")));box.add_child(card)
		var row := HBoxContainer.new();row.add_theme_constant_override("separation",10);card.add_child(row)
		for form in [["As painted",status.image],["Cut-outs see-through",Mods.cut_out(status.image,256)]]:
			var column_box := VBoxContainer.new();column_box.add_theme_constant_override("separation",2);row.add_child(column_box)
			column_box.add_child(checkered(form[1],84))
			column_box.add_child(label(form[0],10,Color("89a6a6")))
		var words := VBoxContainer.new();words.size_flags_horizontal=Control.SIZE_EXPAND_FILL;words.add_theme_constant_override("separation",2);row.add_child(words)
		words.add_child(label("%s · %s.png"%[atlas.title,atlas.name],15))
		var about := label(atlas.about,11,Color("a2c3d3"));about.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;about.custom_minimum_size.x=360;words.add_child(about)
		var standing := ("Replacement · %d×%d" if status.replaced else "Original · %d×%d")%[status.size.x,status.size.y]
		words.add_child(label(standing,11,Color("d7c399") if status.replaced else Color("89a6a6")))
		var actions := HBoxContainer.new();actions.add_theme_constant_override("separation",4);words.add_child(actions)
		for entry in [["View",func():show_texture(atlas),true],["Replace…",func():mods_target=atlas.name;mods_notice="";images.choose(),images.available()],["Restore original",func():
			mods_notice=("Restored the original %s."%atlas.name) if Mods.remove_texture(atlas.name) else "Could not remove the replacement."
			apply_textures();show_mod_textures(),status.replaced]]:
			var act := button(entry[0],entry[1],actions);act.custom_minimum_size.y=28;act.add_theme_font_size_override("font_size",13);act.disabled=not entry[2]
			for state in ["normal","hover","focus","pressed"]:
				var box_style := act.get_theme_stylebox(state).duplicate();box_style.content_margin_top=4;box_style.content_margin_bottom=4;act.add_theme_stylebox_override(state,box_style)
			if first==null:first=act
	var folders := HBoxContainer.new();folders.add_theme_constant_override("separation",8);box.add_child(folders)
	if not OS.has_feature("android") and not OS.has_feature("web"):
		var mods_dir := ProjectSettings.globalize_path(Mods.user_texture_path("deep").get_base_dir())
		button("Open mods folder",func():DirAccess.make_dir_recursive_absolute(mods_dir);OS.shell_open(mods_dir),folders).size_flags_horizontal=Control.SIZE_EXPAND_FILL
		button("Open original textures",func():OS.shell_open(ProjectSettings.globalize_path(content.root.path_join("data/textures"))),folders).size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var back := button("Back",show_mods,folders);back.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	if not mods_notice.is_empty():
		var note := label(mods_notice,12,Color("d7c399"));note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;note.custom_minimum_size.x=560;box.add_child(note)
	scrim.show();modal.show();layout_ui()
	(first if first!=null else back).grab_focus.call_deferred()

func show_texture(atlas: Dictionary, cut: bool=false) -> void:
	"""One atlas at the page's full size, texel for texel, over a
	checkerboard: as painted, or as the cut-out polygons see it."""
	var Mods=preload("res://native/presentation/mods.gd")
	var status: Dictionary=Mods.texture_status(content.root,atlas)
	for child in modal.get_children():modal.remove_child(child);child.queue_free()
	var box := VBoxContainer.new();box.add_theme_constant_override("separation",8);modal.add_child(box)
	box.add_child(label("%s · %s · %d×%d"%[atlas.title.to_upper(),"CUT-OUTS SEE-THROUGH" if cut else "AS PAINTED",status.size.x,status.size.y],18,Color("8bd6ee")))
	var big := checkered(Mods.cut_out(status.image,1024) if cut else status.image,420);big.size_flags_horizontal=Control.SIZE_SHRINK_CENTER;box.add_child(big)
	box.add_child(label(status.path.get_file()+("  ·  replacement" if status.replaced else "  ·  original"),12,Color("a2c3d3")))
	var row := HBoxContainer.new();row.add_theme_constant_override("separation",8);box.add_child(row)
	var other := button("Show cut-outs" if not cut else "Show as painted",func():show_texture(atlas,not cut),row);other.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var back := button("Back",show_mod_textures,row);back.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	scrim.show();modal.show();layout_ui();back.grab_focus.call_deferred()

func install_texture(path: String) -> void:
	var Mods=preload("res://native/presentation/mods.gd")
	var trouble: String=Mods.install_texture(mods_target,path) if not mods_target.is_empty() else "Choose an atlas first."
	if path.begins_with("user://") or path.begins_with(OS.get_cache_dir()):DirAccess.remove_absolute(path)
	mods_notice=trouble if not trouble.is_empty() else "%s.png replaced."%mods_target
	if trouble.is_empty():apply_textures()
	show_mod_textures()

func apply_textures() -> void:
	title_dock.view.library.reload_textures()

func focus_title() -> void:
	if not title_menu.continue_button.disabled: title_menu.continue_button.grab_focus.call_deferred()
	elif not title_menu.new_button.disabled: title_menu.new_button.grab_focus.call_deferred()
	else: title_menu.footer.grab_focus.call_deferred()

func refresh_title() -> void:
	title_menu.new_button.disabled=not ready_for_preview or import_busy or portable.busy
	title_menu.continue_button.disabled=true
	status.text=""
	if ready_for_preview and not import_busy and not portable.busy:
		var store := preload("res://native/simulation/save_store.gd").new()
		for index in 4:
			var path: String=save_path if index==3 else store.slot_path(index)
			if not FileAccess.file_exists(path):continue
			if store.read(path,content.data)!=null:
				title_menu.continue_button.disabled=false
				if store.recovered and index==3:status.text="Latest autosave is damaged; the previous save was loaded."
			elif index==3:status.text=store.failure
	focus_title()

func show_tools() -> void:
	get_viewport().disable_3d=false
	title_dock.set_active(false);abyss.environment.environment=inspector_environment;camera.current=true
	inspector_open=true;title_menu.hide();panel.show();model_name.show()
	abyss.show();abyss.process_mode=Node.PROCESS_MODE_INHERIT
	if ready_for_preview: show_model(maxi(0,catalog.selected))
	catalog.grab_focus()

func hide_tools() -> void:
	get_viewport().disable_3d=false
	abyss.environment.environment=null
	title_dock.set_active(true)
	inspector_open=false;dragging=false;panel.hide();model_name.hide();title_menu.show()
	if model!=null: remove_child(model);model.queue_free();model=null
	abyss.hide();abyss.process_mode=Node.PROCESS_MODE_DISABLED
	close_modal()

func set_preference(section: String, key: String, value: Variant) -> void:
	var config := ConfigFile.new();config.load(settings_path);config.set_value(section,key,value)
	DirAccess.make_dir_recursive_absolute(settings_path.get_base_dir())
	if config.save(settings_path)!=OK: status.text="Could not save settings. Check your user folder."

func show_settings(section: String="") -> void:
	"""The same settings screen the game and the station open."""
	close_modal()
	if not is_instance_valid(settings_panel):
		settings_panel=SettingsMenu.new();ui.add_child(settings_panel)
		settings_panel.changed.connect(apply_setting)
		settings_panel.closed.connect(close_settings)
		settings_panel.visibility_changed.connect(func():
			var behavior := Control.FOCUS_BEHAVIOR_DISABLED if settings_panel.visible else Control.FOCUS_BEHAVIOR_INHERITED
			title_menu.focus_behavior_recursive=behavior;panel.focus_behavior_recursive=behavior)
	modal_origin=get_viewport().gui_get_focus_owner()
	settings_panel.configure(settings_path,{
		"text":content.text,
		"auto_title":func():return title_dock.dive_audio.title_track() if title_dock.dive_audio.title_choice==0 and ready_for_preview else ""},
		false,TouchControls.last_input=="touch" or (TouchControls.last_input.is_empty() and DisplayServer.is_touchscreen_available()))
	scrim.show();settings_panel.open(section)

func close_settings() -> void:
	scrim.hide()
	if is_instance_valid(modal_origin) and modal_origin.is_visible_in_tree(): modal_origin.grab_focus.call_deferred();modal_origin=null
	else: focus_title()

func apply_setting(section: String, key: String) -> void:
	"""The title's backdrop and music follow the choices at once; everything
	else is read when a dive starts."""
	var config := ConfigFile.new();config.load(settings_path)
	var audio=title_dock.dive_audio
	match [section,key]:
		["audio","music"]: title_dock.set_music(clampf(float(config.get_value("audio","music",0.65)),0,1))
		["audio","effects"]: audio.effects_gain=clampf(float(config.get_value("audio","effects",0.75)),0,1);audio.apply_levels()
		["audio","title_music"]: audio.title_choice=title_dock.title_choice(config)
		["graphics","audio"]: title_dock.set_audio_enabled(bool(config.get_value("graphics","audio",true)))
		["graphics","modern"]: title_dock.set_lighting(bool(config.get_value("graphics","modern",true)))
		["graphics","station_smoothing"]: title_dock.view.set_station_smoothing(bool(config.get_value("graphics","station_smoothing",false)))
		["graphics","volumetric"],["graphics","detail"]:
			title_dock.wanted_volumetric=bool(config.get_value("graphics","volumetric",true)) and RenderingServer.get_current_rendering_method()=="forward_plus"
			title_dock.wanted_detail=bool(config.get_value("graphics","detail",true));title_dock.apply_lighting()
		["view","aspect_ratio"],["input","touch"]: fit_window();layout_ui()
		["view","orientation"]: Display.apply_orientation(clampi(int(config.get_value("view","orientation",0)),0,2))

func launch_game(resume: bool=false, player_name: String="Pilot", path: String="") -> void:
	if not ready_for_preview or launching: return
	if path.is_empty():path=save_path
	var chapter := 1
	if resume:
		var store=preload("res://native/simulation/save_store.gd").new()
		if store.read(path,content.data)==null: status.text=store.failure; return
		chapter=int(store.summary(path,content.data).get("chapter",1))
	launching=true
	# Building the dive is one long synchronous stretch: the region, every
	# model in it and every shader variant. Say so on screen first, and let
	# a frame draw it, so the last thing seen is not a menu that stopped.
	show_loading(content.text(229) if not content.text(229).is_empty() else "Loading…",chapter)
	await get_tree().process_frame
	if not is_inside_tree():return
	get_viewport().disable_3d=false
	var gameplay=load("res://native/gameplay.gd").new()
	gameplay.save_path=save_path;gameplay.load_path=path;gameplay.settings_path=settings_path
	gameplay.content=content; gameplay.continue_save=resume; gameplay.player_face=face_layers.duplicate(); gameplay.player_name="Pilot" if player_name.is_empty() else player_name
	get_tree().root.add_child(gameplay); get_tree().current_scene=gameplay; queue_free()
