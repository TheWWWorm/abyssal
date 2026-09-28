extends CanvasLayer
## Frames per second, top centre, over everything (Settings → Display → Show FPS).
var label := Label.new()
var elapsed := 0.0

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
	label.offset_left=-60;label.offset_right=60;label.offset_top=6;label.offset_bottom=28
	add_child(label)
	set_enabled(false)

func set_enabled(on: bool) -> void:
	visible=on;set_process(on);elapsed=1.0

static func wanted(config: ConfigFile) -> bool:
	return bool(config.get_value("view","show_fps",false))

func _process(delta: float) -> void:
	# Twice a second: a number changing every frame cannot be read.
	elapsed+=delta
	if elapsed<0.5:return
	elapsed=0.0
	label.text="%d FPS"%roundi(Engine.get_frames_per_second())
