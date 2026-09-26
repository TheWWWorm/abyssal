extends RefCounted
## The picture fills the window by default. A fixed ratio letterboxes instead,
## for players whose display would otherwise stretch the composition or who
## record at a set shape. Heights match so a switch keeps the same detail.
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

static func apply(window: Window, ratio: String, fallback: Vector2i) -> void:
	## Assigning content_scale_size re-emits the window's size_changed, which is
	## what calls this in the first place. Only write an actual change.
	var chosen := valid(ratio)
	# Auto keeps the engine's responsive sizing, recomputed from the real window.
	var wanted: Vector2i = fallback if chosen=="auto" else RATIOS[chosen]
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

const ORIENTATIONS := ["Auto · any direction","Landscape","Portrait"]
static func orientation_setting_available() -> bool:
	"""Only an installed phone app turns its own screen; a browser tab cannot."""
	return OS.has_feature("mobile") and not OS.has_feature("web")
static func apply_orientation(choice: int) -> void:
	# Auto follows the sensor through every direction, so a phone mounted
	# upside down in a controller clamp (USB port on the other side) turns the
	# picture the right way up; Landscape and Portrait still turn over.
	if not orientation_setting_available(): return
	DisplayServer.screen_set_orientation([DisplayServer.SCREEN_SENSOR,DisplayServer.SCREEN_SENSOR_LANDSCAPE,DisplayServer.SCREEN_SENSOR_PORTRAIT][clampi(choice,0,2)])
