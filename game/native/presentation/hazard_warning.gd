extends Control
## The depth warning: a compact, see-through strip in three cells. The hazard
## sign; what is wrong, the countdown and its bar; and which way to go, with the
## safe depth. Sized to its text, and scaled down rather than wrapped when the
## screen is narrower than that.
const EngineLanguage = preload("res://native/presentation/engine_language.gd")
const Region=preload("res://native/simulation/region.gd")
const HEIGHT := 66.0
const EDGE := Color("5c9fc8")
const TEXT := Color("d6e4ec")
var status: Dictionary={}
var classic := false
var font := SystemFont.new()
var accent := Color("f0895c")
## Once the water is doing damage the countdown has nothing left to say; the
## bar shows the hull instead, so the warning cannot hide how much is left.
var hull_percent := 100
## The width on offer, from the layout.
var room := 0.0
## Drawing scale, below 1 only when the content is wider than the room given.
var fit := 1.0
func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	font.font_names=PackedStringArray(["Share Tech Mono","DejaVu Sans Mono","Liberation Mono","Noto Sans Mono"])
	# Glyphs the monospace face lacks, such as CJK engine text, come from the interface font.
	font.fallbacks=[ThemeDB.fallback_font]
	hide()
static func describe(depth: int, minimum: int, maximum: int, exposure_ms: int) -> Dictionary:
	if depth>=minimum and depth<=maximum:return {}
	var deep := depth>maximum
	return {"kind":"pressure" if deep else "radiation","title":EngineLanguage.translate("Excess pressure").to_upper() if deep else EngineLanguage.translate("Radiation exposure").to_upper(),"action":EngineLanguage.translate("Ascend").to_upper() if deep else EngineLanguage.translate("Descend").to_upper(),"limit":maximum if deep else minimum,"damaging":exposure_ms>Region.PRESSURE_GRACE_MS,"remaining":maxf(0,Region.PRESSURE_GRACE_MS-exposure_ms)/1000.0,"fraction":clampf(float(exposure_ms)/Region.PRESSURE_GRACE_MS,0,1)}
func update(region, allowed: bool, old_ui: bool) -> void:
	status=describe(region.player.depth,region.session.ship.minimum_depth,region.session.ship.maximum_depth,region.pressure_ms)
	classic=old_ui;visible=allowed and not status.is_empty()
	accent=Color("f0895c") if status.get("kind","")=="pressure" else Color("e8bb5a")
	fit_width(size.x if room<=0 else room)
	queue_redraw()
func text_width(value: String, pixels: int) -> float:
	return font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,pixels).x
func content_layout() -> Dictionary:
	"""Positions at full scale: three cells split by rules, sized to the text."""
	if status.is_empty():return {"width":0.0,"height":HEIGHT}
	var damage: String
	if status.damaging:damage=tr("Damage active").to_upper()+" · "+tr("Hull").to_upper()+" %d%%"%maxi(0,hull_percent)
	else:damage=(tr("Damage in %.1f s")%status.remaining).to_upper()
	var safe: String=(tr("Safe depth %s %d")%["≤" if status.kind=="pressure" else "≥",status.limit]).to_upper()
	# Keep the cells steady as the countdown gives way to active damage.
	var damage_width:=maxf(text_width(tr("Damage active").to_upper()+" · "+tr("Hull").to_upper()+" 100%",12),text_width((tr("Damage in %.1f s")%(Region.PRESSURE_GRACE_MS/1000.0)).to_upper(),12))
	var middle:=70.0
	var middle_width:=maxf(150,maxf(text_width(status.title,15),damage_width))
	var divider:=middle+middle_width+16
	var right:=divider+16
	var action_width:=text_width(status.action,22)
	var right_width:=maxf(action_width+28,text_width(safe,12))
	return {"width":right+right_width+20,"height":HEIGHT,"middle":middle,"middle_width":middle_width,"divider":divider,
		"right":right,"arrow":Vector2(right+action_width+18,26),"damage":damage,"safe":safe}
func fit_width(width: float) -> void:
	"""Takes the width on offer; the strip keeps its own and shrinks only to fit."""
	room=width
	var natural: float=content_layout().width
	fit=1.0 if natural<=0 or natural<=width else width/natural
	# Grows about its middle: the layout centres it while it is still empty.
	var before: float=size.x
	size=Vector2(natural,HEIGHT)*fit
	position.x+=(before-size.x)*.5
func text(at: Vector2, value: String, color: Color, pixels: int) -> void:
	draw_string(font,at,value,HORIZONTAL_ALIGNMENT_LEFT,-1,pixels,color)
func _draw() -> void:
	if status.is_empty():return
	var layout:=content_layout()
	draw_set_transform(Vector2.ZERO,0,Vector2(fit,fit))
	var w: float=layout.width;var h:=HEIGHT;var bevel:=0.0 if classic else 12.0
	var outline:=PackedVector2Array([Vector2(bevel,0),Vector2(w-bevel,0),Vector2(w,bevel),Vector2(w,h-bevel),Vector2(w-bevel,h),Vector2(bevel,h),Vector2(0,h-bevel),Vector2(0,bevel),Vector2(bevel,0)])
	draw_colored_polygon(outline,Color(0.02,0.06,0.11,0.78));draw_polyline(outline,EDGE,1.2,true)
	if not classic:
		# Inner corner brackets, as on the station panels.
		for corner in [[Vector2(5,bevel+4),Vector2(5,5+3),Vector2(bevel+4,5)],[Vector2(w-5,bevel+4),Vector2(w-5,8),Vector2(w-bevel-4,5)],
			[Vector2(5,h-bevel-4),Vector2(5,h-8),Vector2(bevel+4,h-5)],[Vector2(w-5,h-bevel-4),Vector2(w-5,h-8),Vector2(w-bevel-4,h-5)]]:
			draw_polyline(PackedVector2Array(corner),Color(EDGE,.55),1.0,true)
	var symbol:=Vector2(31,h*.5)
	if status.kind=="pressure":
		draw_polyline(PackedVector2Array([symbol+Vector2(0,-15),symbol+Vector2(16,13),symbol+Vector2(-16,13),symbol+Vector2(0,-15)]),accent,2.2,true)
		draw_line(symbol+Vector2(0,-6),symbol+Vector2(0,4),accent,2.4,true);draw_circle(symbol+Vector2(0,8.5),1.6,accent)
	else:
		draw_arc(symbol,16,0,TAU,40,accent,1.5,true);draw_circle(symbol,3,accent)
		for wedge in 3:
			var points:=PackedVector2Array()
			var start: float=wedge*TAU/3.0-PI/6
			for i in 13:points.append(symbol+Vector2.from_angle(start+i*PI/36)*14)
			for i in range(12,-1,-1):points.append(symbol+Vector2.from_angle(start+i*PI/36)*6)
			draw_colored_polygon(points,accent)
	var rule:=Color(EDGE,.6)
	draw_line(Vector2(58,12),Vector2(58,h-12),rule,1)
	draw_line(Vector2(layout.divider,12),Vector2(layout.divider,h-12),rule,1)
	var middle: float=layout.middle
	text(Vector2(middle,24),status.title,accent,15)
	var hull_tone:=Color("ff8a6e") if hull_percent<=25 else accent
	text(Vector2(middle,41),layout.damage,hull_tone if status.damaging else TEXT,12)
	var track:=Rect2(middle,48,layout.middle_width,6)
	var filled: float=clampf(hull_percent/100.0,0,1) if status.damaging else status.fraction
	draw_rect(track,Color(0.07,0.15,0.22,0.9))
	if filled>0:draw_rect(Rect2(track.position,Vector2(track.size.x*filled,track.size.y)),hull_tone if status.damaging else accent)
	draw_rect(track,Color(EDGE,.7),false,1)
	var right: float=layout.right
	text(Vector2(right,33),status.action,accent,22)
	var arrow: Vector2=layout.arrow
	var sign_y := -1.0 if status.kind=="pressure" else 1.0
	draw_line(arrow-Vector2(0,10),arrow+Vector2(0,10),accent,2.6,true)
	draw_polyline(PackedVector2Array([arrow+Vector2(-6,sign_y*4),arrow+Vector2(0,sign_y*10),arrow+Vector2(6,sign_y*4)]),accent,2.6,true)
	text(Vector2(right,52),layout.safe,TEXT,12)
