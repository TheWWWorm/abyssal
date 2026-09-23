extends Control
## Numeric ranges change every simulation tick. Reuse individual font glyphs
## instead of reshaping an entire contact name and detail paragraph each time.
var text := ""
var tint := Color.WHITE
var font: Font
var advances := {}
const FONT_SIZE := 13
static func format_distance(meters: float) -> String:
	if meters>=1000.0:return "%.2f km"%(meters/1000.0)
	# Preserve steady five-metre steps nearby without rounding up to 1000 m.
	return "%.0f m"%minf(999,snappedf(meters,5.0) if meters>=50 else meters)
func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	font=get_theme_font("font","Label")
func display(value: String, color: Color) -> void:
	if value==text and color==tint: return
	text=value; tint=color
	var width := 0.0
	for i in text.length():
		var character := text.unicode_at(i)
		if not advances.has(character): advances[character]=font.get_char_size(character,FONT_SIZE).x
		width+=advances[character]
	# Font glyph advances are fractional; reserve the final partial pixel.
	size=Vector2(ceilf(width),font.get_height(FONT_SIZE)); queue_redraw()
func _draw() -> void:
	if font==null: return
	var x := 0.0
	var baseline := font.get_ascent(FONT_SIZE)
	for i in text.length():
		var character := text.unicode_at(i)
		font.draw_char(get_canvas_item(),Vector2(x,baseline),character,FONT_SIZE,tint)
		x+=advances[character]
