extends PanelContainer
## Restrained instrument bezel; focus and content carry the hierarchy.
var decorated := true
func _ready() -> void: resized.connect(queue_redraw)
func _draw() -> void:
	if not decorated:return
	draw_rect(Rect2(Vector2(4,4),size-Vector2(8,8)),Color("204b60"),false,1)
