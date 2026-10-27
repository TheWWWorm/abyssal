extends Node3D
const Session = preload("res://native/simulation/session.gd")
const World = preload("res://native/simulation/world.gd")
const SpecialActor = preload("res://native/simulation/special_actor.gd")
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
const OceanOptions = preload("res://native/presentation/ocean_options.gd")
const GraphicsQuality = preload("res://native/presentation/graphics_quality.gd")
const GraphicsCredits = preload("res://native/presentation/graphics_credits.gd")
var content
var returning_to_menu := false
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
var retro_hud := preload("res://native/presentation/retro_hud.gd").new()
var trip_tallies := preload("res://native/presentation/trip_tallies.gd").new()
var dashboard := preload("res://native/presentation/flight_dashboard.gd").new()
var hazard_warning := preload("res://native/presentation/hazard_warning.gd").new()
var damage_feedback := preload("res://native/presentation/damage_feedback.gd").new()
var damage_seen_ms := -1
var hints := Label.new()
## Resolution, antialiasing and shadows (graphics_quality.gd), read with the settings.
var quality := GraphicsQuality.read(ConfigFile.new())
var headlight_strength := 1.0
var water_colour := OceanOptions.WATER_COLOUR_DEFAULT
var fps_counter := preload("res://native/presentation/fps_counter.gd").new()
var show_fps := false
var player_face: Array = [87,78,68,20,42,-1]
## The character sheet's imported picture, if any (session.face_photo).
var player_photo := ""
## The title's last frame, its loading notice, held over the dive until the
## view's shader oven has drawn and the compilations it set off have stopped,
## so that work is not seen as a stutter in the first second of the dive.
var launch_cover: Texture2D
var cover: TextureRect
var cover_frames := 0
var cover_compilations := -1
var dock_prompt := Label.new()
var dock_caption := Label.new()
var market_selection := 0
## The good picked in Trade or the Workshop, by id, so the row stays picked as
## a trade moves it between the hold and the station's stock, and a product
## just made is the one the Cargo tab opens on.
var market_selected_id := -1
var equipment_tab := 0
## The trade page's height so far on its tab (layout).
var market_floor := 0.0
var market_floor_kind := ""
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
## Where each long list was scrolled to, so picking a row, which rebuilds the
## page, leaves the list where it was.
var list_offsets := {}
## The open page's scroller.
var page_scroll: ScrollContainer
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
	## Auto fire: 0 off, 1 on but the harpoon bank is selected, 2 firing.
	var auto := 0
	func set_auto(state: int) -> void:
		# Firing, the outer marks turn, so it is redrawn every frame.
		if state!=auto or state==2: auto=state;queue_redraw()
	func _draw() -> void:
		# A broken ring with side ticks round a centre dot; amber with four
		# outer marks while auto fire is on, turning while it fires.
		var c := size*.5;var tint := Color("9fe3efcc") if auto==0 else Color("f0c27add")
		for quarter in 4:
			var middle := quarter*PI*.5+PI*.25
			draw_arc(c,8.0,middle-.5,middle+.5,8,tint,1.5,true)
		for side in [-1.0,1.0]:
			draw_line(c+Vector2(side*11,-3),c+Vector2(side*11,3),tint,1.5)
		draw_circle(c,1.5,tint)
		if auto==0: return
		var mark := tint if auto==2 else Color(tint,.45)
		var turn := Time.get_ticks_msec()*.0025 if auto==2 else 0.0
		for quarter in 4:
			var middle := quarter*PI*.5+PI*.25+turn
			draw_arc(c,15.0,middle-.32,middle+.32,8,mark,2.0,true)
var crosshair := Reticle.new()
var struggle := preload("res://native/presentation/catch_progress.gd").new()
var catch_counter := Label.new()
var fishing_feedback := SettingsMenu.FishingFeedback.BOTH
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
func page_subtitle(id: String) -> String:
	match id:
		"hangar":return tr("Equipment and ships")
		"station_missions":return tr("Objectives, journal and contracts")
		"station_status":return tr("Your ship, pilot profile and medals")
		"system":return tr("Save, controls and settings")
		"ship_status":return tr("Vessel, cargo and systems")
		"profile":return tr("Pilot record")
		"journal":return tr("Current objectives")
	return ""
var lines: Array = []
var line_index := 0
var dialogue_cue := "message"
var dialogue_done: Callable
const SettingsMenu = preload("res://native/presentation/settings_menu.gd")
const FocusMap = preload("res://native/presentation/focus_map.gd")
var key_bindings: Dictionary = SettingsMenu.DEFAULT_KEYS.duplicate()
var suppress_fire_until_release := false
var auto_fire := false
var bank_fire_hold := false
## Original weapon controls (Settings · Controls, off by default): one fire
## control for the selected bank, Tab or the touch switch to change bank, and
## auto fire working the guns only while they are selected. Off, auto fire
## always works the guns. Either way auto fire never fires the harpoon.
var original_weapons := false
## Automatic weapons suspended by a transmission, pause or Action freeze.
## Resuming the same dive restores them; opening another menu stops them.
var interrupted_auto := {}
var modern_graphics := true
var travel_status := Label.new()
## Older flight notices are shown together, then fade away as new ones arrive.
var notice_history: Array[Dictionary] = []
const NOTICE_SECONDS := 4.0
const MAX_NOTICE_HISTORY := 2
const Headlights = preload("res://native/presentation/headlight_options.gd")
var headlight_mode := Headlights.DEFAULT
var headlight_previous := Headlights.DEFAULT
var graphics := {"audio":true,"materials":true,"volumetric":true,"detail":true,"station_smoothing":false,"ship_smoothing":false,"depth_limits":true,"depth_limits_always":false}.merged(OceanOptions.defaults())
var map_widget
var map_info: RichTextLabel
var map_title: Label
var map_slice
var map_showcase: VBoxContainer
var map_picker: OptionButton
var map_destination := 0
## Where the chart's Back goes when another page opened it (a board offer's
## Check location), instead of the station or flight.
var map_return := Callable()
## The species whose range the chart draws, kept between charts.
var habitat_range := -1
## The atlas zone was moved off the chosen station and nothing is chosen.
var map_unchosen := false
var stream_button: Button
var map_route_button: Button
var pending_start := false
var continue_save := false
var player_name := tr("Pilot")
var notification_time := 0.0
var notification_duration := NOTICE_SECONDS
var notification_fades_in := false
var capture_frames := 0
var capture_path := ""
var simulated_capture := false
var mouse_sensitivity := 0.8
var mouse_wheel_throttle := false
var wheel_throttle_remainder := 0.0
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
var demo_mode := false
var demo_outfit := preload("res://native/simulation/demo_session.gd").new()
var demo_weapon_bar := preload("res://native/presentation/demo_weapon_bar.gd").new()
var demo_fire_hold := false
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
## Optional flight overlays, each on by default: the toast messages, the dock and
## gate prompt, the autopilot status line and the labels on friendly contacts.
var flight_messages := true
var dock_prompts := true
var autopilot_status := false
var friend_labels := true
## The mission waypoint keeps its arrow at the screen's edge without a radar;
## the original only drew it off screen with one fitted (cb.a).
var waypoint_edge := true
## Settings > Display: the original's cargo, shield and hull bars as well.
var retro := true
var flight_ms := 0
## Which Controls page is open. Empty is the list of sections itself.
var freeze_view
var layout_editor
## The shared settings screen, and where closing it goes back to.
var settings_panel
var settings_return := Callable()
const FullscreenButton = preload("res://native/presentation/fullscreen_button.gd")
## Browser build only: the corner fullscreen switch over the pause menu.
var fullscreen_button
const TravelFade = preload("res://native/presentation/travel_fade.gd")
const Display = preload("res://native/presentation/display_settings.gd")
const SafeMargins = preload("res://native/platform/safe_margins.gd")
const EngineLanguage = preload("res://native/presentation/engine_language.gd")
var aspect_ratio := "auto"
var settings_path := "user://native/settings.cfg"
var world_spacing := preload("res://native/simulation/world_spacing.gd").new()
const Coin=preload("res://native/presentation/coin_glyph.gd")
func _ready() -> void:
	FocusMap.attach(get_viewport())
	original_ui_size=get_window().content_scale_size
	# The first layout below already applies the ratio, so it is read first.
	aspect_ratio=Display.valid(str(settings_config().get_value("view","aspect_ratio","auto")))
	get_window().size_changed.connect(update_render_resolution)
	if "--gameplay-capture" in OS.get_cmdline_user_args(): save_path="user://native/capture-only.json"
	add_child(camera); camera.current=true; camera.fov=65; camera.near=0.5; camera.far=View.DRAW_DISTANCE
	abyss.camera=camera; abyss.world=world; abyss.view=view; abyss.import_sky_ramp(content.root); Coin.install(content.root); add_child(abyss); dive_audio.world=world; add_child(dive_audio)
	add_child(view); terrain.world=world; terrain.camera=camera; add_child(terrain); add_child(canvas); canvas.add_child(ui); ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); ui.mouse_filter=Control.MOUSE_FILTER_IGNORE
	ui.add_child(demo_weapon_bar)
	demo_weapon_bar.stepped.connect(step_demo_weapon);demo_weapon_bar.finished.connect(finish_demo_weapon_test)
	demo_weapon_bar.minimum_size_changed.connect(func():place_demo_weapon_bar.call_deferred())
	classic_frame.imported_art=imported_art;condition.imported_art=imported_art
	ui.add_child(classic_frame);classic_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(dashboard); dashboard.imported_art=imported_art; dashboard.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(hazard_warning);hazard_warning.z_index=20
	ui.add_child(opening);opening.z_index=30;opening.finished.connect(end_opening)
	ui.add_child(damage_feedback);damage_feedback.z_index=19;damage_feedback.imported_art=imported_art
	ui.add_child(hints); hints.add_theme_font_size_override("font_size",12); hints.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; hints.modulate=Color("9bc2cf")
	pressure_material.shader=preload("res://native/presentation/pressure_overlay.gdshader"); pressure_overlay.material=pressure_material
	ui.add_child(pressure_overlay); pressure_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); pressure_overlay.mouse_filter=Control.MOUSE_FILTER_IGNORE
	ui.add_child(instruments); instruments.position=Vector2(26,52)
	ui.add_child(condition)
	retro_hud.imported_art=imported_art;ui.add_child(retro_hud);retro_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);retro_hud.hide()
	trip_tallies.imported_art=imported_art;ui.add_child(trip_tallies)
	ui.add_child(bank_label); bank_label.add_theme_font_size_override("font_size",13); bank_label.add_theme_color_override("font_color",Color("a6ced7")); bank_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT; bank_label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	ui.add_child(hud); hud.position=Vector2(26,24); hud.clip_text=true; hud.add_theme_font_size_override("font_size",18); hud.add_theme_color_override("font_color",Color("c9e7ea"))
	ui.add_child(objective_label); objective_label.position=Vector2(26,82); objective_label.bbcode_enabled=true; objective_label.scroll_active=false; objective_label.mouse_filter=Control.MOUSE_FILTER_IGNORE; objective_label.add_theme_color_override("default_color",Color("b7cbd0"))
	ui.add_child(struggle);struggle.size=Vector2(340,64);struggle.hide()
	ui.add_child(catch_counter);catch_counter.mouse_filter=Control.MOUSE_FILTER_IGNORE;catch_counter.z_index=1
	catch_counter.add_theme_font_size_override("font_size",22)
	catch_counter.add_theme_color_override("font_color",Color.WHITE)
	catch_counter.add_theme_color_override("font_outline_color",Color("02060c"))
	catch_counter.add_theme_constant_override("outline_size",5);catch_counter.hide()
	ui.add_child(travel_status);travel_status.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;travel_status.add_theme_font_size_override("font_size",15);travel_status.mouse_filter=Control.MOUSE_FILTER_IGNORE
	travel_status.add_theme_color_override("font_color",Color("8bd6ee"));travel_status.add_theme_color_override("font_shadow_color",Color.BLACK);travel_status.add_theme_constant_override("shadow_offset_y",2)
	message.z_index=50;message.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	message.add_theme_color_override("font_shadow_color",Color.BLACK);message.add_theme_constant_override("shadow_offset_y",2)
	var toast := StationTheme.frame(Color(.016,.07,.1,.9),Color("3f9fbf"),8,1,Color(.25,.8,1.0,.18),6)
	toast.content_margin_left=16;toast.content_margin_right=16;toast.content_margin_top=7;toast.content_margin_bottom=8
	message.add_theme_stylebox_override("normal",toast)
	ui.add_child(message); message.add_theme_font_size_override("font_size",16); message.add_theme_color_override("font_color",Color("9ce5d1")); message.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	message.mouse_filter=Control.MOUSE_FILTER_IGNORE
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
	add_child(fps_counter)
	add_child(save_files)
	save_files.chosen.connect(import_transfer)
	save_files.delivered.connect(notice)
	save_files.failed.connect(notice)
	fullscreen_supported=fullscreen_available();touch.show_fullscreen=not web_standalone()
	fullscreen_button=FullscreenButton.new(toggle_fullscreen);ui.add_child(fullscreen_button)
	Input.joy_connection_changed.connect(controller_connection)
	ui.resized.connect(layout); overlay.minimum_size_changed.connect(func(): layout.call_deferred()); layout()
	read_settings()
	apply_orientation()
	motion.notice.connect(notice)
	if motion_steering: motion.enable()
	touch.arrange()
	if load_path.is_empty():load_path=save_path
	if demo_mode:
		session=Session.new();session.new_game(content.data,"Demo",20261025)
		demo_outfit.initialize(session);demo_outfit.apply(session)
	elif continue_save:
		session=store.read(load_path,content.data)
		if session==null: session=Session.new(); session.new_game(content.data,player_name,Time.get_unix_time_from_system()); notice(store.failure)
		elif store.recovered: notice(tr("Your save could not be read. Restored the previous checkpoint."))
	else:
		session=Session.new(); session.new_game(content.data,player_name,int(Time.get_unix_time_from_system())); session.face_layers=player_face.duplicate(); session.face_photo=player_photo
	imported_art.root=content.root
	world.configure(session); economy.configure(session); view.configure(world,content,camera); dive_audio.configure(world,content.root);dive_audio.read_title_track(content.data)
	apply_graphics()
	if demo_mode:
		world.depart();show_demo(false)
	elif continue_save and session.docked:
		# Build a stationary view without changing saved station state.
		world.build_docked_view(); show_station()
	else:
		session.prepare_station(session.station_id)
		if not continue_save: session.docked=true; save_game(false)
		world.depart(); close_page()
		var tooling: Array=OS.get_cmdline_user_args()
		if continue_save or "--gameplay-capture" in tooling or "--no-opening" in tooling: briefing()
		else: begin_opening()
	if launch_cover!=null:
		cover=TextureRect.new();cover.texture=launch_cover;cover.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;cover.stretch_mode=TextureRect.STRETCH_SCALE
		cover.z_index=100;cover.mouse_filter=Control.MOUSE_FILTER_STOP;ui.add_child(cover);cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var launch_args := OS.get_cmdline_user_args()
	for index in launch_args.size():
		if launch_args[index]=="--gameplay-capture":simulated_capture=true
		if launch_args[index]=="--capture" and index+1<launch_args.size():capture_path=launch_args[index+1]
func lift_cover(delta: float) -> void:
	"""Fades the launch cover once the oven is gone and a frame compiled no
	pipeline; a renderer that counts none waits on the oven only. At most
	240 frames, whatever the counters say."""
	cover_frames+=1
	var compilations:=RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SURFACE)+RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW)
	var settled:=view.oven==null and compilations==cover_compilations
	cover_compilations=compilations
	if cover.modulate.a>=1.0 and not settled and cover_frames<240:return
	cover.modulate.a-=minf(delta,1.0/30.0)*4.0
	if cover.modulate.a<=0.0:cover.queue_free();cover=null
func layout() -> void:
	place_demo_weapon_bar()
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
		overlay.size=Vector2(minf(430,ui.size.x-48),minf(ui.size.y-64,fitted_height()));overlay.position=Vector2(64,(ui.size.y-overlay.size.y)*.5)
	elif page in ["hangar","station_missions","station_status"]:
		overlay.size=Vector2(minf(1120,ui.size.x-64),minf(ui.size.y-64,fitted_height()));overlay.position=(ui.size-overlay.size)*.5
	elif page in ["ship_status","profile"]:
		overlay.size=Vector2(minf(1240,ui.size.x-48),minf(ui.size.y-48,fitted_height()));overlay.position=(ui.size-overlay.size)*.5
	elif page in ["demo","demo_picker"]:
		overlay.size=Vector2(minf(900,ui.size.x-48),ui.size.y-48);overlay.position=(ui.size-overlay.size)*.5
	elif page=="system":
		overlay.size=Vector2(minf(880,ui.size.x-64),minf(ui.size.y-64,fitted_height()));overlay.position=(ui.size-overlay.size)*.5
	elif page in ["controls","graphics","journal","failure","confirm","transfer","help","save_slots"]:
		overlay.size=Vector2(minf(760,ui.size.x-64),minf(ui.size.y-64,fitted_height()));overlay.position=(ui.size-overlay.size)*.5
	elif page=="reference":
		overlay.size=Vector2(minf(1400,ui.size.x-32),ui.size.y-32);overlay.position=(ui.size-overlay.size)*.5
	elif page=="medal":
		# A short notice: centred, and only as tall as its rows.
		overlay.size=Vector2(minf(560,ui.size.x-64),minf(ui.size.y-64,fitted_height()));overlay.position=(ui.size-overlay.size)*.5
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
	elif page=="market" and market_category in ["trade","manufacture"]:
		# Sized to its rows, but never shorter than the tallest good already
		# shown on this tab, so the frame does not jump between selections.
		# fit_market measures it once the page is built; until then the
		# frame keeps the height it has.
		overlay.size=Vector2(minf(ui.size.x-48,1240),minf(ui.size.y-48,market_floor if market_floor>0 else maxf(overlay.size.y,fitted_height())));overlay.position=(ui.size-overlay.size)*.5
	elif page=="market" and market_category in ["equipment","ships"]:
		# One frame height for every selection: sized to its rows, the panel
		# jumped as a longer description or a shorter list was picked.
		overlay.size=Vector2(minf(ui.size.x-48,1400 if market_category=="ships" else 1240),minf(ui.size.y-48,920.0));overlay.position=(ui.size-overlay.size)*.5
	elif page in ["market","contracts","cargo","market_equipment","market_goods","equipment","ships","factory"]:
		overlay.size=Vector2(minf(1240 if market_category=="missions" else 1000,ui.size.x-64),ui.size.y-64);overlay.position=(ui.size-overlay.size)*.5
	else:
		overlay.position=Vector2(maxf(160,ui.size.x-minf(740,ui.size.x-190)-22),140);overlay.size=Vector2(minf(740,ui.size.x-190),maxf(260,ui.size.y-304))
	hazard_warning.fit_width(minf(640,ui.size.x-64));hazard_warning.position.x=(ui.size.x-hazard_warning.size.x)*.5
	# Under the hull in the chase view (its keel sits near 71% of the height
	# in landscape, 63% upright), clear of the helm strip below.
	struggle.size=Vector2(minf(340,ui.size.x-64),64)
	struggle.position=Vector2((ui.size.x-struggle.size.x)*.5,minf(ui.size.y*(.67 if ui.size.x<ui.size.y else .75),ui.size.y-(96.0*hud_scale()+94.0))+20)
	travel_status.position=Vector2(ui.size.x*.5-240,ui.size.y-220);travel_status.size=Vector2(480,30)
	objective_label.position=Vector2(30,103); objective_label.size=Vector2(minf(390,ui.size.x*.29),160); objective_label.add_theme_font_size_override("normal_font_size",12); objective_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	objective_label.position=Vector2(30,22+102*k);objective_label.scale=Vector2.ONE*k
	bank_label.scale=Vector2.ONE*k;bank_label.position=Vector2(ui.size.x-26-bank_label.size.x*k,ui.size.y-60*k)
	hints.position=Vector2(ui.size.x*.5-350,ui.size.y-21); hints.size=Vector2(700,18);hints.add_theme_font_size_override("font_size",9)
	if touch.enabled():
		hints.position.y=ui.size.y-30;hints.size.y=22;hints.add_theme_font_size_override("font_size",12)
		if touch.free_right>touch.free_left+120:
			hints.position.x=touch.free_left;hints.size.x=touch.free_right-touch.free_left
	place_retro()
	place_trip_tallies()
	place_catch_feedback()
	update_render_resolution()
	crosshair.position=(get_viewport().get_visible_rect().get_center()-ui.position-crosshair.size*.5).round()
	# Under the notice band, clear of the hull below the crosshair.
	dock_prompt.position=Vector2(ui.size.x*.5-250,flight_notice_end()+10);dock_prompt.size=Vector2(500,40)
	dock_caption.position=Vector2(30,36);dock_caption.size=Vector2(ui.size.x*.5,80)
	place_message()
var layout_pending := false
func place_trip_tallies() -> void:
	trip_tallies.scale=Vector2.ONE*hud_scale()
	var bottom := objective_label.position.y+minf(objective_label.size.y,objective_label.get_content_height())*objective_label.scale.y
	trip_tallies.position=Vector2(objective_label.position.x,bottom+8)
func place_catch_feedback() -> void:
	if not touch.enabled():return
	# The taller diagram sits above any thumb controls crossing its band,
	# including controls moved in Settings and the portrait harpoon button.
	for pass_index in 6:
		var previous:=struggle.position.y
		var band:=struggle.get_rect()
		for id in ["stick","guns","hook","throttle","boost"]:
			var button: Rect2=touch.control_rect(id)
			if button.has_area() and band.intersects(button.grow(8)):
				struggle.position.y=minf(struggle.position.y,button.position.y-struggle.size.y-8)
		if is_equal_approx(previous,struggle.position.y):break
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
	var text_width := font.get_string_size(message.text,HORIZONTAL_ALIGNMENT_CENTER,-1,font_size).x
	for entry in notice_history:text_width=maxf(text_width,font.get_string_size(entry.label.text,HORIZONTAL_ALIGNMENT_CENTER,-1,font_size).x)
	var available := minf(640.0,ui.size.x-40.0)
	# Leave the upright depth column and its numbers clear of wrapped notices.
	if not overlay.visible and narrow_touch_hud():available=minf(available,ui.size.x-192.0)
	var width := minf(maxf(220.0,text_width+40.0),available)
	var height := fit_notice(message,width)
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
	var y := message.position.y+message.size.y+6
	for entry in notice_history:
		var older: Label=entry.label
		var older_height := fit_notice(older,width)
		older.position=Vector2(middle,y)
		older.visible=not overlay.visible and page!="freeze" and not session.docked
		y+=older_height+6
	dock_prompt.position.y=flight_notice_end()+10
	hazard_warning.position.y=flight_notice_end()+60
func flight_notice_end() -> float:
	var bottom := flight_notice_top()+message.size.y
	if not overlay.visible and not notice_history.is_empty():
		var last: Label=notice_history.back().label
		bottom=last.position.y+last.size.y
	return bottom
func fit_notice(node: Label, width: float) -> float:
	node.size=Vector2(width,0)
	var height := maxf(44,node.get_line_count()*node.get_line_height()+15)
	node.size.y=height
	return height
func hud_scale() -> float:
	"""The desktop canvas grows with the window up to 1920 wide, so its gauges
	grow with the height to keep the size the touch layout gives them."""
	return 1.0 if touch.enabled() else clampf(ui.size.y/720.0,1.0,1.6)*.67
func place_retro() -> void:
	"""The Retro HUD's two bands. The cargo bar runs along the top between the
	gauges and the top right's buttons; the bottom row lies between the thumb
	controls on touch, above the control hints, and on desktop just over the
	hints, with the helm strip raised above it. A band with no room for it
	is left out, and the cargo stays on the gauges' line."""
	retro_hud.cargo_rect=Rect2();retro_hud.row_rect=Rect2();classic_frame.lift=0.0
	condition.bars_hidden=false;condition.size.y=96
	if not retro:return
	var k := hud_scale()
	retro_hud.unit=k
	var middle := ui.size.x*.5
	# Past the gauges, with the hull reading beside them.
	var left := condition.position.x+(condition.size.x+16.0)*k
	var right := ui.size.x-left
	if touch.enabled():
		for id in ["map","menu"]:
			var button: Rect2=touch.control_rect(id)
			if button.has_area() and button.position.y<120.0:right=minf(right,button.position.x-20.0)
	var half := minf(minf(middle-left,right-middle),380.0*k)
	if half>=100.0*k:retro_hud.cargo_rect=Rect2(Vector2(middle-half,24.0*k),Vector2(half*2,24.0*k))
	var height := 34.0*k
	if touch.enabled():
		var band := Vector2(touch.free_left,touch.free_right)
		var width := minf(band.y-band.x,860.0*k)
		if width>=300.0*k:
			retro_hud.row_rect=Rect2(Vector2((band.x+band.y-width)*.5,ui.size.y-16.0-height),Vector2(width,height))
			hints.position.y=retro_hud.row_rect.position.y-hints.size.y-6
	else:
		# Clear of the weapon bank's label in the bottom right.
		var reach := middle-(26.0+bank_label.size.x*k+16.0)
		var width := minf(reach*2,860.0*k)
		if width>=300.0*k:
			retro_hud.row_rect=Rect2(Vector2(middle-width*.5,ui.size.y-24.0-height),Vector2(width,height))
			classic_frame.lift=maxf(0.0,24.0+height+24.0*k-40.0*k)
			struggle.position.y=minf(struggle.position.y,ui.size.y-(96.0*k+64.0)-classic_frame.lift+20)
	# The bottom bars stand in for the gauge rows; the line under them and the
	# objective move up into their place.
	if retro_hud.row_rect.has_area():
		condition.bars_hidden=true;condition.size.y=26
		objective_label.position.y=22+32*k
	condition.queue_redraw();retro_hud.queue_redraw()
func flight_notice_top() -> float:
	# Touch keeps its gauges in the top left, taller than the desktop line.
	var top := 132.0 if touch.enabled() else 88.0*hud_scale()
	if demo_weapon_bar.visible:top=maxf(top,demo_weapon_bar.position.y+demo_weapon_bar.size.y+8)
	if narrow_touch_hud():
		var objective_height := minf(objective_label.size.y,objective_label.get_content_height())*objective_label.scale.y
		top=maxf(top,objective_label.position.y+objective_height+14)
		if trip_tallies.visible:top=maxf(top,trip_tallies.position.y+trip_tallies.size.y*trip_tallies.scale.y+14)
	return top
func narrow_touch_hud() -> bool:
	return touch.enabled() and ui.size.x<900 and ui.size.x<ui.size.y
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
	for state in ["normal","hover","pressed","focus"]:
		# Keep the room iconic() made for an icon, or the caption runs under it.
		var previous := node.get_theme_stylebox(state)
		var style := StationTheme.button_state(golden(),state,true)
		if previous!=null and style is StyleBoxFlat: style.content_margin_left=maxf(style.content_margin_left,previous.content_margin_left)
		node.add_theme_stylebox_override(state,style)
	node.add_theme_color_override("font_color",colours().go_text);node.add_theme_color_override("font_focus_color",colours().go_text);node.add_theme_color_override("font_hover_color",colours().go_text)
	node.alignment=HORIZONTAL_ALIGNMENT_CENTER;node.set_meta("primary",true)
	return node
func iconic(node: Button, icon: String, extent: float=26.0) -> Button:
	"""An icon at the left of a button's caption."""
	var mark := StationIcon.new(icon,node.get_theme_color("font_color"),extent);node.add_child(mark)
	mark.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT);mark.offset_left=14;mark.offset_right=14+extent;mark.offset_top=-extent*.5;mark.offset_bottom=extent*.5
	for state in ["normal","hover","pressed","focus","disabled"]:
		var style := node.get_theme_stylebox(state) as StyleBoxFlat
		if style!=null: style.content_margin_left=24+extent
	return node
## The imported text writes money as "$", which the phone's font drew as a
## gold coin; the engine's own amounts show the same coin (coin_glyph.gd).
static func plain_money(text: String) -> String:
	return Coin.dollars(text)
func money_text(body: RichTextLabel, text: String) -> void:
	body.text=Coin.coins(Coin.dollars(text))
func label(text: String, size: int=18, parent: Node=null) -> Label:
	var node := Label.new(); node.text=plain_money(text); node.add_theme_font_size_override("font_size",size); node.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; node.size_flags_horizontal=Control.SIZE_EXPAND_FILL
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
	button(tr("Cancel"),cancel)
	back_row(cancel)
func open_page(title: String, id: String, subtitle: String="") -> void:
	demo_weapon_bar.release_contacts();demo_weapon_bar.hide()
	catch_counter.hide()
	trip_tallies.hide()
	if id in ["dialogue","pause"] and page.is_empty() and session!=null and not session.docked:
		interrupted_auto={"fire":auto_fire,"weapons":touch.automatic_weapons.keys()}
	elif not (id==page and id in ["dialogue","pause"]) and not (id=="pause" and page=="freeze"):interrupted_auto={}
	clear_notice_history();wheel_throttle_remainder=0.0
	# A checked offer is marked only on the chart that was opened for it.
	if id!="map":Map.preview_mission=null
	if id!="settings" and is_instance_valid(settings_panel): settings_panel.hide()
	dive_audio.set_context(id,session!=null and session.docked)
	touch.set_active(false);controller.blocked=true
	autopilot_pressed_at=-1
	page=id;page_back=Callable(); weapon_presses.clear();world.weapon_pending.clear();world.speed=1; world.mouse_pending=Vector2.ZERO; looking=false; release_flight_mouse()
	overlay.add_theme_stylebox_override("panel",box_style())
	auto_fire=false
	for child in overlay.get_children(): overlay.remove_child(child); child.queue_free()
	var shell := VBoxContainer.new();shell.add_theme_constant_override("separation",12);overlay.add_child(shell)
	var header := HBoxContainer.new();header.add_theme_constant_override("separation",12);shell.add_child(header)
	var titles := VBoxContainer.new();titles.size_flags_horizontal=Control.SIZE_EXPAND_FILL;titles.add_theme_constant_override("separation",4);header.add_child(titles)
	var heading := label(title.to_upper(),30 if session!=null and session.docked and id in STATION_PAGES and ui.size.x>=700 and ui.size.y>=640 else 24,titles);heading.name="Heading"
	heading.add_theme_font_override("font",heading_font(7));heading.add_theme_color_override("font_color",colours().text);heading.autowrap_mode=TextServer.AUTOWRAP_OFF
	heading.clip_text=true;heading.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	var rule := ColorRect.new();rule.color=colours().accent;rule.custom_minimum_size=Vector2(56,2);rule.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN;titles.add_child(rule)
	if subtitle.is_empty(): subtitle=page_subtitle(id)
	if not subtitle.is_empty() and ui.size.x>=700 and ui.size.y>=640: caption(subtitle,11,titles,3).name="Subtitle"
	header_chips=HBoxContainer.new();header_chips.add_theme_constant_override("separation",10);header.add_child(header_chips)
	# A medal is a notice with its own OK; Esc still moves on.
	if id not in ["station","dialogue","failure","transit","stream","medal"]:
		var back := iconic(button(tr("Close").to_upper() if id=="destinations" else tr("Back").to_upper(),dock_back,header),"back",18)
		back.size_flags_horizontal=Control.SIZE_SHRINK_END;back.size_flags_vertical=Control.SIZE_SHRINK_BEGIN;back.custom_minimum_size=Vector2(128,48 if touch.enabled() else 40)
		back.add_theme_font_override("font",heading_font(4))
	var scroll := ScrollContainer.new();page_scroll=scroll;scroll.follow_focus=true; scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;shell.add_child(scroll)
	# A page longer than its frame scrolls; it is never cut into sheets.
	var gutter := scroll_gutter(scroll)
	column=VBoxContainer.new(); column.size_flags_horizontal=Control.SIZE_EXPAND_FILL; column.size_flags_vertical=Control.SIZE_EXPAND_FILL; column.add_theme_constant_override("separation",7); gutter.add_child(column)
	# Panels sized to their rows follow the rows once text has wrapped to width.
	column.minimum_size_changed.connect(request_layout)
	touch_scroll.scroll=scroll;touch_scroll.gesture_control=null;touch_scroll.release()
	# The keys, as the reference's footer shows them; a touch screen has none.
	var legend := HBoxContainer.new();legend.name="KeyLegend";legend.add_theme_constant_override("separation",8);shell.add_child(legend)
	legend.visible=not touch.enabled()
	for entry in [["ESC / B",tr("Close") if id=="destinations" else tr("Back")],[tr("D-pad / arrows"),tr("Navigate")],[tr("Enter / A"),tr("Select")]]:
		var boxed := StationTheme.frame(Color(0,0,0,0),colours().edge,0);boxed.set_content_margin_all(3);boxed.content_margin_left=7;boxed.content_margin_right=7
		var key := caption(entry[0],10,legend,1);key.add_theme_stylebox_override("normal",boxed);key.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
		var meaning := caption(entry[1],10,legend,2);meaning.add_theme_color_override("font_color",colours().faint);meaning.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
		meaning.custom_minimum_size.x=meaning.get_minimum_size().x+14
	overlay.show(); layout();layout.call_deferred();focus_page.call_deferred();settle_scroll.call_deferred(scroll)
	if id!="dialogue":
		for control in [classic_frame,retro_hud,trip_tallies,hazard_warning,damage_feedback,dashboard,hud,instruments,condition,bank_label,hints,objective_label,crosshair,dock_prompt,travel_status,struggle]:control.hide()
	for marker in markers:marker.hide()
func settle_scroll(scroll: ScrollContainer) -> void:
	"""A page opens at its top, or as far down as its focused row needs.
	Focus is taken before the frame has its final size, and the scroll that
	followed it was measured against the page it replaced."""
	await get_tree().process_frame
	if not is_instance_valid(scroll):return
	scroll.scroll_vertical=0
	var focused := get_viewport().gui_get_focus_owner()
	if focused!=null and scroll.is_ancestor_of(focused):scroll.ensure_control_visible(focused)
func scroll_gutter(scroll: ScrollContainer) -> MarginContainer:
	"""The scroller's content, kept clear of its bar while the bar shows and
	full width while everything fits."""
	var gutter := MarginContainer.new();gutter.name="Gutter";gutter.size_flags_horizontal=Control.SIZE_EXPAND_FILL;gutter.size_flags_vertical=Control.SIZE_EXPAND_FILL
	scroll.add_child(gutter)
	var bar: VScrollBar=scroll.get_v_scroll_bar()
	var fit := func():if is_instance_valid(gutter):gutter.add_theme_constant_override("margin_right",10 if bar.visible else 0)
	bar.visibility_changed.connect(fit);fit.call()
	return gutter
func scrolled_rows(parent: Node, key: String) -> VBoxContainer:
	"""A list that scrolls on its own beside a fixed detail panel. Each row
	rebuilds the page when picked, so the list returns to where it was."""
	var scroll := ScrollContainer.new();scroll.name=key;scroll.follow_focus=true;scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;parent.add_child(scroll)
	var rows := VBoxContainer.new();rows.name="Rows";rows.size_flags_horizontal=Control.SIZE_EXPAND_FILL;rows.add_theme_constant_override("separation",6);scroll_gutter(scroll).add_child(rows)
	var offset: int=list_offsets.get(key,0)
	scroll.get_v_scroll_bar().value_changed.connect(func(value: float):list_offsets[key]=int(value))
	restore_scroll(scroll,offset)
	return rows
func restore_scroll(scroll: ScrollContainer, offset: int) -> void:
	# Applied each time the rows are measured, so the first frame drawn is
	# already at the offset, until the list has settled.
	if offset<=0:return
	var bar: VScrollBar=scroll.get_v_scroll_bar()
	var apply := func():if is_instance_valid(scroll):scroll.scroll_vertical=offset
	bar.changed.connect(apply)
	for _frame in 2:await get_tree().process_frame
	if not is_instance_valid(bar):return
	bar.changed.disconnect(apply);apply.call()
func close_page() -> void:
	# Anything that closes the page under the opening ends the opening with it.
	if opening.active:opening.finish(false)
	dive_audio.set_context("",session!=null and session.docked)
	view.gate_preview=false;Map.preview_mission=null
	touch_scroll.scroll=null;touch_scroll.gesture_control=null;touch_scroll.release()
	page=""; overlay.hide();get_viewport().gui_release_focus();
	if is_instance_valid(settings_panel): settings_panel.hide()
	# A notice given while the menu was up sat beside the menu; with the menu
	# gone it belongs in the flight's own band, not over the hull.
	place_message(); suppress_fire_until_release=Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or Input.is_physical_key_pressed(key_bindings.fire) or Input.is_physical_key_pressed(key_bindings.harpoon)
	mouse_steer=Vector2.ZERO
	controller.blocked=true;touch.set_active(not session.docked)
	if not interrupted_auto.is_empty() and not session.docked:
		auto_fire=interrupted_auto.fire
		for key in interrupted_auto.weapons:touch.automatic_weapons[key]=true
		touch.queue_redraw()
	interrupted_auto={}
	# A departure may open a briefing in this same frame. Never enqueue a
	# browser pointer-lock request before that menu decision has finished.
	capture_flight_mouse.call_deferred()
	if session.demo_mode and demo_outfit.quick_test:refresh_demo_weapon_bar.call_deferred()
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
	# Alt by default, the modifier a browser leaves alone; Ctrl, the one a
	# desktop pilot reaches for, also works while that default is kept and no
	# other action has Ctrl. Neither steers while held.
	if not page.is_empty() or touch.enabled():return false
	if Input.is_physical_key_pressed(key_bindings.free_look):return true
	return key_bindings.free_look==KEY_ALT and not KEY_CTRL in key_bindings.values() and Input.is_physical_key_pressed(KEY_CTRL)
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
	text=plain_money(text)
	if not flight_messages and routine_notice(text):return
	if text.is_empty() or (text==message.text and notification_time>0):return
	var flight: bool=page.is_empty() and not session.docked
	if time_notice(text):
		for index in range(notice_history.size()-1,-1,-1):
			if time_notice(notice_history[index].label.text):remove_old_notice(index)
		if time_notice(message.text):
			message.text=text;notification_time=2;notification_duration=2;notification_fades_in=flight
			update_notices(0);place_message();return
	# Repeated text leaves the row's position and fade clock alone.
	for entry in notice_history:
		if entry.label.text==text:return
	if notification_time>0 and not message.text.is_empty() and flight:
		var older := message.duplicate() as Label
		ui.add_child(older)
		notice_history.push_front({"label":older,"time":minf(notification_time,NOTICE_SECONDS),"duration":notification_duration,"fade_in":notification_fades_in})
		var limit := 1 if ui.size.y<600 else MAX_NOTICE_HISTORY
		while notice_history.size()>limit:remove_old_notice(notice_history.size()-1)
	else:clear_notice_history()
	message.text=text;notification_duration=2.0 if time_notice(text) else (NOTICE_SECONDS if flight else 7.0)
	notification_time=notification_duration;notification_fades_in=flight
	message.show()
	update_notices(0)
	place_message()
func remove_old_notice(index: int) -> void:
	var older: Label=notice_history[index].label
	ui.remove_child(older);older.queue_free();notice_history.remove_at(index)
func clear_notice_history() -> void:
	while not notice_history.is_empty():remove_old_notice(notice_history.size()-1)
func update_notices(delta: float) -> void:
	notification_time=maxf(0,notification_time-delta)
	if notification_time<=0:message.text=""
	if time_notice(message.text):message.text=tr("Time · %d×")%world.speed
	message.modulate.a=notice_alpha(notification_time,notification_duration,notification_fades_in)
	message.visible=not message.text.is_empty() and page!="freeze"
	var changed := false
	for index in range(notice_history.size()-1,-1,-1):
		var entry: Dictionary=notice_history[index]
		entry.time-=delta
		if entry.time<=0:remove_old_notice(index);changed=true
		else:entry.label.modulate.a=(.85-.15*index)*notice_alpha(entry.time,entry.duration,entry.fade_in)
	if changed:place_message()
func notice_alpha(remaining: float, duration: float, fade_in: bool) -> float:
	if not fade_in:return clampf(remaining,0,1)
	var half := duration*.5
	return clampf(minf(duration-remaining,remaining)/half,0,1)
func time_notice(text: String) -> bool:
	"""The time-speed notice (world.gd), in English or the engine's language."""
	var prefix := tr("Time · %d×").get_slice("%d",0).strip_edges()
	return text.begins_with("Time ·") or (not prefix.is_empty() and text.begins_with(prefix))
const ROUTINE_NOTICES := ["Autopilot · %s","Autopilot · mission waypoint","Time · %d×","Docked · %s","Entered %s",
	"S.T.R.E.A.M. arrival · %s","Camera · %s","Leaving %s · Enter / click to skip","Auto guns on · tap to stop","Auto guns off",
"Auto fire off","Tilt centred"]
func routine_notice(text: String) -> bool:
	"""A confirmation of what the player just did or of where the ship now is,
	which the Messages at sea setting hides; refusals and warnings stay."""
	for format in ROUTINE_NOTICES:
		for prefix in [format.get_slice("%",0),tr(format).get_slice("%",0)]:
			if not prefix.strip_edges().is_empty() and text.begins_with(prefix): return true
	return false
func clear_notices() -> void:
	"""Arrival clears flight notices so a refused docking cannot stay on screen
	while the submarine is already inside the station."""
	clear_notice_history()
	message.text="";notification_time=0
	message.hide();place_message()
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
	return tr("Ingredients (in cargo / per unit)")+"\n"+" · ".join(parts)
func flight_hint() -> String:
	var keys: Array = ["up","left","down","right"].map(func(action): return OS.get_keycode_string(key_bindings[action]))
	var steering: String = (tr("%s/%s steer · %s/%s strafe")%[keys[0],keys[2],keys[1],keys[3]]) if strafe_enabled() else tr("%s steer")%"/".join(keys)
	return tr("%s · %s fire · %s pilot · %s map · %s dock · Esc menu")%[steering,OS.get_keycode_string(key_bindings.fire),OS.get_keycode_string(key_bindings.autopilot),OS.get_keycode_string(key_bindings.map),OS.get_keycode_string(key_bindings.dock)]
func discord_context() -> Dictionary:
	if session==null or content==null:return {}
	var context := {"page":page,"market":market_category,"ship":content.ship_name(session.ship.id),"docked":session.docked,"autopilot":world.autopilot}
	var region=world.region
	if region!=null and not session.docked:
		context["transit"]=view.transit_progress>=0
		context["fishing"]=region.fishing.any(func(hook):return hook.hooked)
		context["combat"]=region.enemies.any(func(actor):return actor.state not in [3,4,999] and actor.health.hull>0 and preload("res://native/simulation/npc.gd").within(actor.pose.origin,region.player.pose.origin,55000))
	return context

func _process(delta: float) -> void:
	if session==null: return
	if is_instance_valid(cover):lift_cover(delta)
	GraphicsQuality.update_frame_generation(get_viewport(),quality,page.is_empty() and get_window().has_focus())
	if GraphicsQuality.upscaler_failed(get_viewport()): update_render_resolution()
	view.stabilize_touch_horizon=touch.enabled()
	if world.region!=null:world.region.player.touch_horizon_assist=touch.enabled()
	if not page.is_empty() and Input.mouse_mode!=Input.MOUSE_MODE_VISIBLE:release_flight_mouse()
	view.look_held=(free_look_held() and mouse_steering_enabled()) or (touch.enabled() and not touch.drag_anywhere and touch.orbit_held()) or (page.is_empty() and controller.snapshot().camera!=Vector2.ZERO)
	watch_browser_capture()
	if autopilot_pressed_at>=0 and not autopilot_hold_used and Time.get_ticks_msec()-autopilot_pressed_at>=450:
		autopilot_hold_used=true;autonavigate_objective()
	# Placement keeps the controls on screen without letting them steer, so the
	# per-frame active state must not take them away from the editor drawing them.
	touch.set_active(page.is_empty() and not session.docked and not world.region.cinematic())
	if page=="layout": touch.refresh_visibility()
	if page in ["map","stream"]: map_pad(delta)
	fullscreen_button.place(page=="pause")
	dive_audio.set_context(page,session.docked)
	advance_transit_view(delta)
	var departure_shot: bool=page=="departure" or view.transit_progress>=0 or view.departure_progress>=0
	if world.region!=null:
		world.region.pressure_hold=departure_shot
		if departure_shot:world.region.radio_hold_ms=RADIO_SETTLE_MS
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
		watch_catches(world.region)
		world.advance(delta,flight_input(delta))
		if session.docked: finish_docking()
		else:
			collect_damage_bearings();check_hull_buzz()
			# The simulation stops at a death or at the end of an encounter;
			# its clock runs on alone while the explosion that ended it plays.
			if world.region.failed or world.region.pending_mission!=null:world.region.elapsed_ms+=int(minf(delta,.1)*1000.0)
			consume_events()
			if page.is_empty():
				flight_ms+=int(delta*1000)
				check_stream_proximity()
				if page.is_empty() and not session.demo_mode:check_flight_hints()
				if stream_exit_active:
					var exit_local: Vector3=stream_exit_frame.affine_inverse()*world.region.player.pose.godot_transform().origin
					if absf(exit_local.z)>view.player_model.solid_bounds().size.length():
						stream_exit_active=false;view.clear_player_clip()
	elif session.docked and page.is_empty(): finish_docking()
	elif session.docked and page=="station": check_station_progress()
	if world.region!=null:
		var r=world.region
		dock_caption.visible=session.docked and page!="dialogue" and not overlay.visible
		dock_caption.text=(tr("%s Station\nBerth secured  /  exterior view")%session.stations[session.station_id].name).to_upper()
		dock_prompt.visible=page.is_empty() and not session.docked and (world.in_docking_area() or Vector3(r.player.pose.origin[0],r.player.pose.origin[1],r.player.pose.origin[2]).length()<25000)
		dock_prompt.text=(tr("[ %s ]  Dock at %s")%[control_name("dock"),session.stations[session.station_id].name]) if world.in_docking_area() else tr("[ %s ]  Dock · approach docking area")%control_name("dock")
		if r.success!=null or r.failure!=null:
			dock_prompt.text=tr("Docking locked · encounter active  [ %s ] Mission waypoint")%control_name("autopilot")
		elif world.at_gate(0) and view.transit_progress<0 and not stream_exit_active and not (world.autopilot and world.gate_navigation):
			dock_prompt.visible=page.is_empty() and not session.docked and not r.cinematic()
			dock_prompt.text=tr("[ %s ]  Enter the S.T.R.E.A.M.")%control_name("dock")
		elif not world.dock_denial().is_empty():
			dock_prompt.text=world.dock_denial()
		instruments.update(r,OS.get_keycode_string(key_bindings.boost),world)
		var flight_visible: bool=(page.is_empty() or page=="dialogue") and not r.cinematic() and not session.docked
		demo_weapon_bar.visible=session.demo_mode and demo_outfit.quick_test and flight_visible and page.is_empty()
		hazard_warning.update(r,flight_visible and page.is_empty() and not r.pressure_hold,not modern_graphics)
		damage_feedback.visible=flight_visible
		# With no notice or dock prompt under the top read-out the warning
		# takes their place, leaving room above it for the hull read-out
		# clear of the top edge and of the retro cargo bar's band.
		if message.visible or not notice_history.is_empty() or dock_prompt.visible:hazard_warning.position.y=flight_notice_end()+60
		else:hazard_warning.position.y=maxf(flight_notice_top(),64.0*hud_scale()+damage_feedback.readout_clearance())
		# bd draws the hull readout in the depth warning's place; over a
		# warning that is showing, it moves up into the gap above it.
		damage_feedback.readout_top=hazard_warning.position.y-damage_feedback.position.y-(damage_feedback.readout_clearance() if hazard_warning.visible else 0.0)
		# Over a warning doing damage the warning's own bar reads the hull.
		damage_feedback.readout_covered=hazard_warning.visible and hazard_warning.status.get("damaging",false)
		pressure_material.set_shader_parameter("warning_color",hazard_warning.accent)
		classic_frame.visible=flight_visible and not touch.enabled();classic_frame.update(r.player,session.ship,world.speed,instruments.boost_state(r.player,world),OS.get_keycode_string(key_bindings.boost),instruments.harpoon_state(r,world))
		instruments.visible=flight_visible
		instruments.modulate.a=1;condition.modulate.a=1;bank_label.modulate.a=1
		dashboard.visible=false
		hud.visible=false;hints.visible=flight_visible and gameplay_hints;objective_label.visible=flight_visible
		hints.text=tr("LMB guns · RMB hook · %s fire · %s destination · %s chart")%[OS.get_keycode_string(key_bindings.fire),OS.get_keycode_string(key_bindings.autopilot),OS.get_keycode_string(key_bindings.map)]
		if touch.enabled():hints.text=tr("Drag anywhere to look") if touch.drag_anywhere else (tr("Left thumb strafes · drag the screen to look") if strafe_enabled() else tr("Left thumb steers · drag the screen to look"))
		elif controller.device>=0 and controller.layout==controller.Layout.STANDARD:hints.text=(tr("Right stick aim · left stick throttle and strafe") if controller.default_roles() else tr("Sticks as set in Gamepad settings"))+" · "+tr("RT guns · LT hook · RB fire · LB boost · A dock · X route · View map · Start menu")
		elif controller.device>=0:hints.text=tr("%s · hold D-pad left to look · D-pad speed · RT guns / LT hook · Y dock · View map · Start menu")%((tr("Left stick strafe · right stick turn") if strafe_enabled() else tr("Left stick steer")) if controller.default_roles() else tr("Sticks as set in Gamepad settings"))
		condition.update(r.player.health,session.ship); condition.visible=flight_visible
		# The fitted weapons are the player's own knowledge; the HUD keeps quiet,
		# unless one fire control works whichever bank is selected.
		bank_label.visible=flight_visible and original_weapons and not touch.enabled() and world.region.loadout.groups.size()>1
		condition.info=Coin.coins(tr("%d/%dt     Cr %d     %s")%[session.ship.cargo_used,session.ship.capacity(),session.credits,session.stations[session.station_id].name])
		# The retro cargo bar carries the hold instead.
		if retro and retro_hud.cargo_rect.has_area():condition.info=Coin.coins(tr("Cr %d     %s")%[session.credits,session.stations[session.station_id].name])
		if touch.enabled():
			# The dock button is there while docking, or a manual gate entry, is.
			var dockable: bool=world.in_docking_area() or (world.at_gate(0) and view.transit_progress<0 and not stream_exit_active and not (world.autopilot and world.gate_navigation))
			var banks: Array=r.loadout.groups.filter(func(group):return not group.is_empty())
			touch.set_banks(r.loadout.selected>=0 and not guns_selected(),banks.size()>1)
			touch.show_state(r.player.throttle_target/100.0,flight_visible and page.is_empty() and dockable,instruments.boost_state(r.player,world),world.autopilot,world.speed,
				banks.any(func(group):return group[0].fishing),banks.any(func(group):return not group[0].fishing),instruments.harpoon_state(r,world),instruments.guns_state(r,world))
		if r.loadout.selected>=0:
			var bank: Array = r.loadout.groups[r.loadout.selected]
			bank_label.text=(tr("FISHING BANK · Harpoon") if bank[0].fishing else (tr("COMBAT BANK · %d weapon") if bank.size()==1 else tr("COMBAT BANK · %d weapons"))%bank.size())
			if r.loadout.groups.size()>1: bank_label.text+="\n"+(tr("%s · Switch to combat") if bank[0].fishing else tr("%s · Switch to fishing"))%OS.get_keycode_string(key_bindings.bank)
		else: bank_label.text=tr("NO WEAPONS INSTALLED")
		pressure_material.set_shader_parameter("strength",instruments.pressure_strength if flight_visible and not r.pressure_hold else 0.0)
		hud.text=Coin.coins(tr("%d cr · %s")%[session.credits,session.stations[session.station_id].name])
		if hud.text!=previous_hud_text: previous_hud_text=hud.text; fit_hud()
		var objective=current_objective()
		var objective_text: String=objective_hud(objective)
		if session.demo_mode:objective_text=tr("Demo mode")+" · "+tr("Pause")+" → "+tr("Test loadout")
		if r.cinematic(): objective_text=session.title(objective)+"\n"+tr("Final sequence · Esc pauses")
		# bd.a draws a timed job's remaining time (mm:ss) at the HUD's top left;
		# the job fails when it runs out (region.time_limit).
		elif r.time_limit>0 and not r.encounter_resolved and not r.failed:
			var left: int=maxi(0,r.time_limit-r.elapsed_ms)
			objective_text+="\n[color=#%s]%s[/color]"%["ff7a6a" if left<30000 else "e4ce92",tr("Time left · %s")%clock_text(left)]
		if auto_fire: objective_text+="\n"+tr("AUTO FIRE · %s to stop")%OS.get_keycode_string(key_bindings.auto_fire)
		show_objective(objective_text,objective if not r.cinematic() else null)
		trip_tallies.update(session.medals,flight_visible and page.is_empty() and view.transit_progress<0 and view.departure_progress<0,session.ship.passive_radar,session.ship.upgraded)
		place_trip_tallies()
		# The way out of a gate is a camera shot, not the chase view: its centre
		# is not where the guns point, so the reticle waits for the hand-back.
		crosshair.visible=view.camera_mode==0 and page.is_empty() and not r.cinematic() and not session.docked and not view.looking_around() and view.transit_progress<0 and view.departure_progress<0
		var touch_auto: bool=touch.automatic_weapons.has("guns")
		var auto_live: bool=auto_firing() or (touch_auto and (guns_selected() if original_weapons else true))
		crosshair.set_auto(0 if not (auto_fire or touch_auto) else (2 if auto_live else 1))
		retro_hud.visible=retro and flight_visible
		if retro_hud.visible:retro_hud.update(session.ship.cargo_used,session.ship.capacity(),r.player.health,session.ship,0 if not (auto_fire or touch_auto) else (2 if auto_live else 1),world.autopilot)
		update_catch_feedback(r,flight_visible and page.is_empty())
		travel_status.text=tr("AUTOPILOT  ·  %d× TIME  ·  [%s] CHANGE SPEED")%[world.speed,OS.get_keycode_string(key_bindings.time)]
		travel_status.visible=flight_visible and world.autopilot and autopilot_status
		if not dock_prompts:dock_prompt.visible=false
		dashboard.throttle_keys=[OS.get_keycode_string(key_bindings.throttle_up),OS.get_keycode_string(key_bindings.throttle_down)]
		dashboard.objective_text=objective_label.get_parsed_text();dashboard.update(world)
		if not world.message.is_empty(): notice(world.message); world.message=""
		# After the view has placed this frame's camera: projected with the
		# last one, brackets and hull bars trail their ships through a turn.
		update_markers.call_deferred()
	update_notices(delta)
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
func watch_catches(region) -> void:
	"""cx lets a struggling catch go the moment it leaves the screen (am.a(v)).
	The region's own test, a cone round the bow, reaches far past the edges
	of the view, so in flight the frame actually drawn decides."""
	if region==null: return
	var watch := Callable(self,"catch_in_view")
	for hook in region.fishing:
		if hook.visible_to_camera!=watch: hook.visible_to_camera=watch
func catch_in_view(point: Array) -> bool:
	if not is_instance_valid(camera) or not camera.is_inside_tree(): return true
	var at := Library.point(point)
	if camera.is_position_behind(at): return false
	return Rect2(ui.position,ui.size).has_point(camera.unproject_position(at))
func update_catch_feedback(region, show_feedback: bool) -> void:
	struggle.hide()
	if fishing_feedback not in [SettingsMenu.FishingFeedback.LINE,SettingsMenu.FishingFeedback.BOTH]:return
	var phase: float=view.combat.visual_time
	for hook in region.fishing:
		var id: int=hook.weapon.equipment_id if hook.weapon!=null else 15
		if not hook.hooked or hook.target==null:
			var fraction:=clampf(world.accumulator/world.STEP_MS,0,1) if world.render_interpolation_enabled else 1.0
			var cast: Dictionary=struggle.flight(hook.weapon,fraction)
			if cast.is_empty():continue
			struggle.present("flight",cast.progress,id,phase,cast.kind)
			struggle.visible=show_feedback
			break
		var kind: String="fish" if hook.target.is_creature else "cargo"
		# Attachment and the first tow step occupy adjacent simulation ticks.
		# A wreck is already ready on impact; never ask to disable it again.
		if hook.towing or hook.ready_to_tow():
			var distance: float=preload("res://native/simulation/fixed_math.gd").length_of(preload("res://native/simulation/fixed_math.gd").subtracted(region.player.pose.origin,hook.target.pose.origin))
			var seconds := maxf(0,distance-hook.capture_distance)/maxf(1,hook.tow_speed*1000)
			var initial: float=hook.tow_start_distance if hook.tow_start_distance>0 else distance
			struggle.present("reel",100.0*(1.0-clampf((distance-hook.capture_distance)/maxf(1,initial-hook.capture_distance),0,1)),id,phase,kind,seconds)
			struggle.visible=show_feedback
		elif hook.target.is_creature:
			# The original spends strength once per two-second struggle. Show
			# that same progress continuously without changing the simulation.
			var total := maxf(2000,ceilf(hook.target.struggle_total/1000.0)*2000)
			var remaining := maxf(0,ceilf(hook.target.struggle_remaining/1000.0)*2000-hook.target.struggle_time)
			struggle.present("struggle",100.0*(1.0-remaining/total),id,phase,kind,remaining*.001)
			struggle.visible=show_feedback
		break
func update_catch_counter() -> void:
	"""cx displays af's remaining struggle count beside the hooked creature,
	independently of the scanner. Project after this frame's camera is placed."""
	catch_counter.hide()
	if fishing_feedback not in [SettingsMenu.FishingFeedback.TIMER,SettingsMenu.FishingFeedback.BOTH]:return
	if not page.is_empty() or session.docked or world.region==null or world.region.cinematic() or view.transit_progress>=0 or view.departure_progress>=0:return
	for hook in world.region.fishing:
		var target=hook.target
		if not hook.hooked or target==null or not target.is_creature:continue
		if hook.towing or hook.ready_to_tow() or target.health.hull<=0:continue
		var at: Vector3=world.render_pose(target).origin
		if camera.is_position_behind(at):continue
		var screen: Vector2=ui.get_global_transform().affine_inverse()*camera.unproject_position(at)
		if not Rect2(Vector2.ZERO,ui.size).has_point(screen):continue
		var ray:=PhysicsRayQueryParameters3D.create(camera.global_position,at,2);ray.hit_back_faces=true
		if not view.get_world_3d().direct_space_state.intersect_ray(ray).is_empty():continue
		catch_counter.text=str(target.countdown());catch_counter.size=catch_counter.get_minimum_size()
		var desired:=screen+Vector2(12,-catch_counter.size.y-8)
		catch_counter.position=desired.clamp(Vector2.ONE*6,(ui.size-catch_counter.size-Vector2.ONE*6).max(Vector2.ONE*6)).round()
		catch_counter.show();return
func auto_firing() -> bool:
	"""Auto fire works the guns and never the harpoon. With the original
	controls it works the selected bank, so selecting the harpoon pauses it
	and selecting the guns again resumes it, as in the original."""
	if not auto_fire or world.region==null: return false
	if original_weapons:return guns_selected()
	return world.region.loadout.groups.any(func(group):return not group.is_empty() and not group[0].fishing)
func guns_selected() -> bool:
	if world.region==null:return false
	var loadout=world.region.loadout
	return loadout.selected>=0 and not loadout.groups[loadout.selected].is_empty() and not loadout.groups[loadout.selected][0].fishing
func strafe_enabled() -> bool:
	# Auto strafes wherever something else can turn the boat: a mouse, or the
	# right stick. A thumb on the touch stick has neither, so it keeps turning.
	return not touch.enabled() if strafe_mode==0 else strafe_mode==1
func flight_input(seconds: float=0.0) -> Dictionary:
	if not page.is_empty() or session.docked or world.region.cinematic(): return {}
	var horizontal := float(Input.is_physical_key_pressed(key_bindings.right))-int(Input.is_physical_key_pressed(key_bindings.left))
	var pitch := float(Input.is_physical_key_pressed(key_bindings.up))-int(Input.is_physical_key_pressed(key_bindings.down))
	var mouse_delta := mouse_steer; mouse_steer=Vector2.ZERO
	# Wheel throttle turns the saved throttle_down key into an immediate stop.
	# Otherwise it keeps the keyboard's graduated throttle-down control.
	var throttle_down := Input.is_physical_key_pressed(key_bindings.throttle_down)
	var stopping := mouse_wheel_throttle and throttle_down
	var throttle := int(Input.is_physical_key_pressed(key_bindings.throttle_up))
	if not mouse_wheel_throttle:throttle-=int(throttle_down)
	var fire := Input.is_physical_key_pressed(key_bindings.fire)
	var guns := not touch.enabled() and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	# Auto fire: the selected bank with the original controls, which is never
	# the harpoon while it fires; otherwise the guns, whatever is selected.
	var auto_shot := false
	if auto_firing():
		if original_weapons:auto_shot=true
		else:guns=true
	var hook := (not touch.enabled() and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)) or Input.is_physical_key_pressed(key_bindings.harpoon)
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
	horizontal=clampf(horizontal+pad.horizontal+screen.yaw,-1,1)
	var strafe := 0.0
	var yaw: float=pad.yaw
	if strafe_enabled(): strafe=horizontal
	else: yaw=clampf(yaw+horizontal,-1,1)
	strafe=clampf(strafe+pad.strafe,-1,1)
	# A stick given to the camera swings it round the hull, a full turn in
	# about two and a half seconds; it swings back once let go.
	if pad.camera!=Vector2.ZERO: view.turn_look(pad.camera*2.5*seconds)
	if motion_steering:
		# Tilt turns; it never strafes. A device held level reports nothing, so
		# this sits alongside the stick rather than replacing it.
		var tilted := motion.look(seconds,motion_sensitivity)
		yaw=clampf(yaw+tilted.x,-1,1)
		pitch=clampf(pitch+tilted.y*(-1.0 if invert_motion_pitch else 1.0),-1,1)
	pitch=clampf(pitch+pad.pitch+screen.pitch,-1,1)
	throttle=clampi(throttle+pad.throttle+screen.throttle,-1,1)
	fire=fire or pad.fire or screen.get("fire",false);guns=guns or pad.guns or screen.guns;hook=hook or pad.hook or screen.hook;boost=boost or pad.boost or screen.boost
	# Fire held through a bank switch waits for a fresh press, so switching
	# to the harpoon mid-burst never looses it.
	if bank_fire_hold:
		if fire:fire=false
		else:bank_fire_hold=false
	# Auto fire with the original controls, from the key or the touch fire
	# button: only while the guns are selected.
	if auto_shot or (screen.get("auto",false) and guns_selected()):fire=true
	# A held trigger must be released after a swap, including restoration of
	# the full outfit. Every normal fire control auditions the test launcher.
	if demo_fire_hold:
		if not fire and not guns and not hook:demo_fire_hold=false
		fire=false;guns=false;hook=false
	elif session.demo_mode and demo_outfit.quick_test:fire=fire or guns or hook;guns=false;hook=false
	if stopping:perform("stop");throttle=0;boost=false
	var roll := 0.0
	if world.manual_roll:roll=clampf(float(Input.is_physical_key_pressed(key_bindings.roll_right))-int(Input.is_physical_key_pressed(key_bindings.roll_left))+pad.roll,-1,1)
	return {"yaw":yaw,"pitch":pitch,"strafe":strafe,"roll":roll,"fire":fire,"guns":guns,"hook":hook,"boost":boost,"throttle":throttle,"mouse_x":mouse_delta.x,"mouse_y":mouse_delta.y,"aim_point":view.aim_point(),"hook_aim":view.aim_point(true)}
func _unhandled_input(event: InputEvent) -> void:
	if preload("res://native/presentation/reconstruction_dialog.gd").is_open():return
	if page=="transit": return
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN] and mouse_wheel_throttle and page.is_empty() and not session.docked and world.region!=null and not world.region.cinematic() and not touch.enabled():
		wheel_throttle_remainder+=event.factor*(1 if event.button_index==MOUSE_BUTTON_WHEEL_UP else -1)
		var steps := int(wheel_throttle_remainder)
		wheel_throttle_remainder-=steps
		if steps!=0:
			if world.autopilot:world.cancel_autopilot()
			world.region.player.set_throttle(world.region.player.throttle_target+steps*25)
		get_viewport().set_input_as_handled();return
	if page.is_empty() and event is InputEventMouseMotion and mouse_steering_enabled():
		if free_look_held(): view.turn_look(event.relative*.004)
		else: mouse_steer+=event.relative*mouse_sensitivity*Vector2(1,1 if invert_mouse else -1)
	if event is InputEventKey and event.physical_keycode==key_bindings.autopilot and page.is_empty():
		if event.echo:return
		if event.pressed:
			if world.autopilot:
				autopilot_pressed_at=-1;autopilot_hold_used=true
				perform("autopilot")
			else:autopilot_pressed_at=Time.get_ticks_msec();autopilot_hold_used=false
		elif autopilot_pressed_at>=0:
			var held := autopilot_hold_used
			autopilot_pressed_at=-1
			if not held:perform("autopilot")
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode==KEY_ESCAPE:
			if page in ["dialogue","freeze","settings"]: return
			if page.is_empty(): show_pause()
			else: dock_back()
			return
		if event.physical_keycode==key_bindings.fullscreen: toggle_fullscreen()
		if event.physical_keycode==key_bindings.save: save_game()
		if not page.is_empty(): return
		for action in key_bindings:
			if action in ["fullscreen","save"]:continue
			if event.physical_keycode==key_bindings[action]: perform("stop" if action=="throttle_down" and mouse_wheel_throttle else action)
	if event is InputEventJoypadButton and page.is_empty() and controller.actions().has(event.button_index):
		# The camera button acts on release: held, it lends the right stick
		# to the camera instead.
		if event.button_index==controller.look_button():
			if not event.pressed and not controller.look_hold_used:perform(controller.actions()[event.button_index])
		elif event.pressed:perform(controller.actions()[event.button_index])
func touch_throttle(percent: int) -> void:
	if not page.is_empty() or world.region==null or session.docked: return
	if world.autopilot: world.cancel_autopilot()
	world.region.player.set_throttle(percent)
func touch_action(action: String) -> void:
	if action=="menu":show_pause()
	elif action=="full":toggle_fullscreen()
	elif action=="auto_guns" and page.is_empty():
		notice(tr("Auto guns on · tap to stop") if touch.automatic_weapons.has("guns") else tr("Auto guns off"))
		dive_audio.cue("beep")
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
		if web_standalone(): notice(tr("Already running without browser bars."))
		else: notice(tr(FullscreenButton.NO_FULLSCREEN))
		return
	Display.set_fullscreen(not Display.fullscreen(),settings_path)
func controller_connection(device: int, connected: bool) -> void:
	if not connected and is_instance_valid(map_widget):map_widget.release_cursor_device(device)
	if not connected and controller.device==device:
		controller.reset();controller.device=-1
		if session!=null and page.is_empty():show_pause()
func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT,NOTIFICATION_APPLICATION_PAUSED]:
		demo_weapon_bar.release_contacts()
		controller.reset();touch.reset();touch.release_contacts();mouse_steer=Vector2.ZERO
		if session!=null and page.is_empty():show_pause()
	if what==NOTIFICATION_WM_GO_BACK_REQUEST and session!=null and not preload("res://native/presentation/reconstruction_dialog.gd").is_open():touch_action("menu")
func cinematic_skip_requested(event: InputEvent) -> bool:
	if event is InputEventKey:
		return event.pressed and not event.echo and (event.keycode in [KEY_ENTER,KEY_SPACE,KEY_ESCAPE] or event.physical_keycode==key_bindings.fire)
	if event is InputEventMouseButton:return event.pressed and event.button_index==MOUSE_BUTTON_LEFT
	if event is InputEventJoypadButton:return event.pressed and event.button_index in [JOY_BUTTON_A,JOY_BUTTON_B,JOY_BUTTON_START,JOY_BUTTON_RIGHT_SHOULDER]
	if event is InputEventJoypadMotion:return event.axis==JOY_AXIS_TRIGGER_RIGHT and event.axis_value>.25
	return event is InputEventScreenTouch and event.pressed
func _input(event: InputEvent) -> void:
	if preload("res://native/presentation/reconstruction_dialog.gd").is_open():return
	FocusMap.before_move(get_viewport(),event)
	var was_touch := touch.enabled()
	touch.update_input(event,controller.deadzone)
	view.stabilize_touch_horizon=touch.enabled()
	if world.region!=null:world.region.player.touch_horizon_assist=touch.enabled()
	if was_touch!=touch.enabled():
		mouse_steer=Vector2.ZERO
		if touch.enabled():release_flight_mouse()
		elif not OS.has_feature("web"):capture_flight_mouse()
		layout()
	if handle_demo_weapon_input(event):get_viewport().set_input_as_handled();return
	if page in ["departure","opening"] or (page.is_empty() and view.transit_progress>=0):
		if cinematic_skip_requested(event):
			controller.accept(event);controller.blocked=true
			if page=="departure":finish_departure()
			elif page=="opening":opening.skip()
			else:end_transit_shot()
			weapon_presses.clear();world.weapon_pending.clear();suppress_fire_until_release=true
			get_viewport().set_input_as_handled();return
		if page in ["departure","opening"]:get_viewport().set_input_as_handled();return
	controller.accept(event)
	if chart_input(event):get_viewport().set_input_as_handled();return
	# A camera button pressed in a menu is not a tap in flight when let go.
	if event is InputEventJoypadButton and event.pressed and event.button_index==controller.look_button() and not page.is_empty():controller.look_hold_used=true
	if event is InputEventMouseButton and not event.pressed:
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and not Input.is_physical_key_pressed(key_bindings.fire) and not Input.is_physical_key_pressed(key_bindings.harpoon):suppress_fire_until_release=false
	if page.is_empty() and not suppress_fire_until_release:
		if event is InputEventMouseButton and event.pressed and not touch.enabled():
			if event.button_index==MOUSE_BUTTON_LEFT:weapon_presses.guns=true
			elif event.button_index==MOUSE_BUTTON_RIGHT:weapon_presses.hook=true
		elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode==key_bindings.fire:weapon_presses.fire=true
		elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode==key_bindings.harpoon:weapon_presses.hook=true
	if touch.handle(event):get_viewport().set_input_as_handled();return
	if page=="transit":return
	if page=="market" and market_category in ["trade","manufacture"] and event is InputEventJoypadButton and event.pressed and event.button_index in [JOY_BUTTON_LEFT_SHOULDER,JOY_BUTTON_RIGHT_SHOULDER]:
		switch_goods_tab("trade" if event.button_index==JOY_BUTTON_LEFT_SHOULDER else "manufacture");get_viewport().set_input_as_handled();return
	if page=="map" and event is InputEventJoypadButton and event.pressed and event.button_index in [JOY_BUTTON_LEFT_SHOULDER,JOY_BUTTON_RIGHT_SHOULDER] and is_instance_valid(map_slice):
		map_slice.step(-1 if event.button_index==JOY_BUTTON_LEFT_SHOULDER else 1);get_viewport().set_input_as_handled();return
	if event is InputEventJoypadButton and event.pressed and event.button_index in [JOY_BUTTON_B,JOY_BUTTON_START]:
		if page in ["freeze","settings"]:return
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
	if page in ["map","stream"] and is_instance_valid(map_widget):
		focus_option="";map_widget.grab_focus();return
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
	if session.demo_mode and action=="dock":show_demo();return
	if session.demo_mode and demo_outfit.quick_test and action=="bank":step_demo_weapon(1);return
	if action in ["auto_fire","camera","bank","autopilot","time","time_up","time_down","lights"]: dive_audio.cue("beep")
	match action:
		"auto_fire":
			auto_fire=not auto_fire
			if auto_fire: world.cancel_autopilot(tr("Auto fire enabled"))
			else: notice(tr("Auto fire off"))
		"throttle_up","throttle_down":
			if world.autopilot:world.cancel_autopilot()
			world.region.player.set_throttle(world.region.player.throttle_target+(25 if action=="throttle_up" else -25))
		"stop":
			if world.region==null or session.docked or world.region.cinematic():return
			if world.autopilot:world.cancel_autopilot()
			world.region.player.stop()
		"camera":
			view.camera_mode=(view.camera_mode+1)%4; save_settings(); notice(tr("Camera · %s")%view.camera_names()[view.camera_mode])
		"bank":
			# A shot still waiting for the next tick belonged to the old bank.
			world.region.loadout.cycle();world.weapon_pending.erase("fire");bank_fire_hold=true
		"dock":
			if world.at_gate(0):
				show_stream_menu()
			elif world.in_docking_area() and world.dock_denial().is_empty():ask_dock()
			elif world.dock(): finish_docking()
		"map": show_map()
		"autopilot":
			auto_fire=false
			if world.autopilot:world.cancel_autopilot(tr("Manual control"))
			else:show_destinations()
		"time": world.cycle_speed()
		"time_up","time_down": world.step_speed(1 if action=="time_up" else -1)
		"lights":
			if modern_graphics:
				if headlight_mode!=Headlights.Mode.OFF:headlight_previous=headlight_mode;headlight_mode=Headlights.Mode.OFF
				else:headlight_mode=headlight_previous
				apply_headlights();save_settings()
			else:notice(tr("Headlights need Enhanced lighting."))
func control_name(action: String) -> String:
	"""What the player presses for action with the controls in use: the touch
	button's caption, the pad button or the bound key."""
	if touch.enabled() and touch.labels().has(action):return touch.labels()[action]
	if controller.device>=0:
		for button in controller.actions():
			var performed: String=controller.actions()[button]
			if performed==action or (action=="time" and performed=="time_up"):return pad_name(button)
	return OS.get_keycode_string(key_bindings[action])
func keyed_text(id: int) -> String:
	"""Imported text id, naming the controls in use where it names a phone key."""
	return preload("res://native/presentation/instructions.gd").with_controls(id,session.text(id,session.name),func(action: String) -> String:
		return tr("System")+" → "+tr("Help") if action=="help" else control_name(action))
func pad_name(button: int) -> String:
	match button:
		JOY_BUTTON_A:return "A"
		JOY_BUTTON_X:return "X"
		JOY_BUTTON_Y:return "Y"
		JOY_BUTTON_LEFT_SHOULDER:return "LB"
		JOY_BUTTON_RIGHT_SHOULDER:return "RB"
		JOY_BUTTON_BACK:return tr("View")
		JOY_BUTTON_DPAD_LEFT:return tr("D-pad left")
		JOY_BUTTON_DPAD_RIGHT:return tr("D-pad right")
		JOY_BUTTON_DPAD_UP:return tr("D-pad up")
		JOY_BUTTON_DPAD_DOWN:return tr("D-pad down")
	return tr("Pad %d")%button
func ask_dock() -> void:
	"""br.a: the dock key asks "Dock to #?" (272) over the paused sea;
	autopilot arriving docks without asking, as in the original."""
	var station_name: String=session.stations[session.station_id].name
	confirm(session.text(24),session.text(272,station_name),session.text(45),func():
		close_page()
		if world.dock(): finish_docking()
		else: notice(world.message),close_page)
func finish_docking() -> void:
	clear_notices()
	show_station()
	save_game(false)
func show_pause() -> void:
	open_page(tr("Paused"),"pause")
	iconic(button(tr("Resume"),close_page),"resume")
	if session.demo_mode:
		primary(iconic(button(tr("Test loadout"),show_demo),"hangar"))
		iconic(button(tr("Restore fitted weapons") if demo_outfit.quick_test else tr("Quick weapon test"),func():
			if demo_outfit.quick_test:finish_demo_weapon_test();close_page()
			else:start_demo_weapon_test()),"hangar")
		iconic(button(tr("Reset test area"),reset_demo),"reload")
	if touch.enabled():
		# The touch overlay keeps only what a dive needs to hand; the view and
		# fullscreen switches live here.
		iconic(option(tr("Camera · %s")%view.camera_names()[view.camera_mode],"camera",func():perform("camera");show_pause()),"camera")
		if touch.show_fullscreen: iconic(button(tr("Fullscreen / windowed"),toggle_fullscreen),"fullscreen")
	iconic(button(tr("Overworld map"),show_map),"map")
	if not session.demo_mode:iconic(button(tr("Mission journal"),show_journal),"journal")
	iconic(button(tr("Ship and cargo"),show_ship_status),"cargo")
	if not session.demo_mode:iconic(button(tr("Profile and medals"),show_profile),"person")
	var freeze := iconic(button(tr("Action freeze"),show_action_freeze),"freeze")
	freeze.disabled=session.docked or world.region==null
	freeze.tooltip_text=tr("Freeze the game and move the camera.") if not freeze.disabled else tr("Not available while docked.")
	iconic(button(tr("Settings"),show_settings),"controls")
	iconic(button(tr("Help"),show_help),"help")
	iconic(button(tr("Reference"),show_reference),"book")
	if session.demo_mode:
		iconic(button(tr("Return to main menu"),return_to_menu),"exit")
		return
	iconic(button(tr("Transfer save"),show_transfer),"transfer")
	iconic(button(tr("Reload station checkpoint"),func(): confirm(tr("Reload checkpoint"),
		tr("Return to your last saved station? Everything since that checkpoint is lost."),
		tr("Reload checkpoint"),reload_game,show_pause)),"reload")
	iconic(button(tr("Return to main menu"),func(): confirm(tr("Main menu"),
		(tr("The game is saved at this station first.") if session.docked
			else tr("Progress since your last station save will be lost.")),
		tr("Return to main menu"),return_to_menu,show_pause)),"exit")
func show_demo(refresh: bool=true) -> void:
	if not session.demo_mode:return
	if refresh:demo_outfit.read_outfit(session)
	open_page(tr("Demo mode"),"demo")
	label(tr("All ships and equipment are available. Campaign saves are untouched."),16)
	iconic(button(tr("Quick weapon test"),func():start_demo_weapon_test(true)),"hangar")
	label(tr("Switch weapons in flight and fire them one at a time."),14)
	# Keep the launch action in reach while the outfit scrolls, especially
	# after returning from the last slot on a phone.
	var shell: Node=page_scroll.get_parent()
	var apply := primary(iconic(button(tr("Apply and test"),apply_demo,shell),"depart"));apply.name="DemoApply"
	shell.move_child(apply,page_scroll.get_index()+1)
	label(tr("Unarmed ships ahead; live harpoon targets to the left. Reset the test area to repair, empty cargo and respawn targets."),15)
	var hull: Array=session.data.tables.ships[demo_outfit.ship_id]
	var vessel := option(content.ship_name(demo_outfit.ship_id)+" · "+tr("Equipment slots")+": "+str(int(hull[4])),"demo_ship",func():show_demo_picker(-1))
	demo_item_icon(vessel,demo_outfit.ship_id,"ships")
	for slot in demo_outfit.equipment.size():
		var id: int=demo_outfit.equipment[slot]
		var title: String=tr("Empty") if id<0 else item_name(id,"equipment")
		var choose := option("%d.  %s"%[slot+1,title],"demo_slot_%d"%slot,func():show_demo_picker(slot))
		demo_item_icon(choose,id,"equipment")
		if id>=0:label(EquipmentInfo.stats(session.make_equipment(id)),14).modulate=colours().dim
	back_row(close_page)

func demo_item_icon(control: Button, id: int, kind: String) -> void:
	control.icon=imported_art.item(id,kind) if id>=0 else null
	control.expand_icon=true;control.icon_alignment=HORIZONTAL_ALIGNMENT_LEFT
	control.add_theme_constant_override("icon_max_width",72 if kind=="ships" else 48)
	control.add_theme_constant_override("h_separation",14)
	control.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	control.custom_minimum_size.y=64 if touch.enabled() else 56
	control.clip_text=true;control.tooltip_text=control.text

func show_demo_picker(slot: int) -> void:
	if not session.demo_mode:return
	open_page(tr("Ship") if slot<0 else tr("Equipment"),"demo_picker")
	var search := LineEdit.new();search.placeholder_text=tr("Search");search.clear_button_enabled=true
	search.custom_minimum_size.y=48;search.add_theme_font_size_override("font_size",18);column.add_child(search)
	var rows: Array=[]
	if slot>=0:
		button(tr("Empty"),func():demo_outfit.select_equipment(session,slot,-1);show_demo(false))
	var count: int=session.data.tables.ships.size() if slot<0 else session.data.tables.equipment.size()
	for id in count:
		var row := VBoxContainer.new();row.add_theme_constant_override("separation",4);column.add_child(row)
		var title: String=content.ship_name(id) if slot<0 else item_name(id,"equipment")
		var choose := button(title,func():
			if slot<0:demo_outfit.select_ship(session,id)
			else:demo_outfit.select_equipment(session,slot,id)
			focus_option="demo_ship" if slot<0 else "demo_slot_%d"%slot
			show_demo(false),row)
		demo_item_icon(choose,id,"ships" if slot<0 else "equipment");choose.set_meta("demo_item",id)
		var details: String=tr("Equipment slots")+": "+str(int(session.data.tables.ships[id][4])) if slot<0 else EquipmentInfo.stats(session.make_equipment(id))
		label(details,14,row).modulate=colours().dim
		row.set_meta("search",(title+" "+details).to_lower());rows.append(row)
	var empty := label(tr("No matches"),16);empty.hide()
	search.text_changed.connect(func(value: String):
		var any := false
		for row in rows:
			row.visible=value.strip_edges().to_lower() in str(row.get_meta("search"));any=any or row.visible
		empty.visible=not any;page_scroll.scroll_vertical=0)
	back_row(func():show_demo(false))

func apply_demo() -> void:
	if not session.demo_mode:return
	demo_outfit.apply(session)
	clear_notices();flight_ms=0;stream_prompted=false;stream_exit_active=false
	# Restarting the range teleports the hull; its old wake belongs to the
	# previous run even when the same ship model remains selected.
	view.combat.reset()
	world.depart();view.rebuild();view._process(0)
	if demo_outfit.quick_test:demo_outfit.refresh_weapons(world);clear_demo_fire();refresh_demo_weapon_bar()
	close_page()

func start_demo_weapon_test(apply_outfit: bool=false) -> void:
	if not session.demo_mode:return
	if apply_outfit:apply_demo()
	clear_notices()
	demo_outfit.quick_test=true;demo_outfit.refresh_weapons(world)
	clear_demo_fire();refresh_demo_weapon_bar();close_page()

func step_demo_weapon(direction: int) -> void:
	if not session.demo_mode or not demo_outfit.quick_test:return
	demo_outfit.step_weapon(world,direction)
	clear_demo_fire();refresh_demo_weapon_bar()

func finish_demo_weapon_test() -> void:
	if not session.demo_mode:return
	demo_outfit.quick_test=false;demo_outfit.refresh_weapons(world)
	clear_demo_fire();demo_weapon_bar.hide();place_message()
	notice(tr("Fitted weapons restored"))

func clear_demo_fire() -> void:
	weapon_presses.clear();world.weapon_pending.clear();auto_fire=false;interrupted_auto={}
	touch.automatic_weapons.clear();touch.weapon_presses.clear();touch.last_weapon_tap=""
	demo_fire_hold=true;controller.blocked=true
	view.combat.reset(true);world.region.visual_events.clear()
	# End the previous audition without adding a UI beep over the new shot.
	for voice in dive_audio.voices:voice.stop()
	dive_audio.pending.clear();dive_audio.last_serial=world.region.audio_serial
	dive_audio.priority_until=-1;dive_audio.last_priority=0;dive_audio.last_played.clear()
	dive_audio.collect_launches(world.region)

func refresh_demo_weapon_bar() -> void:
	if not session.demo_mode or not demo_outfit.quick_test:return
	var ids: Array=demo_outfit.weapon_ids(session)
	var prompt := tr("Tap arrows to switch · fire normally")
	if not touch.enabled():
		var pad: bool=touch.last_input=="gamepad" and controller.device>=0
		prompt=tr("%s · Next weapon")%(control_name("bank") if pad else OS.get_keycode_string(key_bindings.bank))
		if not pad:
			if KEY_BRACKETLEFT not in key_bindings.values() and KEY_BRACKETRIGHT not in key_bindings.values():prompt="[ / ]  ·  "+tr("Previous / next weapon")
			if KEY_BACKSPACE not in key_bindings.values():prompt+="     ·     "+OS.get_keycode_string(KEY_BACKSPACE)+"  ·  "+tr("Back")
	demo_weapon_bar.show_weapon(item_name(demo_outfit.quick_weapon,"equipment"),imported_art.item(demo_outfit.quick_weapon,"equipment"),ids.find(demo_outfit.quick_weapon),ids.size(),prompt)
	demo_weapon_bar.visible=page.is_empty();place_demo_weapon_bar();place_message()

func place_demo_weapon_bar() -> void:
	if not demo_weapon_bar.is_inside_tree():return
	demo_weapon_bar.set_touch(touch.enabled())
	var width := minf(500,ui.size.x-32)
	if touch.enabled() and ui.size.x<ui.size.y:width=minf(width,ui.size.x-128)
	if touch.enabled() and ui.size.x>ui.size.y:width=minf(width,maxf(360,ui.size.x-500))
	demo_weapon_bar.size=Vector2(width,demo_weapon_bar.get_combined_minimum_size().y)
	demo_weapon_bar.position=Vector2((ui.size.x-width)*.5,190 if ui.size.x<ui.size.y else 58)
	if touch.enabled() and ui.size.x<ui.size.y:demo_weapon_bar.position.x=16

func handle_demo_weapon_input(event: InputEvent) -> bool:
	if session==null or not session.demo_mode or not page.is_empty() or not demo_outfit.quick_test:return false
	if event is InputEventKey or event is InputEventJoypadButton or event is InputEventScreenTouch:refresh_demo_weapon_bar()
	# A finger that began steering or looking keeps that role when it crosses
	# the bar. Only a fresh contact there belongs to the weapon selector.
	if (event is InputEventScreenTouch or event is InputEventScreenDrag) and touch.fingers.has(event.index):return false
	if demo_weapon_bar.handle_pointer(event,not mouse_is_captured()):
		if event is InputEventMouseButton and event.pressed:suppress_fire_until_release=true
		return true
	if event is InputEventKey and event.physical_keycode==KEY_BACKSPACE and KEY_BACKSPACE not in key_bindings.values():
		if event.pressed and not event.echo:finish_demo_weapon_test()
		return true
	if event is InputEventKey and event.physical_keycode in [KEY_BRACKETLEFT,KEY_BRACKETRIGHT] and event.physical_keycode not in key_bindings.values():
		if event.pressed and not event.echo:step_demo_weapon(-1 if event.physical_keycode==KEY_BRACKETLEFT else 1)
		return true
	if event is InputEventKey and event.physical_keycode==key_bindings.bank:
		if event.pressed and not event.echo:step_demo_weapon(-1 if event.shift_pressed else 1)
		return true
	return false

func reset_demo() -> void:
	if not session.demo_mode:return
	demo_outfit.read_outfit(session);apply_demo()

func show_journal() -> void:
	open_page(tr("Mission journal"),"journal")
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
		if mission.has_destination() and not mission.destination_name.is_empty():
			label(tr("Destination: %s")%mission.destination_name,16,card)
			if mission.destination>=0 and mission.destination<session.stations.size() and not mission.completed and not mission.failed:
				var arrived: bool=session.docked and mission.destination==session.station_id
				var navigate := button(tr("At destination") if arrived else (tr("Depart & autonavigate") if session.docked else tr("Autonavigate to destination")),func():autonavigate_from_journal(mission.destination),card)
				navigate.disabled=arrived;navigate.set_meta("journal_destination",mission.destination)
		if mission.reward>0: label(Coin.coins(tr("Reward: %d cr")%mission.reward),16,card)
		var deadline: String = info.deadline(mission)
		if not deadline.is_empty(): label(deadline,16,card)
		if mission==session.campaign.secondary: button(tr("Abandon contract"),func(): confirm(tr("Abandon contract"),
			tr("Give up \"%s\"? The deposit is not returned.") % session.title(mission),
			tr("Abandon contract"),func(): session.abandon_contract(); show_journal(),show_journal),card)
	label(tr("Rank %d  ·  Stations discovered %d / 200  ·  Catches %d  ·  Enemies defeated %d")%[session.counters.k,session.counters.m,session.counters.h,session.counters.f],16)
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
func autonavigate_from_journal(destination: int, back: Callable=Callable()) -> void:
	# Validate before leaving the berth; a denied route keeps the journal open.
	var denial: String=world.route_denial(destination)
	if not denial.is_empty():notice(denial);return
	if session.docked and destination==session.station_id:notice(tr("Already docked at the destination."));return
	if ask_travel(destination,func():autonavigate_from_journal(destination,back),back if back.is_valid() else show_journal):return
	if session.docked:
		depart()
		if session.docked:return
		if page=="departure":departure_destination=destination;departure_route="objective";return
	if world.route_to_objective(destination):
		stream_prompted=false
		auto_fire=false
		if page not in ["dialogue","departure"]:close_page()
	else:notice(world.message)
## Where Back leaves the ship page for: the hub that opened it.
var ship_status_back := Callable()
func show_ship_status(back: Callable=Callable()) -> void:
	ship_status_back=back
	open_page(tr("Ship and cargo"),"ship_status")
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
	caption(tr("Your vessel"),11,naming,4)
	var about: String=item_description(ship.id,"ships")
	if not about.is_empty():
		var described := label(about,14,vessel);described.add_theme_color_override("font_color",palette.text)
	if ui.size.y>=700 and ui.size.x>=900:
		var preview=preload("res://native/presentation/ship_preview.gd").new()
		identity.add_child(preview);preview.configure(content,ship.id,modern_graphics,view.library)
		preview.custom_minimum_size=Vector2(240,170)
	var protections := HBoxContainer.new();protections.add_theme_constant_override("separation",10);vessel.add_child(protections)
	for entry in [["hull",tr("Hull"),ship.hull],["shield",tr("Shield"),ship.shield],["armor",tr("Armor"),ship.armor]]:
		figure_tile(entry[0],entry[1],str(entry[2]),protections)
	var used: int=ship.equipment.filter(func(item):return item!=null).size()
	var rows: Array=[["shield",tr("Protection limits"),"%d – %d"%[ship.minimum_depth,ship.maximum_depth]],["cargo",tr("Cargo capacity"),tr("%d / %d t")%[ship.cargo_used,ship.capacity()]],["grid",tr("Equipment slots"),"%d / %d"%[used,ship.slots]],["controls",tr("Handling"),str(handling(ship,true))]]
	if not session.docked and world.region!=null:
		var health=world.region.player.health
		rows.append(["hull",tr("Current condition"),tr("Hull %d · Shield %d · Armor %d")%[health.hull,health.shield,health.armor]])
	figure_rows(rows,vessel)
	# What it carries and what is fitted.
	var holds := VBoxContainer.new();holds.size_flags_horizontal=Control.SIZE_EXPAND_FILL;holds.add_theme_constant_override("separation",14);body.add_child(holds)
	var manifest := titled_glass("cargo",tr("Cargo manifest"),holds)
	if ship.cargo.is_empty():
		var empty := label(tr("Cargo hold empty"),16,manifest);empty.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;empty.add_theme_color_override("font_color",palette.dim)
	for item in ship.cargo:
		compact_manifest(imported_art.item(item.id),tr("%s · %d units")%[item_name(item.id),item.owned],tr("Cargo"),item_description(item.id),manifest)
	var systems := titled_glass("system",tr("Installed systems"),holds)
	if used==0: label(tr("No equipment installed."),16,systems).add_theme_color_override("font_color",palette.dim)
	for item in ship.equipment:
		if item!=null:compact_manifest(imported_art.item(item.id,"equipment"),item_name(item.id,"equipment"),EquipmentInfo.stats(item),item_description(item.id,"equipment"),systems)
	back_row(ship_status_back if ship_status_back.is_valid() else show_station_status if session.docked else show_pause)
func handling(ship, fitted: bool) -> int:
	"""How readily a hull turns: the ship table's steering figure, with a
	fitted steering system's bonus when asked for."""
	return roundi((ship.steering() if fitted else ship.base_steering)*100.0)
func split_row(parent: Node, gap: int) -> BoxContainer:
	"""Side by side on a wide screen, one above the other on a narrow one."""
	var row: BoxContainer=HBoxContainer.new() if ui.size.x>=900 else VBoxContainer.new()
	row.add_theme_constant_override("separation",gap);row.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.size_flags_vertical=Control.SIZE_EXPAND_FILL;parent.add_child(row);return row
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
func tier_names() -> Array:
	return [tr("Locked"),tr("Gold"),tr("Silver"),tr("Bronze")]
const TIER_COLOURS := [Color("85939b"),Color("e7c77f"),Color("b6d0de"),Color("ce9b7b")]
func show_profile(medal_view: bool=false) -> void:
	open_page(tr("Medals") if medal_view else tr("Player profile"),"profile",tr("Honours for your work below the surface") if medal_view else tr("Pilot record"))
	var palette := colours()
	var top := HBoxContainer.new();top.add_theme_constant_override("separation",12);column.add_child(top)
	var rank := glass(top,false,10);rank.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var rank_row := HBoxContainer.new();rank_row.add_theme_constant_override("separation",12);rank.add_child(rank_row)
	var portrait := art_image(imported_art.portrait(session.face_layers,session.face_photo),rank_row,72)
	if portrait!=null:portrait.name="PilotPortrait"
	else:line_icon("person",30,rank_row)
	var pilot := label(tr("%s · Rank %d")%[session.name,session.counters.k],22,rank_row);pilot.add_theme_color_override("font_color",palette.text)
	pilot.autowrap_mode=TextServer.AUTOWRAP_OFF;pilot.clip_text=true;pilot.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	var owned: int = session.medals.levels.filter(func(tier): return tier>0).size()
	if ui.size.x>=900: caption(tr("Medals %d / 24")%owned,12,rank_row,3).size_flags_horizontal=Control.SIZE_SHRINK_END
	var swap := iconic(button(tr("View statistics") if medal_view else tr("View medals"),func(): show_profile(not medal_view),top),"status" if medal_view else "medal",24)
	swap.size_flags_horizontal=Control.SIZE_SHRINK_END;swap.custom_minimum_size.x=230 if ui.size.x>=900 else 0
	if not medal_view:
		var record := titled_glass("status",tr("Statistics"),column)
		var tiles := GridContainer.new();tiles.columns=4 if ui.size.x>=1100 else 3 if ui.size.x>=800 else 2
		tiles.add_theme_constant_override("h_separation",10);tiles.add_theme_constant_override("v_separation",10);record.add_child(tiles)
		var entries: Array=[[tr("Time underway"),tr("%d h %02d min")%[session.elapsed_ms/3600000,(session.elapsed_ms/60000)%60]],[tr("Credits"),"%d"%session.credits],[tr("Depth record"),"%d–%d"%[session.counters.u,session.counters.t]]]
		for entry in [[tr("Enemies defeated"),"f"],[tr("Pirates defeated"),"o"],[tr("Creatures caught"),"h"],[tr("Fish killed"),"g"],[tr("Catches released"),"i"],[tr("Dead fish recovered (t)"),"p"],[tr("Crates recovered"),"r"],[tr("Stations discovered"),"m"],[tr("Regions entered"),"q"],[tr("Goods produced"),"n"],[tr("Contracts completed"),"j"],[tr("New equipment purchased"),"s"]]:
			entries.append([entry[0],str(session.counters[entry[1]])])
		for entry in entries:
			var cell := glass(tiles,false,8)
			var words := VBoxContainer.new();words.add_theme_constant_override("separation",2);cell.add_child(words)
			label(entry[1],22,words).add_theme_color_override("font_color",palette.text)
			var name_label := label(entry[0],13,words);name_label.add_theme_color_override("font_color",palette.dim)
			# Kept as plain text for readers and tests alike.
			name_label.set_meta("statistic","%s: %s"%entry)
	else:
		if session.medals.complete_set(): label(tr("Complete medal collection"),16).add_theme_color_override("font_color",palette.value)
		if session.medals.gold_set(): label(tr("All medals at their highest tier"),16).add_theme_color_override("font_color",palette.value)
		var count: int=session.medals.levels.size()
		medal_selection=clampi(medal_selection,0,count-1)
		var body := split_row(column,18)
		var row_height: int=64 if touch.enabled() else 58
		var list := scrolled_rows(body,"MedalRows")
		list.get_parent().get_parent().custom_minimum_size.y=list_height(count,row_height,body)
		for id in count:
			var tier: int=session.medals.levels[id]
			var cells := stock_row("Medal_%d"%id,id==medal_selection,row_height,func():medal_selection=id;focus_option="medal_%d"%id;show_profile(true),list)
			(cells.get_parent() as Button).set_meta("option","medal_%d"%id)
			medal_icon(tier,cells,40)
			var words := VBoxContainer.new();words.size_flags_horizontal=Control.SIZE_EXPAND_FILL;words.add_theme_constant_override("separation",0);words.mouse_filter=Control.MOUSE_FILTER_IGNORE;cells.add_child(words)
			label(session.text(int(content.data.constants.e["a:[[S"][id][0])),17,words).add_theme_color_override("font_color",palette.text if tier>0 else palette.dim)
			var badge := label(tier_names()[tier],13,words);badge.add_theme_color_override("font_color",TIER_COLOURS[tier])
			if tier==0: line_icon("lock",22,cells,palette.faint)
		var tier: int=session.medals.levels[medal_selection]
		var detail := VBoxContainer.new();detail.name="SelectedMedal";detail.add_theme_constant_override("separation",10)
		var frame := glass(body,true,16);frame.size_flags_horizontal=Control.SIZE_EXPAND_FILL;frame.add_child(detail)
		var title := caption(session.text(int(content.data.constants.e["a:[[S"][medal_selection][0])),22,detail,5);title.add_theme_color_override("font_color",palette.text)
		label(tier_names()[tier],17,detail).add_theme_color_override("font_color",TIER_COLOURS[tier])
		var stage := CenterContainer.new();stage.custom_minimum_size.y=150 if ui.size.y>=700 else 100;detail.add_child(stage)
		medal_icon(tier,stage,int(stage.custom_minimum_size.y)-10)
		var rule := ColorRect.new();rule.color=Color(palette.edge,.7);rule.custom_minimum_size.y=1;detail.add_child(rule)
		# A medal not yet won shows what its first tier asks for.
		label(medal_text(medal_selection,tier) if tier>0 else tr("Bronze · %s")%medal_text(medal_selection,3),16,detail).add_theme_color_override("font_color",palette.text)
		figure_rows([["",tr("Status"),tr("Awarded") if tier>0 else tr("Not yet awarded"),palette.value if tier>0 else palette.dim],["",tr("Tier"),tier_names()[tier],TIER_COLOURS[tier]]],detail)
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
func list_height(count: int, row_height: int, row: BoxContainer) -> float:
	"""Beside the detail a list takes the height the detail leaves it, down
	to a few rows. Above the detail it shows three and a half rows, so a cut
	row says there are more."""
	if row is HBoxContainer:return 2.5*(row_height+6)
	return minf(count,3.5)*(row_height+6)
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
	var badge: Label=label(["",tr("Gold"),tr("Silver"),tr("Bronze")][clampi(tier,0,3)],16,words)
	badge.modulate=[Color("85939b"),Color("e7c77f"),Color("b6d0de"),Color("ce9b7b")][clampi(tier,0,3)]
	if tier>0:label(medal_text(id,tier),16)
	if queue.size()>1:label("%d / %d"%[index+1,queue.size()],12).modulate=Color("7f96ad")
	var ok := button(tr("OK"),func():show_new_medal(queue,index+1))
	ok.custom_minimum_size.y=56 if touch.enabled() else 44
	focus_if_visible.call_deferred(ok)
func show_help(topic: int=-1) -> void:
	"""The phone game's Help: Instructions, its ten topics of imported text,
	Controls, and the Credits."""
	var guide=preload("res://native/presentation/instructions.gd")
	var topics: Array=guide.topics(content,control_name)
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
	if topics.is_empty():label(tr("The instructions come with the imported game text."),15)
	button(session.text(19),func():show_settings("controls",show_help))
	button(session.text(20),func():show_dialogue([{"speaker":session.text(20),"text":session.text(26)+"\n\n"+session.text(28)+"\n\n"+session.text(25)}],show_help))
	back_row(show_system if session.docked else show_pause)
func show_reference() -> void:
	"""The reference of the imported game, its story as far as this
	expedition has gone. The reader scrolls itself, so the page's own
	scroller stands aside."""
	open_page(tr("Reference"),"reference")
	back_row(show_system if session.docked else show_pause)
	page_scroll.hide();touch_scroll.scroll=null
	var reference=preload("res://native/wiki/wiki_panel.gd").new()
	reference.configure(content,-1 if session.campaign.finished() else session.campaign.chapter,golden(),false,{"art":imported_art,"modern":modern_graphics,"library":view.library})
	reference.size_flags_vertical=Control.SIZE_EXPAND_FILL
	page_scroll.add_sibling(reference)
func show_action_freeze() -> void:
	"""Holds the dive still and hands the camera over. Nothing is simulated or
	saved while frozen, so resuming continues the same dive untouched."""
	if session.docked or world.region==null or is_instance_valid(freeze_view): return
	if page.is_empty():interrupted_auto={"fire":auto_fire,"weapons":touch.automatic_weapons.keys()}
	auto_fire=false;weapon_presses.clear();world.weapon_pending.clear()
	catch_counter.hide()
	trip_tallies.hide()
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
	if resume:close_page()
	else:show_pause()
func show_transfer() -> void:
	if session.demo_mode:notice(tr("Demo sessions are not saved."));return
	open_page(tr("Transfer save"),"transfer")
	label(tr("Move your save to another device. The export contains only the save; each device imports its own JAR."),16)
	label(tr("The other device must have imported the same JAR."),15).modulate=Color("9dc9bd")
	if not save_files.available():
		label(tr("No file picker on this device."),15).modulate=Color("d7c399")
		back_row(show_system if session.docked else show_pause)
		return
	var exportable: bool=FileAccess.file_exists(save_path)
	var export_button := button(tr("Export save\u2026"),func():
		var record: Dictionary=transfer.collect(content.data,save_path)
		if record.is_empty(): notice(transfer.failure); return
		save_files.export_text(transfer.default_name(session),JSON.stringify(record)))
	export_button.disabled=not exportable
	export_button.tooltip_text=tr("Dock and save at a station first.") if not exportable else tr("Save to a file.")
	if session!=null and not session.docked:
		label(tr("The export contains your last station save."),15).modulate=Color("d7c399")
	button(tr("Import save\u2026"),func(): save_files.choose_import())
	label(tr("Importing replaces the save on this device. The old save is kept as a backup."),15).modulate=Color("d7c399")
	back_row(show_system if session.docked else show_pause)
func import_transfer(path: String) -> void:
	if session.demo_mode:notice(tr("Demo sessions are not saved."));return
	var record: Dictionary=transfer.read_export(content.data,path)
	if record.is_empty(): notice(transfer.failure); return
	if not transfer.install(content.data,save_path,record): notice(transfer.failure); return
	notice(tr("Save imported. Reloading\u2026"))
	reload_game()
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
		show_settings("touch",settings_return))
func show_settings(section: String="", back: Callable=Callable()) -> void:
	"""The same settings screen as the title's, over the game or the station."""
	open_page(tr("Settings"),"settings")
	overlay.hide()
	settings_return=back if back.is_valid() else (show_system if session.docked else show_pause)
	if not is_instance_valid(settings_panel):
		settings_panel=SettingsMenu.new();ui.add_child(settings_panel);settings_panel.z_index=60
		settings_panel.changed.connect(apply_setting)
		settings_panel.closed.connect(func():
			touch_scroll.scroll=null
			if page=="settings": settings_return.call())
	settings_panel.configure(settings_path,{
		"content_root":func():return content.root,
		"fullscreen":toggle_fullscreen,"layout_editor":func():settings_panel.hide();show_layout_editor(),
		"touch_active":touch.enabled,"calibrate":calibrate_tilt,
		"motion_enable":motion.enable,"buzz":func():buzz(150),"text":session.text,
		"auto_title":func():return dive_audio.title_track() if dive_audio.title_choice==0 else "",
		"content_language":func():return str(settings_config().get_value("interface","content_language","")),
		"world_note":world_note,"unsaved":func():return true},golden(),touch.enabled())
	settings_panel.open(section)
	touch_scroll.scroll=settings_panel.scroll;touch_scroll.gesture_control=null;touch_scroll.release()
func calibrate_tilt() -> void:
	if motion.calibrate(): notice(tr("Tilt centred"))
func apply_orientation() -> void:
	Display.apply_orientation(setting_index(settings_config(),"view","orientation",0,2))
func settings_config() -> ConfigFile:
	var config := ConfigFile.new();config.load(settings_path);return config
func world_note() -> String:
	var note:=tr("Current game: %s grid squares.")%Spacing.square_text(session.world_layout.spacing_meters)
	if world_spacing.meters()!=session.world_layout.spacing_meters:
		note+="\n"+tr("Next departure: %s grid squares.")%Spacing.square_text(world_spacing.meters())
	return note+"\n"+tr("Applies on next departure or load.")
func apply_language() -> void:
	"""The title chose the language at start; a change here takes effect at
	once. Pages are drawn again when next opened."""
	var config := settings_config()
	EngineLanguage.apply(EngineLanguage.resolve(str(config.get_value("interface","language",EngineLanguage.AUTO)),str(config.get_value("interface","content_language",""))))
func apply_setting(section: String, key: String) -> void:
	"""The panel has written the file; bring the running game in line with it."""
	var was_motion := motion_steering
	read_settings()
	match section:
		"interface":
			if key=="language": apply_language()
			elif key=="retro_hud": layout()
		"audio":
			dive_audio.apply_levels()
		"graphics":
			if key=="audio": dive_audio.set_enabled(graphics.audio)
			elif key=="reconstructed_textures": view.library.reload_textures()
			else: apply_graphics()
		"view":
			if key=="orientation": apply_orientation()
			elif key in ["fps_limit","vsync"]: Display.apply_frame_pacing(settings_config())
			else: apply_graphics()
		"input":
			if key=="touch": update_render_resolution();touch.arrange();layout()
			elif key=="touch_fixed_stick": touch.reset()
			elif key=="touch_drag_anywhere": touch.arrange()
			elif key=="motion" and motion_steering and not was_motion: motion.enable()
	save_settings()
func migrate_travel_bindings() -> void:
	# Move only the previous default pairs; preserve player-defined bindings.
	if [key_bindings.autopilot,key_bindings.time] in [[KEY_P,KEY_T],[KEY_T,KEY_Y]] and not KEY_R in key_bindings.values():
		key_bindings.autopilot=KEY_R;key_bindings.time=KEY_T
func read_settings() -> void:
	"""The settings file into the running systems. The settings screen writes
	the file; everything that reads a preference reads it from here."""
	var config := ConfigFile.new()
	if config.load(settings_path)==OK:
		for key in key_bindings: key_bindings[key]=setting_keycode(config,key,SettingsMenu.default_key(config,key))
		migrate_travel_bindings()
		for key in graphics: graphics[key]=bool(config.get_value("graphics",key,graphics[key]))
		modern_graphics=bool(config.get_value("graphics","modern",graphics.materials))
		# Migrate the former materials-only switch without carrying its Off state into New mode.
		if not config.has_section_key("graphics","modern") and not graphics.materials:graphics.materials=true
		# Only an old layout that gave W and S to pitch and throttle at once;
		# pitch moved to the arrows. A player's own WASD steering stays.
		if key_bindings.up==KEY_W and key_bindings.throttle_up==KEY_W: key_bindings.up=KEY_UP
		if key_bindings.down==KEY_S and key_bindings.throttle_down==KEY_S: key_bindings.down=KEY_DOWN
		mouse_sensitivity=setting_number(config,"keys","mouse_sensitivity",0.8,0.2,2.0); invert_mouse=bool(config.get_value("keys","invert_mouse",false))
		touch_look_sensitivity=setting_number(config,"input","touch_look",0.7,0.2,2.0)
		dive_audio.music_gain=setting_number(config,"audio","music",0.65,0.0,1.0); dive_audio.effects_gain=setting_number(config,"audio","effects",0.75,0.0,1.0)
		dive_audio.title_choice=setting_index(config,"audio","title_music",0,2)
		view.camera_mode=setting_index(config,"view","camera",0,3)
		dive_audio.apply_levels()
	view.combat.set_enhanced_weapons(SettingsMenu.config_flag(config,"graphics","weapon_effects",true))
	dive_audio.set_weapon_sounds_enabled(SettingsMenu.config_flag(config,"audio","weapon_sounds",true))
	graphics.merge(OceanOptions.read(config),true)
	headlight_mode=Headlights.read(config);headlight_previous=Headlights.previous(config)
	quality=GraphicsQuality.read(config);headlight_strength=GraphicsQuality.headlight_strength(config)
	water_colour=OceanOptions.water_colour(config)
	show_fps=bool(config.get_value("view","show_fps",false))
	touch.mode=setting_index(config,"input","touch",0,2)
	touch.drag_anywhere=bool(config.get_value("input","touch_drag_anywhere",false))
	touch.fixed_stick=bool(config.get_value("input","touch_fixed_stick",false))
	touch.mirror_fire_control=bool(config.get_value("input","touch_mirror_fire",false))
	touch.throttle_slider=bool(config.get_value("input","touch_throttle_slider",false))
	controller.deadzone=setting_number(config,"input","deadzone",.18,.05,.45)
	controller.invert=bool(config.get_value("input","invert_gamepad",false))
	vibration=bool(config.get_value("input","vibration",true))
	strafe_mode=setting_index(config,"input","strafe",0,2)
	mouse_wheel_throttle=bool(config.get_value("input","mouse_wheel_throttle",false))
	if not mouse_wheel_throttle:wheel_throttle_remainder=0.0
	controller.layout=controller.read_layout(config)
	controller.roles=controller.read_roles(config)
	world.set_smooth_steering(bool(config.get_value("input","smooth_steering",false)))
	world.set_manual_roll(bool(config.get_value("input","manual_roll",false)))
	world.objective_travel_mode=setting_index(config,"gameplay","objective_travel",0,1)
	world.ship_collisions=bool(config.get_value("gameplay","ship_collisions",true))
	view.boost_fov=bool(config.get_value("view","boost_fov",true))
	original_weapons=bool(config.get_value("input","original_weapons",false));touch.original_weapons=original_weapons
	touch.layout=preload("res://native/input/touch_layout.gd").decode(config.get_value("input",TOUCH_LAYOUT_KEY,""))
	aspect_ratio=Display.valid(str(config.get_value("view","aspect_ratio","auto")))
	motion_steering=bool(config.get_value("input","motion",false))
	motion_sensitivity=setting_number(config,"input","motion_sensitivity",0.5,0.0,1.0)
	invert_motion_pitch=bool(config.get_value("input","motion_invert",false))
	gameplay_hints=bool(config.get_value("interface","hints",true))
	flight_messages=bool(config.get_value("interface","flight_messages",true))
	dock_prompts=bool(config.get_value("interface","dock_prompts",true))
	autopilot_status=bool(config.get_value("interface","autopilot_status",false))
	friend_labels=bool(config.get_value("interface","friend_labels",true))
	waypoint_edge=bool(config.get_value("interface","waypoint_edge",true))
	fishing_feedback=setting_index(config,"interface","fishing_feedback",SettingsMenu.FishingFeedback.BOTH,SettingsMenu.FishingFeedback.NONE)
	retro=bool(config.get_value("interface","retro_hud",true))
	damage_feedback.flash_enabled=bool(config.get_value("interface","hit_flash",true))
	hit_shake=bool(config.get_value("interface","hit_shake",true))
	damage_feedback.pulse_enabled=bool(config.get_value("interface","low_hull_pulse",true))
	damage_feedback.readout_enabled=bool(config.get_value("interface","hull_readout",true))
	world_spacing.read_config(config);world.spacing_meters=world_spacing.meters()
	Region.split_gates=bool(config.get_value("world","split_gates",true))
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
	config.set_value("graphics","headlight_previous",headlight_previous)
	Headlights.write(config,headlight_mode)
	config.set_value("input","touch",touch.mode);config.set_value("input","deadzone",controller.deadzone);config.set_value("input","invert_gamepad",controller.invert)
	config.set_value("input","vibration",vibration)
	config.set_value("graphics","modern",modern_graphics)
	config.set_value("view","camera",view.camera_mode)
	config.set_value("keys","mouse_sensitivity",mouse_sensitivity); config.set_value("keys","invert_mouse",invert_mouse)
	config.set_value("input","touch_look",touch_look_sensitivity)
	config.set_value("input","touch_drag_anywhere",touch.drag_anywhere)
	config.set_value("input","touch_fixed_stick",touch.fixed_stick)
	config.set_value("input","touch_mirror_fire",touch.mirror_fire_control)
	config.set_value("input","touch_throttle_slider",touch.throttle_slider)
	config.set_value("input","strafe",strafe_mode)
	config.set_value("input","mouse_wheel_throttle",mouse_wheel_throttle)
	config.set_value("input","pad_layout",controller.layout)
	for index in 4: config.set_value("input",controller.AXIS_KEYS[index],controller.roles[index])
	config.set_value("input","smooth_steering",world.smooth_steering)
	config.set_value("input","manual_roll",world.manual_roll)
	config.set_value("gameplay","objective_travel",world.objective_travel_mode)
	config.set_value("gameplay","ship_collisions",world.ship_collisions)
	config.set_value("view","boost_fov",view.boost_fov)
	config.set_value("input","original_weapons",original_weapons)
	config.set_value("input","motion",motion_steering);config.set_value("input","motion_sensitivity",motion_sensitivity)
	config.set_value("input","motion_invert",invert_motion_pitch)
	config.set_value("input",TOUCH_LAYOUT_KEY,preload("res://native/input/touch_layout.gd").encode(touch.layout))
	config.set_value("view","aspect_ratio",aspect_ratio)
	config.set_value("interface","hints",gameplay_hints)
	config.set_value("interface","flight_messages",flight_messages);config.set_value("interface","dock_prompts",dock_prompts)
	config.set_value("interface","autopilot_status",autopilot_status);config.set_value("interface","friend_labels",friend_labels)
	config.set_value("interface","waypoint_edge",waypoint_edge)
	config.set_value("interface","fishing_feedback",fishing_feedback)
	config.set_value("interface","retro_hud",retro)
	config.set_value("audio","music",dive_audio.music_gain); config.set_value("audio","effects",dive_audio.effects_gain)
	config.set_value("graphics","weapon_effects",view.combat.enhanced_weapons)
	config.set_value("audio","weapon_sounds",dive_audio.weapon_sounds_enabled)
	config.set_value("audio","title_music",dive_audio.title_choice)
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
	view.set_ship_smoothing(graphics.ship_smoothing)
	view.set_atmosphere(graphics)
	abyss.set_atmosphere(graphics)
	abyss.set_water_colour(water_colour)
	if rebuild:view.revision=-1
	terrain.apply_pack(view.pack)
	fps_counter.set_enabled(show_fps)
	var shadows: int=quality.shadows if modern_graphics else 3
	view.set_shadow_level(shadows);abyss.set_shadow_level(shadows)
	apply_headlights()
	view.set_depth_limits(graphics.depth_limits,graphics.depth_limits_always)
	var env := abyss.environment.environment
	env.volumetric_fog_enabled=modern_graphics and graphics.volumetric and RenderingServer.get_current_rendering_method()=="forward_plus"
	env.ssao_enabled=modern_graphics and graphics.detail
	env.glow_enabled=modern_graphics;abyss.particles.visible=true
	overlay.decorated=true;overlay.queue_redraw()
	layout()
func apply_headlights() -> void:
	view.set_headlight_mode(headlight_mode)
	abyss.set_headlight_beams(modern_graphics and headlight_mode==Headlights.Mode.LIGHT_BEAMS)
	abyss.set_headlights(modern_graphics and Headlights.casts_light(headlight_mode))
	abyss.set_headlight_strength(headlight_strength);view.set_headlight_strength(headlight_strength)
	if headlight_mode!=Headlights.Mode.OFF:headlight_previous=headlight_mode
func station_identity(parent: Node) -> void:
	var station: Dictionary=session.stations[session.station_id]
	var identity:=HBoxContainer.new();identity.name="StationIdentity";identity.add_theme_constant_override("separation",16);parent.add_child(identity)
	# The gold logo for the gold collection, the faction's otherwise (ch).
	var emblem := art_image(imported_art.image("logo_2" if golden() else "logo_0" if session.is_colonist_station() else "logo_1"),identity,56)
	if emblem!=null: emblem.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	var words:=VBoxContainer.new();words.size_flags_horizontal=Control.SIZE_EXPAND_FILL;words.add_theme_constant_override("separation",2);words.alignment=BoxContainer.ALIGNMENT_CENTER;identity.add_child(words)
	# Unwrapped: a wrapping label measured before the panel has its width
	# reports a column of single words, and the dock panel is sized from it.
	var faction := label(tr("Colonists") if session.is_colonist_station() else tr("Rebels"),20,words);faction.add_theme_color_override("font_color",colours().text);faction.autowrap_mode=TextServer.AUTOWRAP_OFF
	var standing := label(Coin.coins(tr("Tech level %d  ·  %d cr")%[station.tech,session.credits]),15,words);standing.add_theme_color_override("font_color",colours().dim);standing.autowrap_mode=TextServer.AUTOWRAP_OFF
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
func unavailable(node: Button, reason: String) -> void:
	if reason.is_empty():return
	reason=plain_money(reason)
	# The original answers these selections with a refusal. Keep mouse, touch
	# and keyboard activation, while making the unavailable action look dim.
	node.set_meta("unavailable_reason",reason)
	node.tooltip_text=reason;node.accessibility_description=reason
	for connection in node.pressed.get_connections():node.pressed.disconnect(connection.callable)
	node.pressed.connect(func():notice(reason))
	var palette := colours()
	for state in ["normal","hover","pressed"]:
		var style := node.get_theme_stylebox(state).duplicate() as StyleBoxFlat
		style.bg_color=Color(palette.card,.4)
		style.border_color=Color(palette.edge,.45 if state=="normal" else .75)
		style.shadow_size=0;node.add_theme_stylebox_override(state,style)
	for state in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:
		node.add_theme_color_override(state,palette.faint)
	# Leave the focus outline visible for keyboard/controller navigation.
	for child in node.get_children():
		if child is CanvasItem:child.modulate=Color(.65,.68,.72,.6)
func station_service_reason(kind: String) -> String:
	var denial: int=session.service_denial(kind)
	if denial>=0:return session.text(denial)
	var station: Dictionary=session.stations[session.station_id]
	match kind:
		"ships":
			if station.ships.is_empty():return tr("No ships for sale at this station.")
		"manufacture":
			if session.is_colonist_station():return tr("Manufacturing is available at rebel stations.")
			if economy.recipes(station).is_empty():return tr("No recipes available at this station's technology level.")
		"missions":
			if station.missions.is_empty():return tr("No contracts on this station's board.")
	return ""
func station_service(title: String, text: String, kind: String, icon: String, art: Texture2D, parent: Node) -> void:
	var reason := station_service_reason(kind)
	var node := service_card(title,text,icon,art,func():show_market(kind,true),parent)
	unavailable(node,reason)
func market_action(node: Button, denial: int) -> void:
	if denial<0:return
	var reason: String=session.text(denial)
	unavailable(node,reason)
func service_grid(parent: Node=null) -> GridContainer:
	var grid := GridContainer.new();grid.columns=2 if ui.size.x>=900 else 1;grid.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation",16);grid.add_theme_constant_override("v_separation",16);(parent if parent!=null else column).add_child(grid)
	return grid
func show_station() -> void:
	if session.demo_mode:show_demo();return
	open_page(session.stations[session.station_id].name,"station")
	column.add_theme_constant_override("separation",12)
	station_identity(glass(column,false,14))
	var services := [
		[tr("Hangar").to_upper(),tr("Equipment shop and ship dealer"),"hangar",show_hangar],
		[tr("Missions").to_upper(),tr("Current objectives and available contracts"),"missions",show_station_missions],
		[tr("Map").to_upper(),tr("Stations, routes and S.T.R.E.A.M."),"map",show_map],
		[tr("Trade").to_upper(),tr("Buy, sell and manufacture"),"trade",func():show_market("trade",true)],
		[tr("Status").to_upper(),tr("Your ship, cargo and pilot record"),"status",show_station_status],
		[tr("System").to_upper(),tr("Save, controls and settings"),"system",show_system]]
	var grid:=GridContainer.new();grid.name="Services";grid.columns=3;grid.add_theme_constant_override("h_separation",10);grid.add_theme_constant_override("v_separation",10);column.add_child(grid)
	for service in services:
		var node := tile(service[0],service[2],service[3],grid);node.tooltip_text=service[1]
		if service[2] in ["map","trade"]:
			var reason := station_service_reason(service[2]);unavailable(node,reason)
	var launch:=primary(iconic(button(tr("Depart").to_upper(),depart),"depart",30));launch.name="Depart"
	launch.custom_minimum_size.y=64 if touch.enabled() else 58;launch.add_theme_font_override("font",heading_font(6));launch.add_theme_font_size_override("font_size",20)
	if not session.notices.is_empty():
		var notices: Array=session.notices.duplicate();session.notices=[]
		var medals: Array=[]
		for index in notices.size():
			var entry: Dictionary=notices[index]
			session.acknowledge_notice(entry)
			if entry.kind=="medal":medals.append(entry);continue
			# The bounty and the colonists' purchase of the hold each come up as a
			# message over the station, as the original's boxes did (ch); whatever
			# came after is shown when the station is back.
			if entry.kind in ["pirate_bounty","cargo_settlement"]:
				session.notices=medals+notices.slice(index+1)
				show_dialogue([{"speaker":session.text(166) if entry.kind=="pirate_bounty" else tr("Colonists"),"text":entry.text}],show_station);return
			notice(entry.text)
		if not medals.is_empty():show_new_medal(medals,0);return
	check_dock_hints()
func first_art(entries: Array, kind: String) -> Texture2D:
	for entry in entries:
		var art: Texture2D=imported_art.item(entry.id,kind)
		if art!=null: return art
	return null
func show_hangar() -> void:
	open_page(tr("Hangar"),"hangar")
	var station: Dictionary=session.stations[session.station_id]
	var grid := service_grid()
	station_service(tr("Equipment shop"),tr("Buy and fit systems for your ship, or sell what is installed."),"equipment","cart",first_art(station.equipment,"equipment"),grid)
	station_service(tr("Ship dealer"),tr("Buy a new hull. Your current ship is traded in."),"ships","hangar",first_art(station.ships,"ships"),grid)
	service_card(tr("Your ship & cargo"),tr("Hull, cargo manifest and installed systems."),"cargo",imported_art.item(session.ship.id,"ships"),func():show_ship_status(show_hangar),grid)
func show_station_missions() -> void:
	open_page(tr("Missions"),"station_missions")
	var station: Dictionary=session.stations[session.station_id]
	var grid := service_grid()
	service_card(tr("Current objectives & journal"),tr("Story task and accepted contract."),"journal",null,show_journal,grid)
	var offers: int=station.missions.size()
	station_service(tr("Available contracts"),tr("%d on this station's board.")%offers,"missions","contracts",
		imported_art.portrait(station.missions[0].portrait) if offers>0 else null,grid)
func show_station_status() -> void:
	open_page(tr("Status"),"station_status")
	var grid := service_grid()
	service_card(tr("Your ship & cargo"),tr("Hull, cargo manifest and installed systems."),"cargo",imported_art.item(session.ship.id,"ships"),show_ship_status,grid)
	var best := 0
	for tier in session.medals.levels:
		if tier>0 and (best==0 or tier<best): best=tier
	var owned: int=session.medals.levels.filter(func(tier): return tier>0).size()
	service_card(tr("Pilot profile & medals"),tr("Rank %d · %d / 24 medals · statistics")%[session.counters.k,owned],"person",
		imported_art.image("medal_%d"%(best if best>0 else (5 if session.is_colonist_station() else 7))),show_profile,grid)
func show_system() -> void:
	if session.demo_mode:show_pause();return
	open_page(tr("System"),"system")
	var grid := service_grid();grid.add_theme_constant_override("v_separation",10)
	for entry in [[tr("Save game"),"save",show_save_slots],[tr("Load game"),"resume",show_load_slots],[tr("Settings"),"controls",show_settings],
		[tr("Help"),"help",show_help],[tr("Reference"),"book",show_reference],[tr("Transfer save"),"transfer",show_transfer]]:
		iconic(button(entry[0],entry[2],grid),entry[1])
	iconic(button(tr("Reload station checkpoint"),func(): confirm(tr("Reload checkpoint"),
		tr("Return to your last saved station? Everything since that checkpoint is lost."),
		tr("Reload checkpoint"),reload_game,show_system),grid),"reload")
	iconic(button(tr("Main menu"),func(): confirm(tr("Main menu"),
		tr("The game is saved at this station first."),
		tr("Return to main menu"),return_to_menu,show_system),grid),"exit")
func back_row(action: Callable) -> void:
	"""Where a page used to end in its own Back row, the header's BACK, Esc and
	the pad's B now take that way instead; one way back per page."""
	page_back=action
func dock_back() -> void:
	if page_back.is_valid():
		var way := page_back;page_back=Callable();way.call();return
	if not session.docked:close_page();return
	if page=="market":
		if market_category in ["ships","equipment"]:show_hangar();return
		if market_category=="missions":show_station_missions();return
	if page in ["save_slots","load_slots","help"]:show_system();return
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
	open_page(tr("Departing"),"departure");overlay.hide()
	world.region.player.throttle=100
	view.rebuild();view.begin_departure();view._process(0)
	notice(tr("Leaving %s · Enter / click to skip")%session.stations[session.station_id].name)
func finish_departure() -> void:
	if page!="departure":return
	view.place_departure(1.0);view.departure_progress=-1
	world.region.player.throttle=0
	if departure_route=="encounter":world.navigate_encounter()
	elif departure_destination>=0:
		if departure_route=="stream":
			if world.plan_stream(departure_destination):stream_prompted=false
		elif departure_route=="objective":
			if world.route_to_objective(departure_destination):stream_prompted=false
		else:world.route_to(departure_destination)
	departure_destination=-1;message.text="";notification_time=0
	close_page();world.region.events.append({"kind":"departure_briefing"})
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
	open_page(str(lines[line_index].get("speaker",tr("Transmission"))),"dialogue")
	for child in overlay.get_children():overlay.remove_child(child);child.queue_free()
	column=VBoxContainer.new();column.add_theme_constant_override("separation",8);overlay.add_child(column)
	label((tr("Radio  /   %s")%str(lines[line_index].get("speaker",tr("Transmission")))).to_upper(),14).add_theme_color_override("font_color",Color("8bd6ee"))
	var transmission := HBoxContainer.new(); transmission.add_theme_constant_override("separation",10);transmission.size_flags_vertical=Control.SIZE_EXPAND_FILL; column.add_child(transmission)
	var own_line: bool=lines[line_index].get("speaker","")==session.name
	art_image(imported_art.portrait(session.face_layers if own_line else lines[line_index].get("portrait",[]),session.face_photo if own_line else ""),transmission,112)
	var body := RichTextLabel.new();body.custom_minimum_size=Vector2(0,92);body.size_flags_horizontal=Control.SIZE_EXPAND_FILL;body.size_flags_vertical=Control.SIZE_EXPAND_FILL;body.add_theme_font_size_override("normal_font_size",18);body.add_theme_color_override("default_color",Color("c9ded5"));transmission.add_child(body)
	var line_text: String=str(lines[line_index].get("text",""))
	if lines[line_index].has("text_id"):line_text=keyed_text(int(lines[line_index].text_id))
	money_text(body,line_text)
	var footer := HBoxContainer.new();column.add_child(footer);label("%02d / %02d"%[line_index+1,lines.size()],10,footer)
	var previous := button("< "+tr("Back"),func():
		line_index-=1;dialogue_page(),footer)
	previous.name="DialoguePrevious";previous.disabled=line_index==0
	previous.custom_minimum_size.y=64 if touch.enabled() else 44;previous.add_theme_font_size_override("font_size",14)
	var next := button(tr("Continue >"),func():
		line_index+=1
		if line_index>=lines.size(): dialogue_done.call()
		else: dialogue_page(),footer)
	next.name="DialogueNext"
	next.custom_minimum_size.y=64 if touch.enabled() else 44;next.add_theme_font_size_override("font_size",14)
	layout.call_deferred()
	focus_if_visible.call_deferred(next)
func focus_if_visible(control) -> void:
	if is_instance_valid(control) and control.is_inside_tree() and control.is_visible_in_tree(): control.grab_focus()
## How long a death, a failure or a finished encounter waits for the
## explosion that caused it: past the flash, into the falling debris.
const AFTERMATH_MS := 2800
## How long a radio call or briefing waits once a departure or a gate's way
## out has finished, as the phone game lets the arrival settle before talking.
const RADIO_SETTLE_MS := 2500
func aftermath_pending() -> bool:
	var r=world.region
	for event in r.visual_events:
		if event.kind=="explosion" and not event.get("creature",false) and r.elapsed_ms-int(event.time)<AFTERMATH_MS:return true
	return false
func consume_events() -> void:
	# Nobody talks over the shot of the submarine setting out or coming out of
	# a gate. A held briefing keeps its place without holding up what follows.
	var held: Array=[]
	while not world.region.events.is_empty():
		var entry: Dictionary = world.region.events.pop_front()
		if entry.kind in ["death","mission_failed","mission_complete"] and aftermath_pending():
			world.region.events.push_front(entry);break
		if entry.kind in ["briefing","departure_briefing"] and world.region.radio_hold_ms>0:
			held.append(entry);continue
		match entry.kind:
			"briefing": show_dialogue(session.dialogue(entry.mission,0),close_page)
			"departure_briefing": briefing()
			"encounter_dialogue": show_dialogue(session.dialogue(entry.mission,3),finish_transmission)
			"credits": show_dialogue([{"speaker":tr("Credits"),"text":session.text(26)+"\n\n"+session.text(28)+"\n\n"+session.text(27)+("\n\n"+GraphicsCredits.text() if GraphicsCredits.amd() or GraphicsCredits.nvidia() else "")}],func(): world.region.acknowledge_credits(); close_page())
			"mission_complete": show_dialogue(session.dialogue(entry.mission,1),func(): world.region.acknowledge_completion(); close_page())
			"transmission":
				var speaker: String = str(content.data.constants.ah["a:[Ljava.lang.String;"][entry.entry.speaker])
				# cq announces a radio call in the water with the signal cue; the
				# message cue is M.A.I.'s, for the mission screens.
				show_dialogue([{"speaker":session.name if entry.entry.speaker==0 else speaker,"text":keyed_text(entry.entry.text_id),"portrait":content.data.constants.ah["a:[[B"][entry.entry.speaker] if entry.entry.speaker>0 else []}],finish_transmission,"signal")
			"death","mission_failed":
				dive_audio.cue("pressure")
				# The heading names what happened; what to do next is the
				# body's, where a long line wraps instead of being cut off.
				open_page(tr("Game over") if entry.kind=="death" else tr("Mission failed"),"failure")
				if entry.kind=="death":label(entry.text,17).add_theme_color_override("font_color",colours().text)
				if entry.kind=="mission_failed" and not world.region.mission.story:
					button(tr("Continue"),func():
						session.abandon_contract(); world.region.mission=session.campaign.active; world.region.success=null; world.region.failure=null; world.region.time_limit=0; world.region.failed=false; close_page())
				button(tr("Reset test area") if session.demo_mode else tr("Reload station checkpoint"),reload_game); button(tr("Main menu"),return_to_menu)
			_:
				if entry.kind=="notice" and (entry.text.begins_with("Cannot collect catch") or entry.text==tr("Cannot collect catch · cargo hold is full. Make room at a station.")):hold_full_seen=true
				notice(tr("%s · %s %dt")%[entry.text,item_name(entry.goods),entry.amount] if entry.has("goods") else entry.text)
		# Preserve later events until the current dialogue/failure is resolved.
		if not page.is_empty(): break
	held.reverse()
	for entry in held:world.region.events.push_front(entry)
func finish_transmission() -> void:
	"""The original keeps the water still through a whole radio exchange: a
	line waiting on this one (timeline kind 6) opens in the same frame, so no
	tick of the dive runs between the two windows."""
	world.region.acknowledge_transmission(); close_page()
	if world.region.update_radio() and world.region.active_transmission!=null:consume_events()
func save_game(feedback: bool=true) -> void:
	if session.demo_mode:
		if feedback:notice(tr("Demo sessions are not saved."))
		return
	if not session.docked:
		if feedback: notice(tr("Dock at a station to save."))
		return
	if store.write(save_path,session):
		if feedback: notice(session.text(32))
	else: notice(store.failure)
func show_save_slots() -> void:
	if session.demo_mode:notice(tr("Demo sessions are not saved."));return
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
func show_load_slots() -> void:
	if session.demo_mode:notice(tr("Demo sessions are not saved."));return
	"""Another save, loaded at the station, as the main menu loads one. The
	autosave is left as it is: loading is not a reason to write over it."""
	open_page(tr("Load game"),"load_slots")
	for index in store.SLOT_PATHS.size()+1:
		var path: String=save_path if index==store.SLOT_PATHS.size() else store.slot_path(index)
		var entry: Dictionary=store.summary(path,content.data) if FileAccess.file_exists(path) else {}
		var choice := button("%d.  %s  ·  %s"%[index+1,store.slot_title(index),store.describe(entry)],func():
			confirm(tr("Load game"),tr("Load this save? Everything since you last saved is lost."),tr("Load game"),func():reload_game(path),show_load_slots))
		choice.alignment=HORIZONTAL_ALIGNMENT_LEFT;choice.disabled=entry.is_empty()
	back_row(show_system)
func write_slot(path: String) -> void:
	if store.write(path,session):notice(session.text(32))
	else:notice(store.failure)
	if session.docked:show_system()
	else:close_page()
func reload_game(path: String="") -> void:
	if session.demo_mode:reset_demo();return
	var restored=store.read(save_path if path.is_empty() else path,content.data)
	if restored==null: notice(store.failure); return
	var fell_back: bool=store.recovered
	world.dispose(); session=restored; world.configure(session); economy.configure(session)
	world.build_docked_view()
	show_station()
	TravelFade.uncover(ui)
	if fell_back: notice(tr("Your save could not be read. Restored the previous checkpoint."))
func return_to_menu() -> void:
	if returning_to_menu:return
	returning_to_menu=true
	if session.docked: save_game(false)
	set_process(false)
	finish_return_to_menu.call_deferred()
func finish_return_to_menu() -> void:
	var menu=load("res://scenes/native_main.tscn").instantiate()
	menu.content=content;menu.returning_from_game=true
	menu.settings_path=settings_path;menu.save_path=save_path
	# Let the dive release its world and restore the canvas before the title
	# takes over the same viewport. Only the loaded content crosses over.
	var tree := get_tree()
	get_parent().remove_child(self)
	tree.root.add_child(menu);tree.current_scene=menu
	queue_free()
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
	if moved<1: notice(tr("Insufficient credits, cargo space or stock.")); return
	notice(Coin.coins((tr("Bought %d t of %s for %d cr") if buying else tr("Sold %d t of %s for %d cr"))%[moved,item_name(item.id),absi(session.credits-before)]))
func show_market(kind: String, reset: bool=false) -> void:
	if reset: equipment_tab=0;market_floor_kind=""
	# The Workshop opens on what the hold can make; Cargo keeps the good
	# picked, which after a Make is the product, ready to sell.
	if reset or (kind=="manufacture" and market_category!=kind): market_selected_id=-1
	if reset or market_category!=kind: market_selection=0;list_offsets.clear();market_category=kind
	var denial: int = session.service_denial(kind)
	if denial>=0: notice(session.text(denial)); return
	open_page({"equipment":tr("Equipment shop"),"ships":tr("Ship dealer"),"trade":tr("Trade"),"manufacture":tr("Workshop"),"missions":tr("Available contracts")}.get(kind,kind),"market",
		{"equipment":tr("Outfit your ship"),"ships":tr("Buy a hull · trade in your current one"),"trade":tr("Buy and sell cargo"),"manufacture":tr("Craft products from your cargo"),"missions":tr("Contracts offered at this station")}.get(kind,""))
	header_chip("credits",Coin.coins(tr("%d CR")%session.credits),tr("Your credits"))
	if kind=="ships" and ui.size.x>=1100: header_chip("hangar",content.ship_name(session.ship.id),tr("Current ship"))
	var station: Dictionary = session.stations[session.station_id]
	match kind:
		"equipment":
			var bar := HBoxContainer.new();bar.add_theme_constant_override("separation",10);column.add_child(bar)
			var tabs := HBoxContainer.new();tabs.name="EquipmentTabs";tabs.add_theme_constant_override("separation",10);tabs.size_flags_horizontal=Control.SIZE_EXPAND_FILL;bar.add_child(tabs)
			ship_strip=bar if ui.size.x>=1100 else column
			for index in 2:
				var tab := iconic(button(tr("Shop").to_upper() if index==0 else tr("Ship equipment").to_upper(),func():
					equipment_tab=index;market_selection=0;list_offsets.clear();show_market("equipment"),tabs),"cart" if index==0 else "wrench",24)
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
		"trade","manufacture":
			goods_tabs(kind)
			goods_browser(station,kind=="manufacture")
		"missions":
			if session.campaign.secondary.kind>=0: label(tr("Finish or abandon the accepted contract before accepting another.")).add_theme_color_override("font_color",colours().dim)
			if station.missions.is_empty(): label(tr("No contracts on this station's board.")).add_theme_color_override("font_color",colours().dim)
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
	# Beyond the engine's S.T.R.E.A.M. reach, as the chart's station card shows it.
	var far: bool=mission.destination!=station.id and world.stream_distance(mission.destination)>=world.stream_range()
	var rows: Array=[["map",session.text(334),mission.destination_name],
		["shield",session.text(245),tr("%d m")%session.stations[mission.destination].depth,palette.bad if outside else palette.text],
		["depart",session.text(333),session.text(310) if journey==0 else tr("%d km")%journey,palette.bad if far else palette.text]]
	if mission.kind==8: rows.append(["grid",session.text(331),str(mission.jump_limit+1) if mission.jump_limit>=0 else session.text(335)])
	else: rows.append(["status",session.text(39),grade])
	figure_rows(rows,body)
	if outside: label(session.text(255),14,body).add_theme_color_override("font_color",palette.bad)
	target_line(mission,body)
	for detail in [info.progress(session,mission),info.requirements(mission),info.deadline(mission)]:
		if not detail.is_empty(): label(detail,15,body).add_theme_color_override("font_color",palette.text)
	var terms := HBoxContainer.new();terms.add_theme_constant_override("separation",10);body.add_child(terms)
	figure_tile("credits",tr("Reward"),Coin.coins(tr("%d cr")%mission.reward),terms)
	figure_tile("shield",tr("Deposit"),Coin.coins(tr("%d cr")%mission.deposit),terms)
	# Cards side by side share a row's height; the button keeps to the foot.
	var foot := Control.new();foot.size_flags_vertical=Control.SIZE_EXPAND_FILL;foot.mouse_filter=Control.MOUSE_FILTER_IGNORE;body.add_child(foot)
	# The original's offer dialogue (bz) has Check location (251): the chart
	# on the destination, with only this offer marked, and Back to the board.
	iconic(button(session.text(251),func():
		map_destination=mission.destination;Map.preview_mission=mission
		map_return=func():Map.preview_mission=null;show_market("missions")
		show_map(),body),"map",22)
	var accept := primary(iconic(button(tr("Accept contract"),func():
		if session.campaign.secondary.kind>=0: notice(tr("Finish or abandon the accepted contract first."))
		elif session.accept_contract(mission): show_station()
		else: notice(tr("Insufficient credits for the deposit.")),body),"contracts",22))
	if session.campaign.secondary.kind>=0:
		accept.disabled=true;accept.tooltip_text=tr("Finish or abandon the accepted contract first.")
func transaction_result(result: int, done: String="") -> void:
	"""A refusal's reason, or what the original says once it went through
	(ai: "<ship> bought.", "<item> mounted.", "<item> sold.")."""
	if result>=0: notice(session.text(result))
	elif not done.is_empty(): notice(done)
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
	# A phone held landscape has too little width for the full labels in one
	# row; a wrapped second row fell below the page's foot.
	var tight: bool=ui.size.x<(1240 if touch.enabled() else 1000)
	var search := LineEdit.new(); search.placeholder_text=tr("Search") if tight else tr("Find a station…"); search.custom_minimum_size.x=130 if tight else 170; actions.add_child(search)
	StationTheme.style_field(search,golden(),touch.enabled())
	search.text_changed.connect(func(value): map_widget.filtered=value.to_lower(); map_widget.queue_redraw())
	var picker := OptionButton.new(); map_picker=picker; picker.custom_minimum_size.x=160 if tight else 190
	StationTheme.style_option(picker,golden(),touch.enabled())
	for station in session.stations: picker.add_item(station.name,station.id)
	picker.selected=map_destination; picker.item_selected.connect(func(index): select_station(picker.get_item_id(index))); actions.add_child(picker)
	species_toggle(actions,func():
		if not map_unchosen:select_station(map_destination))
	var gap := Control.new(); gap.size_flags_horizontal=Control.SIZE_EXPAND_FILL; actions.add_child(gap)
	if world.encounter_navigation_point()!=null:
		bar_button(tr("Encounter waypoint"),func():
			if session.docked:
				depart()
				if session.docked:return
				if page=="departure":departure_route="encounter";return
			world.navigate_encounter();close_page(),actions).tooltip_text=tr("Local encounter active · follow its waypoint before travelling to the next story station.")
	map_route_button=bar_button(tr("Autopilot") if tight else tr("Set station autopilot"),map_autopilot,actions)
	if tight: map_route_button.tooltip_text=tr("Set station autopilot")
	map_route_button.set_meta("option","map_route")
	stream_button=bar_button(tr("S.T.R.E.A.M. transfer") if tight else tr("Plan S.T.R.E.A.M. transfer"),map_stream,actions)
	stream_button.visible=not atlas_autopilot_only
	if map_return.is_valid():back_row(map_return);map_return=Callable()
	else:
		Map.preview_mission=null;back_row(show_station if session.docked else close_page)
	map_unchosen=false
	var start: Dictionary=session.stations[map_destination]
	map_widget.place_lens(Vector2(start.x,start.y))
	select_station(map_destination)
var map_stick_moving := false
func chart_input(event: InputEvent) -> bool:
	"""The chart has two keyboard stages: move the zone, then pick an exit.
	Tab still reaches search, the station list and the explicit route actions."""
	if page not in ["map","stream"] or not is_instance_valid(map_widget) or not is_instance_valid(map_slice):return false
	var focused := get_viewport().gui_get_focus_owner()
	if focused!=map_widget and focused!=map_slice:return false
	# Digital directions are sampled together each frame. Consume both press
	# and release here so focus navigation and OS repeats cannot move the ring.
	if focused==map_widget and map_widget.cursor_input(event):return true
	# The left stick always moves the area continuously through map_pad().
	if event is InputEventJoypadMotion and event.axis in [JOY_AXIS_LEFT_X,JOY_AXIS_LEFT_Y]:return true
	if not event.is_pressed():return false
	var station_mode: bool=focused==map_slice
	if event.is_action_pressed("ui_cancel"):
		if station_mode:map_widget.grab_focus();return true
		return false
	var direction := Vector2.ZERO
	if event.is_action_pressed("ui_left",true):direction=Vector2.LEFT
	elif event.is_action_pressed("ui_right",true):direction=Vector2.RIGHT
	elif event.is_action_pressed("ui_up",true):direction=Vector2.UP
	elif event.is_action_pressed("ui_down",true):direction=Vector2.DOWN
	if direction!=Vector2.ZERO:
		if station_mode:map_slice.step(-1 if direction.x<0 or direction.y<0 else 1)
		return true
	var fire: bool=event is InputEventKey and event.physical_keycode==key_bindings.fire
	if event.is_action_pressed("ui_accept") or fire:
		if event is InputEventKey and event.echo:return true
		if not station_mode:
			var ids:=zone_stations(map_widget.lens_center)
			if ids.is_empty():notice(zone_prompt(map_widget.lens_center)[1]);return true
			map_stick_moving=false
			map_slice.choose(map_slice.selected_id if map_slice.selected_id in ids else ids[0])
			map_slice.grab_focus()
		elif page=="stream":begin_stream_transit()
		elif atlas_autopilot_only:map_autopilot()
		else:autonavigate_from_journal(map_destination,func():show_map(atlas_autopilot_only))
		return true
	return false
func pad_axis(axis: int) -> float:
	return float(controller.axes.get(axis,0.0))
func map_pad(delta: float) -> void:
	"""A pad walks the chart's zone with the left stick, as the original's
	direction keys do, pans the chart with the right and zooms on the
	triggers about the zone, whatever holds focus. The D-pad follows the
	focused chart stage, or moves between other controls. A zone walked
	towards the edge takes the chart with it."""
	if not is_instance_valid(map_widget) or map_widget.lens_radius<=0: return
	var stick: Vector2=controller.stick()
	if map_widget.has_focus():stick=(stick+map_widget.cursor_direction()).limit_length(1.0)
	var zone: Vector2=map_widget.lens_center
	if stick!=Vector2.ZERO:
		if not map_widget.has_focus():map_widget.grab_focus()
		map_stick_moving=true
		# The same pace on screen at any zoom.
		zone=map_widget.place_lens(zone+stick*map_widget.lens_radius*3.0*delta/sqrt(map_widget.zoom))
		map_widget.keep_in_view(zone,map_widget.lens_radius*minf(map_widget.size.x,map_widget.size.y)*.0085*map_widget.zoom+16)
		map_widget.zone_dragged.emit(zone)
	elif map_stick_moving:
		# Letting go settles the zone, as lifting a finger does.
		map_stick_moving=false;map_widget.zone_moved.emit(zone,-1)
	var panning := controller.stick(JOY_AXIS_RIGHT_X,JOY_AXIS_RIGHT_Y)
	if panning!=Vector2.ZERO:
		map_widget.pan-=panning*minf(map_widget.size.x,map_widget.size.y)*1.2*delta;map_widget.queue_redraw()
	# Some pads report a trigger at rest as -1.
	var zooming := maxf(0,pad_axis(JOY_AXIS_TRIGGER_RIGHT))-maxf(0,pad_axis(JOY_AXIS_TRIGGER_LEFT))
	if absf(zooming)>.2:
		map_widget.zoom_about(exp(zooming*delta*1.5),map_widget.point(zone.x,zone.y))
func map_autopilot() -> void:
	if ask_travel(map_destination,map_autopilot,func():show_map(atlas_autopilot_only)):return
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
	if ask_travel(map_destination,map_stream,func():show_map(atlas_autopilot_only)):return
	if session.docked:
		depart()
		if session.docked: return
		if page=="departure":departure_destination=map_destination;departure_route="stream";return
	if world.plan_stream(map_destination):
		# A new plan can start even without leaving a previously visited gate.
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
	return tr("Map  ·  Discovered %d / %d")%[session.discovered.count(true),session.discovered.size()]
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
	map_widget=Map.new(); map_widget.world=world; map_widget.selected_id=selection; map_widget.habitat_species=habitat_range; map_widget.habitat_caption=species_caption(habitat_range); top.add_child(map_widget)
	map_widget.size_flags_horizontal=Control.SIZE_EXPAND_FILL; map_widget.size_flags_vertical=Control.SIZE_EXPAND_FILL; map_widget.size_flags_stretch_ratio=1.1
	map_widget.custom_minimum_size=Vector2(300,200) # after its _ready, which sets its own
	map_widget.lens_radius=ZONE_RADIUS;map_widget.focus_mode=Control.FOCUS_ALL
	map_stick_moving=false
	touch_scroll.gesture_control=map_widget
	var side := VBoxContainer.new(); side.size_flags_horizontal=Control.SIZE_EXPAND_FILL; side.add_theme_constant_override("separation",10); top.add_child(side)
	map_slice=DepthSlice.new(); map_slice.world=world; map_slice.art=imported_art; map_slice.size_flags_vertical=Control.SIZE_EXPAND_FILL; side.add_child(map_slice)
	map_widget.focus_entered.connect(chart_legend)
	map_slice.focus_entered.connect(chart_legend)
	if compact: map_slice.custom_minimum_size.y=96
	# The side view and the station share the column evenly, so the station
	# is shown at a size that reads rather than as a thumbnail.
	var card := PanelContainer.new(); card.add_theme_stylebox_override("panel",chart_panel()); card.size_flags_vertical=Control.SIZE_EXPAND_FILL; side.add_child(card)
	# Short of rows, the side view gives up more of the column than the card.
	if compact: card.size_flags_stretch_ratio=1.8
	# The card scrolls on its own, so a long warning or the species list
	# shortens nothing but itself instead of pushing the key and the actions
	# below the page's foot.
	var card_scroll := ScrollContainer.new(); card_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; card.add_child(card_scroll)
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation",12); row.size_flags_horizontal=Control.SIZE_EXPAND_FILL; row.size_flags_vertical=Control.SIZE_EXPAND_FILL; card_scroll.add_child(row)
	var facts := VBoxContainer.new(); facts.custom_minimum_size.x=190 if compact else 230; facts.size_flags_horizontal=Control.SIZE_FILL; facts.size_flags_vertical=Control.SIZE_SHRINK_BEGIN; facts.add_theme_constant_override("separation",2); row.add_child(facts)
	map_title=label("",20 if compact else 24,facts); map_title.modulate=Color("eef6ff")
	# Rich text, so a figure the ship cannot manage can be picked out in red.
	map_info=RichTextLabel.new(); map_info.bbcode_enabled=true; map_info.fit_content=true; map_info.scroll_active=false; map_info.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	map_info.add_theme_font_size_override("normal_font_size",14 if compact else 15); map_info.add_theme_color_override("default_color",Color("b9d4f2")); map_info.mouse_filter=Control.MOUSE_FILTER_PASS; facts.add_child(map_info)
	map_showcase=VBoxContainer.new(); map_showcase.size_flags_horizontal=Control.SIZE_EXPAND_FILL; map_showcase.custom_minimum_size.y=90 if compact else 120; row.add_child(map_showcase)
	# Clear of the card's scroll bar, which is drawn over its content.
	var bar_room := Control.new(); bar_room.custom_minimum_size.x=10; bar_room.mouse_filter=Control.MOUSE_FILTER_IGNORE; row.add_child(bar_room)
	var key := PanelContainer.new(); key.add_theme_stylebox_override("panel",chart_panel()); body.add_child(key)
	var legend := VBoxContainer.new(); legend.add_theme_constant_override("separation",2); key.add_child(legend)
	map_key(legend)
	map_widget.tooltip_text=tr("Tap or drag the zone, then pick a station in the side view · hold to grab the zone · pinch / wheel to zoom · drag / right mouse to pan")
	if not compact:
		# Its own line, wrapping, so a narrow window does not widen the chart.
		var gestures := label(map_widget.tooltip_text,13,legend); gestures.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; gestures.modulate=Color("7f96ad")
		if controller.device>=0 or not Input.get_connected_joypads().is_empty():
			gestures.text=tr("Pad: left stick moves the zone · right stick pans · LB / RB station · LT / RT zoom on the zone")
	# A flow, so a narrow window wraps the actions onto a second row instead
	# of pushing the whole chart off the side.
	var actions := HFlowContainer.new(); actions.add_theme_constant_override("h_separation",10); actions.add_theme_constant_override("v_separation",8)
	# The page's scroller clips at its own edge, and a focused control draws its
	# outline outside its box: flush against the bottom, the picker's outline
	# lost its lower edge.
	var inset := MarginContainer.new(); body.add_child(inset); inset.add_child(actions)
	for edge in ["margin_top","margin_bottom","margin_left","margin_right"]: inset.add_theme_constant_override(edge,4)
	return actions
func chart_legend() -> void:
	if page not in ["map","stream"]:return
	var station_mode: bool=is_instance_valid(map_slice) and map_slice.has_focus()
	if is_instance_valid(map_widget) and (station_mode or map_widget.has_focus()):map_widget.select_area(station_mode)
	var legend:=overlay.find_child("KeyLegend",true,false)
	if legend==null:return
	var entries: Array=legend.get_children()
	entries[1].text=tr("Move zone") if station_mode else tr("Back")
	entries[3].text=tr("Choose station") if station_mode else tr("Move zone")
	entries[4].text=OS.get_keycode_string(key_bindings.fire)+" / Enter / A"
	entries[5].text=tr("Set destination") if station_mode else tr("Select area")
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
	toggle.text=tr("Station") if stream_species else tr("Species")
	toggle.pressed.connect(func(): stream_species=not stream_species; toggle.text=tr("Station") if stream_species else tr("Species"); refresh.call())
	return toggle
func show_station_card(id: int, facts: String, empty_title: String=tr("No exits")) -> void:
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
			{"body":"05bbff","core":"0d2170","text":tr("Colonist")},
			{"body":"0d2170","core":"05bbff","text":tr("Colonist, unvisited")},
			{"body":"65e53e","core":"14501a","text":tr("Resistance")},
			{"body":"14501a","core":"65e53e","text":tr("Resistance, unvisited")},
			{"body":"ff8000","core":"ffff00","text":tr("Your station")},
			{"body":"ff0000","core":"c00000","text":tr("Mission destination")},
			{"kind":"arrow","text":tr("You")},
			{"kind":"disc","text":tr("S.T.R.E.A.M. reach")},
			{"kind":"zone","text":tr("Zone in the side view")}]
	if session.trail.size()>1: entries.append({"kind":"trail","text":tr("Recent trips")})
	if world.autopilot and world.destination>=0: entries.append({"kind":"dash","tint":"97e4d3","text":tr("Autopilot route")})
	if world.stream_destination>=0: entries.append({"kind":"dash","tint":"bdabf2","text":tr("S.T.R.E.A.M. transfer")})
	if world.encounter_navigation_point()!=null: entries.append({"kind":"ring","tint":"91e4d4","text":tr("Encounter waypoint")})
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
	if zone_stations(center).is_empty():return [tr("No stations here"),tr("Move the zone over a station, or pick one from the list.")]
	return [tr("Choose a station"),tr("Pick one of the stations in the side view.")]
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
	var status := tr("Ready · transfer at the gate")
	if id==session.station_id: status=tr("Current area")
	elif figures.far: status=""
	elif not denial.is_empty(): status=tr("Locked by the current mission")
	elif figures.unsafe: status=session.text(255)
	show_station_card(id,tr("%s · %s\n%s: %s · %s: %s\u00a0m\nS.T.R.E.A.M. %s / %.1f\u00a0km%s")%[
		tr("Rebels") if session.campaign.rebel_stations[id] else tr("Colonists"),tr("Discovered") if session.discovered[id] else tr("Unexplored"),session.text(44),tech_text(id),session.text(245),figures.depth,
		figures.distance,world.map_kilometers(world.stream_range()),"" if status.is_empty() else "\n"+status])
	map_info.tooltip_text=denial
	if is_instance_valid(stream_button): stream_button.tooltip_text=denial if not denial.is_empty() else tr("Autopilot to the gate, then travel to the selected station.")
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
		if mission.has_destination() and not mission.completed and not mission.failed and not mission.destination_name.is_empty() and mission.destination<session.stations.size():quest_ids[mission.destination]=true
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
		var distance_position := position
		var nodes: Array=view.station_nodes if id==session.station_id else (view.neighbors[id].root.get_children() if view.neighbors.has(id) else [])
		var bounds := AABB();var first := true
		for node in nodes:
			if not node.has_method("solid_bounds"):continue
			var box: AABB=node.global_transform*node.solid_bounds()
			bounds=box if first else bounds.merge(box);first=false
		if not first:position=Vector3(bounds.get_center().x,bounds.end.y+8,bounds.get_center().z)
		result.append({"key":"station" if id==session.station_id else "station:"+str(id),"p":[0,0,0],"position":position,"distance_position":distance_position,"name":session.stations[id].name,"color":Color("e5ce86") if quest_ids.has(id) else Color("7bd2d6"),"edge":id==session.station_id or quest_ids.has(id),"hull":-1.0,"station_contact":true,"quest":quest_ids.has(id)})
	return result

## How near the screen's edge a ship is still bracketed in place.
const ENEMY_MARGIN := 12.0
func encounter_marker_label() -> String:
	var actor=world.encounter_navigation_subject()
	if actor==null:return tr("Mission waypoint")
	if actor.is_creature:return item_name(actor.species)
	if actor is SpecialActor:
		match actor.kind:
			"debris":return tr("Debris")
			"mine":return tr("Mine")
			"freighter":return tr("Convoy target")
			"capsule":return tr("Supply capsule")
	if actor.protected_target:return tr("Rescue target") if world.region.mission.kind==2 else tr("Recovery target")
	return tr("Mission target")

func update_markers() -> void:
	update_catch_counter()
	if not page.is_empty() or world.region.cinematic() or view.transit_progress>=0:
		for marker in markers: marker.hide()
		return
	var region=world.region
	focused_contact=focus_creature()
	var radar: int = session.ship.passive_radar
	var targets: Array = station_contacts()
	# With separate gates each tag says which way its gate goes.
	var gate_title: String=tr("S.T.R.E.A.M. OUT") if region.gate_index(1)==1 else tr("S.T.R.E.A.M.")
	var gate_name: String = gate_title+" > "+session.stations[world.stream_destination].name if world.stream_destination>=0 else gate_title+" · "+session.stations[session.station_id].name
	if world.at_gate(world.departure_gate):
		gate_name=gate_title+" · "+((tr("Transit control") if world.stream_destination>=0 else tr("Choose destination")) if world.gate_time[world.departure_gate]>=world.GATE_OPEN_MS else tr("Opening") if world.region.success==null and world.region.failure==null and not world.tutorial_travel_locked() else tr("Locked"))
	targets.append({"key":"stream","p":region.gates[world.departure_gate],"name":gate_name,"color":Color("bdabf2"),"edge":world.stream_destination>=0,"hull":-1.0})
	if region.gate_index(1)==1:
		# The arrival gate is named too, so it is not taken for the way out.
		targets.append({"key":"stream_in","p":region.gates[1],"name":tr("S.T.R.E.A.M. IN · %s")%session.stations[session.station_id].name,"color":Color("8f86b0"),"edge":false,"hull":-1.0})
	for id in view.neighbors:
		for visual in view.neighbors[id].root.get_children():
			if not visual is Model or not visual.has_meta("neighbor_gate"):continue
			if visual.global_position.distance_to(preload("res://scripts/model_library.gd").point(region.player.pose.origin))>2500.0:continue
			targets.append({"key":"stream:"+str(id),"p":[0,0,0],"position":visual.global_position,"name":tr(str(visual.get_meta("gate_title","S.T.R.E.A.M.")))+" · "+session.stations[id].name,"color":Color("ac9ac9"),"edge":true,"hull":-1.0})
	if world.autopilot and world.local_target!=null and world.stream_destination<0:
		targets.append({"key":"waypoint","p":world.local_target,"name":encounter_marker_label() if world.encounter_autopilot else session.stations[world.destination].name if world.destination>=0 else tr("Autopilot"),"color":Color("e5ce86"),"edge":true,"hull":-1.0})
	elif world.encounter_navigation_point()!=null: targets.append({"key":"waypoint","p":world.encounter_navigation_point(),"name":encounter_marker_label(),"color":Color("e5ce86"),"edge":radar>0 or waypoint_edge,"hull":-1.0})
	for role in ["friend","enemy","creature"]:
		var actors: Array = region.friends if role=="friend" else (region.enemies if role=="enemy" else region.creatures)
		for actor in actors:
			var entry: Dictionary = Scanner.describe(actor,role,radar,region.mission.kind,region.player.pose.origin)
			if not entry.visible or (role=="friend" and not friend_labels): continue
			entry.p=actor.pose.origin; entry.actor=actor; entry.key=actor.get_instance_id()
			# cb brackets ships without a caption; the hull bar is their reading.
			entry.name=tr("Protected school") if role=="creature" and region.mission.kind==6 else ""
			entry.color=Color("ef9b83") if role=="enemy" else Color("85bda4")
			if entry.recoverable: entry.name=tr("Rescue") if actor.protected_target else tr("Salvage"); entry.color=Color("e5ce86")
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
	occupied.append_array(retro_hud.bands())
	# Edge marks run down the screen's sides, where the touch buttons are.
	if touch.enabled() and touch.visible:
		for id in ["menu","map","time","autopilot","dock","boost","hook","guns","stick","throttle"]:
			var button: Rect2=touch.control_rect(id)
			if button.has_area() and touch.shown(id):occupied.append(Rect2(touch.get_global_transform()*button.position,button.size*touch.get_global_transform().get_scale()))
	# The objective runs taller than the labels' top margin on touch.
	if objective_label.visible:occupied.append(Rect2(objective_label.global_position,Vector2(objective_label.size.x,minf(objective_label.size.y,objective_label.get_content_height()))*objective_label.scale))
	for feedback in [hazard_warning,struggle,catch_counter,trip_tallies,travel_status,message]:
		if feedback.visible and (not feedback is Label or not feedback.text.is_empty()):occupied.append(feedback.get_global_rect())
	# An enemy's hull bar gives way to these panels only, not to other labels.
	var panels:=occupied.size()
	for target in targets:
		if shown.size()>=MAX_CONTACT_LABELS and target.get("role","")!="enemy":continue
		var position: Vector3 = world.render_pose(target.actor).origin if target.has("actor") else target.get("position",preload("res://scripts/model_library.gd").point(target.p))
		# Labels sit above station roofs; range is to the station origin, never
		# to that decorative label anchor. Other contacts use their actual pose.
		var distance: float = target.get("distance_position",position).distance_to(preload("res://scripts/model_library.gd").point(region.player.pose.origin))
		var camera_space: Vector3 = camera.global_transform.affine_inverse()*position
		# Perspective projection is undefined exactly on the camera plane.
		var screen: Vector2 = ui.size/2+Vector2(camera_space.x,-camera_space.y).normalized()*ui.size.length()*2 if absf(camera_space.z)<0.001 else camera.unproject_position(position)-ui.position
		var behind: bool = camera.is_position_behind(position)
		var reverse_edge: bool=behind and absf(camera_space.z)>=.001
		var enemy: bool=target.get("role","")=="enemy" and not target.get("recoverable",false)
		# A ship keeps its bracket and hull bar wherever it is drawn; the
		# status bands reserved for labels would turn it into an edge mark
		# sliding along their border while the ship is still in view.
		var on_screen: bool = not behind and (Rect2(Vector2(ENEMY_MARGIN,ENEMY_MARGIN),ui.size-Vector2.ONE*ENEMY_MARGIN*2) if enemy else Rect2(Vector2(20,160),ui.size-Vector2(200,315))).has_point(screen)
		if not on_screen and not target.edge: continue
		if on_screen and target.get("role","")=="creature":
			var ray:=PhysicsRayQueryParameters3D.create(camera.global_position,position,2)
			ray.hit_back_faces=true
			if not view.get_world_3d().direct_space_state.intersect_ray(ray).is_empty():continue
		var detail := "\n"+tr("Quest destination") if target.get("quest",false) else ""
		# cb: only what is in the middle of the view is scanned. The fishing
		# radars (3, 4) name a creature's catch and its weight, the combat
		# ones (2, 4) the cargo a ship carries; no radar names a ship's type.
		# They show the original's picture of it (cb): a fish's or the meat's
		# with its weight, a ship's cargo, and on a ship that carries none but
		# is to be taken, the person of a hostage job or the crate of the
		# others. The names stand in when the picture was not imported.
		var picture: Texture2D = null
		if on_screen and target.get("identify",false) and Scanner.in_scan_window(screen,ui.size):
			var actor=target.actor
			if actor.is_creature:
				picture=imported_art.item(18 if actor.meat else actor.species)
				target.name="" if picture!=null else tr("Meat") if actor.meat else item_name(actor.species)
				detail="\n"+tr("%d t")%actor.mass
			elif actor.loot!=null:
				picture=imported_art.item(actor.loot.id)
				detail="" if picture!=null else "\n"+tr("%s · %d t")%[item_name(actor.loot.id),actor.loot.owned]
			elif actor.get("protected_target") and target.hull>=0:
				picture=imported_art.image("cargo_salvage" if region.mission.kind==2 else "cargo_recovery")
		elif target.get("role","")=="creature" and region.mission.kind!=6: continue
		var anchor:=screen
		var direction: Vector2 = Vector2.ZERO if on_screen else Scanner.edge_direction(screen,ui.size,reverse_edge).normalized()
		if not on_screen: screen=Scanner.edge_position(screen,ui.size,reverse_edge,enemy)
		if not marker_by_contact.has(target.key):
			if available.is_empty(): continue
			marker_by_contact[target.key]=available.pop_back()
		var i: int = marker_by_contact[target.key]
		markers[i].set_symbol(direction);markers[i].quest=target.get("quest",false)
		# The original gives the range of stations and marks, not of ships or animals.
		var ranged: bool=not target.has("actor")
		var caption: String=target.name
		if not ranged and caption.is_empty(): caption=detail.trim_prefix("\n");detail=""
		markers[i].display(caption+(" · " if ranged else ""),RangeText.format_distance(distance) if ranged else "",detail,target.color,float(target.hull) if on_screen else -1.0,picture)
		if enemy and not on_screen:markers[i].track_enemy(screen,18,true)
		screen+=Vector2(24,12) if on_screen and enemy else Vector2(14,10) if on_screen else Vector2.ZERO
		screen.x=clampf(screen.x,12,maxf(12,ui.size.x-markers[i].size.x-12))
		var top: float=ENEMY_MARGIN if on_screen and enemy else 160.0
		screen.y=clampf(screen.y,top,maxf(top,ui.size.y-markers[i].size.y-(ENEMY_MARGIN if on_screen and enemy else 155.0)))
		# Keep labels attached to their contacts; suppress overlaps instead of
		# shuffling them through a stack of unrelated positions on every tick.
		var area:=Rect2(screen,markers[i].size)
		var overlap: bool=dashboard.visible and area.intersects(Rect2(ui.size.x-310,ui.size.y-305,310,305))
		for previous in (occupied.slice(0,panels) if enemy else occupied):
			if previous.grow(6).intersects(area):overlap=true;break
		var navigation: bool=target.get("station_contact",false) or str(target.key)=="waypoint" or str(target.key).begins_with("stream")
		if overlap and navigation:
			# Navigation labels are essential. Try nearby clear slots instead of
			# silently dropping the station, the waypoint or the gate when a
			# notice, such as the depth warning, crosses its anchor: first just
			# clear of each panel in the way, beside it or below it.
			var offsets: Array=[]
			for previous in occupied:
				var block: Rect2=previous.grow(8)
				if not block.intersects(area):continue
				offsets+=[Vector2(block.position.x-area.end.x,0),Vector2(block.end.x-area.position.x,0),Vector2(0,block.end.y-area.position.y)]
			for offset in offsets+[Vector2(0,-48),Vector2(0,48),Vector2(-180,-48),Vector2(180,-48),Vector2(0,-96)]:
				var candidate: Vector2 = (screen+offset).clamp(Vector2(12,160),Vector2(maxf(12,ui.size.x-markers[i].size.x-12),maxf(160,ui.size.y-markers[i].size.y-155)))
				var candidate_area := Rect2(candidate,markers[i].size)
				if not occupied.any(func(previous):return previous.grow(6).intersects(candidate_area)):
					screen=candidate;area=candidate_area;overlap=false;break
			if str(target.key) in ["station","waypoint"] or target.get("quest",false):overlap=false
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
	return mission.kind>=0 and not mission.completed and not mission.failed and (world.encounter_navigation_point()!=null or mission.has_destination())
func objective_summary(mission) -> String:
	if mission.kind<0:return tr("Explore the ocean")
	var info=preload("res://native/presentation/mission_info.gd")
	var lines: Array[String]=[session.title(mission)]
	var instruction: String=info.instruction(mission,world.region)
	if not instruction.is_empty():lines.append(instruction)
	var target: String=info.target(session,mission)
	if not target.is_empty():lines.append(target)
	var progress: String=info.progress(session,mission)
	if not progress.is_empty():lines.append(progress)
	if world.region!=null and world.region.mission==mission:
		var encounter: String=info.encounter_progress(world.region)
		if not encounter.is_empty():lines.append(encounter)
	if objective_has_location(mission):lines.append(hold_line())
	return "\n".join(lines)
func hold_line() -> String:
	"""The objective's last line, picked out by objective_hud()."""
	return tr("Hold %s to auto-navigate")%OS.get_keycode_string(key_bindings.autopilot)
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
static func clock_text(milliseconds: int) -> String:
	"""bx.a: minutes and seconds, with hours in front once there are any."""
	var seconds: int=milliseconds/1000
	if seconds>=3600:return "%02d:%02d:%02d"%[seconds/3600,seconds/60%60,seconds%60]
	return "%02d:%02d"%[seconds/60,seconds%60]
func objective_hud(mission) -> String:
	var summary: PackedStringArray=objective_summary(mission).split("\n")
	var result: Array[String]=["[font_size=10][color=#87a8b3]"+tr("Current objective").to_upper().replace("[","[lb]")+"[/color][/font_size]", "[font_size=16][color=#e4ce92]"+summary[0].replace("[","[lb]")+"[/color][/font_size]"]
	for index in range(1,summary.size()):
		var text: String=summary[index].replace("[","[lb]")
		if summary[index].begins_with("Hold ") or summary[index]==hold_line():result.append("\n[font_size=11][color=#8acdc7]"+text+"[/color][/font_size]")
		elif summary[index].contains(" / "):result.append("[color=#a7dfc8]"+text+"[/color]")
		else:result.append(text)
	return "\n".join(result)
func autonavigate_objective() -> void:
	auto_fire=false
	var mission=current_objective()
	if world.encounter_navigation_point()!=null:
		world.navigate_encounter();close_page()
	elif objective_has_location(mission):
		if world.route_to_objective(mission.destination):stream_prompted=false;close_page()
		else:notice(world.message)
	else:notice(tr("This objective has no fixed destination. %s")%preload("res://native/presentation/mission_info.gd").instruction(mission,world.region))
func show_destinations() -> void:
	open_page(tr("Autopilot"),"destinations")
	var mission=current_objective()
	label(objective_summary(mission),15).modulate=Color("ddca92")
	button(tr("Objective travel · %s")%objective_travel_name(),func():
		world.objective_travel_mode=1-world.objective_travel_mode;save_settings();show_destinations()).tooltip_text=tr("Prefer S.T.R.E.A.M. via intermediate stations, or travel through the open ocean.")
	if world.objective_travel_mode==World.ObjectiveTravel.STREAM and objective_has_location(mission) and world.encounter_navigation_point()==null:
		var stops: Array[int]=world.objective_stream_route(mission.destination)
		if stops.size()>1:
			label(tr("S.T.R.E.A.M. route · %s")%" → ".join(stops.map(func(id):return session.stations[id].name)),13)
	var resume: int=world.resume_destination
	if resume>=0 and resume<session.stations.size() and resume!=session.station_id and not world.autopilot:
		# A route set on the chart (here or before leaving the station) stays
		# on offer after manual control takes over.
		var resume_name: String=session.stations[resume].name
		button(tr("Resume S.T.R.E.A.M. route · %s")%resume_name if world.resume_stream else tr("Resume autopilot · %s")%resume_name,resume_route)
	var objective_action:=button(tr("Navigate to quest objective"),autonavigate_objective)
	objective_action.disabled=not objective_has_location(mission)
	var actions:=GridContainer.new();actions.columns=2;actions.add_theme_constant_override("h_separation",10);column.add_child(actions)
	var dock_locked: bool=world.region.success!=null or world.region.failure!=null
	var dock_refusal: String=world.dock_denial()
	var dock_action := button(tr("Docking locked · encounter active") if dock_locked else (dock_refusal if not dock_refusal.is_empty() else tr("Dock at %s")%session.stations[session.station_id].name),func(): world.route_to(session.station_id); close_page(),actions)
	dock_action.disabled=dock_locked or not dock_refusal.is_empty()
	button(tr("Approach S.T.R.E.A.M. gate"),func():
		var gate: int=world.nearest_safe_gate()
		if gate<0:notice(tr("No S.T.R.E.A.M. gate in this area."));return
		world.fly_to_gate(gate);close_page(),actions)
	button(tr("Choose station on chart"),func():show_map(true),actions)
	if world.autopilot:button(tr("Disengage autopilot"),func():world.cancel_autopilot(tr("Manual control"));close_page(),actions)
	label(tr("%s: 1× / 2× while steering · up to 16× on autopilot")%OS.get_keycode_string(key_bindings.time),12)
func resume_route() -> void:
	var id: int=world.resume_destination
	var resumed: bool=world.plan_objective_stream(id) if world.resume_objective else world.plan_stream(id) if world.resume_stream else world.route_to(id)
	if not resumed: notice(world.message); return
	if world.resume_stream: stream_prompted=false
	close_page()
func objective_travel_name() -> String:
	return tr("Open water") if world.objective_travel_mode==World.ObjectiveTravel.OPEN_WATER else tr("Prefer S.T.R.E.A.M.")
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
		if say_hint("gate",keyed_text(342)):return
	if flight_ms>20000 and world.dock_denial().is_empty() and (world.in_docking_area() or Vector3(r.player.pose.origin[0],r.player.pose.origin[1],r.player.pose.origin[2]).length()<25000):
		if say_hint("dock",keyed_text(343)):return
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
	if session.ship.boost_cooldown>0 and say_hint("booster_card",keyed_text(346)):return
	if chapter==16 and session.station_id!=5 and say_hint("intranet%d"%session.station_id,session.text(280,session.name)):return
	if chapter==18 and not session.is_colonist_station() and session.station_id!=6 and say_hint("nothing%d"%session.station_id,session.text(281)):return
	if session.medals.complete_set() and say_hint("all_medals",session.text(350)):return
	if session.medals.gold_set() and say_hint("all_gold",session.text(351)):return
	if session.campaign.finished() and not session.medals.complete_set() and say_hint("hero",session.text(352)):return
var hold_full_seen := false
## The phone game's Vibration option: a buzz of 110 ms whenever shield,
## armour and hull together drop (bb), on a pad's rumble or a handheld's
## motor. Screens without a motor see it: the view jolts and the edges flash,
## each optional, and a hit the shield or armour absorbs shows only lightly.
var vibration := true
var hit_shake := true
var hull_seen := -1
var hull_only_seen := -1
func buzz(duration_ms: int) -> void:
	if not vibration:return
	if controller.device>=0:Input.start_joy_vibration(controller.device,0.6,0.9,duration_ms/1000.0)
	if OS.has_feature("mobile") or OS.has_feature("android"):Input.vibrate_handheld(duration_ms)
func check_hull_buzz() -> void:
	var r=world.region
	if r==null:hull_seen=-1;hull_only_seen=-1;return
	var health=r.player.health
	var total: int=health.hull+health.shield+health.armor
	if hull_seen>=0 and total<hull_seen:
		buzz(110)
		var whole: float=maxf(1.0,health.max_hull+session.ship.shield+session.ship.armor)
		var lost: float=float(hull_seen-total)/whole
		var strength: float
		if hull_only_seen>=0 and health.hull<hull_only_seen:strength=clampf(.45+lost*6.0,.45,1.0)
		else:strength=clampf(.2+lost*3.0,.2,.5)
		damage_feedback.hit(strength)
		if hit_shake:view.jolt(strength)
	hull_seen=total
	hull_only_seen=health.hull
	damage_feedback.update_hull(int(float(health.hull)/maxf(1.0,health.max_hull)*100.0),health.hull>0)
	hazard_warning.hull_percent=damage_feedback.hull_percent
func check_stream_proximity() -> void:
	# The chart must not reopen over the shot of the submarine leaving the far
	# aperture: it arrives at a gate that is already open, and inside range of it.
	if view.transit_progress>=0:return
	if not world.at_gate(world.departure_gate): stream_prompted=false; return
	# Manual approaches wait for the dock key. Autopilot uses a destination
	# already chosen on the map; a route to the gate alone still needs one.
	if not (world.autopilot and world.gate_navigation):return
	if world.gate_time[world.departure_gate]<world.GATE_OPEN_MS: return
	if stream_prompted:return
	if world.stream_destination>=0:
		stream_prompted=true
		stream_selection=world.stream_destination
		stream_resume_throttle=maxi(world.region.player.throttle_target,25)
		begin_stream_transit(false)
	else: show_stream_menu()

## Set while the canvas is being changed: that change emits size_changed again,
## and answering it from inside itself could only recurse.
var resizing := false
func update_render_resolution() -> void:
	if not is_inside_tree() or resizing: return
	var pixels := get_window().size
	if pixels.x<=0 or pixels.y<=0: return
	resizing=true
	Display.apply(get_window(),aspect_ratio,Display.responsive_size(pixels,touch.enabled()))
	resizing=false
	apply_side_margins()
	GraphicsQuality.apply_viewport(get_viewport(),quality.merged({"modern":modern_graphics},true),pixels)
func apply_side_margins() -> void:
	"""Insets the interface from a phone's notch and rounded corners on both
	sides; the 3D view behind it still fills the screen."""
	var margin: Dictionary=SafeMargins.margins(get_viewport().get_visible_rect().size,get_window().size,touch.enabled())
	if ui.offset_left!=margin.side or ui.offset_right!=-margin.side or ui.offset_top!=margin.top or ui.offset_bottom!=-margin.bottom:
		ui.offset_left=margin.side;ui.offset_right=-margin.side;ui.offset_top=margin.top;ui.offset_bottom=-margin.bottom
	# Screen effects cover the whole picture, including the interface's safe margins.
	for effect in [pressure_overlay,damage_feedback]:
		effect.offset_left=-margin.side;effect.offset_right=margin.side
		effect.offset_top=-margin.top;effect.offset_bottom=margin.bottom
func show_stream_menu() -> void:
	if not world.at_gate(world.departure_gate): return
	stream_prompted=true
	if world.stream_destination>=0: stream_selection=world.stream_destination
	# The menu pauses the simulation without changing manual thrust. A crossing
	# keeps at least one notch so the submarine can clear the far aperture.
	if page!="stream": stream_resume_throttle=maxi(world.region.player.throttle_target,25)
	world.cancel_autopilot()
	open_page(chart_title(),"stream")
	view.gate_preview=true
	var eligible: Array=[]
	for station in session.stations:
		if world.stream_denial(station.id).is_empty(): eligible.append(station.id)
	if not stream_selection in eligible: stream_selection=eligible[0] if not eligible.is_empty() else -1
	var actions := station_chart(stream_selection)
	var options := OptionButton.new();options.custom_minimum_size.x=210;actions.add_child(options)
	StationTheme.style_option(options,golden(),touch.enabled())
	for id in eligible: options.add_item(str(session.stations[id].name),id)
	options.disabled=eligible.size()<2
	var species := species_toggle(actions,func(): pass)
	var gap := Control.new(); gap.size_flags_horizontal=Control.SIZE_EXPAND_FILL; actions.add_child(gap)
	var confirm := bar_button(tr("Initiate transit  >").to_upper(),begin_stream_transit,actions)
	bar_button(tr("Back"),dock_back,actions)
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
			if eligible.is_empty():prompt=[tr("No exits"),tr("No exits in range. Fit a longer-range engine.")]
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
		var status: String=(session.text(255) if figures.unsafe else tr("Exit ready")) if denial.is_empty() else "" if figures.far else denial
		show_station_card(id,tr("%s\n%s: %s · %s: %s\u00a0m\nDistance %s\u00a0km · reach %.1f\u00a0km%s")%[
			tr("Rebels") if session.campaign.rebel_stations[id] else tr("Colonists"),session.text(44),tech_text(id),session.text(245),figures.depth,
			figures.distance,world.map_kilometers(world.stream_range()),"" if status.is_empty() else "\n"+status])
		confirm.disabled=not denial.is_empty()
	species.pressed.connect(func(): select.call(stream_selection))
	map_slice.selected.connect(select)
	map_widget.zone_dragged.connect(func(center):follow_drag(center,stream_selection))
	map_widget.zone_moved.connect(func(center,near):select.call(zone_choice(center,near,stream_selection)))
	options.item_selected.connect(func(at): select.call(options.get_item_id(at)))
	select.call(stream_selection)

func show_habitat(id: int, parent: Node) -> void:
	"""Which species live at a station, the most common first, and which of
	them this expedition has already caught."""
	var habitat: Array = preload("res://native/simulation/habitat.gd").prevalence(content.data,id)
	var living: Array = []
	for index in range(0,habitat.size(),2):
		if int(habitat[index+1])>0:living.append_array([habitat[index],habitat[index+1]])
	habitat=living
	habitat_picker(parent)
	label(tr("Species found here").to_upper(),13,parent).modulate=Color("93b5aa")
	# Two columns where they fit beside the card's figures; one on a narrow
	# card, where two broke the names in the middle of a word.
	var grid := GridContainer.new();grid.columns=2 if parent.size.x>=460 else 1;
	# The card outlives this list; the handler goes with the list, or a later
	# resize would reach a freed grid.
	var relayout:=func():grid.columns=2 if parent.size.x>=460 else 1
	parent.resized.connect(relayout);grid.tree_exiting.connect(func():if parent.resized.is_connected(relayout):parent.resized.disconnect(relayout))
	grid.add_theme_constant_override("h_separation",14);grid.add_theme_constant_override("v_separation",2);parent.add_child(grid)
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
		var name_label := label(item_name(species) if known else tr("Unrecorded"),15,line)
		name_label.modulate=Color("d7edf1") if known else Color("6d8894")
		name_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		if known:
			var caught := label(tr("caught"),12,line);caught.modulate=Color("c9ae79");caught.autowrap_mode=TextServer.AUTOWRAP_OFF;caught.size_flags_horizontal=Control.SIZE_SHRINK_END
func habitat_picker(parent: Node) -> void:
	"""bp's species list (dq): which caught species' range the chart shows,
	the algae together, or none."""
	var choices: Array=[[-1,session.text(324)]]
	if range(13,18).any(func(id):return id<session.fish_found.size() and session.fish_found[id]):choices.append([-3,session.text(261)])
	for id in mini(13,session.fish_found.size()):
		if session.fish_found[id]:choices.append([id,item_name(id)])
	if habitat_range!=-1 and not choices.any(func(choice):return choice[0]==habitat_range):habitat_range=-1
	var line := HBoxContainer.new();line.add_theme_constant_override("separation",8);parent.add_child(line)
	label(tr("Range on chart"),13,line).modulate=Color("93b5aa")
	var picker := OptionButton.new();StationTheme.style_option(picker,golden(),touch.enabled());line.add_child(picker)
	for choice in choices:
		picker.add_item(choice[1],choice[0] if choice[0]>=0 else 1000-choice[0])
		# bp's list pictures: the cross for none, the last alga for the algae.
		var picture: Texture2D=imported_art.item(choice[0]) if choice[0]>=0 else imported_art.item(17) if choice[0]==-3 else imported_art.image("x_1")
		if picture!=null:picker.set_item_icon(picker.item_count-1,picture)
		if choice[0]==habitat_range:picker.select(picker.item_count-1)
	picker.item_selected.connect(func(index):
		var id: int=picker.get_item_id(index);habitat_range=id if id<1000 else 1000-id
		if is_instance_valid(map_widget):map_widget.habitat_species=habitat_range;map_widget.habitat_caption=species_caption(habitat_range);map_widget.queue_redraw())
func species_caption(id: int) -> String:
	"""bp's line under the chart for the fish whose range it shows: the name
	and the weights a catch comes in, three quarters to five quarters of the
	species' mass (cj.a, cj.b)."""
	var creatures: Array=content.data.tables.get("creatures",[])
	if id<0 or id>=creatures.size():return ""
	var mass:=float(creatures[id][1])
	return "%s  (%s – %s)"%[item_name(id),tr("%d t")%int(mass*0.75),tr("%d t")%int(mass*1.25)]
var travel_confirmed := -1
func ask_travel(id: int, go: Callable, back: Callable, warn := true) -> bool:
	"""The original asks before every trip, on the chart (bp) and again at the
	gate (br.a), with the game paused: the destination (334), the depth
	warning (255) when the hull's limits are exceeded (the gate's own question
	leaves it out), and "Travel to this station?" (247). True while the question is open; answering yes runs go
	again with the answer recorded. Docking where you are asks nothing."""
	if travel_confirmed==id: travel_confirmed=-1;return false
	if id<0 or id>=session.stations.size() or id==session.station_id: return false
	confirm(session.text(334)+": "+session.stations[id].name,(session.text(255)+"\n" if warn and world.outside_safety(id) else "")+session.text(247),tr("Travel"),
		func():travel_confirmed=id;go.call(),back)
	return true
func begin_stream_transit(chosen_here := true) -> void:
	"""Confirming a destination is the crossing. The original does not fly the
	submarine into the aperture and wait: the chart closes, the far side is
	already there, and what the player watches is the way out of it. So there is
	no run-up to steer, nothing to arm and no notice to read."""
	var denial: String=world.stream_denial(stream_selection)
	if not denial.is_empty() or not world.at_gate(world.departure_gate):notice(denial);return
	# A destination planned earlier is asked about again at the gate, as br.a
	# does, without repeating the chart's depth warning.
	if ask_travel(stream_selection,begin_stream_transit.bind(chosen_here),show_stream_menu,chosen_here):return
	world.cancel_autopilot("",not chosen_here);world.gate_navigation=false;world.approach_planned=false;world.approach_path.clear()
	if chosen_here:world.resume_destination=stream_selection;world.resume_stream=true;world.resume_objective=false
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
	var arriving: bool=view.transit_emerging
	if arriving and world.region!=null:
		world.region.player.speed_factor=transit_exit_factor
		world.region.player.set_throttle(roundi(transit_exit_throttle))
	view.end_transit()
	if arriving and world.continue_objective_route():stream_prompted=false
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
		holder.name="ShipLine";holder.accessibility_name=content.ship_name(session.ship.id);holder.tooltip_text=tr("Ship and cargo")
		holder.custom_minimum_size.y=52 if ui.size.y<700 else 56
		var strip := HBoxContainer.new();strip.add_theme_constant_override("separation",16);holder.add_child(strip)
		strip.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);strip.offset_left=14;strip.offset_right=-14;strip.mouse_filter=Control.MOUSE_FILTER_IGNORE
		var hull := art_image(imported_art.item(session.ship.id,"ships"),strip,40)
		if hull!=null: hull.custom_minimum_size.x=64;hull.size_flags_vertical=Control.SIZE_SHRINK_CENTER
		caption(content.ship_name(session.ship.id),18,strip,4).add_theme_color_override("font_color",palette.text)
		var used: int=session.ship.equipment.filter(func(item):return item!=null).size()
		caption(tr("%d / %d equipment slots")%[used,session.ship.slots],12,strip,2).size_flags_vertical=Control.SIZE_SHRINK_CENTER
		line_icon("next",18,strip)
	if entries.is_empty(): label(tr("No ships available at this station.") if ships else tr("No equipment for sale at this station.") if equipment_tab==0 else tr("No equipment installed. Choose Shop to fit a system.")).add_theme_color_override("font_color",palette.dim);return
	market_selection=clampi(market_selection,0,entries.size()-1)
	var row := split_row(column,18)
	var list := VBoxContainer.new();list.name="StockList";list.size_flags_horizontal=Control.SIZE_EXPAND_FILL;list.add_theme_constant_override("separation",6);row.add_child(list)
	var headings := HBoxContainer.new();list.add_child(headings)
	caption(tr("Ships for sale") if ships else tr("Shop stock") if equipment_tab==0 else tr("Installed systems"),12,headings,3)
	var value_heading := caption(tr("Value"),12,headings,3);value_heading.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	var row_height: int=(76 if ships else 64) if touch.enabled() else (72 if ships else 60)
	var stock := scrolled_rows(list,"StockRows_"+kind+str(equipment_tab))
	stock.get_parent().get_parent().custom_minimum_size.y=list_height(entries.size(),row_height,row)
	for index in entries.size():
		var entry: Dictionary=entries[index];var item=entry.item
		var title: String=content.ship_name(item.id) if ships else item_name(item.id,"equipment")
		var price: int=economy.ship_price(item) if ships else item.price
		var cells := stock_row("Stock_"+str(index),index==market_selection,row_height,func():market_selection=index;show_market(kind),stock)
		var control := cells.get_parent() as Button;control.accessibility_name=title
		var icon := TextureRect.new();icon.texture=imported_art.item(item.id,kind);icon.custom_minimum_size=Vector2(72 if ships else 56,40);icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;icon.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;icon.mouse_filter=Control.MOUSE_FILTER_IGNORE;cells.add_child(icon)
		var words := VBoxContainer.new();words.size_flags_horizontal=Control.SIZE_EXPAND_FILL;words.add_theme_constant_override("separation",1);words.alignment=BoxContainer.ALIGNMENT_CENTER;cells.add_child(words);words.mouse_filter=Control.MOUSE_FILTER_IGNORE
		var named := label(title,17,words);named.add_theme_color_override("font_color",palette.text);named.autowrap_mode=TextServer.AUTOWRAP_OFF;named.clip_text=true;named.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
		var stats := tr("Hull %d · Cargo %d · Slots %d · Handling %d")%[item.hull,item.capacity(),item.slots,handling(item,false)] if ships else EquipmentInfo.stats(item)
		var spec := label(stats,13,words);spec.add_theme_color_override("font_color",palette.dim);spec.max_lines_visible=1;spec.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;spec.autowrap_mode=TextServer.AUTOWRAP_OFF;spec.clip_text=true
		var value := label(Coin.coins(tr("%d cr")%price) if entry.buy else tr("Installed").to_upper(),15,cells);value.custom_minimum_size.x=96;value.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT;value.size_flags_horizontal=Control.SIZE_SHRINK_END;value.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
		value.add_theme_color_override("font_color",palette.value if entry.buy else palette.good);value.autowrap_mode=TextServer.AUTOWRAP_OFF
		control.tooltip_text=title+"\n"+stats
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
		var fitted := caption(tr("Installed"),12,heading_row,2);fitted.add_theme_color_override("font_color",palette.good);fitted.size_flags_horizontal=Control.SIZE_SHRINK_END
	caption(tr("For sale") if ships else EquipmentInfo.kind_name(item),12,detail,4)
	rule(detail)
	if ships:
		var better := func(now: int, next: int) -> Color: return palette.good if next>now else palette.bad if next<now else palette.text
		figure_rows([["hull",tr("Hull"),"%d  →  %d"%[session.ship.hull,item.hull],better.call(session.ship.hull,item.hull)],
			["cargo",tr("Cargo"),"%d  →  %d"%[session.ship.capacity(),item.capacity()],better.call(session.ship.capacity(),item.capacity())],
			["grid",tr("Slots"),"%d  →  %d"%[session.ship.slots,item.slots],better.call(session.ship.slots,item.slots)],
			["controls",tr("Handling"),"%d  →  %d"%[handling(session.ship,false),handling(item,false)],better.call(handling(session.ship,false),handling(item,false))]],detail)
		rule(detail)
		label(item_description(item.id,"ships"),15,detail).add_theme_color_override("font_color",palette.text)
		rule(detail)
		# be: a hull once owned is worth its catalogue price divided by 1.25.
		var balance: int=session.credits+economy.ship_price(session.ship)-economy.ship_price(item)
		figure_rows([["",tr("Trade-in for your %s")%content.ship_name(session.ship.id),Coin.coins(tr("%d cr")%economy.ship_price(session.ship)),palette.value],
			["",tr("Balance after exchange"),Coin.coins(tr("%d cr")%balance),palette.value if balance>=0 else palette.bad]],detail)
		var purchase := primary(iconic(button(Coin.coins(tr("Buy · %d cr")%economy.ship_price(item)),func():transaction_result(economy.buy_ship(station,item),content.ship_name(item.id)+" "+session.text(89));show_market(kind),detail),"depart",22))
		market_action(purchase,economy.buy_ship_denial(station,item))
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
					caption(tr("Currently equipped"),11,current,3)
					label(item_name(installed.id,"equipment"),15,current).add_theme_color_override("font_color",palette.text)
					label(EquipmentInfo.stats(installed),13,current).add_theme_color_override("font_color",palette.dim)
			var purchase := primary(iconic(button(Coin.coins(tr("Buy · %d cr")%item.price),func():transaction_result(economy.buy_equipment(station,item),item_name(item.id,"equipment")+" "+session.text(91));show_market(kind),detail),"cart",22))
			market_action(purchase,economy.buy_equipment_denial(station,item))
		else:
			var sale := iconic(button(Coin.coins(tr("Sell · %d cr")%item.price),func():transaction_result(economy.sell_equipment(station,item),item_name(item.id,"equipment")+" "+session.text(90));show_market(kind),detail),"credits",22);sale.alignment=HORIZONTAL_ALIGNMENT_CENTER
			market_action(sale,economy.sell_equipment_denial(station,item))
	link_stock_detail(stock,detail)
func link_stock_detail(stock: Node, detail: Control) -> void:
	"""Right from the stock list goes to the chosen entry's actions and Left
	from them back to its row. The Buy button sits below most rows, where
	moving by position never reached it without the mouse."""
	var targets: Array[Control]=[]
	FocusMap.collect(detail,null,targets)
	if targets.is_empty():return
	var buy: Control=targets[0]
	for target in targets:
		if target.has_meta("primary"):buy=target;break
	for row in stock.get_children():
		if row is Control:row.focus_neighbor_right=row.get_path_to(buy)
	var selected := stock.get_node_or_null("Stock_"+str(market_selection)) as Control
	if selected==null:return
	# Placed only once laid out: the actions with nothing of the detail to
	# their left lead back to the list.
	for _frame in 2:await get_tree().process_frame
	if not is_instance_valid(selected):return
	for target in targets:
		if not is_instance_valid(target):continue
		var rect: Rect2=target.get_global_rect()
		if targets.all(func(other):return other==target or not is_instance_valid(other) or FocusMap.distance(rect,other.get_global_rect(),SIDE_LEFT)==INF):
			target.focus_neighbor_left=target.get_path_to(selected)
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
static func sorted_recipes(entries: Array) -> Array:
	"""cp's order: recipes the hold can make first, the most batches first,
	then those wanting the fewest of their ingredients; ties keep the table."""
	var order: Dictionary={}
	for index in entries.size():order[entries[index]]=index
	var share:=func(entry)->float:return INF if entry.missing_ingredients<=0 else float(entry.ingredients.size())/entry.missing_ingredients
	var sorted: Array=entries.duplicate()
	sorted.sort_custom(func(a,b):
		var left: float=share.call(a);var right: float=share.call(b)
		if left!=right:return left>right
		if a.owned!=b.owned:return a.owned>b.owned
		return order[a]<order[b])
	return sorted
func goods_tabs(kind: String) -> void:
	"""Cargo and Workshop as the original Trade screen's two tabs (ds): the
	product just made is one tab away from its sale. LB/RB switch them."""
	var tabs := HBoxContainer.new();tabs.name="TradeTabs";tabs.add_theme_constant_override("separation",10);column.add_child(tabs)
	for entry in [["trade",tr("Cargo"),"cart","CargoTab"],["manufacture",tr("Workshop"),"workshop","WorkshopTab"]]:
		var target: String=entry[0]
		var tab := iconic(button(str(entry[1]).to_upper(),func():switch_goods_tab(target),tabs),entry[2],24)
		tab.name=entry[3];tab.toggle_mode=true;tab.button_pressed=kind==target;tab.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		tab.alignment=HORIZONTAL_ALIGNMENT_CENTER;tab.add_theme_font_override("font",heading_font(4))
		if ui.size.y<700: tab.custom_minimum_size.y=52
		if kind==target:
			var lit := StationTheme.button_state(golden(),"focus");lit.content_margin_left=50;lit.border_width_bottom=3
			tab.add_theme_stylebox_override("normal",lit);tab.add_theme_stylebox_override("pressed",lit)
func fit_market() -> void:
	"""The trade page's height: its rows, but never shorter than the tallest
	good already shown on this tab, so the frame does not jump between them.
	Measured after the build, when the list has taken its scrolling height."""
	if page!="market" or market_category not in ["trade","manufacture"]:return
	if market_floor_kind!=market_category:market_floor_kind=market_category;market_floor=0.0
	market_floor=maxf(market_floor,fitted_height())
	layout()
func trade_side(title: String, amount: String, parent: Node, hold: bool) -> HBoxContainer:
	"""One side of the exchange, its heading over its count; the arrow goes
	on its outer edge."""
	var side := VBoxContainer.new();side.size_flags_horizontal=Control.SIZE_EXPAND_FILL;side.add_theme_constant_override("separation",4);parent.add_child(side)
	caption(title,11,side,2).horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT if hold else HORIZONTAL_ALIGNMENT_LEFT
	var line := HBoxContainer.new();line.add_theme_constant_override("separation",12);line.alignment=BoxContainer.ALIGNMENT_END if hold else BoxContainer.ALIGNMENT_BEGIN;side.add_child(line)
	var count := label(amount,22,line);count.add_theme_color_override("font_color",colours().text);count.autowrap_mode=TextServer.AUTOWRAP_OFF
	count.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN;count.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	return line
func trade_arrow(key: String, icon: String, name: String, disabled: bool, action: Callable, parent: Node) -> Button:
	"""A one-tonne move that keeps focus, so it can be pressed again and again."""
	var arrow := option("",key,action,parent);arrow.name=key;arrow.accessibility_name=name;arrow.tooltip_text=name
	arrow.custom_minimum_size=Vector2(64,48);arrow.size_flags_horizontal=Control.SIZE_SHRINK_CENTER;arrow.disabled=disabled
	var mark := StationIcon.new(icon,colours().faint if disabled else colours().accent,26);arrow.add_child(mark);mark.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return arrow
func switch_goods_tab(target: String) -> void:
	if market_category!=target:show_market(target)
func goods_browser(station: Dictionary, manufacturing: bool=false) -> void:
	var kind: String="manufacture" if manufacturing else "trade"
	var palette := colours()
	# Leave room for the recipe actions on shorter screens.
	var compact := ui.size.y<800
	# The market comes hold first, as the original lists it (aa.a); recipes
	# sort as cp does, those the hold can make first.
	var entries: Array=sorted_recipes(economy.recipes(station)) if manufacturing else economy.market(station)
	if entries.is_empty():label(tr("No recipes available here.") if manufacturing else tr("No cargo available for exchange.")).add_theme_color_override("font_color",palette.dim);return
	var picked: int=entries.map(func(entry):return entry.id).find(market_selected_id)
	market_selection=picked if picked>=0 else clampi(market_selection,0,entries.size()-1)
	market_selected_id=entries[market_selection].id
	# The hold, as a gauge: how much there is room for decides both trades.
	if compact:
		header_chip("cargo",tr("%d / %d t")%[session.ship.cargo_used,session.ship.capacity()],tr("Cargo hold"))
	var hold := HBoxContainer.new();hold.add_theme_constant_override("separation",16)
	if not compact: glass(column,false,10).add_child(hold)
	line_icon("cargo",32,hold)
	var hold_words := VBoxContainer.new();hold_words.add_theme_constant_override("separation",0);hold.add_child(hold_words)
	caption(tr("Cargo hold"),14,hold_words,4).add_theme_color_override("font_color",palette.text)
	caption(tr("%d of %d t used")%[session.ship.cargo_used,session.ship.capacity()],10,hold_words,2)
	var gauge := ProgressBar.new();gauge.show_percentage=false;gauge.max_value=maxi(1,session.ship.capacity());gauge.value=session.ship.cargo_used
	gauge.size_flags_horizontal=Control.SIZE_EXPAND_FILL;gauge.size_flags_vertical=Control.SIZE_SHRINK_CENTER;gauge.custom_minimum_size.y=8;hold.add_child(gauge)
	var track := StationTheme.frame(Color(0,0,0,.35),palette.edge,0);var fill := StationTheme.frame(palette.accent,palette.accent,0)
	gauge.add_theme_stylebox_override("background",track);gauge.add_theme_stylebox_override("fill",fill)
	caption("%d%%"%roundi(100.0*session.ship.cargo_used/maxi(1,session.ship.capacity())),14,hold,1).add_theme_color_override("font_color",palette.text)
	if hold.get_parent()==null: hold.free()
	var row:=split_row(column,18)
	var list:=VBoxContainer.new();list.name="StockList";list.size_flags_horizontal=Control.SIZE_EXPAND_FILL;list.size_flags_stretch_ratio=1.25;list.add_theme_constant_override("separation",6);row.add_child(list)
	var headings:=HBoxContainer.new();list.add_child(headings)
	caption(tr("Recipe & materials") if manufacturing else tr("Cargo"),12,headings,3)
	if manufacturing:caption(tr("Can make"),12,headings,3).horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	var row_height:=64 if touch.enabled() else 56
	var stock := scrolled_rows(list,"StockRows_"+kind)
	stock.get_parent().get_parent().custom_minimum_size.y=list_height(entries.size(),row_height,row)
	for index in entries.size():
		var item=entries[index];var title:=item_name(item.id)
		var cells:=stock_row("Stock_"+str(index),index==market_selection,row_height,func():market_selection=index;market_selected_id=item.id;show_market(kind),stock)
		(cells.get_parent() as Button).accessibility_name=title
		var icon:=TextureRect.new();icon.texture=imported_art.item(item.id);icon.custom_minimum_size=Vector2(48,40);icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;icon.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;icon.mouse_filter=Control.MOUSE_FILTER_IGNORE;cells.add_child(icon)
		var words:=VBoxContainer.new();words.size_flags_horizontal=Control.SIZE_EXPAND_FILL;words.add_theme_constant_override("separation",0);words.alignment=BoxContainer.ALIGNMENT_CENTER;words.mouse_filter=Control.MOUSE_FILTER_IGNORE;cells.add_child(words)
		label(title,17,words).add_theme_color_override("font_color",palette.text)
		var subtitle: String=(tr("Materials ready") if item.owned>0 else tr("Missing %d of %d materials")%[maxi(1,item.missing_ingredients),item.ingredients.size()]) if manufacturing else "%s %d"%[tr("Station stock"),item.stock]
		label(subtitle,13,words).add_theme_color_override("font_color",palette.good if manufacturing and item.owned>0 else palette.dim)
		# The station's own price is beside the selected cargo; the list gives the
		# range it moves within everywhere, with what is aboard under it.
		var figures:=VBoxContainer.new();figures.add_theme_constant_override("separation",0);figures.alignment=BoxContainer.ALIGNMENT_CENTER;figures.size_flags_horizontal=Control.SIZE_SHRINK_END;figures.mouse_filter=Control.MOUSE_FILTER_IGNORE;cells.add_child(figures)
		var value:=label(str(maxi(0,item.owned)) if manufacturing else "%d – %s"%[item.minimum_price,Coin.coins(tr("%d cr")%item.maximum_price)],16,figures);value.custom_minimum_size.x=84;value.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT;value.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
		value.add_theme_color_override("font_color",palette.value);value.autowrap_mode=TextServer.AUTOWRAP_OFF
		if not manufacturing:
			var aboard:=label("%s %d"%[tr("In hold"),item.owned],13,figures);aboard.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT;aboard.autowrap_mode=TextServer.AUTOWRAP_OFF
			aboard.add_theme_color_override("font_color",palette.text if item.owned>0 else palette.dim)
	var frame := glass(row,true,16);frame.custom_minimum_size.x=380 if ui.size.x>=900 else 0
	var detail:=VBoxContainer.new();detail.name="SelectedItem";detail.add_theme_constant_override("separation",9);frame.add_child(detail)
	var item=entries[market_selection]
	# The picture beside the name and description, so the figures and actions
	# follow straight on below.
	var about := HBoxContainer.new();about.add_theme_constant_override("separation",14);detail.add_child(about)
	var holder := glass(about,false,8);holder.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN;holder.size_flags_vertical=Control.SIZE_SHRINK_BEGIN
	var art := art_image(imported_art.item(item.id),holder,56 if compact else 80)
	if art==null: holder.hide()
	var heading := VBoxContainer.new();heading.add_theme_constant_override("separation",2);heading.size_flags_horizontal=Control.SIZE_EXPAND_FILL;about.add_child(heading)
	label(item_name(item.id),26,heading).add_theme_color_override("font_color",palette.text)
	if not compact: caption(tr("Product") if manufacturing else tr("Cargo"),12,heading,4)
	var described := label(item_description(item.id),14,heading);described.add_theme_color_override("font_color",palette.text)
	if manufacturing:
		var price_range := figure_rows([["credits",tr("Unit price"),"%s – %s"%[Coin.coins(tr("%d cr")%item.minimum_price),Coin.coins(tr("%d cr")%item.maximum_price)],palette.value]],detail)
		price_range.name="PriceRange"
		caption(tr("Ingredients (in cargo / per unit)"),11,detail,3)
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
		label(tr("Available to make: %d")%maxi(0,item.owned),15,detail).add_theme_color_override("font_color",palette.text)
		var actions := action_row(detail)
		var one := iconic(button(tr("Make one"),func():
			if not economy.manufacture(station,item.id,1):notice(tr("Required ingredients or cargo space are missing."))
			else:notice(tr("Made 1 %s")%item_name(item.id));market_selected_id=item.id
			show_market(kind),actions),"cargo",22)
		one.disabled=item.owned<1
		if not one.disabled: primary(one)
		iconic(button(tr("Make all (%d)")%maxi(0,item.owned),func():
			if not economy.manufacture(station,item.id,item.owned):notice(tr("Required ingredients or cargo space are missing."))
			else:notice(tr("Made %d %s")%[item.owned,item_name(item.id)]);market_selected_id=item.id
			show_market(kind),actions),"trade",22).disabled=item.owned<2
	else:
		figure_rows([["credits",tr("Unit price"),Coin.coins(tr("%d cr")%item.price),palette.value]],detail)
		# The original's two sides (ds): the station's shelf on the left, the
		# hold on the right, an arrow on each moving a tonne across, and the
		# whole lot either way below.
		var affordable := buy_limit(item)
		var sellable: int=maxi(0,item.owned)
		var exchange := glass(detail,false,10);exchange.name="Exchange"
		var sides := HBoxContainer.new();sides.add_theme_constant_override("separation",12);exchange.add_child(sides)
		var shelf := trade_side(tr("Station stock"),tr("%d t")%item.stock,sides,false)
		var aboard := trade_side(tr("In hold"),tr("%d t")%item.owned,sides,true)
		var sell_one := trade_arrow("SellOne","arrow_left",tr("Sell 1 t"),sellable<1,func():trade_amount(station,item,false,1);show_market(kind),shelf)
		shelf.move_child(sell_one,0)
		trade_arrow("BuyOne","arrow_right",tr("Buy 1 t"),affordable<1,func():trade_amount(station,item,true,1);show_market(kind),aboard)
		var actions := action_row(detail)
		# No icons: a large sum needs the whole width, and wraps if even that
		# is too little.
		var sale := button(Coin.coins(tr("Sell all · %d cr")%(item.price*sellable)),func():
			trade_amount(station,item,false,sellable)
			show_market(kind),actions)
		sale.name="SellAll";sale.disabled=sellable<1
		var purchase := button(Coin.coins(tr("Buy all · %d cr")%(item.price*affordable)),func():
			trade_amount(station,item,true,affordable)
			show_market(kind),actions)
		purchase.name="BuyAll";purchase.disabled=affordable<1
		for total in [sale,purchase]:
			total.alignment=HORIZONTAL_ALIGNMENT_CENTER;total.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		if not purchase.disabled: primary(purchase)
	link_stock_detail(stock,detail)
	fit_market.call_deferred()
