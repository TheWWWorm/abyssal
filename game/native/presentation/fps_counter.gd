extends CanvasLayer
## Frames per second, top centre, over everything (Settings → Display → Show FPS).
## With frame generation the display shows more frames than the game draws:
## the counter then leads with the frames displayed, as the vendors' own
## overlays do, and names the frames drawn beside them.
const EngineLanguage = preload("res://native/presentation/engine_language.gd")
const Nvidia = preload("res://native/presentation/nvidia.gd")
const Amd = preload("res://native/presentation/amd.gd")
var label := Label.new()
## The last reading: its time, the frames drawn and the vendor runtime's
## presented-frame count. Both counts are measured over the same interval.
var read_at := 0
var drawn := 0
var presented := -1

func _ready() -> void:
	layer=128
	process_mode=Node.PROCESS_MODE_ALWAYS
	label.name="FPS"
	label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size",16)
	label.add_theme_color_override("font_color",Color("d9f2fa"))
	label.add_theme_constant_override("outline_size",5)
	label.add_theme_color_override("font_outline_color",Color(0.01,0.04,0.07,0.9))
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	label.offset_left=-140;label.offset_right=140;label.offset_top=6;label.offset_bottom=28
	add_child(label)
	set_enabled(false)

func set_enabled(on: bool) -> void:
	visible=on;set_process(on);read_at=0;presented=-1

static func wanted(config: ConfigFile) -> bool:
	return bool(config.get_value("view","show_fps",false))

static func presented_frames() -> int:
	"""Frames the vendor runtime presented while generating, -1 without one."""
	if Nvidia.generating: return int(Nvidia.status().get("presented_frames",-1))
	if Amd.generating>0: return int(Amd.status().get("presented_frames",-1))
	return -1

static func text(rendered: float, displayed: float) -> String:
	if displayed<=rendered+0.5: return "%d FPS"%roundi(rendered)
	return EngineLanguage.translate("%d FPS · %d drawn")%[roundi(displayed),roundi(rendered)]

func _process(_delta: float) -> void:
	# Twice a second: a number changing every frame cannot be read.
	var now := Time.get_ticks_usec()
	if read_at>0 and now-read_at<500000: return
	var frames := Engine.get_frames_drawn()
	var shown := presented_frames()
	var rendered := Engine.get_frames_per_second()
	var displayed := 0.0
	var seconds := (now-read_at)/1000000.0
	# A reading after a long stall (loading, a hidden window) starts afresh.
	if read_at>0 and seconds<2.0:
		rendered=(frames-drawn)/seconds
		if shown>=0 and presented>=0 and shown>=presented: displayed=(shown-presented)/seconds
	label.text=text(rendered,displayed)
	read_at=now;drawn=frames;presented=shown
