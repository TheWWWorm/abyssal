extends Node
## The renderer the next start uses, on Windows, Linux x86-64 and Android.
## Vulkan is the default: Forward+ on the desktop, the Mobile renderer on
## Android; Automatic (below) where Direct3D 12 is offered. OpenGL is the compatibility renderer the browser build uses, for
## graphics drivers whose Vulkan misbehaves. On Windows, the engine build
## that carries the vendor integrations (engine/godot-4.7/) also offers
## Direct3D 12 twice: with AMD's runtime for FSR 3.1, FSR 4 and frame
## generation, or with NVIDIA's for DLSS and DLSS Frame Generation. The two
## share the swap chain, so a session loads one of them. Godot picks the
## renderer before any script runs, so the choice is a settings override (project.godot's
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
##
## Automatic, the default where Direct3D 12 is offered, starts the Direct3D
## 12 that suits the graphics card: NVIDIA DLSS on an NVIDIA RTX card, AMD
## FSR on any other. The first start runs on Vulkan, finds the card and
## starts again on that renderer, as a trial. A renderer that failed or
## crashed is left out (AUTO_STATE) until the card or its driver changes;
## Vulkan is the last resort.

const Amd = preload("res://native/presentation/amd.gd")
const Nvidia = preload("res://native/presentation/nvidia.gd")

const OVERRIDE := "user://renderer.cfg"
const TRIAL := "user://renderer-trial.cfg"
const TRIAL_SECONDS := 60.0
const AUTO := "auto"
const AUTO_STATE := "user://renderer-auto.cfg"
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
	if OS.has_feature("windows") or OS.get_cmdline_user_args().has("--renderer-option"):
		if Amd.mode()>=0: offered.append("d3d12")
		if Nvidia.dlss_mode()>=0: offered.append("d3d12_dlss")
	if offered.size()>2: offered.push_front(AUTO)
	return offered

static func default_choice() -> String:
	"""Automatic where it chooses between renderers, else Vulkan."""
	return AUTO if AUTO in choices() else "vulkan"

static func preferred(vendor: String, adapter: String) -> Array:
	"""The renderers Automatic tries for a graphics card, best first."""
	if "nvidia" in vendor.to_lower() and "rtx" in adapter.to_lower(): return ["d3d12_dlss","d3d12","vulkan"]
	return ["d3d12","vulkan"]

static func fingerprint() -> String:
	return JSON.stringify([RenderingServer.get_video_adapter_name(),Array(OS.get_video_adapter_driver_info())])

static func auto_state() -> ConfigFile:
	"""What Automatic learned on this card and driver; a new one starts afresh."""
	var state := ConfigFile.new()
	if state.load(AUTO_STATE)!=OK or str(state.get_value("auto","fingerprint",""))!=fingerprint():
		state=ConfigFile.new();state.set_value("auto","fingerprint",fingerprint());state.set_value("auto","failed",[])
	return state

static func auto_failed(choice: String) -> void:
	if choice.is_empty() or choice=="vulkan": return
	var state := auto_state()
	var failed: Array=state.get_value("auto","failed",[])
	if not choice in failed: failed.append(choice)
	state.set_value("auto","failed",failed);state.save(AUTO_STATE)

static func auto_target() -> String:
	"""The renderer Automatic starts on this card."""
	var failed: Array=auto_state().get_value("auto","failed",[])
	for candidate in preferred(RenderingServer.get_video_adapter_vendor(),RenderingServer.get_video_adapter_name()):
		if candidate in choices() and not candidate in failed: return candidate
	return "vulkan"

static func available() -> bool:
	return platform()

static func name_of(choice: String) -> String:
	return {"auto":"Automatic","vulkan":"Vulkan","opengl":"OpenGL","d3d12":"Direct3D 12 · AMD FSR","d3d12_dlss":"Direct3D 12 · NVIDIA DLSS"}.get(choice,choice)

static func names() -> Array:
	return choices().map(name_of)

static func running() -> String:
	"""The renderer this run uses, as a choice."""
	if RenderingServer.get_current_rendering_method()=="gl_compatibility": return "opengl"
	if RenderingServer.get_current_rendering_driver_name()!="d3d12": return "vulkan"
	return "d3d12_dlss" if bool(ProjectSettings.get_setting("rendering/streamline/enabled",false)) else "d3d12"

static func saved() -> ConfigFile:
	"""The trial, else the confirmed choice, else null."""
	for path in [TRIAL,OVERRIDE]:
		if not FileAccess.file_exists(path): continue
		var file := ConfigFile.new();file.load(path);return file
	return null

static func pending() -> String:
	"""The renderer a trial or a confirmed choice names, or "" for the default."""
	var file := saved()
	if file==null: return ""
	# 1.21.1 wrote Direct3D 12 without naming it.
	var choice := str(file.get_value("abyssal","renderer",""))
	return "d3d12" if choice.is_empty() else choice

static func chosen() -> String:
	"""The choice in Settings: Automatic or a renderer. A trial counts as
	chosen; a file from before Automatic named its renderer alone."""
	var file := saved()
	var choice := default_choice() if file==null else str(file.get_value("abyssal","selection",pending()))
	return choice if choice in choices() else default_choice()

static func next() -> String:
	"""The renderer the next start runs."""
	var choice := chosen()
	return auto_target() if choice==AUTO else choice

static func choose(choice: String) -> void:
	if choice==chosen() or choice not in choices(): return
	if choice=="vulkan" and default_choice()=="vulkan": reset();return
	if choice==AUTO: DirAccess.remove_absolute(AUTO_STATE)
	var renderer := auto_target() if choice==AUTO else choice
	write_override(renderer,choice)
	DirAccess.remove_absolute(TRIAL)
	# Vulkan is the fallback itself; anything else starts as a trial.
	if renderer!="vulkan": save_trial(renderer,choice)

static func save_trial(renderer: String, selection: String) -> void:
	var trial := ConfigFile.new();trial.set_value("trial","state","pending")
	trial.set_value("abyssal","renderer",renderer);trial.set_value("abyssal","selection",selection);trial.save(TRIAL)

static func startup() -> bool:
	"""This start's step in a trial; true while it runs on the chosen renderer."""
	started_with=pending()
	if not FileAccess.file_exists(TRIAL): return false
	var trial := ConfigFile.new();trial.load(TRIAL)
	var choice := pending()
	if str(trial.get_value("trial","state",""))=="running":
		auto_failed(choice);reset();notice="crashed";failed_choice=choice;return false
	if running()!=choice:
		auto_failed(choice);reset();notice="failed";failed_choice=choice;return false
	trial.set_value("trial","state","running");trial.save(TRIAL)
	DirAccess.remove_absolute(OVERRIDE)
	return true

static func forced() -> bool:
	"""A renderer named on the command line, or no window: Automatic keeps out."""
	var args := OS.get_cmdline_args()
	return args.has("--rendering-driver") or args.has("--rendering-method") or DisplayServer.get_name()=="headless"

static func automatic_restart() -> bool:
	"""Automatic on a start that runs another renderer than the card's: the
	next start is a trial of it. True when this start should restart now; a
	start that just reported a failed renderer waits for the next."""
	if chosen()!=AUTO or not notice.is_empty() or forced() or FileAccess.file_exists(TRIAL): return false
	# Only ever towards a Direct3D 12 trial: Vulkan is where a failure lands,
	# and a Vulkan the engine replaced with OpenGL would only fall back again.
	var target := auto_target()
	if target==running() or target=="vulkan": return false
	write_override(target,AUTO);save_trial(target,AUTO)
	return true

static func restart_args() -> PackedStringArray:
	"""This start's command line for the next, without a renderer named on it.
	Godot reports neither its own options nor a window flag, so the window
	mode comes back from the settings; arguments after -- are kept."""
	var args := PackedStringArray();var skip := false
	for arg in OS.get_cmdline_args():
		if skip: skip=false;continue
		if arg in ["--rendering-driver","--rendering-method"]: skip=true;continue
		args.append(arg)
	var user := OS.get_cmdline_user_args()
	if not user.is_empty(): args.append("--");args.append_array(user)
	return args

static func restart(tree: SceneTree) -> void:
	"""Starts the game again, on the renderer chosen for the next start."""
	OS.set_restart_on_exit(true,restart_args())
	tree.quit()

static func confirm() -> void:
	"""The trial run works: its renderer stays for the next starts."""
	if not FileAccess.file_exists(TRIAL): return
	var trial := ConfigFile.new();trial.load(TRIAL)
	var choice := pending()
	if str(trial.get_value("trial","state",""))!="running" or running()!=choice: return
	write_override(choice,str(trial.get_value("abyssal","selection",choice)));DirAccess.remove_absolute(TRIAL)

static func reset() -> void:
	DirAccess.remove_absolute(OVERRIDE);DirAccess.remove_absolute(TRIAL)

static func write_override(choice: String, selection: String="") -> void:
	var settings := ConfigFile.new()
	settings.set_value("abyssal","renderer",choice)
	settings.set_value("abyssal","selection",choice if selection.is_empty() else selection)
	match choice:
		"d3d12","d3d12_dlss":
			settings.set_value("rendering","rendering_device/driver","d3d12")
			settings.set_value("rendering","rendering_device/driver.windows","d3d12")
			settings.set_value("rendering","renderer/rendering_method","forward_plus")
			# The engine loads the one vendor runtime named here.
			settings.set_value("rendering","fsr_sdk/enabled" if choice=="d3d12" else "streamline/enabled",true)
		"opengl":
			# The project's feature-tagged methods outrank the plain one.
			for key in ["renderer/rendering_method","renderer/rendering_method.mobile"]:
				settings.set_value("rendering",key,"gl_compatibility")
	settings.save(OVERRIDE)

func _ready() -> void:
	if startup(): get_tree().create_timer(TRIAL_SECONDS,true,false,true).timeout.connect(confirm)
	elif automatic_restart(): restart.call_deferred(get_tree())

func _exit_tree() -> void:
	confirm()
