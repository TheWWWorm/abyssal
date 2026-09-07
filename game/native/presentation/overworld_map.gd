extends Control
signal selected(id: int)
var world
var selected_id := 0
var zoom := 1.0
var pan := Vector2.ZERO
var dragging := false
var filtered := ""
var touches := {}
var tap_start := Vector2.ZERO
var tap_allowed := false
func _ready() -> void:
	custom_minimum_size=Vector2(400,390)
	mouse_filter=Control.MOUSE_FILTER_STOP
	clip_contents=true
func point(x: float,y: float) -> Vector2:
	return size*0.5+(Vector2(x,y)-Vector2(50,50))*minf(size.x,size.y)*0.0085*zoom+pan
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Color("071923"))
	for axis in range(0,101,10):
		draw_line(point(axis,0),point(axis,100),Color("153342"),1)
		draw_line(point(0,axis),point(100,axis),Color("153342"),1)
	if world==null: return
	var session=world.session
	var home: Dictionary = session.stations[session.station_id]
	var reach: float = world.stream_range()*minf(size.x,size.y)*0.0085*zoom
	draw_arc(point(home.x,home.y),reach,0,TAU,96,Color("4b827d"),1.5,true)
	if world.stream_destination>=0:
		var arrival: Dictionary = session.stations[world.stream_destination]
		draw_dashed_line(point(home.x,home.y),point(arrival.x,arrival.y),Color("bdabf2"),2,6)
	for station in session.stations:
		var p := point(station.x,station.y)
		var color := Color("f5b86e") if session.campaign.rebel_stations[station.id] else Color("69b7c8")
		if not session.discovered[station.id]: color=color.darkened(0.45)
		if not filtered.is_empty() and not str(station.name).to_lower().contains(filtered): continue
		var objective: bool = station.id==session.campaign.primary.destination and session.campaign.primary.kind>=0
		if objective: draw_arc(p,8,0,TAU,24,Color("e7ce89"),2,true)
		if station.id==selected_id: draw_arc(p,12,0,TAU,24,Color.WHITE,2,true)
		draw_circle(p,4 if session.discovered[station.id] else 2.5,color)
		if zoom>1.7 or station.id==selected_id or objective:
			draw_string(ThemeDB.fallback_font,p+Vector2(10,-8),station.name,HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("d7edf1"))
	var encounter = world.encounter_navigation_point()
	if encounter!=null:
		var anchor: Array=world.station_origin(session.station_id)
		var waypoint := point(float(anchor[0]+encounter[0])/world.MAP_SCALE,float(anchor[2]+encounter[2])/world.MAP_SCALE)
		draw_arc(waypoint,6,0,TAU,16,Color("91e4d4"),2,true)
		draw_string(ThemeDB.fallback_font,waypoint+Vector2(12,20),"Local encounter",HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("91e4d4"))
	var position: Array = world.global_position()
	var p := point(float(position[0])/world.MAP_SCALE,float(position[2])/world.MAP_SCALE)
	if world.autopilot and world.destination>=0:
		var target: Dictionary = session.stations[world.destination]
		draw_dashed_line(p,point(target.x,target.y),Color("97e4d3"),2,6)
	var direction:=heading()
	if direction.length_squared()<.001:
		draw_circle(p,4,Color("f4fafb")) # Straight up/down has no planar heading.
	else:
		var right:=Vector2(-direction.y,direction.x)
		draw_colored_polygon(PackedVector2Array([p+direction*9,p-direction*6-right*5,p-direction*6+right*5]),Color("f4fafb"))
func heading() -> Vector2:
	if world==null or world.region==null:return Vector2.ZERO
	var forward: Array=world.region.player.pose.forward
	var planar:=Vector2(forward[0],forward[2])
	return planar.normalized() if planar.length()>32 else Vector2.ZERO
func _gui_input(event: InputEvent) -> void:
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
	if id>=0:selected_id=id;selected.emit(id);queue_redraw()
func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT,NOTIFICATION_VISIBILITY_CHANGED]:
		touches.clear();dragging=false;tap_allowed=false
