extends Control
## The desktop helm: thrust, simulation speed and booster on one glass strip
## at the foot of the screen, in the station interface's style. Touch has its
## own throttle arc and boost button instead.
const StationTheme = preload("res://native/presentation/station_theme.gd")
var imported_art
var throttle_fraction := 0.0
var throttle := 0
var speed := 1
var boost := {"mode":"absent","fraction":0.0,"seconds":0.0}
var boost_key := ""
var frame := StationTheme.frame(Color(.016,.07,.1,.78),Color("2b7894"),8,1,Color(.25,.8,1.0,.14),6)
var font: FontVariation
var palette := StationTheme.palette(false)
## Set by the owner's layout: the strip grows with the window height.
var scale_factor := 1.0:
	set(value): scale_factor=value; queue_redraw()
func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	font=StationTheme.spaced(get_theme_default_font(),2)
	resized.connect(queue_redraw)
func update(player, _ship, simulation_speed: int, boost_state: Dictionary={}, key: String="") -> void:
	throttle=int(player.throttle);throttle_fraction=float(player.throttle)/100.0
	speed=simulation_speed;boost_key=key
	if not boost_state.is_empty(): boost=boost_state
	queue_redraw()
func panel_rect() -> Rect2:
	"""In unscaled units about the strip's bottom centre. Without a booster
	the strip carries thrust and time alone and narrows to fit them."""
	var width := 380.0 if boost.get("mode","absent")!="absent" else 196.0
	# Clear of the key hints along the screen's bottom edge.
	return Rect2(Vector2(-width*.5,-80),Vector2(width,40))
func rail(rect: Rect2, amount: float, lit: Color) -> void:
	var count := int(rect.size.x/5)
	for index in count:
		draw_rect(Rect2(rect.position+Vector2(index*5,0),Vector2(3,rect.size.y)),lit if (index+.5)/count<=amount else Color("1d3c48cc"))
func words(at: Vector2, value: String, colour: Color, pixels: int=11, align:=HORIZONTAL_ALIGNMENT_LEFT, width:=-1.0) -> void:
	draw_string(font,at,value,align,width,pixels,colour)
func _draw() -> void:
	draw_set_transform(Vector2(size.x*.5,size.y),0,Vector2.ONE*scale_factor)
	var box := panel_rect()
	draw_style_box(frame,box)
	var fitted: bool=boost.get("mode","absent")!="absent"
	var section := 160.0
	var left := box.position+Vector2(18,17)
	words(left,"THRUST  %d%%"%throttle,palette.text,10)
	words(left,"TIME  %d×"%speed,palette.dim,10,HORIZONTAL_ALIGNMENT_RIGHT,section)
	rail(Rect2(left+Vector2(0,7),Vector2(section,6)),throttle_fraction,palette.accent)
	if not fitted: return
	var mode: String=boost.mode
	var right := left+Vector2(section+22,0)
	var caption: String={"active":"BOOSTING  %.1f s"%boost.seconds,"charging":"BOOST  %.1f s"%boost.seconds,"ready":"BOOST READY"}.get(mode,"BOOST")
	words(right,caption,palette.value if mode=="active" else palette.dim,10)
	if mode=="ready" and not boost_key.is_empty(): words(right,boost_key,palette.text,10,HORIZONTAL_ALIGNMENT_RIGHT,section)
	rail(Rect2(right+Vector2(0,7),Vector2(section,6)),float(boost.get("fraction",0.0)),palette.value if mode in ["active","ready"] else palette.accent.darkened(.3))
