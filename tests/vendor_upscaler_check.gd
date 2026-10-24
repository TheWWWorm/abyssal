extends SceneTree
## AMD FSR 3.1 and FSR 4 on the title's 3D view, through the settings
## screen, then frame generation in a dive. Needs the Windows engine build
## with the FidelityFX integration, on Direct3D 12 as renderer.cfg starts it
## (renderer_choice.gd), with a window: where no
## vendor upscaler runs it exits 2 (blocked), never passing. Each mode must
## report real evaluations from AMD's runtime.
const Quality=preload("res://native/presentation/graphics_quality.gd")
const Amd=preload("res://native/presentation/amd.gd")
const SETTINGS := "user://vendor-upscaler-check/settings.cfg"
const SAVE := "user://vendor-upscaler-check/campaign.json"
const FRAMES := 120
var failures := 0
var rows: Array=[]

func expect(ok: bool, why: String) -> void:
	if not ok:failures+=1;push_error(why)
func _initialize() -> void:call_deferred("run")

func frames(count: int) -> void:
	for i in count:await process_frame

func choose(row: Button, index: int) -> void:
	var list := row.get_node("List") as OptionButton
	list.select(index);list.item_selected.emit(index)

func evaluations(upscaler: String) -> int:
	"""Upscaled frames AMD's runtime counted."""
	return int(Amd.status().get("upscale_evaluations",0))

func runtime_errors() -> bool:
	return not str(Amd.status().get("last_error","")) in ["","0"]

func sample(app, label: String, upscaler: String) -> void:
	# The captures show the 3D view, not the settings over it.
	app.settings_panel.visible=false
	await frames(30)
	var before := evaluations(upscaler)
	var started := Time.get_ticks_usec()
	for i in FRAMES:await RenderingServer.frame_post_draw
	var counted := evaluations(upscaler)-before
	var viewport: Viewport=app.get_viewport()
	var image := viewport.get_texture().get_image()
	expect(image!=null and image.get_size()==root.size,label+": the whole picture is drawn")
	if image!=null:image.save_png("user://vendor-upscaler-check/"+label+".png")
	var vendor: bool=Quality.single_sampled(upscaler)
	expect(counted>=FRAMES-10 if vendor else counted==0,label+": evaluations %d"%counted)
	expect((int(viewport.scaling_3d_mode)==Amd.mode())==vendor,label+": scaling mode")
	if vendor:expect(viewport.msaa_3d==Viewport.MSAA_DISABLED and not viewport.use_taa,label+": the upscaler replaces multisampling and TAA")
	expect(not bool(viewport.get("frame_generation")),label+": the title never generates frames")
	expect(not runtime_errors(),label+": no error from AMD's runtime")
	app.settings_panel.visible=true;await frames(2)
	rows.append({"label":label,"evaluations":counted,"frames":FRAMES,"scale":viewport.scaling_3d_scale,"milliseconds":(Time.get_ticks_usec()-started)/1000.0})

func generated() -> int:
	return int(Amd.status().get("generated_frames",0))

func run() -> void:
	preload("decline_reconstruction.gd").attach(self)
	root.size=Vector2i(1280,720)
	var vendors: Array=Quality.upscalers().filter(Quality.single_sampled)
	if vendors.is_empty():
		print("VENDOR_UPSCALER_CHECK BLOCKED ",JSON.stringify({"driver":RenderingServer.get_current_rendering_driver_name(),"gpu":RenderingServer.get_video_adapter_name(),"amd":Amd.status()}))
		quit(2);return
	DirAccess.make_dir_recursive_absolute(SETTINGS.get_base_dir())
	DirAccess.remove_absolute(SETTINGS);DirAccess.remove_absolute(SAVE)
	var config := ConfigFile.new()
	# Development runs: windowed, FPS shown, silent, measured preset fixed.
	for setting in [["view","show_fps",true],["audio","music",0.0],["audio","effects",0.0],["graphics","preset","high"],["graphics","detection",Quality.DETECTION_VERSION],["graphics","recommended",Quality.HIGH],["view","msaa",2]]:
		config.set_value(setting[0],setting[1],setting[2])
	config.save(SETTINGS)
	var app=load("res://scenes/native_main.tscn").instantiate()
	app.save_path=SAVE;app.settings_path=SETTINGS
	root.add_child(app)
	if not app.ready_for_preview and not app.content_starting:await app.open_cache(OS.get_cmdline_user_args()[-1])
	while app.content_starting:await process_frame
	await frames(10)
	app.show_settings("graphics");await frames(3)
	expect(app.settings_panel.find_child("Row_frame_generation",true,false)!=null,"Frame generation is listed with a vendor upscaler")
	await sample(app,"fsr1",'fsr')
	for upscaler in vendors:
		choose(app.settings_panel.find_child("Row_upscaler",true,false),Quality.upscalers().find(upscaler));await frames(2)
		var saved := ConfigFile.new();saved.load(SETTINGS)
		expect(str(saved.get_value("view","upscaler",""))==upscaler,upscaler+": the choice is saved")
		var generation=app.settings_panel.find_child("Row_frame_generation",true,false)
		expect(generation!=null and generation.disabled==not Quality.generates_frames(upscaler),upscaler+": frame generation is available exactly where the GPU supports it")
		for step in [[100,"native"],[67,"quality"],[58,"balanced"],[50,"performance"],[33,"below-half"]]:
			choose(app.settings_panel.find_child("Row_render_scale",true,false),Quality.SCALES.find(step[0]));await frames(2)
			expect(app.settings_panel.find_child("Row_msaa",true,false).disabled,upscaler+" "+step[1]+": multisampling is greyed out")
			await sample(app,upscaler+"-"+step[1],upscaler)
			expect(app.get_viewport().scaling_3d_scale>=0.5,upscaler+" "+step[1]+": the upscaler keeps a share it accepts")
	choose(app.settings_panel.find_child("Row_upscaler",true,false),Quality.upscalers().find("fsr"));await frames(2)
	await sample(app,"fsr1-restored","fsr")
	# Frame generation runs only in flight, with the first upscaler that has it.
	var generating: Array=vendors.filter(Quality.generates_frames)
	var flight := {}
	if not generating.is_empty():
		var upscaler: String=generating[0]
		choose(app.settings_panel.find_child("Row_upscaler",true,false),Quality.upscalers().find(upscaler));await frames(2)
		choose(app.settings_panel.find_child("Row_render_scale",true,false),Quality.SCALES.find(67));await frames(2)
		app.settings_panel.find_child("Row_frame_generation",true,false).pressed.emit();await frames(2)
		var saved := ConfigFile.new();saved.load(SETTINGS)
		expect(bool(saved.get_value("view","frame_generation",false)),"Frame generation is switched on")
		app.settings_panel.back();app.settings_panel.back();await frames(2)
		app.launch_game(false,"Pilot");await frames(30)
		var game=current_scene
		if game!=null and game.has_method("close_page"):game.close_page()
		# Frame generation stops while another window has focus.
		root.move_to_foreground();root.grab_focus()
		await frames(60)
		var before := generated()
		for i in FRAMES:await RenderingServer.frame_post_draw
		var made: int=generated()-before
		flight={"upscaler":upscaler,"generated":made,"viewport":bool(game.get_viewport().get("frame_generation")) if game!=null else false,"page":str(game.page) if game!=null else "","focus":root.has_focus()}
		var image := root.get_texture().get_image()
		if image!=null:image.save_png("user://vendor-upscaler-check/flight-"+upscaler+".png")
		expect(made>=FRAMES/2,"%s: frames are generated in flight (%d)"%[upscaler,made])
		expect(not runtime_errors(),"Flight: no error from AMD's runtime")
	var result := {"failures":failures,"driver":RenderingServer.get_current_rendering_driver_name(),"gpu":RenderingServer.get_video_adapter_name(),"vendors":vendors,"generating":generating,"flight":flight,"amd":Amd.status(),"rows":rows}
	FileAccess.open("user://vendor-upscaler-check/result.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t")+"\n")
	print("VENDOR_UPSCALER_CHECK ","OK " if failures==0 else "FAILED %d "%failures,JSON.stringify(result))
	quit(1 if failures>0 else 0)
