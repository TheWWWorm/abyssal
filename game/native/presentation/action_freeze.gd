extends Control
## A dive held still so it can be looked at. Only the inspection camera moves:
## the simulation is not advanced, no state is written and resuming puts the
## camera back exactly where the flight view had it.
signal closed(resume: bool)
var game
var saved_camera := Transform3D.IDENTITY
var saved_fov := 0.0
var saved_headlights := true
var saved_audio: Array = []
var restored := false
var pivot := Vector3.ZERO
var home_pivot := Vector3.ZERO
var yaw := 0.0
var pitch := 0.0
var distance := 50.0
var minimum_distance := 4.0
var toolbar: PanelContainer
var controls_visible := true
var fingers := {}
var pinch_span := 0.0
var pinch_center := Vector2.ZERO

func configure(owner) -> void:
	game=owner
	saved_camera=game.camera.global_transform
	saved_fov=game.camera.fov
	saved_headlights=game.graphics.headlights
	hold_audio(game.dive_audio)
	mouse_filter=Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var subject = game.view.player_model
	home_pivot=subject.global_transform*subject.solid_bounds().get_center() if subject!=null else saved_camera.origin
	minimum_distance=maxf(3.0,subject.solid_bounds().size.length()*.7) if subject!=null else 4.0
	reset_camera()
	build_toolbar()

func hold_audio(node: Node) -> void:
	if node is AudioStreamPlayer or node is AudioStreamPlayer3D:
		saved_audio.append([node,node.stream_paused])
		node.stream_paused=true
	for child in node.get_children(): hold_audio(child)

func restore_scene() -> void:
	if restored: return
	restored=true
	if is_instance_valid(game):
		game.camera.global_transform=saved_camera
		game.camera.fov=saved_fov
		game.abyss.set_headlights(game.modern_graphics and saved_headlights)
	for record in saved_audio:
		if is_instance_valid(record[0]): record[0].stream_paused=record[1]

func _exit_tree() -> void: restore_scene()

func caption(text: String, size: int, parent: Node) -> Label:
	var node := Label.new()
	node.text=text
	node.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	node.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	node.add_theme_font_size_override("font_size",size)
	node.modulate=Color("9ddbea")
	parent.add_child(node)
	return node

func build_toolbar() -> void:
	# A container that fills the view and packs to its end keeps the bar on screen
	# whatever it ends up measuring. Anchoring the panel itself placed it by the
	# size it had before its rows existed, which was none, and put it off screen.
	var column := VBoxContainer.new()
	add_child(column)
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.alignment=BoxContainer.ALIGNMENT_END
	column.mouse_filter=Control.MOUSE_FILTER_IGNORE
	toolbar=PanelContainer.new()
	column.add_child(toolbar)
	var skin := StyleBoxFlat.new()
	skin.bg_color=Color("061923e0");skin.border_color=Color("52b8d0");skin.set_border_width_all(1)
	skin.content_margin_left=16;skin.content_margin_right=16;skin.content_margin_top=8;skin.content_margin_bottom=10
	toolbar.add_theme_stylebox_override("panel",skin)
	var rows := VBoxContainer.new()
	toolbar.add_child(rows)
	var touching: bool=game!=null and game.touch.enabled()
	caption("ACTION FREEZE  ·  "+("Drag to orbit  ·  Two fingers to pan and zoom" if touching
		else "Drag to orbit  ·  Right-drag to pan  ·  Wheel to zoom"),14,rows)
	var actions := HFlowContainer.new()
	actions.alignment=FlowContainer.ALIGNMENT_CENTER
	rows.add_child(actions)
	for item in [["−",zoom.bind(1.15)],["+",zoom.bind(1.0/1.15)],["Lights",toggle_lights],
			["Reset camera",reset_camera],["Hide panel",toggle_panel],
			["Back to pause",dismiss.bind(false)],["Resume dive",dismiss.bind(true)]]:
		var node := Button.new()
		node.text=item[0]
		node.custom_minimum_size=Vector2(74,38)
		node.add_theme_font_size_override("font_size",15)
		node.focus_mode=Control.FOCUS_NONE
		node.pressed.connect(item[1])
		actions.add_child(node)
	caption(("Double-tap to bring the panel back" if touching
		else "H panel  ·  R reset  ·  L lights  ·  Esc back  ·  Pad: right stick orbit, left stick pan, triggers zoom"),11,rows)

func dismiss(resume: bool) -> void:
	"""Marks the event handled before tearing anything down: emitting first frees
	this node, and the handler would then be finishing on a freed viewport."""
	var window := get_viewport()
	if window!=null: window.set_input_as_handled()
	closed.emit.call_deferred(resume)
func toggle_panel() -> void:
	controls_visible=not controls_visible
	toolbar.visible=controls_visible

func toggle_lights() -> void:
	# Cosmetic only while frozen; restore_scene() puts the player's choice back.
	game.abyss.set_headlights(not game.abyss.headlights_enabled)

func reset_camera() -> void:
	pivot=home_pivot
	var offset: Vector3 = saved_camera.origin-pivot
	if offset.length()<minimum_distance: offset=saved_camera.basis.z*minimum_distance*2.0
	distance=offset.length()
	yaw=atan2(offset.x,offset.z)
	pitch=asin(clampf(offset.y/maxf(distance,.001),-.9999,.9999))
	apply_camera()

func orbit(movement: Vector2) -> void:
	yaw-=movement.x*.006
	pitch=clampf(pitch+movement.y*.006,-PI*.47,PI*.47)
	apply_camera()

func pan(movement: Vector2) -> void:
	pivot+=(game.camera.global_basis.x*-movement.x+game.camera.global_basis.y*movement.y)*distance*.0015
	apply_camera()

func zoom(multiplier: float) -> void:
	distance=clampf(distance*multiplier,minimum_distance,2500)
	apply_camera()

func apply_camera() -> void:
	game.camera.global_position=pivot+Vector3(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch))*distance
	game.camera.look_at(pivot,Vector3.UP)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouse and event.device==InputEvent.DEVICE_ID_EMULATION: return
	if event is InputEventMouseMotion:
		if event.button_mask & MOUSE_BUTTON_MASK_LEFT: orbit(event.relative)
		elif event.button_mask & MOUSE_BUTTON_MASK_RIGHT: pan(event.relative)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index==MOUSE_BUTTON_WHEEL_UP: zoom(1.0/1.12)
		elif event.button_index==MOUSE_BUTTON_WHEEL_DOWN: zoom(1.12)
	elif event is InputEventScreenTouch:
		if event.pressed:
			if event.double_tap: toggle_panel()
			fingers[event.index]=event.position
		else: fingers.erase(event.index)
		pinch_span=0
	elif event is InputEventScreenDrag and fingers.has(event.index):
		fingers[event.index]=event.position
		if fingers.size()==1: orbit(event.relative)
		elif fingers.size()==2:
			var points: Array = fingers.values()
			var span: float = points[0].distance_to(points[1])
			var center: Vector2 = (points[0]+points[1])*.5
			if pinch_span>0 and span>0:
				zoom(pinch_span/span)
				pan(center-pinch_center)
			pinch_span=span
			pinch_center=center
	accept_event()

func _input(event: InputEvent) -> void:
	if not visible: return
	# Escape and the pad's cancel button must never fall through to the dive
	# behind this view, whichever of the two spellings the platform sends.
	if event is InputEventKey and event.pressed and not event.echo:
		var code: int = event.keycode if event.keycode!=0 else event.physical_keycode
		match code:
			KEY_H: toggle_panel()
			KEY_R: reset_camera()
			KEY_L: toggle_lights()
			KEY_ESCAPE, KEY_P: dismiss(false); return
			_: return
		var window := get_viewport()
		if window!=null: window.set_input_as_handled()
	elif event is InputEventJoypadButton and event.pressed:
		match event.button_index:
			JOY_BUTTON_Y: toggle_panel()
			JOY_BUTTON_X: reset_camera()
			JOY_BUTTON_A: dismiss(true); return
			JOY_BUTTON_B, JOY_BUTTON_START: dismiss(false); return
			_: return
		var window := get_viewport()
		if window!=null: window.set_input_as_handled()

func _process(seconds: float) -> void:
	var devices := Input.get_connected_joypads()
	if devices.is_empty(): return
	var device: int = devices[0]
	var look := Vector2(Input.get_joy_axis(device,JOY_AXIS_RIGHT_X),Input.get_joy_axis(device,JOY_AXIS_RIGHT_Y))
	if look.length()>.15: orbit(look*seconds*150)
	var slide := Vector2(Input.get_joy_axis(device,JOY_AXIS_LEFT_X),Input.get_joy_axis(device,JOY_AXIS_LEFT_Y))
	if slide.length()>.15: pan(slide*seconds*150)
	var closer := Input.get_joy_axis(device,JOY_AXIS_TRIGGER_LEFT)-Input.get_joy_axis(device,JOY_AXIS_TRIGGER_RIGHT)
	if absf(closer)>.1: zoom(exp(closer*seconds))
