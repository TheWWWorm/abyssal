extends Node
## The renderer the next start uses, on Windows, Linux x86-64 and Android.
## Vulkan is the default: Forward+ on the desktop, the Mobile renderer on
## Android. OpenGL is the compatibility renderer the browser build uses, for
## graphics drivers whose Vulkan misbehaves. On Windows, the engine build
## that carries AMD's FidelityFX integration (engine/godot-4.7/amd-fsr.patch)
## also offers Direct3D 12, which loads AMD's runtime for FSR 3.1, FSR 4 and
## frame generation. Godot picks the renderer before any script runs, so the
## choice is a settings override (project.godot's
## application/config/project_settings_override names OVERRIDE) read at the
## next start. Whatever branches on the renderer reads the running one,
## never this choice.
##
## Crash safety: the first start on another renderer is a trial. Once it
## runs, OVERRIDE is removed, so a crash in that run leaves the next start on
## Vulkan; after TRIAL_SECONDS or a clean quit the choice is written again.
## A start that finds a trial still running (that run ended unexpectedly) or
## another renderer than the one chosen (it could not start) goes back to
## Vulkan, and the title says so (`notice`, `failed_choice`).

const Amd = preload("res://native/presentation/amd.gd")

const OVERRIDE := "user://renderer.cfg"
const TRIAL := "user://renderer-trial.cfg"
const TRIAL_SECONDS := 60.0
const DEFAULT := "vulkan"
## The notice for the title: "crashed" (a trial run ended unexpectedly),
## "failed" (the chosen renderer did not start) or "" for none, and the
## choice it concerns.
static var notice := ""
static var failed_choice := ""
## The choice this run was started with, "" for the default: a run on OpenGL
## without one is Godot's own fallback where Vulkan cannot start.
static var started_with := ""

static func platform() -> bool:
	"""Where the export runs Vulkan by default (export_game.py): Windows,
	Linux x86-64 and Android. Checks may ask for it with --renderer-option."""
	if OS.get_cmdline_user_args().has("--renderer-option"): return true
	return OS.has_feature("windows") or OS.has_feature("android") or (OS.has_feature("linuxbsd") and OS.has_feature("x86_64"))

static func choices() -> Array:
	var offered: Array=["vulkan","opengl"]
	if Amd.mode()>=0 and (OS.has_feature("windows") or OS.get_cmdline_user_args().has("--renderer-option")): offered.append("d3d12")
	return offered

static func available() -> bool:
	return platform()

static func name_of(choice: String) -> String:
	return {"vulkan":"Vulkan","opengl":"OpenGL","d3d12":"Direct3D 12 · AMD FSR"}.get(choice,choice)

static func names() -> Array:
	return choices().map(name_of)

static func running() -> String:
	"""The renderer this run uses, as a choice."""
	if RenderingServer.get_current_rendering_method()=="gl_compatibility": return "opengl"
	return "d3d12" if RenderingServer.get_current_rendering_driver_name()=="d3d12" else "vulkan"

static func pending() -> String:
	"""The renderer a trial or a confirmed choice names, or "" for the default."""
	for path in [TRIAL,OVERRIDE]:
		if not FileAccess.file_exists(path): continue
		var file := ConfigFile.new();file.load(path)
		var choice := str(file.get_value("abyssal","renderer",""))
		# 1.21.1 wrote Direct3D 12 without naming it.
		if choice.is_empty(): choice="d3d12"
		return choice
	return ""

static func chosen() -> String:
	"""The renderer for the next start; a trial counts as chosen."""
	var choice := pending()
	return choice if choice in choices() else DEFAULT

static func choose(choice: String) -> void:
	if choice==chosen(): return
	if choice==DEFAULT or choice not in choices(): reset();return
	write_override(choice)
	var trial := ConfigFile.new();trial.set_value("trial","state","pending");trial.set_value("abyssal","renderer",choice);trial.save(TRIAL)

static func startup() -> bool:
	"""This start's step in a trial; true while it runs on the chosen renderer."""
	started_with=pending()
	if not FileAccess.file_exists(TRIAL): return false
	var trial := ConfigFile.new();trial.load(TRIAL)
	var choice := pending()
	if str(trial.get_value("trial","state",""))=="running":
		reset();notice="crashed";failed_choice=choice;return false
	if running()!=choice:
		reset();notice="failed";failed_choice=choice;return false
	trial.set_value("trial","state","running");trial.save(TRIAL)
	DirAccess.remove_absolute(OVERRIDE)
	return true

static func confirm() -> void:
	"""The trial run works: its renderer stays for the next starts."""
	if not FileAccess.file_exists(TRIAL): return
	var trial := ConfigFile.new();trial.load(TRIAL)
	var choice := pending()
	if str(trial.get_value("trial","state",""))!="running" or running()!=choice: return
	write_override(choice);DirAccess.remove_absolute(TRIAL)

static func reset() -> void:
	DirAccess.remove_absolute(OVERRIDE);DirAccess.remove_absolute(TRIAL)

static func write_override(choice: String) -> void:
	var settings := ConfigFile.new()
	settings.set_value("abyssal","renderer",choice)
	match choice:
		"d3d12":
			settings.set_value("rendering","rendering_device/driver","d3d12")
			settings.set_value("rendering","rendering_device/driver.windows","d3d12")
			settings.set_value("rendering","renderer/rendering_method","forward_plus")
			settings.set_value("rendering","fsr_sdk/enabled",true)
		"opengl":
			# The project's feature-tagged methods outrank the plain one.
			for key in ["renderer/rendering_method","renderer/rendering_method.mobile"]:
				settings.set_value("rendering",key,"gl_compatibility")
	settings.save(OVERRIDE)

func _ready() -> void:
	if startup(): get_tree().create_timer(TRIAL_SECONDS,true,false,true).timeout.connect(confirm)

func _exit_tree() -> void:
	confirm()
