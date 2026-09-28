extends Node
## Drag anywhere inside a list to scroll it, not only on the narrow scroll bar.
## Rows are buttons, and a button consumes the touch before the ScrollContainer
## can start its own drag, so the gesture is tracked here instead. Once the
## finger has clearly travelled the press is cancelled, which keeps a scroll
## from activating whichever row it started on.
##
## The host may name the list (scroll); otherwise, and for any other list
## on screen, the list under the finger is the one it drags. The title's
## settings and help pages have no host to name theirs.
##
## The same holds for any drag on any page, list or not: a finger that lands
## on a button and travels is dragging the screen, not pressing the button.
## The press is cancelled by moving the emulated pointer off the button rather
## than by swallowing the release. Swallowing it leaves the interface holding
## the button as the pointer's owner, and the next tap anywhere then lands on
## that button instead of where it was made.
const THRESHOLD := 10.0
const STOP_SPEED := 12.0
const FRICTION := 1800.0

var scroll: ScrollContainer
## The list the current finger, or the coasting after it, moves.
var target: ScrollContainer
var gesture_control: Control
var finger := -1
var travelled := 0.0
var scrolling := false
var last := Vector2.ZERO
var velocity := 0.0
## The emulated pointer's current press, and whether it has become a drag.
var pointer_down := false
var pointer_from := Vector2.ZERO
var pointer_dragged := false
var pointer_guarded := false
## Far outside every control: a press ending here is a press let go elsewhere.
const AWAY := Vector2(-100000,-100000)

static func shown(list) -> bool:
	# Pages rebuild their lists; a freed one is simply gone.
	return is_instance_valid(list) and list is ScrollContainer and list.is_visible_in_tree()
func usable() -> bool:
	return shown(target)
func release() -> void:
	finger=-1;scrolling=false;velocity=0.0;target=null
func gesture_at(point: Vector2) -> bool:
	# Controls with their own gestures, such as the atlas, keep their input.
	return gesture_control!=null and is_instance_valid(gesture_control) and gesture_control.is_visible_in_tree() and gesture_control.get_global_rect().has_point(point)
func list_at(point: Vector2) -> ScrollContainer:
	"""The named list when the finger is on it, else the innermost list
	under the finger that can scroll vertically."""
	if gesture_at(point):return null
	if shown(scroll) and scroll.get_global_rect().has_point(point):return scroll
	var hit := control_at(get_tree().root,point)
	while hit!=null:
		if hit is ScrollContainer and hit.vertical_scroll_mode!=ScrollContainer.SCROLL_MODE_DISABLED and hit.get_global_rect().has_point(point):
			var bar: VScrollBar=hit.get_v_scroll_bar()
			if bar.max_value>bar.page:return hit
		hit=hit.get_parent() as Control
	return null
func _process(delta: float) -> void:
	if not usable() or finger>=0:return
	if absf(velocity)<STOP_SPEED:velocity=0.0;return
	target.scroll_vertical-=int(round(velocity*delta))
	velocity=move_toward(velocity,0.0,FRICTION*delta)
func _input(event: InputEvent) -> void:
	guard_pointer(event)
	if event is InputEventScreenTouch:
		if event.pressed:
			if finger<0:
				var list := list_at(event.position)
				if list!=null:
					target=list;finger=event.index;last=event.position;travelled=0.0;scrolling=false;velocity=0.0
				elif event.index==0:
					velocity=0.0
		elif event.index==finger:
			finger=-1
			if scrolling:get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and event.index==finger:
		if not usable():
			release();return
		var step: Vector2=event.position-last
		last=event.position
		travelled+=absf(step.y)
		if travelled>THRESHOLD:scrolling=true
		if scrolling:
			target.scroll_vertical-=int(round(step.y))
			velocity=step.y*60.0
			get_viewport().set_input_as_handled()
	elif scrolling and event is InputEventMouseButton and not event.pressed:
		# guard_pointer has already taken the emulated release off the row.
		scrolling=false
func guard_pointer(event: InputEvent) -> void:
	"""Follows the emulated pointer that touch produces. Once it has
	travelled, its motion and its release are moved away from the button it
	pressed, so the button lets go without firing."""
	if not event is InputEventMouse or event.device!=InputEvent.DEVICE_ID_EMULATION:return
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		if event.pressed:
			pointer_down=true;pointer_dragged=false;pointer_from=event.position
			pointer_guarded=pressed_button(event.position)
			return
		if pointer_down and (pointer_dragged or scrolling) and pointer_guarded:move_away(event)
		pointer_down=false;pointer_dragged=false
	elif event is InputEventMouseMotion and pointer_down:
		if event.position.distance_to(pointer_from)>THRESHOLD:pointer_dragged=true
		if (pointer_dragged or scrolling) and pointer_guarded:move_away(event)
func move_away(event: InputEventMouse) -> void:
	event.position=AWAY;event.global_position=AWAY
func pressed_button(point: Vector2) -> bool:
	"""Whether the press landed on a button. Sliders, text fields and the
	chart's own gestures follow the finger, so their drags are left alone."""
	var hit := control_at(get_tree().root,point)
	while hit!=null:
		if hit is BaseButton:return true
		hit=hit.get_parent() as Control
	return false
static func control_at(node: Node, point: Vector2) -> Control:
	"""The topmost visible control under a point that takes the pointer."""
	if node is CanvasItem and not node.is_visible_in_tree():return null
	for index in range(node.get_child_count()-1,-1,-1):
		var found := control_at(node.get_child(index),point)
		if found!=null:return found
	if node is Control and node.mouse_filter!=Control.MOUSE_FILTER_IGNORE and node.get_global_rect().has_point(point):return node
	return null
