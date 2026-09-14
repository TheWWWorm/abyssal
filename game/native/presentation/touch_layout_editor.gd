extends Control
## Places the touch controls by hand. The live overlay keeps drawing them, so
## what a player drags is the control itself rather than a stand-in, and the
## panel sits in the middle of the screen the flight controls leave free.
const Layout = preload("res://native/input/touch_layout.gd")
signal closed(layout: Dictionary)
var touch
var working := {}
var restore := {}
var anchors := {}
var selected := ""
var finger := -1
var grab := Vector2.ZERO
var panel: PanelContainer
var caption: Label
var unit := 1.0
var panel_finger := -1
var panel_grab := Vector2.ZERO

func configure(controls) -> void:
	touch=controls
	restore=Layout.sanitize(touch.layout)
	working=restore.duplicate(true)
	mouse_filter=Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	touch.layout_preview=true
	touch.refresh_visibility()
	# Turning the device mid-edit gives a different composition, so the anchors
	# a drag is measured against have to be taken again.
	touch.resized.connect(capture_anchors)
	capture_anchors()
	build_panel()
	select(Layout.IDS[-1])

func capture_anchors() -> void:
	"""Measures every control where the standard composition puts it, so a drag
	is always an offset from that anchor however far the last one wandered."""
	touch.layout={}
	touch.arrange()
	unit=touch.unit
	for id in Layout.IDS:
		var area: Rect2 = touch.control_rect(id)
		if area.size.x<=0: continue
		anchors[id]=area.get_center()/maxf(unit,.001)
	apply()

func apply() -> void:
	touch.layout=working
	touch.arrange()
	touch.refresh_visibility()
	unit=touch.unit
	queue_redraw()
	refresh_caption()

func build_panel() -> void:
	panel=PanelContainer.new()
	add_child(panel)
	panel.mouse_filter=Control.MOUSE_FILTER_STOP
	panel.gui_input.connect(drag_panel)
	var skin := StyleBoxFlat.new()
	skin.bg_color=Color("061923f2");skin.border_color=Color("52b8d0");skin.set_border_width_all(1)
	skin.content_margin_left=18;skin.content_margin_right=18;skin.content_margin_top=12;skin.content_margin_bottom=14
	panel.add_theme_stylebox_override("panel",skin)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation",8)
	panel.add_child(rows)
	rows.add_child(text("ADJUST TOUCH CONTROLS",15,Color("8bd6ee")))
	var hint := text("Drag any control to move it. Tap one to select it, then resize it. Drag this panel itself if it sits over a control you need.",13,Color("a2c3d3"))
	hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size.x=minf(size.x*.8,340)
	rows.add_child(hint)
	caption=text("",14,Color("d7c399"))
	rows.add_child(caption)
	var sizing := HFlowContainer.new()
	sizing.alignment=FlowContainer.ALIGNMENT_CENTER
	rows.add_child(sizing)
	for item in [["Smaller",resize.bind(-Layout.SCALE_STEP)],["Bigger",resize.bind(Layout.SCALE_STEP)],
			["Next control",cycle],["Reset this",reset_selected]]:
		sizing.add_child(action(item[0],item[1]))
	var finishing := HFlowContainer.new()
	finishing.alignment=FlowContainer.ALIGNMENT_CENTER
	rows.add_child(finishing)
	for item in [["Reset all",reset_all],["Cancel",func(): closed.emit(restore)],["Done",func(): closed.emit(working)]]:
		finishing.add_child(action(item[0],item[1]))
	place_panel.call_deferred()

func place_panel() -> void:
	"""Puts the panel wherever it hides the fewest controls. The middle of the
	screen is usually free, but a player who has already moved things there, or a
	tall narrow screen, needs it somewhere else."""
	var span: Vector2 = panel.size
	if span.x<=0: span=panel.get_combined_minimum_size()
	var margin := 12.0
	var best := Vector2(maxf(margin,(size.x-span.x)*.5),maxf(margin,(size.y-span.y)*.5))
	var lowest := INF
	var spots: Array[Vector2] = [best,Vector2((size.x-span.x)*.5,margin),Vector2((size.x-span.x)*.5,size.y-span.y-margin),
			Vector2(margin,(size.y-span.y)*.5),Vector2(size.x-span.x-margin,(size.y-span.y)*.5),
			Vector2(margin,margin),Vector2(size.x-span.x-margin,margin),
			Vector2(margin,size.y-span.y-margin),Vector2(size.x-span.x-margin,size.y-span.y-margin)]
	for spot in spots:
		var at := spot.clamp(Vector2(margin,margin),(size-span-Vector2(margin,margin)).max(Vector2(margin,margin)))
		var cost := 0.0
		for id in Layout.IDS:
			var area: Rect2 = touch.control_rect(id)
			if area.size.x<=0: continue
			var shared := Rect2(at,span).intersection(area)
			cost += shared.size.x*shared.size.y
		if cost<lowest: lowest=cost;best=at
		if cost<=0: break
	panel.position=best

func drag_panel(event: InputEvent) -> void:
	if event is InputEventMouse and event.device==InputEvent.DEVICE_ID_EMULATION: return
	if event is InputEventScreenTouch or (event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT):
		var index: int = event.index if event is InputEventScreenTouch else -3
		if event.pressed:
			panel_finger=index
			panel_grab=event.position
		elif panel_finger==index: panel_finger=-1
		panel.accept_event()
	elif (event is InputEventScreenDrag and event.index==panel_finger) or (event is InputEventMouseMotion and panel_finger==-3):
		panel.position=(panel.position+event.position-panel_grab).clamp(Vector2.ZERO,(size-panel.size).max(Vector2.ZERO))
		panel.accept_event()

func text(value: String, font_size: int, color: Color) -> Label:
	var node := Label.new()
	node.text=value
	node.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	node.add_theme_font_size_override("font_size",font_size)
	node.modulate=color
	return node

func action(value: String, act: Callable) -> Button:
	var node := Button.new()
	node.text=value
	node.focus_mode=Control.FOCUS_NONE
	node.custom_minimum_size=Vector2(96,40)
	node.add_theme_font_size_override("font_size",14)
	node.pressed.connect(act)
	return node

func refresh_caption() -> void:
	if caption==null: return
	caption.text="%s  ·  %d%%" % [Layout.NAMES.get(selected,selected),roundi(Layout.scale_of(working,selected)*100)]

func select(id: String) -> void:
	selected=id
	refresh_caption()
	queue_redraw()

func cycle() -> void:
	var placed: Array[String] = Layout.IDS.filter(func(id): return touch.control_rect(id).size.x>0)
	if placed.is_empty(): return
	select(placed[(placed.find(selected)+1)%placed.size()])

func resize(step: float) -> void:
	if selected.is_empty(): return
	working=Layout.adjusted(working,selected,Layout.offset_of(working,selected),
		clampf(Layout.scale_of(working,selected)+step,Layout.MIN_SCALE,Layout.MAX_SCALE))
	apply()

func reset_selected() -> void:
	if selected.is_empty(): return
	working.erase(selected)
	apply()

func reset_all() -> void:
	working={}
	apply()

func at(point: Vector2) -> String:
	## IDS runs the small controls first, so an overlapping pair picks the one a
	## finger is least likely to have meant by accident.
	for id in Layout.IDS:
		var area: Rect2 = touch.control_rect(id)
		if area.size.x>0 and area.has_point(point): return id
	return ""

func move_to(point: Vector2) -> void:
	if selected.is_empty() or not anchors.has(selected): return
	var half: Vector2 = touch.control_rect(selected).size*.5
	# Stop where the whole control is still on screen, so the stored offset and
	# the placed control never disagree about where the finger is. The bounds
	# are the overlay's own, which is the space control_rect() reports in.
	var placed := (point-grab).clamp(half,touch.size-half)
	working=Layout.adjusted(working,selected,placed/maxf(unit,.001)-anchors[selected],
		Layout.scale_of(working,selected))
	apply()

func begin(point: Vector2, index: int) -> bool:
	var id := at(point)
	if id.is_empty(): return false
	select(id)
	grab=point-touch.control_rect(id).get_center()
	finger=index
	# The panel would otherwise sit between the player and where they are
	# dragging a control to. It returns the moment the finger lifts.
	panel.hide()
	return true

func finish() -> void:
	finger=-1
	panel.show()
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouse and event.device==InputEvent.DEVICE_ID_EMULATION: return
	if event is InputEventScreenTouch:
		if event.pressed: begin(event.position,event.index)
		elif event.index==finger: finish()
		accept_event()
	elif event is InputEventScreenDrag and event.index==finger:
		move_to(event.position)
		accept_event()
	elif event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		if event.pressed: begin(event.position,-2)
		elif finger==-2: finish()
		accept_event()
	elif event is InputEventMouseMotion and finger==-2:
		move_to(event.position)
		accept_event()

func _exit_tree() -> void:
	if is_instance_valid(touch):
		touch.layout_preview=false
		touch.refresh_visibility()
		if touch.resized.is_connected(capture_anchors): touch.resized.disconnect(capture_anchors)

func _draw() -> void:
	if touch==null or not is_instance_valid(touch): return
	var font := ThemeDB.fallback_font
	var body := maxi(11,roundi(13*unit))
	for id in Layout.IDS:
		var area: Rect2 = touch.control_rect(id)
		if area.size.x<=0: continue
		var chosen := id==selected
		var grown := area.grow(3*unit)
		draw_rect(grown,Color(0,.08,.12,.35 if chosen else .18),true)
		draw_rect(grown,Color("7defff") if chosen else Color("2f8ea0"),false,maxf(1,unit*(1.8 if chosen else .9)),true)
		# Name every control on itself: the overlay's own caption can be missing
		# entirely on a control drawn as a ring, and a player resizing something
		# needs to know which thing it is. The name rides the top edge so it does
		# not land on the caption the overlay already centres in the same box.
		var name: String = Layout.NAMES.get(id,id)
		var caption_size: Vector2 = font.get_string_size(name,HORIZONTAL_ALIGNMENT_LEFT,-1,body)
		var at := Vector2(area.get_center().x-caption_size.x*.5,grown.position.y+caption_size.y*.86)
		draw_rect(Rect2(at-Vector2(5,caption_size.y*.82),caption_size+Vector2(10,5)),Color(.02,.09,.13,.9),true)
		draw_string(font,at,name,HORIZONTAL_ALIGNMENT_LEFT,-1,body,Color("d9f6ff") if chosen else Color("9fc9d6"))
		if chosen:
			var amount := "%d%%" % roundi(Layout.scale_of(working,id)*100)
			var amount_size: Vector2 = font.get_string_size(amount,HORIZONTAL_ALIGNMENT_LEFT,-1,body)
			var below := Vector2(area.get_center().x-amount_size.x*.5,grown.end.y-amount_size.y*.25)
			draw_rect(Rect2(below-Vector2(5,amount_size.y*.82),amount_size+Vector2(10,5)),Color(.02,.09,.13,.9),true)
			draw_string(font,below,amount,HORIZONTAL_ALIGNMENT_LEFT,-1,body,Color("d7c399"))
