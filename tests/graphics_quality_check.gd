extends SceneTree
## Graphics presets, first-start detection, headlight brightness and touch
## scrolling on the title's settings screen.
const Quality=preload("res://native/presentation/graphics_quality.gd")
const Probe=preload("res://native/presentation/graphics_probe.gd")
const SETTINGS := "user://graphics-quality-check/settings.cfg"
const SAVE := "user://graphics-quality-check/campaign.json"
var failures := 0

func expect(ok: bool, why: String) -> void:
	if not ok:failures+=1;push_error(why)
func _initialize() -> void:call_deferred("run")

func frames(count: int) -> void:
	for i in count:await process_frame

func saved() -> ConfigFile:
	var config := ConfigFile.new();config.load(SETTINGS);return config

func run() -> void:
	# A headless window is tiny; touch arrives in window pixels.
	root.size=Vector2i(1280,720)
	check_presets()
	check_probe_rules()
	DirAccess.make_dir_recursive_absolute(SETTINGS.get_base_dir())
	DirAccess.remove_absolute(SETTINGS);DirAccess.remove_absolute(SAVE)
	var app=load("res://scenes/native_main.tscn").instantiate()
	app.save_path=SAVE;app.settings_path=SETTINGS
	root.add_child(app)
	if not app.ready_for_preview:app.open_cache(OS.get_cmdline_user_args()[0])
	await frames(4)
	expect(app.wants_graphics_probe()==false,"A headless run never measures the device")
	await check_detection(app)
	await check_settings_rows(app)
	await check_display_rows(app)
	app.show_settings("graphics");await frames(3)
	await check_touch_scroll(app)
	await check_manual_choice(app)
	app.queue_free();await frames(2)
	DirAccess.remove_absolute(SETTINGS);DirAccess.remove_absolute(SAVE)
	print("GRAPHICS_QUALITY_CHECK ","OK" if failures==0 else "FAILED %d"%failures)
	quit(1 if failures>0 else 0)

func check_presets() -> void:
	var empty := ConfigFile.new()
	var quality := Quality.read(empty)
	expect(quality.height==0 and quality.scale==100 and quality.shadows==3 and quality.modern,"Without settings the view is native at 100% with full shadows")
	expect(not Quality.has_preset(empty),"A new settings file has no preset yet")
	var older := ConfigFile.new();older.set_value("view","resolution_v5",0)
	expect(Quality.read(older).height==1080 and Quality.read(older).scale==100,"The earlier 1080p choice becomes the 1080p display resolution")
	older.set_value("view","resolution_v5",99)
	expect(Quality.read(older).height==0,"An out-of-range earlier resolution is native")
	older.set_value("view","resolution_height",777)
	expect(Quality.read(older).height==0,"An unknown resolution is native")
	older.set_value("view","render_scale",33)
	expect(Quality.read(older).scale==100,"An unknown 3D percentage is 100%")
	for preset in range(Quality.LOW,Quality.VERY_HIGH+1):
		var kept := ConfigFile.new();kept.set_value("view","render_scale",75);kept.set_value("view","resolution_height",1080);Quality.write(kept,preset)
		expect(Quality.read(kept).scale==75 and Quality.read(kept).height==1080,"Presets leave resolution alone")
	for preset in range(Quality.CLASSIC,Quality.VERY_HIGH+1):
		var config := ConfigFile.new();Quality.write(config,preset)
		expect(Quality.current(config)==preset,"%s reads back as itself"%Quality.PRESETS[preset])
		expect(Quality.has_preset(config),"Writing a preset records it")
	var config := ConfigFile.new();Quality.write(config,Quality.HIGH)
	config.set_value("graphics","shadows",1)
	expect(Quality.current(config)==Quality.CUSTOM,"Changing a preset's setting makes it Custom")
	Quality.write(config,Quality.MEDIUM);config.set_value("view","temporal_aa",true)
	expect(Quality.current(config)==Quality.CUSTOM,"Temporal antialiasing is outside every preset")
	var low := Quality.preset_quality(Quality.LOW)
	expect(low.shadows==0 and low.msaa==0 and not low.volumetric and not low.detail,"Low turns off the costly items")
	var top := Quality.preset_quality(Quality.VERY_HIGH)
	expect(top.shadows==3 and top.msaa==2 and top.volumetric and top.detail,"Very high keeps everything")
	var chosen := ConfigFile.new();Quality.mark_chosen(chosen,"graphics","marine_snow")
	expect(not Quality.has_preset(chosen),"An ocean effect is not a preset setting")
	Quality.mark_chosen(chosen,"graphics","shadows")
	expect(Quality.has_preset(chosen),"A hand-set shadow quality counts as a choice")
	expect(Quality.render_scale({"height":720,"scale":100},Vector2i(2560,1440))==0.5,"720p on a 1440p screen draws at half scale")
	expect(Quality.render_scale({"height":0,"scale":50},Vector2i(2560,1440))==0.5,"50% of native draws at half scale")
	expect(is_equal_approx(Quality.render_scale({"height":1080,"scale":50},Vector2i(2560,1440)),0.375),"The percentage applies to the display resolution")
	expect(Quality.render_scale({"height":2160,"scale":100},Vector2i(1920,1080))==1.0,"A resolution above the screen's is the screen's")
	expect(Quality.heights_for(1080)==[0,720,900],"Only resolutions below the screen's are offered")
	var strength := ConfigFile.new()
	expect(Quality.headlight_strength(strength)==1.0,"Headlights start at full strength")
	strength.set_value("graphics","headlight_strength",0.01)
	expect(Quality.headlight_strength(strength)==Quality.HEADLIGHT_LOW,"Headlight strength keeps a floor")
	strength.set_value("graphics","headlight_strength","bright")
	expect(Quality.headlight_strength(strength)==1.0,"A malformed strength is full strength")

func check_probe_rules() -> void:
	var steady: Array=[];var smooth: Array=[];var busy: Array=[];var none: Array=[]
	for i in 60:steady.append(1.0/60.0);smooth.append(8.0);busy.append(14.0);none.append(0.0)
	expect(Probe.fast_enough(steady,smooth,smooth),"Sixty frames a second with room to spare passes")
	expect(not Probe.fast_enough(steady,busy,smooth),"Sixty frames with no GPU room left fails")
	expect(Probe.fast_enough(steady,none,none),"Without render-time queries a steady sixty passes")
	var slow: Array=[];for i in 60:slow.append(1.0/40.0)
	expect(not Probe.fast_enough(slow,none,none),"Forty frames a second fails")
	var probe := Probe.new()
	probe.results={Quality.HIGH:true,Quality.VERY_HIGH:false}
	expect(probe.best()==Quality.HIGH,"The highest passing preset wins")
	probe.results={Quality.HIGH:false,Quality.MEDIUM:false,Quality.LOW:false}
	expect(probe.best()==Quality.LOW,"Low is the floor, never Classic")
	probe.free()

func check_detection(app) -> void:
	app.start_graphics_probe()
	expect(app.probing(),"The device can be measured on request")
	var started := Time.get_ticks_msec()
	while app.probing() and Time.get_ticks_msec()-started<40000:
		await process_frame
	expect(not app.probing(),"Measuring finishes")
	var config := saved()
	expect(Quality.has_preset(config),"The measured preset is stored")
	expect(Quality.current(config)>=Quality.LOW and Quality.current(config)<=Quality.VERY_HIGH,"Measuring chooses a preset from Low up")
	expect(app.modal.visible and app.modal.find_child("GraphicsChoice",true,false)!=null,"The first choice is shown in a dialog")
	expect(Quality.recommended(saved())==Quality.current(saved()),"The measured preset is the recommended one")
	app.close_modal();await frames(2)
	# A preset from before the recommendation was stored: measure, keep the preset.
	var older := saved();older.set_value("graphics","preset","custom");older.set_value("graphics","shadows",0);older.erase_section_key("graphics","recommended");older.save(SETTINGS)
	app.start_graphics_probe()
	var again := Time.get_ticks_msec()
	while app.probing() and Time.get_ticks_msec()-again<40000:
		await process_frame
	expect(Quality.recommended(saved())>=Quality.LOW and Quality.read(saved()).shadows==0,"An existing preset gains a recommendation and keeps its settings")
	expect(not app.modal.visible,"Only the first choice opens the dialog")
	var back := saved();Quality.write(back,Quality.recommended(back));back.save(SETTINGS);app.apply_render_quality()

func lights(app, meta: String) -> Array:
	return app.title_dock.view.find_children("*","OmniLight3D",true,false).filter(func(light):return light.has_meta(meta))

func preset_row(app) -> Button:
	return app.settings_panel.find_child("Row_preset",true,false) as Button

func check_settings_rows(app) -> void:
	app.show_settings("graphics");await frames(3)
	var row := preset_row(app)
	expect(row!=null and row.get_node("Value").text==Quality.PRESETS[Quality.current(saved())]+" (Recommended)","The Graphics page names the measured preset as recommended")
	expect((app.settings_panel.scroll.get_child(0) as MarginContainer).get_theme_constant("margin_right")>0,"Rows keep clear of the scroll bar")
	expect(app.settings_panel.find_child("Row_lighting",true,false)==null and app.settings_panel.find_child("Row_detect_graphics",true,false)==null,"Lighting and measuring are presets, not rows")
	var list := row.get_node("List") as OptionButton
	expect(list.item_count==5 and list.selected==Quality.current(saved()),"The preset row opens a list with the current preset chosen")
	row.pressed.emit();await frames(2)
	expect(list.get_popup().visible,"Pressing the row opens its list")
	list.get_popup().hide();row.pressed.emit();await frames(2)
	expect(not list.get_popup().visible,"The press that closes a list does not reopen it")
	await create_timer(0.35).timeout
	# Step to Medium: dual-hemisphere station lamps, no sprite-lamp shadows.
	choose(preset_row(app),Quality.MEDIUM);await frames(2)
	expect(Quality.current(saved())==Quality.MEDIUM,"Choosing from the list sets the preset")
	await frames(30)
	var work := lights(app,"work_lamp")
	expect(not work.is_empty(),"The title's station has work lamps")
	if Quality.compatibility():
		expect(work.all(func(light):return light.omni_shadow_mode==OmniLight3D.SHADOW_CUBE and light.shadow_enabled!=light.get_meta("service_lamp")),"Medium on Compatibility shadows only the overhead work lamps")
	else:
		expect(work.all(func(light):return light.shadow_enabled and light.omni_shadow_mode==OmniLight3D.SHADOW_DUAL_PARABOLOID),"Medium uses the faster lamp shadows")
	expect(lights(app,"wanted_shadow").all(func(light):return not light.shadow_enabled),"Medium drops the small lamps' shadows")
	expect(app.get_viewport().msaa_3d==Viewport.MSAA_DISABLED,"Medium leaves multisampling off")
	choose(preset_row(app),Quality.HIGH);await frames(2)
	expect(Quality.current(saved())==Quality.HIGH,"Medium changes to High")
	await frames(4)
	expect(lights(app,"wanted_shadow").all(func(light):return light.shadow_enabled==light.get_meta("wanted_shadow")),"High keeps the small lamps' shadows")
	expect(app.get_viewport().msaa_3d==Viewport.MSAA_2X,"High multisamples twice")
	choose(app.settings_panel.find_child("Row_shadows",true,false),3);await frames(2)
	expect(Quality.current(saved())==Quality.CUSTOM and preset_row(app).get_node("Value").text=="Custom","A changed setting shows Custom")
	expect(lights(app,"work_lamp").all(func(light):return light.shadow_enabled and light.omni_shadow_mode==OmniLight3D.SHADOW_CUBE),"High shadow quality uses full lamp shadows")
	choose(app.settings_panel.find_child("Row_shadows",true,false),0);await frames(2)
	expect(lights(app,"work_lamp").all(func(light):return not light.shadow_enabled),"Shadow quality Off removes the lamp shadows")
	var slider := app.settings_panel.find_child("Slider_headlight_strength",true,false) as HSlider
	expect(slider!=null and slider.editable,"Headlight brightness has a slider")
	if slider!=null:
		slider.value=0.5;await frames(1)
		expect(is_equal_approx(Quality.headlight_strength(saved()),0.5),"The slider stores the headlight brightness")

func choose(row: Button, index: int) -> void:
	var list := row.get_node("List") as OptionButton
	list.select(index);list.item_selected.emit(index)

func check_display_rows(app) -> void:
	app.show_settings("display");await frames(3)
	var fps := app.settings_panel.find_child("Row_show_fps",true,false) as Button
	expect(fps!=null and not app.fps_counter.visible,"The FPS counter starts hidden")
	fps.pressed.emit();await frames(2)
	expect(app.fps_counter.visible and bool(saved().get_value("view","show_fps",false)),"Show FPS turns the counter on")
	await create_timer(0.7).timeout
	expect(app.fps_counter.label.text.ends_with("FPS"),"The counter shows frames per second")
	var resolution := app.settings_panel.find_child("Row_resolution",true,false) as Button
	expect(resolution!=null and resolution.get_node("Value").text=="Native","Resolution starts native")
	app.show_settings("graphics");await frames(3)
	choose(app.settings_panel.find_child("Row_render_scale",true,false),Quality.SCALES.find(50));await frames(2)
	expect(Quality.read(saved()).scale==50 and is_equal_approx(app.get_viewport().scaling_3d_scale,0.5),"3D resolution draws at the chosen share")
	var slider := app.settings_panel.find_child("Slider_headlight_strength",true,false) as HSlider
	expect(slider!=null and not slider.scrollable,"The mouse wheel does not move sliders")
	app.settings_panel.back();await frames(2)

func check_touch_scroll(app) -> void:
	var list: ScrollContainer=app.settings_panel.scroll
	list.scroll_vertical=0;await frames(2)
	var bar := list.get_v_scroll_bar()
	expect(bar.max_value>bar.page,"The Graphics page is taller than its frame")
	var target := preset_row(app)
	var before := saved().encode_to_text()
	var from: Vector2=root.get_final_transform()*target.get_global_rect().get_center()
	var press := InputEventScreenTouch.new();press.index=0;press.position=from;press.pressed=true
	Input.parse_input_event(press);await frames(1)
	var at := from
	for step in 12:
		var drag := InputEventScreenDrag.new();drag.index=0;drag.relative=Vector2(0,-20);at+=drag.relative;drag.position=at
		Input.parse_input_event(drag);await frames(1)
	var lift := InputEventScreenTouch.new();lift.index=0;lift.position=at;lift.pressed=false
	Input.parse_input_event(lift);await frames(3)
	expect(list.scroll_vertical>100,"A drag that starts on a row scrolls the title's settings (%d)"%list.scroll_vertical)
	expect(saved().encode_to_text()==before and not target.get_node("List").get_popup().visible,"The row the drag started on is not pressed")
	# A tap still presses, once the fling has stopped.
	app.touch_scroll.velocity=0.0;list.scroll_vertical=0;await frames(3)
	var tap_at: Vector2=root.get_final_transform()*preset_row(app).get_global_rect().get_center()
	var tap := InputEventScreenTouch.new();tap.index=0;tap.position=tap_at;tap.pressed=true
	Input.parse_input_event(tap);await frames(1)
	tap=tap.duplicate();tap.pressed=false
	Input.parse_input_event(tap);await frames(3)
	var popup: PopupMenu=preset_row(app).get_node("List").get_popup()
	expect(popup.visible,"A tap on a row still opens it")
	popup.hide();await frames(1)
	app.settings_panel.back();await frames(2)

func check_manual_choice(app) -> void:
	DirAccess.remove_absolute(SETTINGS)
	expect(not Quality.has_preset(saved()),"Without a preset the next start measures")
	app.show_settings("graphics");await frames(3)
	app.settings_panel.put("view","msaa",0)
	expect(Quality.has_preset(saved()),"A graphics choice made by hand is kept")
	app.settings_panel.back();await frames(2)
	var older := ConfigFile.new();older.set_value("graphics","modern",false);older.save(SETTINGS)
	app.wants_graphics_probe()
	expect(Quality.current(saved())==Quality.CLASSIC and Quality.has_preset(saved()),"Classic lighting from an earlier version stays Classic")
