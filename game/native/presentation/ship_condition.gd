extends Control
## Read-only health layers; depleted protection remains distinct from absent gear.
var imported_art
var labels: Array[Label] = []
var bars: Array[ProgressBar] = []
var fills: Array[StyleBoxFlat] = []
var colors := [Color("91ddbc"),Color("91cbe4"),Color("d2be91")]
## The touch layout's two-row gauge: armour and then hull on the first row,
## shield on the second, and the cargo, credits and station line under them.
var compact := false
var info := ""
var compact_fill := [0.0,0.0]
var compact_colors := [Color.WHITE,Color.WHITE]
const ARMOR_COLOR := Color("f0cc4a")
const HULL_COLOR := Color("7ee08e")
const SHIELD_COLOR := Color("5fd0ea")
func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	for index in 3:
		var caption := Label.new(); caption.add_theme_font_size_override("font_size",12); caption.mouse_filter=Control.MOUSE_FILTER_IGNORE
		caption.clip_text=true; add_child(caption); labels.append(caption)
		var bar := ProgressBar.new(); bar.show_percentage=false; bar.mouse_filter=Control.MOUSE_FILTER_IGNORE
		var background := StyleBoxFlat.new(); background.bg_color=Color("1a303bcc")
		var fill := StyleBoxFlat.new(); fill.bg_color=colors[index]
		bar.add_theme_stylebox_override("background",background); bar.add_theme_stylebox_override("fill",fill)
		add_child(bar); bars.append(bar); fills.append(fill)
	resized.connect(layout); layout()
func layout() -> void:
	var width := (size.x-24)/3.0
	for index in labels.size():
		labels[index].position=Vector2(index*(width+12)+26,0); labels[index].size=Vector2(width-26,18)
		bars[index].position=Vector2(index*(width+12),21); bars[index].size=Vector2(width,10); bars[index].hide()
func update(health, stats) -> void:
	var values := [health.hull,health.shield,health.armor]
	var capacities := [stats.hull,stats.shield,stats.armor]
	for index in labels.size():
		var ratio := clampf(float(values[index])/maxi(1,capacities[index]),0,1)
		labels[index].text=["HULL","SHIELD","ARMOR"][index]+(" %d / %d"%[values[index],capacities[index]] if capacities[index]>0 else " —")
		var color: Color = Color("f5a58b") if index==0 and ratio<=0.25 else colors[index]
		if capacities[index]<=0: color=Color("82969e")
		labels[index].modulate=color; fills[index].bg_color=color; bars[index].value=ratio*100
		labels[index].visible=not compact
	# Armour takes a hit before the hull does, so the first row shows it in
	# yellow while any is left and the hull in green once it is gone.
	if health.armor>0 and stats.armor>0:
		compact_fill[0]=clampf(float(health.armor)/stats.armor,0,1);compact_colors[0]=ARMOR_COLOR
	else:
		compact_fill[0]=clampf(float(health.hull)/maxi(1,stats.hull),0,1)
		compact_colors[0]=Color("f5795f") if compact_fill[0]<=.25 else HULL_COLOR
	compact_fill[1]=clampf(float(health.shield)/maxi(1,stats.shield),0,1) if stats.shield>0 else 0.0
	compact_colors[1]=SHIELD_COLOR if stats.shield>0 else Color("5d717a")
	queue_redraw()
func _draw() -> void:
	if compact:draw_compact();return
	var width := (size.x-24)/3.0
	for index in labels.size():
		if imported_art!=null:
			var texture: Texture2D=imported_art.symbol(["i_hull","i_shield","i_hull"][index])
			if texture!=null:draw_texture_rect(texture,Rect2(index*(width+12),0,20,18),false,colors[index])
		for segment in range(0,int(width)-4,7):
			var color: Color=fills[index].bg_color if float(segment)/width<bars[index].value/100.0 else Color("244653")
			draw_rect(Rect2(index*(width+12)+segment,21,4,10),color)
func draw_compact() -> void:
	var width := minf(size.x,190.0)
	for row in 2:
		var y := row*30.0
		if imported_art!=null:
			var texture: Texture2D=imported_art.symbol(["i_hull","i_shield"][row])
			if texture!=null:draw_texture_rect(texture,Rect2(0,y,22,20),false,compact_colors[row])
		var start := 34.0
		var count := int((width-start)/7)
		for segment in count:
			var lit: bool=(segment+.5)/count<=compact_fill[row]
			draw_rect(Rect2(start+segment*7,y+3,4,15),compact_colors[row] if lit else Color("1d3c48cc"))
	var font := get_theme_default_font()
	draw_string_outline(font,Vector2(2,84),info,HORIZONTAL_ALIGNMENT_LEFT,-1,17,4,Color(0,.04,.07,.7))
	draw_string(font,Vector2(2,84),info,HORIZONTAL_ALIGNMENT_LEFT,-1,17,Color("c9e7ea"))
