extends Control
var label := Label.new()
var description := Label.new()
var range_text := preload("res://native/presentation/range_text.gd").new()
var text := ""
var hull := ProgressBar.new()
var fill := StyleBoxFlat.new()
var current_color := Color.TRANSPARENT
var symbol_direction := Vector2.ZERO
const ICON_WIDTH := 16.0
var enemy_ring := false
var edge_square := false
var ring_center := Vector2.ZERO
var ring_radius := 18.0
func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	for line in [label,description]:
		line.add_theme_font_size_override("font_size",13); line.mouse_filter=Control.MOUSE_FILTER_IGNORE; add_child(line)
	add_child(range_text)
	hull.size=Vector2(62,4)
	hull.show_percentage=false; hull.mouse_filter=Control.MOUSE_FILTER_IGNORE; add_child(hull)
	var background := StyleBoxFlat.new(); background.bg_color=Color("041219cc"); hull.add_theme_stylebox_override("background",background)
	hull.add_theme_stylebox_override("fill",fill)
	hull.size=Vector2(62,4)
func display(prefix: String, distance: String, detail: String, color: Color, percentage: float) -> void:
	enemy_ring=false;edge_square=false;label.show();range_text.show()
	text=prefix+distance+detail
	if label.text!=prefix:
		label.text=prefix; label.size=label.get_minimum_size()
	var detail_text := detail.trim_prefix("\n")
	if description.text!=detail_text:
		description.text=detail_text; description.size=description.get_minimum_size()
	description.visible=not detail.is_empty()
	range_text.display(distance,color); label.position.x=ICON_WIDTH
	range_text.position=Vector2(ICON_WIDTH+label.size.x,0)
	description.position=Vector2(ICON_WIDTH,label.size.y+label.get_theme_constant("line_spacing"))
	var text_height: float = description.position.y+description.size.y if description.visible else label.size.y
	var text_width := ICON_WIDTH+maxf(label.size.x+range_text.size.x,description.size.x if description.visible else 0)
	if current_color!=color:
		current_color=color
		for line in [label,description]: line.add_theme_color_override("font_color",color)
		fill.bg_color=color
	hull.visible=percentage>=0
	if hull.visible:
		hull.value=percentage
		hull.position=Vector2(ICON_WIDTH,text_height+2)
	size=Vector2(maxf(text_width,62 if hull.visible else 0),text_height+(6 if hull.visible else 0))
	queue_redraw();show()

func track_enemy(anchor: Vector2, radius: float, offscreen: bool, captions: bool=true) -> void:
	enemy_ring=not offscreen;edge_square=offscreen;ring_center=anchor-position;ring_radius=radius
	if offscreen or not captions:
		label.hide();description.hide();range_text.hide();hull.hide()
	if offscreen:size=Vector2(14,14)
	queue_redraw()

func set_symbol(direction: Vector2) -> void:
	if symbol_direction==direction:return
	symbol_direction=direction;queue_redraw()
func _draw() -> void:
	if edge_square:
		draw_rect(Rect2(3,3,8,8),Color("091318dd"));draw_rect(Rect2(3,3,8,8),current_color,false,2);return
	if enemy_ring:
		draw_arc(ring_center,ring_radius,0,TAU,48,current_color,1.5,true)
		for angle in [0.0,PI*.5,PI,PI*1.5]:
			var direction:=Vector2.from_angle(angle);draw_line(ring_center+direction*ring_radius,ring_center+direction*(ring_radius+4),current_color,1.5,true)
		return
	var center:=Vector2(6,8)
	if symbol_direction==Vector2.ZERO:
		draw_polyline(PackedVector2Array([center+Vector2(0,-4),center+Vector2(4,0),center+Vector2(0,4),center+Vector2(-4,0),center+Vector2(0,-4)]),current_color,1.3,true)
	else:
		var direction:=symbol_direction.normalized();var side:=Vector2(-direction.y,direction.x)
		draw_polyline(PackedVector2Array([center-direction*3+side*4,center+direction*4,center-direction*3-side*4]),current_color,1.5,true)
