extends Control
## Live instrument based on art/hazards/warning-reference.png.
const EngineLanguage = preload("res://native/presentation/engine_language.gd")
const Region=preload("res://native/simulation/region.gd")
var status: Dictionary={}
var classic := false
var font := SystemFont.new()
var accent := Color("e9977d")
func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	font.font_names=PackedStringArray(["Nimbus Sans Narrow","Liberation Sans Narrow"])
	# Glyphs the narrow face lacks, such as CJK engine text, come from the interface font.
	font.fallbacks=[ThemeDB.fallback_font]
	hide()
static func describe(depth: int, minimum: int, maximum: int, exposure_ms: int) -> Dictionary:
	if depth>=minimum and depth<=maximum:return {}
	var deep := depth>maximum
	return {"kind":"pressure" if deep else "radiation","title":EngineLanguage.translate("Excess pressure").to_upper() if deep else EngineLanguage.translate("Radiation exposure").to_upper(),"action":EngineLanguage.translate("Ascend").to_upper() if deep else EngineLanguage.translate("Descend").to_upper(),"limit":maximum if deep else minimum,"damaging":exposure_ms>Region.PRESSURE_GRACE_MS,"remaining":maxf(0,Region.PRESSURE_GRACE_MS-exposure_ms)/1000.0,"fraction":clampf(float(exposure_ms)/Region.PRESSURE_GRACE_MS,0,1)}
func update(region, allowed: bool, old_ui: bool) -> void:
	status=describe(region.player.depth,region.session.ship.minimum_depth,region.session.ship.maximum_depth,region.pressure_ms)
	classic=old_ui;visible=allowed and not status.is_empty()
	accent=Color("e9977d") if status.get("kind","")=="pressure" else Color("e6b85b")
	fit_width(size.x)
	queue_redraw()
func text_width(value: String, pixels: int) -> float:
	return font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,pixels).x
func content_layout() -> Dictionary:
	if status.is_empty():return {"height":108.0}
	var damage: String=tr("Damage active").to_upper() if status.damaging else (tr("Damage in %.1f s")%status.remaining).to_upper()
	var safe: String=(tr("Safe depth %s %d")%["≤" if status.kind=="pressure" else "≥",status.limit]).to_upper()
	var exposure: String=tr("Exposure").to_upper()
	# Keep the columns steady as the countdown gives way to active damage.
	var damage_width:=maxf(text_width(tr("Damage active").to_upper(),16),text_width((tr("Damage in %.1f s")%(Region.PRESSURE_GRACE_MS/1000.0)).to_upper(),16))
	var left_width:=maxf(text_width(status.title,19),damage_width)
	var action_width:=text_width(status.action,27)
	var right_width:=maxf(action_width+35,text_width(safe,14))
	var stacked:=88+left_width+28+right_width+22>size.x
	var right:=22.0 if stacked else clampf(size.x*.53,88+left_width+28,size.x-22-right_width)
	var offset:=64.0 if stacked else 0.0
	return {"height":172.0 if stacked else 108.0,"stacked":stacked,"right":right,"offset":offset,
		"arrow":Vector2(right+action_width+21,30+offset),"damage":damage,"safe":safe,"exposure":exposure,
		"track_left":maxf(88,22+text_width(exposure,11)+12)}
func fit_width(width: float) -> void:
	size.x=width;size.y=content_layout().height
func text(at: Vector2, value: String, color: Color, pixels: int) -> void:
	draw_string(font,at,value,HORIZONTAL_ALIGNMENT_LEFT,-1,pixels,color)
func _draw() -> void:
	if status.is_empty():return
	var w:=size.x;var h:=size.y;var bevel:=0.0 if classic else 9.0
	var outline:=PackedVector2Array([Vector2(bevel,0),Vector2(w-bevel,0),Vector2(w,bevel),Vector2(w,h-bevel),Vector2(w-bevel,h),Vector2(bevel,h),Vector2(0,h-bevel),Vector2(0,bevel),Vector2(bevel,0)])
	draw_colored_polygon(outline,Color("06151cf5"));draw_polyline(outline,Color("a58b58"),1.0,true)
	if not classic:
		draw_rect(Rect2(5,5,w-10,h-10),Color("7d704344"),false,1)
		for point in [Vector2(10,10),Vector2(w-10,10),Vector2(10,h-10),Vector2(w-10,h-10)]:
			draw_circle(point,3,Color("020b10"));draw_line(point-Vector2(1,1),point+Vector2(1,1),Color("9b885c"),1,true)
	var symbol:=Vector2(38,43)
	if status.kind=="pressure":
		draw_polyline(PackedVector2Array([symbol+Vector2(0,-22),symbol+Vector2(22,19),symbol+Vector2(-22,19),symbol+Vector2(0,-22)]),accent,2.0,true)
		text(symbol+Vector2(-3,12),"!",accent,30)
	else:
		draw_arc(symbol,23,0,TAU,40,accent,1.5,true);draw_circle(symbol,4,accent)
		for wedge in 3:
			var points:=PackedVector2Array()
			var start: float=wedge*TAU/3.0-PI/6
			for i in 13:points.append(symbol+Vector2.from_angle(start+i*PI/36)*20)
			for i in range(12,-1,-1):points.append(symbol+Vector2.from_angle(start+i*PI/36)*8)
			draw_colored_polygon(points,accent)
	draw_line(Vector2(74,18),Vector2(74,71),Color("86744877"),1)
	text(Vector2(88,32),status.title,accent,19)
	var layout:=content_layout()
	text(Vector2(88,59),layout.damage,accent,16)
	var right: float=layout.right;var offset: float=layout.offset
	if layout.stacked:draw_line(Vector2(22,75),Vector2(w-22,75),Color("86744877"),1)
	else:draw_line(Vector2(right-14,18),Vector2(right-14,71),Color("86744877"),1)
	text(Vector2(right,38+offset),status.action,accent,27)
	var arrow: Vector2=layout.arrow
	var sign_y := -1.0 if status.kind=="pressure" else 1.0
	draw_line(arrow-Vector2(0,14),arrow+Vector2(0,14),accent,2,true)
	draw_polyline(PackedVector2Array([arrow+Vector2(-7,sign_y*6),arrow+Vector2(0,sign_y*14),arrow+Vector2(7,sign_y*6)]),accent,2,true)
	text(Vector2(right,61+offset),layout.safe,Color("bbd5c4"),14)
	text(Vector2(22,h-18),layout.exposure,Color("a3ac8d"),11)
	var track:=Rect2(layout.track_left,h-27,w-layout.track_left-22,8)
	draw_rect(track,Color("203131"));draw_rect(Rect2(track.position,Vector2(track.size.x*status.fraction,track.size.y)),accent)
	draw_rect(track,Color("9f8a55"),false,1)
