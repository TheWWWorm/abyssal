extends Control
## The chart's side view. The original turns the circle under its cursor into a
## cross-section: the stations inside it laid out west to east by where they sit
## in the circle and top to bottom by depth, between the fixed marks of 15000
## and 30000 metres, with the water the ship cannot take greyed out above
## (radiation) and below (pressure). Left and right step through them in that
## order and wrap round, as its soft keys do.
signal selected(id: int)
const Map = preload("res://native/presentation/overworld_map.gd")
const TOP_DEPTH := 15000
const BOTTOM_DEPTH := 30000
## Room kept at each end for the stepping arrows, and on the right for the
## depth marks.
const ARROW_ROOM := 34.0
const SCALE_ROOM := 66.0
## Five bands, shallow to deep, on the chart's own blues: the original's map
## steps its water the same way (15000, 20000, 25000 and 30000 on the
## boundaries), from pale above the marks to near black below them.
const BANDS := [Color("5872dc"),Color("4360cc"),Color("2f43b4"),Color("1f2d86"),Color("121a52")]
var world
var art
var center := Vector2(50,50)
var radius := 16.0
## Stations under the lens, west to east.
var ids: Array = []
var selected_id := -1
var press_at := Vector2.ZERO
var pressing := false

func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_STOP
	focus_mode=Control.FOCUS_ALL
	clip_contents=true
	custom_minimum_size=Vector2(200,130)
	tooltip_text="◀ ▶ step through the stations in this slice"

func frame(lens_center: Vector2, lens_radius: float, selection: int) -> void:
	"""Takes the stations inside the lens. The selection is kept in the slice
	even when it lies outside it, so the station the card describes is always
	one of the marks."""
	center=lens_center;radius=maxf(lens_radius,1.0);selected_id=selection
	ids=[]
	if world==null:return
	for station in world.session.stations:
		if station.id==selection or Vector2(station.x,station.y).distance_to(center)<=radius:ids.append(station.id)
	ids.sort_custom(func(a,b):
		var first: Dictionary=world.session.stations[a];var second: Dictionary=world.session.stations[b]
		return first.x<second.x or (first.x==second.x and a<b))
	queue_redraw()

func field() -> Rect2:
	return Rect2(Vector2.ZERO,Vector2(maxf(1,size.x-SCALE_ROOM),size.y))

func depth_y(depth: float) -> float:
	# The marks sit an eighth in from each edge, as on the original, so the
	# water beyond them still shows.
	return size.y*(0.125+0.75*(depth-TOP_DEPTH)/float(BOTTOM_DEPTH-TOP_DEPTH))

func station_point(station: Dictionary) -> Vector2:
	var area := field()
	var across := clampf((float(station.x)-(center.x-radius))/(2.0*radius),0.0,1.0)
	return Vector2(area.position.x+ARROW_ROOM+across*maxf(1,area.size.x-2*ARROW_ROOM),clampf(depth_y(station.depth),6,size.y-6))

func _draw() -> void:
	var area := field()
	var marks := [TOP_DEPTH,20000,25000,BOTTOM_DEPTH]
	var edges: Array=[0.0]
	for depth in marks:edges.append(depth_y(depth))
	edges.append(size.y)
	for band in BANDS.size():
		draw_rect(Rect2(0,edges[band],size.x,edges[band+1]-edges[band]),BANDS[band])
	draw_rect(Rect2(area.end.x,0,SCALE_ROOM,size.y),Color("08102e"))
	if world==null:return
	var ship=world.session.ship
	var shallow := clampf(depth_y(ship.minimum_depth),0,size.y)
	var deep := clampf(depth_y(ship.maximum_depth),0,size.y)
	# The water outside the hull's limits goes dark, the radiation side with
	# a red cast to it, and each limit gets the original's hatched edge.
	draw_rect(Rect2(0,0,area.size.x,shallow),Color(0.03,0.04,0.12,0.62))
	for step in 6:
		draw_rect(Rect2(0,shallow*step/6.0,area.size.x,shallow/6.0),Color(0.85,0.2,0.2,0.16*(1.0-step/6.0)))
	draw_rect(Rect2(0,deep,area.size.x,size.y-deep),Color(0.01,0.02,0.07,0.66))
	for edge in [shallow,deep]:
		draw_dashed_line(Vector2(0,edge),Vector2(area.size.x,edge),Color("ff8f8f") if edge==shallow else Color("9fb4ff"),1.5,8)
		var x := -6.0
		while x<area.size.x:
			var top: float=edge-6 if edge==shallow else edge+1
			draw_line(Vector2(x,top+5),Vector2(x+5,top),Color(0,0,0,0.35),1)
			x+=5
	var font: Font=get_theme_default_font()
	for depth in marks:
		var y := depth_y(depth)
		draw_line(Vector2(area.end.x-6,y),Vector2(area.end.x+4,y),Color("9fb4ff"),1.5)
		draw_string(font,Vector2(area.end.x+8,y+5),str(depth),HORIZONTAL_ALIGNMENT_LEFT,SCALE_ROOM-10,13,Color("c9d7ff"))
	legend_mark(Vector2(8,8),"map_radiation","Radiation",false)
	legend_mark(Vector2(8,size.y-8),"map_pressure","Pressure",true)
	if ids.size()>1:
		var middle := size.y*0.5
		for side in [-1,1]:
			var tip := Vector2(area.position.x+8 if side<0 else area.end.x-8,middle)
			var back: float=tip.x-side*12
			draw_colored_polygon(PackedVector2Array([tip,Vector2(back,middle-10),Vector2(back,middle+10)]),Color("75ebe8"))
	var chosen := {}
	for id in ids:
		var station: Dictionary=world.session.stations[id]
		var colors: Dictionary=Map.marker(world,station)
		var p := station_point(station)
		if id==selected_id:chosen=station
		Map.pixel_square(self,p,9.0 if colors.discovered else 7.0,3.0,colors.body,colors.core)
	if not chosen.is_empty():
		# The selected mark gets the chart's ring and a name tag beside it,
		# turned to whichever side has room.
		var p := station_point(chosen)
		draw_arc(p,11,0,TAU,24,Color.WHITE,2,true)
		var width := font.get_string_size(chosen.name,HORIZONTAL_ALIGNMENT_LEFT,-1,15).x+14
		var left := p.x+16
		if left+width>area.end.x-ARROW_ROOM:left=p.x-16-width
		var tag := Rect2(left,clampf(p.y-28,2,size.y-26),width,24)
		draw_rect(tag,Color("071631e6"))
		draw_rect(tag,Color("9fb4ff"),false,1)
		draw_string(font,tag.position+Vector2(7,17),chosen.name,HORIZONTAL_ALIGNMENT_LEFT,-1,15,Color("eef6ff"))
	if has_focus():draw_rect(Rect2(Vector2.ONE,size-Vector2(2,2)),Color("e5ae63"),false,2)

func legend_mark(at: Vector2, image: String, text: String, bottom: bool) -> void:
	var icon: Texture2D=art.symbol(image) if art!=null else null
	var x := at.x
	if icon!=null:
		var box := Vector2(22,22)
		draw_texture_rect(icon,Rect2(Vector2(x,at.y-box.y if bottom else at.y),box),false,Color(1,1,1,0.75))
		x+=box.x+6
	draw_string(get_theme_default_font(),Vector2(x,at.y-6 if bottom else at.y+16),text,HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color(1,1,1,0.72))

func step(direction: int) -> void:
	if ids.is_empty():return
	var index: int=ids.find(selected_id)
	index=0 if index<0 else (index+direction+ids.size())%ids.size()
	choose(ids[index])

func choose(id: int) -> void:
	selected_id=id;queue_redraw();selected.emit(id)

func tap(position: Vector2) -> void:
	var area := field()
	if ids.size()>1 and position.x<area.position.x+ARROW_ROOM:step(-1);return
	if ids.size()>1 and position.x>area.end.x-ARROW_ROOM and position.x<=area.end.x:step(1);return
	var nearest := 24.0;var id := -1
	for candidate in ids:
		var distance := station_point(world.session.stations[candidate]).distance_to(position)
		if distance<nearest:nearest=distance;id=candidate
	if id>=0:choose(id)

func _gui_input(event: InputEvent) -> void:
	# A press that travels is a drag across the panel, not a choice; touch
	# arrives here as the emulated left button.
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		if event.pressed:pressing=true;press_at=event.position
		elif pressing:
			pressing=false
			if event.position.distance_to(press_at)<14:tap(event.position)
		accept_event()
	elif event.is_action_pressed("ui_left"):step(-1);accept_event()
	elif event.is_action_pressed("ui_right"):step(1);accept_event()

func _notification(what: int) -> void:
	if what in [NOTIFICATION_FOCUS_ENTER,NOTIFICATION_FOCUS_EXIT]:queue_redraw()
	if what==NOTIFICATION_VISIBILITY_CHANGED:pressing=false
