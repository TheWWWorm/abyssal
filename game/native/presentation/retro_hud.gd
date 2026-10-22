extends Control
## The Retro HUD option: the original's own gauges (bd) in the standard HUD's
## segmented style, with the JAR's pixel icons. The cargo hold runs across the
## top; along the foot of the screen the shield and hull bars sit either side
## of the auto fire, autopilot and hull lamps, and take over from the two
## gauge rows in the top left.
const StationTheme = preload("res://native/presentation/station_theme.gd")
const CARGO_COLOR := Color("e8c063")
const FULL_COLOR := Color("f39a5c")
const SHIELD_COLOR := Color("5fd0ea")
const HULL_COLOR := Color("7ee08e")
const ARMOR_COLOR := Color("f0cc4a")
const LOW_COLOR := Color("f5795f")
const UNLIT := Color("1d3c48cc")
const OFF := Color("4f7482")
var imported_art
var palette := StationTheme.palette(false)
## Set by the owner's layout, in this control's pixels: the cargo bar's band
## and the bottom row's, either empty where there is no room for it.
var cargo_rect := Rect2()
var row_rect := Rect2()
var unit := 1.0
var cargo := 0
var capacity := 0
var shield := 0.0
var shielded := false
var hull := 1.0
## What the right bar shows: armour in yellow while any is left, as the top
## gauge's first row does, then the hull.
var plating := 1.0
var armored := false
## 0 off, 1 armed, 2 firing.
var auto_fire := 0
var autopilot := false
func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
func update(cargo_used: int, cargo_capacity: int, health, stats, fire_state: int, piloting: bool) -> void:
	cargo=cargo_used;capacity=cargo_capacity
	shielded=stats.shield>0
	shield=clampf(float(health.shield)/maxi(1,stats.shield),0,1) if shielded else 0.0
	hull=clampf(float(health.hull)/maxf(1.0,health.max_hull),0,1)
	armored=health.armor>0 and stats.armor>0
	plating=clampf(float(health.armor)/stats.armor,0,1) if armored else hull
	auto_fire=fire_state;autopilot=piloting
	queue_redraw()
func bands() -> Array[Rect2]:
	"""What the retro gauges cover, for labels that keep clear of them."""
	var covered: Array[Rect2]=[]
	if not visible:return covered
	for band in [cargo_rect,row_rect]:
		if band.has_area():covered.append(Rect2(get_global_transform()*band.position,band.size))
	return covered
func icon(name: String, area: Rect2, tint: Color) -> void:
	"""A JAR icon at the nearest whole multiple of its pixels to the area,
	centred on it."""
	var texture: Texture2D=imported_art.symbol(name) if imported_art!=null else null
	if texture==null:return
	var source := texture.get_size()
	var scale := maxf(1.0,roundf(minf(area.size.x/source.x,area.size.y/source.y)))
	var shown := source*scale
	draw_texture_rect(texture,Rect2((area.get_center()-shown*.5).round(),shown),false,tint)
func segments(area: Rect2, amount: float, lit: Color) -> void:
	var pitch := 7.0*unit
	var count := maxi(1,int((area.size.x+3.0*unit)/pitch))
	for index in count:
		var on: bool=(index+.5)/count<=amount
		draw_rect(Rect2(area.position+Vector2(index*pitch,0),Vector2(4.0*unit,area.size.y)),lit if on else UNLIT)
func tile(area: Rect2, name: String, lit: bool, tint: Color, bright := false) -> void:
	var edge: Color=tint if lit else Color("2b5566")
	var fill := Color(tint.r*.18,tint.g*.18,tint.b*.18,.82) if lit else Color(.016,.07,.1,.72)
	var glow := Color(tint.r,tint.g,tint.b,.35 if bright else .2) if lit else Color(0,0,0,0)
	draw_style_box(StationTheme.frame(fill,edge,roundi(6*unit),maxi(1,roundi(unit)),glow,roundi((7 if bright else 4)*unit) if lit else 0),area)
	icon(name,area.grow(-3.0*unit),tint if lit else OFF)
func _draw() -> void:
	if cargo_rect.has_area():draw_cargo()
	if row_rect.has_area():draw_row()
func draw_cargo() -> void:
	var area := cargo_rect
	var font := get_theme_default_font()
	var pixels := roundi(area.size.y*.62)
	var reading := tr("%d/%dt")%[cargo,capacity]
	var full: bool=capacity>0 and cargo>=capacity
	var tint: Color=FULL_COLOR if full else CARGO_COLOR
	var side := area.size.y*11.0/13.0
	icon("i_weight",Rect2(area.position,Vector2(side,area.size.y)),tint)
	var box_width := font.get_string_size(reading,HORIZONTAL_ALIGNMENT_LEFT,-1,pixels).x+20.0*unit
	var box := Rect2(Vector2(area.end.x-box_width,area.position.y),Vector2(box_width,area.size.y))
	draw_style_box(StationTheme.frame(Color(.016,.07,.1,.78),Color(tint.r,tint.g,tint.b,.75),roundi(6*unit),maxi(1,roundi(unit))),box)
	var baseline := box.position.y+(box.size.y+font.get_ascent(pixels)-font.get_descent(pixels))*.5
	draw_string_outline(font,Vector2(box.position.x,baseline),reading,HORIZONTAL_ALIGNMENT_CENTER,box.size.x,pixels,maxi(2,roundi(3*unit)),Color(0,.04,.07,.7))
	draw_string(font,Vector2(box.position.x,baseline),reading,HORIZONTAL_ALIGNMENT_CENTER,box.size.x,pixels,palette.text)
	var start := area.position.x+side+8.0*unit
	var bar := Rect2(Vector2(start,area.position.y+area.size.y*.2),Vector2(box.position.x-8.0*unit-start,area.size.y*.6))
	segments(bar,float(cargo)/capacity if capacity>0 else 0.0,tint)
func draw_row() -> void:
	var area := row_rect
	var h := area.size.y
	var gap := 6.0*unit
	var lamps := Rect2(Vector2(area.get_center().x-(h*3+gap*2)*.5,area.position.y),Vector2(h*3+gap*2,h))
	var bar_height := h*.46
	var bar_top := area.position.y+(h-bar_height)*.5
	# Shield on the left, after its icon.
	var side := h*.8*11.0/13.0
	icon("i_shield",Rect2(Vector2(area.position.x,area.position.y+h*.1),Vector2(side,h*.8)),SHIELD_COLOR if shielded else OFF)
	var start := area.position.x+side+8.0*unit
	segments(Rect2(Vector2(start,bar_top),Vector2(lamps.position.x-14.0*unit-start,bar_height)),shield,SHIELD_COLOR)
	# The lamps: auto fire, autopilot, then the hull, which leads its bar.
	tile(Rect2(lamps.position,Vector2(h,h)),"i_autofire",auto_fire>0,palette.value if auto_fire==2 else palette.accent,auto_fire==2)
	tile(Rect2(lamps.position+Vector2(h+gap,0),Vector2(h,h)),"i_autopilot",autopilot,palette.accent)
	var low := hull<=.25
	var tint: Color=LOW_COLOR if low else HULL_COLOR
	var bar_tint: Color=ARMOR_COLOR if armored else tint
	# bd blinks a failing hull.
	var showing: bool=not low or Time.get_ticks_msec()%800<500
	tile(Rect2(lamps.position+Vector2((h+gap)*2,0),Vector2(h,h)),"i_hull",showing,tint,low)
	var right := lamps.end.x+14.0*unit
	segments(Rect2(Vector2(right,bar_top),Vector2(area.end.x-right,bar_height)),plating,bar_tint)
	# bd: a damaged hull's percentage stays on screen, here over the lamp.
	var percent := roundi(hull*100.0)
	if percent<100:
		var font := get_theme_default_font()
		var pixels := roundi(15*unit)
		var reading := "%d%%"%percent
		var at := Vector2(lamps.position.x+(h+gap)*2,area.position.y-6.0*unit)
		draw_string_outline(font,at,reading,HORIZONTAL_ALIGNMENT_CENTER,h,pixels,maxi(2,roundi(3*unit)),Color(0,.04,.07,.7))
		draw_string(font,at,reading,HORIZONTAL_ALIGNMENT_CENTER,h,pixels,Color("ff8a6e") if low else Color("f0c27a"))
