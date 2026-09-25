extends SubViewportContainer
## The chart card's showroom: the selected station built from the same modules
## and layout the dive uses, turning slowly in its own world.
const Body = preload("res://native/simulation/station_body.gd")
const Model = preload("res://native/presentation/model.gd")
const Pose = preload("res://native/simulation/ship_transform.gd")
var viewport := SubViewport.new()
var camera := Camera3D.new()
var turntable := Node3D.new()
var modules: Array = []
## Half the height, and the radius the turntable sweeps, of what is drawn.
var half_height := 30.0
var sweep := 60.0
## Elevation of the camera above the station's middle.
const TILT := 0.4
var elapsed := 0.0
var mount := Node3D.new()
var fitted := false
var pending: Array = []

func configure(view, world, id: int) -> void:
	name="StationPreview";stretch=true;mouse_filter=Control.MOUSE_FILTER_IGNORE
	custom_minimum_size=Vector2(150,90);size_flags_horizontal=Control.SIZE_EXPAND_FILL;size_flags_vertical=Control.SIZE_EXPAND_FILL
	viewport.own_world_3d=true;viewport.size=Vector2i(640,400)
	viewport.render_target_update_mode=SubViewport.UPDATE_WHEN_VISIBLE;add_child(viewport)
	var environment:=WorldEnvironment.new();var env:=Environment.new();environment.environment=env;viewport.add_child(environment)
	env.background_mode=Environment.BG_SKY
	var sky:=Sky.new();var water:=ShaderMaterial.new();water.shader=load("res://native/presentation/abyss_sky.gdshader");sky.sky_material=water;env.sky=sky
	preload("res://native/presentation/showroom_light.gd").apply(viewport,env)
	viewport.add_child(camera);camera.current=true;camera.fov=38;camera.far=20000
	viewport.add_child(turntable)
	# A headless run has no renderer to show it, and the dummy one reports
	# the sky's material as missing.
	if DisplayServer.get_name()=="headless":return
	if world==null or world.region==null or id<0 or id>=world.session.stations.size():return
	# Built on the first frame it is shown rather than now: stepping through a
	# list replaces the card several times in one frame, and a station freed
	# in the frame its modules were made leaves the renderer holding
	# instances whose materials are already gone.
	pending=[view,world,id]
	self_modulate.a=0

func build(view, world, id: int) -> void:
	var station: Dictionary=world.session.stations[id]
	var body:=Body.new();body.configure(station,world.session.is_colonist_station(id),world.region.sine,world.session.data.get("station_geometry",{}))
	turntable.add_child(mount)
	for part in body.parts:
		# The dive's own model factory, so the modules share its decoded
		# meshes, textures and compiled shaders and a new selection costs a
		# frame rather than a stall.
		var visual=view.model(int(part.model_id),part.frame_ms,mount)
		if visual==null:continue
		var pose:=Pose.new();pose.math.sine_table=world.region.sine;pose.origin=part.origin;pose.set_euler(0,part.yaw,0)
		visual.transform=Model.station_transform(pose.godot_transform())
		visual.configure_station(part)
		modules.append(visual)
	_process(0)
	# As the ship showroom: keep the picture clear until the viewport has
	# rendered into it once.
	self_modulate.a=0
	RenderingServer.frame_post_draw.connect(reveal,CONNECT_ONE_SHOT)

func reveal() -> void:
	if is_inside_tree():self_modulate.a=1

func _process(delta: float) -> void:
	if not is_visible_in_tree():return
	if not pending.is_empty():
		var args:=pending;pending=[];build(args[0],args[1],args[2]);return
	elapsed+=delta
	for visual in modules:visual.advance(roundi(delta*1000))
	if not fitted and not modules.is_empty():fit()
	turntable.rotation.y=elapsed*.22
	camera.position=Vector3(0,sin(TILT),cos(TILT))*distance();camera.look_at(Vector3.ZERO)

func distance() -> float:
	"""How far back the camera stands so every station fills the card about
	as much as any other. A compact station is framed by its height; a long
	one by the circle it sweeps as it turns, but let run past the edges a
	little when it is broadside, or it would sit small in the middle for the
	rest of the turn."""
	var aspect: float=maxf(size.x,1.0)/maxf(size.y,1.0)
	var vertical: float=tan(deg_to_rad(camera.fov)*.5)
	var horizontal: float=vertical*aspect
	# The sweep seen from above rises and falls with the turn; only part of
	# it is allowed for, for the same reason as the width.
	var tall: float=(half_height*cos(TILT)+sweep*sin(TILT)*.6)/vertical
	var wide: float=sweep*.75/horizontal
	return maxf(tall,wide)+sweep*.35

func fit() -> void:
	"""Frames what is actually drawn. The modules' own boxes leave out parts of
	some meshes, which put the larger stations off centre and over the edge."""
	var bounds:=AABB();var first:=true
	var into_mount:=mount.global_transform.affine_inverse()
	for node in mount.find_children("*","GeometryInstance3D",true,false):
		# The lamp sprites hang well clear of the hull and would pull the
		# framing off the station.
		if not node.visible or node is MultiMeshInstance3D or str(mount.get_path_to(node)).contains("Lamp"):continue
		var box: AABB=into_mount*node.global_transform*node.get_aabb()
		if box.size==Vector3.ZERO:continue
		bounds=box if first else bounds.merge(box);first=false
	if first:return
	fitted=true
	mount.position=-bounds.get_center()
	half_height=bounds.size.y*.5
	sweep=maxf(8,Vector2(bounds.size.x,bounds.size.z).length()*.5)
