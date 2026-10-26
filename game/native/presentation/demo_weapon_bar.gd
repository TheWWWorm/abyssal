extends PanelContainer
## A flight overlay: each pointer keeps its owner through a drag or release.
signal stepped(direction: int)
signal finished
const StationTheme=preload("res://native/presentation/station_theme.gd")
var previous := Button.new()
var next := Button.new()
var restore := Button.new()
var picture := TextureRect.new()
var heading := Label.new()
var title := Label.new()
var hint := Label.new()
var contacts := {}
var last_touch_ms := -1000000
var touch_layout := false

func _ready() -> void:
	z_index=65;mouse_filter=Control.MOUSE_FILTER_IGNORE
	var panel := StationTheme.frame(Color("06202eef"),Color("368ba6"),8,1)
	panel.set_content_margin_all(8);add_theme_stylebox_override("panel",panel)
	var column := VBoxContainer.new();column.add_theme_constant_override("separation",4);add_child(column)
	var row := HBoxContainer.new();row.add_theme_constant_override("separation",6);column.add_child(row)
	for entry in [[previous,"‹",tr("Previous weapon")],[next,"›",tr("Next weapon")],[restore,"×",tr("Restore fitted weapons")]]:
		var control: Button=entry[0];control.text=entry[1];control.tooltip_text=entry[2]
		control.custom_minimum_size=Vector2(44,48);control.focus_mode=Control.FOCUS_NONE;control.mouse_filter=Control.MOUSE_FILTER_IGNORE
		control.add_theme_font_size_override("font_size",26)
		control.add_theme_color_override("font_color",Color("91e4f4"))
		for state in ["normal","hover","pressed","focus","disabled"]:control.add_theme_stylebox_override(state,StationTheme.button_state(false,state))
	row.add_child(previous)
	picture.custom_minimum_size=Vector2(36,36);picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;row.add_child(picture)
	var words := VBoxContainer.new();words.size_flags_horizontal=Control.SIZE_EXPAND_FILL;words.size_flags_vertical=Control.SIZE_SHRINK_CENTER;row.add_child(words)
	for entry in [[heading,11,Color("93b9c7")],[title,17,Color("d1f2f8")]]:
		var label: Label=entry[0];label.add_theme_font_size_override("font_size",entry[1]);label.add_theme_color_override("font_color",entry[2])
		label.clip_text=true;label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;words.add_child(label)
	title.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;title.max_lines_visible=2;title.custom_minimum_size.y=44
	row.add_child(next);row.add_child(restore)
	hint.add_theme_font_size_override("font_size",12);hint.add_theme_color_override("font_color",Color("93b9c7"));hint.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	hint.clip_text=true;column.add_child(hint)
	previous.pressed.connect(func():stepped.emit(-1));next.pressed.connect(func():stepped.emit(1));restore.pressed.connect(func():finished.emit())
	hide()

func show_weapon(name_text: String, icon: Texture2D, index: int, total: int, prompt: String) -> void:
	if title.text!=name_text:title.text=name_text
	if picture.texture!=icon:picture.texture=icon
	heading.text="%d / %d · "%[index+1,total]+tr("Quick weapon test").to_upper()
	hint.text=prompt

func set_touch(enabled: bool) -> void:
	if touch_layout==enabled:return
	touch_layout=enabled
	for control in [previous,next,restore]:control.custom_minimum_size=Vector2(68,68) if enabled else Vector2(44,48)
	title.add_theme_font_size_override("font_size",20 if enabled else 17)
	title.custom_minimum_size.y=48 if enabled else 44
	heading.add_theme_font_size_override("font_size",13 if enabled else 11)
	hint.add_theme_font_size_override("font_size",15 if enabled else 12)
	picture.custom_minimum_size=Vector2(44,44) if enabled else Vector2(36,36)

func contains(point: Vector2) -> bool:
	return visible and get_global_rect().has_point(point)

func button_at(point: Vector2) -> Button:
	for control in [previous,next,restore]:
		if control.get_global_rect().has_point(point):return control
	return null

func handle_pointer(event: InputEvent, mouse_available: bool) -> bool:
	var pointer := -1
	var point := Vector2.ZERO
	var pressed := false
	var released := false
	var canceled := false
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		last_touch_ms=Time.get_ticks_msec();pointer=event.index;point=event.position
		if event is InputEventScreenTouch:pressed=event.pressed;released=not event.pressed;canceled=event.canceled
	elif event is InputEventMouseButton or event is InputEventMouseMotion:
		if not mouse_available:return false
		point=event.position
		# A tap already activated its button on touchend. Ignore its browser
		# compatibility click rather than advancing twice.
		if event.device==InputEvent.DEVICE_ID_EMULATION or Time.get_ticks_msec()-last_touch_ms<750:return contains(point)
		if event is InputEventMouseButton:
			if event.button_index!=MOUSE_BUTTON_LEFT:return contains(point)
			pressed=event.pressed;released=not event.pressed
	else:return false
	if pressed and contains(point):
		var control := button_at(point)
		contacts[pointer]={"button":control,"start":point,"valid":true}
		if control!=null:control.modulate=Color(1.35,1.35,1.35)
		return true
	if not contacts.has(pointer):return false
	var contact: Dictionary=contacts[pointer]
	var target: Button=contact.button
	if point.distance_to(contact.start)>24:contact.valid=false
	if released:
		contacts.erase(pointer)
		if target!=null:
			target.modulate=Color.WHITE
			if not canceled and contact.valid and visible and target.get_global_rect().has_point(point):target.pressed.emit()
	return true

func release_contacts() -> void:
	contacts.clear()
	for control in [previous,next,restore]:control.modulate=Color.WHITE
