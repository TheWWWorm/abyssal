extends Node
## Windows: the renderer the next start uses. Vulkan is the default;
## Direct3D 12 also loads AMD's FidelityFX runtime in the engine build that
## carries it (engine/godot-4.7/amd-fsr.patch), for FSR 3.1, FSR 4 and frame
## generation. Godot picks the driver before any script runs, so the choice
## is a settings override (project.godot's
## application/config/project_settings_override.windows names OVERRIDE)
## read at the next start. Whatever branches on the renderer reads the
## running one, never this choice.
##
## Crash safety: the first start on Direct3D 12 is a trial. Once it runs,
## OVERRIDE is removed, so a crash in that run leaves the next start on
## Vulkan; after TRIAL_SECONDS or a clean quit the choice is written again.
## A start that finds a trial still running (that run ended unexpectedly) or
## another driver than Direct3D 12 (it could not start) goes back to Vulkan,
## and the title says so (`notice`).

const Amd = preload("res://native/presentation/amd.gd")

const OVERRIDE := "user://renderer.cfg"
const TRIAL := "user://renderer-trial.cfg"
const TRIAL_SECONDS := 60.0
const CHOICES := ["vulkan","d3d12"]
## The notice for the title: "crashed" (a trial run ended unexpectedly),
## "failed" (Direct3D 12 did not start) or "" for none.
static var notice := ""

static func available() -> bool:
	"""Offered on Windows by the engine build with AMD's FidelityFX
	integration (and in checks that ask for it)."""
	return (OS.has_feature("windows") or OS.get_cmdline_user_args().has("--renderer-option")) and Amd.mode()>=0

static func names() -> Array:
	return ["Vulkan","Direct3D 12 · AMD FSR"]

static func running() -> String:
	return RenderingServer.get_current_rendering_driver_name()

static func chosen() -> String:
	"""The renderer for the next start; a trial counts as chosen."""
	return "d3d12" if FileAccess.file_exists(OVERRIDE) or FileAccess.file_exists(TRIAL) else "vulkan"

static func choose(choice: String) -> void:
	if choice==chosen(): return
	if choice=="d3d12":
		write_override()
		var trial := ConfigFile.new();trial.set_value("trial","state","pending");trial.save(TRIAL)
	else: reset()

static func startup() -> bool:
	"""This start's step in a trial; true while it runs on Direct3D 12."""
	if not FileAccess.file_exists(TRIAL): return false
	var trial := ConfigFile.new();trial.load(TRIAL)
	if str(trial.get_value("trial","state",""))=="running":
		reset();notice="crashed";return false
	if running()!="d3d12":
		reset();notice="failed";return false
	trial.set_value("trial","state","running");trial.save(TRIAL)
	DirAccess.remove_absolute(OVERRIDE)
	return true

static func confirm() -> void:
	"""The trial run works: Direct3D 12 stays for the next starts."""
	if not FileAccess.file_exists(TRIAL) or running()!="d3d12": return
	var trial := ConfigFile.new();trial.load(TRIAL)
	if str(trial.get_value("trial","state",""))!="running": return
	write_override();DirAccess.remove_absolute(TRIAL)

static func reset() -> void:
	DirAccess.remove_absolute(OVERRIDE);DirAccess.remove_absolute(TRIAL)

static func write_override() -> void:
	var settings := ConfigFile.new()
	settings.set_value("rendering","rendering_device/driver","d3d12")
	settings.set_value("rendering","rendering_device/driver.windows","d3d12")
	settings.set_value("rendering","renderer/rendering_method","forward_plus")
	settings.set_value("rendering","fsr_sdk/enabled",true)
	settings.save(OVERRIDE)

func _ready() -> void:
	if startup(): get_tree().create_timer(TRIAL_SECONDS,true,false,true).timeout.connect(confirm)

func _exit_tree() -> void:
	confirm()
