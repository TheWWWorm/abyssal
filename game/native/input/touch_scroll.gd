extends Node
## Drag anywhere inside a list to scroll it, not only on the narrow scroll bar.
## Rows are buttons, and a button consumes the touch before the ScrollContainer
## can start its own drag, so the gesture is tracked here instead. Once the
## finger has clearly travelled the press is cancelled, which keeps a scroll
## from activating whichever row it started on.
const THRESHOLD := 10.0
const STOP_SPEED := 12.0
const FRICTION := 1800.0

var scroll: ScrollContainer
var gesture_control: Control
var finger := -1
var travelled := 0.0
var scrolling := false
var last := Vector2.ZERO
var velocity := 0.0

func usable() -> bool:
	return scroll!=null and is_instance_valid(scroll) and scroll.is_visible_in_tree()
func release() -> void:
	finger=-1;scrolling=false;velocity=0.0
func owns(point: Vector2) -> bool:
	if not scroll.get_global_rect().has_point(point):return false
	# Controls with their own gestures, such as the atlas, keep their input.
	if gesture_control!=null and is_instance_valid(gesture_control) and gesture_control.is_visible_in_tree():
		if gesture_control.get_global_rect().has_point(point):return false
	return true
func _process(delta: float) -> void:
	if not usable() or finger>=0:return
	if absf(velocity)<STOP_SPEED:velocity=0.0;return
	scroll.scroll_vertical-=int(round(velocity*delta))
	velocity=move_toward(velocity,0.0,FRICTION*delta)
func _input(event: InputEvent) -> void:
	if not usable():
		release();return
	if event is InputEventScreenTouch:
		if event.pressed:
			if finger<0 and owns(event.position):
				finger=event.index;last=event.position;travelled=0.0;scrolling=false;velocity=0.0
		elif event.index==finger:
			finger=-1
			if scrolling:get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and event.index==finger:
		var step: Vector2=event.position-last
		last=event.position
		travelled+=absf(step.y)
		if travelled>THRESHOLD:scrolling=true
		if scrolling:
			scroll.scroll_vertical-=int(round(step.y))
			velocity=step.y*60.0
			get_viewport().set_input_as_handled()
	elif scrolling and (event is InputEventMouseButton or event is InputEventMouseMotion):
		# The same finger also arrives as emulated mouse input, which would press
		# the row underneath it. Swallow that for the rest of the gesture.
		get_viewport().set_input_as_handled()
		if event is InputEventMouseButton and not event.pressed:scrolling=false
