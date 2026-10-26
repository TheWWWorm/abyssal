extends SceneTree
## Waiting combat actors are already in the water: AI activation must not
## reveal their hulls. Exercise the actual mission factory and world view.
const Session=preload("res://native/simulation/session.gd")
const World=preload("res://native/simulation/world.gd")
const Mission=preload("res://native/simulation/mission.gd")
const Special=preload("res://native/simulation/special_actor.gd")
const View=preload("res://native/presentation/world_view.gd")
const Math=preload("res://native/simulation/fixed_math.gd")
var checks:=0
var failures:=0
var world
var view
var abyss
var camera: Camera3D
var output: String
var trace: Array=[]

func expect(ok: bool,why: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(why)
func _initialize() -> void:call_deferred("run")
func settle(frames: int=4) -> void:
	for frame in frames:
		view._process(.04)
		if abyss!=null:abyss._process(.04)
		await process_frame
	while view.rebuilding:await process_frame
	view._process(0.0)
func visual(actor):return view.objects[actor.get_instance_id()].visual
func lamps(actor) -> Array:return view.objects[actor.get_instance_id()].lamps
func record(freighter,metres: int) -> void:
	trace.append({"metres":metres,"state":freighter.state,"combat_enabled":freighter.health.enabled,"hull":freighter.health.hull,"visible":visual(freighter).visible,"camera_distance":camera.global_position.distance_to(visual(freighter).global_position)})
	if output.is_empty() or DisplayServer.get_name()=="headless":return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("intercept-%04dm.png"%metres))
func run() -> void:
	var args:=OS.get_cmdline_user_args()
	var content=preload("res://native/content.gd").new()
	if args.is_empty() or not content.load_cache(args[0]):push_error("Pass a compatible imported content directory");quit(1);return
	output=args[1] if args.size()>1 else ""
	if not output.is_empty():DirAccess.make_dir_recursive_absolute(output)
	root.size=Vector2i(1280,720);root.msaa_3d=Viewport.MSAA_4X
	var session:=Session.new();session.new_game(content.data,"Intercept visibility",91)
	while session.campaign.chapter<9:session.campaign.next_chapter(session.counters)
	session.campaign.primary.kind=-1
	var mission:=Mission.new();mission.kind=5;mission.destination=113;mission.difficulty=2
	session.campaign.secondary=mission
	world=World.new();world.configure(session);world.depart();world.enter_region(113)
	var region=world.region
	var convoy: Array=region.enemies.filter(func(actor):return actor is Special and actor.kind=="freighter")
	expect(convoy.size() in [2,3],"Interception constructs its full convoy when the mission region is entered")
	var freighter=convoy[0]
	expect(convoy.all(func(actor):return actor.state==5 and not actor.health.enabled),"Convoy waits with combat disabled before proximity activation")
	var guard=region.enemies.filter(func(actor):return not actor is Special)[0]
	region.player.set_throttle(0)
	camera=Camera3D.new();camera.current=true;camera.far=10000;root.add_child(camera)
	view=View.new();root.add_child(view);view.set_process(false);view.configure(world,content,camera)
	view.depth_limits=false
	if DisplayServer.get_name()!="headless":
		abyss=preload("res://native/presentation/abyss.gd").new();abyss.camera=camera;abyss.world=world;abyss.view=view;root.add_child(abyss)
		abyss.set_process(false);abyss.import_sky_ramp(content.root)
	# A broadside approach keeps the large hull readable while the normal
	# chase camera and production water/materials remain in use.
	for metres in [1000,600,501,499,300]:
		region.player.pose.origin=Math.added(freighter.pose.origin,[metres*100,0,0]);region.player.pose.face([-4096,0,0]);world.previous_render_poses.clear()
		freighter.advance(40)
		await settle(20 if metres==1000 else 4)
		expect(visual(freighter).visible,"The freighter hull is visible at %d metres, independently of combat wake"%metres)
		expect(freighter.state==(5 if metres>=500 else 1),"Rendering preserves the original 500 m freighter activation threshold")
		expect(freighter.health.enabled==(metres<500),"Rendering does not enable damage or targeting early")
		await record(freighter,metres)
		if metres==600:
			expect(visual(freighter).headlights_powered and lamps(freighter).size()==visual(freighter).headlight_rig().size(),"A waiting freighter keeps its powered hull presentation and any authored lamp mounts")
			expect(visual(guard).visible and guard.state==5 and not guard.health.enabled,"A pre-existing dormant escort is visible without activating its AI")
			expect(lamps(guard).size()==visual(guard).headlight_rig().size() and lamps(guard).all(func(lamp):return lamp.visible),"A dormant guard's authored headlights are initialized before combat wakes it")
			if abyss!=null:await check_pixels(freighter)
	# An explosion retains this hull only through its chain of bursts.
	freighter.health.hull=0;freighter.advance(40);await settle()
	expect(freighter.state==3 and visual(freighter).visible,"A freighter remains visible during its destruction sequence")
	expect(not visual(freighter).headlights_powered and lamps(freighter).all(func(lamp):return not lamp.visible),"A destroyed freighter has no powered lamps")
	freighter.advance(freighter.explosion_duration+1);freighter.advance(40);await settle()
	expect(freighter.state==4 and not visual(freighter).visible,"A fully destroyed freighter remains absent")
	# Disabled active ships and the zero-hull finale placeholder are deliberate
	# removals, unlike a live vessel waiting in dormant state 5.
	guard.state=1;guard.health.enabled=false;await settle()
	expect(not visual(guard).visible,"Scripted removal of an active ship remains hidden")
	guard.state=5;guard.health.hull=0;await settle()
	expect(not visual(guard).visible,"A dormant zero-hull placeholder stays hidden")
	guard.model_id=17;guard.state=4;guard.health.enabled=true;guard.capturable=true;await settle()
	expect(visual(guard).visible,"An uncollected salvage wreck remains visible")
	guard.capturable=false;guard.health.enabled=false;await settle()
	expect(not visual(guard).visible,"A collected wreck remains hidden")
	if not output.is_empty():FileAccess.open(output.path_join("trace.json"),FileAccess.WRITE).store_string(JSON.stringify(trace,"\t"))
	view.queue_free();camera.queue_free()
	if abyss!=null:abyss.queue_free()
	world.dispose();await process_frame;await process_frame
	print("ACTOR_VISIBILITY ",checks," checks; ",failures," failures");quit(1 if failures else 0)

func check_pixels(actor) -> void:
	# Freeze presentation clocks, then compare the rendered water with/without
	# the actual dormant mesh. A visible flag alone cannot catch GPU culling.
	await RenderingServer.frame_post_draw
	var shown:=root.get_texture().get_image()
	visual(actor).visible=false
	for frame in 3:await process_frame
	await RenderingServer.frame_post_draw
	var hidden:=root.get_texture().get_image()
	visual(actor).visible=true
	var changed:=0
	for y in shown.get_height():
		for x in shown.get_width():
			var a:=shown.get_pixel(x,y);var b:=hidden.get_pixel(x,y)
			if absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b)>.02:changed+=1
	expect(changed>30,"The dormant freighter contributes visible pixels at 600 m through production water (changed %d)"%changed)
	await settle()
