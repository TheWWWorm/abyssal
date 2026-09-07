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
const OCEAN_DEPTH := 50000.0
func gauge_rect() -> Rect2:
	return Rect2(size.x-48,size.y*.24,18,size.y*.46)
func layout() -> void:
	var gauge := gauge_rect()
	depth_label.position=Vector2(size.x-168,gauge.position.y-52); depth_label.size=Vector2(144,46)
	depth_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	depth_bar.hide()
	boost_label.position=Vector2(size.x*.5-220,size.y-118); boost_label.size=Vector2(260,20)
	boost_bar.position=boost_label.position+Vector2(0,23); boost_bar.size=Vector2(170,6)
	queue_redraw()
func _draw() -> void:
	var gauge := gauge_rect()
	draw_rect(gauge.grow(5),Color("04131dcc"))
	for step in 50:
		var depth := (step+.5)*OCEAN_DEPTH/50.0
		var safe := depth>=safe_minimum and depth<=safe_maximum
		var y := gauge.position.y+step*gauge.size.y/50.0
		draw_rect(Rect2(gauge.position.x,y,gauge.size.x,gauge.size.y/50.0-2),Color("59c9dc") if safe else Color("244653"))
		if step%5==0: draw_line(Vector2(gauge.position.x-7,y),Vector2(gauge.position.x-2,y),Color("6093a3"))
	for limit in [safe_minimum,safe_maximum]:
		var y := gauge.position.y+clampf(limit/OCEAN_DEPTH,0,1)*gauge.size.y
		draw_line(Vector2(gauge.position.x-14,y),Vector2(gauge.end.x+5,y),Color("72dae8"),1)
		var caption := ("MIN " if limit==safe_minimum else "MAX ")+str(int(limit))
		draw_string(ThemeDB.fallback_font,Vector2(gauge.position.x-102,y+(-6 if limit==safe_minimum else 16)),caption,HORIZONTAL_ALIGNMENT_RIGHT,82,12,Color("91d5df"))
	var cursor_y := gauge.position.y+clampf(current_depth/OCEAN_DEPTH,0,1)*gauge.size.y
	var color := Color("f0b665") if warning else Color("d0faff")
	draw_colored_polygon(PackedVector2Array([Vector2(gauge.position.x-2,cursor_y),Vector2(gauge.position.x-13,cursor_y-6),Vector2(gauge.position.x-13,cursor_y+6)]),color)
	draw_line(Vector2(gauge.position.x,cursor_y),Vector2(gauge.end.x+3,cursor_y),color,2)
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
	boost_bar.visible=boost.mode!="absent"; boost_bar.value=boost.fraction*100
	var boost_color := Color("8ce6df") if boost.mode in ["ready","active"] else Color("8a9da8")
	boost_label.modulate=boost_color; boost_fill.bg_color=boost_color
