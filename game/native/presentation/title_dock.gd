extends Node3D
## The menu's backdrop. The phone game keeps its menu over the station the
## expedition is at, the camera circling it once a minute (bk with ck's first
## path), and its one track playing (l). Here that is the same water, station
## and music the dive uses, built from the player's checkpoint or the first
## station of a new expedition, and a plain dark field until content exists.
const World = preload("res://native/simulation/world.gd")
const View = preload("res://native/presentation/world_view.gd")
const Abyss = preload("res://native/presentation/abyss.gd")
const Terrain = preload("res://native/presentation/terrain.gd")
const DiveAudio = preload("res://native/presentation/dive_audio.gd")
const Session = preload("res://native/simulation/session.gd")
const SaveStore = preload("res://native/simulation/save_store.gd")
var camera := Camera3D.new()
var abyss := Abyss.new()
var view := View.new()
var terrain := Terrain.new()
var world := World.new()
var dive_audio := DiveAudio.new()
var environment: WorldEnvironment
var dock_environment: Environment
var sky_environment: Environment
var built := false
var wanted_volumetric := true
var wanted_detail := true
var elapsed_fraction := 0.0

func _ready() -> void:
	dock_environment=Environment.new()
	dock_environment.background_mode=Environment.BG_COLOR
	dock_environment.background_color=Color("030a10")
	add_child(camera);camera.current=true;camera.fov=65;camera.near=0.5;camera.far=View.DRAW_DISTANCE
	# The art direction reads the expedition once there is one (load_content).
	abyss.camera=camera;abyss.view=view;add_child(abyss)
	# Before a JAR is imported there is no submarine or station to mount these
	# on. The Abyss rig otherwise draws its two default headlight cones alone
	# against the empty title background.
	abyss.set_headlights(false);abyss.set_headlight_beams(false)
	environment=abyss.environment;sky_environment=abyss.environment.environment
	# No station yet: the sky shader has nothing to sit behind, so hold the field.
	abyss.environment.environment=dock_environment
	add_child(view);view.menu_backdrop=true
	terrain.world=world;terrain.camera=camera;add_child(terrain)
	dive_audio.world=world;add_child(dive_audio)

func load_content(content, save_path: String, settings_path: String) -> void:
	"""Stand the menu in front of the station of the player's checkpoint, or
	of the first station when there is none to return to."""
	var session=null
	var store := SaveStore.new()
	if FileAccess.file_exists(save_path):session=store.read(save_path,content.data)
	if session==null:
		session=Session.new();session.new_game(content.data,"Diver",int(Time.get_unix_time_from_system()))
		session.prepare_station(session.station_id)
	session.docked=true
	var config := ConfigFile.new();config.load(settings_path)
	var spacing:=preload("res://native/simulation/world_spacing.gd").new();spacing.read_config(config)
	world.spacing_meters=spacing.meters()
	view.modern_graphics=bool(config.get_value("graphics","modern",config.get_value("graphics","materials",true)))
	view.set_station_smoothing(bool(config.get_value("graphics","station_smoothing",false)))
	world.configure(session);world.build_docked_view();abyss.world=world
	view.configure(world,content,camera);view.revision=-1
	abyss.import_sky_ramp(content.root)
	abyss.set_headlights(false);abyss.set_headlight_beams(false)
	wanted_volumetric=bool(config.get_value("graphics","volumetric",true)) and RenderingServer.get_current_rendering_method()=="forward_plus"
	wanted_detail=bool(config.get_value("graphics","detail",true))
	apply_lighting()
	dive_audio.configure(world,content.root)
	dive_audio.music_gain=clampf(float(config.get_value("audio","music",0.65)),0,1)
	dive_audio.effects_gain=clampf(float(config.get_value("audio","effects",0.75)),0,1)
	dive_audio.set_enabled(bool(config.get_value("graphics","audio",true)))
	dive_audio.set_context("",true)
	dock_environment=sky_environment
	if is_processing():abyss.environment.environment=sky_environment
	built=true

func set_active(value: bool) -> void:
	"""The content inspector and the backdrop share the viewport; one of them
	owns the environment and the camera at a time."""
	visible=value
	process_mode=Node.PROCESS_MODE_INHERIT if value else Node.PROCESS_MODE_DISABLED
	abyss.environment.environment=dock_environment if value else null
	if value:camera.current=true

func set_lighting(modern: bool) -> void:
	"""The menu shows the lighting the dive will use; a change in Options
	rebuilds the station in it at once."""
	if not built or view.modern_graphics==modern:return
	view.modern_graphics=modern;view.revision=-1
	apply_lighting()

func apply_lighting() -> void:
	var env := sky_environment
	env.volumetric_fog_enabled=view.modern_graphics and wanted_volumetric
	env.ssao_enabled=view.modern_graphics and wanted_detail
	env.glow_enabled=view.modern_graphics

func set_music(value: float) -> void:
	dive_audio.music_gain=value;dive_audio.apply_levels()

func set_audio_enabled(value: bool) -> void:
	dive_audio.set_enabled(value)

func _process(delta: float) -> void:
	if not built or world.region==null:return
	# The station's own clocks: the hangar doors, the rotor and the caps run
	# as they do in the dive; nothing else here is simulated.
	elapsed_fraction+=delta*1000.0
	var milliseconds := int(elapsed_fraction);elapsed_fraction-=milliseconds
	world.region.elapsed_ms+=milliseconds

func _exit_tree() -> void:
	# The region's actors, weapons and hooks refer to one another; cut those
	# ties as the dive does on the way out, or the menu's copy is never freed.
	world.dispose()
