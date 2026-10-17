extends Control
## The reference's station chart: every station at its chart position,
## coloured by who holds it at a given chapter. Stations joining in that
## chapter are ringed and the page's own station is marked and named.
## Clicking a station opens its page.
signal followed(key: String)

var catalog
var palette: Dictionary
var highlight := -1
var as_of := 0
var joining: Array = []
var hovered := -1
const COLONIST := Color("6fb6ff")
const REBEL := Color("f0a24a")

func configure(owner_catalog, shown: Dictionary, colours: Dictionary) -> void:
	catalog = owner_catalog; palette = colours
	highlight = int(shown.get("highlight", -1)); as_of = int(shown.get("as_of", 0)); joining = shown.get("joining", [])
	custom_minimum_size = Vector2(200, 200); mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_exited.connect(func(): hovered = -1; queue_redraw())
	resized.connect(queue_redraw)

## The chart's 0..100 square fitted into the control, with a margin.
func area() -> Rect2:
	var side := minf(size.x, size.y) - 16
	return Rect2((size - Vector2(side, side)) * 0.5, Vector2(side, side))

func point(id: int) -> Vector2:
	var row: Array = catalog.data.tables.stations[id]
	var box := area()
	return box.position + Vector2(float(row[2]), float(row[3])) / 100.0 * box.size

func rebel(id: int) -> bool: return catalog.rebel_since.has(id) and catalog.rebel_since[id] <= as_of

func nearest(at: Vector2) -> int:
	var best := -1
	var reach := 14.0
	for id in catalog.data.tables.stations.size():
		var gap := point(id).distance_to(at)
		if gap < reach: reach = gap; best = id
	return best

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var id := nearest(event.position)
		if id != hovered:
			hovered = id; queue_redraw()
			tooltip_text = catalog.station_name(id) if id >= 0 else ""
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var id := nearest(event.position)
		if id >= 0: followed.emit("station/%d" % id); accept_event()

func _draw() -> void:
	if catalog == null: return
	var box := area()
	draw_rect(box.grow(6), Color(palette.card, 0.55))
	for step in range(1, 4):
		var at := box.size * step / 4.0
		draw_line(box.position + Vector2(at.x, 0), box.position + Vector2(at.x, box.size.y), Color(palette.edge, 0.25))
		draw_line(box.position + Vector2(0, at.y), box.position + Vector2(box.size.x, at.y), Color(palette.edge, 0.25))
	var unit := maxf(1.6, box.size.x / 150.0)
	for id in catalog.data.tables.stations.size():
		var colour := REBEL if rebel(id) else COLONIST
		draw_circle(point(id), unit * (1.6 if id in joining else 1.0), Color(colour, 0.85))
		if id in joining: draw_arc(point(id), unit * 2.6, 0, TAU, 20, palette.text, 1.0, true)
	for id in [highlight, hovered]:
		if id < 0: continue
		var at := point(id)
		draw_arc(at, unit * 3.4, 0, TAU, 24, palette.value if id == highlight else palette.text, 2.0, true)
		var font := get_theme_font("font", "Label")
		var name_ := str(catalog.station_name(id))
		var width := font.get_string_size(name_, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		var place := Vector2(clampf(at.x + unit * 4, box.position.x, box.end.x - width), clampf(at.y - unit * 3, box.position.y + 14, box.end.y))
		draw_string_outline(font, place, name_, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, Color(0, 0, 0, 0.8))
		draw_string(font, place, name_, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, palette.text)
