extends SceneTree
## Preview viewports follow live edge-AA choices without inheriting the
## main scene's reduced resolution. No imported assets are needed.
const Ship = preload("res://native/presentation/ship_preview.gd")
const Station = preload("res://native/presentation/station_preview.gd")
const Quality = preload("res://native/presentation/graphics_quality.gd")
var failures := 0
var previews: Array = []

func _initialize() -> void:run.call_deferred()
func expect(ok: bool, message: String) -> void:
	if not ok:failures+=1;push_error(message)
func frames() -> void:
	for i in 3:await process_frame

func check(msaa: int, taa: bool, label: String) -> void:
	for preview in previews:
		var viewport: SubViewport=preview.viewport
		expect(viewport.msaa_3d==msaa,label+": "+preview.name+" inherits multisampling")
		expect(viewport.use_taa==taa,label+": "+preview.name+" follows temporal antialiasing")
		expect(viewport.scaling_3d_scale==1.0 and viewport.scaling_3d_mode==Viewport.SCALING_3D_MODE_BILINEAR,label+": "+preview.name+" keeps its native resolution")

func run() -> void:
	if DisplayServer.get_name()=="headless":
		print("PREVIEW_ANTIALIASING skipped: render with a GPU to check preview viewports");quit();return
	root.size=Vector2i(800,480)
	var forward := RenderingServer.get_current_rendering_method()=="forward_plus"
	var config := ConfigFile.new();config.set_value("view","msaa",3);config.set_value("view","temporal_aa",true);config.set_value("view","render_scale",50)
	Quality.apply_viewport(root,Quality.read(config),root.size)
	var ship := Ship.new();root.add_child(ship);ship.configure({"registry":[],"root":""},0,true);ship.size=Vector2(360,320)
	var station := Station.new();root.add_child(station);station.position.x=400;station.stage();station.size=Vector2(360,320)
	station.turntable.add_child(station.mount)
	previews=[ship,station];await frames()
	check(Viewport.MSAA_8X,forward,"Initial choice")
	config.set_value("view","msaa",0);config.set_value("view","temporal_aa",false)
	Quality.apply_viewport(root,Quality.read(config),root.size);await frames()
	check(Viewport.MSAA_DISABLED,false,"AA switched off while previews are open")
	if forward:
		config.set_value("view","upscaler","fsr2")
		Quality.apply_viewport(root,Quality.read(config),root.size);await frames()
		expect(not root.use_taa,"FSR 2 handles the main view's temporal antialiasing")
		check(Viewport.MSAA_DISABLED,true,"Temporal upscaling selected")
	config.set_value("view","upscaler","bilinear");config.set_value("view","msaa",2)
	Quality.apply_viewport(root,Quality.read(config),root.size);await frames()
	check(Viewport.MSAA_4X,false,"Return to spatial AA")
	# Hidden cards refresh when shown again, without rebuilding their models.
	ship.hide();station.hide();config.set_value("view","msaa",3);config.set_value("view","temporal_aa",true)
	Quality.apply_viewport(root,Quality.read(config),root.size);await frames();ship.show();station.show();await frames()
	check(Viewport.MSAA_8X,forward,"Reopened previews")
	for preview in previews:preview.queue_free()
	await frames()
	print("PREVIEW_ANTIALIASING ",failures," failures");quit(1 if failures else 0)
