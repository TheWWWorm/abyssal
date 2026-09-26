extends Control
## Classic menu structure with scalable desktop controls and imported title art.
signal continued
signal started
signal settings_requested
signal tools_requested
signal quit_requested
signal help_requested
signal mods_requested
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
const StationTheme = preload("res://native/presentation/station_theme.gd")
const StationIcon = preload("res://native/presentation/station_icon.gd")
var palette := StationTheme.palette(false)

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	headline=caption("ABYSSAL",42,palette.text);headline.add_theme_font_override("font",StationTheme.spaced(headline.get_theme_font("font"),10))
	subtitle=caption("COMPATIBILITY ENGINE",13,palette.dim);subtitle.add_theme_font_override("font",StationTheme.spaced(subtitle.get_theme_font("font"),5))
	add_child(logo);logo.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;logo.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;logo.mouse_filter=Control.MOUSE_FILTER_IGNORE;logo.hide()
	add_child(panel)
	# The menu stands to the left of the station behind it, as the phone game's
	# dock menu does, and lets the water show through.
	# The same glass as the station menus, lighter so the water shows through.
	var skin := StationTheme.panel(false);skin.bg_color.a=.72
	skin.content_margin_left=16;skin.content_margin_right=16;skin.content_margin_top=14;skin.content_margin_bottom=16
	panel.add_theme_stylebox_override("panel",skin)
	panel.add_child(choices);choices.add_theme_constant_override("separation",8)
	menu_title=Label.new();menu_title.text="MAIN MENU";menu_title.add_theme_font_size_override("font_size",15);menu_title.add_theme_color_override("font_color",palette.dim)
	menu_title.add_theme_font_override("font",StationTheme.spaced(menu_title.get_theme_font("font"),5));choices.add_child(menu_title)
	var accent := ColorRect.new();accent.color=palette.accent;accent.custom_minimum_size=Vector2(48,2);accent.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN;choices.add_child(accent)
	new_button=entry("Start new game",func():started.emit(),true,"depart")
	continue_button=entry("Load game",func():continued.emit(),true,"save")
	entry("Options",func():settings_requested.emit(),true,"system")
	entry("Mods",func():mods_requested.emit(),true,"workshop")
	entry("Help",func():help_requested.emit(),true,"help")
	if not OS.has_feature("web"):entry("Exit",func():quit_requested.emit(),true,"exit")
	status=caption("Choose your DEEP JAR to begin.",15,palette.dim);status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;status.horizontal_alignment=HORIZONTAL_ALIGNMENT_LEFT
	footer=entry("Choose game JAR…",func():tools_requested.emit(),false,"cargo")
	var version := str(ProjectSettings.get_setting("application/config/version",""))
	edition=caption("ABYSSAL" if version.is_empty() else "ABYSSAL  /  "+version,12,palette.faint)
	edition.add_theme_font_override("font",StationTheme.spaced(edition.get_theme_font("font"),3))
	rule=ColorRect.new();rule.color=Color(palette.edge,.6);rule.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(rule)
	add_child(help);help.hide();help.text="Mouse · Steer    W / S · Throttle\nM · World map    R · Autopilot (hold: quest)    T · Time 1×/2×; autopilot to 16×\nE · Dock    Esc · Menu    F11 · Fullscreen\n\nTouch: flight pads + action buttons. Gamepad: left stick + triggers.\nD-pad speed / menus · A select / fire · Start pause."
	help.add_theme_font_size_override("font_size",15);help.modulate=palette.text;help.horizontal_alignment=HORIZONTAL_ALIGNMENT_LEFT;help.mouse_filter=Control.MOUSE_FILTER_IGNORE;help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	resized.connect(layout);layout()

func load_content(directory: String) -> void:
	var file := directory.path_join("data/interface/logo.png")
	if not FileAccess.file_exists(file):return
	var pixels := Image.load_from_file(file)
	if pixels==null:return
	logo.texture=ImageTexture.create_from_image(pixels);logo.show();headline.hide();subtitle.hide();layout()

func caption(value: String, font_size: int, color: Color) -> Label:
	var node := Label.new();node.text=value;node.add_theme_font_size_override("font_size",font_size);node.modulate=color;node.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(node);return node

func entry(value: String, action: Callable, in_list: bool=true, icon: String="") -> Button:
	var node := Button.new();node.text=value;node.alignment=HORIZONTAL_ALIGNMENT_LEFT if in_list else HORIZONTAL_ALIGNMENT_CENTER
	node.custom_minimum_size=Vector2(310,46);node.add_theme_font_size_override("font_size",19)
	for state in ["normal","hover","focus","pressed","disabled"]:
		var skin := StationTheme.button_state(false,state)
		if not icon.is_empty(): skin.content_margin_left=54
		node.add_theme_stylebox_override(state,skin)
	node.add_theme_color_override("font_color",palette.text);node.add_theme_color_override("font_focus_color",Color.WHITE);node.add_theme_color_override("font_hover_color",Color.WHITE)
	node.add_theme_color_override("font_disabled_color",palette.faint)
	if not icon.is_empty():
		var mark := StationIcon.new(icon,palette.accent,24);node.add_child(mark)
		mark.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT);mark.offset_left=16;mark.offset_right=40;mark.offset_top=-12;mark.offset_bottom=12
	(choices if in_list else self).add_child(node);node.pressed.connect(action);return node

func toggle_help() -> void:
	help_open=not help_open;help.visible=help_open;status.visible=not help_open;layout()

func layout() -> void:
	if status==null:return
	var upright: bool=size.y>size.x
	var unit := clampf(size.x/560.0 if upright else minf(size.x/1000.0,size.y/720.0),0.8,2.5)
	# Everything keeps to a column down the left; the station has the rest.
	# Upright, the column takes the width and the station shows below it.
	var left := (24 if upright else 40)*unit
	var column := size.x/unit-48 if upright else minf(360,size.x/unit-80)
	headline.scale=Vector2.ONE*unit;headline.position=Vector2(left,38*unit)
	subtitle.scale=Vector2.ONE*unit;subtitle.position=Vector2(left,91*unit)
	logo.position=Vector2(left,44*unit);logo.size=Vector2(column,column*81.0/354.0)*unit
	# A column-wide logo is taller than the landscape one; the menu starts under it.
	var top: float=maxf(150*unit,logo.position.y+logo.size.y+18*unit) if logo.visible else 150*unit
	panel.scale=Vector2.ONE*unit;panel.size=Vector2(column,0);panel.position=Vector2(left,top)
	var below: float=top+panel.get_combined_minimum_size().y*unit+14*unit
	status.scale=Vector2.ONE*unit;status.position=Vector2(left,below);status.size=Vector2(column,65)
	help.scale=Vector2.ONE*unit;help.position=Vector2(left,below);help.size=Vector2(minf(620,size.x/unit-80),150)
	footer.scale=Vector2.ONE*unit;footer.size=Vector2(column,42);footer.position=Vector2(left,size.y-94*unit)
	edition.scale=Vector2.ONE*unit;edition.position=Vector2(left,size.y-33*unit)
	rule.position=Vector2(16,size.y-110*unit);rule.size=Vector2(size.x-32,1)
	queue_redraw()

func _draw() -> void:
	# Corner brackets round the screen, as the station interface frames it.
	var edge := Color(palette.edge,.8)
	var inset := 14.0;var arm := 28.0
	for corner in [Vector2(0,0),Vector2(1,0),Vector2(0,1),Vector2(1,1)]:
		var at := Vector2(inset+(size.x-2*inset)*corner.x,inset+(size.y-2*inset)*corner.y)
		var across := Vector2(1 if corner.x==0 else -1,0)*arm;var down := Vector2(0,1 if corner.y==0 else -1)*arm
		draw_polyline(PackedVector2Array([at+across,at,at+down]),edge,1.5,true)
