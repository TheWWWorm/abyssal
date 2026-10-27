extends Control
## cb's radar tallies: live fish collected and enemy ships defeated this trip.
## Read the medal counters directly, so their display and awards cannot drift.
var imported_art
var kills := 0
var catches := 0
var icon_theme := "b"
const ROW_HEIGHT := 26.0
const WIDTH := 176.0
const READOUT := Color("c9e7ea")
const SHADOW := Color("020a11")
# be.a(Z): the original flight HUD ink, including the all-gold override.
const INKS := {"b":Color("4993b8"),"g":Color("6ab764"),"go":Color("fdffb4")}
const MAX_MARKS := 55
func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	hide()
func update(medals, show_feedback: bool, radar: int, rebel_hull: bool=false) -> void:
	var next_theme := "go" if medals.gold_set() else "g" if rebel_hull else "b"
	var changed: bool=kills!=medals.kills or catches!=medals.catches or icon_theme!=next_theme
	kills=maxi(0,medals.kills);catches=maxi(0,medals.catches)
	icon_theme=next_theme
	size=Vector2(WIDTH,entry_height(kills)+entry_height(catches))
	visible=show_feedback and radar>0 and size.y>0
	if changed:queue_redraw()
static func entry_height(count: int) -> float:
	if count<=0:return 0.0
	return ROW_HEIGHT+16.0*ceili(maxi(0,mini(count,MAX_MARKS)-15)/20.0)
func draw_tally(mark: int, y: float, ink: Color) -> void:
	# cb: 2-pixel pitch, a 6-pixel upright, then an 8-by-5 slash on
	# every fifth mark. The first row holds 15; later rows hold 20.
	# Draw at 2x with whole source pixels, preserving the thin flat strokes.
	var at := Vector2(82+mark*4,y+7)
	if mark>=15:at=Vector2(62+((mark-15)%20)*4,y+7+(1+int((mark-15)/20))*16)
	if mark%5==4:
		for x in 9:
			var pixel := Vector2(x,roundi(5.0-x*5.0/8.0))
			draw_rect(Rect2(at+Vector2(-18,0)+pixel*2,Vector2(2,2)),ink)
	else:draw_rect(Rect2(at,Vector2(2,12)),ink)
func _draw() -> void:
	var y := 0.0
	var ink: Color=INKS[icon_theme]
	for entry in [[kills,"s"],[catches,"f"]]:
		var count: int=entry[0]
		if count<=0:continue
		# These are coloured ship/fish sprites; retain their outline and eye.
		var icon: Texture2D=imported_art.image("c_"+icon_theme+"_"+entry[1]) if imported_art!=null else null
		if icon!=null:
			var extent:=icon.get_size()*2.0
			draw_texture_rect(icon,Rect2(Vector2(0,y+(ROW_HEIGHT-extent.y)*.5),extent),false)
		var font := get_theme_default_font()
		var at := Vector2(28,y+19)
		var pixels := clampi(floori(18*50/maxf(50,font.get_string_size(str(count),HORIZONTAL_ALIGNMENT_LEFT,-1,18).x)),9,18)
		draw_string_outline(font,at,str(count),HORIZONTAL_ALIGNMENT_LEFT,-1,pixels,4,SHADOW)
		draw_string(font,at,str(count),HORIZONTAL_ALIGNMENT_LEFT,-1,pixels,READOUT)
		for mark in mini(count,MAX_MARKS):draw_tally(mark,y,ink)
		# Keep long trips bounded on phones. The number remains exact; an
		# ellipsis after three rows indicates that there are further marks.
		if count>MAX_MARKS:
			for dot in 3:draw_rect(Rect2(Vector2(146+dot*5,y+47),Vector2(2,2)),ink)
		y+=entry_height(count)
