extends Control
## Read-only flight status. Depth values use the same units as the atlas.
var depth_label := Label.new()
var boost_label := Label.new()
var depth_bar := ProgressBar.new()
var boost_bar := ProgressBar.new()
var depth_fill := StyleBoxFlat.new()
var boost_fill := StyleBoxFlat.new()
var warning := false
var pressure_strength := 0.0
func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	for label in [depth_label,boost_label]:
		label.add_theme_font_size_override("font_size",13); label.mouse_filter=Control.MOUSE_FILTER_IGNORE; label.clip_text=true; add_child(label)
	for bar in [depth_bar,boost_bar]:
		bar.show_percentage=false; bar.mouse_filter=Control.MOUSE_FILTER_IGNORE; add_child(bar)
		var background := StyleBoxFlat.new(); background.bg_color=Color("19303b"); bar.add_theme_stylebox_override("background",background)
	depth_bar.add_theme_stylebox_override("fill",depth_fill); boost_bar.add_theme_stylebox_override("fill",boost_fill)
	resized.connect(layout); layout()
var current_depth := 0.0
var safe_minimum := 0.0
var safe_maximum := 0.0
## Set by the touch layout: a short gauge under its pause and map buttons.
var compact_rect := Rect2()
func gauge_rect() -> Rect2:
	if compact_rect.size.x>0: return compact_rect
	return Rect2(size.x-48,size.y*.24,18,size.y*.46)
func layout() -> void:
	var gauge := gauge_rect()
	depth_label.position=Vector2(size.x-168,gauge.position.y-52); depth_label.size=Vector2(144,46)
	if compact_rect.size.x>0: depth_label.position=Vector2(gauge.end.x-150,gauge.position.y-50);depth_label.size=Vector2(154,46)
	depth_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	depth_bar.hide()
	boost_label.position=Vector2(size.x*.5-220,size.y-118); boost_label.size=Vector2(260,20)
	boost_bar.position=boost_label.position+Vector2(0,23); boost_bar.size=Vector2(170,6)
	boost_label.visible=compact_rect.size.x<=0
	queue_redraw()
func scale_range() -> Vector2:
	"""The depths the gauge spans: the hull's safe band with a short margin of
	danger either side, stretched to keep the ship on it when it is outside."""
	var margin := maxf(1500.0,(safe_maximum-safe_minimum)*.25)
	return Vector2(minf(safe_minimum-margin,current_depth),maxf(safe_maximum+margin,current_depth))
func depth_y(depth: float, gauge: Rect2, span: Vector2) -> float:
	return gauge.position.y+clampf((depth-span.x)/maxf(1,span.y-span.x),0,1)*gauge.size.y
func _draw() -> void:
	var gauge := gauge_rect()
	var compact := compact_rect.size.x>0
	var span := scale_range()
	var steps := 30 if compact else 50
	if not compact: draw_rect(gauge.grow(5),Color("04131dcc"))
	for step in steps:
		var depth := span.x+(step+.5)*(span.y-span.x)/steps
		var safe := depth>=safe_minimum and depth<=safe_maximum
		var y := gauge.position.y+step*gauge.size.y/steps
		draw_rect(Rect2(gauge.position.x,y,gauge.size.x,maxf(1,gauge.size.y/steps-2)),Color("59c9dc") if safe else Color("8c3a3acc"))
	# The rail beside the gauge, red past the limits.
	var rail_x := gauge.end.x+5
	draw_line(Vector2(rail_x,gauge.position.y),Vector2(rail_x,gauge.end.y),Color("6093a3"),2)
	for limit in [safe_minimum,safe_maximum]:
		var y := depth_y(limit,gauge,span)
		draw_line(Vector2(rail_x,gauge.position.y if limit==safe_minimum else y),Vector2(rail_x,y if limit==safe_minimum else gauge.end.y),Color("e0524a"),2)
		draw_line(Vector2(gauge.position.x-(8 if compact else 14),y),Vector2(gauge.position.x-2,y),Color("72dae8"),1)
		var caption := str(int(limit)) if compact else ("MIN " if limit==safe_minimum else "MAX ")+str(int(limit))
		draw_string(ThemeDB.fallback_font,Vector2(gauge.position.x-(96 if compact else 102),y+(4 if compact else (-6 if limit==safe_minimum else 16))),caption,HORIZONTAL_ALIGNMENT_RIGHT,82,13 if compact else 12,Color("91d5df"))
	var cursor_y := depth_y(current_depth,gauge,span)
	var color := Color("f0b665") if warning else Color("d0faff")
	draw_colored_polygon(PackedVector2Array([Vector2(rail_x+3,cursor_y),Vector2(rail_x+13,cursor_y-7),Vector2(rail_x+13,cursor_y+7)]),color)
	draw_line(Vector2(gauge.position.x,cursor_y),Vector2(gauge.end.x+3,cursor_y),color,2)
	if warning:
		# A warning sign beside the gauge's foot while the hull is out of its band.
		var sign := Vector2(gauge.position.x-26,gauge.end.y+20)
		draw_colored_polygon(PackedVector2Array([sign+Vector2(0,-11),sign+Vector2(11,8),sign+Vector2(-11,8)]),Color("e0524a"))
		draw_string(ThemeDB.fallback_font,sign+Vector2(-6,7),"!",HORIZONTAL_ALIGNMENT_CENTER,12,14,Color("1a0606"))
static func boost_state(player) -> Dictionary:
	if player.stats.boost_cooldown<=0: return {"mode":"absent","fraction":0.0,"seconds":0.0}
	if player.boost_active:
		var remaining: int = maxi(0,player.stats.boost_duration-player.boost_timer)
		return {"mode":"active","fraction":float(remaining)/maxi(1,player.stats.boost_duration),"seconds":remaining/1000.0}
	if player.boost_timer<0:
		return {"mode":"charging","fraction":clampf(1.0+float(player.boost_timer)/player.stats.boost_cooldown,0,1),"seconds":-player.boost_timer/1000.0}
	return {"mode":"ready","fraction":1.0,"seconds":0.0}
func update(region, boost_key: String) -> void:
	var player=region.player; var stats=player.stats
	warning=player.depth<stats.minimum_depth or player.depth>stats.maximum_depth
	var condition := "RADIATION · DESCEND" if player.depth<stats.minimum_depth else "PRESSURE · ASCEND"
	current_depth=player.depth; safe_minimum=stats.minimum_depth; safe_maximum=stats.maximum_depth
	depth_label.text="DEPTH\n%d m"%player.depth
	depth_label.tooltip_text="%s %d–%d m"%[condition if warning else "Safe depth",stats.minimum_depth,stats.maximum_depth]
	queue_redraw()
	var color := (Color("e6b85b") if player.depth<stats.minimum_depth else Color("e9977d")) if warning else Color("8fbfc8")
	depth_label.modulate=color; depth_fill.bg_color=color
	depth_bar.value=clampf(float(player.depth-stats.minimum_depth)/maxi(1,stats.maximum_depth-stats.minimum_depth)*100.0,0,100)
	pressure_strength=(0.12+0.24*clampf(float(region.pressure_ms)/5000,0,1)) if warning else 0.0
	var boost := boost_state(player)
	match boost.mode:
		"absent": boost_label.text="BOOST · Not installed"
		"active": boost_label.text="BOOSTING · %.1f s"%boost.seconds
		"charging": boost_label.text="BOOST · Recharging %.1f s"%boost.seconds
		"ready": boost_label.text="BOOST READY · "+boost_key
	# On touch the boost button shows its own charge.
	boost_bar.visible=boost.mode!="absent" and compact_rect.size.x<=0; boost_bar.value=boost.fraction*100
	var boost_color := Color("8ce6df") if boost.mode in ["ready","active"] else Color("8a9da8")
	boost_label.modulate=boost_color; boost_fill.bg_color=boost_color
