extends Control
## Independent finger ownership allows steering, looking, thrust and weapons at the same time.
signal action(name: String)
var mode := 0 # Auto, On, Off
# Shared across the title/gameplay scene change; a pad used in menus also wins
# over touchscreen availability when the dive starts.
static var last_input := ""
## Safari can send compatibility mouse events from a finger with an ordinary
## mouse device ID, including motion between touchstart and touchend. Keep the
## gesture's ownership through those events and its delayed click after lift.
static var touch_contacts := {}
static var last_touch_ms := -1000000
const TOUCH_MOUSE_GRACE_MS := 750
var drag_anywhere := false
const Layout = preload("res://native/input/touch_layout.gd")
## Player placements, as offsets from the standard composition. Empty means the
## arrangement below is used exactly as designed.
var layout := {}
## Draws every control regardless of finger state, for the placement editor.
var layout_preview := false
var unit := 1.0
var active := false
var fingers := {}
var steer := Vector2.ZERO
var look := Vector2.ZERO
var zones := {}
var steer_region := Rect2()
var stick_center := Vector2.ZERO
var stick_home := Vector2.ZERO
var stick_radius := 96.0
var engaged := false
var cluster_top := 0.0
var gauge_reserve := 0.0
var free_left := 0.0
var free_right := 0.0
var show_fullscreen := true
const HOLD := ["guns","hook","boost","throttle_up","throttle_down"]
const TOP := ["menu","map","autopilot","time","dock","camera","bank","full"]
const LABELS := {"guns":"GUNS","hook":"HOOK","boost":"BOOST","throttle_up":"+ SPEED","throttle_down":"− SPEED","dock":"DOCK","map":"MAP","autopilot":"ROUTE","time":"TIME","camera":"VIEW","bank":"BANK","menu":"MENU","full":"FULL"}
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	z_index=60
	resized.connect(arrange);arrange()
func enabled() -> bool:
	return mode==1 or (mode==0 and (last_input=="touch" or (last_input.is_empty() and DisplayServer.is_touchscreen_available())))
static func record_input(event: InputEvent, deadzone: float=.18) -> void:
	if event is InputEventScreenTouch:
		last_touch_ms=Time.get_ticks_msec()
		if event.pressed and not event.canceled:
			touch_contacts[event.index]=true;last_input="touch"
		else:touch_contacts.erase(event.index)
	elif event is InputEventScreenDrag:
		last_touch_ms=Time.get_ticks_msec()
		touch_contacts[event.index]=true;last_input="touch"
	elif event is InputEventKey and event.pressed and not event.echo:
		last_input="keyboard"
	elif (event is InputEventMouseButton and event.pressed) or (event is InputEventMouseMotion and not event.relative.is_zero_approx()):
		# A browser's synthetic mouse event need not use Godot's emulation ID.
		# The short grace also covers WebKit's click after touchend. A physical
		# mouse can still take over after the touch gesture is finished.
		if event.device!=InputEvent.DEVICE_ID_EMULATION and touch_contacts.is_empty() and Time.get_ticks_msec()-last_touch_ms>TOUCH_MOUSE_GRACE_MS:
			last_input="mouse"
	elif event is InputEventJoypadButton and event.pressed:
		last_input="gamepad"
	elif event is InputEventJoypadMotion:
		var strength: float = event.axis_value if event.axis in [JOY_AXIS_TRIGGER_LEFT,JOY_AXIS_TRIGGER_RIGHT] else absf(event.axis_value)
		if strength>maxf(deadzone,.25):last_input="gamepad"
static func release_contacts() -> void:
	# A backgrounded browser can omit the final touchend/touchcancel event.
	touch_contacts.clear()
func update_input(event: InputEvent, deadzone: float=.18) -> void:
	var before := enabled()
	record_input(event,deadzone)
	if before!=enabled():
		reset();refresh_visibility()
func reset() -> void:
	fingers.clear();steer=Vector2.ZERO;look=Vector2.ZERO;engaged=false;stick_center=stick_home;queue_redraw()
func set_active(value: bool) -> void:
	if active!=value:reset()
	active=value;refresh_visibility()
func refresh_visibility() -> void:
	"""The placement editor needs the controls drawn while it deliberately keeps
	them from steering, so previewing counts as a reason to be on screen."""
	visible=(active or layout_preview) and enabled()
func safe_rect() -> Rect2:
	"""Keep controls clear of notches and rounded corners when the platform reports them."""
	var full := Rect2(Vector2.ZERO,size)
	var window := DisplayServer.window_get_size()
	if window.x<=0 or window.y<=0: return full
	var area := DisplayServer.get_display_safe_area()
	if area.size.x<=0 or area.size.y<=0: return full
	if area.position==Vector2i.ZERO and area.size==window: return full
	var scale := Vector2(size.x/float(window.x),size.y/float(window.y))
	var mapped := Rect2(Vector2(area.position)*scale,Vector2(area.size)*scale).intersection(full)
	return mapped if mapped.size.x>size.x*.5 and mapped.size.y>size.y*.5 else full
func top_keys() -> Array:
	"""Fullscreen is dropped where the browser cannot leave its own chrome."""
	return TOP if show_fullscreen else TOP.filter(func(key): return key!="full")
func arrange() -> void:
	reset();zones.clear()
	# UI uses a landscape logical canvas. Leave an inset for rounded display edges.
	var s:=minf(size.x/1280.0,size.y/720.0)
	var safe:=safe_rect()
	var inset:=28.0*s
	# Occasional controls sit along the top, away from where thumbs rest.
	var bw:=104.0*s;var bh:=74.0*s;var gap:=8.0*s
	var top_row:=top_keys()
	var span:=top_row.size()*bw+(top_row.size()-1)*gap
	var start:=safe.position.x+maxf(inset,(safe.size.x-span)*.5)
	for i in top_row.size():
		zones[top_row[i]]=Rect2(Vector2(start+i*(bw+gap),safe.position.y+12*s),Vector2(bw,bh))
	# Weapons sit under the right thumb; throttle stacks directly above them.
	# The depth gauge owns the right edge, so the cluster stops short of it.
	var gauge:=168.0*s
	var right:=safe.end.x-inset-gauge
	var weapon_y:=safe.end.y-inset-104*s
	for i in 3:
		var key: String=["boost","hook","guns"][i]
		zones[key]=Rect2(Vector2(right-(i+1)*118*s+8*s,weapon_y),Vector2(110,104)*s)
	zones.throttle_down=Rect2(Vector2(right-118*s+8*s,weapon_y-96*s),Vector2(110,88)*s)
	zones.throttle_up=Rect2(Vector2(right-2*118*s+8*s,weapon_y-96*s),Vector2(110,88)*s)
	cluster_top=zones.throttle_up.position.y
	gauge_reserve=gauge
	# The band between the stick and the weapon cluster stays free for the HUD.
	free_right=zones.boost.position.x-12*s
	# The stick floats: it appears wherever the left thumb lands in this region.
	stick_radius=104.0*s
	stick_home=Vector2(safe.position.x+inset+stick_radius,safe.end.y-inset-stick_radius)
	stick_center=stick_home
	free_left=safe.position.x+inset if drag_anywhere else stick_home.x+stick_radius+12*s
	var top:=safe.position.y+bh+24*s
	steer_region=Rect2(Vector2(safe.position.x,top),Vector2(safe.size.x*.46,safe.end.y-top))
	unit=s
	apply_layout(s)
func apply_layout(s: float) -> void:
	"""Moves and resizes what the player placed, then re-derives the free bands
	the HUD is laid out against so nothing ends up underneath a moved control."""
	for key in zones:
		var placement: float = Layout.scale_of(layout,key)
		var shift: Vector2 = Layout.offset_of(layout,key)*s
		if shift==Vector2.ZERO and is_equal_approx(placement,1.0): continue
		var area: Rect2 = zones[key]
		var middle := area.get_center()+shift
		var extent: Vector2 = area.size*placement
		zones[key]=Rect2(middle-extent*.5,extent)
	stick_radius=104.0*s*Layout.scale_of(layout,"stick")
	stick_home+=Layout.offset_of(layout,"stick")*s
	stick_center=stick_home
	cluster_top=zones.throttle_up.position.y if zones.has("throttle_up") else cluster_top
	free_right=zones.boost.position.x-12*s if zones.has("boost") else free_right
	free_left=safe_rect().position.x+28.0*s if drag_anywhere else stick_home.x+stick_radius+12*s
func control_rect(id: String) -> Rect2:
	"""The on-screen area of one control, including any player placement."""
	if id=="stick": return Rect2(stick_home-Vector2.ONE*stick_radius,Vector2.ONE*stick_radius*2)
	return zones.get(id,Rect2())
func button_at(point: Vector2) -> String:
	for key in zones:
		if zones[key].has_point(point):return key
	return ""
func handle(event: InputEvent) -> bool:
	if event is InputEventScreenTouch and event.pressed:
		update_input(event)
	if not active or not enabled():return false
	if event is InputEventScreenTouch:
		if event.pressed:
			var key:=button_at(event.position)
			if not key.is_empty() and key not in fingers.values():
				fingers[event.index]=key;queue_redraw();return true
			if not drag_anywhere and key.is_empty() and "steer" not in fingers.values() and steer_region.has_point(event.position):
				fingers[event.index]="steer";engaged=true
				stick_center=clamp_stick(event.position);steer=Vector2.ZERO
				queue_redraw();return true
			if key.is_empty() and "look" not in fingers.values():
				# Anywhere else is a free look surface, so the view is not stick-bound.
				fingers[event.index]="look";return true
		elif fingers.has(event.index):
			var key: String=fingers[event.index];fingers.erase(event.index)
			if key=="steer":steer=Vector2.ZERO;engaged=false;stick_center=stick_home
			elif key!="look" and key not in HOLD and not event.canceled and zones[key].has_point(event.position):action.emit(key)
			queue_redraw();return true
	if event is InputEventScreenDrag and fingers.has(event.index):
		var key: String=fingers[event.index]
		if key=="steer":move_stick(event.position)
		elif key=="look":look+=event.relative
		return true
	return false
func clamp_stick(point: Vector2) -> Vector2:
	var edge:=stick_radius*1.1
	return Vector2(clampf(point.x,edge,size.x-edge),clampf(point.y,edge,size.y-edge))
func move_stick(point: Vector2) -> void:
	steer=((point-stick_center)/stick_radius).limit_length()
	if steer.length()<.10:steer=Vector2.ZERO
	queue_redraw()
func snapshot() -> Dictionary:
	var held:=fingers.values()
	var drag:=look;look=Vector2.ZERO
	return {"yaw":steer.x,"pitch":-steer.y,"look":drag,"guns":"guns" in held,"hook":"hook" in held,"boost":"boost" in held,"throttle":int("throttle_up" in held)-int("throttle_down" in held)}
func _draw() -> void:
	if not active and not layout_preview:return
	var held:=fingers.values()
	var idle:=Color("679fba66") if not engaged else Color("8bd6eedd")
	if not drag_anywhere:
		draw_circle(stick_center,stick_radius,Color("102a4055"))
		draw_arc(stick_center,stick_radius,0,TAU,48,idle,2,true)
		draw_circle(stick_center+steer*stick_radius*.72,stick_radius*.3,Color("8bd6eedd") if engaged else Color("679fbaaa"))
	for key in zones:
		var area: Rect2=zones[key]
		var color:=Color("8bd6eedd") if key in held else Color("679fbaaa")
		draw_style_box(skin(color),area)
		var font_size:=maxi(12,roundi(16*minf(size.x/1280,size.y/720)))
		draw_string(ThemeDB.fallback_font,area.position+Vector2(0,area.size.y/2+font_size*.35),LABELS[key],HORIZONTAL_ALIGNMENT_CENTER,area.size.x,font_size,color)
func skin(color: Color) -> StyleBoxFlat:
	var box:=StyleBoxFlat.new();box.bg_color=Color("102a4077");box.border_color=color;box.set_border_width_all(1);box.set_corner_radius_all(8);return box
