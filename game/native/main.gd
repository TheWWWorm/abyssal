extends Node3D
## Campaign title screen with an optional, isolated content inspection workbench.
const Content = preload("res://native/content.gd")
const Model = preload("res://native/presentation/model.gd")
const Health = preload("res://native/simulation/health.gd")
const Trade = preload("res://native/simulation/trade.gd")
const StationTheme = preload("res://native/presentation/station_theme.gd")
const EngineLanguage = preload("res://native/presentation/engine_language.gd")
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
## The pilot's portrait as the original draws it (ab.a), composed by
## compose_face() from the choices below.
var face_layers: Array = [87,78,68,20,42,-1]
## The character sheet's choices: a woman's face or a man's, which premade
## head (face_heads), suit and accessory (0 for none).
var face_female := false
var face_head := 4
var face_suit := 1
var face_accessory := 0
## An imported picture in place of the drawn face (imported_art.make_photo).
var face_photo := ""
## The image picker is shared with the Mods page; set while it is for a portrait.
var photo_pick := false
const ImportedArt = preload("res://native/presentation/imported_art.gd")
var face_art := ImportedArt.new()
var face_preview: TextureRect
var face_captions: Array = []
var face_note: Label
var face_sexes: Array = []
var capture_path := ""
var capture_frames := 0
var title_menu := preload("res://native/presentation/title_menu.gd").new()
var inspector_open := false
var save_path := "user://native/campaign.json"
var settings_path := "user://native/settings.cfg"
## The imported game's language, which engine text on Auto follows.
var content_language := ""
## The settings tab to reopen after a language change redraws the title.
static var reopen_settings := ""
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
## The same picker for a music file, and the track it is for.
var music_files := preload("res://native/platform/image_file.gd").new()
var music_target := ""
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
const GraphicsQuality = preload("res://native/presentation/graphics_quality.gd")
const GraphicsProbe = preload("res://native/presentation/graphics_probe.gd")
## Measures the device on first start (or when asked) and picks a preset.
var graphics_probe: Node
var fps_counter := preload("res://native/presentation/fps_counter.gd").new()
## Lists the finger drags, on the title as in the dive.
var touch_scroll := preload("res://native/input/touch_scroll.gd").new()

func face_part_name(row: int) -> String:
	return [tr("Accessory"),tr("Face"),tr("Suit")][row]

func importer_messages() -> Array:
	"""The importers' fixed progress and failure text (desktop/import.js,
	android/import.js, browser/worker.js, browser/import_jar.py and
	tools/import_native.py). It arrives in English and is listed here so it is
	translated; importer_message() matches it."""
	return [tr("Loading the bundled offline importer…"),tr("Loading local importer…"),tr("Converting audio: %d / %d"),
		tr("Preparing your local game content…"),tr("Preparing browser content cache…"),tr("Decoding resources: %d%%"),
		tr("Reading game data…"),tr("Could not decode audio: %s"),tr("Damaged JAR entry: %s"),tr("JAR exceeds 16 MiB."),
		tr("Unsupported JAR: not a readable MIDlet archive."),tr("Unsupported JAR: this is not a DEEP MIDlet."),
		tr("Unsupported JAR: this DEEP build renders with JSR-184 (M3G) models under data/3d. Only the Mascot Capsule builds with MBAC models under data/v3d are supported, such as the Sony Ericsson release."),
		tr("JAR exceeds import limits"),tr("Unsafe JAR entry"),tr("Unsupported JAR entry"),tr("Invalid BMP"),
		tr("Importer files are missing. Re-export the complete Web build."),tr("Content import failed."),tr("Import failed."),
		tr("Expected a JAR path and output pack path.")]

func importer_message(message: String) -> String:
	"""An importer's English progress or failure text in the engine language;
	text it does not know stays as it came."""
	var text := message.strip_edges()
	for prefix in ["ValueError: ","Error: "]:
		if text.begins_with(prefix): return prefix+importer_message(text.trim_prefix(prefix))
	var found := RegEx.create_from_string("^Converting audio: (\\d+) / (\\d+)$").search(text)
	if found!=null: return tr("Converting audio: %d / %d")%[int(found.get_string(1)),int(found.get_string(2))]
	found=RegEx.create_from_string("^Decoding resources: (\\d+)%$").search(text)
	if found!=null: return tr("Decoding resources: %d%%")%int(found.get_string(1))
	for pattern in ["Could not decode audio: ","Damaged JAR entry: "]:
		if text.begins_with(pattern):
			var subject := text.trim_prefix(pattern)
			return (tr("Could not decode audio: %s") if pattern.begins_with("Could") else tr("Damaged JAR entry: %s"))%subject
	var translated := tr(text)
	return message if translated==text else translated

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
	add_child(touch_scroll)
	add_child(fps_counter)
	fps_counter.set_enabled(fps_counter.wanted(start_config_now()))
	add_child(canvas)
	canvas.add_child(ui)
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter=Control.MOUSE_FILTER_IGNORE
	# The title is built in the engine's language, which follows the game
	# opened last until this start's game is read.
	content_language=str(start_config_now().get_value("interface","content_language",""))
	apply_language()
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
	title_menu.update_help(bool(start_config.get_value("input","mouse_wheel_throttle",false)))
	Display.apply_orientation(clampi(int(start_config.get_value("view","orientation",0)),0,2))
	add_child(images)
	images.chosen.connect(func(path):(import_photo if photo_pick else install_texture).call(path))
	images.failed.connect(func(message):
		if photo_pick:show_face_note(message);return
		mods_notice=message;show_mod_textures())
	music_files.kind="audio";add_child(music_files)
	music_files.chosen.connect(install_music)
	music_files.failed.connect(func(message):mods_notice=message;show_mod_music())
	ui.add_child(panel)
	panel.add_theme_stylebox_override("panel",style(Color("091720f5"),Color("254451")))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	column.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	column.add_theme_constant_override("separation",8)
	column.add_child(label(tr("Content").to_upper(),26,Color("8bd6ee")))
	column.add_child(label(tr("Local game resources").to_upper(),13,Color("73a6b3")))
	column.add_child(HSeparator.new())
	column.add_child(label(tr("Model inspector"),22))
	status=title_menu.status
	tools_status=label("",14,Color("89a6a6"));tools_status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;column.add_child(tools_status)
	catalog.custom_minimum_size.y=44
	catalog.add_theme_font_size_override("font_size",17)
	catalog.item_selected.connect(show_model)
	column.add_child(catalog)
	button(tr("Back to main menu"),hide_tools)
	button(tr("Ship systems · native rule checks"),show_systems)
	button(tr("Headlights  ·  L"),toggle_lights)
	button(tr("Choose game content"),choose_content)
	
	column.add_child(HSeparator.new())
	details=label(tr("Orbit: drag right mouse / right stick\nZoom: mouse wheel\nFullscreen: F11"),14,Color("81a2b0"))
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
	portable.failed.connect(func(message):status.text=importer_message(message))
	portable.progress.connect(func(message):status.text=importer_message(message))
	portable.busy_changed.connect(func(active):
		title_menu.footer.text=tr("Cancel import") if active else content_picker_label()
		refresh_title())
	add_child(chooser)
	chooser.file_mode=FileDialog.FILE_MODE_OPEN_FILE
	chooser.access=FileDialog.ACCESS_FILESYSTEM
	chooser.filters=PackedStringArray(["*.jar,*.abyss ; %s"%tr("Game JAR or private content pack")])
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
	elif "--choose-jar" in args: status.text=tr("Choose your DEEP JAR to begin."); chooser.popup_centered_ratio(0.65)
	elif source_import_available() and FileAccess.file_exists(jar_path): import_jar(jar_path)
	else: status.text=tr("Choose your DEEP JAR to begin.")
	title_menu.footer.text=content_picker_label()
	if not ready_for_preview:status.text=tr("Choose your private .abyss content pack.") if not source_import_available() and not OS.has_feature("web") and portable.android==null else tr("Choose your JAR or private .abyss content pack.")
	refresh_title()
	if not reopen_settings.is_empty():
		show_settings(reopen_settings);reopen_settings="";settings_panel.focus_key="language"

func dropped_files(paths: PackedStringArray) -> void:
	"""A dropped file is the same request the picker makes, so it takes the same
	two routes. Anything else is said out loud rather than quietly ignored."""
	if paths.is_empty() or import_busy or portable.busy: return
	var path: String = paths[0]
	match path.get_extension().to_lower():
		"abyss": import_pack(path)
		"jar": import_jar(path)
		_: status.text=tr("Drop a DEEP .jar, or an .abyss content pack prepared on a computer.")

func content_picker_label() -> String:
	return tr("Choose JAR / content pack…") if source_import_available() or OS.has_feature("web") or portable.android!=null else tr("Choose content pack…")

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
	status.text=tr("Installing local content…")
	var cache:=pack_importer.install(path)
	if cache.is_empty():status.text=pack_importer.failure;return
	selected_jar="";open_cache(cache)

## Set while fit_window changes the canvas, which emits size_changed again.
var fitting := false
func fit_window() -> void:
	"""The title uses the dive's canvas rule, so an upright phone gets an upright
	title rather than a letterboxed landscape one."""
	if fitting:return
	var pixels := get_window().size
	if pixels.x>0 and pixels.y>0:
		fitting=true
		var config := ConfigFile.new();config.load(settings_path)
		# The dive's rule (touch_controls.enabled), read before any dive exists.
		var mode:=clampi(int(config.get_value("input","touch",0)),0,2)
		var last:=TouchControls.last_input
		var touch: bool=mode==1 or (mode==0 and (last=="touch" or (last.is_empty() and DisplayServer.is_touchscreen_available())))
		Display.apply(get_window(),Display.valid(str(config.get_value("view","aspect_ratio","auto"))),Display.responsive_size(pixels,touch))
		fitting=false
		if not probing():apply_render_quality()
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
	# The reference reads best with all the room the window has.
	if modal.get_node_or_null("Reference")!=null:modal.size=Vector2(minf(1400,ui.size.x-32),ui.size.y-32)
	modal.position=(ui.size-modal.size)*0.5
	loading.size=loading.get_combined_minimum_size();loading.position=(ui.size-loading.size)*0.5

func import_jar(path: String) -> void:
	if import_busy: return
	if not source_import_available():status.text=tr("Prepare a .abyss content pack on desktop first.");return
	import_busy=true
	selected_jar=path
	status.text=tr("Importing your game content…")
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
	content_language=EngineLanguage.content_language(str(content.data.get("language","")),content.data.strings)
	set_preference("interface","content_language",content_language)
	if apply_language():
		# Another game's language: the title is drawn again in it.
		get_tree().reload_current_scene.call_deferred();return
	catalog.clear()
	for record: Dictionary in content.registry: catalog.add_item(content.record_name(record))
	ready_for_preview=true
	title_menu.load_content(content.root)
	preload("res://native/presentation/coin_glyph.gd").install(content.root)
	var initial := 0
	for i in content.registry.size():
		if int(content.registry[i].id)==0: initial=i; break
	catalog.select(initial)
	if inspector_open: show_model(initial)
	title_dock.load_content(content,save_path,settings_path)
	refresh_title()
	apply_render_quality()
	var question := language_question()
	# The graphics measurement waits for the answer: both use the dialog.
	if not question.is_empty():ask_language.call_deferred(question[0],question[1])
	elif wants_graphics_probe():start_graphics_probe.call_deferred()
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
		if not progress.is_empty():status.text=importer_message(progress)
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
			status.text=tr("Import failed. %s")%importer_message(str(result.text).strip_edges().split("\n")[-1]) if bundled_import else tr("Import failed. Check your JAR and local converter dependencies.")
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
	box.add_child(label(tr("Native ship systems"),28))
	var explanation := label(tr("Verification workbench: isolated test inputs.\nThese are ported rules, not a playable campaign."),16,Color("93b4c1"))
	box.add_child(explanation)
	health.configure(75,30,20)
	health_label=label("",20)
	box.add_child(health_label)
	button(tr("Apply 35 combined damage"),func(): health.damage(35); refresh_systems(),box)
	button(tr("Restore test hull"),func(): health.configure(75,30,20); refresh_systems(),box)
	trade.price=100; trade.owned=0; trade.stock=3; credits=1000
	trade_label=label("",18)
	box.add_child(trade_label)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation",12)
	box.add_child(actions)
	button(tr("Buy one"),func(): credits+=trade.transact(true,credits,trade.owned,2); refresh_systems(),actions)
	button(tr("Sell one"),func(): credits+=trade.transact(false,credits,trade.owned,2); refresh_systems(),actions)
	var ok := button(tr("OK  ·  Enter / Esc"),close_modal,box)
	refresh_systems()
	scrim.show()
	modal.show()
	layout_ui()
	ok.grab_focus.call_deferred()

func refresh_systems() -> void:
	health_label.text=tr("Hull %d    Shield %d    Armor %d") % [health.hull,health.shield,health.armor]
	trade_label.text=tr("Credits %d  ·  Cargo %d / 2  ·  Stock %d\nTest item: 100 credits each") % [credits,trade.owned,trade.stock]

func close_modal() -> void:
	stop_music_preview()
	modal.hide()
	scrim.hide()
	if inspector_open: catalog.grab_focus()
	elif is_instance_valid(modal_origin) and modal_origin.is_visible_in_tree() and not modal_origin.disabled: modal_origin.grab_focus.call_deferred();modal_origin=null
	else: focus_title()

func _exit_tree() -> void:
	if importer.is_started(): importer.wait_to_finish()

func show_start(player_name: String="") -> void:
	if not ready_for_preview: return
	if player_name.is_empty(): player_name=tr("Pilot")
	face_art.root=content.root
	for child in modal.get_children(): modal.remove_child(child); child.queue_free()
	var shell := VBoxContainer.new();shell.name="CharacterSheet";shell.add_theme_constant_override("separation",12); modal.add_child(shell)
	shell.add_child(label(tr("Create your character").to_upper(),26,Color("8bd6ee")))
	shell.add_child(label(tr("Choose your name and portrait."),15))
	# Scrolls only where a phone's height cannot hold it all.
	var scroll:=ScrollContainer.new();scroll.follow_focus=true;scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;shell.add_child(scroll)
	# Inset so a focused field's outline is not cut by the scroller's edge.
	var inset:=MarginContainer.new();inset.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(inset)
	for edge in ["margin_top","margin_bottom","margin_left","margin_right"]: inset.add_theme_constant_override(edge,4)
	var box := VBoxContainer.new();box.size_flags_horizontal=Control.SIZE_EXPAND_FILL;box.add_theme_constant_override("separation",12);inset.add_child(box)
	var name_field := LineEdit.new(); name_field.placeholder_text=tr("Your name"); name_field.text=player_name; name_field.max_length=32;name_field.custom_minimum_size.y=44; box.add_child(name_field)
	# A man or a woman, so the arrows only step through that one's faces.
	var sexes := HBoxContainer.new();sexes.alignment=BoxContainer.ALIGNMENT_CENTER;sexes.add_theme_constant_override("separation",8);box.add_child(sexes)
	var group := ButtonGroup.new();face_sexes=[]
	for female in [false,true]:
		var choice := button(tr("Female") if female else tr("Male"),func(): set_face_sex(female),sexes)
		choice.toggle_mode=true;choice.button_group=group;choice.alignment=HORIZONTAL_ALIGNMENT_CENTER;choice.custom_minimum_size=Vector2(120,44);face_sexes.append(choice)
	# The portrait between two columns of arrows, one row each for the
	# accessory, the face and the suit.
	var stage := HBoxContainer.new();stage.alignment=BoxContainer.ALIGNMENT_CENTER;stage.add_theme_constant_override("separation",10);box.add_child(stage)
	var backward := VBoxContainer.new();backward.alignment=BoxContainer.ALIGNMENT_CENTER;backward.add_theme_constant_override("separation",14);stage.add_child(backward)
	var frame := PanelContainer.new();frame.add_theme_stylebox_override("panel",StationTheme.panel(false));stage.add_child(frame)
	face_preview=TextureRect.new();face_preview.custom_minimum_size=Vector2(160,160);face_preview.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;face_preview.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;face_preview.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;frame.add_child(face_preview)
	var forward := VBoxContainer.new();forward.alignment=BoxContainer.ALIGNMENT_CENTER;forward.add_theme_constant_override("separation",14);stage.add_child(forward)
	var arrows: Array=[]
	for row in 3: arrows.append([face_arrow("‹",row,-1,backward,arrows),face_arrow("›",row,1,forward,arrows)])
	var captions := VBoxContainer.new();captions.add_theme_constant_override("separation",0);box.add_child(captions)
	face_captions=[]
	for row in 3:
		var caption := label("",14,Color("a2c3d3"));caption.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;captions.add_child(caption);face_captions.append(caption)
	var actions := HBoxContainer.new();actions.alignment=BoxContainer.ALIGNMENT_CENTER;actions.add_theme_constant_override("separation",8);box.add_child(actions)
	var random := button(content.text(302) if not content.text(302).is_empty() else tr("Generate face"),random_face,actions)
	var photo := button(tr("Import image"),choose_photo,actions);photo.disabled=not images.available()
	for action in [random,photo]: action.alignment=HORIZONTAL_ALIGNMENT_CENTER;action.custom_minimum_size=Vector2(140,44)
	face_note=label("",13,Color("89a6a6"));face_note.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;face_note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;box.add_child(face_note)
	refresh_face()
	box.add_child(label(tr("World spacing").to_upper(),18,Color("8bd6ee")))
	var config:=ConfigFile.new();config.load(settings_path)
	var spacing:=preload("res://native/simulation/world_spacing.gd").new();spacing.read_config(config)
	var controls:=preload("res://native/presentation/world_settings.gd").new();controls.configure(spacing);box.add_child(controls)
	controls.changed.connect(func():
		var saved:=ConfigFile.new();saved.load(settings_path);spacing.write_config(saved)
		DirAccess.make_dir_recursive_absolute(settings_path.get_base_dir())
		if saved.save(settings_path)!=OK:status.text=tr("Could not save settings. Check your user folder."))
	box.add_child(label(tr("Change later in Options → Gameplay."),14,Color("89a6a6")))
	shell.add_child(label(tr("Your previous checkpoint is kept as a backup."),12,Color("89a6a6")))
	button(tr("Start game").to_upper(),func(): launch_game(false,name_field.text.strip_edges()),shell)
	button(tr("Back"),close_modal,shell)
	# The first focus lands before the sheet has its size; following it then
	# would scroll the name field out of sight.
	scroll.follow_focus=false;name_field.focus_exited.connect(func(): scroll.follow_focus=true,CONNECT_ONE_SHOT)
	scrim.show(); modal.show();layout_ui();name_field.grab_focus.call_deferred()
func face_arrow(text: String, row: int, direction: int, parent: Node, arrows: Array) -> Button:
	"""One of the portrait's arrows. On a pad or keyboard, left and right on
	either arrow of a row step that row, so up and down choose the row."""
	var arrow := button(text,func(): step_face(row,direction),parent)
	arrow.alignment=HORIZONTAL_ALIGNMENT_CENTER;arrow.custom_minimum_size=Vector2(52,44);arrow.add_theme_font_size_override("font_size",26);arrow.tooltip_text=face_part_name(row)
	arrow.gui_input.connect(func(event: InputEvent):
		for step in [[-1,"ui_left"],[1,"ui_right"]]:
			if event.is_action_pressed(step[1],true):
				arrow.accept_event();step_face(row,step[0]);arrows[row][0 if step[0]<0 else 1].grab_focus();return)
	return arrow

func face_table() -> Array:
	"""The JAR's portrait table (ab.a): per layer, per column the face
	images; the columns are a light-skinned man, a dark-skinned man and a
	woman, and the layers backdrop, suit, chin, eyes, hair and accessory."""
	var table: Array=content.data.get("constants",{}).get("ab",{}).get("a:[[[B",[])
	return table if table.size()>=6 else []

func face_heads(female: bool) -> Array:
	"""The premade heads the sheet offers, each [column, chin, eyes, hair]
	from one column of the table: for a man the light-skinned and then the
	dark-skinned, for a woman the third column, which the original keeps for
	its crew. The k-th head takes the k-th of each part, from the start again
	where a part runs out, so every chin, pair of eyes and hairstyle is in
	some head, and every head is one the original could draw."""
	var table := face_table();var heads: Array=[]
	if table.is_empty(): return heads
	for column in ([2] if female else [0,1]):
		var chins: Array=table[2][column];var eyes: Array=table[3][column];var hair: Array=table[4][column]
		if chins.is_empty() or eyes.is_empty() or hair.is_empty(): continue
		for k in maxi(chins.size(),maxi(eyes.size(),hair.size())): heads.append([column,int(chins[k%chins.size()]),int(eyes[k%eyes.size()]),int(hair[k%hair.size()])])
	return heads

func face_counts() -> Array:
	"""How many accessories (with none), heads and suits the sheet's rows hold."""
	var table := face_table();var heads := face_heads(face_female)
	if heads.is_empty(): return [1,0,0]
	var column: int=heads[posmod(face_head,heads.size())][0]
	return [1+table[5][column].size(),heads.size(),table[1][column].size()]

func compose_face() -> void:
	"""face_layers from the sheet's choices, in the original's drawing order
	(ab.a): a man's suit goes under his chin, a woman's over hers. The
	backdrop is always the plain one the original gives the player (bu.a:
	ab.a(true,3), the fourth), or the table's last if it is shorter."""
	var table := face_table();var heads := face_heads(face_female)
	if heads.is_empty(): return
	var counts := face_counts()
	face_head=posmod(face_head,heads.size());face_accessory=posmod(face_accessory,counts[0]);face_suit=posmod(face_suit,maxi(1,counts[2]))
	var head: Array=heads[face_head];var column: int=head[0]
	var backdrops: Array=table[0][column];var suits: Array=table[1][column]
	var backdrop: int=int(backdrops[mini(3,backdrops.size()-1)]) if not backdrops.is_empty() else -1
	var suit: int=int(suits[face_suit]) if not suits.is_empty() else -1
	var accessory: int=-1 if face_accessory==0 else int(table[5][column][face_accessory-1])
	face_layers=[backdrop,suit,head[1],head[2],head[3],accessory] if column<2 else [backdrop,head[1],suit,head[2],head[3],accessory]

func step_face(row: int, direction: int) -> void:
	"""An arrow: the next or previous accessory, head or suit, which also
	brings back the drawn face after an imported picture."""
	var counts := face_counts()
	match row:
		0: face_accessory=posmod(face_accessory+direction,counts[0])
		1: face_head=posmod(face_head+direction,maxi(1,counts[1]))
		2: face_suit=posmod(face_suit+direction,maxi(1,counts[2]))
	face_photo="";refresh_face()

func set_face_sex(female: bool) -> void:
	if female==face_female and face_photo.is_empty(): return
	face_female=female;face_head=0;face_suit=0;face_accessory=0;face_photo="";refresh_face()

func random_face() -> void:
	"""The original's "Generate face" (ch: 302; ab.a(true,3)): a dark-skinned
	man at the table's own odds (c:byte), otherwise a light-skinned one, or a
	woman when Female is chosen; then one of those heads, any suit, and an
	accessory at the table's own odds (d:byte). The original draws chin, eyes
	and hair apart; here they come as one premade head."""
	var parts: Dictionary=content.data.get("constants",{}).get("ab",{})
	var heads := face_heads(face_female)
	if heads.is_empty(): return
	var column: int=2 if face_female else (1 if randi()%100<int(parts.get("c:byte",20)) else 0)
	var choices: Array=range(heads.size()).filter(func(index): return heads[index][0]==column)
	face_head=int(choices.pick_random()) if not choices.is_empty() else randi()%heads.size()
	var counts := face_counts()
	face_suit=randi()%maxi(1,counts[2])
	face_accessory=1+randi()%(counts[0]-1) if counts[0]>1 and randi()%100<int(parts.get("d:byte",60)) else 0
	face_photo="";refresh_face()

func refresh_face() -> void:
	compose_face()
	if is_instance_valid(face_preview): face_preview.texture=face_art.portrait(face_layers,face_photo)
	var counts := face_counts();var chosen := [face_accessory,face_head+1,face_suit+1]
	for row in face_captions.size():
		if not is_instance_valid(face_captions[row]): continue
		var total: int=counts[row]-(1 if row==0 else 0)
		face_captions[row].text=face_part_name(row)+" · "+tr("None") if row==0 and face_accessory==0 else tr("%s %d / %d")%[face_part_name(row),chosen[row],total]
		face_captions[row].modulate.a=1.0 if face_photo.is_empty() else 0.45
	for index in face_sexes.size():
		if is_instance_valid(face_sexes[index]): face_sexes[index].set_pressed_no_signal(face_female==(index==1))
	show_face_note("" if face_photo.is_empty() else tr("Imported image. The arrows bring back a drawn face."))

func show_face_note(text: String) -> void:
	if is_instance_valid(face_note): face_note.text=text;face_note.visible=not text.is_empty()

func choose_photo() -> void:
	photo_pick=true;images.any_image=true;images.choose()

## The largest picture file read for a portrait.
const PHOTO_FILE_LIMIT := 33554432

func import_photo(path: String) -> void:
	"""Import image: the original's camera portrait (bs.a), from a picture
	file instead (imported_art.make_photo). It stands in for the drawn face
	until an arrow or Generate face brings one back."""
	photo_pick=false
	var file := FileAccess.open(path,FileAccess.READ);var made := ""
	if file!=null:
		if file.get_length()<=PHOTO_FILE_LIMIT: made=ImportedArt.make_photo(file.get_buffer(file.get_length()))
		file.close()
	# The browser's and Android's pickers hand over a copy of their own.
	if path.begins_with("user://") or (OS.has_feature("android") and path.begins_with(OS.get_cache_dir())):DirAccess.remove_absolute(path)
	if made.is_empty(): show_face_note(tr("That file is not a picture the game can read."));return
	face_photo=made;refresh_face()

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
	var back := button(tr("Back"),close_modal,box)
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
		var back := button(tr("Back"),func():show_help(),box)
		scrim.show();modal.show();layout_ui();back.grab_focus.call_deferred();return
	box.add_child(label((tr("Help").to_upper() if not ready_for_preview else content.text(4).to_upper()),24,Color("8bd6ee")))
	var first: Button=null
	if not topics.is_empty():box.add_child(label(content.text(18),16,Color("aedbec")))
	var grid := GridContainer.new();grid.columns=2;grid.add_theme_constant_override("h_separation",10);grid.add_theme_constant_override("v_separation",6);box.add_child(grid)
	for index in topics.size():
		var row := button(topics[index].title,func():show_help(index),grid);row.custom_minimum_size.x=270
		if first==null:first=row
	if ready_for_preview:
		# The reference of the imported game; the title column has no room
		# for another row, so it opens from here.
		var reference := button(tr("Reference"),show_reference,box);reference.alignment=HORIZONTAL_ALIGNMENT_LEFT
		if first==null:first=reference
	var keys := label(title_menu.help.text,13,Color("b2d5e5"));keys.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;keys.custom_minimum_size.x=550;box.add_child(keys)
	if ready_for_preview:
		var credits := button(content.text(20),func():
			for child in modal.get_children():modal.remove_child(child);child.queue_free()
			var roll := VBoxContainer.new();roll.add_theme_constant_override("separation",10);modal.add_child(roll)
			var scroller := ScrollContainer.new();scroller.custom_minimum_size=Vector2(560,340);roll.add_child(scroller)
			var text := label(content.text(26)+"\n\n"+content.text(28)+"\n\n"+content.text(25),15);text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;text.custom_minimum_size.x=540;scroller.add_child(text)
			var back := button(tr("Back"),func():show_help(),roll);layout_ui();back.grab_focus.call_deferred(),box)
		credits.alignment=HORIZONTAL_ALIGNMENT_LEFT
	var back := button(tr("Back"),close_modal,box)
	if ready_for_preview:
		# Credits and Back share a row to keep the page inside a 720p window.
		var last := HBoxContainer.new();last.add_theme_constant_override("separation",10);box.add_child(last)
		for entry in [box.get_child(box.get_child_count()-3),back]:
			box.remove_child(entry);last.add_child(entry);entry.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	scrim.show();modal.show();layout_ui()
	(first if first!=null else back).grab_focus.call_deferred()

func show_reference() -> void:
	"""The reference of the imported game. Its story stops at the furthest
	chapter any of the saves has reached, so it gives nothing away."""
	if not ready_for_preview:return
	if not modal.visible:modal_origin=get_viewport().gui_get_focus_owner()
	for child in modal.get_children():modal.remove_child(child);child.queue_free()
	var store := preload("res://native/simulation/save_store.gd")
	var reached := 1
	for index in 4:
		var path: String=save_path if index==3 else store.slot_path(index)
		if FileAccess.file_exists(path):reached=maxi(reached,int(store.summary(path,content.data).get("chapter",1)))
	var reference=preload("res://native/wiki/wiki_panel.gd").new()
	reference.configure(content,reached,false,true,{"art":face_art})
	reference.closed.connect(close_modal)
	modal.add_child(reference)
	scrim.show();modal.show();layout_ui()

func show_mods() -> void:
	"""Mods: the sections of player-supplied art and music."""
	if not modal.visible:modal_origin=get_viewport().gui_get_focus_owner()
	for child in modal.get_children():modal.remove_child(child);child.queue_free()
	var box := VBoxContainer.new();box.add_theme_constant_override("separation",10);modal.add_child(box)
	box.add_child(label(tr("Mods").to_upper(),24,Color("8bd6ee")))
	stop_music_preview()
	var intro := label(tr("Replace the game's textures and music with your own files. Remove a replacement to restore the original."),13,Color("a2c3d3"))
	intro.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;intro.custom_minimum_size.x=560;box.add_child(intro)
	var textures := button(tr("Textures"),show_mod_textures,box)
	box.add_child(label(tr("The two texture atlases used by all models."),12,Color("89a6a6")))
	button(tr("Music"),show_mod_music,box)
	box.add_child(label(tr("The menu and station tracks, as OGG, MP3 or WAV."),12,Color("89a6a6")))
	var back := button(tr("Back"),close_modal,box)
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
	box.add_child(label(tr("Mods · Textures").to_upper(),22,Color("8bd6ee")))
	var Mods=preload("res://native/presentation/mods.gd")
	if not ready_for_preview:
		box.add_child(label(tr("Import your DEEP JAR first; the textures come from it."),15))
		var only := button(tr("Back"),show_mods,box);scrim.show();modal.show();layout_ui();only.grab_focus.call_deferred();return
	var intro := label(tr("A PNG of any size replaces an atlas; keep the original layout. Pure white or transparent areas are see-through. Changes apply immediately."),12,Color("a2c3d3"))
	intro.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;intro.custom_minimum_size.x=580;box.add_child(intro)
	var first: Button=null
	for atlas in Mods.atlases():
		var status: Dictionary=Mods.texture_status(content.root,atlas)
		var card := PanelContainer.new();card.add_theme_stylebox_override("panel",style(Color("0b1b22aa"),Color("2f4d57")));box.add_child(card)
		var row := HBoxContainer.new();row.add_theme_constant_override("separation",10);card.add_child(row)
		for form in [[tr("As painted"),status.image],[tr("Cut-outs see-through"),Mods.cut_out(status.image,256)]]:
			var column_box := VBoxContainer.new();column_box.add_theme_constant_override("separation",2);row.add_child(column_box)
			column_box.add_child(checkered(form[1],84))
			column_box.add_child(label(form[0],10,Color("89a6a6")))
		var words := VBoxContainer.new();words.size_flags_horizontal=Control.SIZE_EXPAND_FILL;words.add_theme_constant_override("separation",2);row.add_child(words)
		words.add_child(label("%s · %s.png"%[atlas.title,atlas.name],15))
		var about := label(atlas.about,11,Color("a2c3d3"));about.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;about.custom_minimum_size.x=360;words.add_child(about)
		var standing := (tr("Replacement · %d×%d") if status.replaced else tr("Original · %d×%d"))%[status.size.x,status.size.y]
		words.add_child(label(standing,11,Color("d7c399") if status.replaced else Color("89a6a6")))
		var actions := HBoxContainer.new();actions.add_theme_constant_override("separation",4);words.add_child(actions)
		for entry in [[tr("View"),func():show_texture(atlas),true],[tr("Replace…"),func():mods_target=atlas.name;mods_notice="";photo_pick=false;images.any_image=false;images.choose(),images.available()],[tr("Restore original"),func():
			mods_notice=(tr("Restored the original %s.")%atlas.name) if Mods.remove_texture(atlas.name) else tr("Could not remove the replacement.")
			apply_textures();show_mod_textures(),status.replaced]]:
			var act := button(entry[0],entry[1],actions);act.custom_minimum_size.y=28;act.add_theme_font_size_override("font_size",13);act.disabled=not entry[2]
			for state in ["normal","hover","focus","pressed"]:
				var box_style := act.get_theme_stylebox(state).duplicate();box_style.content_margin_top=4;box_style.content_margin_bottom=4;act.add_theme_stylebox_override(state,box_style)
			if first==null:first=act
	var folders := HBoxContainer.new();folders.add_theme_constant_override("separation",8);box.add_child(folders)
	if not OS.has_feature("android") and not OS.has_feature("web"):
		var mods_dir := ProjectSettings.globalize_path(Mods.user_texture_path("deep").get_base_dir())
		button(tr("Open mods folder"),func():DirAccess.make_dir_recursive_absolute(mods_dir);OS.shell_open(mods_dir),folders).size_flags_horizontal=Control.SIZE_EXPAND_FILL
		button(tr("Open original textures"),func():OS.shell_open(ProjectSettings.globalize_path(content.root.path_join("data/textures"))),folders).size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var back := button(tr("Back"),show_mods,folders);back.size_flags_horizontal=Control.SIZE_EXPAND_FILL
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
	box.add_child(label("%s · %s · %d×%d"%[atlas.title.to_upper(),tr("Cut-outs see-through").to_upper() if cut else tr("As painted").to_upper(),status.size.x,status.size.y],18,Color("8bd6ee")))
	var big := checkered(Mods.cut_out(status.image,1024) if cut else status.image,420);big.size_flags_horizontal=Control.SIZE_SHRINK_CENTER;box.add_child(big)
	box.add_child(label((tr("%s  ·  replacement") if status.replaced else tr("%s  ·  original"))%status.path.get_file(),12,Color("a2c3d3")))
	var row := HBoxContainer.new();row.add_theme_constant_override("separation",8);box.add_child(row)
	var other := button(tr("Show cut-outs") if not cut else tr("Show as painted"),func():show_texture(atlas,not cut),row);other.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var back := button(tr("Back"),show_mod_textures,row);back.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	scrim.show();modal.show();layout_ui();back.grab_focus.call_deferred()

func install_texture(path: String) -> void:
	var Mods=preload("res://native/presentation/mods.gd")
	var trouble: String=Mods.install_texture(mods_target,path) if not mods_target.is_empty() else tr("Choose an atlas first.")
	if path.begins_with("user://") or path.begins_with(OS.get_cache_dir()):DirAccess.remove_absolute(path)
	mods_notice=trouble if not trouble.is_empty() else tr("%s.png replaced.")%mods_target
	if trouble.is_empty():apply_textures()
	show_mod_textures()

func show_mod_music() -> void:
	"""Mods · Music: the JAR's two tracks, what plays for each now, and the
	ways to hear it, replace it with a file of the player's own, or have the
	converted MIDI back; on desktop, the folders themselves."""
	if not modal.visible:modal_origin=get_viewport().gui_get_focus_owner()
	for child in modal.get_children():modal.remove_child(child);child.queue_free()
	var box := VBoxContainer.new();box.add_theme_constant_override("separation",8);modal.add_child(box)
	box.add_child(label(tr("Mods · Music").to_upper(),22,Color("8bd6ee")))
	var Mods=preload("res://native/presentation/mods.gd")
	if not ready_for_preview:
		box.add_child(label(tr("Import your DEEP JAR first; the music comes from it."),15))
		var only := button(tr("Back"),show_mods,box);scrim.show();modal.show();layout_ui();only.grab_focus.call_deferred();return
	var intro := label(tr("An OGG Vorbis, MP3 or WAV file replaces a track and loops wherever it would play. Changes apply immediately."),12,Color("a2c3d3"))
	intro.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;intro.custom_minimum_size.x=580;box.add_child(intro)
	var first: Button=null
	for track in Mods.tracks():
		var status: Dictionary=Mods.music_status(content.root,track)
		var card := PanelContainer.new();card.add_theme_stylebox_override("panel",style(Color("0b1b22aa"),Color("2f4d57")));box.add_child(card)
		var words := VBoxContainer.new();words.add_theme_constant_override("separation",2);card.add_child(words)
		words.add_child(label("%s · %s.mid"%[track.title,track.name],15))
		var about := label(track.about,11,Color("a2c3d3"));about.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;about.custom_minimum_size.x=520;words.add_child(about)
		var standing := tr("Not in this JAR · a replacement adds it")
		if status.replaced: standing=tr("Replacement · %s · %s")%[status.path.get_file(),clock(status.length)] if status.readable else tr("Replacement · %s · cannot be read")%status.path.get_file()
		elif status.in_jar: standing=tr("Original · converted MIDI · %s")%clock(status.length)
		words.add_child(label(standing,11,Color("d7c399") if status.replaced else Color("89a6a6")))
		var playing: bool=title_dock.dive_audio.preview_track==track.name
		var actions := HBoxContainer.new();actions.add_theme_constant_override("separation",4);words.add_child(actions)
		for entry in [[tr("Stop") if playing else tr("Listen"),func():
			title_dock.dive_audio.preview_track="" if playing else track.name;show_mod_music(),status.readable],
			[tr("Replace…"),func():music_target=track.name;mods_notice="";music_files.choose(),music_files.available()],
			[tr("Restore original"),func():
				mods_notice=(tr("Restored the original %s track.")%track.name) if Mods.remove_music(track.name) else tr("Could not remove the replacement.")
				apply_music();show_mod_music(),status.replaced]]:
			var act := button(entry[0],entry[1],actions);act.custom_minimum_size.y=28;act.add_theme_font_size_override("font_size",13);act.disabled=not entry[2]
			for state in ["normal","hover","focus","pressed"]:
				var box_style := act.get_theme_stylebox(state).duplicate();box_style.content_margin_top=4;box_style.content_margin_bottom=4;act.add_theme_stylebox_override(state,box_style)
			if first==null:first=act
	var folders := HBoxContainer.new();folders.add_theme_constant_override("separation",8);box.add_child(folders)
	if not OS.has_feature("android") and not OS.has_feature("web"):
		var music_dir := ProjectSettings.globalize_path(Mods.user_music_path("station","ogg").get_base_dir())
		button(tr("Open mods folder"),func():DirAccess.make_dir_recursive_absolute(music_dir);OS.shell_open(music_dir),folders).size_flags_horizontal=Control.SIZE_EXPAND_FILL
		button(tr("Open original music"),func():OS.shell_open(ProjectSettings.globalize_path(content.root.path_join("data/sound"))),folders).size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var back := button(tr("Back"),show_mods,folders);back.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	if not mods_notice.is_empty():
		var note := label(mods_notice,12,Color("d7c399"));note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;note.custom_minimum_size.x=560;box.add_child(note)
	scrim.show();modal.show();layout_ui()
	(first if first!=null else back).grab_focus.call_deferred()

static func clock(seconds: float) -> String:
	return "%d:%02d"%[int(seconds)/60,int(seconds)%60]

func install_music(path: String) -> void:
	var Mods=preload("res://native/presentation/mods.gd")
	var trouble: String=Mods.install_music(music_target,path) if not music_target.is_empty() else tr("Choose a track first.")
	if path.begins_with("user://") or path.begins_with(OS.get_cache_dir()):DirAccess.remove_absolute(path)
	mods_notice=trouble if not trouble.is_empty() else tr("The %s track is replaced.")%music_target
	if trouble.is_empty():apply_music()
	show_mod_music()

func apply_music() -> void:
	if ready_for_preview:title_dock.dive_audio.reload_music(content.root)

func stop_music_preview() -> void:
	title_dock.dive_audio.preview_track=""

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
				if store.recovered and index==3:status.text=tr("Latest autosave is damaged; the previous save was loaded.")
			elif index==3:status.text=store.failure
		# Imported before the water palette was: every region shows the same
		# neutral water until the JAR is imported again (saves still match).
		if status.text.is_empty() and not content.data.has("water_palette"):
			status.text=tr("Import your JAR again for each region's original water colour. Saves are kept.")
	focus_title()

func show_tools() -> void:
	cancel_graphics_probe()
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
	if config.save(settings_path)!=OK: status.text=tr("Could not save settings. Check your user folder.")

func apply_render_quality(quality: Dictionary={}) -> void:
	"""The backdrop draws what the dive will: resolution, antialiasing,
	shadows, volumetric light and shading detail from the settings, or the
	preset being measured."""
	if quality.is_empty():
		var config := ConfigFile.new();config.load(settings_path);quality=GraphicsQuality.read(config)
	GraphicsQuality.apply_viewport(get_viewport(),quality,get_window().size)
	title_dock.set_quality(quality)

func start_config_now() -> ConfigFile:
	var config := ConfigFile.new();config.load(settings_path);return config

func probing() -> bool:
	return is_instance_valid(graphics_probe) and graphics_probe.running

func wants_graphics_probe() -> bool:
	"""Once, on the first start with content: no preset chosen or measured yet."""
	var config := ConfigFile.new();config.load(settings_path)
	# Measured once per profile. A profile whose preset came from before the
	# recommendation was stored is measured for the recommendation alone.
	if GraphicsQuality.measured(config):return false
	# Classic lighting chosen in an earlier version is a look, not a speed: keep it.
	if not GraphicsQuality.has_preset(config) and not GraphicsQuality.read(config).modern:
		GraphicsQuality.write(config,GraphicsQuality.CLASSIC)
		DirAccess.make_dir_recursive_absolute(settings_path.get_base_dir());config.save(settings_path)
		return false
	if DisplayServer.get_name()=="headless" or "--gameplay-capture" in OS.get_cmdline_user_args() or not capture_path.is_empty():return false
	return ready_for_preview and not launching

func start_graphics_probe() -> void:
	if probing() or not ready_for_preview or launching or inspector_open:return
	if is_instance_valid(settings_panel) and settings_panel.visible:return
	if is_instance_valid(graphics_probe):graphics_probe.queue_free()
	graphics_probe=GraphicsProbe.new();add_child(graphics_probe)
	var config := ConfigFile.new();config.load(settings_path)
	# A preset that an earlier detection chose and the player kept is
	# replaced by the new result, as a first choice is.
	graphics_probe.set_meta("first",not GraphicsQuality.has_preset(config) or GraphicsQuality.following_recommendation(config))
	graphics_probe.trying.connect(try_graphics_preset)
	title_dock.view.backdrop_close=true
	graphics_probe.finished.connect(finish_graphics_probe)
	status.text=tr("Choosing graphics settings for this device…")
	graphics_probe.begin()

func try_graphics_preset(preset: int) -> void:
	"""The preset over the player's own resolution, with the probe's margin."""
	var config := ConfigFile.new();config.load(settings_path)
	GraphicsQuality.write(config,preset)
	var quality := GraphicsQuality.read(config)
	quality.margin=GraphicsProbe.PIXEL_MARGIN
	apply_render_quality(quality)

func cancel_graphics_probe() -> void:
	"""Leaving the title while measuring keeps the settings as they were;
	the next start measures again."""
	if not probing():return
	graphics_probe.stop();graphics_probe.queue_free()
	title_dock.view.backdrop_close=false
	if status.text==tr("Choosing graphics settings for this device…"):status.text=""
	apply_render_quality()

func finish_graphics_probe(preset: int) -> void:
	var first: bool=graphics_probe.get_meta("first",true)
	graphics_probe.queue_free()
	title_dock.view.backdrop_close=false
	var config := ConfigFile.new();config.load(settings_path)
	# A preset the player already has stays; only the recommendation is new.
	if first or not GraphicsQuality.has_preset(config):GraphicsQuality.write(config,preset)
	config.set_value("graphics","recommended",preset)
	config.set_value("graphics","detection",GraphicsQuality.DETECTION_VERSION)
	DirAccess.make_dir_recursive_absolute(settings_path.get_base_dir())
	if config.save(settings_path)!=OK: status.text=tr("Could not save settings. Check your user folder.");return
	apply_render_quality()
	if status.text==tr("Choosing graphics settings for this device…"):status.text=""
	if first:show_graphics_choice(preset)

func language_question() -> Array:
	"""[system, game] the first time a game opens in another language than the
	system's, both with engine text, before any language was chosen."""
	if start_config_now().has_section_key("interface","language"):return []
	var system := EngineLanguage.supported(OS.get_locale())
	var game := EngineLanguage.supported(content_language)
	if system.is_empty() or game.is_empty() or system==game:return []
	return [system,game]

func ask_language(system: String, game: String) -> void:
	"""Engine text in the system's language, or everything in the game's. The
	question is put in both, since either may be the one the player reads."""
	if launching or inspector_open:return
	if is_instance_valid(settings_panel) and settings_panel.visible:return
	if not modal.visible:modal_origin=get_viewport().gui_get_focus_owner()
	for child in modal.get_children():modal.remove_child(child);child.queue_free()
	var box := VBoxContainer.new();box.name="LanguageChoice";box.add_theme_constant_override("separation",12);modal.add_child(box)
	box.add_child(label(EngineLanguage.text_in(system,"Language").to_upper(),24,Color("8bd6ee")))
	for code in [system,game]:
		var lines := [EngineLanguage.text_in(code,"System language: %s")%EngineLanguage.native_name(system),
			EngineLanguage.text_in(code,"Game language: %s")%EngineLanguage.native_name(game),
			EngineLanguage.text_in(code,"Show the engine's menus and messages in the system language? The game's own text stays in the game's language.")]
		var text := label("\n".join(lines),15 if code==system else 13,Color("d6e8ee") if code==system else Color("a2c3d3"))
		text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;text.custom_minimum_size.x=480;box.add_child(text)
	var answer := func(code: String):
		# Auto keeps following the game for everything; a language is fixed.
		set_preference("interface","language",code)
		close_modal()
		if apply_language():get_tree().reload_current_scene.call_deferred()
		elif wants_graphics_probe():start_graphics_probe()
	var first := button(EngineLanguage.native_name(system),answer.bind(system),box)
	button(EngineLanguage.native_name(game),answer.bind(EngineLanguage.AUTO),box)
	box.add_child(label(EngineLanguage.text_in(system,"You can change this in Settings › Display › Language."),13,Color("a2c3d3")))
	scrim.show();modal.show();layout_ui();first.grab_focus.call_deferred()

func show_graphics_choice(preset: int) -> void:
	"""Says which preset was chosen, once, where it cannot be missed."""
	if launching or inspector_open:return
	if is_instance_valid(settings_panel) and settings_panel.visible:return
	if not modal.visible:modal_origin=get_viewport().gui_get_focus_owner()
	for child in modal.get_children():modal.remove_child(child);child.queue_free()
	var box := VBoxContainer.new();box.name="GraphicsChoice";box.add_theme_constant_override("separation",12);modal.add_child(box)
	box.add_child(label(tr("Graphics").to_upper(),24,Color("8bd6ee")))
	var text := label(tr("The %s preset suits this device best, so the game now uses it.\n\nYou can choose another preset or change single settings in Settings > Graphics.")%GraphicsQuality.preset_names()[preset],16)
	text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;text.custom_minimum_size.x=480;box.add_child(text)
	var ok := button(tr("OK"),close_modal,box)
	button(tr("Open graphics settings"),func():close_modal();show_settings("graphics"),box)
	scrim.show();modal.show();layout_ui();ok.grab_focus.call_deferred()

func show_settings(section: String="") -> void:
	"""The same settings screen the game and the station open."""
	cancel_graphics_probe()
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
		"content_language":func():return content_language,
		"auto_title":func():return title_dock.dive_audio.title_track() if title_dock.dive_audio.title_choice==0 and ready_for_preview else ""},
		false,TouchControls.last_input=="touch" or (TouchControls.last_input.is_empty() and DisplayServer.is_touchscreen_available()))
	scrim.show();settings_panel.open(section)

func close_settings() -> void:
	scrim.hide()
	if is_instance_valid(modal_origin) and modal_origin.is_visible_in_tree(): modal_origin.grab_focus.call_deferred();modal_origin=null
	else: focus_title()

func apply_language() -> bool:
	"""Engine text in the chosen language, or the game's on Auto. True when
	that changed the language."""
	var before: String=EngineLanguage.current
	EngineLanguage.apply(EngineLanguage.resolve(str(start_config_now().get_value("interface","language",EngineLanguage.AUTO)),content_language))
	return EngineLanguage.current!=before

func apply_setting(section: String, key: String) -> void:
	"""The title's backdrop and music follow the choices at once; everything
	else is read when a dive starts."""
	var config := ConfigFile.new();config.load(settings_path)
	if [section,key]==["interface","language"] and apply_language():
		# The menus behind the settings are drawn again in the new language.
		reopen_settings="display";get_tree().reload_current_scene.call_deferred();return
	var audio=title_dock.dive_audio
	if key in SettingsMenu.OceanOptions.VISUALS:
		title_dock.apply_atmosphere(config)
	match [section,key]:
		["input","mouse_wheel_throttle"]: title_menu.update_help(bool(config.get_value("input","mouse_wheel_throttle",false)))
		["audio","music"]: title_dock.set_music(clampf(float(config.get_value("audio","music",0.65)),0,1))
		["audio","effects"]: audio.effects_gain=clampf(float(config.get_value("audio","effects",0.75)),0,1);audio.apply_levels()
		["audio","title_music"]: audio.title_choice=title_dock.title_choice(config)
		["graphics","audio"]: title_dock.set_audio_enabled(bool(config.get_value("graphics","audio",true)))
		["graphics","modern"]: title_dock.set_lighting(bool(config.get_value("graphics","modern",true)));apply_render_quality()
		["graphics","station_smoothing"]: title_dock.view.set_station_smoothing(bool(config.get_value("graphics","station_smoothing",false)))
		["graphics","ship_smoothing"]: title_dock.view.set_ship_smoothing(bool(config.get_value("graphics","ship_smoothing",false)))
		["graphics","headlight_mode"]: title_dock.view.set_headlight_mode(SettingsMenu.Headlights.read(config))
		["graphics","volumetric"],["graphics","detail"]:
			title_dock.wanted_volumetric=bool(config.get_value("graphics","volumetric",true)) and RenderingServer.get_current_rendering_method()=="forward_plus"
			title_dock.wanted_detail=bool(config.get_value("graphics","detail",true));title_dock.apply_lighting()
		["view","aspect_ratio"],["input","touch"]: fit_window();layout_ui()
		["view","show_fps"]: fps_counter.set_enabled(fps_counter.wanted(config))
		["view","resolution_height"],["view","render_scale"],["view","msaa"],["view","temporal_aa"],["view","upscaler"],["graphics","shadows"],["graphics","preset"]:
			title_dock.set_lighting(bool(config.get_value("graphics","modern",true)));apply_render_quality()
		["view","orientation"]: Display.apply_orientation(clampi(int(config.get_value("view","orientation",0)),0,2))

func launch_game(resume: bool=false, player_name: String="Pilot", path: String="") -> void:
	if not ready_for_preview or launching: return
	if path.is_empty():path=save_path
	var chapter := 1
	if resume:
		var store=preload("res://native/simulation/save_store.gd").new()
		if store.read(path,content.data)==null: status.text=store.failure; return
		chapter=int(store.summary(path,content.data).get("chapter",1))
	cancel_graphics_probe()
	launching=true
	# Building the dive is one long synchronous stretch: the region, every
	# model in it and every shader variant. Say so on screen first, and let
	# a frame draw it, so the last thing seen is not a menu that stopped.
	show_loading(content.text(229) if not content.text(229).is_empty() else tr("Loading…"),chapter)
	await get_tree().process_frame
	if not is_inside_tree():return
	get_viewport().disable_3d=false
	# The title is only freed at the end of the frame. Until then its fit_window
	# and the dive's update_render_resolution would each answer the other's
	# canvas change, and disagree about the ratio, recursing without end.
	if get_window().size_changed.is_connected(fit_window):get_window().size_changed.disconnect(fit_window)
	var gameplay=load("res://native/gameplay.gd").new()
	gameplay.save_path=save_path;gameplay.load_path=path;gameplay.settings_path=settings_path
	gameplay.content=content; gameplay.continue_save=resume; gameplay.player_face=face_layers.duplicate(); gameplay.player_photo=face_photo; gameplay.player_name=tr("Pilot") if player_name.is_empty() else player_name
	get_tree().root.add_child(gameplay); get_tree().current_scene=gameplay; queue_free()
