extends Control
## Shared opt-in, progress and recovery flow for the title and settings screen.
signal chosen(action: String)
const Reconstruction = preload("res://native/textures/reconstructed_textures.gd")
const StationTheme = preload("res://native/presentation/station_theme.gd")
static var current: WeakRef
var work
var panel: PanelContainer
var words: Label
var status: Label
var bar: ProgressBar
var actions: HFlowContainer
var busy := false
var focus_before: Control
var blocked: Array=[]
var info := {}
var settings_path := ""

static func is_open() -> bool:
	return current!=null and current.get_ref()!=null and current.get_ref().is_inside_tree()

func _ready() -> void:
	name="ReconstructionDialog";current=weakref(self)
	process_mode=Node.PROCESS_MODE_ALWAYS;z_index=100
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	set_meta("focus_scope",true)
	focus_before=get_viewport().gui_get_focus_owner()
	for child in get_parent().get_children():
		if child is Control and child!=self:
			blocked.append([child,child.focus_behavior_recursive]);child.focus_behavior_recursive=Control.FOCUS_BEHAVIOR_DISABLED
	var scrim := ColorRect.new();scrim.color=Color(0,.025,.045,.84);add_child(scrim);scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel=PanelContainer.new();panel.name="Panel";panel.add_theme_stylebox_override("panel",StationTheme.panel(false));add_child(panel)
	var column := VBoxContainer.new();column.add_theme_constant_override("separation",16);panel.add_child(column)
	var title := Label.new();title.text=tr("Reconstructed textures");title.add_theme_font_size_override("font_size",24);title.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;column.add_child(title)
	var scroll := ScrollContainer.new();scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;column.add_child(scroll)
	words=Label.new();words.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;words.add_theme_font_size_override("font_size",17);words.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(words)
	status=Label.new();status.name="Status";status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;status.add_theme_font_size_override("font_size",15);column.add_child(status)
	bar=ProgressBar.new();bar.name="Progress";bar.custom_minimum_size.y=24;bar.max_value=100;column.add_child(bar);bar.hide()
	bar.add_theme_stylebox_override("background",StationTheme.frame(Color("06141d"),Color("37616e"),1))
	var fill := StyleBoxFlat.new();fill.bg_color=Color("247b94");bar.add_theme_stylebox_override("fill",fill)
	actions=HFlowContainer.new();actions.add_theme_constant_override("h_separation",12);actions.add_theme_constant_override("v_separation",8);column.add_child(actions)
	resized.connect(fit);fit()

func fit() -> void:
	if panel==null:return
	panel.size=Vector2(minf(620,size.x-32),minf(430 if size.x<560 else 350,size.y-32))
	panel.position=((size-panel.size)*.5).round()

func _process(_delta: float) -> void:fit()

func add_action(caption: String, action: String) -> Button:
	var button := Button.new();button.text=caption;button.name=action.capitalize();button.custom_minimum_size=Vector2(140,52);button.add_theme_font_size_override("font_size",17)
	for state in ["normal","hover","pressed","focus","disabled"]:button.add_theme_stylebox_override(state,StationTheme.button_state(false,state))
	button.pressed.connect(func():choose(action));actions.add_child(button);return button

func focus_action(button: Button) -> void:
	if is_instance_valid(button) and button.is_inside_tree() and button.is_visible_in_tree():button.grab_focus()

func clear_actions() -> void:
	for child in actions.get_children():actions.remove_child(child);child.queue_free()

func choose(action: String) -> void:
	if busy:
		if action=="cancel":
			work.cancel();status.text=tr("Cancelling…")
			for button in actions.get_children():button.disabled=true
	else:chosen.emit(action)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled();choose("cancel" if busy else "later")

func _notification(what: int) -> void:
	if what==NOTIFICATION_WM_GO_BACK_REQUEST:choose("cancel" if busy else "later")

func _exit_tree() -> void:
	if work!=null:work.shutdown()
	for saved in blocked:
		if is_instance_valid(saved[0]):saved[0].focus_behavior_recursive=saved[1]
	if is_instance_valid(focus_before) and focus_before.is_inside_tree() and focus_before.is_visible_in_tree():focus_before.grab_focus()

func update_progress(value: float, stage: String) -> void:
	bar.value=value*100
	match stage:
		"deep":status.text=tr("Rebuilding hulls and stations…")
		"fx":status.text=tr("Rebuilding creatures and effects…")
		"normals":status.text=tr("Building surface relief…")
		"save":status.text=tr("Saving reconstructed textures…")
		"done":status.text=tr("Applying textures…")
		_:status.text=tr("Preparing reconstruction…")

func run(content_root: String, path: String, offer := true) -> bool:
	settings_path=path;info=Reconstruction.inspect(content_root)
	words.text=tr("Create sharper textures for ships, stations, creatures and effects from your imported game, with shallow surface relief. This can take a minute or more on slower devices. The result is saved on this device for later launches.")
	status.text=tr("Your originals are kept. Custom texture packs take priority. You can switch this off in Settings → Graphics.")
	if offer:
		add_action(tr("Reconstruct and enable"),"enable")
		focus_action.call_deferred(add_action(tr("Not now"),"later"))
		var answer: String=await chosen
		if answer!="enable":
			if Reconstruction.save_choice(path,info,false)!=OK:await settings_error()
			return false
	while true:
		clear_actions();bar.show();bar.value=0;busy=true
		work=Reconstruction.new();work.progress.connect(update_progress)
		focus_action.call_deferred(add_action(tr("Cancel"),"cancel"))
		var success: bool=await work.generate(info,get_tree())
		busy=false
		if success:
			if Reconstruction.save_choice(path,info,true)!=OK:await settings_error();return false
			bar.value=100;return true
		if work.cancelled:
			if Reconstruction.save_choice(path,info,false)!=OK:await settings_error()
			return false
		clear_actions();bar.hide()
		words.text=tr("The original textures are still available. You can retry reconstruction or keep playing with them.")
		match work.failure:
			"source":status.text=tr("This import does not contain the supported 128×128 texture atlases.")
			"recipe":status.text=tr("The reconstruction recipe is missing or damaged. Reinstall the update to restore it.")
			_:status.text=tr("Could not save reconstructed textures. Check the free space available to the game.")
		add_action(tr("Retry"),"retry")
		focus_action.call_deferred(add_action(tr("Keep originals"),"later"))
		var answer: String=await chosen
		if answer!="retry":
			if Reconstruction.save_choice(path,info,false)!=OK:await settings_error()
			return false
		info=Reconstruction.inspect(content_root)
	return false

func settings_error() -> void:
	clear_actions();bar.hide();status.text=tr("Could not save settings. Check your user folder.")
	focus_action.call_deferred(add_action(tr("Close"),"close"));await chosen
