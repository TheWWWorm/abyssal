extends RefCounted
## The picture fills the window by default. A fixed ratio letterboxes instead,
## for players whose display would otherwise stretch the composition or who
## record at a set shape. Heights match so a switch keeps the same detail.
const RATIOS := {"auto":Vector2i(1600,900),"4:3":Vector2i(1200,900),
	"16:9":Vector2i(1600,900),"16:10":Vector2i(1440,900),"21:9":Vector2i(2100,900)}

static func names() -> Array:
	return RATIOS.keys()

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
