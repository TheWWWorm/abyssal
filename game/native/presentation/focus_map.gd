extends RefCounted
## Keyboard and gamepad movement between buttons by where they are drawn.
## Godot's own search measures from the nearest edges, so in a two-column
## grid under a full-width button, Right from the left cell went up to the
## wide button instead of across to its neighbour. Whenever a control takes
## focus, its four neighbours are set to the nearest control that lies wholly
## on that side, preferring one level with it; with nothing there, focus stays.
## A neighbour a page sets itself is kept.

## Panels whose controls are searched together; outside one, the topmost
## control holding the focused one.
const SCOPE_META := "focus_scope"
const AUTO_META := "focus_map_sides"
## Overlap tolerated before a control no longer counts as beside another.
const SLACK := 4.0
## How much being out of line weighs against being further away.
const MISALIGNMENT := 3.0

## Wires a viewport: neighbours on each change of focus, and again as a
## direction is pressed (call from the scene's _input), since a list may have
## scrolled since.
static func attach(viewport: Viewport) -> void:
	if not viewport.gui_focus_changed.is_connected(wire):viewport.gui_focus_changed.connect(wire)

static func before_move(viewport: Viewport, event: InputEvent) -> void:
	if not event.is_pressed():return
	for action in ["ui_up","ui_down","ui_left","ui_right"]:
		if event.is_action(action):
			var focused: Control=viewport.gui_get_focus_owner()
			if focused!=null:place(focused)
			return

static func wire(control: Control) -> void:
	place(control)
	# A list follows its focused row only after this; measure again once it has.
	if control==null or not control.is_inside_tree():return
	await control.get_tree().process_frame
	if is_instance_valid(control) and control.has_focus():place(control)

static func place(control: Control) -> void:
	if control==null or not control.is_inside_tree():return
	var scope := scope_of(control)
	var candidates: Array[Control]=[]
	collect(scope,control,candidates)
	var own := control.get_global_rect()
	var list := scroller(control)
	var automatic: Array=control.get_meta(AUTO_META,[])
	for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:
		if not control.get_focus_neighbor(side).is_empty() and side not in automatic:continue
		# Within a scrolling list its own rows come first, wherever they are
		# scrolled to; anything outside it is measured where it shows.
		var best: Control=null;var best_score := INF;var best_inside := false
		for other in candidates:
			var rect := shown(other,control)
			if not rect.has_area():continue
			var score := distance(own,rect,side)
			if score==INF:continue
			var inside: bool=list!=null and list.is_ancestor_of(other)
			if (inside and not best_inside) or (inside==best_inside and score<best_score):best_score=score;best=other;best_inside=inside
		control.set_focus_neighbor(side,control.get_path_to(best if best!=null else control))
		if side not in automatic:automatic.append(side)
	control.set_meta(AUTO_META,automatic)

static func scroller(control: Control) -> ScrollContainer:
	var node: Node=control.get_parent()
	while node!=null and node is Control:
		if node is ScrollContainer:return node
		node=node.get_parent()
	return null

static func shown(control: Control, focused: Control) -> Rect2:
	"""Where a control is seen: cut to every scrolling list round it except
	those round the focused control too, whose rows count where they lie."""
	var rect := control.get_global_rect()
	var node: Node=control.get_parent()
	while node!=null and node is Control:
		if node is ScrollContainer and not node.is_ancestor_of(focused):rect=rect.intersection(node.get_global_rect())
		node=node.get_parent()
	return rect

static func scope_of(control: Control) -> Node:
	var scope: Node=control
	var node: Node=control.get_parent()
	while node!=null and node is Control:
		scope=node
		if node.has_meta(SCOPE_META):break
		node=node.get_parent()
	return scope

static func collect(node: Node, focused: Control, into: Array[Control]) -> void:
	if node is CanvasItem and not node.visible:return
	if node is Control and node!=focused and node.focus_mode==Control.FOCUS_ALL and not (node is BaseButton and node.disabled):into.append(node)
	for child in node.get_children():collect(child,focused,into)

static func distance(from: Rect2, to: Rect2, side: int) -> float:
	"""How far `to` lies past `from` on the side, weighted by how far out of
	line it is; INF unless it lies wholly on that side."""
	var gap: float;var along: Vector2;var other: Vector2
	match side:
		SIDE_RIGHT:gap=to.position.x-from.end.x;along=Vector2(from.position.y,from.end.y);other=Vector2(to.position.y,to.end.y)
		SIDE_LEFT:gap=from.position.x-to.end.x;along=Vector2(from.position.y,from.end.y);other=Vector2(to.position.y,to.end.y)
		SIDE_BOTTOM:gap=to.position.y-from.end.y;along=Vector2(from.position.x,from.end.x);other=Vector2(to.position.x,to.end.x)
		_:gap=from.position.y-to.end.y;along=Vector2(from.position.x,from.end.x);other=Vector2(to.position.x,to.end.x)
	if gap<-SLACK:return INF
	var apart: float=maxf(0.0,maxf(other.x-along.y,along.x-other.y))
	var offset: float=absf((other.x+other.y)-(along.x+along.y))*.5
	return maxf(0.0,gap)+apart*MISALIGNMENT+offset*.05
