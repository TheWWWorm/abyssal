extends Control
## Read-only health layers; depleted protection remains distinct from absent gear.
var imported_art
var labels: Array[Label] = []
var bars: Array[ProgressBar] = []
var fills: Array[StyleBoxFlat] = []
var colors := [Color("91ddbc"),Color("91cbe4"),Color("d2be91")]
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

	queue_redraw()
func _draw() -> void:
	var width := (size.x-24)/3.0
	for index in labels.size():
		if imported_art!=null:
			var texture: Texture2D=imported_art.symbol(["i_hull","i_shield","i_hull"][index])
			if texture!=null:draw_texture_rect(texture,Rect2(index*(width+12),0,20,18),false,colors[index])
		for segment in range(0,int(width)-4,7):
			var color: Color=fills[index].bg_color if float(segment)/width<bars[index].value/100.0 else Color("244653")
			draw_rect(Rect2(index*(width+12)+segment,21,4,10),color)
