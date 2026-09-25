extends Node3D
const Session = preload("res://native/simulation/session.gd")
const World = preload("res://native/simulation/world.gd")
const Save = preload("res://native/simulation/save_store.gd")
const Economy = preload("res://native/simulation/economy.gd")
const View = preload("res://native/presentation/world_view.gd")
const Model = preload("res://native/presentation/model.gd")
const Map = preload("res://native/presentation/overworld_map.gd")
const DepthSlice = preload("res://native/presentation/depth_slice.gd")
## The original's chart cursor: a circle a twelfth of the ocean across. The
## side view shows what lies inside it.
const ZONE_RADIUS := 100.0/12.0
const Scanner = preload("res://native/presentation/scanner.gd")
const ContactMarker = preload("res://native/presentation/contact_marker.gd")
const StationTheme = preload("res://native/presentation/station_theme.gd")
const StationIcon = preload("res://native/presentation/station_icon.gd")
const RangeText = preload("res://native/presentation/range_text.gd")
const Spacing = preload("res://native/simulation/world_spacing.gd")
const Region = preload("res://native/simulation/region.gd")
const EquipmentInfo = preload("res://native/presentation/equipment_info.gd")
const Library = preload("res://scripts/model_library.gd")
var content
var imported_art := preload("res://native/presentation/imported_art.gd").new()
var stream_prompted := false
var departure_elapsed := 0.0
var opening := preload("res://native/presentation/opening.gd").new()
var opening_fraction := 0.0
var departure_destination := -1
var departure_route := "station"
var stream_selection := -1
var session
var world := World.new()
var economy := Economy.new()
var store := Save.new()
var camera := Camera3D.new()
var abyss := preload("res://native/presentation/abyss.gd").new()
var view := View.new()
var dive_audio := preload("res://native/presentation/dive_audio.gd").new()
var terrain := preload("res://native/presentation/terrain.gd").new()
var canvas := CanvasLayer.new()
var ui := Control.new()
var overlay := preload("res://native/presentation/instrument_panel.gd").new()
var column: VBoxContainer
var classic_frame := preload("res://native/presentation/classic_frame.gd").new()
var dashboard := preload("res://native/presentation/flight_dashboard.gd").new()
var hazard_warning := preload("res://native/presentation/hazard_warning.gd").new()
var damage_feedback := preload("res://native/presentation/damage_feedback.gd").new()
var damage_seen_ms := -1
var hints := Label.new()
var render_quality := 2
var temporal_aa := false
var player_face: Array = [85,65,75,16,43,-1]
var dock_prompt := Label.new()
var dock_caption := Label.new()
var market_selection := 0
var market_page := 0
var equipment_tab := 0
## How many tonnes one press of Buy or Sell moves. Kept between rows so a run of
## identical trades is set up once rather than once per commodity.
var market_quantity := 1
var stream_exit_active := false
## The original map has two modes, Navigate and Species. This is the second.
var stream_species := false
## Length of the framed passage along the gate axis: the 110 units from the
## alignment point to the aperture, and the 260 beyond it.
## The far side runs on a clock rather than on distance: what it shows is the
## submarine leaving for the station, which is a beat of fixed length, not a
## stretch of water to be crossed.
const TRANSIT_EXIT_SECONDS := 4.0
const STREAM_EXIT_FACTOR := 9.0
const STREAM_STANDOFF := 24.0
var transit_exit_elapsed := 0.0
## The throttle the player was flying before the crossing, restored across the
## exit so the shot ends at their own speed rather than at full ahead.
var transit_exit_throttle := 0.0
var transit_exit_factor := 2.0
var stream_resume_throttle := 100
var stream_exit_frame := Transform3D.IDENTITY
var atlas_autopilot_only := false
var autopilot_pressed_at := -1
var autopilot_hold_used := false
var sheet_full_height := 0.0
var sheet_index := 0
var sheet_pages: Array = []
var sheet_bar: HBoxContainer
var sheet_scroll: ScrollContainer
var market_category := ""
var original_ui_size := Vector2i.ZERO
var hud := Label.new()
var previous_hud_text := ""
var objective_label := RichTextLabel.new()
var message := Label.new()
## The reticle is drawn on the exact pixel the chase camera's shots converge
## on. A "+" glyph in a label sat five pixels off it, which reads as the
## harpoon missing what it was pointed at.
class Reticle extends Control:
	func _draw() -> void:
		# A broken ring with side ticks round a centre dot.
		var c := size*.5;var tint := Color("9fe3efcc")
		for quarter in 4:
			var middle := quarter*PI*.5+PI*.25
			draw_arc(c,8.0,middle-.5,middle+.5,8,tint,1.5,true)
		for side in [-1.0,1.0]:
			draw_line(c+Vector2(side*11,-3),c+Vector2(side*11,3),tint,1.5)
		draw_circle(c,1.5,tint)
var crosshair := Reticle.new()
var struggle := ProgressBar.new()
var instruments := preload("res://native/presentation/flight_instruments.gd").new()
var condition := preload("res://native/presentation/ship_condition.gd").new()
var bank_label := Label.new()
var pressure_overlay := ColorRect.new()
var pressure_material := ShaderMaterial.new()
var marker_layer := Control.new()
var markers: Array = []
var marker_by_contact := {}
var focused_contact := 0
const MAX_CONTACT_LABELS := 6
var page := ""
## The way back from the open page, taken by the header's BACK, Esc and B.
var page_back := Callable()
## Figures shown beside a page's title: credits, the current ship.
var header_chips: HBoxContainer
## Where the equipment shop puts its ship line: beside the tabs when wide.
var ship_strip: Node
## Docked pages drawn at the station's larger title size.
const STATION_PAGES := ["station","hangar","station_missions","station_status","system","market","ship_status","profile"]
const PAGE_SUBTITLES := {"hangar":"Equipment, ships and manufacture","station_missions":"Objectives, journal and contracts",
	"station_status":"Your ship, pilot profile and medals","system":"Save, controls and settings","ship_status":"Vessel, cargo and systems",
	"profile":"Pilot record","journal":"Current objectives"}
var lines: Array = []
var line_index := 0
var dialogue_cue := "message"
var dialogue_done: Callable
var key_bindings := {"left":KEY_A,"right":KEY_D,"up":KEY_UP,"throttle_up":KEY_W,"throttle_down":KEY_S,"down":KEY_DOWN,"fire":KEY_SPACE,"auto_fire":KEY_Q,"camera":KEY_C,"boost":KEY_SHIFT,"bank":KEY_TAB,"dock":KEY_E,"map":KEY_M,"autopilot":KEY_R,"time":KEY_T,"lights":KEY_L}
var suppress_fire_until_release := false
var auto_fire := false
var modern_graphics := true
var catch_status := Label.new()
var travel_status := Label.new()
var pending_notices: Array[String] = []
var graphics := {"audio":true,"materials":true,"headlights":true,"beams":true,"volumetric":true,"detail":true,"station_smoothing":false,"depth_limits":false}
var binding_action := ""
var map_widget
var map_info: RichTextLabel
var map_title: Label
var map_slice
var map_showcase: VBoxContainer
var map_picker: OptionButton
var map_destination := 0
## The atlas zone was moved off the chosen station and nothing is chosen.
var map_unchosen := false
var stream_button: Button
var map_route_button: Button
var pending_start := false
var continue_save := false
var player_name := "Diver"
var notification_time := 0.0
var capture_frames := 0
var capture_path := ""
var simulated_capture := false
var mouse_sensitivity := 0.8
var touch_look_sensitivity := 0.7
var fullscreen_supported := true
## The 1.4 touch controls sit in other places, so placements made against the
## earlier composition would be offsets from the wrong anchors.
const TOUCH_LAYOUT_KEY := "touch_layout_v2"
var invert_mouse := false
var strafe_mode := 0 # 0 auto · 1 always strafe · 2 always turn
var mouse_steer := Vector2.ZERO
var looking := false
# The browser owns pointer lock and can revoke it (Escape, tab change, a refused
# re-request) while Godot still reports MOUSE_MODE_CAPTURED. Steering has to
# follow the real lock, and a lock lost mid-dive has to pause the game once.
var web_lock_observed := false
var mouse_flight_enabled := false
var weapon_presses: Dictionary={}
var controller := preload("res://native/input/flight_controls.gd").new()
var touch := preload("res://native/input/touch_controls.gd").new()
var motion := preload("res://native/input/motion_steering.gd").new()
## Tilt steering, for devices that have the sensor for it. Off by default:
## a submarine that turns because the player shifted in their chair is worse
## than one that needs a thumb.
var motion_steering := false
var motion_sensitivity := 0.5
var invert_motion_pitch := false
var touch_scroll := preload("res://native/input/touch_scroll.gd").new()
var save_path := "user://native/campaign.json"
## The save an expedition was resumed from; the checkpoint above is the autosave.
var load_path := ""
var transfer := preload("res://native/simulation/save_transfer.gd").new()
var save_files := preload("res://native/platform/save_file.gd").new()
# A settings row that rebuilds its page hands its own key back here, so focus
# returns to the row the player just changed instead of the top of the list.
var focus_option := ""
## The phone game's one-time hints (br/ch, the ap flags). Their history is in
## the expedition save; this preference can suppress both those messages and
## the always-on control reminder without hiding objectives or action prompts.
var gameplay_hints := true
var flight_ms := 0
## Which Controls page is open. Empty is the list of sections itself.
var controls_section := ""
var freeze_view
var layout_editor
const TravelFade = preload("res://native/presentation/travel_fade.gd")
const Display = preload("res://native/presentation/display_settings.gd")
const SafeMargins = preload("res://native/platform/safe_margins.gd")
var aspect_ratio := "auto"
var settings_path := "user://native/settings.cfg"
var world_spacing := preload("res://native/simulation/world_spacing.gd").new()
func _ready() -> void:
	original_ui_size=get_window().content_scale_size
	get_window().size_changed.connect(update_render_resolution)
	if "--gameplay-capture" in OS.get_cmdline_user_args(): save_path="user://native/capture-only.json"
	add_child(camera); camera.current=true; camera.fov=65; camera.near=0.5; camera.far=View.DRAW_DISTANCE
	abyss.camera=camera; abyss.world=world; abyss.view=view; abyss.import_sky_ramp(content.root); add_child(abyss); dive_audio.world=world; add_child(dive_audio)
	add_child(view); terrain.world=world; terrain.camera=camera; add_child(terrain); add_child(canvas); canvas.add_child(ui); ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); ui.mouse_filter=Control.MOUSE_FILTER_IGNORE
	classic_frame.imported_art=imported_art;condition.imported_art=imported_art
	ui.add_child(classic_frame);classic_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(dashboard); dashboard.imported_art=imported_art; dashboard.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(hazard_warning);hazard_warning.z_index=20
	ui.add_child(opening);opening.z_index=30;opening.finished.connect(end_opening)
	ui.add_child(damage_feedback);damage_feedback.z_index=19
	ui.add_child(hints); hints.add_theme_font_size_override("font_size",12); hints.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; hints.modulate=Color("9bc2cf")
	pressure_material.shader=preload("res://native/presentation/pressure_overlay.gdshader"); pressure_overlay.material=pressure_material
	ui.add_child(pressure_overlay); pressure_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); pressure_overlay.mouse_filter=Control.MOUSE_FILTER_IGNORE
	ui.add_child(instruments); instruments.position=Vector2(26,52)
	ui.add_child(condition)
	ui.add_child(bank_label); bank_label.add_theme_font_size_override("font_size",13); bank_label.add_theme_color_override("font_color",Color("a6ced7")); bank_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT; bank_label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	ui.add_child(hud); hud.position=Vector2(26,24); hud.clip_text=true; hud.add_theme_font_size_override("font_size",18); hud.add_theme_color_override("font_color",Color("c9e7ea"))
	ui.add_child(objective_label); objective_label.position=Vector2(26,82); objective_label.bbcode_enabled=true; objective_label.scroll_active=false; objective_label.mouse_filter=Control.MOUSE_FILTER_IGNORE; objective_label.add_theme_color_override("default_color",Color("b7cbd0"))
	ui.add_child(struggle); struggle.position=Vector2(26,150); struggle.size=Vector2(240,7); struggle.show_percentage=false; struggle.mouse_filter=Control.MOUSE_FILTER_IGNORE; struggle.hide()
	for feedback in [catch_status,travel_status]:
		ui.add_child(feedback);feedback.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;feedback.add_theme_font_size_override("font_size",15);feedback.mouse_filter=Control.MOUSE_FILTER_IGNORE
		feedback.add_theme_color_override("font_color",Color("8bd6ee"));feedback.add_theme_color_override("font_shadow_color",Color.BLACK);feedback.add_theme_constant_override("shadow_offset_y",2)
	var track := StyleBoxFlat.new();track.bg_color=Color("173b42");struggle.add_theme_stylebox_override("background",track)
	var fill := StyleBoxFlat.new();fill.bg_color=Color("8fddc4");struggle.add_theme_stylebox_override("fill",fill)
	message.z_index=50;message.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	message.add_theme_color_override("font_shadow_color",Color.BLACK);message.add_theme_constant_override("shadow_offset_y",2)
	var toast := StationTheme.frame(Color(.016,.07,.1,.9),Color("3f9fbf"),8,1,Color(.25,.8,1.0,.18),6)
	toast.content_margin_left=16;toast.content_margin_right=16;toast.content_margin_top=7;toast.content_margin_bottom=8
	message.add_theme_stylebox_override("normal",toast)
	ui.add_child(message); message.add_theme_font_size_override("font_size",16); message.add_theme_color_override("font_color",Color("9ce5d1")); message.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	ui.add_child(crosshair); crosshair.size=Vector2(32,32); crosshair.mouse_filter=Control.MOUSE_FILTER_IGNORE
	ui.add_child(dock_prompt); dock_prompt.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; dock_prompt.add_theme_font_size_override("font_size",17); dock_prompt.modulate=Color("b6ecd7"); dock_prompt.mouse_filter=Control.MOUSE_FILTER_IGNORE
	# Outlined: the prompt at a gate sits over the aperture's glow.
	dock_prompt.add_theme_constant_override("outline_size",6); dock_prompt.add_theme_color_override("font_outline_color",Color(0.01,0.05,0.08,0.85))
	ui.add_child(dock_caption); dock_caption.add_theme_font_size_override("font_size",22); dock_caption.modulate=Color("8bd6ee"); dock_caption.mouse_filter=Control.MOUSE_FILTER_IGNORE
	ui.add_child(marker_layer); marker_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); marker_layer.mouse_filter=Control.MOUSE_FILTER_IGNORE
	for i in 96:
		var marker := ContactMarker.new(); marker_layer.add_child(marker); markers.append(marker)
	ui.add_child(overlay); overlay.add_theme_stylebox_override("panel",box_style())
	ui.add_child(touch);touch.action.connect(touch_action);touch.throttle_changed.connect(touch_throttle)
	# The compact HUD is laid out against the controls' own arrangement.
	touch.resized.connect(func(): layout.call_deferred())
	add_child(touch_scroll)
	add_child(save_files)
	save_files.chosen.connect(import_transfer)
	save_files.delivered.connect(notice)
	save_files.failed.connect(notice)
	fullscreen_supported=fullscreen_available();touch.show_fullscreen=not web_standalone()
	Input.joy_connection_changed.connect(controller_connection)
	ui.resized.connect(layout); overlay.minimum_size_changed.connect(func(): layout.call_deferred()); layout()
	var config := ConfigFile.new()
	if config.load(settings_path)==OK:
		for key in key_bindings: key_bindings[key]=setting_keycode(config,key,key_bindings[key])
		migrate_travel_bindings()
		for key in graphics: graphics[key]=bool(config.get_value("graphics",key,graphics[key]))
		modern_graphics=bool(config.get_value("graphics","modern",graphics.materials))
		# Migrate the former materials-only switch without carrying its Off state into New mode.
		if not config.has_section_key("graphics","modern") and not graphics.materials:graphics.materials=true
		if key_bindings.up==KEY_W: key_bindings.up=KEY_UP
		if key_bindings.down==KEY_S: key_bindings.down=KEY_DOWN
		mouse_sensitivity=setting_number(config,"keys","mouse_sensitivity",0.8,0.2,2.0); invert_mouse=bool(config.get_value("keys","invert_mouse",false))
		touch_look_sensitivity=setting_number(config,"input","touch_look",0.7,0.2,2.0)
		render_quality=setting_index(config,"view","resolution_v5",2,2)
		temporal_aa=bool(config.get_value("view","temporal_aa",false))
		dive_audio.music_gain=setting_number(config,"audio","music",0.65,0.0,1.0); dive_audio.effects_gain=setting_number(config,"audio","effects",0.75,0.0,1.0)
		view.camera_mode=setting_index(config,"view","camera",0,3)
		dive_audio.apply_levels()
	touch.mode=setting_index(config,"input","touch",0,2)
	touch.drag_anywhere=bool(config.get_value("input","touch_drag_anywhere",false))
	touch.fixed_stick=bool(config.get_value("input","touch_fixed_stick",false))
	controller.deadzone=setting_number(config,"input","deadzone",.18,.05,.45)
	controller.invert=bool(config.get_value("input","invert_gamepad",false))
	vibration=bool(config.get_value("input","vibration",true))
	strafe_mode=setting_index(config,"input","strafe",0,2)
	world.smooth_steering=bool(config.get_value("input","smooth_steering",false))
	touch.layout=preload("res://native/input/touch_layout.gd").decode(config.get_value("input",TOUCH_LAYOUT_KEY,""))
	aspect_ratio=Display.valid(str(config.get_value("view","aspect_ratio","auto")))
	motion_steering=bool(config.get_value("input","motion",false))
	motion_sensitivity=setting_number(config,"input","motion_sensitivity",0.5,0.0,1.0)
	invert_motion_pitch=bool(config.get_value("input","motion_invert",false))
	gameplay_hints=bool(config.get_value("interface","hints",true))
	world_spacing.read_config(config);world.spacing_meters=world_spacing.meters()
	Region.split_gates=bool(config.get_value("world","split_gates",true))
	motion.notice.connect(notice)
	if motion_steering: motion.enable()
	touch.arrange()
	if load_path.is_empty():load_path=save_path
	if continue_save:
		session=store.read(load_path,content.data)
		if session==null: session=Session.new(); session.new_game(content.data,player_name,Time.get_unix_time_from_system()); notice(store.failure)
		elif store.recovered: notice("Your save could not be read. Restored the previous checkpoint.")
	else:
		session=Session.new(); session.new_game(content.data,player_name,int(Time.get_unix_time_from_system())); session.face_layers=player_face.duplicate()
	imported_art.root=content.root
	world.configure(session); economy.configure(session); view.configure(world,content,camera); dive_audio.configure(world,content.root)
	apply_graphics()
	if continue_save and session.docked:
		# Build a stationary view without changing saved station state.
		world.build_docked_view(); show_station()
	else:
		session.prepare_station(session.station_id)
		if not continue_save: session.docked=true; save_game(false)
		world.depart(); close_page()
		var tooling: Array=OS.get_cmdline_user_args()
		if continue_save or "--gameplay-capture" in tooling or "--no-opening" in tooling: briefing()
		else: begin_opening()
	var launch_args := OS.get_cmdline_user_args()
	for index in launch_args.size():
		if launch_args[index]=="--gameplay-capture":simulated_capture=true
		if launch_args[index]=="--capture" and index+1<launch_args.size():capture_path=launch_args[index+1]
func layout() -> void:
	instruments.position=Vector2.ZERO; instruments.size=ui.size
	condition.size=Vector2(440,34); condition.position=Vector2((ui.size.x-440)*.5,ui.size.y-70)
	bank_label.size=Vector2(minf(400,ui.size.x*0.45),50); bank_label.position=Vector2(ui.size.x-26-bank_label.size.x,ui.size.y-60)
	# Touch: gauges and the cargo, credits and station line in the top left,
	# and a short depth gauge under the pause and map buttons.
	# Desktop shares the touch layout's gauges: condition, cargo and credits in
	# the top left and the short depth gauge down the right; thrust and boost
	# sit on the helm strip at the foot of the screen.
	condition.compact=true
	var k := hud_scale()
	instruments.compact_rect=touch.depth_rect if touch.enabled() else Rect2(Vector2(ui.size.x-64*k,110+60*k),Vector2(12*k,280*k))
	instruments.text_scale=k
	instruments.layout()
	condition.position=Vector2(28,22);condition.size=Vector2(330,96);condition.scale=Vector2.ONE*k
	classic_frame.scale_factor=k
	fit_hud()
	if page=="destinations":
		overlay.size=Vector2(minf(700,ui.size.x-48),minf(ui.size.y-48,fitted_height()));overlay.position=(ui.size-overlay.size)*.5
	elif page=="pause":
		overlay.size=Vector2(minf(430,ui.size.x-48),minf(ui.size.y-64,overlay.get_combined_minimum_size().y+maxf(sheet_full_height,column.get_combined_minimum_size().y)+2));overlay.position=Vector2(64,(ui.size.y-overlay.size.y)*.5)
	elif page in ["hangar","station_missions","station_status"]:
		overlay.size=Vector2(minf(1120,ui.size.x-64),minf(ui.size.y-64,fitted_height()));overlay.position=(ui.size-overlay.size)*.5
	elif page in ["ship_status","profile"]:
		overlay.size=Vector2(minf(1240,ui.size.x-48),minf(ui.size.y-48,fitted_height()));overlay.position=(ui.size-overlay.size)*.5
	elif page=="system":
		overlay.size=Vector2(minf(880,ui.size.x-64),minf(ui.size.y-64,fitted_height()));overlay.position=(ui.size-overlay.size)*.5
	elif page in ["controls","graphics","journal","failure","confirm","transfer"]:
		overlay.size=Vector2(minf(760,ui.size.x-64),minf(ui.size.y-64,overlay.get_combined_minimum_size().y+maxf(sheet_full_height,column.get_combined_minimum_size().y)+2));overlay.position=(ui.size-overlay.size)*.5
	elif page=="dialogue":
		overlay.size=Vector2(minf(660,ui.size.x-64),minf(300,ui.size.y-100)); overlay.position=(ui.size-overlay.size)*.5
	elif page=="station":
		# Down the left side, the docked station in view on the right.
		overlay.size=Vector2(minf(520,ui.size.x-48),minf(fitted_height(),ui.size.y-48));overlay.position=Vector2(24,ui.size.y-overlay.size.y-24)
		if ui.size.x<ui.size.y: overlay.position.y=ui.size.y-overlay.size.y-maxf(24,ui.size.y*.06)
	elif page in ["map","stream"]:
		overlay.size=Vector2(minf(1600,ui.size.x-48),ui.size.y-48);overlay.position=(ui.size-overlay.size)*.5
	elif page=="transit":
		overlay.size=Vector2(minf(760,ui.size.x-80),minf(520,ui.size.y-100));overlay.position=(ui.size-overlay.size)*.5
	elif page=="market" and market_category in ["equipment","ships","trade","manufacture"]:
		# One frame height for every selection: sized to its rows, the panel
		# jumped as a longer description or a shorter list was picked.
		overlay.size=Vector2(minf(ui.size.x-48,1400 if market_category=="ships" else 1240),minf(ui.size.y-48,920.0));overlay.position=(ui.size-overlay.size)*.5
	elif page in ["market","contracts","cargo","market_equipment","market_goods","equipment","ships","factory"]:
		overlay.size=Vector2(minf(1240 if market_category=="missions" else 1000,ui.size.x-64),ui.size.y-64);overlay.position=(ui.size-overlay.size)*.5
	else:
		overlay.position=Vector2(maxf(160,ui.size.x-minf(740,ui.size.x-190)-22),140);overlay.size=Vector2(minf(740,ui.size.x-190),maxf(260,ui.size.y-304))
	place_message()
	hazard_warning.size=Vector2(minf(640,ui.size.x-64),108);hazard_warning.position=Vector2((ui.size.x-hazard_warning.size.x)*.5,flight_notice_top()+104)
	catch_status.position=Vector2(ui.size.x*.5-240,minf(ui.size.y*.5+72,ui.size.y-282));catch_status.size=Vector2(480,44)
	struggle.position=Vector2(ui.size.x*.5-120,catch_status.position.y+42);struggle.size=Vector2(240,4)
	travel_status.position=Vector2(ui.size.x*.5-240,ui.size.y-220);travel_status.size=Vector2(480,30)
	objective_label.position=Vector2(30,103); objective_label.size=Vector2(minf(390,ui.size.x*.29),160); objective_label.add_theme_font_size_override("normal_font_size",12); objective_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	objective_label.position=Vector2(30,22+102*k);objective_label.scale=Vector2.ONE*k
	bank_label.scale=Vector2.ONE*k;bank_label.position=Vector2(ui.size.x-26-bank_label.size.x*k,ui.size.y-60*k)
	hints.position=Vector2(ui.size.x*.5-350,ui.size.y-21); hints.size=Vector2(700,18);hints.add_theme_font_size_override("font_size",9)
	if touch.enabled():
		hints.position.y=ui.size.y-30;hints.size.y=22;hints.add_theme_font_size_override("font_size",12)
		if touch.free_right>touch.free_left+120:
			hints.position.x=touch.free_left;hints.size.x=touch.free_right-touch.free_left
	update_render_resolution()
	crosshair.position=(ui.size*0.5-crosshair.size*.5).floor()
	# Under the notice band, clear of the hull below the crosshair.
	dock_prompt.position=Vector2(ui.size.x*.5-250,flight_notice_top()+54);dock_prompt.size=Vector2(500,40)
	dock_caption.position=Vector2(30,36);dock_caption.size=Vector2(ui.size.x*.5,80)
var layout_pending := false
func request_layout() -> void:
	if layout_pending: return
	layout_pending=true
	(func():layout_pending=false;if overlay.visible:layout()).call_deferred()
func fitted_height() -> float:
	"""The open page's height with all of its rows showing: the frame, header
	and footer around the scroller, and the rows inside it."""
	return overlay.get_combined_minimum_size().y+column.get_combined_minimum_size().y+2
func place_message() -> void:
	"""The notice sits above everything, so an open menu has to be given room
	rather than drawn through: a confirmation landing on a menu row reads as a
	rendering fault, not as an answer to what the player just did."""
	var font: Font = message.get_theme_font("font")
	var font_size: int = message.get_theme_font_size("font_size")
	var width := minf(maxf(220.0,font.get_string_size(message.text,HORIZONTAL_ALIGNMENT_CENTER,-1,font_size).x+40.0),minf(640.0,ui.size.x-40.0))
	var height := 44.0
	message.size=Vector2(width,height)
	var middle := (ui.size.x-width)*.5
	if overlay.visible:
		var below := overlay.position.y+overlay.size.y+14
		var above := overlay.position.y-height-14
		# Under the panel by preference, over it when there is room there, and
		# otherwise along the panel's own bottom edge, where it covers the key
		# legend rather than a row the player is reading.
		var y := below if below+height<=ui.size.y-12 else (above if above>=12 else overlay.position.y+overlay.size.y-height-6)
		# The charts fill the screen and keep their actions along the bottom,
		# so their notices cover the page title instead.
		if page in ["map","stream"] and below+height>ui.size.y-12: y=overlay.position.y+6
		message.position=Vector2(clampf((overlay.position.x+overlay.size.x*.5)-width*.5,12,maxf(12,ui.size.x-width-12)),y)
	else:
		# In flight the lower middle is the hull itself in the chase view, so
		# notices take the band under the target read-out at the top instead.
		message.position=Vector2(middle,flight_notice_top())
func hud_scale() -> float:
	"""The desktop canvas grows with the window up to 1920 wide, so its gauges
	grow with the height to keep the size the touch layout gives them."""
	return 1.0 if touch.enabled() else clampf(ui.size.y/720.0,1.0,1.6)*.67
func flight_notice_top() -> float:
	# Touch keeps its gauges in the top left, taller than the desktop line.
	return 132.0 if touch.enabled() else 88.0*hud_scale()
func fit_hud() -> void:
	var font: Font = hud.get_theme_font("font")
	var font_size := 18
	var width := minf(450,ui.size.x-190)
	hud.position=Vector2(28,53)
	while font_size>12 and font.get_string_size(hud.text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x>width: font_size-=1
	if hud.get_theme_font_size("font_size")!=font_size: hud.add_theme_font_size_override("font_size",font_size)
	hud.size=Vector2(width,26)
func golden() -> bool:
	return session!=null and session.medals.gold_set()
func box_style() -> StyleBoxFlat:
	return StationTheme.panel(golden())
func colours() -> Dictionary:
	return StationTheme.palette(golden())
var heading_fonts := {}
func heading_font(spacing: int) -> FontVariation:
	"""The tracked-out face of titles and captions, one per spacing."""
	if not heading_fonts.has(spacing): heading_fonts[spacing]=StationTheme.spaced(ui.get_theme_font("font","Label"),spacing)
	return heading_fonts[spacing]
func caption(text: String, size: int=11, parent: Node=null, spacing: int=3) -> Label:
	"""A small tracked-out heading in capitals."""
	var node := label(text.to_upper(),size,parent);node.add_theme_font_override("font",heading_font(spacing))
	node.add_theme_color_override("font_color",colours().dim);node.autowrap_mode=TextServer.AUTOWRAP_OFF
	return node
func glass(parent: Node, lit: bool=false, cut: int=12) -> PanelContainer:
	var panel := PanelContainer.new();panel.add_theme_stylebox_override("panel",StationTheme.card(golden(),lit,cut))
	panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL;parent.add_child(panel);return panel
func line_icon(icon: String, extent: float, parent: Node, tint=null) -> Control:
	var node := StationIcon.new(icon,colours().accent if tint==null else tint,extent);parent.add_child(node);return node
func primary(node: Button) -> Button:
	"""The page's main action: the green of the reference's Depart and Buy."""
	for state in ["normal","hover","pressed","focus"]: node.add_theme_stylebox_override(state,StationTheme.button_state(golden(),state,true))
	node.add_theme_color_override("font_color",colours().go_text);node.add_theme_color_override("font_focus_color",colours().go_text);node.add_theme_color_override("font_hover_color",colours().go_text)
	node.alignment=HORIZONTAL_ALIGNMENT_CENTER
	return node
func iconic(node: Button, icon: String, extent: float=26.0) -> Button:
	"""An icon at the left of a button's caption."""
	var mark := StationIcon.new(icon,node.get_theme_color("font_color"),extent);node.add_child(mark)
	mark.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT);mark.offset_left=14;mark.offset_right=14+extent;mark.offset_top=-extent*.5;mark.offset_bottom=extent*.5
	for state in ["normal","hover","pressed","focus","disabled"]:
		var style := node.get_theme_stylebox(state) as StyleBoxFlat
		if style!=null: style.content_margin_left=24+extent
	return node
func label(text: String, size: int=18, parent: Node=null) -> Label:
	var node := Label.new(); node.text=text; node.add_theme_font_size_override("font_size",size); node.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; node.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	(parent if parent!=null else column).add_child(node); return node
func information_card(title: String) -> VBoxContainer:
	var panel := glass(column)
	var body := VBoxContainer.new(); body.add_theme_constant_override("separation",8); panel.add_child(body)
	label(title,18,body).add_theme_color_override("font_color",colours().accent); return body
func equipment_card(item) -> VBoxContainer:
	var card := information_card(item_name(item.id,"equipment"))
	art_image(imported_art.item(item.id,"equipment"),card,72)
	label(EquipmentInfo.stats(item),15,card).add_theme_color_override("font_color",Color("b6e3da"))
	var description := item_description(item.id,"equipment")
	if not description.is_empty(): label(description,14,card).add_theme_color_override("font_color",Color("b5c6cd"))
	return card
func button(text: String, action: Callable, parent: Node=null) -> Button:
	var node := Button.new(); node.text=text;
	for state in ["normal","hover","pressed","focus","disabled"]: node.add_theme_stylebox_override(state,StationTheme.button_state(golden(),state))
	var palette := colours()
	node.add_theme_color_override("font_color",palette.text);node.add_theme_color_override("font_focus_color",Color.WHITE);node.add_theme_color_override("font_hover_color",Color.WHITE)
	node.add_theme_color_override("font_disabled_color",palette.faint)
	node.alignment=HORIZONTAL_ALIGNMENT_LEFT; node.custom_minimum_size.y=64 if touch.enabled() else 44; node.size_flags_horizontal=Control.SIZE_EXPAND_FILL; node.add_theme_font_size_override("font_size",20 if touch.enabled() else 16); node.pressed.connect(action)
	(parent if parent!=null else column).add_child(node)
	return node
func option(text: String, key: String, action: Callable, parent: Node=null) -> Button:
	"""A settings row whose action rebuilds the page it lives on."""
	var node := button(text,func(): focus_option=key; action.call(),parent)
	node.set_meta("option",key)
	return node
func confirm(title: String, question: String, accept: String, act: Callable, cancel: Callable) -> void:
	"""Destructive menu actions ask first. The answer is the only way back."""
	open_page(title,"confirm")
	label(question,17)
	button(accept,act)
	button("Cancel",cancel)
func open_page(title: String, id: String, subtitle: String="") -> void:
	dive_audio.set_context(id,session!=null and session.docked)
	touch.set_active(false);controller.blocked=true
	autopilot_pressed_at=-1
	page=id;page_back=Callable(); weapon_presses.clear();world.weapon_pending.clear();world.speed=1; world.mouse_pending=Vector2.ZERO; looking=false; release_flight_mouse()
	overlay.add_theme_stylebox_override("panel",box_style())
	auto_fire=false
	for child in overlay.get_children(): overlay.remove_child(child); child.queue_free()
	sheet_index=0;sheet_full_height=0;sheet_pages.clear()
	var shell := VBoxContainer.new();shell.add_theme_constant_override("separation",12);overlay.add_child(shell)
	var header := HBoxContainer.new();header.add_theme_constant_override("separation",12);shell.add_child(header)
	var titles := VBoxContainer.new();titles.size_flags_horizontal=Control.SIZE_EXPAND_FILL;titles.add_theme_constant_override("separation",4);header.add_child(titles)
	var heading := label(title.to_upper(),30 if session!=null and session.docked and id in STATION_PAGES and ui.size.x>=700 and ui.size.y>=640 else 24,titles);heading.name="Heading"
	heading.add_theme_font_override("font",heading_font(7));heading.add_theme_color_override("font_color",colours().text);heading.autowrap_mode=TextServer.AUTOWRAP_OFF
	heading.clip_text=true;heading.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	var rule := ColorRect.new();rule.color=colours().accent;rule.custom_minimum_size=Vector2(56,2);rule.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN;titles.add_child(rule)
	if subtitle.is_empty(): subtitle=PAGE_SUBTITLES.get(id,"")
	if not subtitle.is_empty() and ui.size.x>=700 and ui.size.y>=640: caption(subtitle,11,titles,3).name="Subtitle"
	header_chips=HBoxContainer.new();header_chips.add_theme_constant_override("separation",10);header.add_child(header_chips)
	if id not in ["station","dialogue","failure","transit","map","stream"]:
		var back := iconic(button("CLOSE" if id=="destinations" else "BACK",dock_back,header),"back",18)
		back.size_flags_horizontal=Control.SIZE_SHRINK_END;back.size_flags_vertical=Control.SIZE_SHRINK_BEGIN;back.custom_minimum_size=Vector2(128,48 if touch.enabled() else 40)
		back.add_theme_font_override("font",heading_font(4))
	var scroll := ScrollContainer.new();sheet_scroll=scroll;scroll.follow_focus=true; scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;shell.add_child(scroll)
	scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_AUTO if touch.enabled() or id in ["station","destinations","controls"] else ScrollContainer.SCROLL_MODE_SHOW_NEVER
	column=VBoxContainer.new(); column.size_flags_horizontal=Control.SIZE_EXPAND_FILL; column.add_theme_constant_override("separation",7); scroll.add_child(column)
	# Panels sized to their rows follow the rows once text has wrapped to width.
	column.minimum_size_changed.connect(request_layout)
	touch_scroll.scroll=scroll;touch_scroll.gesture_control=null;touch_scroll.release()
	sheet_bar=HBoxContainer.new();shell.add_child(sheet_bar);sheet_bar.hide()
	# The keys, as the reference's footer shows them; a touch screen has none.
	var legend := HBoxContainer.new();legend.name="KeyLegend";legend.add_theme_constant_override("separation",8);shell.add_child(legend)
	legend.visible=not touch.enabled()
	for entry in [["ESC / B","CLOSE" if id=="destinations" else "BACK"],["D-PAD / ARROWS","NAVIGATE"],["ENTER / A","SELECT"]]:
		var boxed := StationTheme.frame(Color(0,0,0,0),colours().edge,0);boxed.set_content_margin_all(3);boxed.content_margin_left=7;boxed.content_margin_right=7
		var key := caption(entry[0],10,legend,1);key.add_theme_stylebox_override("normal",boxed);key.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
		var meaning := caption(entry[1],10,legend,2);meaning.add_theme_color_override("font_color",colours().faint);meaning.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
		meaning.custom_minimum_size.x=meaning.get_minimum_size().x+14
	overlay.show(); layout();layout.call_deferred();fit_sheets.call_deferred();focus_page.call_deferred()
	if id!="dialogue":
		for control in [classic_frame,hazard_warning,damage_feedback,dashboard,hud,instruments,condition,bank_label,hints,objective_label,crosshair,dock_prompt,catch_status,travel_status,struggle]:control.hide()
	for marker in markers:marker.hide()
func fit_sheets() -> void:
	# Content pages replace overflowing lists; no hidden clipping or tiny scrollbars.
	var source_column=column
	await get_tree().process_frame
	if not is_instance_valid(source_column) or source_column!=column or not is_instance_valid(sheet_scroll):return
	if not is_instance_valid(column) or not overlay.visible:return
	# Pages laid out as panels side by side scroll instead of splitting into sheets.
	if page in ["station","destinations","controls","map","stream","hangar","station_missions","station_status","system","ship_status","profile","journal"] or (page=="market" and market_category in ["equipment","ships","trade","manufacture"]):return
	for child in column.get_children():child.show()
	await get_tree().process_frame
	if not is_instance_valid(source_column) or source_column!=column or not is_instance_valid(sheet_scroll):return
	if not is_instance_valid(column):return
	sheet_full_height=column.get_combined_minimum_size().y;layout()
	await get_tree().process_frame
	if not is_instance_valid(source_column) or source_column!=column or not is_instance_valid(sheet_scroll):return
	var available: float=sheet_scroll.size.y
	if column.get_combined_minimum_size().y>available:available-=48
	sheet_pages.clear();var batch: Array=[];var height:=0.0
	# The separation falls between rows only, not after the last one.
	for child in column.get_children():
		if not child.visible:continue
		var next: float=child.get_combined_minimum_size().y+(7.0 if not batch.is_empty() else 0.0)
		if height+next>available+.5 and not batch.is_empty():sheet_pages.append(batch);batch=[];height=0;next=child.get_combined_minimum_size().y
		batch.append(child);height+=next
	if not batch.is_empty():sheet_pages.append(batch)
	for child in sheet_bar.get_children():sheet_bar.remove_child(child);child.queue_free()
	sheet_bar.visible=sheet_pages.size()>1
	if sheet_pages.size()>1:
		var previous:=iconic(button("PREVIOUS",func():sheet_index=maxi(0,sheet_index-1);display_sheet(),sheet_bar),"back",16)
		var number:=caption("",14,sheet_bar,2);number.name="SheetNumber";number.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;number.add_theme_color_override("font_color",colours().text)
		var following:=button("NEXT",func():sheet_index=mini(sheet_pages.size()-1,sheet_index+1);display_sheet(),sheet_bar);following.alignment=HORIZONTAL_ALIGNMENT_CENTER
		for node in [previous,following]:node.add_theme_font_override("font",heading_font(3))
	display_sheet()
func display_sheet() -> void:
	if sheet_pages.is_empty():return
	sheet_index=clampi(sheet_index,0,sheet_pages.size()-1)
	for child in column.get_children():child.visible=child in sheet_pages[sheet_index]
	var number=sheet_bar.get_node_or_null("SheetNumber")
	if number!=null:number.text="%02d / %02d"%[sheet_index+1,sheet_pages.size()]
func close_page() -> void:
	# Anything that closes the page under the opening ends the opening with it.
	if opening.active:opening.finish(false)
	dive_audio.set_context("",session!=null and session.docked)
	view.gate_preview=false
	touch_scroll.scroll=null;touch_scroll.gesture_control=null;touch_scroll.release()
	page=""; overlay.hide();get_viewport().gui_release_focus();
	# A notice given while the menu was up sat beside the menu; with the menu
	# gone it belongs in the flight's own band, not over the hull.
	place_message(); binding_action=""; suppress_fire_until_release=Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or Input.is_physical_key_pressed(key_bindings.fire)
	mouse_steer=Vector2.ZERO
	controller.blocked=true;touch.set_active(not session.docked)
	# A departure may open a briefing in this same frame. Never enqueue a
	# browser pointer-lock request before that menu decision has finished.
	capture_flight_mouse.call_deferred()
func capture_flight_mouse() -> void:
	if page.is_empty() and DisplayServer.get_name()!="headless" and not session.docked and not touch.enabled():
		mouse_flight_enabled=true
		web_lock_observed=false
		Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
func release_flight_mouse() -> void:
	mouse_steer=Vector2.ZERO
	mouse_flight_enabled=false
	web_lock_observed=false
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
func mouse_is_captured() -> bool:
	# Ask the document rather than Godot: a revoked or refused lock leaves the
	# engine's own mouse mode saying Captured with no pointer lock in place.
	if OS.has_feature("web"): return browser_flag("document.pointerLockElement !== null")
	return Input.mouse_mode==Input.MOUSE_MODE_CAPTURED
func free_look_held() -> bool:
	# Either modifier: Alt is the one a browser leaves alone, Ctrl the one a
	# desktop pilot reaches for. Neither steers while held.
	return page.is_empty() and not touch.enabled() and (Input.is_key_pressed(KEY_ALT) or Input.is_key_pressed(KEY_CTRL))
func mouse_steering_enabled() -> bool:
	if touch.enabled(): return false
	# Some browsers refuse to re-lock after Escape even from a fresh click, so
	# canvas motion stays usable while a new capture gesture is pending.
	return mouse_flight_enabled if OS.has_feature("web") else Input.mouse_mode==Input.MOUSE_MODE_CAPTURED
func watch_browser_capture() -> void:
	if not OS.has_feature("web") or not page.is_empty() or not mouse_flight_enabled: return
	var captured := mouse_is_captured()
	if web_lock_observed and not captured:
		# Escape's browser default can swallow the key event entirely. A real
		# locked -> unlocked transition still has to pause the dive, once.
		# A refused first request never gets here, nor does a menu release.
		release_flight_mouse()
		show_pause()
		return
	web_lock_observed=captured
func notice(text: String) -> void:
	if text.begins_with("Time ·"):
		pending_notices=pending_notices.filter(func(value):return not value.begins_with("Time ·"))
		if message.text.begins_with("Time ·"):message.text=text;notification_time=2;return
	if text.is_empty() or (text==message.text and notification_time>0) or text in pending_notices:return
	if text.begins_with("Cannot collect") or text.begins_with("Catch lost"):
		message.text=text;notification_time=7
	# Docked, a message is the answer to whatever was just pressed, and the next
	# press deserves its own answer rather than a place in a seven-second queue.
	# In flight they arrive on their own and a queue is the only way to read them.
	elif notification_time>0 and not message.text.is_empty() and not session.docked:
		if pending_notices.size()>=6:pending_notices.pop_front()
		pending_notices.append(text)
	else:message.text=text;notification_time=7
	message.show()
	place_message()
func clear_notices() -> void:
	"""Nothing queued in flight is worth reading once the hatch is shut. Left
	alone, the prompt that refused a docking sits on screen while docked, saying
	to approach a station the submarine is already inside."""
	pending_notices.clear()
	message.text="";notification_time=0
func item_name(id: int, kind: String="goods") -> String:
	var key := "c:[[S" if kind=="goods" else "b:[[S"
	var table: Array = content.data.constants.e[key]
	return content.text(int(table[id][0])) if id<table.size() else str(id)
func item_description(id: int, kind: String="goods") -> String:
	var table: Array = content.data.constants.e["c:[[S" if kind=="goods" else ("d:[[S" if kind=="ships" else "b:[[S")]
	return content.text(int(table[id][1])) if id>=0 and id<table.size() and table[id].size()>1 else ""
func recipe_ingredients(recipe) -> String:
	var parts := PackedStringArray()
	for i in recipe.ingredients.size():
		var id: int = recipe.ingredients[i]
		var owned := 0
		for item in session.ship.cargo:
			if item.id==id: owned=item.owned; break
		parts.append("%s: %d / %d"%[item_name(id),owned,recipe.ingredient_counts[i]])
	return "Ingredients (in cargo / per unit)\n"+" · ".join(parts)
func flight_hint() -> String:
	var keys: Array = ["up","left","down","right"].map(func(action): return OS.get_keycode_string(key_bindings[action]))
	var steering: String = ("%s/%s steer · %s/%s strafe"%[keys[0],keys[2],keys[1],keys[3]]) if strafe_enabled() else "/".join(keys)+" steer"
	return "%s · %s fire · %s pilot · %s map · %s dock · Esc menu"%[steering,OS.get_keycode_string(key_bindings.fire),OS.get_keycode_string(key_bindings.autopilot),OS.get_keycode_string(key_bindings.map),OS.get_keycode_string(key_bindings.dock)]
func _process(delta: float) -> void:
	if session==null: return
	view.stabilize_touch_horizon=touch.enabled()
	if world.region!=null:world.region.player.touch_horizon_assist=touch.enabled()
	if not page.is_empty() and Input.mouse_mode!=Input.MOUSE_MODE_VISIBLE:release_flight_mouse()
	view.look_held=(free_look_held() and mouse_steering_enabled()) or (touch.enabled() and not touch.drag_anywhere and touch.orbit_held())
	watch_browser_capture()
	if autopilot_pressed_at>=0 and not autopilot_hold_used and Time.get_ticks_msec()-autopilot_pressed_at>=450:
		autopilot_hold_used=true;autonavigate_objective()
	# Placement keeps the controls on screen without letting them steer, so the
	# per-frame active state must not take them away from the editor drawing them.
	touch.set_active(page.is_empty() and not session.docked and not world.region.cinematic())
	if page=="layout": touch.refresh_visibility()
	dive_audio.set_context(page,session.docked)
	advance_transit_view(delta)
	if page=="departure":
		departure_elapsed+=minf(delta,.1)
		view.place_departure(clampf(departure_elapsed/3.2,0,1))
		if departure_elapsed>=3.2:finish_departure()
	if page=="opening":
		# The flight is not simulated under the shot: the berth's water moves
		# as it does from the dock, or failing that only the clocks run, so
		# the station's doors and rotor and the creatures' fins keep moving.
		if session.docked and world.ambient_rng!=null: world.advance_docked(minf(delta,.1))
		else:
			opening_fraction+=minf(delta,.1)*1000.0
			var opening_ms := int(opening_fraction);opening_fraction-=opening_ms
			world.region.elapsed_ms+=opening_ms
		opening.advance(minf(delta,.1))
	if page=="freeze": return
	if session.docked and page not in ["departure","transit","opening"]: world.advance_docked(minf(delta,.1))
	if page.is_empty() and not session.docked:
		world.advance(delta,flight_input(delta))
		if session.docked: finish_docking()
		else:
			collect_damage_bearings();check_hull_buzz()
			consume_events()
			if page.is_empty():
				flight_ms+=int(delta*1000)
				check_stream_proximity()
				if page.is_empty():check_flight_hints()
				if stream_exit_active:
					var exit_local: Vector3=stream_exit_frame.affine_inverse()*world.region.player.pose.godot_transform().origin
					if absf(exit_local.z)>view.player_model.solid_bounds().size.length():
						stream_exit_active=false;view.clear_player_clip()
	elif session.docked and page.is_empty(): finish_docking()
	elif session.docked and page=="station": check_station_progress()
	if world.region!=null:
		var r=world.region
		dock_caption.visible=session.docked and page!="dialogue" and not overlay.visible
		dock_caption.text=session.stations[session.station_id].name.to_upper()+" STATION\nBERTH SECURED  /  EXTERIOR VIEW"
		dock_prompt.visible=page.is_empty() and not session.docked and (r.station.can_dock(r.player.pose.origin) or Vector3(r.player.pose.origin[0],r.player.pose.origin[1],r.player.pose.origin[2]).length()<25000)
		dock_prompt.text=("[ %s ]  Dock at %s"%[control_name("dock"),session.stations[session.station_id].name]) if r.station.can_dock(r.player.pose.origin) else "[ %s ]  Dock · approach within 150 m"%control_name("dock")
		if r.success!=null or r.failure!=null:
			dock_prompt.text="Docking locked · encounter active  [ %s ] Mission waypoint"%control_name("autopilot")
		elif world.at_gate(0) and view.transit_progress<0 and not stream_exit_active and not (world.autopilot and world.gate_navigation):
			dock_prompt.visible=page.is_empty() and not session.docked and not r.cinematic()
			dock_prompt.text="[ %s ]  Enter the S.T.R.E.A.M."%control_name("dock")
		instruments.update(r,OS.get_keycode_string(key_bindings.boost))
		var flight_visible: bool=(page.is_empty() or page=="dialogue") and not r.cinematic() and not session.docked
		hazard_warning.update(r,flight_visible and page.is_empty(),not modern_graphics)
		pressure_material.set_shader_parameter("warning_color",hazard_warning.accent)
		classic_frame.visible=flight_visible and not touch.enabled();classic_frame.update(r.player,session.ship,world.speed,instruments.boost_state(r.player),OS.get_keycode_string(key_bindings.boost))
		instruments.visible=flight_visible
		instruments.modulate.a=1;condition.modulate.a=1;bank_label.modulate.a=1
		dashboard.visible=false
		hud.visible=false;hints.visible=flight_visible and gameplay_hints;objective_label.visible=flight_visible
		hints.text="LMB guns · RMB hook · %s fire · %s destination · %s chart"%[OS.get_keycode_string(key_bindings.fire),OS.get_keycode_string(key_bindings.autopilot),OS.get_keycode_string(key_bindings.map)]
		if touch.enabled():hints.text="Drag anywhere to look" if touch.drag_anywhere else ("Left thumb strafes" if strafe_enabled() else "Left thumb steers")+" · drag the screen to look"
		elif controller.device>=0:hints.text=("Left stick strafe · right stick turn" if strafe_enabled() else "Left stick steer")+" · D-pad speed · RT guns / LT hook · Y dock · View map · Start menu"
		condition.update(r.player.health,session.ship); condition.visible=flight_visible
		# The fitted weapons are the player's own knowledge; the HUD keeps quiet.
		bank_label.visible=false
		condition.info="%d/%dt     Cr %d     %s"%[session.ship.cargo_used,session.ship.capacity(),session.credits,session.stations[session.station_id].name]
		if touch.enabled():
			# The dock button is there while docking, or a manual gate entry, is.
			var dockable: bool=r.station.can_dock(r.player.pose.origin) or (world.at_gate(0) and view.transit_progress<0 and not stream_exit_active and not (world.autopilot and world.gate_navigation))
			var banks: Array=r.loadout.groups.filter(func(group):return not group.is_empty())
			touch.show_state(r.player.throttle_target/100.0,flight_visible and page.is_empty() and dockable,instruments.boost_state(r.player),world.autopilot,world.speed,
				banks.any(func(group):return group[0].fishing),banks.any(func(group):return not group[0].fishing))
		if r.loadout.selected>=0:
			var bank: Array = r.loadout.groups[r.loadout.selected]
			bank_label.text=("FISHING BANK · Harpoon" if bank[0].fishing else "COMBAT BANK · %d weapon%s"%[bank.size(),"" if bank.size()==1 else "s"])
			if r.loadout.groups.size()>1: bank_label.text+="\n%s · Switch to %s"%[OS.get_keycode_string(key_bindings.bank),"combat" if bank[0].fishing else "fishing"]
		else: bank_label.text="NO WEAPONS INSTALLED"
		pressure_material.set_shader_parameter("strength",instruments.pressure_strength if flight_visible else 0.0)
		hud.text="%d cr · %s"%[session.credits,session.stations[session.station_id].name]
		if hud.text!=previous_hud_text: previous_hud_text=hud.text; fit_hud()
		var objective=current_objective()
		var objective_text: String=objective_hud(objective)
		if r.cinematic(): objective_text=session.title(objective)+"\nFinal sequence · Esc pauses"
		if auto_fire: objective_text+="\nAUTO FIRE · "+OS.get_keycode_string(key_bindings.auto_fire)+" to stop"
		show_objective(objective_text,objective if not r.cinematic() else null)
		# The way out of a gate is a camera shot, not the chase view: its centre
		# is not where the guns point, so the reticle waits for the hand-back.
		crosshair.visible=view.camera_mode==0 and page.is_empty() and not r.cinematic() and not session.docked and not view.looking_around() and view.transit_progress<0 and view.departure_progress<0
		update_catch_feedback(r,flight_visible and page.is_empty())
		travel_status.text="AUTOPILOT  ·  %d× TIME  ·  [%s] CHANGE SPEED"%[world.speed,OS.get_keycode_string(key_bindings.time)]
		travel_status.visible=flight_visible and world.autopilot
		dashboard.throttle_keys=[OS.get_keycode_string(key_bindings.throttle_up),OS.get_keycode_string(key_bindings.throttle_down)]
		dashboard.objective_text=objective_label.get_parsed_text();dashboard.update(world)
		if not world.message.is_empty(): notice(world.message); world.message=""
		update_markers()
	notification_time-=delta
	if notification_time<=0:
		message.text=""
		if not pending_notices.is_empty():message.text=pending_notices.pop_front();notification_time=7;place_message()
	if message.text.begins_with("Time ·"):message.text="Time · %d×"%world.speed
	# The freeze is a clean look at the scene; notices wait until it ends.
	message.visible=not message.text.is_empty() and page!="freeze"
	if simulated_capture:
		capture_frames+=1
		if capture_frames==15: close_page()
		if capture_frames==90:
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(capture_path if not capture_path.is_empty() else "user://native-world.png"); print("GAMEPLAY_CAPTURE")
			# Let audio/render resources retire before ending the capture process.
			var tree:=get_tree();tree.create_timer(.2).timeout.connect(tree.quit);queue_free()
func collect_damage_bearings() -> void:
	"""Reads hits the simulation already reported. Each is shown once, and a new
	region (whose clock restarts) starts over rather than replaying old ones."""
	var region = world.region
	if region==null: return
	if region.elapsed_ms<damage_seen_ms: damage_seen_ms=-1;damage_feedback.clear()
	var here: Vector3 = world.render_pose(region.player).origin
	for event in region.visual_events:
		if event.kind!="impact" or not event.get("player",false): continue
		if int(event.time)<=damage_seen_ms: continue
		damage_feedback.record(camera,Library.point(event.position),here)
		damage_seen_ms=maxi(damage_seen_ms,int(event.time))
	damage_feedback.advance(get_process_delta_time())
func update_catch_feedback(region, show_feedback: bool) -> void:
	struggle.hide();catch_status.hide();catch_status.text=""
	for hook in region.fishing:
		if not hook.hooked or hook.target==null:continue
		if hook.towing:
			var distance: float=preload("res://native/simulation/fixed_math.gd").length_of(preload("res://native/simulation/fixed_math.gd").subtracted(region.player.pose.origin,hook.target.pose.origin))
			var seconds := maxf(0,distance-hook.capture_distance)/maxf(1,hook.tow_speed*1000)
			catch_status.text="REELING IN  ·  %.1f s TO COLLECTION"%seconds
		elif hook.target.is_creature:
			catch_status.text="CATCH  ·  %d s  ·  KEEP TARGET IN VIEW"%hook.target.countdown()
			struggle.value=clampf(100.0*(1.0-float(hook.target.struggle_remaining)/maxi(1,hook.target.struggle_total)),0,100)
			struggle.visible=show_feedback
		else:catch_status.text="HARPOON ATTACHED  ·  DISABLE TARGET TO RECOVER"
		catch_status.visible=show_feedback
		break
func strafe_enabled() -> bool:
	# Auto strafes wherever something else can turn the boat: a mouse, or the
	# right stick. A thumb on the touch stick has neither, so it keeps turning.
	return not touch.enabled() if strafe_mode==0 else strafe_mode==1
func flight_input(seconds: float=0.0) -> Dictionary:
	if not page.is_empty() or session.docked or world.region.cinematic(): return {}
	var horizontal := float(Input.is_physical_key_pressed(key_bindings.right))-int(Input.is_physical_key_pressed(key_bindings.left))
	var pitch := float(Input.is_physical_key_pressed(key_bindings.up))-int(Input.is_physical_key_pressed(key_bindings.down))
	var mouse_delta := mouse_steer; mouse_steer=Vector2.ZERO
	var throttle := int(Input.is_physical_key_pressed(key_bindings.throttle_up))-int(Input.is_physical_key_pressed(key_bindings.throttle_down))
	var fire := auto_fire or Input.is_physical_key_pressed(key_bindings.fire)
	var guns := not touch.enabled() and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var hook := not touch.enabled() and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	if suppress_fire_until_release:
		if not guns and not hook and not Input.is_physical_key_pressed(key_bindings.fire): suppress_fire_until_release=false
		else: guns=false; hook=false; fire=false
	guns=guns or weapon_presses.get("guns",false);hook=hook or weapon_presses.get("hook",false);fire=fire or weapon_presses.get("fire",false)
	weapon_presses.clear()
	var boost := Input.is_physical_key_pressed(key_bindings.boost)
	var pad:=controller.snapshot();var screen:=touch.snapshot()
	if touch.drag_anywhere: mouse_delta+=screen.look*touch_look_sensitivity*Vector2(1,1 if invert_mouse else -1)
	elif screen.look!=Vector2.ZERO:
		# With a stick to steer by, a drag swings the camera round the hull
		# instead of fighting the stick for the helm. A drag across the
		# screen's height turns the view half way round.
		var rate: float=PI/maxf(1.0,ui.size.y)*touch_look_sensitivity
		view.turn_look(-screen.look*rate*Vector2(1,-1 if invert_mouse else 1))
	# The vertical inversion covers the stick too, not only the drag.
	if invert_mouse: screen.pitch=-screen.pitch
	horizontal=clampf(horizontal+pad.yaw+screen.yaw,-1,1)
	var strafe := 0.0
	var yaw := clampf(pad.look.x,-1,1)
	if strafe_enabled(): strafe=horizontal
	else: yaw=clampf(yaw+horizontal,-1,1)
	if motion_steering:
		# Tilt turns; it never strafes. A device held level reports nothing, so
		# this sits alongside the stick rather than replacing it.
		var tilted := motion.look(seconds,motion_sensitivity)
		yaw=clampf(yaw+tilted.x,-1,1)
		pitch=clampf(pitch+tilted.y*(-1.0 if invert_motion_pitch else 1.0),-1,1)
	pitch=clampf(pitch+pad.pitch+screen.pitch+pad.look.y,-1,1)
	throttle=clampi(throttle+pad.throttle+screen.throttle,-1,1)
	fire=fire or pad.fire;guns=guns or pad.guns or screen.guns;hook=hook or pad.hook or screen.hook;boost=boost or pad.boost or screen.boost
	return {"yaw":yaw,"pitch":pitch,"strafe":strafe,"fire":fire,"guns":guns,"hook":hook,"boost":boost,"throttle":throttle,"mouse_x":mouse_delta.x,"mouse_y":mouse_delta.y,"aim_point":view.aim_point()}
func _unhandled_input(event: InputEvent) -> void:
	if page=="transit": return
	if page.is_empty() and event is InputEventMouseMotion and mouse_steering_enabled():
		if free_look_held(): view.turn_look(event.relative*.004)
		else: mouse_steer+=event.relative*mouse_sensitivity*Vector2(1,1 if invert_mouse else -1)
	if event is InputEventKey and event.physical_keycode==key_bindings.autopilot and binding_action.is_empty() and page.is_empty():
		if event.echo:return
		if event.pressed:
			autopilot_pressed_at=Time.get_ticks_msec();autopilot_hold_used=false
		elif autopilot_pressed_at>=0:
			var held := autopilot_hold_used
			autopilot_pressed_at=-1
			if not held:perform("autopilot")
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if not binding_action.is_empty():
			if event.physical_keycode!=KEY_ESCAPE:
				for action in key_bindings:
					if action!=binding_action and key_bindings[action]==event.physical_keycode: notice("That key is already assigned."); return
				key_bindings[binding_action]=event.physical_keycode; save_settings()
			binding_action=""; show_controls(); return
		if event.keycode==KEY_ESCAPE:
			if page in ["dialogue","freeze"]: return
			if page.is_empty(): show_pause()
			else: dock_back()
			return
		if event.keycode==KEY_F11: toggle_fullscreen()
		if event.keycode==KEY_F5: save_game()
		if not page.is_empty(): return
		for action in key_bindings:
			if event.physical_keycode==key_bindings[action]: perform(action)
	if event is InputEventJoypadButton and event.pressed and page.is_empty():
		if controller.ACTIONS.has(event.button_index):perform(controller.ACTIONS[event.button_index])
func touch_throttle(percent: int) -> void:
	if not page.is_empty() or world.region==null or session.docked: return
	if world.autopilot: world.cancel_autopilot()
	world.region.player.set_throttle(percent)
func touch_action(action: String) -> void:
	if action=="menu":show_pause()
	elif action=="full":toggle_fullscreen()
	elif page.is_empty():perform(action)
func browser_flag(expression: String) -> bool:
	if not OS.has_feature("web"): return false
	return bool(JavaScriptBridge.eval(expression,true))
func fullscreen_available() -> bool:
	# iPhone Safari ships no Fullscreen API, so the request would fail silently.
	if not OS.has_feature("web"): return true
	return browser_flag("!!(document.fullscreenEnabled||document.webkitFullscreenEnabled)")
func web_standalone() -> bool:
	"""True once the page runs from a home-screen icon, with no browser chrome."""
	return browser_flag("!!(navigator.standalone||matchMedia('(display-mode: standalone)').matches||matchMedia('(display-mode: fullscreen)').matches)")
func toggle_fullscreen() -> void:
	# A browser only grants fullscreen inside the gesture that asked for it.
	if not fullscreen_supported:
		if web_standalone(): notice("Already running without browser bars.")
		else: notice("This browser has no fullscreen control. Use the browser's Share menu, choose Add to Home Screen, and start the game from that icon to play without browser bars.")
		return
	var mode := DisplayServer.window_get_mode()
	var full: bool = mode==DisplayServer.WINDOW_MODE_FULLSCREEN or mode==DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
func controller_connection(device: int, connected: bool) -> void:
	if not connected and controller.device==device:
		controller.reset();controller.device=-1
		if session!=null and page.is_empty():show_pause()
func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT,NOTIFICATION_APPLICATION_PAUSED]:
		controller.reset();touch.reset();touch.release_contacts();mouse_steer=Vector2.ZERO
		if session!=null and page.is_empty():show_pause()
	if what==NOTIFICATION_WM_GO_BACK_REQUEST and session!=null:touch_action("menu")
func _input(event: InputEvent) -> void:
	var was_touch := touch.enabled()
	touch.update_input(event,controller.deadzone)
	view.stabilize_touch_horizon=touch.enabled()
	if world.region!=null:world.region.player.touch_horizon_assist=touch.enabled()
	if was_touch!=touch.enabled():
		mouse_steer=Vector2.ZERO
		if touch.enabled():release_flight_mouse()
		elif not OS.has_feature("web"):capture_flight_mouse()
		layout()
	if page in ["departure","opening"]:
		var skip: bool=(event is InputEventKey and event.pressed and event.keycode in [KEY_ENTER,KEY_SPACE,KEY_ESCAPE]) or (event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT) or (event is InputEventJoypadButton and event.pressed and event.button_index in [JOY_BUTTON_A,JOY_BUTTON_B,JOY_BUTTON_START]) or (event is InputEventScreenTouch and event.pressed)
		if skip:
			if page=="departure":finish_departure()
			else:opening.skip()
		get_viewport().set_input_as_handled();return
	controller.accept(event)
	if event is InputEventMouseButton and not event.pressed:
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and not Input.is_physical_key_pressed(key_bindings.fire):suppress_fire_until_release=false
	if page.is_empty() and not suppress_fire_until_release:
		if event is InputEventMouseButton and event.pressed and not touch.enabled():
			if event.button_index==MOUSE_BUTTON_LEFT:weapon_presses.guns=true
			elif event.button_index==MOUSE_BUTTON_RIGHT:weapon_presses.hook=true
		elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode==key_bindings.fire:weapon_presses.fire=true
	if touch.handle(event):get_viewport().set_input_as_handled();return
	if page=="transit":return
	if event is InputEventJoypadButton and event.pressed and event.button_index in [JOY_BUTTON_B,JOY_BUTTON_START]:
		if page=="freeze":return
		if page.is_empty():show_pause()
		elif page not in ["dialogue","failure"]:dock_back()
		get_viewport().set_input_as_handled()
	# Pointer lock must originate in a browser user gesture, after content/menu loading.
	if OS.has_feature("web") and page.is_empty() and event is InputEventMouseButton and event.pressed and not touch.enabled() and not mouse_is_captured():
		capture_flight_mouse()
		# Pointer lock and the first weapon press can share the same gesture.
		# A refused lock must not swallow subsequent hook attempts either.
func find_option(node: Node, key: String) -> Button:
	if node is Button and node.get_meta("option","")==key and node.is_visible_in_tree() and not node.disabled: return node
	for child in node.get_children():
		var found := find_option(child,key)
		if found!=null: return found
	return null
func focus_page() -> void:
	if not overlay.visible or not is_instance_valid(column):return
	if not focus_option.is_empty():
		var wanted := find_option(column,focus_option)
		focus_option=""
		if wanted!=null: wanted.grab_focus(); return
	if page=="market":
		var selected:=column.find_child("Stock_"+str(market_selection),true,false) as Button
		if selected!=null and selected.is_visible_in_tree():selected.grab_focus();return
	var pending: Array[Node]=[column]
	while not pending.is_empty():
		var node: Node=pending.pop_front()
		if node is Button and node.is_visible_in_tree() and not node.disabled:node.grab_focus();return
		pending.append_array(node.get_children())
func perform(action: String) -> void:
	if action in ["auto_fire","camera","bank","autopilot","time","lights"]: dive_audio.cue("beep")
	match action:
		"auto_fire":
			auto_fire=not auto_fire
			if auto_fire: world.cancel_autopilot("Auto fire enabled")
			else: notice("Auto fire off")
		"throttle_up","throttle_down":
			if world.autopilot:world.cancel_autopilot()
			world.region.player.set_throttle(world.region.player.throttle_target+(25 if action=="throttle_up" else -25))
		"camera":
			view.camera_mode=(view.camera_mode+1)%4; save_settings(); notice("Camera · "+view.CAMERA_NAMES[view.camera_mode])
		"bank": world.region.loadout.cycle()
		"dock":
			if world.at_gate(0):
				show_stream_menu()
			elif world.dock(): finish_docking()
		"map": show_map()
		"autopilot":
			auto_fire=false
			show_destinations()
		"time": world.cycle_speed()
		"lights":
			if modern_graphics:graphics.headlights=not graphics.headlights;abyss.set_headlights(graphics.headlights);save_settings()
			else:notice("Headlights are available in New graphics mode.")
func control_name(action: String) -> String:
	"""What the player presses for action with the controls in use: the touch
	button's caption, the pad button or the bound key."""
	if touch.enabled():return touch.LABELS.get(action,action.to_upper())
	if controller.device>=0:
		for button in controller.ACTIONS:
			if controller.ACTIONS[button]==action:return PAD_NAMES.get(button,"Pad %d"%button)
	return OS.get_keycode_string(key_bindings[action])
const PAD_NAMES := {JOY_BUTTON_X:"X",JOY_BUTTON_Y:"Y",JOY_BUTTON_LEFT_SHOULDER:"LB",JOY_BUTTON_RIGHT_SHOULDER:"RB",JOY_BUTTON_BACK:"View",JOY_BUTTON_DPAD_LEFT:"D-pad left",JOY_BUTTON_DPAD_RIGHT:"D-pad right"}
func finish_docking() -> void:
	clear_notices()
	show_station()
	save_game(false)
func show_pause() -> void:
	open_page("Dive paused","pause")
	iconic(button("Resume",close_page),"resume")
	if touch.enabled():
		# The touch overlay keeps only what a dive needs to hand; the view and
		# fullscreen switches live here.
		iconic(option("Camera · "+view.CAMERA_NAMES[view.camera_mode],"camera",func():perform("camera");show_pause()),"camera")
		if touch.show_fullscreen: iconic(button("Fullscreen / windowed",toggle_fullscreen),"fullscreen")
	iconic(button("Overworld map",show_map),"map")
	iconic(button("Mission journal",show_journal),"journal")
	iconic(button("Ship and cargo",show_ship_status),"cargo")
	iconic(button("Profile and medals",show_profile),"person")
	var freeze := iconic(button("Action freeze",show_action_freeze),"freeze")
	freeze.disabled=session.docked or world.region==null
	freeze.tooltip_text="Hold the dive still and look around it." if not freeze.disabled else "Available while diving."
	iconic(button("Controls",show_controls),"controls")
	iconic(button("Graphics",show_graphics),"graphics")
	iconic(button("World",show_world_settings),"world")
	iconic(button("Help",show_help),"help")
	iconic(button("Transfer expedition",show_transfer),"transfer")
	iconic(button("Reload station checkpoint",func(): confirm("Reload checkpoint",
		"Return to your last saved station? Everything since that checkpoint is lost.",
		"Reload checkpoint",reload_game,show_pause)),"reload")
	iconic(button("Return to main menu",func(): confirm("Main menu",
		("Your expedition is saved at this station first." if session.docked
			else "You are away from a station, so this dive since your last checkpoint is lost."),
		"Return to main menu",return_to_menu,show_pause)),"exit")
func show_journal() -> void:
	open_page("Mission journal","journal")
	var info=preload("res://native/presentation/mission_info.gd")
	for mission in [session.campaign.primary,session.campaign.secondary]:
		if mission.kind<0: continue
		var card := information_card(session.title(mission))
		var progress: String = info.progress(session,mission)
		var description: String = session.description(mission)
		# Source counter descriptions end in an empty heading; the native
		# progress line provides both its label and the current/target counts.
		if mission.kind in [15,16,18,19,21] and description.strip_edges().ends_with(":") and description.contains("\n\n"):
			description=description.substr(0,description.rfind("\n\n"))
		label(description,16,card)
		target_line(mission,card)
		if not progress.is_empty(): label(progress,16,card).modulate=Color("98d4c6")
		var requirements: String = info.requirements(mission)
		if not requirements.is_empty(): label(requirements,16,card)
		if not mission.destination_name.is_empty():
			label("Destination: "+mission.destination_name,16,card)
			if mission.destination>=0 and mission.destination<session.stations.size() and not mission.completed and not mission.failed:
				var arrived: bool=session.docked and mission.destination==session.station_id
				var navigate := button("At destination" if arrived else ("Depart & autonavigate" if session.docked else "Autonavigate to destination"),func():autonavigate_from_journal(mission.destination),card)
				navigate.disabled=arrived;navigate.set_meta("journal_destination",mission.destination)
		if mission.reward>0: label("Reward: %d cr"%mission.reward,16,card)
		var deadline: String = info.deadline(mission)
		if not deadline.is_empty(): label(deadline,16,card)
		if mission==session.campaign.secondary: button("Abandon contract",func(): confirm("Abandon contract",
			"Give up \"%s\"? The deposit is not returned." % session.title(mission),
			"Abandon contract",func(): session.abandon_contract(); show_journal(),show_journal),card)
	label("Rank %d  ·  Stations discovered %d / 200  ·  Catches %d  ·  Enemies defeated %d"%[session.counters.k,session.counters.m,session.counters.h,session.counters.f],16)
	back_row(dock_back if session.docked else show_pause)
func target_line(mission, parent: Node) -> void:
	"""Names the creature a job is about, with its picture, since the job's own
	text only says "fishes"."""
	var info=preload("res://native/presentation/mission_info.gd")
	var text: String=info.target(session,mission)
	if text.is_empty():return
	var line := HBoxContainer.new();line.add_theme_constant_override("separation",8);parent.add_child(line)
	var icon := TextureRect.new();icon.texture=imported_art.item(info.target_species(mission));icon.custom_minimum_size=Vector2(34,28)
	icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;line.add_child(icon)
	label(text,15,line).add_theme_color_override("font_color",colours().good)
func autonavigate_from_journal(destination: int) -> void:
	# Validate before leaving the berth; a denied route keeps the journal open.
	var denial: String=world.route_denial(destination)
	if not denial.is_empty():notice(denial);return
	if session.docked and destination==session.station_id:notice("Already docked at the destination.");return
	if ask_outside_safety(destination,func():autonavigate_from_journal(destination),show_journal):return
	if session.docked:
		depart()
		if session.docked:return
		if page=="departure":departure_destination=destination;return
	if world.route_to(destination):
		auto_fire=false
		if page not in ["dialogue","departure"]:close_page()
	else:notice(world.message)
## Where Back leaves the ship page for: the hub that opened it.
var ship_status_back := Callable()
func show_ship_status(back: Callable=Callable()) -> void:
	ship_status_back=back
	open_page("Ship and cargo","ship_status")
	var ship=session.ship
	var palette := colours()
	var body := split_row(column,20)
	# The vessel: its picture, the three protections and the limits.
	var vessel := VBoxContainer.new();vessel.add_theme_constant_override("separation",14);glass(body,false,16).add_child(vessel)
	vessel.get_parent().size_flags_stretch_ratio=1.0
	var identity:=HBoxContainer.new();identity.name="CurrentShip";identity.add_theme_constant_override("separation",18);vessel.add_child(identity)
	art_image(imported_art.item(ship.id,"ships"),identity,112)
	var naming := VBoxContainer.new();naming.size_flags_horizontal=Control.SIZE_EXPAND_FILL;naming.alignment=BoxContainer.ALIGNMENT_CENTER;identity.add_child(naming)
	var called := label(content.ship_name(ship.id),30,naming);called.add_theme_color_override("font_color",palette.text)
	caption("Your vessel",11,naming,4)
	if ui.size.y>=700 and ui.size.x>=900:
		var preview=preload("res://native/presentation/ship_preview.gd").new()
		identity.add_child(preview);preview.configure(content,ship.id,modern_graphics,view.library)
		preview.custom_minimum_size=Vector2(240,170)
	var protections := HBoxContainer.new();protections.add_theme_constant_override("separation",10);vessel.add_child(protections)
	for entry in [["hull","Hull",ship.hull],["shield","Shield",ship.shield],["armor","Armor",ship.armor]]:
		figure_tile(entry[0],entry[1],str(entry[2]),protections)
	var used: int=ship.equipment.filter(func(item):return item!=null).size()
	var rows: Array=[["shield","Protection limits","%d – %d"%[ship.minimum_depth,ship.maximum_depth]],["cargo","Cargo capacity","%d / %d t"%[ship.cargo_used,ship.capacity()]],["grid","Equipment slots","%d / %d"%[used,ship.slots]]]
	if not session.docked and world.region!=null:
		var health=world.region.player.health
		rows.append(["hull","Current condition","Hull %d · Shield %d · Armor %d"%[health.hull,health.shield,health.armor]])
	figure_rows(rows,vessel)
	# What it carries and what is fitted.
	var holds := VBoxContainer.new();holds.size_flags_horizontal=Control.SIZE_EXPAND_FILL;holds.add_theme_constant_override("separation",14);body.add_child(holds)
	var manifest := titled_glass("cargo","Cargo manifest",holds)
	if ship.cargo.is_empty():
		var empty := label("Cargo hold empty",16,manifest);empty.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;empty.add_theme_color_override("font_color",palette.dim)
	for item in ship.cargo:
		compact_manifest(imported_art.item(item.id),"%s · %d units"%[item_name(item.id),item.owned],"Cargo",item_description(item.id),manifest)
	var systems := titled_glass("system","Installed systems",holds)
	if used==0: label("No equipment installed.",16,systems).add_theme_color_override("font_color",palette.dim)
	for item in ship.equipment:
		if item!=null:compact_manifest(imported_art.item(item.id,"equipment"),item_name(item.id,"equipment"),EquipmentInfo.stats(item),item_description(item.id,"equipment"),systems)
	back_row(ship_status_back if ship_status_back.is_valid() else show_station_status if session.docked else show_pause)
func split_row(parent: Node, gap: int) -> BoxContainer:
	"""Side by side on a wide screen, one above the other on a narrow one."""
	var row: BoxContainer=HBoxContainer.new() if ui.size.x>=900 else VBoxContainer.new()
	row.add_theme_constant_override("separation",gap);row.size_flags_horizontal=Control.SIZE_EXPAND_FILL;parent.add_child(row);return row
func titled_glass(icon: String, title: String, parent: Node) -> VBoxContainer:
	var body := VBoxContainer.new();body.add_theme_constant_override("separation",8);glass(parent,false,14).add_child(body)
	var top := HBoxContainer.new();top.add_theme_constant_override("separation",12);body.add_child(top)
	line_icon(icon,28,top);caption(title,15,top,4).add_theme_color_override("font_color",colours().text)
	var rule := ColorRect.new();rule.color=Color(colours().edge,.7);rule.custom_minimum_size.y=1;body.add_child(rule)
	return body
func figure_tile(icon: String, title: String, value: String, parent: Node) -> void:
	var cell := HBoxContainer.new();cell.size_flags_horizontal=Control.SIZE_EXPAND_FILL;cell.add_theme_constant_override("separation",10);parent.add_child(cell)
	line_icon(icon,34,cell)
	var words := VBoxContainer.new();words.add_theme_constant_override("separation",0);cell.add_child(words)
	caption(title,11,words,3)
	var figure := label(value,24,words);figure.add_theme_color_override("font_color",colours().text);figure.autowrap_mode=TextServer.AUTOWRAP_OFF
func figure_rows(rows: Array, parent: Node) -> GridContainer:
	"""Name and value pairs as a two-column table, with an icon when given."""
	var grid := GridContainer.new();grid.columns=2;grid.add_theme_constant_override("h_separation",24);grid.add_theme_constant_override("v_separation",8);parent.add_child(grid)
	for entry in rows:
		var name_cell := HBoxContainer.new();name_cell.add_theme_constant_override("separation",10);grid.add_child(name_cell)
		if not str(entry[0]).is_empty(): line_icon(entry[0],22,name_cell)
		var name_label := label(entry[1],15,name_cell);name_label.add_theme_color_override("font_color",colours().dim);name_label.autowrap_mode=TextServer.AUTOWRAP_OFF
		var value := label(entry[2],16,grid);value.add_theme_color_override("font_color",entry[3] if entry.size()>3 else colours().text)
	return grid
func compact_manifest(texture: Texture2D, title: String, stats: String, description: String, parent: Node=null) -> void:
	var row:=HBoxContainer.new();row.add_theme_constant_override("separation",14);(parent if parent!=null else column).add_child(row);row.tooltip_text=description
	var icon:=TextureRect.new();icon.texture=texture;icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;icon.custom_minimum_size=Vector2(52,44);icon.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;row.add_child(icon)
	var words:=VBoxContainer.new();words.size_flags_horizontal=Control.SIZE_EXPAND_FILL;words.add_theme_constant_override("separation",1);row.add_child(words)
	label(title,17,words).add_theme_color_override("font_color",colours().text);label(stats,13,words).add_theme_color_override("font_color",colours().dim)
var medal_selection := 0
var medal_page := 0
const TIER_NAMES := ["Locked","Gold","Silver","Bronze"]
const TIER_COLOURS := [Color("85939b"),Color("e7c77f"),Color("b6d0de"),Color("ce9b7b")]
func show_profile(medal_view: bool=false) -> void:
	open_page("Medals" if medal_view else "Player profile","profile","Honours for your work below the surface" if medal_view else "Pilot record")
	var palette := colours()
	var top := HBoxContainer.new();top.add_theme_constant_override("separation",12);column.add_child(top)
	var rank := glass(top,false,10);rank.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var rank_row := HBoxContainer.new();rank_row.add_theme_constant_override("separation",12);rank.add_child(rank_row)
	line_icon("person",30,rank_row)
	var pilot := label(session.name+" · Rank %d"%session.counters.k,22,rank_row);pilot.add_theme_color_override("font_color",palette.text)
	pilot.autowrap_mode=TextServer.AUTOWRAP_OFF;pilot.clip_text=true;pilot.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	var owned: int = session.medals.levels.filter(func(tier): return tier>0).size()
	if ui.size.x>=900: caption("Medals %d / 24"%owned,12,rank_row,3).size_flags_horizontal=Control.SIZE_SHRINK_END
	var swap := iconic(button("View statistics" if medal_view else "View medals",func(): show_profile(not medal_view),top),"status" if medal_view else "medal",24)
	swap.size_flags_horizontal=Control.SIZE_SHRINK_END;swap.custom_minimum_size.x=230 if ui.size.x>=900 else 0
	if not medal_view:
		var record := titled_glass("status","Expedition record",column)
		var tiles := GridContainer.new();tiles.columns=4 if ui.size.x>=1100 else 3 if ui.size.x>=800 else 2
		tiles.add_theme_constant_override("h_separation",10);tiles.add_theme_constant_override("v_separation",10);record.add_child(tiles)
		var entries: Array=[["Time underway","%d h %02d min"%[session.elapsed_ms/3600000,(session.elapsed_ms/60000)%60]],["Credits","%d"%session.credits],["Depth record","%d–%d"%[session.counters.u,session.counters.t]]]
		for entry in [["Enemies defeated","f"],["Pirates defeated","o"],["Creatures caught","h"],["Fish killed","g"],["Catches released","i"],["Dead fish recovered (t)","p"],["Crates recovered","r"],["Stations discovered","m"],["Regions entered","q"],["Goods produced","n"],["Contracts completed","j"],["New equipment purchased","s"]]:
			entries.append([entry[0],str(session.counters[entry[1]])])
		for entry in entries:
			var cell := glass(tiles,false,8)
			var words := VBoxContainer.new();words.add_theme_constant_override("separation",2);cell.add_child(words)
			label(entry[1],22,words).add_theme_color_override("font_color",palette.text)
			var name_label := label(entry[0],13,words);name_label.add_theme_color_override("font_color",palette.dim)
			# Kept as plain text for readers and tests alike.
			name_label.set_meta("statistic","%s: %s"%entry)
	else:
		if session.medals.complete_set(): label("Complete medal collection",16).add_theme_color_override("font_color",palette.value)
		if session.medals.gold_set(): label("All medals at their highest tier",16).add_theme_color_override("font_color",palette.value)
		var count: int=session.medals.levels.size()
		medal_selection=clampi(medal_selection,0,count-1)
		var body := split_row(column,18)
		var list := VBoxContainer.new();list.name="MedalRows";list.size_flags_horizontal=Control.SIZE_EXPAND_FILL;list.add_theme_constant_override("separation",6);body.add_child(list)
		var row_height: int=64 if touch.enabled() else 58
		var page_size: int=clampi(int((ui.size.y-(300 if ui.size.x>=900 else 760))/(row_height+6)),3,9)
		medal_page=clampi(medal_page,0,(count-1)/page_size)
		for id in range(medal_page*page_size,mini(count,(medal_page+1)*page_size)):
			var tier: int=session.medals.levels[id]
			var cells := stock_row("Medal_%d"%id,id==medal_selection,row_height,func():medal_selection=id;focus_option="medal_%d"%id;show_profile(true),list)
			(cells.get_parent() as Button).set_meta("option","medal_%d"%id)
			medal_icon(tier,cells,40)
			var words := VBoxContainer.new();words.size_flags_horizontal=Control.SIZE_EXPAND_FILL;words.add_theme_constant_override("separation",0);words.mouse_filter=Control.MOUSE_FILTER_IGNORE;cells.add_child(words)
			label(session.text(int(content.data.constants.e["a:[[S"][id][0])),17,words).add_theme_color_override("font_color",palette.text if tier>0 else palette.dim)
			var badge := label(TIER_NAMES[tier],13,words);badge.add_theme_color_override("font_color",TIER_COLOURS[tier])
			if tier==0: line_icon("lock",22,cells,palette.faint)
		pager(medal_page,ceili(float(count)/page_size),func(to):medal_page=to;medal_selection=to*page_size;show_profile(true),list)
		var tier: int=session.medals.levels[medal_selection]
		var detail := VBoxContainer.new();detail.name="SelectedMedal";detail.add_theme_constant_override("separation",10)
		var frame := glass(body,true,16);frame.size_flags_horizontal=Control.SIZE_EXPAND_FILL;frame.add_child(detail)
		var title := caption(session.text(int(content.data.constants.e["a:[[S"][medal_selection][0])),22,detail,5);title.add_theme_color_override("font_color",palette.text)
		label(TIER_NAMES[tier],17,detail).add_theme_color_override("font_color",TIER_COLOURS[tier])
		var stage := CenterContainer.new();stage.custom_minimum_size.y=150 if ui.size.y>=700 else 100;detail.add_child(stage)
		medal_icon(tier,stage,int(stage.custom_minimum_size.y)-10)
		var rule := ColorRect.new();rule.color=Color(palette.edge,.7);rule.custom_minimum_size.y=1;detail.add_child(rule)
		# A medal not yet won shows what its first tier asks for.
		label(medal_text(medal_selection,tier) if tier>0 else "Bronze · "+medal_text(medal_selection,3),16,detail).add_theme_color_override("font_color",palette.text)
		figure_rows([["","Status","Awarded" if tier>0 else "Not yet awarded",palette.value if tier>0 else palette.dim],["","Tier",TIER_NAMES[tier],TIER_COLOURS[tier]]],detail)
	back_row(dock_back if session.docked else show_pause)
func stock_row(id: String, selected: bool, height: int, action: Callable, parent: Node) -> HBoxContainer:
	"""A list row that selects its entry for the detail beside the list; the
	chosen one keeps a lit edge while focus moves on."""
	var control := button("",action,parent)
	control.name=id;control.custom_minimum_size=Vector2(0,height)
	if selected:
		var lit := StationTheme.button_state(golden(),"focus");lit.border_width_left=4
		control.add_theme_stylebox_override("normal",lit)
	var cells := HBoxContainer.new();control.add_child(cells);cells.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cells.offset_left=12;cells.offset_right=-14;cells.offset_top=5;cells.offset_bottom=-5;cells.add_theme_constant_override("separation",14);cells.mouse_filter=Control.MOUSE_FILTER_IGNORE
	return cells
func pager(index: int, pages: int, turn: Callable, parent: Node) -> void:
	if pages<=1: return
	var bar := HBoxContainer.new();bar.add_theme_constant_override("separation",10);parent.add_child(bar)
	var previous := iconic(button("PREVIOUS",func():turn.call(index-1),bar),"back",16);previous.disabled=index==0
	var number := caption("%02d / %02d"%[index+1,pages],14,bar,2);number.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;number.add_theme_color_override("font_color",colours().text)
	var following := button("NEXT",func():turn.call(index+1),bar);following.disabled=index+1>=pages;following.alignment=HORIZONTAL_ALIGNMENT_CENTER
	for node in [previous,following]: node.add_theme_font_override("font",heading_font(3))
func medal_icon(tier: int, parent: Node, height: int=32) -> TextureRect:
	"""The original's medal sprite: medal_1 to medal_3 for gold, silver and
	bronze (n, y), and for one not yet won the empty frame of the station's
	holder, medal_5 at a colonist station and medal_7 at a rebel one."""
	var sprite: int=tier if tier>0 else (5 if session.is_colonist_station() else 7)
	var icon := TextureRect.new();icon.texture=imported_art.image("medal_%d"%sprite)
	icon.custom_minimum_size=Vector2(roundi(height*13.0/16.0),height);icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;icon.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	icon.size_flags_vertical=Control.SIZE_SHRINK_CENTER;parent.add_child(icon)
	return icon
func medal_text(id: int, tier: int) -> String:
	"""The medal's description with the figure its tier asks for (y.a)."""
	return session.text(int(content.data.constants.e["a:[[S"][id][1]),str(int(content.data.constants.f["a:[[I"][id][tier-1])))
func show_new_medal(queue: Array, index: int) -> void:
	"""ch.e/y: on docking, every medal won or bettered since the last dock is
	shown in turn under "New Medal!" (text 163): its sprite, name and what it
	was given for."""
	if index>=queue.size():show_station();return
	var entry: Dictionary=queue[index]
	var id: int=int(entry.id);var tier: int=int(entry.tier)
	open_page(session.text(163),"medal")
	page_back=func():show_new_medal(queue,index+1)
	dive_audio.cue("message")
	var row := HBoxContainer.new();row.add_theme_constant_override("separation",16);column.add_child(row)
	medal_icon(tier,row,64)
	var words := VBoxContainer.new();words.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(words)
	label(session.text(int(content.data.constants.e["a:[[S"][id][0])),22,words).modulate=Color("eef6ff")
	var badge: Label=label(["","Gold","Silver","Bronze"][clampi(tier,0,3)],16,words)
	badge.modulate=[Color("85939b"),Color("e7c77f"),Color("b6d0de"),Color("ce9b7b")][clampi(tier,0,3)]
	if tier>0:label(medal_text(id,tier),16)
	if queue.size()>1:label("%d / %d"%[index+1,queue.size()],12).modulate=Color("7f96ad")
	var ok := button("OK",func():show_new_medal(queue,index+1))
	ok.custom_minimum_size.y=56 if touch.enabled() else 44
	focus_if_visible.call_deferred(ok)
func section_row(text: String, key: String, act: Callable) -> Button:
	"""A row that opens another page, carrying the key that page hands focus back
	to. `option` cannot serve here: that one is for rows that rebuild their own."""
	var node := button(text,act)
	node.set_meta("option",key)
	return node
func show_controls(section: String="") -> void:
	"""One page per kind of control. All of it on a single page was longer than a
	pad could comfortably walk, and the sliders sat at the bottom of it. Leaving a
	section puts focus back on the row that opened it, so a pass through several
	settings never restarts at the top."""
	controls_section=section
	open_page({"steering":"Steering","gamepad":"Gamepad","touch":"Touch controls",
		"bindings":"Key bindings","reference":"Control reference"}.get(section,"Controls"),"controls")
	match section:
		"steering": controls_steering()
		"gamepad": controls_gamepad()
		"touch": controls_touch()
		"bindings": controls_bindings()
		"reference": controls_reference()
		_:
			option("Gameplay tips & control hints · "+("On" if gameplay_hints else "Off"),"hints",func():gameplay_hints=not gameplay_hints;save_settings();show_controls(""))
			section_row("Steering · mouse, keys and stick","steering",func():show_controls("steering"))
			section_row("Gamepad · "+("connected" if controller.device>=0 else "none connected"),"gamepad",func():show_controls("gamepad"))
			section_row("Touch controls","touch",func():show_controls("touch"))
			section_row("Key bindings","bindings",func():show_controls("bindings"))
			section_row("Control reference","reference",func():show_controls("reference"))
	if section.is_empty(): back_row(show_system if session.docked else show_pause)
	else: back_row(func():focus_option=section;show_controls(""))
func show_help(topic: int=-1) -> void:
	"""The phone game's Help: Instructions, its ten topics of imported text,
	Controls, and the Credits."""
	var guide=preload("res://native/presentation/instructions.gd")
	var topics: Array=guide.topics(content)
	if topic>=0 and topic<topics.size():
		open_page(topics[topic].title,"help")
		var card := information_card(session.text(18))
		label(topics[topic].text,15,card)
		if topic==0:label(guide.key_note(),13,card)
		back_row(func():focus_option="topic%d"%topic;show_help())
		return
	open_page(session.text(4),"help")
	label(session.text(18),17)
	for index in topics.size():
		option(topics[index].title,"topic%d"%index,func():show_help(index))
	if topics.is_empty():label("The instructions come with the imported game text.",15)
	button(session.text(19),show_controls)
	button(session.text(20),func():show_dialogue([{"speaker":session.text(20),"text":session.text(26)+"\n\n"+session.text(28)+"\n\n"+session.text(25)}],show_help))
	back_row(show_system if session.docked else show_pause)
func slider_setting(caption: String, low: float, high: float, value: float, act: Callable) -> HSlider:
	label(caption,16)
	var node := HSlider.new()
	node.min_value=low;node.max_value=high;node.step=.1;node.value=value;node.custom_minimum_size.y=44
	column.add_child(node)
	node.value_changed.connect(act)
	return node
func controls_steering() -> void:
	option("Helm response · "+("Smooth" if world.smooth_steering else "Direct"),"smooth_steering",func():world.set_smooth_steering(not world.smooth_steering);save_settings();show_controls("steering"))
	label("Smooth eases the submarine into and out of every turn and holds the mouse to three times the hull's own steering rate, so steering upgrades count. Direct is the original's instant response, with the mouse turning one step per pixel.",16)
	option("Left/right keys and stick · "+["Auto · strafe unless on touch","Always strafe","Always turn"][strafe_mode],"strafe",func():strafe_mode=(strafe_mode+1)%3;save_settings();show_controls("steering"))
	slider_setting("Mouse sensitivity",0.2,2.0,mouse_sensitivity,func(value): mouse_sensitivity=value; save_settings())
	option("Invert vertical mouse and touch · "+("On" if invert_mouse else "Off"),"invert_mouse",func(): invert_mouse=not invert_mouse; save_settings(); show_controls("steering"))
	label("Tilt steering uses the device's motion sensor. Desktop machines have none.",16)
	option("Steer by tilting · "+("On" if motion_steering else "Off"),"motion",func():
		motion_steering=not motion_steering
		# A browser only grants the sensor from inside a user gesture, and this
		# press is one. Asking at startup is refused before the player sees it.
		if motion_steering: motion.enable()
		save_settings();show_controls("steering"))
	if motion_steering:
		var tilt:=slider_setting("Tilt sensitivity",0.0,1.0,motion_sensitivity,func(value): motion_sensitivity=value; save_settings())
		tilt.step=.05
		option("Invert tilt pitch · "+("On" if invert_motion_pitch else "Off"),"motion_invert",func(): invert_motion_pitch=not invert_motion_pitch; save_settings(); show_controls("steering"))
		option("Centre tilt on how it is held now","motion_centre",func():
			if motion.calibrate(): notice("Tilt centred")
			show_controls("steering"))
func controls_gamepad() -> void:
	option("Invert gamepad pitch · "+("On" if controller.invert else "Off"),"invert_pad",func():controller.invert=not controller.invert;save_settings();show_controls("gamepad"))
	option("%s · %s"%[session.text(10),session.text(14 if vibration else 15)],"vibration",func():
		vibration=not vibration;save_settings()
		if vibration:buzz(150)
		show_controls("gamepad"))
	var deadzone:=slider_setting("Gamepad deadzone",.05,.45,controller.deadzone,func(value):controller.deadzone=value;save_settings())
	deadzone.step=.01
	label("Raise the deadzone if the submarine drifts with the sticks at rest.",16)
func controls_touch() -> void:
	option("Touch controls · "+["Auto","On","Off"][touch.mode],"touch_mode",func():touch.mode=(touch.mode+1)%3;update_render_resolution();save_settings();show_controls("touch"))
	var placement := button("Adjust touch control placement…",show_layout_editor)
	placement.disabled=not touch.enabled()
	placement.tooltip_text="Move and resize the on-screen controls." if touch.enabled() else "Turn touch controls on first."
	option("Touch look area · "+("Whole screen" if touch.drag_anywhere else "Outside analog area"),"touch_area",func():touch.drag_anywhere=not touch.drag_anywhere;touch.arrange();save_settings();show_controls("touch"))
	option("Steering stick · "+("Fixed in place" if touch.fixed_stick else "Moves to thumb"),"touch_stick",func():touch.fixed_stick=not touch.fixed_stick;touch.reset();save_settings();show_controls("touch"))
	option("Invert vertical steering · "+("On" if invert_mouse else "Off"),"touch_invert",func(): invert_mouse=not invert_mouse; save_settings(); show_controls("touch"))
	slider_setting("Touch look sensitivity",0.2,2.0,touch_look_sensitivity,func(value): touch_look_sensitivity=value; save_settings())
	label("Outside analog area: the left thumb steers with a stick and a drag elsewhere swings the camera round the submarine. The camera comes back when the stick is touched again or after a few seconds. Whole screen: a drag anywhere steers, using Touch look sensitivity. Hold guns/hook/boost and slide the throttle arc; tap the top row for travel and menus.",16)
func controls_bindings() -> void:
	var travel_keys:=HBoxContainer.new();column.add_child(travel_keys)
	for action in ["autopilot","time"]:button(("Autopilot (tap / hold)" if action=="autopilot" else "Time acceleration")+" · "+OS.get_keycode_string(key_bindings[action]),func():binding_action=action;notice("Press a key for "+action),travel_keys)
	label("Select an action to rebind. Esc cancels.",16)
	var bindings := GridContainer.new();bindings.columns=2;bindings.add_theme_constant_override("h_separation",24);column.add_child(bindings)
	for action in key_bindings: button(action.capitalize()+"    "+OS.get_keycode_string(key_bindings[action]),func(): binding_action=action; notice("Press a key for "+action),bindings)
func controls_reference() -> void:
	label("Mouse turns · Left-click guns · Right-click harpoon · W/S throttle",16)
	label("Mouse pitch and yaw allow full loops; your camera follows the submarine’s orientation.",16)
	label("Gamepad: right stick turns · left stick strafes or turns · D-pad up/down throttle · A selected weapon · RT guns / LT hook · L3 boost",16)
	label("X bank · Y dock · LB route · RB time · View map · D-pad left camera / right lights · Start/B menu",16)
func show_action_freeze() -> void:
	"""Holds the dive still and hands the camera over. Nothing is simulated or
	saved while frozen, so resuming continues the same dive untouched."""
	if session.docked or world.region==null or is_instance_valid(freeze_view): return
	page="freeze"
	overlay.hide()
	touch.set_active(false)
	controller.blocked=true
	release_flight_mouse()
	touch_scroll.scroll=null;touch_scroll.gesture_control=null;touch_scroll.release()
	# The flight view owns the camera every frame; it has to stand down first.
	view.process_mode=Node.PROCESS_MODE_DISABLED
	freeze_view=preload("res://native/presentation/action_freeze.gd").new()
	ui.add_child(freeze_view)
	freeze_view.z_index=70
	freeze_view.configure(self)
	freeze_view.closed.connect(end_action_freeze)
func end_action_freeze(resume: bool) -> void:
	if is_instance_valid(freeze_view):
		freeze_view.restore_scene()
		ui.remove_child(freeze_view)
		freeze_view.queue_free()
	freeze_view=null
	view.process_mode=Node.PROCESS_MODE_INHERIT
	page=""
	if resume: close_page()
	else: show_pause()
func show_transfer() -> void:
	open_page("Transfer expedition","transfer")
	label("Move this expedition between your devices. An export carries the saved expedition only \u2014 never imported game content, which each device imports from its own JAR.",16)
	label("An export can only be loaded by a copy that imported the same game content.",15).modulate=Color("9dc9bd")
	if not save_files.available():
		label("This build cannot open a file picker on this device, so expeditions cannot be moved here.",15).modulate=Color("d7c399")
		back_row(show_system if session.docked else show_pause)
		return
	var exportable: bool=FileAccess.file_exists(save_path)
	var export_button := button("Export expedition\u2026",func():
		var record: Dictionary=transfer.collect(content.data,save_path)
		if record.is_empty(): notice(transfer.failure); return
		save_files.export_text(transfer.default_name(session),JSON.stringify(record)))
	export_button.disabled=not exportable
	export_button.tooltip_text="Dock and save at a station first." if not exportable else "Write this expedition to a file you can carry."
	if session!=null and not session.docked:
		label("Your export is the last checkpoint you saved at a station, not this dive in progress.",15).modulate=Color("d7c399")
	button("Import expedition\u2026",func(): save_files.choose_import())
	label("Importing replaces the expedition on this device. The replaced one is kept as the backup checkpoint.",15).modulate=Color("d7c399")
	back_row(show_system if session.docked else show_pause)
func import_transfer(path: String) -> void:
	var record: Dictionary=transfer.read_export(content.data,path)
	if record.is_empty(): notice(transfer.failure); return
	if not transfer.install(content.data,save_path,record): notice(transfer.failure); return
	notice("Expedition imported. Reloading it now\u2026")
	reload_game()
func cycle_aspect_ratio() -> void:
	var choices: Array = Display.names()
	aspect_ratio=choices[(choices.find(aspect_ratio)+1)%choices.size()]
	update_render_resolution()
	layout()
	save_settings()
	show_graphics()
func show_layout_editor() -> void:
	"""Placing the controls is something a player does while looking at them, so
	it happens over the live overlay rather than inside a settings list."""
	if is_instance_valid(layout_editor) or not touch.enabled(): return
	var previous := page
	page="layout"
	overlay.hide()
	layout_editor=preload("res://native/presentation/touch_layout_editor.gd").new()
	ui.add_child(layout_editor)
	layout_editor.z_index=80
	layout_editor.configure(touch)
	layout_editor.closed.connect(func(result: Dictionary):
		touch.layout=result
		touch.arrange()
		save_settings()
		if is_instance_valid(layout_editor):
			ui.remove_child(layout_editor)
			layout_editor.queue_free()
		layout_editor=null
		page=previous
		show_controls())
func migrate_travel_bindings() -> void:
	# Move only the previous default pairs; preserve player-defined bindings.
	if [key_bindings.autopilot,key_bindings.time] in [[KEY_P,KEY_T],[KEY_T,KEY_Y]] and not KEY_R in key_bindings.values():
		key_bindings.autopilot=KEY_R;key_bindings.time=KEY_T
func setting_number(config: ConfigFile, section: String, key: String, fallback: float, low: float, high: float) -> float:
	"""A settings file is text a player can edit, and older builds wrote other
	shapes. A value that is missing, the wrong type, NAN or INF has to come back
	as the default rather than reaching audio gain or a sensitivity multiplier."""
	var value: Variant = config.get_value(section,key,fallback)
	if value is not float and value is not int: return fallback
	var number := float(value)
	return clampf(number,low,high) if is_finite(number) else fallback
func setting_index(config: ConfigFile, section: String, key: String, fallback: int, highest: int) -> int:
	var value: Variant = config.get_value(section,key,fallback)
	if value is not int and value is not float: return fallback
	if value is float and not is_finite(value): return fallback
	return clampi(int(value),0,highest)
func setting_keycode(config: ConfigFile, key: String, fallback: int) -> int:
	var value: Variant = config.get_value("keys",key,fallback)
	if value is not int and value is not float: return fallback
	if value is float and not is_finite(value): return fallback
	var code := int(value)
	# Rebinding only ever stores a physical keycode; anything else would leave
	# an action permanently unreachable with no way to notice from the menu.
	return code if code>0 and not OS.get_keycode_string(code).is_empty() else fallback
func save_settings() -> void:
	var config := ConfigFile.new(); config.load(settings_path)
	world_spacing.write_config(config)
	config.set_value("world","split_gates",Region.split_gates)
	for key in key_bindings: config.set_value("keys",key,key_bindings[key])
	for key in graphics: config.set_value("graphics",key,graphics[key])
	config.set_value("input","touch",touch.mode);config.set_value("input","deadzone",controller.deadzone);config.set_value("input","invert_gamepad",controller.invert)
	config.set_value("input","vibration",vibration)
	config.set_value("graphics","modern",modern_graphics)
	config.set_value("view","camera",view.camera_mode)
	config.set_value("view","render_quality",render_quality)
	config.set_value("view","resolution_v5",render_quality)
	config.set_value("view","temporal_aa",temporal_aa)
	config.set_value("keys","mouse_sensitivity",mouse_sensitivity); config.set_value("keys","invert_mouse",invert_mouse)
	config.set_value("input","touch_look",touch_look_sensitivity)
	config.set_value("input","touch_drag_anywhere",touch.drag_anywhere)
	config.set_value("input","touch_fixed_stick",touch.fixed_stick)
	config.set_value("input","strafe",strafe_mode)
	config.set_value("input","smooth_steering",world.smooth_steering)
	config.set_value("input","motion",motion_steering);config.set_value("input","motion_sensitivity",motion_sensitivity)
	config.set_value("input","motion_invert",invert_motion_pitch)
	config.set_value("input",TOUCH_LAYOUT_KEY,preload("res://native/input/touch_layout.gd").encode(touch.layout))
	config.set_value("view","aspect_ratio",aspect_ratio)
	config.set_value("interface","hints",gameplay_hints)
	config.set_value("audio","music",dive_audio.music_gain); config.set_value("audio","effects",dive_audio.effects_gain)
	DirAccess.make_dir_recursive_absolute(settings_path.get_base_dir()); config.save(settings_path)
func set_graphics_mode(modern: bool) -> void:
	modern_graphics=modern
	apply_graphics();save_settings()
func apply_graphics() -> void:
	update_render_resolution()
	dive_audio.set_enabled(graphics.audio)
	# Rebuild both directions: every actor, station and cached neighbor changes together.
	var rebuild: bool=view.pack.enabled!=(false) or view.modern_graphics!=modern_graphics
	view.modern_graphics=modern_graphics;view.pack.enabled=false
	view.set_station_smoothing(graphics.station_smoothing)
	if rebuild:view.revision=-1
	terrain.apply_pack(view.pack)
	abyss.set_headlights(modern_graphics and graphics.headlights)
	abyss.set_headlight_beams(modern_graphics and graphics.beams)
	view.set_actor_beams(modern_graphics and graphics.beams)
	view.set_depth_limits(graphics.depth_limits)
	var env := abyss.environment.environment
	env.volumetric_fog_enabled=modern_graphics and graphics.volumetric and RenderingServer.get_current_rendering_method()=="forward_plus"
	env.ssao_enabled=modern_graphics and graphics.detail
	env.glow_enabled=modern_graphics;abyss.particles.visible=true
	overlay.decorated=true;overlay.queue_redraw()
	layout()
func show_graphics() -> void:
	open_page("Ocean presentation","graphics")
	var mode := option("GRAPHICS  ·  "+("ENHANCED LIGHTING" if modern_graphics else "CLASSIC LIGHTING")+"  ⇄","lighting",func():set_graphics_mode(not modern_graphics);show_graphics())
	mode.name="GraphicsMode"
	label("Original JAR models and textures. Classic instruments in both lighting modes.",14)
	var names := {"headlights":"Headlights","beams":"Headlight beams","volumetric":"Volumetric light","detail":"Surface shading detail"}
	# Fog scattering, ambient occlusion and TAA exist only on the Forward+
	# renderer; on OpenGL the rows say so instead of toggling nothing.
	var forward: bool=RenderingServer.get_current_rendering_method()=="forward_plus"
	var settings_grid:=GridContainer.new();settings_grid.columns=2;settings_grid.add_theme_constant_override("h_separation",20);column.add_child(settings_grid)
	for key in names:
		var needs_forward: bool=key in ["volumetric","detail"] and not forward
		var toggle := option(names[key]+(" · Needs Vulkan" if needs_forward else (" · On" if modern_graphics and graphics[key] else " · Off")),key,func():graphics[key]=not graphics[key];apply_graphics();save_settings();show_graphics(),settings_grid)
		toggle.disabled=not modern_graphics or needs_forward;toggle.set_meta("modern_option",true)
	option("Depth limit markers · "+("On" if graphics.depth_limits else "Off"),"depth_limits",func():graphics.depth_limits=not graphics.depth_limits;apply_graphics();save_settings();show_graphics())
	label("A hatched panel below or above the submarine that shows as it nears its deepest or shallowest safe depth, after the phone game's limiter panels.",14)
	option("Station texture smoothing · "+("On" if graphics.station_smoothing else "Off · pixelated"),"smoothing",func():graphics.station_smoothing=not graphics.station_smoothing;apply_graphics();save_settings();show_graphics())
	var taa := option("Temporal antialiasing · "+("Needs Vulkan" if not forward else ("On" if modern_graphics and temporal_aa else "Off")),"taa",func():temporal_aa=not temporal_aa;update_render_resolution();save_settings();show_graphics())
	taa.disabled=not modern_graphics or not forward;taa.set_meta("modern_option",true)
	var resolution := option("3D resolution · "+(["Performance · 1080p","Quality · 1440p","Native · full display resolution"][clampi(render_quality,0,2)] if modern_graphics else "Native"),"resolution",func():render_quality=(render_quality+1)%3;update_render_resolution();save_settings();show_graphics())
	resolution.disabled=not modern_graphics;resolution.set_meta("modern_option",true)
	option("Aspect ratio · "+aspect_ratio.capitalize(),"aspect",cycle_aspect_ratio)
	option("Game audio · "+("On" if graphics.audio else "Off"),"audio",func():graphics.audio=not graphics.audio;apply_graphics();save_settings();show_graphics())
	volume_slider("Music",dive_audio.music_gain,func(value):dive_audio.music_gain=value;dive_audio.apply_levels();save_settings())
	volume_slider("Effects",dive_audio.effects_gain,func(value):dive_audio.effects_gain=value;dive_audio.apply_levels();save_settings())
	button("Fullscreen / windowed",toggle_fullscreen)
	back_row(show_system if session.docked else show_pause)
func station_identity(parent: Node) -> void:
	var station: Dictionary=session.stations[session.station_id]
	var identity:=HBoxContainer.new();identity.name="StationIdentity";identity.add_theme_constant_override("separation",16);parent.add_child(identity)
	# The gold logo for the gold collection, the faction's otherwise (ch).
	var emblem := art_image(imported_art.image("logo_2" if golden() else "logo_0" if session.is_colonist_station() else "logo_1"),identity,56)
	if emblem!=null: emblem.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	var words:=VBoxContainer.new();words.size_flags_horizontal=Control.SIZE_EXPAND_FILL;words.add_theme_constant_override("separation",2);words.alignment=BoxContainer.ALIGNMENT_CENTER;identity.add_child(words)
	# Unwrapped: a wrapping label measured before the panel has its width
	# reports a column of single words, and the dock panel is sized from it.
	var faction := label("Colonists" if session.is_colonist_station() else "Rebels",20,words);faction.add_theme_color_override("font_color",colours().text);faction.autowrap_mode=TextServer.AUTOWRAP_OFF
	var standing := label("Tech level %d  ·  %d cr"%[station.tech,session.credits],15,words);standing.add_theme_color_override("font_color",colours().dim);standing.autowrap_mode=TextServer.AUTOWRAP_OFF
func tile(text: String, icon: String, action: Callable, parent: Node) -> Button:
	"""A station service: its icon over its name."""
	var node := button(text,action,parent)
	node.alignment=HORIZONTAL_ALIGNMENT_CENTER;node.custom_minimum_size=Vector2(0,112 if touch.enabled() else 104)
	node.add_theme_font_override("font",heading_font(4));node.add_theme_font_size_override("font_size",16)
	for state in ["normal","hover","pressed","focus","disabled"]:
		var style := node.get_theme_stylebox(state) as StyleBoxFlat
		style.content_margin_top=60;style.content_margin_bottom=8;style.content_margin_left=6;style.content_margin_right=6
	var mark := StationIcon.new(icon,colours().accent,44);node.add_child(mark)
	mark.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP);mark.offset_left=-22;mark.offset_right=22;mark.offset_top=12;mark.offset_bottom=56
	node.accessibility_name=text
	return node
func service_card(title: String, text: String, icon: String, art: Texture2D, action: Callable, parent: Node) -> Button:
	"""A hub entry: icon, name and what is behind it, with the station's own
	picture of that thing where the game has one."""
	var node := button("",action,parent)
	node.custom_minimum_size=Vector2(0,140 if ui.size.y>=700 else 124);node.accessibility_name=title;node.tooltip_text=text
	node.set_meta("option",title)
	var cells := HBoxContainer.new();node.add_child(cells);cells.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cells.offset_left=22;cells.offset_right=-18;cells.offset_top=16;cells.offset_bottom=-14;cells.add_theme_constant_override("separation",16);cells.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var words := VBoxContainer.new();words.size_flags_horizontal=Control.SIZE_EXPAND_FILL;words.add_theme_constant_override("separation",6);words.mouse_filter=Control.MOUSE_FILTER_IGNORE;cells.add_child(words)
	var top := HBoxContainer.new();top.add_theme_constant_override("separation",14);top.mouse_filter=Control.MOUSE_FILTER_IGNORE;words.add_child(top)
	line_icon(icon,40,top)
	var roomy: bool=ui.size.y>=700
	var name_label := caption(title,19 if roomy else 16,top,4 if roomy else 3);name_label.add_theme_color_override("font_color",colours().text);name_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	var about := label(text,15,words);about.add_theme_color_override("font_color",colours().dim)
	if art!=null:
		var picture := TextureRect.new();picture.texture=art;picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;picture.custom_minimum_size=Vector2(minf(150,ui.size.x*(.12 if roomy else .07)),0);picture.mouse_filter=Control.MOUSE_FILTER_IGNORE;cells.add_child(picture)
	line_icon("next",22,cells)
	return node
func service_grid(parent: Node=null) -> GridContainer:
	var grid := GridContainer.new();grid.columns=2 if ui.size.x>=900 else 1;grid.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation",16);grid.add_theme_constant_override("v_separation",16);(parent if parent!=null else column).add_child(grid)
	return grid
func show_station() -> void:
	open_page(session.stations[session.station_id].name,"station")
	column.add_theme_constant_override("separation",12)
	station_identity(glass(column,false,14))
	if not session.cargo_receipt.is_empty():
		var receipt:=label(session.cargo_receipt,15);receipt.name="CargoReceipt";receipt.add_theme_color_override("font_color",colours().good)
	var services := [
		["HANGAR","Equipment shop, ship dealer and workshop","hangar",show_hangar],
		["MISSIONS","Current objectives and available contracts","missions",show_station_missions],
		["MAP","Stations, routes and S.T.R.E.A.M.","map",show_map],
		["TRADE","Buy and sell cargo","trade",func():show_market("trade")],
		["STATUS","Your ship, cargo and pilot record","status",show_station_status],
		["SYSTEM","Save, controls and settings","system",show_system]]
	var grid:=GridContainer.new();grid.name="Services";grid.columns=3;grid.add_theme_constant_override("h_separation",10);grid.add_theme_constant_override("v_separation",10);column.add_child(grid)
	for service in services:
		tile(service[0],service[2],service[3],grid).tooltip_text=service[1]
	var launch:=primary(iconic(button("DEPART",depart),"depart",30));launch.name="Depart"
	launch.custom_minimum_size.y=64 if touch.enabled() else 58;launch.add_theme_font_override("font",heading_font(6));launch.add_theme_font_size_override("font_size",20)
	if not session.notices.is_empty():
		var notices: Array=session.notices.duplicate();session.notices=[]
		var medals: Array=[]
		for index in notices.size():
			var entry: Dictionary=notices[index]
			session.acknowledge_notice(entry)
			if entry.kind=="medal":medals.append(entry);continue
			if entry.kind=="pirate_bounty":
				# Whatever came after the bounty is shown when the station is back.
				session.notices=medals+notices.slice(index+1)
				show_dialogue([{"speaker":session.text(166),"text":entry.text}],show_station);return
			if entry.kind!="cargo_settlement":notice(entry.text)
		if not medals.is_empty():show_new_medal(medals,0);return
	check_dock_hints()
func first_art(entries: Array, kind: String) -> Texture2D:
	for entry in entries:
		var art: Texture2D=imported_art.item(entry.id,kind)
		if art!=null: return art
	return null
func show_hangar() -> void:
	open_page("Hangar","hangar")
	var station: Dictionary=session.stations[session.station_id]
	var grid := service_grid()
	service_card("Equipment shop","Buy and fit systems for your ship, or sell what is installed.","cart",first_art(station.equipment,"equipment"),func():show_market("equipment"),grid)
	service_card("Ship dealer","Buy a new hull. Your current ship is traded in.","hangar",first_art(station.ships,"ships"),func():show_market("ships"),grid)
	service_card("Workshop / Manufacture","Turn the cargo in your hold into products.","workshop",first_art(economy.recipes(station),"goods"),func():show_market("manufacture"),grid)
	service_card("Your ship & cargo","Hull, cargo manifest and installed systems.","cargo",imported_art.item(session.ship.id,"ships"),func():show_ship_status(show_hangar),grid)
func show_station_missions() -> void:
	open_page("Missions","station_missions")
	var station: Dictionary=session.stations[session.station_id]
	var grid := service_grid()
	service_card("Current objectives & journal","Your story task and accepted contract, with autonavigation to their destinations.","journal",null,show_journal,grid)
	var offers: int=station.missions.size()
	service_card("Available contracts","%d on this station's board."%offers if session.campaign.secondary.kind<0 else "An accepted contract is already in your journal.","contracts",
		imported_art.portrait(station.missions[0].portrait) if offers>0 else null,func():show_market("missions"),grid)
func show_station_status() -> void:
	open_page("Status","station_status")
	var grid := service_grid()
	service_card("Your ship & cargo","Hull, cargo manifest and installed systems.","cargo",imported_art.item(session.ship.id,"ships"),show_ship_status,grid)
	var best := 0
	for tier in session.medals.levels:
		if tier>0 and (best==0 or tier<best): best=tier
	var owned: int=session.medals.levels.filter(func(tier): return tier>0).size()
	service_card("Pilot profile & medals","Rank %d · %d / 24 medals · expedition statistics."%[session.counters.k,owned],"person",
		imported_art.image("medal_%d"%(best if best>0 else (5 if session.is_colonist_station() else 7))),show_profile,grid)
func show_system() -> void:
	open_page("System","system")
	var grid := service_grid();grid.add_theme_constant_override("v_separation",10)
	for entry in [["Save game","save",show_save_slots],["Controls","controls",show_controls],["Graphics & audio","graphics",show_graphics],["World","world",show_world_settings],
		["Help","help",show_help],["Transfer expedition","transfer",show_transfer]]:
		iconic(button(entry[0],entry[2],grid),entry[1])
	iconic(button("Reload station checkpoint",func(): confirm("Reload checkpoint",
		"Return to your last saved station? Everything since that checkpoint is lost.",
		"Reload checkpoint",reload_game,show_system),grid),"reload")
	iconic(button("Main menu",func(): confirm("Main menu",
		"Your expedition is saved at this station first.",
		"Return to main menu",return_to_menu,show_system),grid),"exit")
func show_world_settings() -> void:
	open_page("World","world_settings")
	var settings:=preload("res://native/presentation/world_settings.gd").new()
	settings.configure(world_spacing);column.add_child(settings)
	var active:=label("",16)
	var refresh:=func():
		active.text="Current dive: %s grid squares."%Spacing.square_text(session.world_layout.spacing_meters)
		if world_spacing.meters()!=session.world_layout.spacing_meters:
			active.text+="\nNext departure: %s grid squares."%Spacing.square_text(world_spacing.meters())
	refresh.call()
	label("Changes apply on your next departure or when you load an expedition.",15)
	settings.changed.connect(func():world.spacing_meters=world_spacing.meters();save_settings();refresh.call())
	option(preload("res://native/presentation/world_settings.gd").gate_text(Region.split_gates),"split_gates",func():Region.split_gates=not Region.split_gates;save_settings();show_world_settings())
	label("Gate changes apply from the next area you enter.",15)
	back_row(show_system if session.docked else show_pause)
func back_row(action: Callable) -> void:
	"""Where a page used to end in its own Back row, the header's BACK, Esc and
	the pad's B now take that way instead; one way back per page."""
	page_back=action
func dock_back() -> void:
	if page_back.is_valid():
		var way := page_back;page_back=Callable();way.call();return
	# Back inside Controls means the section list, not the way out of settings.
	if page=="controls" and not controls_section.is_empty(): focus_option=controls_section;show_controls("");return
	if not session.docked:close_page();return
	if page=="market":
		if market_category in ["ships","equipment","manufacture"]:show_hangar();return
		if market_category=="missions":show_station_missions();return
	if page in ["graphics","controls","world_settings","save_slots","help"]:show_system();return
	if page=="journal":show_station_missions();return
	if page in ["ship_status","profile"]:show_station_status();return
	show_station()
func depart() -> void:
	save_game(false)
	if world.depart(): begin_departure()
	else: notice(world.message)
func begin_departure() -> void:
	flight_ms=0
	departure_elapsed=0;departure_destination=-1;departure_route="station"
	open_page("Departing","departure");overlay.hide()
	world.region.player.throttle=100
	view.rebuild();view.begin_departure();view._process(0)
	notice("Leaving %s · Enter / click to skip"%session.stations[session.station_id].name)
func finish_departure() -> void:
	if page!="departure":return
	view.place_departure(1.0);view.departure_progress=-1
	world.region.player.throttle=0
	if departure_route=="encounter":world.navigate_encounter()
	elif departure_destination>=0:
		if departure_route=="stream":world.plan_stream(departure_destination)
		else:world.route_to(departure_destination)
	departure_destination=-1;message.text="";notification_time=0
	close_page();briefing()
func check_station_progress() -> void:
	var mission=session.campaign.completion(true,0,session.station_id,session.ship,session.counters)
	if mission!=null:
		mission.completed=true
		show_dialogue(session.dialogue(mission,1),func(): session.complete_mission(mission); show_station(); save_game(false))
func begin_opening() -> void:
	"""A new expedition opens on the phone game's title sequence, laid over
	the station the diver starts at; the briefing follows it."""
	view.rebuild();view._process(0)
	open_page("","opening");overlay.hide();opening_fraction=0.0
	opening.begin(view,dive_audio,session,imported_art.image("logo"))
func end_opening() -> void:
	if page=="opening":close_page()
	briefing()
func briefing() -> void:
	var secondary=session.campaign.secondary
	if secondary.kind>=0 and secondary.jump_limit>=0 and secondary.expired():
		secondary.failed=true
		show_dialogue(session.dialogue(secondary,2),func(): session.abandon_contract(); close_page())
		return
	var mission=session.campaign.active
	if mission.kind>=0:
		show_dialogue(session.dialogue(mission,0),close_page)
func show_dialogue(entries: Array, after: Callable, cue: String="message") -> void:
	lines=entries; line_index=0; dialogue_done=after; dialogue_cue=cue
	if lines.is_empty(): after.call(); return
	dialogue_page()
func dialogue_page() -> void:
	dive_audio.cue(dialogue_cue)
	open_page(str(lines[line_index].get("speaker","Transmission")),"dialogue")
	for child in overlay.get_children():overlay.remove_child(child);child.queue_free()
	column=VBoxContainer.new();column.add_theme_constant_override("separation",8);overlay.add_child(column)
	label("RADIO  /   "+str(lines[line_index].get("speaker","TRANSMISSION")).to_upper(),14).add_theme_color_override("font_color",Color("8bd6ee"))
	var transmission := HBoxContainer.new(); transmission.add_theme_constant_override("separation",10);transmission.size_flags_vertical=Control.SIZE_EXPAND_FILL; column.add_child(transmission)
	art_image(imported_art.portrait(session.face_layers if lines[line_index].get("speaker","")==session.name else lines[line_index].get("portrait",[])),transmission,112)
	var body := RichTextLabel.new();body.text=str(lines[line_index].get("text",""));body.custom_minimum_size=Vector2(0,92);body.size_flags_horizontal=Control.SIZE_EXPAND_FILL;body.size_flags_vertical=Control.SIZE_EXPAND_FILL;body.add_theme_font_size_override("normal_font_size",18);body.add_theme_color_override("default_color",Color("c9ded5"));transmission.add_child(body)
	var footer := HBoxContainer.new();column.add_child(footer);label("%02d / %02d"%[line_index+1,lines.size()],10,footer)
	var next := button("Continue >",func():
		line_index+=1
		if line_index>=lines.size(): dialogue_done.call()
		else: dialogue_page(),footer)
	next.custom_minimum_size.y=64 if touch.enabled() else 44;next.add_theme_font_size_override("font_size",14)
	layout.call_deferred()
	focus_if_visible.call_deferred(next)
func focus_if_visible(control) -> void:
	if is_instance_valid(control) and control.is_inside_tree() and control.is_visible_in_tree(): control.grab_focus()
func consume_events() -> void:
	while not world.region.events.is_empty():
		var entry: Dictionary = world.region.events.pop_front()
		match entry.kind:
			"briefing": show_dialogue(session.dialogue(entry.mission,0),close_page)
			"credits": show_dialogue([{"speaker":"Credits","text":session.text(26)+"\n\n"+session.text(28)+"\n\n"+session.text(27)}],func(): world.region.acknowledge_credits(); close_page())
			"mission_complete": show_dialogue(session.dialogue(entry.mission,1),func(): world.region.acknowledge_completion(); close_page())
			"transmission":
				var speaker: String = str(content.data.constants.ah["a:[Ljava.lang.String;"][entry.entry.speaker])
				# cq announces a radio call in the water with the signal cue; the
				# message cue is M.A.I.'s, for the mission screens.
				show_dialogue([{"speaker":session.name if entry.entry.speaker==0 else speaker,"text":session.text(entry.entry.text_id,session.name),"portrait":content.data.constants.ah["a:[[B"][entry.entry.speaker] if entry.entry.speaker>0 else []}],func(): world.region.acknowledge_transmission(); close_page(),"signal")
			"death","mission_failed":
				dive_audio.cue("pressure")
				open_page(entry.text,"failure")
				if entry.kind=="mission_failed" and not world.region.mission.story:
					button("Continue expedition",func():
						session.abandon_contract(); world.region.mission=session.campaign.active; world.region.success=null; world.region.failure=null; world.region.time_limit=0; world.region.failed=false; close_page())
				button("Reload station checkpoint",reload_game); button("Main menu",return_to_menu)
			_:
				if entry.kind=="notice" and entry.text.begins_with("Cannot collect catch"):hold_full_seen=true
				notice(entry.text)
		# Preserve later events until the current dialogue/failure is resolved.
		if not page.is_empty(): break
func save_game(feedback: bool=true) -> void:
	if not session.docked:
		if feedback: notice("Dock at a station to save your expedition.")
		return
	if store.write(save_path,session):
		if feedback: notice(session.text(32))
	else: notice(store.failure)
func show_save_slots() -> void:
	"""The phone game's three saves, each named for who and where it holds;
	writing over one asks first. The autosave keeps the dock checkpoint."""
	open_page(session.text(2),"save_slots")
	for index in store.SLOT_PATHS.size():
		var path: String=store.slot_path(index)
		var entry: Dictionary=store.summary(path,content.data) if FileAccess.file_exists(path) else {}
		var choice := button("%d.  %s"%[index+1,store.describe(entry)],func():
			if entry.is_empty():write_slot(path)
			else:confirm(store.slot_title(index),session.text(31),session.text(45),func():write_slot(path),show_save_slots))
		choice.alignment=HORIZONTAL_ALIGNMENT_LEFT
	back_row(dock_back if session.docked else show_pause)
func write_slot(path: String) -> void:
	if store.write(path,session):notice(session.text(32))
	else:notice(store.failure)
	if session.docked:show_system()
	else:close_page()
func reload_game() -> void:
	var restored=store.read(save_path,content.data)
	if restored==null: notice(store.failure); return
	var fell_back: bool=store.recovered
	world.dispose(); session=restored; world.configure(session); economy.configure(session)
	world.build_docked_view()
	show_station()
	TravelFade.uncover(ui)
	if fell_back: notice("Your save could not be read. Restored the previous checkpoint.")
func return_to_menu() -> void:
	if session.docked: save_game(false)
	world.dispose(); get_tree().change_scene_to_file("res://scenes/native_main.tscn")
func buy_limit(item) -> int:
	"""What the purse, the hold and the station's shelf allow, whichever runs out
	first. A free commodity would divide by nothing, so it buys what fits."""
	var space: int = session.ship.capacity()-session.ship.cargo_used
	var affordable: int = session.credits/item.price if item.price>0 else space
	return maxi(0,mini(int(item.stock),mini(affordable,space)))
func trade_amount(station: Dictionary, item, buying: bool, count: int) -> void:
	"""Repeats the single trade the player would otherwise click, so the station's
	repricing, its stock and the hold all move exactly as they do one at a time.
	Stops at the first refusal, and reports what actually moved rather than what
	was asked for, because a part-filled order is the ordinary case here."""
	var before: int = session.credits
	var moved := 0
	for _index in maxi(0,count):
		if not economy.trade(station,item.id,buying): break
		moved+=1
	if moved<1: notice("Insufficient credits, cargo space or stock."); return
	notice("%s %d t of %s for %d cr"%["Bought" if buying else "Sold",moved,item_name(item.id),absi(session.credits-before)])
func show_market(kind: String) -> void:
	if market_category!=kind: market_selection=0;market_page=0;market_category=kind
	var denial: int = session.service_denial(kind)
	if denial>=0: notice(session.text(denial)); return
	open_page({"equipment":"Equipment shop","ships":"Ship dealer","trade":"Trade","manufacture":"Workshop","missions":"Available contracts"}.get(kind,kind),"market",
		{"equipment":"Outfit your ship","ships":"Buy a hull · trade in your current one","trade":"Buy and sell cargo","manufacture":"Craft products from your cargo","missions":"Contracts offered at this station"}.get(kind,""))
	header_chip("credits","%d CR"%session.credits,"Your credits")
	if kind=="ships" and ui.size.x>=1100: header_chip("hangar",content.ship_name(session.ship.id),"Current ship")
	var station: Dictionary = session.stations[session.station_id]
	match kind:
		"equipment":
			var bar := HBoxContainer.new();bar.add_theme_constant_override("separation",10);column.add_child(bar)
			var tabs := HBoxContainer.new();tabs.name="EquipmentTabs";tabs.add_theme_constant_override("separation",10);tabs.size_flags_horizontal=Control.SIZE_EXPAND_FILL;bar.add_child(tabs)
			ship_strip=bar if ui.size.x>=1100 else column
			for index in 2:
				var tab := iconic(button("SHOP" if index==0 else "SHIP EQUIPMENT",func():
					equipment_tab=index;market_selection=0;market_page=0;show_market("equipment"),tabs),"cart" if index==0 else "wrench",24)
				tab.name="ShopTab" if index==0 else "ShipEquipmentTab"
				tab.toggle_mode=true
				tab.button_pressed=equipment_tab==index
				tab.alignment=HORIZONTAL_ALIGNMENT_CENTER;tab.add_theme_font_override("font",heading_font(4))
				if ui.size.y<700: tab.custom_minimum_size.y=52
				if equipment_tab==index:
					var lit := StationTheme.button_state(golden(),"focus");lit.content_margin_left=50;lit.border_width_bottom=3
					tab.add_theme_stylebox_override("normal",lit);tab.add_theme_stylebox_override("pressed",lit)
			equipment_browser(station)
		"ships":
			equipment_browser(station,true)
		"trade":
			goods_browser(station)
		"manufacture":
			goods_browser(station,true)
		"missions":
			if session.campaign.secondary.kind>=0: label("An accepted contract is already in your journal.").add_theme_color_override("font_color",colours().dim)
			elif station.missions.is_empty(): label("No contracts on this station's board.").add_theme_color_override("font_color",colours().dim)
			else:
				var board := GridContainer.new();board.columns=2 if ui.size.x>=1100 else 1;board.add_theme_constant_override("h_separation",16);board.add_theme_constant_override("v_separation",16);column.add_child(board)
				for mission in station.missions: contract_card(station,mission,board)
	if kind not in ["equipment","ships","trade","manufacture"]: back_row(dock_back)
func contract_card(station: Dictionary, mission, parent: Node) -> void:
	"""The board's card (k): the client's face and name, the destination, its
	depth and distance, the difficulty (or the stopovers of a passage), the
	target, and the fee against the deposit."""
	var palette := colours()
	var info=preload("res://native/presentation/mission_info.gd")
	var body := VBoxContainer.new();body.add_theme_constant_override("separation",10);glass(parent,false,14).add_child(body)
	var top := HBoxContainer.new();top.add_theme_constant_override("separation",14);body.add_child(top)
	var face := glass(top,false,8);face.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
	art_image(imported_art.portrait(mission.portrait),face,72)
	var words := VBoxContainer.new();words.size_flags_horizontal=Control.SIZE_EXPAND_FILL;words.add_theme_constant_override("separation",4);top.add_child(words)
	label(session.title(mission),19,words).add_theme_color_override("font_color",palette.text)
	caption("%s: %s"%[session.text(142),mission.sponsor],11,words,3)
	label(session.description(mission),15,words).add_theme_color_override("font_color",palette.dim)
	rule(body)
	var journey: int=int(economy.distance(station,session.stations[mission.destination]))
	var rating: int=mission.normalized_difficulty(int(session.counters.k))
	var grade: String=session.text(273 if rating<4 else 274 if rating<8 else 275)
	var outside: bool=world.outside_safety(mission.destination)
	var rows: Array=[["map",session.text(334),mission.destination_name],
		["shield",session.text(245),"%d m"%session.stations[mission.destination].depth,palette.bad if outside else palette.text],
		["depart",session.text(333),session.text(310) if journey==0 else "%d km"%journey]]
	if mission.kind==8: rows.append(["grid",session.text(331),str(mission.jump_limit+1) if mission.jump_limit>=0 else session.text(335)])
	else: rows.append(["status",session.text(39),grade])
	figure_rows(rows,body)
	if outside: label(session.text(255),14,body).add_theme_color_override("font_color",palette.bad)
	target_line(mission,body)
	for detail in [info.progress(session,mission),info.requirements(mission),info.deadline(mission)]:
		if not detail.is_empty(): label(detail,15,body).add_theme_color_override("font_color",palette.text)
	var terms := HBoxContainer.new();terms.add_theme_constant_override("separation",10);body.add_child(terms)
	figure_tile("credits","Reward","%d cr"%mission.reward,terms)
	figure_tile("shield","Deposit","%d cr"%mission.deposit,terms)
	# Cards side by side share a row's height; the button keeps to the foot.
	var foot := Control.new();foot.size_flags_vertical=Control.SIZE_EXPAND_FILL;foot.mouse_filter=Control.MOUSE_FILTER_IGNORE;body.add_child(foot)
	primary(iconic(button("Accept contract",func():
		if session.accept_contract(mission): show_station()
		else: notice("Insufficient credits for the deposit."),body),"contracts",22))
func transaction_result(result: int) -> void:
	if result>=0: notice(session.text(result))
func show_map(autopilot_only: bool=false) -> void:
	atlas_autopilot_only=autopilot_only
	if session.docked:
		var denial: int = session.service_denial("map")
		if denial>=0: notice(session.text(denial)); return
	open_page(chart_title(),"map")
	# The chart's own hint (ch: 359), once, the first time it is opened with
	# a task on the board.
	if gameplay_hints and not session.hints_said.has("map") and (session.campaign.primary.kind>=0 or session.campaign.secondary.kind>=0):
		session.hints_said["map"]=true;notice(chart_hint())
	var actions := station_chart(map_destination)
	map_slice.selected.connect(select_station)
	map_widget.zone_dragged.connect(func(center):follow_drag(center,-1 if map_unchosen else map_destination))
	map_widget.zone_moved.connect(func(center,near):
		var choice:=zone_choice(center,near,-1 if map_unchosen else map_destination)
		if choice>=0:select_station(choice);return
		map_unchosen=true;map_picker.select(-1);map_widget.selected_id=-1;map_widget.queue_redraw();map_slice.frame(center,ZONE_RADIUS,-1)
		var prompt:=zone_prompt(center)
		show_station_card(-1,prompt[1],prompt[0])
		for node in [map_route_button,stream_button]:
			if is_instance_valid(node):node.disabled=true)
	var search := LineEdit.new(); search.placeholder_text="Find a station…"; search.custom_minimum_size.x=170; actions.add_child(search)
	search.text_changed.connect(func(value): map_widget.filtered=value.to_lower(); map_widget.queue_redraw())
	var picker := OptionButton.new(); map_picker=picker; picker.custom_minimum_size.x=190
	for station in session.stations: picker.add_item(station.name,station.id)
	picker.selected=map_destination; picker.item_selected.connect(func(index): select_station(picker.get_item_id(index))); actions.add_child(picker)
	species_toggle(actions,func():
		if not map_unchosen:select_station(map_destination))
	var gap := Control.new(); gap.size_flags_horizontal=Control.SIZE_EXPAND_FILL; actions.add_child(gap)
	if world.encounter_navigation_point()!=null:
		bar_button("Encounter waypoint",func():
			if session.docked:
				depart()
				if session.docked:return
				if page=="departure":departure_route="encounter";return
			world.navigate_encounter();close_page(),actions).tooltip_text="Local encounter active · follow its waypoint before travelling to the next story station."
	map_route_button=bar_button("Set station autopilot",map_autopilot,actions)
	stream_button=bar_button("Plan S.T.R.E.A.M. transfer",map_stream,actions)
	stream_button.visible=not atlas_autopilot_only
	bar_button("Back",dock_back,actions)
	back_row(show_station if session.docked else close_page)
	map_unchosen=false
	var start: Dictionary=session.stations[map_destination]
	map_widget.place_lens(Vector2(start.x,start.y))
	select_station(map_destination)
func map_autopilot() -> void:
	if ask_outside_safety(map_destination,map_autopilot,func():show_map(atlas_autopilot_only)):return
	if session.docked:
		depart()
		if session.docked: return
		if page=="departure":departure_destination=map_destination;return
	if world.route_to(map_destination):
		if page!="dialogue": close_page()
	else: notice(world.message)
func map_stream() -> void:
	var denial: String = world.stream_denial(map_destination)
	if not denial.is_empty(): notice(denial); return
	if ask_outside_safety(map_destination,map_stream,func():show_map(atlas_autopilot_only)):return
	if session.docked:
		depart()
		if session.docked: return
		if page=="departure":departure_destination=map_destination;departure_route="stream";return
	if world.plan_stream(map_destination):
		# A chart already shown at this gate must come up again for the
		# new plan, even without leaving the gate first.
		stream_prompted=false
		if page!="dialogue": close_page()
	else: notice(world.message)
func chart_hint() -> String:
	"""The chart's hint (ch: 359) without its last instruction. On the phone
	the depth map was a second screen behind the "Proceed" soft key (74);
	here it is always beside the chart, so the paragraph that sends the
	player looking for that key is left out, in whatever language it is in."""
	var key: String=session.text(74)
	var kept: PackedStringArray=[]
	for paragraph in session.text(359).split("\n\n"):
		if key.is_empty() or not paragraph.contains(key):kept.append(paragraph)
	return "\n\n".join(kept)
func chart_title() -> String:
	"""Both chart pages carry the original's own heading."""
	return "MAP  ·  DISCOVERED %d / %d"%[session.discovered.count(true),session.discovered.size()]
func station_chart(selection: int) -> HFlowContainer:
	"""The frame both chart pages share: the plan view on the left; on the
	right the original's side view of the stations under the lens and a card
	for the selected one, its figures beside the station itself; the key under
	both; and the page's actions along the bottom, which it returns."""
	column.size_flags_vertical=Control.SIZE_EXPAND_FILL
	# A wide phone leaves under six hundred rows for all of it.
	var compact: bool=ui.size.y<700
	var body := VBoxContainer.new(); body.size_flags_vertical=Control.SIZE_EXPAND_FILL; body.add_theme_constant_override("separation",10); column.add_child(body)
	var top := HBoxContainer.new(); top.size_flags_vertical=Control.SIZE_EXPAND_FILL; top.add_theme_constant_override("separation",14); body.add_child(top)
	map_widget=Map.new(); map_widget.world=world; map_widget.selected_id=selection; top.add_child(map_widget)
	map_widget.size_flags_horizontal=Control.SIZE_EXPAND_FILL; map_widget.size_flags_vertical=Control.SIZE_EXPAND_FILL; map_widget.size_flags_stretch_ratio=1.1
	map_widget.custom_minimum_size=Vector2(300,200) # after its _ready, which sets its own
	map_widget.lens_radius=ZONE_RADIUS;map_widget.focus_mode=Control.FOCUS_CLICK
	touch_scroll.gesture_control=map_widget
	var side := VBoxContainer.new(); side.size_flags_horizontal=Control.SIZE_EXPAND_FILL; side.add_theme_constant_override("separation",10); top.add_child(side)
	map_slice=DepthSlice.new(); map_slice.world=world; map_slice.art=imported_art; map_slice.size_flags_vertical=Control.SIZE_EXPAND_FILL; side.add_child(map_slice)
	if compact: map_slice.custom_minimum_size.y=96
	# The side view and the station share the column evenly, so the station
	# is shown at a size that reads rather than as a thumbnail.
	var card := PanelContainer.new(); card.add_theme_stylebox_override("panel",chart_panel()); card.size_flags_vertical=Control.SIZE_EXPAND_FILL; side.add_child(card)
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation",12); card.add_child(row)
	var facts := VBoxContainer.new(); facts.custom_minimum_size.x=190 if compact else 230; facts.size_flags_horizontal=Control.SIZE_FILL; facts.size_flags_vertical=Control.SIZE_SHRINK_BEGIN; facts.add_theme_constant_override("separation",2); row.add_child(facts)
	map_title=label("",20 if compact else 24,facts); map_title.modulate=Color("eef6ff")
	# Rich text, so a figure the ship cannot manage can be picked out in red.
	map_info=RichTextLabel.new(); map_info.bbcode_enabled=true; map_info.fit_content=true; map_info.scroll_active=false; map_info.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	map_info.add_theme_font_size_override("normal_font_size",14 if compact else 15); map_info.add_theme_color_override("default_color",Color("b9d4f2")); map_info.mouse_filter=Control.MOUSE_FILTER_PASS; facts.add_child(map_info)
	map_showcase=VBoxContainer.new(); map_showcase.size_flags_horizontal=Control.SIZE_EXPAND_FILL; map_showcase.custom_minimum_size.y=90 if compact else 120; row.add_child(map_showcase)
	var key := PanelContainer.new(); key.add_theme_stylebox_override("panel",chart_panel()); body.add_child(key)
	var legend := VBoxContainer.new(); legend.add_theme_constant_override("separation",2); key.add_child(legend)
	map_key(legend)
	map_widget.tooltip_text="Tap or drag the zone, then pick a station in the side view · hold a finger still to grab the zone · pinch / wheel to zoom · drag elsewhere / right mouse to pan"
	if not compact:
		# Its own line, wrapping, so a narrow window does not widen the chart.
		var gestures := label(map_widget.tooltip_text,13,legend); gestures.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; gestures.modulate=Color("7f96ad")
	# A flow, so a narrow window wraps the actions onto a second row instead
	# of pushing the whole chart off the side.
	var actions := HFlowContainer.new(); actions.add_theme_constant_override("h_separation",10); actions.add_theme_constant_override("v_separation",8)
	# The page's scroller clips at its own edge, and a focused control draws its
	# outline outside its box: flush against the bottom, the picker's outline
	# lost its lower edge.
	var inset := MarginContainer.new(); body.add_child(inset); inset.add_child(actions)
	for edge in ["margin_top","margin_bottom","margin_left","margin_right"]: inset.add_theme_constant_override(edge,4)
	return actions
func chart_panel() -> StyleBoxFlat:
	var style := StyleBoxFlat.new(); style.bg_color=Color("071631cc"); style.border_color=Color("2f6fa8"); style.set_border_width_all(1); style.set_content_margin_all(10)
	return style
func bar_button(text: String, action: Callable, parent: Node) -> Button:
	var node := button(text,action,parent); node.size_flags_horizontal=Control.SIZE_SHRINK_END; node.alignment=HORIZONTAL_ALIGNMENT_CENTER
	return node
func species_toggle(parent: Node, refresh: Callable) -> Button:
	"""Swaps the card between the station and the species living there, and
	keeps the choice for the next chart."""
	var toggle := bar_button("",func(): pass,parent)
	toggle.text="Station" if stream_species else "Species"
	toggle.pressed.connect(func(): stream_species=not stream_species; toggle.text="Station" if stream_species else "Species"; refresh.call())
	return toggle
func show_station_card(id: int, facts: String, empty_title := "No exits") -> void:
	map_title.text=session.stations[id].name if id>=0 else empty_title
	map_info.text=facts
	for child in map_showcase.get_children(): map_showcase.remove_child(child); child.queue_free()
	if id<0: return
	if stream_species: show_habitat(id,map_showcase); return
	var preview=preload("res://native/presentation/station_preview.gd").new(); map_showcase.add_child(preview)
	preview.configure(view,world,id)
func map_key(parent: Node) -> HFlowContainer:
	"""Shows the markers rather than naming their colours, so the key is read by
	comparing it with the chart instead of by translating it. The routes and the
	waypoint are listed only while the chart is actually drawing them, which is
	also the only time anyone needs to ask what they are."""
	var flow := HFlowContainer.new(); flow.add_theme_constant_override("h_separation",16); flow.add_theme_constant_override("v_separation",4); parent.add_child(flow)
	# Each holding has two markers, not one: the dark square with the bright
	# centre is the same holding before you have been there, and listing only one
	# of the pair left the other unaccounted for on the chart.
	var entries := [
			{"body":"05bbff","core":"0d2170","text":"Colonist"},
			{"body":"0d2170","core":"05bbff","text":"Colonist, unvisited"},
			{"body":"65e53e","core":"14501a","text":"Resistance"},
			{"body":"14501a","core":"65e53e","text":"Resistance, unvisited"},
			{"body":"ff8000","core":"ffff00","text":"Your station"},
			{"body":"ff0000","core":"c00000","text":"Mission destination"},
			{"kind":"arrow","text":"You"},
			{"kind":"disc","text":"S.T.R.E.A.M. reach"},
			{"kind":"zone","text":"Zone in the side view"}]
	if session.trail.size()>1: entries.append({"kind":"trail","text":"Recent trips"})
	if world.autopilot and world.destination>=0: entries.append({"kind":"dash","tint":"97e4d3","text":"Autopilot route"})
	if world.stream_destination>=0: entries.append({"kind":"dash","tint":"bdabf2","text":"S.T.R.E.A.M. transfer"})
	if world.encounter_navigation_point()!=null: entries.append({"kind":"ring","tint":"91e4d4","text":"Encounter waypoint"})
	for entry in entries:
		var item := HBoxContainer.new(); item.add_theme_constant_override("separation",6); flow.add_child(item)
		item.add_child(map_marker(entry))
		var text := label(entry.text,14,item); text.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN; text.autowrap_mode=TextServer.AUTOWRAP_OFF
	return flow
func map_marker(entry: Dictionary) -> Control:
	var node := Control.new(); node.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	# A line needs a longer chip than a square does before it reads as dashed.
	node.custom_minimum_size=Vector2(29,19) if entry.get("kind","") in ["dash","trail"] else Vector2(19,19)
	node.draw.connect(func():
		# Each mark sits on a chip of the chart's own field, so the key is read
		# against the blue the chart is read against rather than the page's dark.
		# The true middle of the chip: a floored one put every mark half a
		# pixel up and left of centre, which shows on a 19 px chip.
		node.draw_rect(Rect2(Vector2.ZERO,node.size),Color("2f43b4"),true)
		var middle := node.size*0.5
		var kind: String = entry.get("kind","station")
		if kind=="disc":
			node.draw_circle(middle,8,Color("6e86ff4d"),true)
			node.draw_arc(middle,8,0,TAU,24,Color("9fb4ff"),1.5,true)
		elif kind=="zone":
			node.draw_arc(middle,6,0,TAU,16,Color("75ebe8"),1.5,true)
			for side in [Vector2.RIGHT,Vector2.DOWN,Vector2.LEFT,Vector2.UP]:node.draw_line(middle+side*6,middle+side*9,Color("75ebe8"),1.5)
		elif kind=="ring":
			node.draw_arc(middle,6,0,TAU,16,Color(entry.tint),2,true)
		elif kind=="trail":
			node.draw_line(middle+Vector2(-13,4),middle,Map.TRAIL[3],2,true)
			node.draw_line(middle,middle+Vector2(13,-4),Map.TRAIL[0],2,true)
		elif kind=="dash":
			node.draw_dashed_line(middle+Vector2(-13,0),middle+Vector2(13,0),Color(entry.tint),2,4)
		elif kind=="arrow":
			node.draw_colored_polygon(PackedVector2Array([middle+Vector2(0,-6),middle+Vector2(-4,5),middle+Vector2(4,5)]),Color("f4fafb"))
		else:
			Map.pixel_square(node,middle,11.0,3.0,Color(entry.body),Color(entry.core)))
	return node
func zone_stations(center: Vector2) -> Array:
	"""The stations inside the zone, west to east, as the side view lists them."""
	var ids: Array=[]
	for station in session.stations:
		if Vector2(station.x,station.y).distance_to(center)<=ZONE_RADIUS:ids.append(station.id)
	ids.sort_custom(func(a,b):return session.stations[a].x<session.stations[b].x or (session.stations[a].x==session.stations[b].x and a<b))
	return ids
func zone_choice(center: Vector2, near: int, current: int) -> int:
	"""Which station stays chosen when the zone moves: the one tapped, else the
	one already chosen if it is still inside. Nothing else is picked for the
	player; the side view is where they choose."""
	var ids:=zone_stations(center)
	if near in ids:return near
	if current in ids:return current
	return -1
func follow_drag(center: Vector2, current: int) -> void:
	"""While the zone is dragged the side view shows what it covers; the card
	and the choice wait for it to be let go."""
	map_slice.frame(center,ZONE_RADIUS,current if current in zone_stations(center) else -1)
func zone_prompt(center: Vector2) -> Array:
	"""The card's title and text while the zone has no station chosen."""
	if zone_stations(center).is_empty():return ["No stations here","Move the zone over a station, or pick one from the list."]
	return ["Choose a station","Pick one of the stations in the side view."]
func follow_zone(id: int) -> void:
	"""A station chosen from the list is brought under the zone, so the side
	view always shows the station the card describes."""
	var station: Dictionary=session.stations[id]
	var at:=Vector2(station.x,station.y)
	if at.distance_to(map_widget.lens_center)>ZONE_RADIUS:map_widget.place_lens(at)
	map_widget.selected_id=id;map_widget.queue_redraw()
	map_slice.frame(map_widget.lens_center,ZONE_RADIUS,id if at.distance_to(map_widget.lens_center)<=ZONE_RADIUS else -1)
func warn(text: String, bad: bool) -> String:
	return "[color=#ff6b6b]%s[/color]"%text if bad else text
func station_figures(id: int) -> Dictionary:
	"""The depth and S.T.R.E.A.M. distance as the card shows them, each in red
	when the ship cannot manage it. Being out of reach does not close a station
	off, since the autopilot still goes anywhere, so there is no line saying so;
	the red figure is the whole message."""
	var station: Dictionary=session.stations[id]
	var far: bool=world.stream_distance(id)>=world.stream_range()
	var unsafe: bool=station.depth<session.ship.minimum_depth or station.depth>session.ship.maximum_depth
	return {"far":far,"unsafe":unsafe,"depth":warn(str(station.depth),unsafe),"distance":warn("%.1f"%world.map_kilometers(world.stream_distance(id)),far)}
func tech_text(id: int) -> String:
	# The original reads the tech level only for a station already visited.
	return str(session.stations[id].tech) if session.discovered[id] or id==session.station_id else "?"
func select_station(id: int) -> void:
	map_destination=id;map_unchosen=false
	follow_zone(id)
	map_picker.select(id)
	if is_instance_valid(map_route_button):map_route_button.disabled=false
	var denial: String = world.stream_denial(id)
	var figures:=station_figures(id)
	var status := "Ready · transfer at the gate"
	if id==session.station_id: status="Current area"
	elif figures.far: status=""
	elif not denial.is_empty(): status="Locked by the current mission"
	elif figures.unsafe: status=session.text(255)
	show_station_card(id,"%s · %s\nTec Level: %s · Depth: %s\nS.T.R.E.A.M. %s / %.1f km%s"%[
		"Rebels" if session.campaign.rebel_stations[id] else "Colonists","Discovered" if session.discovered[id] else "Unexplored",tech_text(id),figures.depth,
		figures.distance,world.map_kilometers(world.stream_range()),"" if status.is_empty() else "\n"+status])
	map_info.tooltip_text=denial
	if is_instance_valid(stream_button): stream_button.tooltip_text=denial if not denial.is_empty() else "Autopilot to the gate, then confirm your exit in transit control."
	if is_instance_valid(stream_button): stream_button.disabled=not denial.is_empty()
func contact_priority(target: Dictionary) -> int:
	if target.get("quest",false):return -2
	if str(target.key)=="station":return -1
	if typeof(target.key)==TYPE_INT:
		if int(target.key)==focused_contact:return 0
		return 3 if target.get("role","")=="enemy" else 4
	return 1 if str(target.key) in ["waypoint","stream","stream_in"] else 2

func focus_creature() -> int:
	# A sticky aim cone identifies one animal, rather than labelling every school.
	var radius:=minf(ui.size.x,ui.size.y)*.16
	var best:=0;var score:=INF;var retained_score:=INF
	for actor in world.region.creatures:
		if not actor.health.enabled or actor.subdued:continue
		var point: Vector3=world.render_pose(actor).origin
		if camera.is_position_behind(point) or point.distance_to(camera.global_position)>650:continue
		var offset:=camera.unproject_position(point)-ui.position-ui.size*.5
		var distance:=offset.length()
		var id: int=actor.get_instance_id()
		if distance>radius*(1.35 if id==focused_contact else 1.0):continue
		var ray:=PhysicsRayQueryParameters3D.create(camera.global_position,point,2);ray.hit_back_faces=true
		if not view.get_world_3d().direct_space_state.intersect_ray(ray).is_empty():continue
		if id==focused_contact:retained_score=distance
		if distance<score:score=distance;best=id
	if retained_score<INF and (best==focused_contact or score>retained_score*.55):return focused_contact
	return best

func station_contacts() -> Array:
	var quest_ids := {}
	for mission in [session.campaign.primary,session.campaign.secondary]:
		if mission.kind>=0 and not mission.completed and not mission.failed and not mission.destination_name.is_empty() and mission.destination>=0 and mission.destination<session.stations.size():quest_ids[mission.destination]=true
	var ids: Array=[session.station_id]
	for id in quest_ids:
		if not id in ids:ids.append(id)
	var nearby: Array=view.neighbors.keys()
	nearby.sort_custom(func(a,b):return world.geography.stations[a].distance_squared_to(camera.global_position+world.geography.anchor)<world.geography.stations[b].distance_squared_to(camera.global_position+world.geography.anchor))
	for id in nearby:
		if not id in ids and world.geography.stations[id].distance_to(camera.global_position+world.geography.anchor)<2500 and ids.size()<6:ids.append(id)
	var result: Array=[]
	for id in ids:
		var position: Vector3=world.geography.stations[id]-world.geography.anchor
		var nodes: Array=view.station_nodes if id==session.station_id else (view.neighbors[id].root.get_children() if view.neighbors.has(id) else [])
		var bounds := AABB();var first := true
		for node in nodes:
			if not node.has_method("solid_bounds"):continue
			var box: AABB=node.global_transform*node.solid_bounds()
			bounds=box if first else bounds.merge(box);first=false
		if not first:position=Vector3(bounds.get_center().x,bounds.end.y+8,bounds.get_center().z)
		result.append({"key":"station" if id==session.station_id else "station:"+str(id),"p":[0,0,0],"position":position,"name":session.stations[id].name,"color":Color("e5ce86") if quest_ids.has(id) else Color("7bd2d6"),"edge":id==session.station_id or quest_ids.has(id),"hull":-1.0,"station_contact":true,"quest":quest_ids.has(id)})
	return result

func update_markers() -> void:
	if not page.is_empty() or world.region.cinematic() or view.transit_progress>=0:
		for marker in markers: marker.hide()
		return
	var region=world.region
	focused_contact=focus_creature()
	var radar: int = session.ship.passive_radar
	var targets: Array = station_contacts()
	# With separate gates each tag says which way its gate goes.
	var gate_title: String="S.T.R.E.A.M. OUT" if region.gate_index(1)==1 else "S.T.R.E.A.M."
	var gate_name: String = gate_title+" > "+session.stations[world.stream_destination].name if world.stream_destination>=0 else gate_title+" · "+session.stations[session.station_id].name
	if world.at_gate(world.departure_gate):
		gate_name=gate_title+" · "+(("Transit control" if world.stream_destination>=0 else "Choose destination") if world.gate_time[world.departure_gate]>=world.GATE_OPEN_MS else "Opening" if world.region.success==null and world.region.failure==null and not world.tutorial_travel_locked() else "Locked")
	targets.append({"key":"stream","p":region.gates[world.departure_gate],"name":gate_name,"color":Color("bdabf2"),"edge":world.stream_destination>=0,"hull":-1.0})
	if region.gate_index(1)==1:
		# The arrival gate is named too, so it is not taken for the way out.
		targets.append({"key":"stream_in","p":region.gates[1],"name":"S.T.R.E.A.M. IN · "+session.stations[session.station_id].name,"color":Color("8f86b0"),"edge":false,"hull":-1.0})
	for id in view.neighbors:
		for visual in view.neighbors[id].root.get_children():
			if not visual is Model or not visual.has_meta("neighbor_gate"):continue
			if visual.global_position.distance_to(preload("res://scripts/model_library.gd").point(region.player.pose.origin))>2500.0:continue
			targets.append({"key":"stream:"+str(id),"p":[0,0,0],"position":visual.global_position,"name":str(visual.get_meta("gate_title","S.T.R.E.A.M."))+" · "+session.stations[id].name,"color":Color("ac9ac9"),"edge":true,"hull":-1.0})
	if world.autopilot and world.local_target!=null and world.stream_destination<0:
		targets.append({"key":"waypoint","p":world.local_target,"name":session.stations[world.destination].name if world.destination>=0 else "Autopilot","color":Color("e5ce86"),"edge":true,"hull":-1.0})
	elif world.encounter_navigation_point()!=null: targets.append({"key":"waypoint","p":world.encounter_navigation_point(),"name":"Encounter waypoint","color":Color("e5ce86"),"edge":radar>0,"hull":-1.0})
	for role in ["friend","enemy","creature"]:
		var actors: Array = region.friends if role=="friend" else (region.enemies if role=="enemy" else region.creatures)
		for actor in actors:
			var entry: Dictionary = Scanner.describe(actor,role,radar,region.mission.kind,region.player.pose.origin)
			if role=="creature":
				entry.visible=actor.get_instance_id()==focused_contact;entry.identify=entry.visible;entry.edge=false
			if not entry.visible: continue
			entry.p=actor.pose.origin; entry.actor=actor; entry.key=actor.get_instance_id()
			entry.name="Friendly" if role=="friend" else ("Protected school" if role=="creature" and region.mission.kind==6 else "Contact")
			entry.color=Color("ef9b83") if role=="enemy" else Color("85bda4")
			if entry.recoverable: entry.name="Rescue" if actor.protected_target else "Salvage"; entry.color=Color("e5ce86")
			targets.append(entry)
	targets.sort_custom(func(a,b):return contact_priority(a)<contact_priority(b))
	# Keep each contact's controls while it remains scannable. Filtering one
	# contact must not reassign and reshape all the later labels in the pool.
	var keys := {}; var assigned := {}; var available: Array = []; var shown := {}
	for target in targets: keys[target.key]=true
	for key in marker_by_contact.keys():
		if not keys.has(key): marker_by_contact.erase(key)
		else: assigned[marker_by_contact[key]]=true
	for index in range(markers.size()-1,-1,-1):
		if not assigned.has(index): available.append(index)
	var occupied: Array[Rect2] = [instruments.gauge_rect().grow(24),condition.get_global_rect()]
	for feedback in [hazard_warning,catch_status,struggle,travel_status,message]:
		if feedback.visible and (not feedback is Label or not feedback.text.is_empty()):occupied.append(feedback.get_global_rect())
	for target in targets:
		if shown.size()>=MAX_CONTACT_LABELS and target.get("role","")!="enemy":continue
		var position: Vector3 = world.render_pose(target.actor).origin if target.has("actor") else target.get("position",preload("res://scripts/model_library.gd").point(target.p))
		var distance: float = position.distance_to(preload("res://scripts/model_library.gd").point(region.player.pose.origin))
		var camera_space: Vector3 = camera.global_transform.affine_inverse()*position
		# Perspective projection is undefined exactly on the camera plane.
		var screen: Vector2 = ui.size/2+Vector2(camera_space.x,-camera_space.y).normalized()*ui.size.length()*2 if absf(camera_space.z)<0.001 else camera.unproject_position(position)-ui.position
		var behind: bool = camera.is_position_behind(position)
		var reverse_edge: bool=behind and absf(camera_space.z)>=.001
		var enemy: bool=target.get("role","")=="enemy" and not target.get("recoverable",false)
		var on_screen: bool = not behind and Rect2(Vector2(20,160),ui.size-Vector2(40 if enemy else 200,315)).has_point(screen)
		if not on_screen and not target.edge: continue
		if on_screen and target.get("role","")=="creature":
			var ray:=PhysicsRayQueryParameters3D.create(camera.global_position,position,2)
			ray.hit_back_faces=true
			if not view.get_world_3d().direct_space_state.intersect_ray(ray).is_empty():continue
		var detail := "\nQuest destination" if target.get("quest",false) else ""
		if on_screen and target.get("identify",false) and (target.get("role","")=="creature" or Scanner.in_scan_window(screen,ui.size)):
			var actor=target.actor
			if actor.is_creature:
				target.name="Meat" if actor.meat else item_name(actor.species)
				detail="\n%d t · Cargo %d / %d"%[actor.mass,session.ship.cargo_used,session.ship.capacity()]
			else:
				if not target.recoverable: target.name=content.ship_name(actor.original_model_id) if actor.original_model_id<content.data.tables.ships.size() else ("Mine" if actor.model_id==13 else "Contact")
				if actor.capturable and actor.loot!=null: detail="\n%s · %d t"%[item_name(actor.loot.id),actor.loot.owned]
		elif target.get("role","")=="creature" and region.mission.kind!=6: continue
		var anchor:=screen
		var direction: Vector2 = Vector2.ZERO if on_screen else Scanner.edge_direction(screen,ui.size,reverse_edge).normalized()
		if not on_screen: screen=Scanner.edge_position(screen,ui.size,reverse_edge,enemy)
		if not marker_by_contact.has(target.key):
			if available.is_empty(): continue
			marker_by_contact[target.key]=available.pop_back()
		var i: int = marker_by_contact[target.key]
		markers[i].set_symbol(direction);markers[i].quest=target.get("quest",false)
		markers[i].display(target.name+" · ",RangeText.format_distance(distance),detail,target.color,float(target.hull) if on_screen else -1.0)
		if enemy and not on_screen:markers[i].track_enemy(screen,18,true)
		screen+=Vector2(24,12) if on_screen and enemy else Vector2(14,10) if on_screen else Vector2.ZERO
		screen.x=clampf(screen.x,12,maxf(12,ui.size.x-markers[i].size.x-12))
		screen.y=clampf(screen.y,160,maxf(160,ui.size.y-markers[i].size.y-155))
		# Keep labels attached to their contacts; suppress overlaps instead of
		# shuffling them through a stack of unrelated positions on every tick.
		var area:=Rect2(screen,markers[i].size)
		var overlap: bool=dashboard.visible and area.intersects(Rect2(ui.size.x-310,ui.size.y-305,310,305))
		for previous in occupied:
			if previous.grow(6).intersects(area):overlap=true;break
		if overlap and target.get("station_contact",false):
			# Navigation labels are essential. Try nearby clear slots instead of
			# silently dropping the station when a notice crosses its anchor.
			for offset in [Vector2(0,-48),Vector2(0,48),Vector2(-180,-48),Vector2(180,-48),Vector2(0,-96)]:
				var candidate: Vector2 = (screen+offset).clamp(Vector2(12,160),Vector2(maxf(12,ui.size.x-markers[i].size.x-12),maxf(160,ui.size.y-markers[i].size.y-155)))
				var candidate_area := Rect2(candidate,markers[i].size)
				if not occupied.any(func(previous):return previous.grow(6).intersects(candidate_area)):
					screen=candidate;area=candidate_area;overlap=false;break
			if str(target.key)=="station" or target.get("quest",false):overlap=false
		if overlap and not enemy:markers[i].hide();continue
		occupied.append(area)
		markers[i].position=screen; shown[i]=true
		if enemy:
			var radius:=18.0
			if on_screen and view.objects.has(target.key):
				var extent: float=view.objects[target.key].visual.solid_bounds().size.length()*.3
				radius=clampf(anchor.distance_to(camera.unproject_position(position+camera.global_basis.x*extent)-ui.position),12,65)
			markers[i].track_enemy(anchor,radius,not on_screen,not overlap)
	for unused in markers.size():
		if not shown.has(unused): markers[unused].hide()
func _exit_tree() -> void:
	if is_instance_valid(get_window()):
		if get_window().size_changed.is_connected(update_render_resolution): get_window().size_changed.disconnect(update_render_resolution)
		get_window().content_scale_size=original_ui_size
	release_flight_mouse()

	world.dispose()

func art_image(texture: Texture2D, parent: Node, extent: int) -> TextureRect:
	if texture==null: return null
	var rect := TextureRect.new(); rect.texture=texture
	rect.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; rect.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.custom_minimum_size=Vector2(extent,extent); rect.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN; rect.size_flags_vertical=Control.SIZE_SHRINK_BEGIN
	rect.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	parent.add_child(rect); return rect
func current_objective():
	if world.region!=null and (world.region.success!=null or world.region.failure!=null) and world.region.mission.kind>=0 and not world.region.mission.completed and not world.region.mission.failed:return world.region.mission
	return session.campaign.primary
func objective_has_location(mission) -> bool:
	return mission.kind>=0 and not mission.completed and not mission.failed and (world.encounter_navigation_point()!=null or (mission.kind in [0,1,2,3,4,5,6,7,8,9,10,11,12,13,14] and mission.destination>=0))
func objective_summary(mission) -> String:
	if mission.kind<0:return "Explore the ocean"
	var info=preload("res://native/presentation/mission_info.gd")
	var lines: Array[String]=[session.title(mission)]
	var instruction: String=info.instruction(mission)
	if not instruction.is_empty():lines.append(instruction)
	var target: String=info.target(session,mission)
	if not target.is_empty():lines.append(target)
	var progress: String=info.progress(session,mission)
	if not progress.is_empty():lines.append(progress)
	if world.region!=null and world.region.mission==mission:
		var encounter: String=info.encounter_progress(world.region)
		if not encounter.is_empty():lines.append(encounter)
	if objective_has_location(mission):lines.append("Hold %s to auto-navigate"%OS.get_keycode_string(key_bindings.autopilot))
	return "\n".join(lines)
var objective_shown := ""
func show_objective(text: String, mission) -> void:
	"""Fills the HUD objective, with the creature a fishing job is about drawn
	in front of its line. Rebuilt only when it changes."""
	var info=preload("res://native/presentation/mission_info.gd")
	var species: int=info.target_species(mission) if mission!=null else -1
	var key: String=text+"|%d"%species
	if key==objective_shown:return
	objective_shown=key;objective_label.clear()
	var target: String=info.target(session,mission).replace("[","[lb]") if species>=0 else ""
	var icon: Texture2D=imported_art.item(species) if species>=0 else null
	var lines: PackedStringArray=text.split("\n")
	for index in lines.size():
		if index>0:objective_label.append_text("\n")
		if icon!=null and not target.is_empty() and lines[index]==target:
			objective_label.add_image(icon,26,20,Color.WHITE,INLINE_ALIGNMENT_CENTER);objective_label.append_text(" ")
		objective_label.append_text(lines[index])
func objective_hud(mission) -> String:
	var summary: PackedStringArray=objective_summary(mission).split("\n")
	var result: Array[String]=["[font_size=10][color=#87a8b3]CURRENT OBJECTIVE[/color][/font_size]", "[font_size=16][color=#e4ce92]"+summary[0].replace("[","[lb]")+"[/color][/font_size]"]
	for index in range(1,summary.size()):
		var text: String=summary[index].replace("[","[lb]")
		if summary[index].begins_with("Hold "):result.append("\n[font_size=11][color=#8acdc7]"+text+"[/color][/font_size]")
		elif summary[index].contains(" / "):result.append("[color=#a7dfc8]"+text+"[/color]")
		else:result.append(text)
	return "\n".join(result)
func autonavigate_objective() -> void:
	auto_fire=false
	var mission=current_objective()
	if world.encounter_navigation_point()!=null:
		world.navigate_encounter();close_page()
	elif objective_has_location(mission):
		if world.route_to(mission.destination):close_page()
		else:notice(world.message)
	else:notice("This objective has no fixed destination. "+preload("res://native/presentation/mission_info.gd").instruction(mission))
func show_destinations() -> void:
	open_page("Autopilot","destinations")
	var mission=current_objective()
	label(objective_summary(mission),15).modulate=Color("ddca92")
	var objective_action:=button("Navigate to quest objective",autonavigate_objective)
	objective_action.disabled=not objective_has_location(mission)
	var actions:=GridContainer.new();actions.columns=2;actions.add_theme_constant_override("h_separation",10);column.add_child(actions)
	var dock_locked: bool=world.region.success!=null or world.region.failure!=null
	var dock_action := button("Docking locked · encounter active" if dock_locked else "Dock at "+session.stations[session.station_id].name,func(): world.route_to(session.station_id); close_page(),actions)
	dock_action.disabled=dock_locked
	button("Approach S.T.R.E.A.M. gate",func():
		var gate: int=world.nearest_safe_gate()
		if gate<0:notice("No S.T.R.E.A.M. gate in this area.");return
		world.fly_to_gate(gate);close_page(),actions)
	button("Choose station on chart",func():show_map(true),actions)
	if world.autopilot:button("Disengage autopilot",func():world.cancel_autopilot("Manual control");close_page(),actions)
	label("%s: 1× / 2× in flight · up to 16× on autopilot"%OS.get_keycode_string(key_bindings.time),12)
func say_hint(key: String,text: String) -> bool:
	if not gameplay_hints or session.hints_said.has(key) or text.is_empty():return false
	session.hints_said[key]=true
	show_dialogue([{"speaker":"M.A.I.","portrait":[-1],"text":text}],close_page)
	return true
func check_flight_hints() -> void:
	"""What M.A.I. says once, the first time it comes up in the water: the
	gate, the dock, the radiation and the pressure, the booster she wants,
	the catch that got away and the hold that is full."""
	var r=world.region
	if r==null or session.docked or r.cinematic() or r.failed:return
	var chapter: int=session.campaign.chapter
	if world.at_gate(world.departure_gate) and chapter>2 and not (chapter==6 and r.mission.kind==0):
		if say_hint("gate",session.text(342)):return
	if flight_ms>20000 and (r.station.can_dock(r.player.pose.origin) or Vector3(r.player.pose.origin[0],r.player.pose.origin[1],r.player.pose.origin[2]).length()<25000):
		if say_hint("dock",session.text(343)):return
	if r.player.depth<session.ship.minimum_depth and say_hint("radiation",session.text(344)):return
	if r.player.depth>session.ship.maximum_depth and say_hint("pressure",session.text(345)):return
	if chapter>14 and flight_ms>20000 and session.ship.boost_cooldown<=0 and r.enemies.is_empty():
		if say_hint("booster",session.text(347)):return
	if int(session.counters.i)==1 and say_hint("escaped",session.text(348)):return
	if hold_full_seen and chapter!=7 and r.mission.kind!=1 and say_hint("hold",session.text(349)):return
func check_dock_hints() -> void:
	"""What the station has to say on arrival (ch.d): the booster's card the
	first time one is aboard, the two story asides of chapters 16 and 18,
	and the medal collection's rewards."""
	var chapter: int=session.campaign.chapter
	if session.ship.boost_cooldown>0 and say_hint("booster_card",session.text(346)):return
	if chapter==16 and session.station_id!=5 and say_hint("intranet%d"%session.station_id,session.text(280,session.name)):return
	if chapter==18 and not session.is_colonist_station() and session.station_id!=6 and say_hint("nothing%d"%session.station_id,session.text(281)):return
	if session.medals.complete_set() and say_hint("all_medals",session.text(350)):return
	if session.medals.gold_set() and say_hint("all_gold",session.text(351)):return
	if session.campaign.finished() and not session.medals.complete_set() and say_hint("hero",session.text(352)):return
var hold_full_seen := false
## The phone game's Vibration option: a buzz of 110 ms when the hull takes
## a hit (bb), on a pad's rumble or a handheld's motor.
var vibration := true
var hull_seen := -1
func buzz(duration_ms: int) -> void:
	if not vibration:return
	if controller.device>=0:Input.start_joy_vibration(controller.device,0.6,0.9,duration_ms/1000.0)
	if OS.has_feature("mobile") or OS.has_feature("android"):Input.vibrate_handheld(duration_ms)
func check_hull_buzz() -> void:
	var r=world.region
	if r==null:hull_seen=-1;return
	if hull_seen>=0 and r.player.health.hull<hull_seen:buzz(110)
	hull_seen=r.player.health.hull
func check_stream_proximity() -> void:
	# The chart must not reopen over the shot of the submarine leaving the far
	# aperture: it arrives at a gate that is already open, and inside range of it.
	if view.transit_progress>=0:return
	if not world.at_gate(world.departure_gate): stream_prompted=false; return
	# br.a: a pilot at the open gate is told to press the dock key (text 270)
	# and nothing opens until it is pressed. Only a ship the autopilot brought
	# to the gate goes on to the chart by itself.
	if not (world.autopilot and world.gate_navigation):return
	if world.gate_time[world.departure_gate]<world.GATE_OPEN_MS: return
	if not stream_prompted: show_stream_menu()

func update_render_resolution() -> void:
	if not is_inside_tree(): return
	var pixels := get_window().size
	if pixels.x<=0 or pixels.y<=0: return
	var virtual_width := 1280 if touch.enabled() else clampi(pixels.x,1280,1920)
	var virtual_size := Vector2i(virtual_width,roundi(virtual_width*float(pixels.y)/pixels.x))
	# Held upright, the long side is 1280 as it is held landscape, so every
	# control and line of text keeps its size on the same phone.
	if touch.enabled() and pixels.y>pixels.x: virtual_size=Vector2i(roundi(1280.0*pixels.x/pixels.y),1280)
	Display.apply(get_window(),aspect_ratio,virtual_size)
	apply_side_margins()
	var budget: float = [1920.0*1080.0,2560.0*1440.0,999999999.0][clampi(render_quality,0,2)]
	get_viewport().scaling_3d_scale=clampf(sqrt(budget/maxf(1,pixels.x*pixels.y)),0.35,1.0) if modern_graphics else 1.0
	get_viewport().scaling_3d_mode=Viewport.SCALING_3D_MODE_FSR if RenderingServer.get_current_rendering_method()=="forward_plus" else Viewport.SCALING_3D_MODE_BILINEAR
	get_viewport().use_taa=modern_graphics and temporal_aa
func apply_side_margins() -> void:
	"""Insets the interface from a phone's notch and rounded corners on both
	sides; the 3D view behind it still fills the screen."""
	var margin: Dictionary=SafeMargins.margins(get_viewport().get_visible_rect().size,get_window().size,touch.enabled())
	if ui.offset_left!=margin.side or ui.offset_right!=-margin.side or ui.offset_top!=margin.top or ui.offset_bottom!=-margin.bottom:
		ui.offset_left=margin.side;ui.offset_right=-margin.side;ui.offset_top=margin.top;ui.offset_bottom=-margin.bottom
	# The pressure tint covers the whole picture, not only the inset interface.
	pressure_overlay.offset_left=-margin.side;pressure_overlay.offset_right=margin.side
	pressure_overlay.offset_top=-margin.top;pressure_overlay.offset_bottom=margin.bottom
func volume_slider(title: String, value: float, changed: Callable) -> void:
	label(title,16)
	var slider := HSlider.new(); slider.min_value=0; slider.max_value=1; slider.step=0.05; slider.value=value
	column.add_child(slider); slider.value_changed.connect(changed)

func show_stream_menu() -> void:
	if not world.at_gate(world.departure_gate): return
	stream_prompted=true
	if world.stream_destination>=0: stream_selection=world.stream_destination
	# The chart stops the submarine, so what it was doing has to be remembered
	# here or the far side hands back a dead stop. Only the first open sees
	# the real throttle. A notch is the floor because a crossing cannot put
	# anyone down stationary.
	if page!="stream": stream_resume_throttle=maxi(world.region.player.throttle_target,25)
	world.cancel_autopilot(); world.region.player.set_throttle(0)
	open_page(chart_title(),"stream")
	view.gate_preview=true
	var eligible: Array=[]
	for station in session.stations:
		if world.stream_denial(station.id).is_empty(): eligible.append(station.id)
	if not stream_selection in eligible: stream_selection=eligible[0] if not eligible.is_empty() else -1
	var actions := station_chart(stream_selection)
	var options := OptionButton.new();options.custom_minimum_size.x=210;actions.add_child(options)
	for id in eligible: options.add_item(str(session.stations[id].name),id)
	options.disabled=eligible.size()<2
	var species := species_toggle(actions,func(): pass)
	var gap := Control.new(); gap.size_flags_horizontal=Control.SIZE_EXPAND_FILL; actions.add_child(gap)
	var confirm := bar_button("INITIATE TRANSIT  >",begin_stream_transit,actions)
	bar_button("Back",dock_back,actions)
	# As on the original's gate chart, the zone moves only within the reach, so
	# whatever it covers is a crossing this engine can make at least as far.
	var home: Dictionary=session.stations[session.station_id]
	map_widget.lens_limit=maxf(world.stream_range()-ZONE_RADIUS,0)
	var first: Dictionary=session.stations[stream_selection] if stream_selection>=0 else home
	map_widget.place_lens(Vector2(first.x,first.y))
	var select := func(id):
		stream_selection=id
		if id<0:
			map_widget.selected_id=-1;map_widget.queue_redraw();map_slice.frame(map_widget.lens_center,ZONE_RADIUS,-1)
			var prompt:=zone_prompt(map_widget.lens_center)
			if eligible.is_empty():prompt=["No exits","No exits in range. Fit a longer-range engine."]
			show_station_card(-1,prompt[1],prompt[0])
			confirm.disabled=true;return
		follow_zone(id)
		var station: Dictionary=session.stations[id]
		var index := options.get_item_index(id)
		if index>=0: options.select(index)
		var denial: String=world.stream_denial(id)
		# The original reads out who holds the station, its tech level and its
		# depth. The reach and distance are this engine's own, and matter here.
		var figures:=station_figures(id)
		var status: String=(session.text(255) if figures.unsafe else "Exit ready") if denial.is_empty() else "" if figures.far else denial
		show_station_card(id,"%s\nTec Level: %s · Depth: %s\nDistance %s km · reach %.1f km%s"%[
			"Rebels" if session.campaign.rebel_stations[id] else "Colonists",tech_text(id),figures.depth,
			figures.distance,world.map_kilometers(world.stream_range()),"" if status.is_empty() else "\n"+status])
		confirm.disabled=not denial.is_empty()
	species.pressed.connect(func(): select.call(stream_selection))
	map_slice.selected.connect(select)
	map_widget.zone_dragged.connect(func(center):follow_drag(center,stream_selection))
	map_widget.zone_moved.connect(func(center,near):select.call(zone_choice(center,near,stream_selection)))
	options.item_selected.connect(func(at): select.call(options.get_item_id(at)))
	select.call(stream_selection)

func show_habitat(id: int, parent: Node) -> void:
	"""Which species live at a station, and which of them this expedition has
	already caught. Every station carries six, stored as pairs of species and a
	constant weight; only the species half is meaningful to a reader."""
	var habitat: Array = content.data.habitats[id] if id>=0 and id<content.data.habitats.size() else []
	label("SPECIES FOUND HERE",13,parent).modulate=Color("93b5aa")
	# Two columns, so the six fit beside the card's figures.
	var grid := GridContainer.new();grid.columns=2;grid.add_theme_constant_override("h_separation",14);grid.add_theme_constant_override("v_separation",2);parent.add_child(grid)
	var seen := {}
	for index in range(0,habitat.size(),2):
		var species := int(habitat[index])
		if seen.has(species): continue
		seen[species]=true
		var known: bool = species<session.fish_found.size() and session.fish_found[species]
		var line := HBoxContainer.new();line.add_theme_constant_override("separation",8);line.size_flags_horizontal=Control.SIZE_EXPAND_FILL;grid.add_child(line)
		var icon := TextureRect.new();icon.texture=imported_art.item(species);icon.custom_minimum_size=Vector2(34,28)
		icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		if not known: icon.modulate=Color(1,1,1,.3)
		line.add_child(icon)
		var name_label := label(item_name(species) if known else "Unrecorded",15,line)
		name_label.modulate=Color("d7edf1") if known else Color("6d8894")
		name_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		if known: label("caught",12,line).modulate=Color("c9ae79")
var safety_confirmed := -1
func ask_outside_safety(id: int, go: Callable, back: Callable) -> bool:
	"""The original's chart asks before a trip outside the hull's depth
	limits instead of refusing it: the destination (334), the warning (255)
	and "Travel to this station?" (247). True while the question is open;
	answering yes runs go again with the answer recorded."""
	if safety_confirmed==id: safety_confirmed=-1;return false
	if not world.outside_safety(id): return false
	confirm(session.text(334)+": "+session.stations[id].name,session.text(255)+"\n"+session.text(247),"Travel",
		func():safety_confirmed=id;go.call(),back)
	return true
func begin_stream_transit() -> void:
	"""Confirming a destination is the crossing. The original does not fly the
	submarine into the aperture and wait: the chart closes, the far side is
	already there, and what the player watches is the way out of it. So there is
	no run-up to steer, nothing to arm and no notice to read."""
	var denial: String=world.stream_denial(stream_selection)
	if not denial.is_empty() or not world.at_gate(world.departure_gate):notice(denial);return
	if ask_outside_safety(stream_selection,begin_stream_transit,show_stream_menu):return
	world.cancel_autopilot();world.gate_navigation=false;world.approach_planned=false;world.approach_path.clear()
	# The chart can be opened (E) before the aperture has finished opening,
	# and nothing advances while it is up, so the gate would stay part open
	# and refuse the crossing however often it was confirmed. Confirming at
	# the gate is the order to open it.
	world.gate_time[world.departure_gate]=maxi(world.gate_time[world.departure_gate],world.GATE_OPEN_MS)
	close_page()
	# Every region sits on one side of its gate, so that is the side a submarine
	# comes out on: just clear of the aperture, pointed at the station. Nothing
	# was flown to get here, so there is no approach pose to carry across.
	if not cross_stream(Transform3D(Basis(),Vector3(0,0,-STREAM_STANDOFF))): notice(world.message)
func cross_stream(arrival_local: Transform3D) -> bool:
	"""Move the expedition to the chosen region and open the shot on the far
	aperture. arrival_local is where the submarine comes out, in the coordinates
	of the gate it comes out of."""
	world.stream_destination=stream_selection
	if not world.stream_transfer(): view.clear_player_clip();view.end_transit();return false
	view.rebuild()
	var exit: Transform3D=view.gate_nodes[world.region.gate_index(1)].get_meta("gate_rest",view.gate_nodes[world.region.gate_index(1)].global_transform)
	var arrival: Transform3D=exit*arrival_local
	world.region.player.pose.origin=[roundi(arrival.origin.x*100),roundi(-arrival.origin.y*100),roundi(-arrival.origin.z*100)]
	view.assign_player_basis(arrival.basis)
	world.previous_render_poses.clear();stream_exit_active=true;stream_exit_frame=exit
	view.clip_player_at_gate(exit,-1.0);dive_audio.cue("gate")
	# Only the way out is framed.
	view.begin_transit(exit,-1.0);view.transit_emerging=true
	transit_exit_elapsed=0.0
	# Out of the gate hard, then back down to the speed that was being flown, so
	# control returns at the pace the player left off at.
	transit_exit_throttle=stream_resume_throttle
	transit_exit_factor=world.region.player.speed_factor
	world.region.player.throttle=100;world.region.player.set_throttle(100)
	world.region.player.speed_factor=STREAM_EXIT_FACTOR
	return true
func advance_transit_view(seconds: float) -> void:
	"""The far side of a crossing, on a clock. The crossing itself is instant, so
	the only thing there is to show is the submarine leaving the far aperture and
	making for the station."""
	if view.transit_progress<0: return
	if world.region==null or session.docked or view.player_model==null: end_transit_shot(); return
	# A menu, a briefing or an arrival dialogue ends the moment the shot was for.
	# Leaving it running would park the camera at the aperture behind them.
	if not page.is_empty(): end_transit_shot(); return
	if view.transit_emerging:
		transit_exit_elapsed+=minf(maxf(seconds,0.0),.1)
		view.transit_progress=clampf(transit_exit_elapsed/TRANSIT_EXIT_SECONDS,0,1)
		# Thrown clear of the aperture, then easing back to what was being flown.
		# Throttle alone tops out at the speed of ordinary flight, so the launch
		# is carried by the speed multiplier and handed back to it.
		world.region.player.set_throttle(roundi(lerpf(100.0,transit_exit_throttle,smoothstep(.25,1.0,view.transit_progress))))
		world.region.player.speed_factor=lerpf(STREAM_EXIT_FACTOR,transit_exit_factor,smoothstep(.10,.80,view.transit_progress))
		if view.transit_progress>=1.0: end_transit_shot()
		return
	end_transit_shot()
func end_transit_shot() -> void:
	"""Hand the submarine back. The launch is a temporary speed multiplier and
	has to come off however the shot ends, including early."""
	if view.transit_emerging and world.region!=null:
		world.region.player.speed_factor=transit_exit_factor
		world.region.player.set_throttle(roundi(transit_exit_throttle))
	view.end_transit()
func equipment_browser(station: Dictionary, ships: bool=false) -> void:
	var entries: Array=[]
	var kind := "ships" if ships else "equipment"
	var palette := colours()
	if ships:
		for item in station.ships: entries.append({"item":item,"buy":true})
	elif equipment_tab==0:
		for item in station.equipment: entries.append({"item":item,"buy":true})
	else:
		for item in session.ship.equipment:
			if item!=null: entries.append({"item":item,"buy":false})
	if not ships:
		# The ship being outfitted, its free slots and its hold.
		# The ship line opens the ship page, and Back from there returns here.
		var holder := button("",func():show_ship_status(func():show_market("equipment")),ship_strip if is_instance_valid(ship_strip) else column)
		holder.name="ShipLine";holder.accessibility_name=content.ship_name(session.ship.id);holder.tooltip_text="Ship and cargo"
		holder.custom_minimum_size.y=52 if ui.size.y<700 else 56
		var strip := HBoxContainer.new();strip.add_theme_constant_override("separation",16);holder.add_child(strip)
		strip.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);strip.offset_left=14;strip.offset_right=-14;strip.mouse_filter=Control.MOUSE_FILTER_IGNORE
		var hull := art_image(imported_art.item(session.ship.id,"ships"),strip,40)
		if hull!=null: hull.custom_minimum_size.x=64;hull.size_flags_vertical=Control.SIZE_SHRINK_CENTER
		caption(content.ship_name(session.ship.id),18,strip,4).add_theme_color_override("font_color",palette.text)
		var used: int=session.ship.equipment.filter(func(item):return item!=null).size()
		caption("%d / %d EQUIPMENT SLOTS  ·  CARGO %d / %d t"%[used,session.ship.slots,session.ship.cargo_used,session.ship.capacity()],12,strip,2).size_flags_vertical=Control.SIZE_SHRINK_CENTER
		line_icon("next",18,strip)
	if entries.is_empty(): label("No ships available at this station." if ships else "No equipment for sale at this station." if equipment_tab==0 else "No equipment installed. Choose Shop to fit a system.").add_theme_color_override("font_color",palette.dim);return
	market_selection=clampi(market_selection,0,entries.size()-1)
	var row := split_row(column,18)
	var list := VBoxContainer.new();list.name="StockRows";list.size_flags_horizontal=Control.SIZE_EXPAND_FILL;list.add_theme_constant_override("separation",6);row.add_child(list)
	var headings := HBoxContainer.new();list.add_child(headings)
	caption("SHIPS FOR SALE" if ships else "SHOP STOCK" if equipment_tab==0 else "INSTALLED SYSTEMS",12,headings,3)
	var value_heading := caption("VALUE",12,headings,3);value_heading.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	var row_height: int=(76 if ships else 64) if touch.enabled() else (72 if ships else 60)
	var page_size := clampi(int((ui.size.y-(330 if ui.size.x>=900 else 900))/(row_height+6)),3,8)
	market_page=clampi(market_page,0,(entries.size()-1)/page_size)
	for index in range(market_page*page_size,mini(entries.size(),(market_page+1)*page_size)):
		var entry: Dictionary=entries[index];var item=entry.item
		var title: String=content.ship_name(item.id) if ships else item_name(item.id,"equipment")
		var price: int=economy.ship_price(item) if ships else item.price
		var cells := stock_row("Stock_"+str(index),index==market_selection,row_height,func():market_selection=index;show_market(kind),list)
		var control := cells.get_parent() as Button;control.accessibility_name=title
		var icon := TextureRect.new();icon.texture=imported_art.item(item.id,kind);icon.custom_minimum_size=Vector2(72 if ships else 56,40);icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;icon.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;icon.mouse_filter=Control.MOUSE_FILTER_IGNORE;cells.add_child(icon)
		var words := VBoxContainer.new();words.size_flags_horizontal=Control.SIZE_EXPAND_FILL;words.add_theme_constant_override("separation",1);words.alignment=BoxContainer.ALIGNMENT_CENTER;cells.add_child(words);words.mouse_filter=Control.MOUSE_FILTER_IGNORE
		var named := label(title,17,words);named.add_theme_color_override("font_color",palette.text);named.autowrap_mode=TextServer.AUTOWRAP_OFF;named.clip_text=true;named.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
		var stats := "Hull %d · Cargo %d · Slots %d"%[item.hull,item.capacity(),item.slots] if ships else EquipmentInfo.stats(item)
		var spec := label(stats,13,words);spec.add_theme_color_override("font_color",palette.dim);spec.max_lines_visible=1;spec.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;spec.autowrap_mode=TextServer.AUTOWRAP_OFF;spec.clip_text=true
		var value := label("%d cr"%price if entry.buy else "INSTALLED",15,cells);value.custom_minimum_size.x=96;value.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT;value.size_flags_horizontal=Control.SIZE_SHRINK_END;value.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
		value.add_theme_color_override("font_color",palette.value if entry.buy else palette.good);value.autowrap_mode=TextServer.AUTOWRAP_OFF
		control.tooltip_text=title+"\n"+stats
	pager(market_page,ceili(float(entries.size())/page_size),func(to):market_page=to;market_selection=to*page_size;show_market(kind),list)
	if ships:
		var stage := glass(row,false,16);stage.size_flags_stretch_ratio=1.3 if ui.size.x>=1400 else .8
		var preview=preload("res://native/presentation/ship_preview.gd").new()
		stage.add_child(preview)
		preview.configure(content,entries[market_selection].item.id,modern_graphics,view.library)
		# A drag across the showroom turns the hull instead of scrolling the page.
		touch_scroll.gesture_control=preview
		if ui.size.x<900:stage.custom_minimum_size.y=180
	var frame := glass(row,true,16);frame.custom_minimum_size.x=340 if ui.size.x>=900 else 0;frame.size_flags_horizontal=Control.SIZE_FILL if ui.size.x>=900 else Control.SIZE_EXPAND_FILL
	var detail := VBoxContainer.new();detail.name="SelectedItem";detail.add_theme_constant_override("separation",10);frame.add_child(detail)
	var selected: Dictionary=entries[market_selection];var item=selected.item
	var heading_row := HBoxContainer.new();detail.add_child(heading_row)
	var name_label := label(content.ship_name(item.id) if ships else item_name(item.id,"equipment"),26,heading_row);name_label.add_theme_color_override("font_color",palette.text)
	if not ships and not selected.buy:
		var fitted := caption("Installed",12,heading_row,2);fitted.add_theme_color_override("font_color",palette.good);fitted.size_flags_horizontal=Control.SIZE_SHRINK_END
	caption("For sale" if ships else EquipmentInfo.kind_name(item),12,detail,4)
	rule(detail)
	if ships:
		var better := func(now: int, next: int) -> Color: return palette.good if next>now else palette.bad if next<now else palette.text
		figure_rows([["hull","Hull","%d  →  %d"%[session.ship.hull,item.hull],better.call(session.ship.hull,item.hull)],
			["cargo","Cargo","%d  →  %d"%[session.ship.capacity(),item.capacity()],better.call(session.ship.capacity(),item.capacity())],
			["grid","Slots","%d  →  %d"%[session.ship.slots,item.slots],better.call(session.ship.slots,item.slots)]],detail)
		rule(detail)
		label(item_description(item.id,"ships"),15,detail).add_theme_color_override("font_color",palette.text)
		rule(detail)
		# be: a hull once owned is worth its catalogue price divided by 1.25.
		var balance: int=session.credits+economy.ship_price(session.ship)-economy.ship_price(item)
		figure_rows([["","Trade-in for your %s"%content.ship_name(session.ship.id),"%d cr"%economy.ship_price(session.ship),palette.value],
			["","Balance after exchange","%d cr"%balance,palette.value if balance>=0 else palette.bad]],detail)
		primary(iconic(button("Buy · %d cr"%economy.ship_price(item),func():transaction_result(economy.buy_ship(station,item));show_market(kind),detail),"depart",22))
	else:
		# A phone held landscape has the row's own icon to go by.
		if ui.size.y>=700:
			var showcase := CenterContainer.new();detail.add_child(showcase)
			var art := art_image(imported_art.item(item.id,"equipment"),showcase,96)
			if art!=null: art.custom_minimum_size.x=art.custom_minimum_size.y*2
		var figures: Array=[]
		for pair in EquipmentInfo.figures(item): figures.append(["",pair[0],pair[1]])
		figure_rows(figures,detail)
		rule(detail)
		label(item_description(item.id,"equipment"),14,detail).add_theme_color_override("font_color",palette.text)
		if selected.buy:
			for installed in session.ship.equipment:
				if installed!=null and installed.kind==item.kind:
					var current := VBoxContainer.new();current.add_theme_constant_override("separation",2);glass(detail,false,8).add_child(current)
					caption("Currently equipped",11,current,3)
					label(item_name(installed.id,"equipment"),15,current).add_theme_color_override("font_color",palette.text)
					label(EquipmentInfo.stats(installed),13,current).add_theme_color_override("font_color",palette.dim)
			primary(iconic(button("Buy · %d cr"%item.price,func():transaction_result(economy.buy_equipment(station,item));show_market(kind),detail),"cart",22))
		else:iconic(button("Sell · %d cr"%item.price,func():transaction_result(economy.sell_equipment(station,item));show_market(kind),detail),"credits",22).alignment=HORIZONTAL_ALIGNMENT_CENTER
func header_chip(icon: String, value: String, note: String) -> void:
	"""A figure beside the page title, as the reference shows the purse."""
	if ui.size.x<700: return
	var panel := glass(header_chips,false,10);panel.size_flags_horizontal=Control.SIZE_SHRINK_END;panel.size_flags_vertical=Control.SIZE_SHRINK_BEGIN
	var row := HBoxContainer.new();row.add_theme_constant_override("separation",12);panel.add_child(row)
	line_icon(icon,30,row)
	var words := VBoxContainer.new();words.add_theme_constant_override("separation",0);row.add_child(words)
	var figure := caption(value,18,words,2);figure.add_theme_color_override("font_color",colours().text)
	caption(note,9,words,3)
func action_row(parent: Node) -> HBoxContainer:
	"""The detail's actions, side by side so the pair fits a phone's height."""
	var row := HBoxContainer.new();row.name="Actions";row.add_theme_constant_override("separation",10);parent.add_child(row);return row
func rule(parent: Node) -> void:
	var line := ColorRect.new();line.color=Color(colours().edge,.7);line.custom_minimum_size.y=1;parent.add_child(line)
func goods_browser(station: Dictionary, manufacturing: bool=false) -> void:
	var kind: String="manufacture" if manufacturing else "trade"
	var palette := colours()
	var entries: Array=economy.recipes(station) if manufacturing else economy.market(station)
	entries.sort_custom(func(a,b):return a.id<b.id)
	if entries.is_empty():label("No recipes available here." if manufacturing else "No cargo available for exchange.").add_theme_color_override("font_color",palette.dim);return
	market_selection=clampi(market_selection,0,entries.size()-1)
	# The hold, as a gauge: how much there is room for decides both trades.
	if ui.size.y<700:
		header_chip("cargo","%d / %d t"%[session.ship.cargo_used,session.ship.capacity()],"Cargo hold")
	var hold := HBoxContainer.new();hold.add_theme_constant_override("separation",16)
	if ui.size.y>=700: glass(column,false,10).add_child(hold)
	line_icon("cargo",32,hold)
	var hold_words := VBoxContainer.new();hold_words.add_theme_constant_override("separation",0);hold.add_child(hold_words)
	caption("Cargo hold",14,hold_words,4).add_theme_color_override("font_color",palette.text)
	caption("%d of %d t used"%[session.ship.cargo_used,session.ship.capacity()],10,hold_words,2)
	var gauge := ProgressBar.new();gauge.show_percentage=false;gauge.max_value=maxi(1,session.ship.capacity());gauge.value=session.ship.cargo_used
	gauge.size_flags_horizontal=Control.SIZE_EXPAND_FILL;gauge.size_flags_vertical=Control.SIZE_SHRINK_CENTER;gauge.custom_minimum_size.y=8;hold.add_child(gauge)
	var track := StationTheme.frame(Color(0,0,0,.35),palette.edge,0);var fill := StationTheme.frame(palette.accent,palette.accent,0)
	gauge.add_theme_stylebox_override("background",track);gauge.add_theme_stylebox_override("fill",fill)
	caption("%d%%"%roundi(100.0*session.ship.cargo_used/maxi(1,session.ship.capacity())),14,hold,1).add_theme_color_override("font_color",palette.text)
	if hold.get_parent()==null: hold.free()
	var row:=split_row(column,18)
	var list:=VBoxContainer.new();list.name="StockRows";list.size_flags_horizontal=Control.SIZE_EXPAND_FILL;list.size_flags_stretch_ratio=1.25;list.add_theme_constant_override("separation",6);row.add_child(list)
	var headings:=HBoxContainer.new();list.add_child(headings)
	caption("RECIPE & MATERIALS" if manufacturing else "CARGO & AVAILABILITY",12,headings,3)
	caption("CAN MAKE" if manufacturing else "UNIT PRICE",12,headings,3).horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	var row_height:=64 if touch.enabled() else 56
	var page_size:=clampi(int((ui.size.y-(360 if ui.size.x>=900 else 980))/(row_height+6)),3,7)
	market_page=clampi(market_page,0,(entries.size()-1)/page_size)
	for index in range(market_page*page_size,mini(entries.size(),(market_page+1)*page_size)):
		var item=entries[index];var title:=item_name(item.id)
		var cells:=stock_row("Stock_"+str(index),index==market_selection,row_height,func():market_selection=index;show_market(kind),list)
		(cells.get_parent() as Button).accessibility_name=title
		var icon:=TextureRect.new();icon.texture=imported_art.item(item.id);icon.custom_minimum_size=Vector2(48,40);icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;icon.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;icon.mouse_filter=Control.MOUSE_FILTER_IGNORE;cells.add_child(icon)
		var words:=VBoxContainer.new();words.size_flags_horizontal=Control.SIZE_EXPAND_FILL;words.add_theme_constant_override("separation",0);words.alignment=BoxContainer.ALIGNMENT_CENTER;words.mouse_filter=Control.MOUSE_FILTER_IGNORE;cells.add_child(words)
		label(title,17,words).add_theme_color_override("font_color",palette.text)
		var subtitle: String=("Materials ready" if item.owned>0 else "Needs materials") if manufacturing else "In hold %d · Station stock %d"%[item.owned,item.stock]
		label(subtitle,13,words).add_theme_color_override("font_color",palette.good if manufacturing and item.owned>0 else palette.dim)
		var value:=label(str(maxi(0,item.owned)) if manufacturing else "%d cr"%item.price,16,cells);value.custom_minimum_size.x=84;value.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT;value.size_flags_horizontal=Control.SIZE_SHRINK_END;value.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
		value.add_theme_color_override("font_color",palette.value);value.autowrap_mode=TextServer.AUTOWRAP_OFF
	pager(market_page,ceili(float(entries.size())/page_size),func(to):market_page=to;market_selection=to*page_size;show_market(kind),list)
	var frame := glass(row,true,16);frame.custom_minimum_size.x=380 if ui.size.x>=900 else 0
	var detail:=VBoxContainer.new();detail.name="SelectedItem";detail.add_theme_constant_override("separation",9);frame.add_child(detail)
	var item=entries[market_selection]
	label(item_name(item.id),26,detail).add_theme_color_override("font_color",palette.text)
	if ui.size.y>=700: caption("Product" if manufacturing else "Cargo",12,detail,4)
	var about := HBoxContainer.new();about.add_theme_constant_override("separation",14);detail.add_child(about)
	var holder := glass(about,false,8);holder.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
	var art := art_image(imported_art.item(item.id),holder,80) if ui.size.y>=700 else null
	var described := label(item_description(item.id),14,about);described.add_theme_color_override("font_color",palette.text);described.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	if art==null: holder.hide()
	if manufacturing:
		caption("Ingredients (in cargo / per unit)",11,detail,3)
		for index in item.ingredients.size():
			var id: int=item.ingredients[index];var need: int=item.ingredient_counts[index];var have := 0
			for held in session.ship.cargo:
				if held.id==id: have=held.owned;break
			var line := HBoxContainer.new();line.add_theme_constant_override("separation",12)
			var cell := glass(detail,false,6);cell.add_child(line);cell.get_theme_stylebox("panel").content_margin_top=5;cell.get_theme_stylebox("panel").content_margin_bottom=5
			var picture := art_image(imported_art.item(id),line,26)
			if picture!=null: picture.custom_minimum_size.x=34;picture.size_flags_vertical=Control.SIZE_SHRINK_CENTER
			label(item_name(id),15,line).add_theme_color_override("font_color",palette.text)
			var count := label("%d / %d"%[have,need],15,line);count.size_flags_horizontal=Control.SIZE_SHRINK_END;count.autowrap_mode=TextServer.AUTOWRAP_OFF
			count.add_theme_color_override("font_color",palette.good if have>=need else palette.dim)
		label("Available to make: %d"%maxi(0,item.owned),15,detail).add_theme_color_override("font_color",palette.text)
		var actions := action_row(detail)
		var one := iconic(button("Make one",func():
			if not economy.manufacture(station,item.id,1):notice("Required ingredients or cargo space are missing.")
			else:notice("Made 1 "+item_name(item.id))
			show_market(kind),actions),"cargo",22)
		one.disabled=item.owned<1
		if not one.disabled: primary(one)
		iconic(button("Make all (%d)"%maxi(0,item.owned),func():
			if not economy.manufacture(station,item.id,item.owned):notice("Required ingredients or cargo space are missing.")
			else:notice("Made %d %s"%[item.owned,item_name(item.id)])
			show_market(kind),actions),"trade",22).disabled=item.owned<2
	else:
		figure_rows([["credits","Unit price","%d cr"%item.price,palette.value],["cargo","In hold","%d t"%item.owned],["trade","Station stock","%d t"%item.stock]],detail)
		var affordable := buy_limit(item)
		var sellable: int = maxi(0,item.owned)
		var reachable: int = maxi(1,maxi(affordable,sellable))
		market_quantity=clampi(market_quantity,1,reachable)
		# The amount is chosen once and both trades read it, because a hold is
		# usually filled at one station and emptied at the next.
		var amount:=HBoxContainer.new();amount.add_theme_constant_override("separation",6);detail.add_child(amount)
		var quantity:=caption("Amount  %d t"%market_quantity,12,amount,2);quantity.custom_minimum_size.x=110;quantity.vertical_alignment=VERTICAL_ALIGNMENT_CENTER;quantity.add_theme_color_override("font_color",palette.text)
		for entry in [["−",-1],["+",1]]:
			var stride: int=entry[1]
			var step:=option(entry[0],"amount"+entry[0],func():market_quantity=clampi(market_quantity+stride,1,reachable);show_market(kind),amount)
			step.custom_minimum_size.x=52;step.alignment=HORIZONTAL_ALIGNMENT_CENTER;step.size_flags_horizontal=Control.SIZE_SHRINK_CENTER
		var most:=option("Max","amount_max",func():market_quantity=reachable;show_market(kind),amount)
		most.custom_minimum_size.x=64;most.alignment=HORIZONTAL_ALIGNMENT_CENTER;most.size_flags_horizontal=Control.SIZE_SHRINK_CENTER
		# Each button offers what it can actually move, so the number on it is never
		# a promise the hold or the purse is about to refuse.
		var buying: int=mini(market_quantity,affordable)
		var selling: int=mini(market_quantity,sellable)
		var actions := action_row(detail)
		var purchase := iconic(button("Buy %d · %d cr"%[maxi(1,buying),item.price*maxi(1,buying)],func():
			trade_amount(station,item,true,buying)
			show_market(kind),actions),"cart",22)
		purchase.disabled=buying<1
		if not purchase.disabled: primary(purchase)
		iconic(button("Sell %d · %d cr"%[maxi(1,selling),item.price*maxi(1,selling)],func():
			trade_amount(station,item,false,selling)
			show_market(kind),actions),"credits",22).disabled=selling<1
