extends RefCounted
## The picture fills the window by default. A fixed ratio letterboxes instead,
## for players whose display would otherwise stretch the composition or who
## record at a set shape. Heights match so a switch keeps the same detail.
const EngineLanguage = preload("res://native/presentation/engine_language.gd")
const RATIOS := {"auto":Vector2i(1600,900),"4:3":Vector2i(1200,900),
	"16:9":Vector2i(1600,900),"16:10":Vector2i(1440,900),"21:9":Vector2i(2100,900)}

static func names() -> Array:
	return RATIOS.keys()

static func framed_fov(vertical: float, visible: Vector2) -> float:
	"""A camera's vertical field of view for the screen's shape. Held upright a
	phone keeps the landscape's vertical angle only by cutting the sides to a
	slit, filling the screen with whatever is ahead - a station at close range
	is then almost every pixel. Taller screens widen the angle part of the way,
	so the view still reads as the same camera turned on its side."""
	if visible.x<=0 or visible.y<=visible.x: return vertical
	var widened: float=tan(deg_to_rad(vertical)*.5)*pow(visible.y/visible.x,.6)
	return rad_to_deg(2.0*atan(widened))

static func valid(ratio: String) -> String:
	return ratio if RATIOS.has(ratio) else "auto"

## Interface sizes, in percent of the canvas's own. Smaller draws every
## control and line of text smaller on a larger canvas; the picture still
## fills the window, unlike a wider fixed ratio, which letterboxes it.
const UI_SCALES := [70,80,90,100,110,125]
static func ui_scale(config: ConfigFile) -> int:
	var value: Variant=config.get_value("view","ui_scale",100)
	return int(value) if (value is int or value is float) and int(value) in UI_SCALES else 100
static func ui_scale_names() -> Array:
	return UI_SCALES.map(func(percent): return "%d%%"%percent)

static func apply(window: Window, ratio: String, fallback: Vector2i, scale_percent := 100) -> void:
	## Assigning content_scale_size re-emits the window's size_changed, which is
	## what calls this in the first place. Only write an actual change.
	var chosen := valid(ratio)
	# Auto keeps the engine's responsive sizing, recomputed from the real window.
	var base: Vector2i = fallback if chosen=="auto" else RATIOS[chosen]
	var wanted := Vector2i((Vector2(base)*100.0/maxi(1,scale_percent)).round())
	var shape := Window.CONTENT_SCALE_ASPECT_EXPAND if chosen=="auto" else Window.CONTENT_SCALE_ASPECT_KEEP
	if window.content_scale_size!=wanted: window.content_scale_size=wanted
	if window.content_scale_aspect!=shape: window.content_scale_aspect=shape

static func responsive_size(pixels: Vector2i, touch: bool) -> Vector2i:
	"""The interface canvas for a window: a desktop canvas grows with the window
	up to 1920 wide; touch keeps 1280 on the long side. Held upright, the long
	side is 1280 as it is held landscape, so every control and line of text
	keeps its size on the same phone. The title and the dive share this."""
	var width := 1280 if touch else clampi(pixels.x,1280,1920)
	var size := Vector2i(width,roundi(width*float(pixels.y)/maxf(1,pixels.x)))
	if touch and pixels.y>pixels.x: size=Vector2i(roundi(1280.0*pixels.x/pixels.y),1280)
	return size

## Frame rate limits: 0 draws as fast as the GPU allows, -1 at the display's
## refresh rate. VSync, on by default, already holds the rate to the display;
## off with no limit is the unlocked frame rate.
const FPS_LIMITS := [0,30,60,120,144,165,240,-1]
static func fps_limit_names() -> Array:
	return FPS_LIMITS.map(func(limit): return EngineLanguage.translate("Unlimited") if limit==0 else EngineLanguage.translate("Display refresh") if limit<0 else str(limit))

static func desktop() -> bool:
	"""A window of its own: the desktop builds, not a browser tab or a phone."""
	return not OS.has_feature("web") and not OS.has_feature("mobile")

static func fps_limit(config: ConfigFile) -> int:
	var value: Variant=config.get_value("view","fps_limit",0)
	return int(value) if (value is int or value is float) and int(value) in FPS_LIMITS else 0

static func vsync(config: ConfigFile) -> bool:
	return bool(config.get_value("view","vsync",true))

## A --max-fps on the command line, read before the first change: Godot sets
## it over the project's own limit and does not list it among the arguments.
static var command_line_fps := -1

static func apply_frame_pacing(config: ConfigFile) -> void:
	"""The frame rate limit and VSync. A --max-fps on the command line (the
	checks run capped) and a browser's own pacing are left alone."""
	if command_line_fps<0:
		command_line_fps=Engine.max_fps if Engine.max_fps!=int(ProjectSettings.get_setting("application/run/max_fps",0)) else 0
	if command_line_fps==0:
		var limit := fps_limit(config)
		if limit<0: limit=roundi(maxf(DisplayServer.screen_get_refresh_rate(),0.0))
		Engine.max_fps=limit
	if desktop() and DisplayServer.get_name()!="headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync(config) else DisplayServer.VSYNC_DISABLED)

static func fullscreen() -> bool:
	return DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN,DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]

static func set_fullscreen(on: bool, settings_path: String) -> void:
	"""Switches the window and remembers it for the next start (desktop only;
	a browser grants fullscreen only inside a press)."""
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED)
	if not desktop() or settings_path.is_empty(): return
	var config := ConfigFile.new();config.load(settings_path);config.set_value("view","fullscreen",on)
	DirAccess.make_dir_recursive_absolute(settings_path.get_base_dir());config.save(settings_path)

static func restore_window(config: ConfigFile) -> void:
	"""The start: the window mode the player left. A window the command line
	already changed (--fullscreen, --maximized) is left as it is."""
	if not desktop() or DisplayServer.get_name()=="headless": return
	if DisplayServer.window_get_mode()!=int(ProjectSettings.get_setting("display/window/size/mode",DisplayServer.WINDOW_MODE_WINDOWED)): return
	if bool(config.get_value("view","fullscreen",false)) and not fullscreen():
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

const ORIENTATIONS := ["Auto · any direction","Landscape","Portrait"]
static func orientation_names() -> Array:
	"""ORIENTATIONS in the engine's language."""
	return [EngineLanguage.translate("Auto · any direction"),EngineLanguage.translate("Landscape"),EngineLanguage.translate("Portrait")]
static func orientation_setting_available() -> bool:
	"""Only an installed phone app turns its own screen; a browser tab cannot."""
	return OS.has_feature("mobile") and not OS.has_feature("web")
static func apply_orientation(choice: int) -> void:
	# Auto follows the sensor through every direction, so a phone mounted
	# upside down in a controller clamp (USB port on the other side) turns the
	# picture the right way up; Landscape and Portrait still turn over.
	if not orientation_setting_available(): return
	DisplayServer.screen_set_orientation([DisplayServer.SCREEN_SENSOR,DisplayServer.SCREEN_SENSOR_LANDSCAPE,DisplayServer.SCREEN_SENSOR_PORTRAIT][clampi(choice,0,2)])
