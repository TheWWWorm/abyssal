extends RefCounted
## Where each touch control sits, as an offset from the place the standard
## composition puts it rather than an absolute position. A different screen size
## keeps the arrangement it was designed for and moves only what a player moved.
## Offsets are in the 1280x720 layout units arrange() works in.
const MIN_SCALE := 0.6
const MAX_SCALE := 2.0
const SCALE_STEP := 0.1
const MAX_OFFSET := 4096.0
## Ordered so hit tests reach the small controls before the steering stick they
## can overlap, and so "next control" walks the screen roughly left to right.
const IDS: Array[String] = ["menu","map","autopilot","time","dock","camera","bank","full",
	"throttle_up","throttle_down","boost","hook","guns","stick"]
const NAMES := {"menu":"Menu","map":"Map","autopilot":"Route","time":"Time","dock":"Dock",
	"camera":"View","bank":"Bank","full":"Fullscreen","throttle_up":"Speed up",
	"throttle_down":"Slow down","boost":"Boost","hook":"Harpoon","guns":"Guns",
	"stick":"Steering stick"}

static func number(value, fallback: float=0.0) -> float:
	if value is not float and value is not int: return fallback
	var result := float(value)
	# A stored NAN or INF would place a control nowhere, with no way back to it.
	return result if is_finite(result) and absf(result)<MAX_OFFSET else fallback

static func sanitize(stored) -> Dictionary:
	"""Settings are text a player can edit, and older builds wrote other shapes.
	Keep only entries this build still places, at sizes it can still draw."""
	var clean := {}
	if stored is not Dictionary: return clean
	for id in IDS:
		if stored.get(id) is not Dictionary: continue
		var entry: Dictionary = stored[id]
		var offset := Vector2(number(entry.get("x")),number(entry.get("y")))
		var scale := clampf(number(entry.get("scale"),1.0),MIN_SCALE,MAX_SCALE)
		if offset==Vector2.ZERO and is_equal_approx(scale,1.0): continue
		clean[id]={"x":offset.x,"y":offset.y,"scale":scale}
	return clean

static func offset_of(layout: Dictionary, id: String) -> Vector2:
	if layout.get(id) is not Dictionary: return Vector2.ZERO
	var entry: Dictionary = layout[id]
	return Vector2(number(entry.get("x")),number(entry.get("y")))

static func scale_of(layout: Dictionary, id: String) -> float:
	if layout.get(id) is not Dictionary: return 1.0
	return clampf(number(layout[id].get("scale"),1.0),MIN_SCALE,MAX_SCALE)

static func adjusted(layout: Dictionary, id: String, offset: Vector2, scale: float) -> Dictionary:
	"""The layout with one control replaced. A control returned to its standard
	place leaves no entry behind, so a reset really is a reset."""
	var result := layout.duplicate(true)
	var clamped := clampf(scale,MIN_SCALE,MAX_SCALE)
	if offset.is_zero_approx() and is_equal_approx(clamped,1.0): result.erase(id)
	else: result[id]={"x":offset.x,"y":offset.y,"scale":clamped}
	return result

static func encode(layout: Dictionary) -> String:
	return JSON.stringify(sanitize(layout))

static func decode(text) -> Dictionary:
	if text is not String or str(text).is_empty(): return {}
	var reader := JSON.new()
	return sanitize(reader.data) if reader.parse(str(text))==OK else {}
