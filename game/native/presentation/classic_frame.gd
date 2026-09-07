extends Control
## Responsive instruments using the owner's imported symbols and independent layout.
var imported_art
var cargo_fraction := 0.0
var throttle_fraction := 0.0
var throttle_caption := Label.new()
var cargo_caption := Label.new()
func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	for caption in [throttle_caption,cargo_caption]:
		add_child(caption);caption.add_theme_font_size_override("font_size",14)
		caption.modulate=Color("9ddbea");caption.mouse_filter=Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
func update(player, ship, speed: int) -> void:
	cargo_fraction=clampf(float(ship.cargo_used)/maxf(1,ship.capacity()),0,1)
	throttle_fraction=float(player.throttle)/100.0
	cargo_caption.text="%d / %d"%[ship.cargo_used,ship.capacity()]
	cargo_caption.position=Vector2(240,22)
	throttle_caption.text="THRUST %d%%   TIME %d×"%[player.throttle,speed]
	throttle_caption.position=Vector2(size.x*.5+10,size.y-118)
	queue_redraw()
func rail(rect: Rect2, amount: float) -> void:
	draw_rect(rect.grow(3),Color("04131dcc"))
	var count := int(rect.size.x/7)
	for index in count:
		draw_rect(Rect2(rect.position+Vector2(index*7,0),Vector2(4,rect.size.y)),Color("7ad4e5") if float(index)/count<amount else Color("244653"))
func symbol(path: String, rect: Rect2) -> void:
	if imported_art==null:return
	var texture: Texture2D=imported_art.symbol(path)
	if texture!=null:draw_texture_rect(texture,rect,false,Color("9ddbea"))
func _draw() -> void:
	symbol("i_weight",Rect2(26,22,24,24))
	rail(Rect2(62,26,164,14),cargo_fraction)
	rail(Rect2(size.x*.5+10,size.y-95,200,6),throttle_fraction)
