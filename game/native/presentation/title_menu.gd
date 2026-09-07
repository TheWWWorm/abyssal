extends Control
## Classic menu structure with scalable desktop controls and imported title art.
signal continued
signal started
signal settings_requested
signal tools_requested
signal quit_requested
var continue_button: Button
var new_button: Button
var status: Label
var subtitle: Label
var headline: Label
var rule: ColorRect
var choices := VBoxContainer.new()
var footer: Button
var edition: Label
var logo := TextureRect.new()
var panel := PanelContainer.new()
var menu_title: Label
var help := Label.new()
var help_open := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	headline=caption("ABYSSAL",42,Color("cdeaf5"))
	subtitle=caption("COMPATIBILITY ENGINE",13,Color("76acc3"))
	add_child(logo);logo.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;logo.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;logo.mouse_filter=Control.MOUSE_FILTER_IGNORE;logo.hide()
	add_child(panel)
	var skin := StyleBoxFlat.new();skin.bg_color=Color("142e3f");skin.border_color=Color("5197b2");skin.set_border_width_all(1)
	skin.content_margin_left=12;skin.content_margin_right=12;skin.content_margin_top=10;skin.content_margin_bottom=14
	panel.add_theme_stylebox_override("panel",skin)
	panel.add_child(choices);choices.add_theme_constant_override("separation",4)
	menu_title=Label.new();menu_title.text="Menu";menu_title.add_theme_font_size_override("font_size",16);menu_title.modulate=Color("aedbec");choices.add_child(menu_title)
	new_button=entry("Start new game",func():started.emit())
	continue_button=entry("Load game",func():continued.emit())
	entry("Options",func():settings_requested.emit())
	entry("Help",toggle_help)
	if not OS.has_feature("web"):entry("Exit",func():quit_requested.emit())
	status=caption("Choose your DEEP JAR to begin.",15,Color("a2c3d3"));status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;status.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	footer=entry("Choose game JAR…",func():tools_requested.emit(),false)
	edition=caption("ABYSSAL  /  ENGINE PREVIEW",12,Color("78a3b7"))
	rule=ColorRect.new();rule.color=Color("377691");rule.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(rule)
	add_child(help);help.hide();help.text="Mouse · Steer    W / S · Throttle\nM · World map    R · Autopilot (hold: quest)    T · Time 1×/2×; autopilot to 16×\nE · Dock    Esc · Menu    F11 · Fullscreen\n\nTouch: flight pads + action buttons. Gamepad: left stick + triggers.\nD-pad speed / menus · A select / fire · Start pause."
	help.add_theme_font_size_override("font_size",15);help.modulate=Color("b2d5e5");help.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;help.mouse_filter=Control.MOUSE_FILTER_IGNORE
	resized.connect(layout);layout()

func load_content(directory: String) -> void:
	var file := directory.path_join("data/interface/logo.png")
	if not FileAccess.file_exists(file):return
	var pixels := Image.load_from_file(file)
	if pixels==null:return
	logo.texture=ImageTexture.create_from_image(pixels);logo.show();headline.hide();subtitle.hide()

func caption(value: String, font_size: int, color: Color) -> Label:
	var node := Label.new();node.text=value;node.add_theme_font_size_override("font_size",font_size);node.modulate=color;node.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(node);return node

func entry(value: String, action: Callable, in_list: bool=true) -> Button:
	var node := Button.new();node.text=value;node.alignment=HORIZONTAL_ALIGNMENT_LEFT if in_list else HORIZONTAL_ALIGNMENT_CENTER
	node.custom_minimum_size=Vector2(310,42);node.add_theme_font_size_override("font_size",19)
	for state in ["normal","hover","focus","pressed","disabled"]:
		var skin := StyleBoxFlat.new();skin.bg_color=Color("234e65") if state in ["hover","focus","pressed"] else Color("142e3f")
		skin.border_color=Color("8cd6ef") if state in ["focus","pressed"] else Color("468ba7")
		skin.set_border_width_all(1 if state in ["hover","focus","pressed"] or not in_list else 0)
		skin.content_margin_left=12;skin.content_margin_right=12;skin.content_margin_top=6;skin.content_margin_bottom=6
		node.add_theme_stylebox_override(state,skin)
	node.add_theme_color_override("font_color",Color("e0eff5"));node.add_theme_color_override("font_disabled_color",Color("6a8494"))
	(choices if in_list else self).add_child(node);node.pressed.connect(action);return node

func toggle_help() -> void:
	help_open=not help_open;help.visible=help_open;status.visible=not help_open;layout()

func layout() -> void:
	if status==null:return
	var unit := clampf(minf(size.x/1000.0,size.y/720.0),0.8,2.5)
	var middle := size.x*.5
	headline.scale=Vector2.ONE*unit;headline.position=Vector2(middle-headline.get_minimum_size().x*unit*.5,38*unit)
	subtitle.scale=Vector2.ONE*unit;subtitle.position=Vector2(middle-subtitle.get_minimum_size().x*unit*.5,91*unit)
	logo.position=Vector2(middle-177*unit,52*unit);logo.size=Vector2(354,81)*unit
	panel.scale=Vector2.ONE*unit;panel.size=Vector2(360,0);panel.position=Vector2(middle-180*unit,161*unit)
	status.scale=Vector2.ONE*unit;status.position=Vector2(middle-235*unit,470*unit);status.size=Vector2(470,65)
	help.scale=Vector2.ONE*unit;help.position=Vector2(middle-310*unit,464*unit);help.size=Vector2(620,130)
	footer.scale=Vector2.ONE*unit;footer.size=Vector2(360,42);footer.position=Vector2(middle-180*unit,size.y-94*unit)
	edition.scale=Vector2.ONE*unit;edition.position=Vector2(middle-edition.get_minimum_size().x*unit*.5,size.y-33*unit)
	rule.position=Vector2(16,size.y-110*unit);rule.size=Vector2(size.x-32,1)
	queue_redraw()

func _draw() -> void:
	var bottom := size.y-8
	var cyan := Color("26516a")
	draw_line(Vector2(12,12),Vector2(size.x-12,12),cyan,1)
	draw_line(Vector2(12,bottom),Vector2(size.x-12,bottom),cyan,1)
	for x in range(14,int(size.x)-14,5):
		draw_line(Vector2(x,bottom-4),Vector2(x,bottom),cyan,1)
