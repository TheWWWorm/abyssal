extends Node
## Samples public gameplay state and feeds the desktop-only local IPC helper.
## The helper exits when its pipe closes, including after an engine crash.
const SETTINGS := "user://native/settings.cfg"
const DEFAULT_APPLICATION_ID := "1561821965210222642"
var helper := {}
var previous := ""
var elapsed := 0.0
var restart_after := 0
var started_at := 0

static func supported() -> bool:
	return not OS.has_feature("web") and (OS.has_feature("windows") or OS.has_feature("linux") or OS.has_feature("macos")) and not OS.has_feature("android")

static func application_id() -> String:
	var override := OS.get_environment("ABYSSAL_DISCORD_APPLICATION_ID").strip_edges()
	return override if not override.is_empty() else str(ProjectSettings.get_setting("discord/application_id",DEFAULT_APPLICATION_ID))

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	started_at=int(Time.get_unix_time_from_system())
	# Test runners and server processes never publish activity.
	set_process(supported() and DisplayServer.get_name()!="headless")

func _process(delta: float) -> void:
	elapsed+=delta
	if elapsed<1.0:return
	elapsed=0.0
	var config := ConfigFile.new();config.load(SETTINGS)
	if not bool(config.get_value("discord","enabled",true)):
		stop();restart_after=0;return
	if not helper.is_empty() and not OS.is_process_running(int(helper.pid)):stop()
	if helper.is_empty():
		if Time.get_ticks_msec()<restart_after:return
		restart_after=Time.get_ticks_msec()+30000
		start()
	if helper.is_empty():return
	var scene := get_tree().current_scene
	var context: Dictionary=scene.discord_context() if is_instance_valid(scene) and scene.has_method("discord_context") else {}
	var activity := activity_for(context,started_at)
	var serialized := JSON.stringify(activity)
	if serialized==previous:return
	helper.stdio.store_string(serialized+"\n")
	if helper.stdio.get_error()!=OK:stop();return
	previous=serialized

func start() -> void:
	var client_id := application_id()
	if not RegEx.create_from_string("^[0-9]{17,20}$").search(client_id):return
	var folder := OS.get_executable_path().get_base_dir()
	var importer := folder.path_join("../Resources/importer").simplify_path() if OS.has_feature("macos") else folder.path_join("importer")
	var platform := "macos-arm64" if OS.has_feature("macos") else "windows" if OS.has_feature("windows") else "linux-arm64" if OS.has_feature("arm64") else "linux"
	var executable := importer.path_join("bin/"+platform+"/"+("node.exe" if OS.has_feature("windows") else "node"))
	var script := importer.path_join("discord_presence.js")
	if not FileAccess.file_exists(executable) or not FileAccess.file_exists(script):
		# Running directly from source uses the developer's Node installation.
		if not OS.has_feature("editor"):return
		script=ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir().path_join("desktop/discord_presence.js")
		executable=OS.get_environment("ABYSSAL_NODE_PATH")
		if executable.is_empty():executable="node"
		if not FileAccess.file_exists(script):return
	helper=OS.execute_with_pipe(executable,PackedStringArray([script,client_id,str(OS.get_process_id())]),false)
	previous=""

func stop() -> void:
	for key in ["stdio","stderr"]:
		if helper.has(key):helper[key].close()
	helper={};previous=""

func _exit_tree() -> void:
	stop()

static func activity_for(context: Dictionary, start_time: int) -> Dictionary:
	var activity := {"type":0,"details":"In the main menu","timestamps":{"start":start_time},"assets":{"large_image":"abyssal","large_text":"Abyssal · DEEP"}}
	if context.is_empty():return activity
	var page := str(context.get("page",""))
	var details := "Exploring the ocean"
	match page:
		"pause","freeze","layout":details="Paused"
		"settings":details="Adjusting settings"
		"map","destinations","stream":details="Charting a course"
		"journal","station_missions":details="Reviewing missions"
		"market":
			details={"ships":"Choosing a ship","equipment":"Outfitting the submarine","manufacture":"At the workshop","missions":"Choosing a contract"}.get(str(context.get("market","")),"Trading at a station")
		"hangar":details="At the hangar"
		"dialogue","opening":details="Following the story"
		"failure":details="Expedition interrupted"
		"departure":details="Leaving the station"
		_:
			if bool(context.get("docked",false)):details="Docked at a station"
			elif not page.is_empty():details="In the ship's menus"
			elif bool(context.get("transit",false)):details="Travelling through S.T.R.E.A.M."
			elif bool(context.get("fishing",false)):details="Fishing in the deep"
			elif bool(context.get("combat",false)):details="In combat"
			elif bool(context.get("autopilot",false)):details="Cruising on autopilot"
	activity.details=details
	var ship := str(context.get("ship","")).replace("\n"," ").replace("\r"," ").strip_edges()
	# Discord's text fields allow 128 bytes; retain valid UTF-8 for every JAR.
	while ("Piloting "+ship).to_utf8_buffer().size()>128:ship=ship.left(ship.length()-1)
	if not ship.is_empty():activity["state"]="Piloting "+ship
	return activity
