extends ColorRect
## A short black cover over a change of place. The dive is never held up for it:
## the swap has already landed by the time the cover appears, so steering, the
## simulation and the save all behave exactly as they did without it. What the
## cover hides is the single frame on which every piece of scenery changes at
## once, and the build stall that follows it.
const UNCOVER := 0.38

static func uncover(parent: Control, seconds: float=UNCOVER) -> void:
	"""Covers the frame a swap has already landed on, then lifts the cover."""
	if parent==null or not parent.is_inside_tree(): return
	var node = new()
	node.color=Color(0,0,0,1)
	# Never in the way of a finger or a cursor: the player is still flying.
	node.mouse_filter=Control.MOUSE_FILTER_IGNORE
	# Above the instruments and the notice, which belong to the place being left.
	node.z_index=60
	parent.add_child(node)
	node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Reach past an interface inset from a phone's notch to the screen's edges.
	node.offset_left=-parent.offset_left;node.offset_right=-parent.offset_right
	node.offset_top=-parent.offset_top;node.offset_bottom=-parent.offset_bottom
	node.lift(seconds)

func lift(seconds: float) -> void:
	if not is_inside_tree(): queue_free(); return
	var tween := create_tween()
	tween.tween_property(self,"color:a",0.0,maxf(.01,seconds))
	tween.tween_callback(queue_free)
