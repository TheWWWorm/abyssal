extends PanelContainer
## Restrained instrument bezel; focus and content carry the hierarchy.
var decorated := true
func _ready() -> void:
	resized.connect(queue_redraw)
	# Menu movement stays within the panel (focus_map.gd).
	set_meta("focus_scope",true)
func _draw() -> void:
	if not decorated:return
	draw_rect(Rect2(Vector2(4,4),size-Vector2(8,8)),Color("204b60"),false,1)
