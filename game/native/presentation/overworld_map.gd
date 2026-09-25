extends Control
signal selected(id: int)
## A tap placed the zone: where it ended up, and the station tapped, if any.
signal zone_moved(center: Vector2, near: int)
var world
var selected_id := 0
var zoom := 1.0
var pan := Vector2.ZERO
var dragging := false
var filtered := ""
## The circle the side view is cut through, in chart units; none at zero.
var lens_center := Vector2.ZERO
var lens_radius := 0.0
## How far from the current station the zone's middle may go, in chart units;
## unbounded below zero. The original keeps its cursor inside the reach.
var lens_limit := -1.0
## The trail's legs, newest first: the original's six blues.
const TRAIL := [Color("99ceff"),Color("78beff"),Color("52a8f2"),Color("2389ec"),Color("006ed9"),Color("0060c5")]
var touches := {}
var tap_start := Vector2.ZERO
var tap_allowed := false
func _ready() -> void:
	custom_minimum_size=Vector2(400,390)
	mouse_filter=Control.MOUSE_FILTER_STOP
	clip_contents=true
func point(x: float,y: float) -> Vector2:
	return size*0.5+(Vector2(x,y)-Vector2(50,50))*minf(size.x,size.y)*0.0085*zoom+pan
func chart_at(position: Vector2) -> Vector2:
	return (position-size*0.5-pan)/(minf(size.x,size.y)*0.0085*zoom)+Vector2(50,50)
func place_lens(target: Vector2) -> Vector2:
	"""Moves the zone as far towards the target as it may go: inside the reach
	when it is bounded, and on the ocean."""
	if lens_limit>=0 and world!=null:
		var home: Dictionary=world.session.stations[world.session.station_id]
		var middle:=Vector2(home.x,home.y)
		target=middle+(target-middle).limit_length(lens_limit)
	lens_center=target.clamp(Vector2.ZERO,Vector2(100,100));queue_redraw()
	return lens_center
func _draw() -> void:
	# The original chart is a flat blue field with a dark grid over it, stations
	# as small squares and the sonar reach as a filled disc rather than a ring.
	draw_rect(Rect2(Vector2.ZERO,size),Color("2f43b4"))
	for axis in range(0,101,25):
		draw_line(point(axis,0),point(axis,100),Color("101a52"),2)
		draw_line(point(0,axis),point(100,axis),Color("101a52"),2)
	if world==null: return
	var session=world.session
	var home: Dictionary = session.stations[session.station_id]
	var reach: float = world.stream_range()*minf(size.x,size.y)*0.0085*zoom
	draw_circle(point(home.x,home.y),reach,Color("6e86ff4d"),true)
	draw_arc(point(home.x,home.y),reach,0,TAU,96,Color("9fb4ff"),1.5,true)
	if world.stream_destination>=0:
		var arrival: Dictionary = session.stations[world.stream_destination]
		draw_dashed_line(point(home.x,home.y),point(arrival.x,arrival.y),Color("bdabf2"),2,6)
	if lens_radius>0:
		# The original's cursor: a ring with a tick on each side, marking what
		# the side view shows.
		var middle := point(lens_center.x,lens_center.y)
		var ring: float=lens_radius*minf(size.x,size.y)*0.0085*zoom
		draw_circle(middle,ring,Color(0.46,0.92,0.91,0.12),true)
		draw_arc(middle,ring,0,TAU,96,Color("75ebe8"),1.5,true)
		for side in [Vector2.RIGHT,Vector2.DOWN,Vector2.LEFT,Vector2.UP]:
			var tip: Vector2=middle+side*(ring+7)
			var across := Vector2(-side.y,side.x)
			draw_colored_polygon(PackedVector2Array([tip,middle+side*(ring+2)+across*4,middle+side*(ring+2)-across*4]),Color("75ebe8"))
	# The recent trips (bp.e): a line through the last areas visited, the
	# newest leg palest and the older ones darkening into the water.
	var trail: Array=session.trail
	for leg in range(trail.size()-1):
		var from: Dictionary=session.stations[trail[leg]];var to: Dictionary=session.stations[trail[leg+1]]
		draw_line(point(from.x,from.y),point(to.x,to.y),TRAIL[mini(trail.size()-2-leg,TRAIL.size()-1)],2,true)
	for station in session.stations:
		if not filtered.is_empty() and not str(station.name).to_lower().contains(filtered): continue
		var p := point(station.x,station.y)
		var mark := marker(world,station)
		var discovered: bool = mark.discovered
		var objective: bool = mark.objective
		if station.id==selected_id and selected_id>=0: draw_arc(p,12,0,TAU,24,Color.WHITE,2,true)
		# A visited station is drawn a little wider as well, which the original
		# does not do, but which reads before the colours are compared.
		pixel_square(self,p,9.0 if discovered else 7.0,3.0,mark.body,mark.core)
		if zoom>1.7 or station.id==selected_id or objective:
			draw_string(ThemeDB.fallback_font,p.round()+Vector2(10,-8),station.name,HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("d7edf1"))
	var encounter = world.encounter_navigation_point()
	if encounter!=null:
		var anchor: Array=world.station_origin(session.station_id)
		var waypoint := point(float(anchor[0]+encounter[0])/world.map_scale(),float(anchor[2]+encounter[2])/world.map_scale())
		draw_arc(waypoint,6,0,TAU,16,Color("91e4d4"),2,true)
		draw_string(ThemeDB.fallback_font,waypoint+Vector2(12,20),"Local encounter",HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("91e4d4"))
	var position: Array = world.global_position()
	var p := point(float(position[0])/world.map_scale(),float(position[2])/world.map_scale())
	if world.autopilot and world.destination>=0:
		var target: Dictionary = session.stations[world.destination]
		draw_dashed_line(p,point(target.x,target.y),Color("97e4d3"),2,6)
	scale_bar()
	var direction:=heading()
	if direction.length_squared()<.001:
		draw_circle(p,3,Color("f4fafb")) # Straight up/down has no planar heading.
	else:
		# Kept small: it is parked on a station most of the time, and the marker
		# underneath says who holds the place you are sitting in.
		var right:=Vector2(-direction.y,direction.x)
		draw_colored_polygon(PackedVector2Array([p+direction*7,p-direction*4-right*3.5,p-direction*4+right*3.5]),Color("f4fafb"))
func scale_bar() -> void:
	"""A round distance in the corner, as on a sea chart: the world spacing
	setting decides how far a map unit is, so the bar is what tells the
	player how far the squares actually are."""
	var pixels_per_unit: float=minf(size.x,size.y)*0.0085*zoom
	var meters_per_pixel: float=world.session.world_layout.spacing_meters/maxf(pixels_per_unit,0.001)
	var meters: float=nice_distance(meters_per_pixel*110.0)
	var length: float=meters/meters_per_pixel
	var right := Vector2(size.x-14,size.y-14)
	var left := right-Vector2(length,0)
	var ink := Color("d7edf1")
	# Beside it, how wide a square of the grid is: the figure the world
	# spacing setting is given in.
	var grid := "= "+distance_text(world.session.world_layout.spacing_meters*25.0)
	var grid_width: float=ThemeDB.fallback_font.get_string_size(grid,HORIZONTAL_ALIGNMENT_LEFT,-1,13).x
	var start := left.x-grid_width-38
	draw_rect(Rect2(Vector2(start-8,left.y-26),Vector2(right.x-start+16,34)),Color("101a52b0"))
	draw_rect(Rect2(Vector2(start,left.y-15),Vector2(12,12)),Color("101a52"),true)
	draw_rect(Rect2(Vector2(start,left.y-15),Vector2(12,12)),ink,false,1.5)
	draw_string(ThemeDB.fallback_font,Vector2(start+17,right.y-4),grid,HORIZONTAL_ALIGNMENT_LEFT,-1,13,ink)
	draw_line(Vector2(left.x-9,left.y-20),Vector2(left.x-9,left.y+2),Color(ink,0.35),1)
	draw_line(left,right,ink,2)
	for end in [left,right]:draw_line(end,end-Vector2(0,7),ink,2)
	var text := distance_text(meters)
	var width: float=ThemeDB.fallback_font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,13).x
	draw_string(ThemeDB.fallback_font,Vector2((left.x+right.x-width)*0.5,right.y-9),text,HORIZONTAL_ALIGNMENT_LEFT,-1,13,ink)
static func nice_distance(meters: float) -> float:
	"""The largest 1, 2 or 5 times a power of ten not above the given length."""
	var power: float=pow(10.0,floorf(log(maxf(meters,1.0))/log(10.0)))
	for step in [5.0,2.0,1.0]:
		if step*power<=meters:return step*power
	return power
static func distance_text(meters: float) -> String:
	if meters>=1000.0:
		var kilometers: float=meters/1000.0
		if is_equal_approx(kilometers,roundf(kilometers)):return "%d km"%roundi(kilometers)
		return "%.1f km"%kilometers
	return "%d m"%roundi(meters)
static func marker(world, station: Dictionary) -> Dictionary:
	"""A station's colours on the chart and the side view alike.

	The original chart blits a three-by-three sprite for each station: a ring of
	the holder's colour around a single pixel of its opposite. Arriving swaps
	the two, so an unvisited station is a dark square with a bright centre and a
	visited one is the reverse. These are those sprites' own colours, the dark
	states lifted off near-black so they still read on a lit screen. The
	resistance is green because the dialogue that reveals it says so."""
	var session=world.session
	var discovered: bool = session.discovered[station.id]
	var rebel: bool = session.campaign.rebel_stations[station.id]
	var bright := Color("65e53e") if rebel else Color("05bbff")
	var dark := Color("14501a") if rebel else Color("0d2170")
	var body := bright if discovered else dark
	var core := dark if discovered else bright
	var objective: bool = station.id==session.campaign.primary.destination and session.campaign.primary.kind>=0
	# The station you are at and the one you are sent to wear their own marker
	# over whoever holds them, orange and red, as they do on the original.
	if station.id==session.station_id: body=Color("ff8000"); core=Color("ffff00")
	if objective: body=Color("ff0000"); core=Color("c00000")
	return {"body":body,"core":core,"discovered":discovered,"objective":objective}
static func pixel_square(item: CanvasItem, at: Vector2, outer_units: float, inner_units: float, body: Color, core: Color) -> void:
	"""Lays a station marker out on the physical pixel grid rather than on the
	chart's own units. The window scales this canvas, so whole units here are not
	whole pixels there: each square rounded to whichever side of the grid its
	fraction fell on, independently of the other, and the centres looked
	scattered across the chart. Both are odd numbers of real pixels wide now,
	around one shared centre pixel, which is also how the original's sprite is
	cut."""
	# The canvas transform alone stops at the viewport. A fixed aspect ratio in
	# Display settings scales the viewport onto the window on top of that, and
	# leaving that factor out put the markers back on fractions of a pixel.
	var to_screen := item.get_viewport().get_final_transform()*item.get_global_transform_with_canvas()
	var scale: float = maxf(to_screen.get_scale().x,0.0001)
	var inverse := to_screen.affine_inverse()
	var outer := odd_pixels(outer_units*scale)
	var inner := odd_pixels(inner_units*scale)
	var corner := (to_screen*at-Vector2(outer,outer)*0.5).round()
	var inset := float((outer-inner)/2)
	pixel_rect(item,inverse,corner,outer,scale,body)
	pixel_rect(item,inverse,corner+Vector2(inset,inset),inner,scale,core)
static func pixel_rect(item: CanvasItem, inverse: Transform2D, corner: Vector2, pixels: int, scale: float, tint: Color) -> void:
	"""Whole pixels, edge to edge. Insetting the rectangle to keep it clear of
	its own boundary sounds safer and is not: a three-pixel centre loses most of
	a pixel that way and lands on two of them in one direction and three in the
	other, which is what made the centres look like bars."""
	item.draw_rect(Rect2(inverse*corner,Vector2(pixels,pixels)/scale),tint,true)
static func odd_pixels(value: float) -> int:
	"""Nearest odd number of pixels, so a square has a centre pixel to share."""
	return maxi(1,int(roundf((value-1.0)*0.5))*2+1)
func heading() -> Vector2:
	if world==null or world.region==null:return Vector2.ZERO
	var forward: Array=world.region.player.pose.forward
	var planar:=Vector2(forward[0],forward[2])
	return planar.normalized() if planar.length()>32 else Vector2.ZERO
func _gui_input(event: InputEvent) -> void:
	for pair in [["ui_left",Vector2.LEFT],["ui_right",Vector2.RIGHT],["ui_up",Vector2.UP],["ui_down",Vector2.DOWN]]:
		if event.is_action_pressed(pair[0],true) and lens_radius>0:nudge(pair[1]);accept_event();return
	# Touch gestures below own taps and drags; ignore their emulated mouse events.
	if event.device==-1 and (event is InputEventMouseButton or event is InputEventMouseMotion):return
	if event is InputEventMouseButton:
		if event.button_index==MOUSE_BUTTON_RIGHT: dragging=event.pressed
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			var old := zoom; zoom=clampf(zoom*(1.2 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1/1.2),0.75,6)
			pan=event.position-size*0.5-(event.position-size*0.5-pan)*zoom/old; queue_redraw()
		if event.pressed and event.button_index==MOUSE_BUTTON_LEFT:select_at(event.position)
	if event is InputEventMouseMotion and dragging: pan+=event.relative; queue_redraw()
	if event is InputEventMagnifyGesture: zoom=clampf(zoom*event.factor,0.75,6); queue_redraw()
	if event is InputEventScreenTouch:
		if event.pressed:
			touches[event.index]=event.position
			tap_allowed=touches.size()==1;tap_start=event.position
		else:
			if tap_allowed and not event.canceled and touches.size()==1 and event.position.distance_to(tap_start)<12:select_at(event.position)
			touches.erase(event.index);tap_allowed=false
		accept_event()
	if event is InputEventScreenDrag and touches.has(event.index):
		if event.position.distance_to(tap_start)>12:tap_allowed=false
		if touches.size()==1:pan+=event.relative
		elif touches.size()==2:
			var other: Vector2=touches.values()[1] if touches.keys()[0]==event.index else touches.values()[0]
			var before: Vector2=touches[event.index]
			var distance:=before.distance_to(other)
			if distance>10:
				var old:=zoom;zoom=clampf(zoom*event.position.distance_to(other)/distance,.75,6)
				var center:=(other+before)*.5
				pan=center-size*.5-(center-size*.5-pan)*zoom/old+(event.position-before)*.5
			tap_allowed=false
		touches[event.index]=event.position;queue_redraw();accept_event()
func select_at(position: Vector2) -> void:
	if world==null:return
	var nearest:=24.0;var id:=-1
	for station in world.session.stations:
		if not filtered.is_empty() and not str(station.name).to_lower().contains(filtered):continue
		var distance:=point(station.x,station.y).distance_to(position)
		if distance<nearest:nearest=distance;id=station.id
	if lens_radius>0:
		# With a zone on the chart a tap moves the zone, onto the station when
		# one was tapped; the side view then picks among what it covers.
		var target:=chart_at(position)
		if id>=0:target=Vector2(world.session.stations[id].x,world.session.stations[id].y)
		zone_moved.emit(place_lens(target),id);return
	if id>=0:selected_id=id;selected.emit(id);queue_redraw()
func nudge(direction: Vector2) -> void:
	"""The direction keys walk the zone, as the original's do."""
	if lens_radius<=0:return
	zone_moved.emit(place_lens(lens_center+direction*lens_radius*.5),-1)
func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT,NOTIFICATION_VISIBILITY_CHANGED]:
		touches.clear();dragging=false;tap_allowed=false
