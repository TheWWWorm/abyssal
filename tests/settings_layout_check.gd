extends SceneTree
## Long translated values must not take the setting name's space. Exercise
## the live layout across languages, window changes and dropdown selection.
const Language=preload("res://native/presentation/engine_language.gd")
const Quality=preload("res://native/presentation/graphics_quality.gd")
const Settings=preload("res://native/presentation/settings_menu.gd")
var failures := 0

func expect(ok: bool, message: String) -> void:
	if not ok:failures+=1;push_error(message)
func _initialize() -> void:call_deferred("run")
func settle() -> void:
	for i in 10:await process_frame

func check_row(row: Button, context: String) -> void:
	var value:=row.get_node("Value") as Label
	var style:=row.get_theme_stylebox("normal")
	var text_room:=Rect2(style.get_offset(),row.size-style.get_minimum_size())
	var title_width:=row.get_theme_font("font").get_string_size(row.text,HORIZONTAL_ALIGNMENT_LEFT,-1,row.get_theme_font_size("font_size")).x
	expect(text_room.size.x>=minf(title_width,160),context+": name has room for words")
	expect(not text_room.intersects(value.get_rect()),context+": name and value have separate space")
	expect(Rect2(Vector2.ZERO,row.size).encloses(value.get_rect()),context+": value fits the row")
	expect(value.size.y>=value.get_minimum_size().y,context+": wrapped value has its full height")
	expect(value.get_line_count()<=3 and row.size.y<150,context+": no letter-by-letter columns")
	var arrow:=row.get_children().filter(func(child):return child is Control and child!=value and not child is OptionButton)
	if not arrow.is_empty():expect(not value.get_rect().intersects(arrow[-1].get_rect()),context+": value clears the dropdown arrow")

func run() -> void:
	root.size=Vector2i(1280,720)
	var ui:=Control.new();root.add_child(ui);ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var config:=ConfigFile.new();config.set_value("view","upscaler","fsr2");config.set_value("view","render_scale",33)
	config.save("user://settings-layout.cfg")
	var checked:=0
	var cases: Array=[]
	for code in Language.codes():
		for touch in [false,true]:cases.append([code,touch])
	for case in cases:
		var code: String=case[0]
		Language.apply(code)
		var panel:=Settings.new();panel.configure("user://settings-layout.cfg",{},false,case[1]);ui.add_child(panel);panel.open("display")
		# Include the longest mode even on a renderer without temporal upscaling.
		var grid:=panel.graphics_grid()
		var selected: Array=[]
		var row:=panel.chooser(tr("Upscaling mode"),[Quality.mode_name("fsr2",33),Quality.mode_name("fsr2",67)],0,"layout_mode",func(index):selected.append(index),grid)
		panel.toggle(tr("Temporal antialiasing"),"view","temporal_aa",false,tr("On"),tr("Off"),grid)
		for width in [1280,640,560,1280]:
			root.size=Vector2i(width,720);await settle()
			check_row(row,"%s touch=%s at %d"%[code,case[1],width]);checked+=1
			expect(grid.columns==(2 if panel.size.x>=700 else 1),"The grid reflows when the window changes")
			for option in panel.column.find_children("Row_*","Button",true,false):
				if option.has_node("Value"):check_row(option,"%s/%s at %d"%[code,option.name,width])
		# A value changed after construction must use the new width too.
		panel.show_value(row,tr("On"));await settle();check_row(row,code+" short value")
		panel.show_value(row,Quality.mode_name("fsr2",33));await settle();check_row(row,code+" restored long value")
		row.grab_focus();row.pressed.emit();await settle()
		var list:=row.get_node("List") as OptionButton
		expect(list.get_popup().visible,"The responsive row still opens its choices")
		list.get_popup().index_pressed.emit(1);await settle()
		expect(selected==[1],"The dropdown still applies the selected choice")
		list.get_popup().hide();panel.queue_free();await process_frame
	Language.apply("en");ui.queue_free();await process_frame
	print("SETTINGS_LAYOUT ",checked," language/width combinations, ",failures," failures")
	quit(1 if failures else 0)
