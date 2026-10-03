extends PanelContainer
## The one settings screen. The title, the pause menu and the station's System
## page all open this panel, so every option lives in one place with one name.
## It reads and writes the settings file itself and reports each change, so the
## host only applies what changed: the dive to its running systems, the title
## to its backdrop and music.
signal changed(section: String, key: String)
signal closed

const StationTheme = preload("res://native/presentation/station_theme.gd")
const StationIcon = preload("res://native/presentation/station_icon.gd")
const Display = preload("res://native/presentation/display_settings.gd")
const WorldSettings = preload("res://native/presentation/world_settings.gd")
const Spacing = preload("res://native/simulation/world_spacing.gd")
const OceanOptions = preload("res://native/presentation/ocean_options.gd")
const Headlights = preload("res://native/presentation/headlight_options.gd")
const Quality = preload("res://native/presentation/graphics_quality.gd")
const Pad = preload("res://native/input/flight_controls.gd")
const EngineLanguage = preload("res://native/presentation/engine_language.gd")

## Tabs in order of how often they are reached for: sound first, input last
## but one, and the world rules that only matter between dives at the end.
const TABS := [["audio","Audio","audio"],["graphics","Graphics","graphics"],["display","Display","fullscreen"],
	["controls","Controls","controls"],["gameplay","Gameplay","world"]]
const CONTROL_PAGES := {"steering":"Steering","gamepad":"Gamepad","touch":"Touch controls","bindings":"Key bindings","reference":"Control reference"}
const DEFAULT_KEYS := {"left":KEY_A,"right":KEY_D,"up":KEY_UP,"throttle_up":KEY_W,"throttle_down":KEY_S,"down":KEY_DOWN,"fire":KEY_SPACE,"auto_fire":KEY_Q,"camera":KEY_C,"boost":KEY_SHIFT,"bank":KEY_TAB,"dock":KEY_E,"map":KEY_M,"autopilot":KEY_R,"time":KEY_T,"lights":KEY_L}

## Reopening settings returns to the tab last used, in the title or a dive.
static var last_section := "audio"

var settings_path := ""
var golden := false
var touch := false
## What only the host can do, each optional: "fullscreen", "layout_editor",
## "touch_active", "calibrate", "motion_enable", "buzz", "world_note",
## "auto_title" (the track Auto resolves to), "text" (imported game text) and
## "content_language" (the imported game's language code).
var host := {}
var section := "audio"
var subpage := ""
var binding := ""
var binding_notice := ""
var focus_key := ""
var scroll: ScrollContainer
var column: VBoxContainer
var tab_bar: GridContainer
var subtitle: Label
var legend: HFlowContainer
var back_button: Button
var fonts := {}
var rebuild_revision := 0

func configure(path: String, capabilities: Dictionary, gold := false, touch_sized := false) -> void:
	settings_path=path;host=capabilities;golden=gold;touch=touch_sized

func _ready() -> void:
	name="Settings"
	focus_mode=Control.FOCUS_NONE
	# It sits over a paused dive and must still follow the window.
	process_mode=Node.PROCESS_MODE_ALWAYS
	get_parent().resized.connect(fit)

func _process(_delta: float) -> void:
	# The canvas is rescaled after a window change, and a size set in the same
	# frame as that change does not always hold; keep to the wanted frame.
	if visible: fit()

func open(first := "") -> void:
	section=first if first in tab_ids() else last_section
	subpage=""
	if first in CONTROL_PAGES: section="controls";subpage=first
	binding="";binding_notice="";focus_key=""
	build_chrome()
	show();fit()
	rebuild()

func tab_ids() -> Array:
	return TABS.map(func(tab): return tab[0])

func tab_name(id: String) -> String:
	match id:
		"audio": return tr("Audio")
		"graphics": return tr("Graphics")
		"display": return tr("Display")
		"controls": return tr("Controls")
		"gameplay": return tr("Gameplay")
	return id.capitalize()

func control_page_name(id: String) -> String:
	match id:
		"steering": return tr("Steering")
		"gamepad": return tr("Gamepad")
		"touch": return tr("Touch controls")
		"bindings": return tr("Key bindings")
		"reference": return tr("Control reference")
	return id.capitalize()

func title_music_names() -> Array:
	return [tr("Auto"),tr("Intro"),tr("Station")]

func strafe_names() -> Array:
	return [tr("Auto · strafe unless on touch"),tr("Always strafe"),tr("Always turn")]

func touch_mode_names() -> Array:
	return [tr("Auto"),tr("On"),tr("Off")]

func colours() -> Dictionary:
	return StationTheme.palette(golden)

func spaced(spacing: int) -> FontVariation:
	if not fonts.has(spacing): fonts[spacing]=StationTheme.spaced(get_theme_font("font","Label"),spacing)
	return fonts[spacing]

func fit() -> void:
	"""One size for every tab, so switching tabs never moves the frame."""
	var room: Vector2=get_parent().size
	var wanted:=Vector2(minf(780,room.x-(24.0 if room.x<560 else 48.0)),minf(room.y-(24.0 if room.y<560 else 48.0),760))
	if tab_bar!=null:
		var columns := tab_columns(wanted.x-get_theme_stylebox("panel").get_minimum_size().x)
		if tab_bar.columns!=columns: tab_bar.columns=columns
	if size!=wanted: size=wanted
	if position!=((room-size)*.5).round(): position=((room-size)*.5).round()

func tab_columns(inner: float) -> int:
	"""All five tabs in a row when they fit, else rows of three or two: an
	upright phone is too narrow for one row."""
	var tabs := tab_bar.get_children()
	for columns in [5,3,2]:
		# A grid column is as wide as its widest tab.
		var needed: float=(columns-1)*8.0
		for place in columns:
			var widest := 0.0
			for at in range(place,tabs.size(),columns): widest=maxf(widest,tabs[at].get_combined_minimum_size().x)
			needed+=widest
		if needed<=inner: return columns
	return 1

# ---------------------------------------------------------------- the file

func load_config() -> ConfigFile:
	var config := ConfigFile.new();config.load(settings_path);return config

func put(section_name: String, key: String, value: Variant, rebuild_after := true) -> void:
	var config := load_config();config.set_value(section_name,key,value)
	Quality.mark_chosen(config,section_name,key)
	DirAccess.make_dir_recursive_absolute(settings_path.get_base_dir());config.save(settings_path)
	changed.emit(section_name,key)
	if rebuild_after: rebuild(true)

func flag(section_name: String, key: String, fallback: bool) -> bool:
	var value: Variant=load_config().get_value(section_name,key,fallback)
	return bool(value) if value is bool or value is int else fallback

func number(section_name: String, key: String, fallback: float, low: float, high: float) -> float:
	"""The file is text a player can edit: a wrong type, NAN or INF is the default."""
	var value: Variant=load_config().get_value(section_name,key,fallback)
	if value is not float and value is not int: return fallback
	if not is_finite(float(value)): return fallback
	return clampf(float(value),low,high)

func index(section_name: String, key: String, fallback: int, highest: int) -> int:
	var value: Variant=load_config().get_value(section_name,key,fallback)
	if value is not int and value is not float: return fallback
	if value is float and not is_finite(value): return fallback
	return clampi(int(value),0,highest)

func modern() -> bool:
	var config := load_config()
	return bool(config.get_value("graphics","modern",config.get_value("graphics","materials",true)))

func forward_plus() -> bool:
	return RenderingServer.get_current_rendering_method()=="forward_plus"

func keycode(action: String) -> int:
	var value: Variant=load_config().get_value("keys",action,DEFAULT_KEYS[action])
	if value is not int and value is not float: return DEFAULT_KEYS[action]
	var code := int(value)
	return code if code>0 and not OS.get_keycode_string(code).is_empty() else DEFAULT_KEYS[action]

func can(capability: String) -> bool:
	return host.has(capability) and host[capability] is Callable and host[capability].is_valid()

func text(id: int, fallback: String) -> String:
	var found: String=host.text.call(id) if can("text") else ""
	return fallback if found.is_empty() else found

# ---------------------------------------------------------------- the frame

func build_chrome() -> void:
	for child in get_children(): remove_child(child);child.queue_free()
	add_theme_stylebox_override("panel",StationTheme.panel(golden))
	var shell := VBoxContainer.new();shell.add_theme_constant_override("separation",12);add_child(shell)
	var header := HBoxContainer.new();header.add_theme_constant_override("separation",12);shell.add_child(header)
	var titles := VBoxContainer.new();titles.size_flags_horizontal=Control.SIZE_EXPAND_FILL;titles.add_theme_constant_override("separation",4);header.add_child(titles)
	var heading := plain(tr("Settings").to_upper(),26,titles);heading.name="Heading"
	heading.add_theme_font_override("font",spaced(7));heading.add_theme_color_override("font_color",colours().text);heading.autowrap_mode=TextServer.AUTOWRAP_OFF
	var rule := ColorRect.new();rule.color=colours().accent;rule.custom_minimum_size=Vector2(56,2);rule.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN;titles.add_child(rule)
	subtitle=caption("",11,titles,3);subtitle.name="Subtitle"
	back_button=styled_button(tr("Back").to_upper(),back,header);back_button.name="Back"
	icon_on(back_button,"back",18)
	back_button.size_flags_horizontal=Control.SIZE_SHRINK_END;back_button.size_flags_vertical=Control.SIZE_SHRINK_BEGIN
	back_button.custom_minimum_size=Vector2(128,48 if touch else 40);back_button.add_theme_font_override("font",spaced(4))
	back_button.set_meta("option","back")
	tab_bar=GridContainer.new();tab_bar.name="Tabs";tab_bar.add_theme_constant_override("h_separation",8);tab_bar.add_theme_constant_override("v_separation",8);shell.add_child(tab_bar)
	for tab in TABS:
		var node := styled_button(tab_name(tab[0]),func(): switch_to(tab[0],true),tab_bar)
		node.name="Tab_"+tab[0];node.set_meta("option","tab_"+tab[0]);node.set_meta("tab",tab[0])
		icon_on(node,tab[2],22)
		node.add_theme_font_override("font",spaced(2));node.add_theme_font_size_override("font_size",17 if touch else 16)
	scroll=ScrollContainer.new();scroll.name="Scroll";scroll.follow_focus=true;scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;shell.add_child(scroll)
	# Room between the rows and the scroll bar.
	var gutter := MarginContainer.new();gutter.name="Gutter";gutter.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	gutter.add_theme_constant_override("margin_right",18 if touch else 14);scroll.add_child(gutter)
	column=VBoxContainer.new();column.name="Rows";column.size_flags_horizontal=Control.SIZE_EXPAND_FILL;column.add_theme_constant_override("separation",8);gutter.add_child(column)
	legend=HFlowContainer.new();legend.name="KeyLegend";legend.add_theme_constant_override("h_separation",8);legend.add_theme_constant_override("v_separation",6);shell.add_child(legend)
	legend.visible=not touch
	for entry in [["ESC / B",tr("Back")],["LB / RB",tr("Section")],["D-PAD / ARROWS",tr("Navigate")],["ENTER / A",tr("Select")]]:
		var boxed := StationTheme.frame(Color(0,0,0,0),colours().edge,0);boxed.set_content_margin_all(3);boxed.content_margin_left=7;boxed.content_margin_right=7
		var key := caption(entry[0],10,legend,1);key.add_theme_stylebox_override("normal",boxed)
		var meaning := caption(entry[1],10,legend,2);meaning.add_theme_color_override("font_color",colours().faint)
		meaning.custom_minimum_size.x=meaning.get_minimum_size().x+14

func refresh_tabs() -> void:
	for node in tab_bar.get_children():
		var current: bool=node.get_meta("tab")==section
		# The open tab keeps its lit frame whether or not it holds focus.
		var skin := StationTheme.button_state(golden,"focus" if current else "normal");skin.content_margin_left=44
		node.add_theme_stylebox_override("normal",skin)
		node.add_theme_color_override("font_color",colours().text if current else colours().dim)
		node.custom_minimum_size.y=56 if touch else 44
	var place: String=tab_name(section)
	if not subpage.is_empty(): place+="  ›  "+control_page_name(subpage)
	subtitle.text=place.to_upper()

func switch_to(id: String, keep_tab_focus := false) -> void:
	if binding!="": binding=""
	section=id;last_section=id;subpage="";binding_notice=""
	focus_key="tab_"+id if keep_tab_focus else ""
	scroll.scroll_vertical=0
	rebuild()

func cycle_tab(step: int) -> void:
	var ids := tab_ids()
	switch_to(ids[(ids.find(section)+step+ids.size())%ids.size()])

func back() -> void:
	if binding!="":
		binding="";rebuild();return
	if not subpage.is_empty():
		focus_key=subpage;subpage="";binding_notice="";rebuild();return
	hide();closed.emit()

func _input(event: InputEvent) -> void:
	if not visible or not is_inside_tree(): return
	if scroll!=null:
		# A pointer may hit the visible part of a clipped row. Focusing it on
		# press must not move the target before the release activates it.
		if (event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed) or (event is InputEventScreenTouch and event.pressed):
			if scroll.get_global_rect().has_point(event.position):scroll.follow_focus=false
		elif event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion:
			scroll.follow_focus=true
	if binding!="" and event is InputEventKey and event.pressed and not event.echo:
		get_viewport().set_input_as_handled()
		if event.physical_keycode==KEY_ESCAPE or event.keycode==KEY_ESCAPE:
			binding="";rebuild();return
		for action in DEFAULT_KEYS:
			if action!=binding and keycode(action)==event.physical_keycode:
				binding_notice=tr("%s is already assigned to %s.")%[OS.get_keycode_string(event.physical_keycode),action_name(action)];rebuild();return
		var action := binding;binding="";binding_notice="";focus_key="key_"+action
		put("keys",action,event.physical_keycode)
		return
	if event is InputEventJoypadButton and event.pressed:
		if event.button_index==JOY_BUTTON_LEFT_SHOULDER: cycle_tab(-1);get_viewport().set_input_as_handled();return
		if event.button_index==JOY_BUTTON_RIGHT_SHOULDER: cycle_tab(1);get_viewport().set_input_as_handled();return
		if event.button_index==JOY_BUTTON_B: back();get_viewport().set_input_as_handled();return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_ESCAPE:
		back();get_viewport().set_input_as_handled()

# ---------------------------------------------------------------- the rows

func plain(value: String, font_size: int, parent: Node) -> Label:
	var node := Label.new();node.text=value;node.add_theme_font_size_override("font_size",font_size)
	node.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;node.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	parent.add_child(node);return node

func caption(value: String, font_size: int, parent: Node, spacing: int) -> Label:
	var node := plain(value.to_upper(),font_size,parent);node.add_theme_font_override("font",spaced(spacing))
	node.add_theme_color_override("font_color",colours().dim);node.autowrap_mode=TextServer.AUTOWRAP_OFF
	node.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
	return node

func note(value: String) -> Label:
	var node := plain(value,14,column);node.add_theme_color_override("font_color",colours().dim)
	return node

func group(value: String) -> void:
	"""A small heading over a run of related rows."""
	var spacer := Control.new();spacer.custom_minimum_size.y=4;column.add_child(spacer)
	caption(value,11,column,3).add_theme_color_override("font_color",colours().accent)

func styled_button(value: String, action: Callable, parent: Node) -> Button:
	var node := Button.new();node.text=value
	for state in ["normal","hover","pressed","focus","disabled"]: node.add_theme_stylebox_override(state,StationTheme.button_state(golden,state))
	var palette := colours()
	node.add_theme_color_override("font_color",palette.text);node.add_theme_color_override("font_focus_color",Color.WHITE);node.add_theme_color_override("font_hover_color",Color.WHITE)
	node.add_theme_color_override("font_disabled_color",palette.faint)
	node.alignment=HORIZONTAL_ALIGNMENT_LEFT;node.custom_minimum_size.y=64 if touch else 44
	node.size_flags_horizontal=Control.SIZE_EXPAND_FILL;node.add_theme_font_size_override("font_size",20 if touch else 16)
	node.pressed.connect(action);parent.add_child(node)
	return node

func icon_on(node: Button, icon: String, extent: float) -> void:
	var mark := StationIcon.new(icon,node.get_theme_color("font_color"),extent);node.add_child(mark)
	mark.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT);mark.offset_left=12;mark.offset_right=12+extent;mark.offset_top=-extent*.5;mark.offset_bottom=extent*.5
	for state in ["normal","hover","pressed","focus","disabled"]:
		var style := node.get_theme_stylebox(state) as StyleBoxFlat
		if style!=null: style.content_margin_left=22+extent

func row(title: String, value: String, key: String, action: Callable, parent: Node=null) -> Button:
	"""A setting: its name on the left, its current value on the right. The
	key is where focus comes back to after the row rebuilds the page."""
	var node := styled_button(title,func(): focus_key=key;action.call(),parent if parent!=null else column)
	node.set_meta("option",key);node.name="Row_"+key
	node.accessibility_name=title+(" · "+value if not value.is_empty() else "")
	if not value.is_empty():
		var shown := Label.new();shown.name="Value";shown.text=value;shown.mouse_filter=Control.MOUSE_FILTER_IGNORE
		shown.add_theme_font_size_override("font_size",18 if touch else 15);shown.add_theme_color_override("font_color",colours().value)
		shown.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT;shown.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
		node.add_child(shown);shown.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);shown.offset_right=-16;shown.offset_left=16
		# The name wraps short of the value rather than running under it.
		var room:=shown.get_combined_minimum_size().x
		for state in ["normal","hover","pressed","focus","disabled"]:
			var style := node.get_theme_stylebox(state) as StyleBoxFlat
			if style!=null: style.content_margin_right=room+28
		node.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	return node

func toggle(title: String, section_name: String, key: String, fallback: bool, on_text := "", off_text := "", parent: Node=null) -> Button:
	var value := flag(section_name,key,fallback)
	if on_text.is_empty(): on_text=tr("On")
	if off_text.is_empty(): off_text=tr("Off")
	return row(title,on_text if value else off_text,key,func(): put(section_name,key,not value),parent)

func chooser(title: String, names: Array, current: int, key: String, choose: Callable, parent: Node=null, shown_text := "") -> Button:
	"""A dropdown: the row shows the current choice and opens the list of
	them below it. A value outside the list (Custom) shows shown_text."""
	var chosen: bool=current>=0 and current<names.size()
	var node := row(title,str(names[current]) if chosen else shown_text,key,func():pass,parent)
	# The list itself is an OptionButton behind the row: it places the popup,
	# follows the window's scale and takes keys, pad and touch.
	var list := OptionButton.new();list.name="List"
	list.focus_mode=Control.FOCUS_NONE;list.mouse_filter=Control.MOUSE_FILTER_IGNORE;list.self_modulate=Color(1,1,1,0)
	for i in names.size():list.add_item(str(names[i]),i)
	list.selected=current if chosen else -1
	StationTheme.style_popup(list.get_popup(),golden,touch)
	node.add_child(list);node.move_child(list,0);list.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	list.item_selected.connect(func(index):
		focus_key=key
		if index!=current: choose.call(index)
		else: restore_focus())
	# A press outside an open list closes it; the same press on this row must
	# not open it again straight away.
	list.get_popup().popup_hide.connect(func(): list.set_meta("closed_at",Time.get_ticks_msec()))
	node.pressed.connect(func():
		if Time.get_ticks_msec()-int(list.get_meta("closed_at",-10000))<300:return
		list.show_popup())
	var arrow := StationIcon.new("down",colours().accent,14 if not touch else 18);node.add_child(arrow)
	arrow.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	var extent: float=arrow.custom_minimum_size.x
	arrow.offset_left=-16-extent;arrow.offset_right=-16;arrow.offset_top=-extent*.5;arrow.offset_bottom=extent*.5
	var value := node.get_node_or_null("Value") as Label
	if value!=null:value.offset_right=-24-extent
	for state in ["normal","hover","pressed","focus","disabled"]:
		var style := node.get_theme_stylebox(state) as StyleBoxFlat
		if style!=null: style.content_margin_right+=extent+8
	return node

func slider(title: String, section_name: String, key: String, fallback: float, low: float, high: float, step: float, percent := false) -> HSlider:
	var line := HBoxContainer.new();line.add_theme_constant_override("separation",16);column.add_child(line)
	line.custom_minimum_size.y=56 if touch else 44
	var words := plain(title,20 if touch else 16,line);words.size_flags_horizontal=Control.SIZE_FILL;words.custom_minimum_size.x=200 if size.x>=700 else 130
	words.add_theme_color_override("font_color",colours().text);words.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;words.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	var node := HSlider.new();node.name="Slider_"+key;node.set_meta("option",key)
	node.min_value=low;node.max_value=high;node.step=step;node.value=number(section_name,key,fallback,low,high)
	node.size_flags_horizontal=Control.SIZE_EXPAND_FILL;node.size_flags_vertical=Control.SIZE_SHRINK_CENTER;node.custom_minimum_size.y=32
	node.focus_mode=Control.FOCUS_ALL;line.add_child(node)
	# The wheel scrolls the page; it never moves a slider under the pointer.
	node.scrollable=false
	var amount := plain("",18 if touch else 15,line);amount.size_flags_horizontal=Control.SIZE_SHRINK_END;amount.custom_minimum_size.x=56
	amount.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT;amount.vertical_alignment=VERTICAL_ALIGNMENT_CENTER;amount.add_theme_color_override("font_color",colours().value)
	var show_amount := func(value: float): amount.text="%d%%"%roundi(value*100) if percent else "%.2f"%value
	show_amount.call(node.value)
	node.value_changed.connect(func(value):
		show_amount.call(value)
		put(section_name,key,value,false))
	return node

func sub_row(title: String, key: String) -> Button:
	"""A row that opens a page of its own. It shows an arrow, never a value: a
	value there reads as a choice made on the row itself."""
	var node := row(title,"",key,func(): subpage=key;focus_key="";scroll.scroll_vertical=0;rebuild())
	var arrow := StationIcon.new("next",colours().accent,20);node.add_child(arrow)
	arrow.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT);arrow.offset_left=-36;arrow.offset_right=-16;arrow.offset_top=-10;arrow.offset_bottom=10
	return node

# ---------------------------------------------------------------- the pages

func rebuild(preserve_scroll := false) -> void:
	if column==null: return
	rebuild_revision+=1
	var previous_scroll := scroll.scroll_vertical
	# Refocusing a replacement row before containers finish laying it out
	# can scroll to a temporary position, even when the row was visible.
	if preserve_scroll:scroll.follow_focus=false
	for child in column.get_children(): column.remove_child(child);child.queue_free()
	refresh_tabs()
	match section:
		"audio": audio_page()
		"graphics": graphics_page()
		"display": display_page()
		"controls":
			match subpage:
				"steering": steering_page()
				"gamepad": gamepad_page()
				"touch": touch_page()
				"bindings": bindings_page()
				"reference": reference_page()
				_: controls_page()
		"gameplay": gameplay_page()
	restore_focus.call_deferred()
	if preserve_scroll:restore_scroll.call_deferred(previous_scroll,rebuild_revision)
	else:scroll.follow_focus=true

func restore_scroll(position_y: int, revision: int) -> void:
	if not is_inside_tree():return
	await get_tree().process_frame
	if not is_inside_tree() or revision!=rebuild_revision:return
	scroll.scroll_vertical=position_y
	# Navigation still brings newly focused rows into view normally.
	scroll.follow_focus=true

func restore_focus() -> void:
	if not is_inside_tree() or not visible or not is_instance_valid(column): return
	var wanted := focus_key;focus_key=""
	if not wanted.is_empty():
		var found := find_option(self,wanted)
		if found!=null: found.grab_focus();return
	var owner: Control=get_viewport().gui_get_focus_owner()
	if owner!=null and is_ancestor_of(owner) and owner.is_visible_in_tree(): return
	for node in column.find_children("*","",true,false):
		if node is Control and node.focus_mode==Control.FOCUS_ALL and node.is_visible_in_tree() and not (node is BaseButton and node.disabled):
			node.grab_focus();return

func find_option(node: Node, key: String) -> Control:
	if node is Control and node.get_meta("option","")==key and node.is_visible_in_tree() and not (node is BaseButton and node.disabled): return node
	for child in node.get_children():
		var found := find_option(child,key)
		if found!=null: return found
	return null

func audio_page() -> void:
	group(tr("Volume"))
	slider(tr("Music"),"audio","music",0.65,0.0,1.0,0.05,true)
	slider(tr("Sound effects"),"audio","effects",0.75,0.0,1.0,0.05,true)
	toggle(tr("Game audio"),"graphics","audio",true)
	group(tr("Music"))
	var choice := index("audio","title_music",0,2)
	var auto_track: String=host.auto_title.call() if can("auto_title") else ""
	var names := title_music_names()
	if not auto_track.is_empty(): names[0]=tr("Auto · %s")%{"intro":names[1],"station":names[2]}.get(auto_track,auto_track.capitalize())
	chooser(tr("Menu and opening music"),names,choice,"title_music",func(next): put("audio","title_music",next))
	note(tr("Auto: Intro for version 1.0.3 JARs, Station for 1.0.8. Stations always play Station."))

func graphics_page() -> void:
	var enhanced := modern()
	var preset := Quality.current(load_config())
	var presets: Array=Quality.preset_names()
	var best := Quality.recommended(load_config())
	if best>=0: presets[best]=tr("%s (Recommended)")%presets[best]
	chooser(tr("Preset"),presets,preset,"preset",choose_preset,null,tr("Custom"))
	note(tr("Classic matches the original's lighting. The others add lights, fog and shading, and set shadows, antialiasing, volumetric light and surface shading. Changing one of those makes the preset Custom."))
	group(tr("Performance"))
	performance_options()
	group(tr("Enhanced lighting"))
	graphics_options(["headlight_mode","blue_headlights","cabin_lights","cool_lighting","filtered_sunlight"])
	var strength := slider(tr("Headlight brightness"),"graphics","headlight_strength",Quality.HEADLIGHT_HIGH,Quality.HEADLIGHT_LOW,Quality.HEADLIGHT_HIGH,0.05,true)
	strength.editable=enhanced and Headlights.casts_light(Headlights.read(load_config()))
	strength.tooltip_text=tr("How strongly the headlights light the water and nearby surfaces.")
	group(tr("Ocean atmosphere"))
	graphics_options(["volumetric","deep_darkness","regional_water","marine_snow","bioluminescence","explosion_aftermath"])
	group(tr("Surfaces and textures"))
	graphics_options(["detail"])
	var textures := graphics_grid()
	for kind in ["station","ship"]:
		var node := toggle(tr("Station texture smoothing") if kind=="station" else tr("Ship texture smoothing"),"graphics",kind+"_smoothing",false,tr("On"),tr("Off"),textures)
		node.tooltip_text=tr("On: smoothly filtered textures. Off: original pixelated textures.")

func choose_preset(preset: int) -> void:
	var config := load_config();Quality.write(config,preset)
	DirAccess.make_dir_recursive_absolute(settings_path.get_base_dir());config.save(settings_path)
	changed.emit("graphics","preset")
	focus_key="preset";rebuild(true)

func performance_options() -> void:
	var enhanced := modern()
	var quality := Quality.read(load_config())
	var grid := graphics_grid()
	var shadows := chooser(tr("Shadow quality"),Quality.shadow_names(),quality.shadows if enhanced else -1,"shadows",func(next): put("graphics","shadows",next),grid,tr("Classic"))
	shadows.disabled=not enhanced
	shadows.tooltip_text=tr("Shadows from station lamps, headlights and overhead light. Low and Medium use faster station-lamp shadows that can let a little light through close to a lamp.")
	var scales: Array=Quality.SCALES
	var resolution := chooser(tr("3D resolution"),scales.map(func(value): return "%d%%"%value),scales.find(quality.scale),"render_scale",func(next): put("view","render_scale",scales[next]),grid)
	resolution.tooltip_text=tr("Draws the 3D view at this share of the display resolution and scales it up. The interface stays sharp.")
	var upscalers: Array=Quality.upscalers()
	var upscaling: Button
	if upscalers.size()>1: upscaling=chooser(tr("Upscaling"),upscalers.map(Quality.upscaler_name),upscalers.find(Quality.upscaler(quality)),"upscaler",func(next): put("view","upscaler",upscalers[next]),grid)
	else: upscaling=row(tr("Upscaling"),tr("Needs Vulkan"),"upscaler",func():pass,grid);upscaling.disabled=true
	upscaling.tooltip_text=tr("How the 3D view is scaled up below full resolution. FSR 2.2 and MetalFX temporal use earlier frames, replace temporal antialiasing and also smooth edges at full resolution.")
	var msaa := chooser(tr("Multisample antialiasing"),Quality.msaa_names(),quality.msaa,"msaa",func(next): put("view","msaa",next),grid)
	msaa.tooltip_text=tr("Smooths the edges of models.")
	var taa: Button
	if forward_plus(): taa=toggle(tr("Temporal antialiasing"),"view","temporal_aa",false,tr("On"),tr("Off"),grid)
	else: taa=row(tr("Temporal antialiasing"),tr("Needs Vulkan"),"temporal_aa",func():pass,grid)
	taa.disabled=not enhanced or not forward_plus() or Quality.upscaler(quality) in Quality.TEMPORAL_UPSCALERS
	taa.tooltip_text=tr("Smooths edges further; slightly blurs motion.")

func graphics_grid() -> GridContainer:
	var grid := GridContainer.new();grid.columns=2 if size.x>=700 else 1
	grid.add_theme_constant_override("h_separation",10);grid.add_theme_constant_override("v_separation",8);column.add_child(grid)
	return grid

func graphics_options(keys: Array) -> void:
	var enhanced := modern()
	var grid := graphics_grid()
	var lighting := {
		"volumetric":[tr("Volumetric light"),tr("Light and shadow in the surrounding water.")],
		"detail":[tr("Surface shading detail"),tr("Fine shading and contact shadows on hulls and structures.")]
	}
	for key in keys:
		if key=="headlight_mode":
			var mode := Headlights.read(load_config())
			var lamps := chooser(tr("Headlights"),Headlights.names(),mode if enhanced else -1,key,func(next):
				var config := load_config();Headlights.write(config,next)
				DirAccess.make_dir_recursive_absolute(settings_path.get_base_dir());config.save(settings_path)
				changed.emit("graphics","headlight_mode");rebuild(true),grid,tr("Classic"))
			lamps.disabled=not enhanced
			lamps.tooltip_text=tr("Off: no headlight glow or beams. Light only: lit lenses and surface illumination. Light + beams: adds visible light in the water. Classic: the original textured beams and colours.")
			continue
		var option: Array=OceanOptions.visuals().get(key,lighting.get(key,[]))
		var needs_forward: bool=key in ["volumetric","detail"] and not forward_plus()
		var node: Button
		if needs_forward:node=row(option[0],tr("Needs Vulkan"),key,func():pass,grid)
		else:node=toggle(option[0],"graphics",key,OceanOptions.default_on(key),tr("Blue") if key=="blue_headlights" else tr("On"),tr("White") if key=="blue_headlights" else tr("Off"),grid)
		node.tooltip_text=option[1];node.disabled=not enhanced or needs_forward
		if not enhanced and not needs_forward:
			node.get_node("Value").text=tr("Classic") if key=="blue_headlights" else tr("Off")
			node.accessibility_name=tr("%s: unavailable in Classic lighting")%option[0]
		elif key=="blue_headlights" and not Headlights.casts_light(Headlights.read(load_config())):
			node.disabled=true
			if Headlights.read(load_config())==Headlights.Mode.CLASSIC:node.get_node("Value").text=tr("Original")
			node.tooltip_text=tr("Choose Light only or Light + beams to change the colour. Classic keeps the original beam colours.")

func change_language(code: String) -> void:
	if not is_inside_tree():return
	put("interface","language",code,false)
	refresh_language.call_deferred()

func refresh_language() -> void:
	# The title's host may already have scheduled a scene reload. Only the
	# surviving in-game panel needs to rebuild its frame here.
	if not is_inside_tree() or is_queued_for_deletion():return
	fonts.clear();build_chrome();rebuild()

func display_page() -> void:
	var codes := EngineLanguage.codes()
	var chosen: String=str(load_config().get_value("interface","language",EngineLanguage.AUTO))
	var game_language: String=host.content_language.call() if can("content_language") else ""
	var automatic := EngineLanguage.resolve(EngineLanguage.AUTO,game_language)
	var names: Array=[tr("Auto · %s")%EngineLanguage.native_name(automatic)]+codes.map(func(code): return EngineLanguage.native_name(code))
	chooser(tr("Language"),names,codes.find(chosen)+1,"language",func(next):
		# The native popup must finish dispatching its selection before a
		# language change replaces its controls or reloads the title scene.
		change_language.call_deferred(EngineLanguage.AUTO if next==0 else codes[next-1]))
	note(tr("Menus and messages the engine adds. Auto matches the imported game's language."))
	if not OS.has_feature("mobile") or OS.has_feature("web"):
		var mode := DisplayServer.window_get_mode()
		var full: bool=mode in [DisplayServer.WINDOW_MODE_FULLSCREEN,DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]
		row(tr("Fullscreen"),tr("On") if full else tr("Off"),"fullscreen",func():
			if can("fullscreen"): host.fullscreen.call()
			else: DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
			# The window reports its new mode a frame later.
			await get_tree().process_frame
			focus_key="fullscreen";rebuild())
		if not OS.has_feature("web"): note(tr("F11 toggles fullscreen."))
	if Display.orientation_setting_available():
		chooser(tr("Screen orientation"),Display.orientation_names(),index("view","orientation",0,2),"orientation",func(next): put("view","orientation",next))
		note(tr("Auto rotates with the device."))
	var ratio: String=Display.valid(str(load_config().get_value("view","aspect_ratio","auto")))
	var ratios: Array=Display.names()
	chooser(tr("Aspect ratio"),ratios.map(func(item): return tr("Auto") if item=="auto" else str(item)),maxi(0,ratios.find(ratio)),"aspect",func(next): put("view","aspect_ratio",ratios[next]))
	var quality := Quality.read(load_config())
	var screen: int=DisplayServer.screen_get_size(get_window().current_screen).y
	var heights: Array=Quality.heights_for(maxi(screen,get_window().size.y))
	if not quality.height in heights: heights.append(quality.height)
	var shown := chooser(tr("Resolution"),heights.map(func(height): return Quality.height_name(height)),heights.find(quality.height),"resolution",func(next): put("view","resolution_height",heights[next]))
	shown.tooltip_text=tr("The resolution the game is drawn at. The interface stays at the screen's own resolution.")
	note(tr("3D resolution and antialiasing are in Graphics."))
	toggle(tr("Show FPS"),"view","show_fps",false).tooltip_text=tr("Frames per second at the top of the screen.")

func controls_page() -> void:
	sub_row(tr("Steering"),"steering")
	sub_row(tr("Gamepad"),"gamepad")
	sub_row(tr("Touch controls"),"touch")
	sub_row(tr("Key bindings"),"bindings")
	sub_row(tr("Control reference"),"reference")

func steering_page() -> void:
	chooser(tr("Helm response"),[tr("Direct"),tr("Smooth")],1 if flag("input","smooth_steering",false) else 0,"smooth_steering",func(next): put("input","smooth_steering",next==1))
	note(tr("Smooth: eased turns, mouse limited by the ship's steering rate. Direct: instant, as in the original."))
	chooser(tr("Left/right keys and stick"),strafe_names(),index("input","strafe",0,2),"strafe",func(next): put("input","strafe",next))
	slider(tr("Mouse sensitivity"),"keys","mouse_sensitivity",0.8,0.2,2.0,0.1)
	toggle(tr("Invert vertical mouse and touch"),"keys","invert_mouse",false)
	group(tr("Tilt steering"))
	var tilt := flag("input","motion",false)
	var tilt_row := row(tr("Steer by tilting"),tr("On") if tilt else tr("Off"),"motion",func():
		put("input","motion",not tilt,false)
		# A browser grants the sensor only inside the press that asked for it.
		if not tilt and can("motion_enable"): host.motion_enable.call()
		rebuild())
	if OS.has_feature("web") and not can("motion_enable") and not tilt:
		tilt_row.disabled=true;tilt_row.tooltip_text=tr("Turn on during gameplay; the browser asks for sensor access then.")
	note(tr("Needs a motion sensor."))
	if tilt:
		slider(tr("Tilt sensitivity"),"input","motion_sensitivity",0.5,0.0,1.0,0.05)
		toggle(tr("Invert tilt pitch"),"input","motion_invert",false)
		if can("calibrate"):
			row(tr("Calibrate tilt"),"","motion_centre",func(): host.calibrate.call())

func gamepad_page() -> void:
	note(tr("Gamepad connected.") if not Input.get_connected_joypads().is_empty() else tr("No gamepad connected."))
	toggle(tr("Invert gamepad pitch"),"input","invert_gamepad",false)
	var vibration := flag("input","vibration",true)
	row(text(10,tr("Vibration")),text(14,tr("On")) if vibration else text(15,tr("Off")),"vibration",func():
		put("input","vibration",not vibration,false)
		if not vibration and can("buzz"): host.buzz.call()
		rebuild())
	slider(tr("Gamepad deadzone"),"input","deadzone",.18,.05,.45,.01)
	note(tr("Raise if the ship drifts with the sticks at rest."))
	group(tr("Sticks"))
	var roles: Array=Pad.read_roles(load_config())
	for axis in 4:
		var key: String=Pad.AXIS_KEYS[axis]
		chooser(Pad.axis_names()[axis],Pad.role_names(),roles[axis],key,func(next): put("input",key,next))
	note(tr("Turn or strafe follows Steering › Left/right keys and stick. Throttle steps the speed as D-pad up and down do. Camera swings the view round the ship."))
	note(tr("Hold D-pad left to turn the camera with the right stick; tap it to change the camera."))
	var reset := row(tr("Reset sticks"),"","pad_reset",func():
		var config := load_config()
		for axis in 4: config.set_value("input",Pad.AXIS_KEYS[axis],Pad.DEFAULT_ROLES[axis])
		DirAccess.make_dir_recursive_absolute(settings_path.get_base_dir());config.save(settings_path)
		changed.emit("input","pad_left_x");rebuild(true))
	reset.disabled=roles==Pad.DEFAULT_ROLES

func touch_page() -> void:
	chooser(tr("Touch controls"),touch_mode_names(),index("input","touch",0,2),"touch_mode",func(next): put("input","touch",next))
	var active: bool=can("touch_active") and host.touch_active.call()
	var placement := row(tr("Adjust control placement"),"","touch_layout",func():
		if can("layout_editor"): host.layout_editor.call())
	placement.disabled=not (can("layout_editor") and active)
	placement.tooltip_text=tr("Move and resize the on-screen controls.") if not placement.disabled else (tr("Turn touch controls on first.") if can("layout_editor") else tr("Available during gameplay."))
	toggle(tr("Mirror fire control"),"input","touch_mirror_fire",false).tooltip_text=tr("Put the throttle arc on the right of the fire button, for a button placed on the left.")
	toggle(tr("Touch look area"),"input","touch_drag_anywhere",false,tr("Whole screen"),tr("Outside analog area"))
	toggle(tr("Steering stick"),"input","touch_fixed_stick",false,tr("Fixed in place"),tr("Moves to thumb"))
	toggle(tr("Invert vertical steering"),"keys","invert_mouse",false)
	slider(tr("Touch look sensitivity"),"input","touch_look",0.7,0.2,2.0,0.1)
	note(tr("Outside analog area: the left stick steers, dragging elsewhere turns the camera. Whole screen: dragging anywhere steers."))

func action_name(action: String) -> String:
	return {"autopilot":tr("Autopilot (tap / hold)"),"time":tr("Time acceleration"),"throttle_up":tr("Throttle up"),"throttle_down":tr("Throttle down"),"auto_fire":tr("Auto fire"),"up":tr("Pitch up"),"down":tr("Pitch down"),"left":tr("Left"),"right":tr("Right"),
		"fire":tr("Fire"),"camera":tr("Camera"),"boost":tr("Boost"),"bank":tr("Bank"),"dock":tr("Dock"),"map":tr("Map"),"lights":tr("Lights")}.get(action,action.capitalize())

func bindings_page() -> void:
	if binding!="": note(tr("Press a key for %s. Esc cancels.")%action_name(binding)).add_theme_color_override("font_color",colours().value)
	elif not binding_notice.is_empty(): note(binding_notice).add_theme_color_override("font_color",colours().bad)
	else: note(tr("Select an action, then press its new key. Esc cancels."))
	var grid := GridContainer.new();grid.columns=2 if size.x>=700 else 1;grid.add_theme_constant_override("h_separation",10);grid.add_theme_constant_override("v_separation",8);column.add_child(grid)
	# Travel first: tap-or-hold autopilot is the binding players look for.
	var order: Array=["autopilot","time"]
	for action in DEFAULT_KEYS:
		if action not in order: order.append(action)
	for action in order:
		var waiting: bool=binding==action
		row(action_name(action),"…" if waiting else OS.get_keycode_string(keycode(action)),"key_"+action,func():
			binding=action;binding_notice="";focus_key="key_"+action;rebuild(),grid)

func reference_page() -> void:
	for line in [tr("Mouse turns · Left-click guns · Right-click harpoon · W/S throttle"),
		tr("Mouse pitch and yaw allow full loops; your camera follows the submarine’s orientation."),
		tr("Gamepad: right stick turns · left stick strafes or turns (sticks can be reassigned in Gamepad) · D-pad up/down throttle · A selected weapon · RT guns / LT hook · L3 boost"),
		tr("X bank · Y dock · LB route · RB time · View map · D-pad left camera, hold to look with the right stick · D-pad right lights · Start/B menu")]:
		plain(line,16,column).add_theme_color_override("font_color",colours().text)

func gameplay_page() -> void:
	toggle(tr("Gameplay tips & control hints"),"interface","hints",true)
	note(tr("Loading tips, M.A.I. guidance and the control reminder."))
	group(tr("On-screen messages"))
	toggle(tr("Flight messages"),"interface","flight_messages",true)
	note(tr("Autopilot, time speed, camera and arrival messages. Warnings still show."))
	toggle(tr("Dock and gate prompts"),"interface","dock_prompts",true)
	toggle(tr("Autopilot status line"),"interface","autopilot_status",true)
	toggle(tr("Friendly contact labels"),"interface","friend_labels",true)
	group(tr("Interface"))
	toggle(tr("Depth limit markers"),"graphics","depth_limits",false)
	note(tr("Shows when the ship nears its depth limits."))
	group(tr("Damage feedback"))
	toggle(tr("Red flash on damage"),"interface","hit_flash",true)
	toggle(tr("Screen shake on damage"),"interface","hit_shake",true)
	toggle(tr("Red pulse at low hull"),"interface","low_hull_pulse",true)
	toggle(tr("Hull percentage on hull damage"),"interface","hull_readout",true)
	group(tr("World"))
	var spacing := Spacing.new();spacing.read_config(load_config())
	var controls := WorldSettings.new();controls.configure(spacing);column.add_child(controls)
	for label in controls.find_children("*","Label",true,false): label.add_theme_color_override("font_color",colours().dim)
	var current := note("")
	var describe := func():
		current.text=host.world_note.call() if can("world_note") else tr("Applies on next departure.")
	describe.call()
	controls.changed.connect(func():
		var config := load_config();spacing.write_config(config)
		DirAccess.make_dir_recursive_absolute(settings_path.get_base_dir());config.save(settings_path)
		changed.emit("world","spacing");describe.call())
	var split := flag("world","split_gates",true)
	var words: PackedStringArray=WorldSettings.gate_text(split).split(" · ",true,1)
	row(words[0],words[1],"split_gates",func(): put("world","split_gates",not split))
	note(tr("Applies from the next area."))
