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
## The stick stays where it is placed instead of coming to the thumb; a touch
## must then land on it to steer.
var fixed_stick := false
## A look drag swings the camera round the submarine. It stays swung after the
## finger lifts, until the stick is touched again or ORBIT_HOLD_MS pass.
const ORBIT_HOLD_MS := 4000
var orbit_hold := false
var look_released_ms := 0
const Layout = preload("res://native/input/touch_layout.gd")
## Player placements, as offsets from the standard composition. Empty means the
## arrangement below is used exactly as designed.
var layout := {}
## Draws every control regardless of finger state, for the placement editor.
## The editor shows the standard positions, so leaving it puts the harpoon back
## in the guns' place on a ship without guns.
var layout_preview := false:
	set(value):
		layout_preview=value
		if not weapon_home.is_empty(): place_throttle()
		queue_redraw()
var unit := 1.0
var active := false
var fingers := {}
var finger_positions := {}
const DOUBLE_TAP_MS := 320
var automatic_weapons := {}
var weapon_presses := {}
var weapon_touches := {}
var last_weapon_tap := ""
var last_weapon_tap_ms := -1000000
## Puts the throttle on the right of the fire button without moving the button.
var mirror_fire_control := false:
	set(value):
		if mirror_fire_control==value:return
		mirror_fire_control=value
		if not weapon_home.is_empty(): place_throttle()
		reset()
## The throttle as a separate upright slider instead of the arc round the
## fire button.
var throttle_slider := false:
	set(value):
		if throttle_slider==value:return
		throttle_slider=value
		arrange()
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
## Flight state the controls show: the throttle slider's level, whether the
## dock button has anything to dock with, the boost charge, autopilot and time.
signal throttle_changed(percent: int)
var throttle_level := 1.0
var dock_ready := false
var harpoon_reload := 1.0
var guns_reload := 1.0
var boost_fraction := 0.0
var boost_mode := "absent"
var autopilot_on := false
## Weapons the ship carries: a control for gear that is not fitted is not drawn.
var has_hook := true
var has_guns := true
## Original weapon controls: the guns button fires the selected bank (its
## double tap still only ever auto-fires the guns), and the harpoon's button
## switches bank. fishing_selected and can_switch come from the flight.
var original_weapons := false:
	set(value):
		if original_weapons==value:return
		original_weapons=value;reset()
		if not weapon_home.is_empty(): place_throttle()
		queue_redraw()
var fishing_selected := false
var can_switch := false
## The dock button's pulse, so a chance to dock is noticed.
var pulse := 0.0
## Where the placed layout puts the harpoon and guns; a ship with no guns
## has its harpoon take the guns' place and size.
var weapon_home := {}
var time_speed := 1
## The compact depth gauge's column, under the pause and map buttons.
var depth_rect := Rect2()
## Height of the depth gauge's two-line label (flight_instruments.gd).
const DEPTH_LABEL := 50.0
const HOLD := ["guns","hook","boost","throttle"]
const ROUND := ["menu","map","time","autopilot","dock","boost","hook","guns"]
const LABELS := {"guns":"GUNS","hook":"HOOK","boost":"BOOST","throttle":"THROTTLE","dock":"DOCK","map":"MAP","autopilot":"ROUTE","time":"TIME","menu":"PAUSE"}
func labels() -> Dictionary:
	"""LABELS in the engine's language."""
	return {"guns":tr("Guns").to_upper(),"hook":tr("Hook").to_upper(),"boost":tr("Boost").to_upper(),"throttle":tr("Throttle").to_upper(),"dock":tr("Dock").to_upper(),"map":tr("Map").to_upper(),"autopilot":tr("Route").to_upper(),"time":tr("Time").to_upper(),"menu":tr("Pause").to_upper()}
const IDLE := Color("5fc4df")
const LIT := Color("aef0ff")
const FACE := Color("06202ecc")
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
	automatic_weapons.clear();weapon_presses.clear();weapon_touches.clear();last_weapon_tap=""
	fingers.clear();finger_positions.clear();steer=Vector2.ZERO;look=Vector2.ZERO;engaged=false;stick_center=stick_home;orbit_hold=false;queue_redraw()
func orbit_held() -> bool:
	"""Whether the camera should stay where a look drag swung it."""
	if "look" in fingers.values(): return true
	return orbit_hold and Time.get_ticks_msec()-look_released_ms<ORBIT_HOLD_MS
func on_stick(point: Vector2) -> bool:
	return point.distance_to(stick_home)<=stick_radius*1.15
func set_active(value: bool) -> void:
	if active!=value:reset()
	active=value;refresh_visibility()
func refresh_visibility() -> void:
	"""The placement editor needs the controls drawn while it deliberately keeps
	them from steering, so previewing counts as a reason to be on screen."""
	visible=(active or layout_preview) and enabled()
func safe_rect() -> Rect2:
	"""The interface this overlay sits in is already inset from notches and
	rounded corners (see safe_margins.gd), so the whole of it is usable."""
	return Rect2(Vector2.ZERO,size)
func placement_rect() -> Rect2:
	"""Custom positions can use the full screen, measured from the safe-area
	origin that the default layout and HUD share."""
	if not is_inside_tree(): return safe_rect()
	return get_global_transform_with_canvas().affine_inverse()*get_viewport().get_visible_rect()
func round_zone(center: Vector2, radius: float) -> Rect2:
	return Rect2(center-Vector2.ONE*radius,Vector2.ONE*radius*2)
func arrange() -> void:
	reset();zones.clear()
	# UI uses a landscape logical canvas. Leave an inset for rounded display edges.
	# Scaled by the long and short sides, so a phone turned upright keeps
	# controls of the size they have held landscape.
	var s:=minf(maxf(size.x,size.y)/1280.0,minf(size.x,size.y)/720.0)
	var safe:=safe_rect()
	var left:=safe.position.x;var right:=safe.end.x;var top:=safe.position.y;var bottom:=safe.end.y
	# Pause and map in the top right corner, away from where thumbs rest.
	zones.menu=round_zone(Vector2(right-58*s,top+50*s),34*s)
	zones.map=round_zone(Vector2(right-146*s,top+50*s),34*s)
	# The depth gauge hangs under them; docking appears below it when possible.
	# Its DEPTH label is 50 units tall at every scale, so the gauge starts
	# that far plus a clear gap below the buttons' rims.
	depth_rect=Rect2(Vector2(right-52*s,top+(50+34+24)*s+DEPTH_LABEL),Vector2(12*s,250*s))
	# Docking comes up in from the edge, above the weapons, where it is seen.
	zones.dock=round_zone(Vector2(right-300*s,bottom-300*s),46*s)
	# Route and time stack above the stick, within reach of the left thumb.
	zones.time=round_zone(Vector2(left+62*s,bottom-392*s),26*s)
	zones.autopilot=round_zone(Vector2(left+62*s,bottom-304*s),26*s)
	# Weapons under the right thumb: the harpoon, then the guns outside it.
	zones.guns=round_zone(Vector2(right-128*s,bottom-150*s),74*s)
	zones.hook=round_zone(Vector2(right-296*s,bottom-104*s),44*s)
	cluster_top=zones.guns.position.y
	gauge_reserve=0.0
	# The stick floats: it appears wherever the left thumb lands in this region.
	stick_radius=104.0*s
	stick_home=Vector2(left+150*s,bottom-150*s)
	stick_center=stick_home
	# Level with the harpoon, so the two small buttons read as one row.
	zones.boost=round_zone(Vector2(stick_home.x+stick_radius+80*s,zones.hook.get_center().y),44*s)
	if size.y>size.x:
		# Held upright there is no width for a row: the booster goes above the
		# stick's right, and the harpoon above the guns and their throttle arc.
		if not throttle_slider: zones.hook=round_zone(zones.guns.get_center()+Vector2(0,-196*s),44*s)
		zones.boost=round_zone(stick_home+Vector2(stick_radius*.8,-stick_radius-62*s),44*s)
	unit=s
	zones.throttle=throttle_rect(zones.guns)
	var reach:=top+104*s
	steer_region=Rect2(Vector2(left,reach),Vector2(safe.size.x*.46,bottom-reach))
	apply_layout(s)
func apply_layout(s: float) -> void:
	"""Moves and resizes what the player placed, then re-derives the free bands
	the HUD is laid out against so nothing ends up underneath a moved control."""
	var bounds:=placement_rect()
	for key in zones:
		var placement: float = Layout.scale_of(layout,key)
		var shift: Vector2 = Layout.offset_of(layout,key)*s
		if shift==Vector2.ZERO and is_equal_approx(placement,1.0): continue
		var area: Rect2 = zones[key]
		var middle := area.get_center()+shift
		var extent: Vector2 = area.size*placement
		# A different orientation can have narrower margins. Fit the visible
		# control to that screen while retaining the player's saved offset.
		middle=middle.clamp(bounds.position+extent*.5,bounds.end-extent*.5)
		zones[key]=Rect2(middle-extent*.5,extent)
	stick_radius=104.0*s*Layout.scale_of(layout,"stick")
	stick_home+=Layout.offset_of(layout,"stick")*s
	if layout.has("stick"):
		var half:=Vector2.ONE*stick_radius
		stick_home=stick_home.clamp(bounds.position+half,bounds.end-half)
	stick_center=stick_home
	weapon_home={"hook":zones.hook,"guns":zones.guns}
	place_throttle()
	cluster_top=zones.throttle.position.y
	# The band between the left and right thumb controls stays free for the HUD.
	free_left=safe_rect().position.x+28.0*s if drag_anywhere else maxf(stick_home.x+stick_radius,zones.boost.end.x)+12*s
	free_right=minf(zones.hook.position.x,zones.throttle.position.x)-12*s
func harpoon_in_guns_place() -> bool:
	return not has_guns and has_hook and not layout_preview and not original_weapons
func place_throttle() -> void:
	"""A ship with no guns has its harpoon in their place, at their size. The
	throttle follows the guns wherever the player has put them, unless it has
	been placed itself."""
	zones.hook=weapon_home.guns if harpoon_in_guns_place() else weapon_home.hook
	if not throttle_slider: zones.throttle=round_zone(weapon_home.guns.get_center(),weapon_home.guns.size.x*.5+46*unit)
	elif layout.get("throttle") is not Dictionary: zones.throttle=throttle_rect(weapon_home.guns)
## The arc curves round the guns, wherever the player has put them; the
## slider is a control of its own, standing above the fire button on the
## side towards the screen's middle, clear of its rim: setting the speed while
## still (to fish, say) cannot fire, and firing cannot change the speed.
const THROTTLE_SIZE := Vector2(48,180)
func throttle_rect(guns: Rect2) -> Rect2:
	"""Where the throttle stands for guns placed at that rect, kept on screen."""
	var grown: float=guns.size.x/(148*unit)
	var side:=1.0 if mirror_fire_control else -1.0
	var extent:=THROTTLE_SIZE*unit
	var middle:=guns.get_center()+Vector2(side*84*grown*unit,-100*grown*unit-extent.y*.5)
	var bounds:=placement_rect()
	middle=middle.clamp(bounds.position+extent*.5,bounds.end-extent*.5)
	return Rect2(middle-extent*.5,extent)
func control_rect(id: String) -> Rect2:
	"""The on-screen area of one control, including any player placement."""
	if id=="stick": return Rect2(stick_home-Vector2.ONE*stick_radius,Vector2.ONE*stick_radius*2)
	# The arc goes with the guns; only the slider is placed on its own.
	if id=="throttle" and not throttle_slider: return Rect2()
	return zones.get(id,Rect2())
func shown(key: String) -> bool:
	"""The dock button is only there while there is something to dock with,
	and a weapon or booster button only while one is fitted."""
	if layout_preview: return true
	match key:
		"dock": return dock_ready
		"hook": return can_switch if original_weapons else has_hook
		"guns": return (has_guns or has_hook) if original_weapons else has_guns
		"boost": return boost_mode!="absent"
	return true
## The default upper-left arc is reflected for a left-side fire control.
const ARC_START := PI
const ARC_SPAN := PI*.5
func arc_radius(area: Rect2) -> float:
	return area.size.x*.5-20*unit
func arc_angle(level: float) -> float:
	var angle := ARC_START+ARC_SPAN*level
	return PI-angle if mirror_fire_control else angle
func arc_offset(area: Rect2, point: Vector2) -> Vector2:
	var offset := point-area.get_center()
	if mirror_fire_control:offset.x=-offset.x
	return offset
func arc_level(area: Rect2, point: Vector2) -> float:
	var angle:=wrapf(arc_offset(area,point).angle(),0,TAU)
	return clampf((angle-ARC_START)/ARC_SPAN,0,1)
func on_arc(area: Rect2, point: Vector2) -> bool:
	var offset:=arc_offset(area,point);var radius:=arc_radius(area)
	var angle:=wrapf(offset.angle(),0,TAU)
	return absf(offset.length()-radius)<26*unit and angle>ARC_START-.2 and angle<ARC_START+ARC_SPAN+.2
func throttle_track(area: Rect2) -> Vector2:
	"""The heights of the slider's empty and full ends, inset by the knob."""
	return Vector2(area.end.y-area.size.x*.5,area.position.y+area.size.x*.5)
func throttle_level_at(area: Rect2, point: Vector2) -> float:
	var track:=throttle_track(area)
	return clampf((track.x-point.y)/maxf(1,track.x-track.y),0,1)
func button_at(point: Vector2) -> String:
	for key in zones:
		if not shown(key):continue
		var area: Rect2=zones[key]
		# Round buttons answer within their circle, with a little slack for
		# a thumb landing on the rim; the throttle arc answers along its arc.
		if key=="throttle" and not throttle_slider:
			if on_arc(area,point):return key
		elif key in ROUND:
			if point.distance_to(area.get_center())<=area.size.x*.5+6*unit:return key
		elif area.grow(8*unit).has_point(point):return key
	return ""
func handle(event: InputEvent) -> bool:
	if event is InputEventScreenTouch and event.pressed:
		update_input(event)
	if not active or not enabled():return false
	# Fingers arrive in screen coordinates; the overlay can be inset from the
	# screen's edges.
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		event=event.duplicate();event.position=get_global_transform_with_canvas().affine_inverse()*event.position
	if event is InputEventScreenTouch:
		if not event.pressed:finger_positions.erase(event.index)
		if event.pressed:
			finger_positions[event.index]=event.position
			var key:=button_at(event.position)
			if not key.is_empty() and key not in fingers.values():
				fingers[event.index]=key
				if key=="guns" or (key=="hook" and not original_weapons):
					var stopping: bool=automatic_weapons.has(key)
					if stopping:
						automatic_weapons.erase(key);last_weapon_tap=""
						action.emit("auto_"+key)
					else:weapon_presses[key]=true
					weapon_touches[event.index]={"started":Time.get_ticks_msec(),"position":event.position,"valid":not stopping}
				if key=="throttle":slide(event.position)
				queue_redraw();return true
			var reach: bool=on_stick(event.position) if fixed_stick else steer_region.has_point(event.position) or on_stick(event.position)
			if not drag_anywhere and key.is_empty() and "steer" not in fingers.values() and reach:
				fingers[event.index]="steer";engaged=true
				# Taking the stick again after a look brings the camera back.
				if "look" not in fingers.values(): orbit_hold=false
				stick_center=stick_home if fixed_stick else clamp_stick(event.position);steer=Vector2.ZERO
				if fixed_stick: move_stick(event.position)
				queue_redraw();return true
			if key.is_empty() and "look" not in fingers.values():
				# Anywhere else is a free look surface, so the view is not stick-bound.
				fingers[event.index]="look";orbit_hold=true;return true
		elif fingers.has(event.index):
			var key: String=fingers[event.index];fingers.erase(event.index)
			if key=="hook" and original_weapons:
				# The switch: a tap changes bank.
				last_weapon_tap=""
				if not event.canceled and shown(key) and button_at(event.position)==key:action.emit("bank")
			elif key in ["guns","hook"]:
				var gesture: Dictionary=weapon_touches.get(event.index,{})
				weapon_touches.erase(event.index)
				var now := Time.get_ticks_msec()
				var tapped: bool=not event.canceled and gesture.get("valid",false) and now-int(gesture.get("started",0))<=DOUBLE_TAP_MS and shown(key) and button_at(event.position)==key
				if event.canceled:weapon_presses.erase(key)
				# Only the guns fire on their own; a double tap on the harpoon is
				# two shots.
				if tapped and key=="guns":
					if last_weapon_tap==key and now-last_weapon_tap_ms<=DOUBLE_TAP_MS:
						automatic_weapons[key]=true;last_weapon_tap="";action.emit("auto_"+key)
					else:last_weapon_tap=key;last_weapon_tap_ms=now
				else:last_weapon_tap=""
			if key=="steer":steer=Vector2.ZERO;engaged=false;stick_center=stick_home
			elif key=="look":look_released_ms=Time.get_ticks_msec()
			elif key!="look" and key not in HOLD and not event.canceled and shown(key) and button_at(event.position)==key:action.emit(key)
			queue_redraw();return true
	if event is InputEventScreenDrag and fingers.has(event.index):
		var key: String=fingers[event.index]
		# Web touch batches can reorder or omit fingers that did not move.
		# Some engine versions calculate relative against the batch slot, not
		# the touch ID, so it can contain the distance to the other thumb.
		# Our own per-finger positions also keep deltas in overlay coordinates.
		var relative: Vector2=event.position-finger_positions.get(event.index,event.position)
		finger_positions[event.index]=event.position
		if weapon_touches.has(event.index) and event.position.distance_to(weapon_touches[event.index].position)>24*unit:
			weapon_touches[event.index].valid=false
		if key=="steer":move_stick(event.position)
		elif key=="look":look+=relative
		elif key=="throttle":slide(event.position)
		return true
	return false
func slide(point: Vector2) -> void:
	"""The throttle is set where the thumb is on it, in steps of five."""
	var level: float=throttle_level_at(zones.throttle,point) if throttle_slider else arc_level(zones.throttle,point)
	var percent: int=roundi(level*20)*5
	if not is_equal_approx(percent/100.0,throttle_level):
		throttle_level=percent/100.0;throttle_changed.emit(percent);queue_redraw()
func clamp_stick(point: Vector2) -> Vector2:
	var edge:=stick_radius*1.1
	var bounds:=placement_rect()
	return point.clamp(bounds.position+Vector2.ONE*edge,bounds.end-Vector2.ONE*edge)
func move_stick(point: Vector2) -> void:
	steer=((point-stick_center)/stick_radius).limit_length()
	if steer.length()<.10:steer=Vector2.ZERO
	queue_redraw()
func show_state(throttle: float, dock: bool, boost: Dictionary, autopilot: bool, speed: int, hook: bool=true, guns: bool=true, harpoon: Dictionary={}, gun_reload: Dictionary={}) -> void:
	"""Takes the flight state the controls draw, redrawing only on a change."""
	var sliding: bool="throttle" in fingers.values()
	var reload: float=float(harpoon.fraction) if harpoon.get("mode","")=="reloading" else 1.0
	var rearming: float=float(gun_reload.fraction) if gun_reload.get("mode","")=="reloading" else 1.0
	# A long cooldown changes by less than one percent per frame. Comparing
	# against that threshold while storing every sample suppressed all redraws
	# until an unrelated control changed, making the fill jump forward.
	var changed: bool=not is_equal_approx(reload,harpoon_reload) or not is_equal_approx(rearming,guns_reload) or hook!=has_hook or guns!=has_guns or dock!=dock_ready or autopilot!=autopilot_on or speed!=time_speed or boost.mode!=boost_mode or not is_equal_approx(boost.fraction,boost_fraction) or (not sliding and absf(throttle-throttle_level)>.001)
	if not sliding:throttle_level=throttle
	var rearm: bool=hook!=has_hook or guns!=has_guns
	has_hook=hook;has_guns=guns
	if rearm: place_throttle()
	harpoon_reload=reload;guns_reload=rearming
	dock_ready=dock;autopilot_on=autopilot;time_speed=speed;boost_mode=boost.mode;boost_fraction=boost.fraction
	# A control that goes away lets go of the finger on it.
	for index in fingers.keys():
		if fingers[index] in zones and not shown(fingers[index]):fingers.erase(index)
	for key in automatic_weapons.keys():
		if not shown(key):automatic_weapons.erase(key)
	for key in weapon_presses.keys():
		if not shown(key):weapon_presses.erase(key)
	if changed:queue_redraw()
func set_banks(fishing: bool, switchable: bool) -> void:
	if fishing==fishing_selected and switchable==can_switch:return
	fishing_selected=fishing;can_switch=switchable
	for index in fingers.keys():
		if fingers[index] in zones and not shown(fingers[index]):fingers.erase(index)
	queue_redraw()
func snapshot() -> Dictionary:
	var held:=fingers.values()
	var drag:=look;look=Vector2.ZERO
	var shots := weapon_presses.duplicate();weapon_presses.clear()
	if original_weapons:
		# The fire button works the selected bank; its auto fire waits while
		# the harpoon is selected (gameplay.flight_input).
		return {"yaw":steer.x,"pitch":-steer.y,"look":drag,"fire":"guns" in held or shots.has("guns"),"auto":automatic_weapons.has("guns"),"guns":false,"hook":false,"boost":"boost" in held,"throttle":0}
	return {"yaw":steer.x,"pitch":-steer.y,"look":drag,"guns":"guns" in held or automatic_weapons.has("guns") or shots.has("guns"),"hook":"hook" in held or shots.has("hook"),"boost":"boost" in held,"throttle":0}
func _draw() -> void:
	if not active and not layout_preview:return
	var held:=fingers.values()
	if not drag_anywhere:draw_stick()
	for key in zones:
		if not shown(key):continue
		var lit: bool=key in held or automatic_weapons.has(key) or (key=="autopilot" and autopilot_on)
		if key=="throttle":
			if throttle_slider: draw_throttle(zones[key],key in held)
			else: draw_throttle_arc(zones[key],key in held)
		else:draw_button(key,zones[key],lit)
func glow_ring(center: Vector2, r: float, tint: Color, width: float) -> void:
	"""A lit rim: a soft halo either side of a bright line, as the reference's."""
	draw_arc(center,r,0,TAU,72,Color(tint,.08),width*6,true)
	draw_arc(center,r,0,TAU,72,Color(tint,.18),width*3,true)
	draw_arc(center,r,0,TAU,72,Color(tint.lerp(Color.WHITE,.15),.95),width,true)
func sphere(center: Vector2, r: float, tint: Color) -> void:
	"""A glossy ball: dark at its edge, bright towards a highlight up and left."""
	for step in 12:
		var t:=step/11.0
		draw_circle(center-Vector2(r,r)*.18*t,r*(1.0-t*.72),Color("0a3a4f").lerp(tint.lerp(Color.WHITE,.25),t*.9))
	draw_circle(center-Vector2(r,r)*.34,r*.16,Color(1,1,1,.35))
func draw_stick() -> void:
	var tint:=LIT if engaged else IDLE
	var r:=stick_radius
	# Darkened well with a faint glow towards the rim.
	draw_circle(stick_center,r,Color("041722aa"))
	for step in 4:draw_arc(stick_center,r*(.62+step*.1),0,TAU,64,Color(tint,.035),r*.1,true)
	glow_ring(stick_center,r,tint,3*unit)
	# A notch across the rim at each of the four directions, and a chevron
	# just inside it.
	for angle in [0.0,PI*.5,PI,PI*1.5]:
		var out:=Vector2.from_angle(angle);var side:=Vector2(-out.y,out.x)
		var rim:=stick_center+out*r
		draw_line(rim-side*11*unit,rim+side*11*unit,Color(tint.lerp(Color.WHITE,.4)),5*unit,true)
		var tip:=stick_center+out*r*.8
		draw_polyline(PackedVector2Array([tip-out*9*unit+side*12*unit,tip,tip-out*9*unit-side*12*unit]),Color(tint,.9),3*unit,true)
	# The socket the knob rides in.
	draw_circle(stick_center,r*.46,Color("031119cc"))
	draw_arc(stick_center,r*.46,0,TAU,56,Color(tint,.45),1.5*unit,true)
	var knob:=stick_center+steer*r*.62
	draw_circle(knob,r*.36,Color("021018"))
	sphere(knob,r*.32,tint.lerp(Color.WHITE,.1) if engaged else tint)
	draw_arc(knob,r*.34,0,TAU,48,Color(tint,.8),2*unit,true)
func _process(delta: float) -> void:
	if dock_ready and visible and active:
		pulse=fmod(pulse+delta,1.4);queue_redraw()
func draw_button(key: String, area: Rect2, lit: bool) -> void:
	var center:=area.get_center();var r:=area.size.x*.5
	var tint:=LIT if lit else IDLE
	if key=="dock" and not layout_preview:
		# A ripple spreading off the rim, and the rim brightening with it.
		var t: float=pulse/1.4
		draw_arc(center,r+t*22*unit,0,TAU,56,Color(LIT,.55*(1.0-t)),3*unit,true)
		tint=IDLE.lerp(Color.WHITE,.35+.25*sin(t*TAU))
		draw_string(ThemeDB.fallback_font,center+Vector2(-r,r+20*unit),tr("Dock").to_upper(),HORIZONTAL_ALIGNMENT_CENTER,r*2,roundi(14*unit),LIT)
	draw_circle(center,r,Color("1a5f78cc") if lit else FACE)
	var waiting: bool=key=="boost" and boost_mode=="charging"
	if key=="boost" and boost_mode in ["charging","active"]:
		# The button fills from the bottom as the booster recharges, and
		# drains while it burns.
		fill_level(center,r-2*unit,boost_fraction,Color("f0c870",.45) if boost_mode=="active" else Color(IDLE,.3))
	# The weapon buttons fill as they reload, like the booster's. The fire
	# button follows the harpoon while it stands in for the guns.
	var harpoon_on_fire: bool=original_weapons and not layout_preview and (fishing_selected or not has_guns)
	var reloading := 1.0
	if key=="guns":reloading=harpoon_reload if harpoon_on_fire else guns_reload
	elif key=="hook" and not (original_weapons and not layout_preview):reloading=harpoon_reload
	if reloading<1.0:fill_level(center,r-2*unit,reloading,Color(IDLE,.3))
	glow_ring(center,r,Color(tint,.45) if waiting else tint,(3.0 if key=="guns" else 2.5)*unit)
	var large: bool=key=="guns" or (key=="hook" and harpoon_in_guns_place())
	if large:draw_arc(center,r*.8,0,TAU,64,Color(tint,.6),2*unit,true)
	var drawn := key
	if original_weapons and not layout_preview:
		if key=="guns" and (fishing_selected or not has_guns):drawn="hook"
		elif key=="hook":drawn="switch"
	icon(drawn,center,r*(.5 if large else .56),Color(tint,.5) if waiting else tint.lerp(Color.WHITE,.12))
	if key=="time" and time_speed>1:
		draw_string(ThemeDB.fallback_font,center+Vector2(-r,r+16*unit),"%d×"%time_speed,HORIZONTAL_ALIGNMENT_CENTER,r*2,roundi(14*unit),LIT)
	if automatic_weapons.has(key):
		# Dim while the harpoon is selected and the guns wait.
		draw_string(ThemeDB.fallback_font,center+Vector2(-r,r+18*unit),tr("Auto").to_upper(),HORIZONTAL_ALIGNMENT_CENTER,r*2,roundi(14*unit),Color(LIT,.45) if original_weapons and fishing_selected else LIT)
func fill_level(center: Vector2, r: float, fraction: float, color: Color) -> void:
	"""The part of a disc below a level, as liquid in a round flask."""
	if fraction<=0: return
	var disc := PackedVector2Array()
	for step in 48: disc.append(center+Vector2.from_angle(step*TAU/48)*r)
	var line: float=center.y+r-2*r*clampf(fraction,0,1)
	var below := PackedVector2Array([Vector2(center.x-r-1,line),Vector2(center.x+r+1,line),Vector2(center.x+r+1,center.y+r+1),Vector2(center.x-r-1,center.y+r+1)])
	for part in Geometry2D.intersect_polygons(disc,below): draw_colored_polygon(part,color)
func draw_throttle_arc(area: Rect2, lit: bool) -> void:
	var tint:=LIT if lit else IDLE
	var c:=area.get_center();var radius:=arc_radius(area)
	var start:=arc_angle(0);var end:=arc_angle(1);var fill:=arc_angle(throttle_level)
	draw_arc(c,radius,minf(start,end),maxf(start,end),40,Color("031119cc"),16*unit,true)
	draw_arc(c,radius,minf(start,end),maxf(start,end),40,Color(tint,.22),10*unit,true)
	if throttle_level>0:draw_arc(c,radius,minf(start,fill),maxf(start,fill),40,Color(tint,.85),7*unit,true)
	for step in 5:
		var out:=Vector2.from_angle(arc_angle(step*.25))
		draw_line(c+out*(radius+9*unit),c+out*(radius+14*unit),Color(tint,.6),1.5*unit,true)
	var knob:=c+Vector2.from_angle(arc_angle(throttle_level))*radius
	draw_circle(knob,9*unit,Color("0b3446"));draw_arc(knob,9*unit,0,TAU,24,tint,2*unit,true)
	var label_at:=c+Vector2.from_angle(arc_angle(.5))*(radius+30*unit)
	draw_string(ThemeDB.fallback_font,label_at+Vector2(-30*unit,5*unit),"%d%%"%roundi(throttle_level*100),HORIZONTAL_ALIGNMENT_CENTER,60*unit,roundi(12*unit),Color(tint,.85))
func draw_throttle(area: Rect2, lit: bool) -> void:
	var tint:=LIT if lit else IDLE
	var k: float=area.size.x/(THROTTLE_SIZE.x*unit)*unit
	var track:=throttle_track(area);var x:=area.get_center().x
	var low:=Vector2(x,track.x);var high:=Vector2(x,track.y);var level:=low.lerp(high,throttle_level)
	# A rounded groove, filled from the bottom up to the knob.
	for part in [[16.0,Color("031119cc")],[10.0,Color(tint,.22)]]:
		draw_line(low,high,part[1],part[0]*k);draw_circle(low,part[0]*.5*k,part[1]);draw_circle(high,part[0]*.5*k,part[1])
	if throttle_level>0:draw_line(low,level,Color(tint,.85),7*k);draw_circle(low,3.5*k,Color(tint,.85))
	for step in 5:
		var y: float=lerpf(track.x,track.y,step*.25)
		for side in [-1,1]:draw_line(Vector2(x+side*11*k,y),Vector2(x+side*16*k,y),Color(tint,.6),1.5*k,true)
	draw_circle(level,11*k,Color("0b3446"));draw_arc(level,11*k,0,TAU,24,tint,2*k,true)
	# The level reads beside the knob, on the side towards the screen's middle.
	var inward: bool=x<size.x*.5
	var label_at:=level+Vector2(20*k if inward else -80*k,5*k)
	draw_string(ThemeDB.fallback_font,label_at,"%d%%"%roundi(throttle_level*100),HORIZONTAL_ALIGNMENT_LEFT if inward else HORIZONTAL_ALIGNMENT_RIGHT,60*k,roundi(12*k),Color(tint,.85))

func icon(key: String, c: Vector2, r: float, color: Color) -> void:
	"""Line icons, drawn at the size of the button so they stay sharp."""
	var w:=maxf(1.5,r*.13)
	match key:
		"menu":
			for side in [-1,1]:draw_rect(Rect2(c+Vector2(side*r*.32-r*.13,-r*.5),Vector2(r*.26,r)),color)
		"map":
			var p:=PackedVector2Array([c+Vector2(-r*.8,-r*.45),c+Vector2(-r*.27,-r*.7),c+Vector2(r*.27,-r*.45),c+Vector2(r*.8,-r*.7),
				c+Vector2(r*.8,r*.6),c+Vector2(r*.27,r*.85),c+Vector2(-r*.27,r*.6),c+Vector2(-r*.8,r*.85),c+Vector2(-r*.8,-r*.45)])
			draw_polyline(p,color,w,true)
			draw_line(c+Vector2(-r*.27,-r*.7),c+Vector2(-r*.27,r*.6),Color(color,.6),w*.7,true)
			draw_line(c+Vector2(r*.27,-r*.45),c+Vector2(r*.27,r*.85),Color(color,.6),w*.7,true)
			draw_circle(c+Vector2(0,-r*.2),r*.26,color);draw_circle(c+Vector2(0,-r*.2),r*.1,FACE)
			draw_colored_polygon(PackedVector2Array([c+Vector2(-r*.22,-r*.08),c+Vector2(r*.22,-r*.08),c+Vector2(0,r*.3)]),color)
		"time":
			var o:=c+Vector2(-r*.12,0)
			draw_arc(o,r*.7,PI*.3,PI*1.95,40,color,w,true)
			draw_line(o,o+Vector2(0,-r*.42),color,w,true);draw_line(o,o+Vector2(r*.3,0),color,w,true)
			for step in 2:
				var x: float=c.x+r*(.38+step*.32)
				draw_colored_polygon(PackedVector2Array([Vector2(x,c.y+r*.12),Vector2(x+r*.34,c.y+r*.42),Vector2(x,c.y+r*.72)]),color)
		"autopilot":
			var p:=PackedVector2Array([c+Vector2(0,-r*.85),c+Vector2(r*.62,r*.72),c+Vector2(0,r*.36),c+Vector2(-r*.62,r*.72),c+Vector2(0,-r*.85)])
			draw_polyline(p,color,w,true)
			draw_colored_polygon(PackedVector2Array([c+Vector2(0,-r*.05),c+Vector2(r*.24,r*.3),c+Vector2(0,r*.62),c+Vector2(-r*.24,r*.3)]),color)
		"dock":
			draw_line(c+Vector2(0,-r*.8),c+Vector2(0,r*.2),color,w*1.2,true)
			draw_colored_polygon(PackedVector2Array([c+Vector2(-r*.4,-r*.05),c+Vector2(r*.4,-r*.05),c+Vector2(0,r*.38)]),color)
			draw_polyline(PackedVector2Array([c+Vector2(-r*.75,r*.3),c+Vector2(-r*.75,r*.68),c+Vector2(r*.75,r*.68),c+Vector2(r*.75,r*.3)]),color,w,true)
		"boost":
			for step in 2:
				var y: float=c.y+r*(.05+step*.45)-r*.3
				draw_polyline(PackedVector2Array([Vector2(c.x-r*.6,y+r*.35),Vector2(c.x,y-r*.25),Vector2(c.x+r*.6,y+r*.35)]),color,w*1.5,true)
		"hook":
			# Eye, shank, bend and a barbed point, centred on the button.
			c.y+=r*.12
			var shank:=c.x+r*.2;var bend:=Vector2(c.x-r*.1,c.y+r*.3);var point:=c.x-r*.4
			draw_arc(Vector2(shank,c.y-r*.7),r*.14,0,TAU,16,color,w,true)
			draw_line(Vector2(shank,c.y-r*.56),Vector2(shank,bend.y),color,w*1.2,true)
			draw_arc(bend,r*.3,0,PI,24,color,w*1.2,true)
			draw_line(Vector2(point,bend.y),Vector2(point,c.y),color,w*1.2,true)
			draw_colored_polygon(PackedVector2Array([Vector2(point,c.y-r*.22),Vector2(point+w*.6,c.y+r*.02),Vector2(point-r*.2,c.y+r*.06)]),color)
		"switch":
			# Two arrows passing each other: change weapon bank.
			for side in [-1,1]:
				var y: float=c.y+side*r*.28
				var tip:=Vector2(c.x+side*r*.62,y)
				draw_line(Vector2(c.x-side*r*.62,y),tip,color,w*1.2,true)
				draw_colored_polygon(PackedVector2Array([tip+Vector2(side*r*.12,0),tip+Vector2(-side*r*.26,-r*.22),tip+Vector2(-side*r*.26,r*.22)]),color)
		"guns":
			for side in [-1,1]:
				var x: float=c.x+side*r*.3
				var body:=PackedVector2Array([Vector2(x-r*.2,c.y+r*.8),Vector2(x-r*.2,c.y-r*.2),Vector2(x-r*.12,c.y-r*.55),Vector2(x,c.y-r*.8),Vector2(x+r*.12,c.y-r*.55),Vector2(x+r*.2,c.y-r*.2),Vector2(x+r*.2,c.y+r*.8)])
				draw_colored_polygon(body,color)
				draw_line(Vector2(x-r*.2,c.y+r*.5),Vector2(x+r*.2,c.y+r*.5),FACE,maxf(1,w*.6))
