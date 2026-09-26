extends Button
## The browser build's fullscreen switch in the top-right corner, as video
## players place it. The title and the pause menu show it; its press is the
## user gesture a browser requires before it grants fullscreen.
const StationTheme = preload("res://native/presentation/station_theme.gd")
const StationIcon = preload("res://native/presentation/station_icon.gd")

## iOS allows home-screen web apps only from Safari; other iOS browsers cannot.
const NO_FULLSCREEN := "This browser does not support fullscreen. Open the game in Safari and use Share → Add to Home Screen to play without browser bars."

## Only the browser build shows it. Tests set this to check the placement.
var web_build := OS.has_feature("web")

func _init(action: Callable) -> void:
	pressed.connect(action)

func _ready() -> void:
	name="FullscreenButton"
	accessibility_name="Fullscreen"
	tooltip_text="Fullscreen"
	# Pointer and touch only; a pad reaches fullscreen through Settings.
	focus_mode=Control.FOCUS_NONE
	for state in ["normal","hover","pressed","focus","disabled"]: add_theme_stylebox_override(state,StationTheme.button_state(false,state))
	var mark := StationIcon.new("fullscreen",StationTheme.palette(false).accent,26);add_child(mark)
	mark.set_anchors_and_offsets_preset(Control.PRESET_CENTER);mark.offset_left=-13;mark.offset_right=13;mark.offset_top=-13;mark.offset_bottom=13
	set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	offset_left=-76;offset_right=-24;offset_top=24;offset_bottom=76
	z_index=50
	hide()

func place(wanted: bool) -> void:
	visible=web_build and wanted

static func browser_supported() -> bool:
	# iPhone Safari has no Fullscreen API, so a request there fails silently.
	if not OS.has_feature("web"): return true
	return bool(JavaScriptBridge.eval("!!(document.fullscreenEnabled||document.webkitFullscreenEnabled)",true))

static func toggle(notice: Callable) -> void:
	"""The same switch as the pause menu's: fullscreen, or the reason there is none."""
	if not browser_supported():
		notice.call(NO_FULLSCREEN)
		return
	var mode := DisplayServer.window_get_mode()
	var full: bool=mode in [DisplayServer.WINDOW_MODE_FULLSCREEN,DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
