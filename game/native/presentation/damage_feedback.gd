extends Control
## Where a hit came from, as arcs around the centre of the view, a red edge
## when the hull takes damage, a slow red pulse while it is nearly gone, and
## the phone game's blinking hull readout. Presentation only: bearings and
## hull values are read from the simulation and nothing here is written back,
## so the same dive plays out identically without it.
const EngineLanguage = preload("res://native/presentation/engine_language.gd")
const FADE := 1.4
const REACH := 0.34
## bd: after the hull percentage drops, its readout blinks for three seconds,
## shown for the second 300 ms of every 600 ms (bf.c).
const READOUT_SECONDS := 3.0
const BLINK_PERIOD := 0.6
## A hull at or under this fraction pulses the edges.
const LOW_HULL := 25
var marks: Array = []
var flash := 0.0
var flash_enabled := true
var pulse_enabled := true
var readout_enabled := true
var hull_percent := 100
var readout_time := 0.0
var readout_clock := 0.0
var readout_top := 220.0
var low := false
var pulse := 0.0
var font := SystemFont.new()

func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	font.font_names=PackedStringArray(["Nimbus Sans Narrow","Liberation Sans Narrow"])
	font.fallbacks=[ThemeDB.fallback_font]
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(queue_redraw)

func clear() -> void:
	marks.clear()
	flash=0.0
	readout_time=0.0
	queue_redraw()

func hit(strength: float) -> void:
	"""Any loss of shield, armour or hull: the moment the phone buzzed (bb)."""
	flash=maxf(flash,clampf(strength,0.0,1.0))
	queue_redraw()

func update_hull(percent: int, alive: bool) -> void:
	if percent<hull_percent and percent<100 and alive and readout_enabled:
		readout_time=READOUT_SECONDS;readout_clock=0.0
	hull_percent=percent
	var was_low := low
	low=alive and percent<=LOW_HULL and pulse_enabled
	if not alive:readout_time=0.0
	if low!=was_low:queue_redraw()

func record(camera: Camera3D, source: Vector3, target: Vector3) -> void:
	"""Bearing is measured in the camera's own frame, so an arc keeps pointing at
	the attacker while the view turns, and a hit from behind reads as behind."""
	if camera==null: return
	var relative: Vector3 = camera.global_transform.affine_inverse()*source-camera.global_transform.affine_inverse()*target
	var planar := Vector2(relative.x,-relative.z)
	# A shot landing exactly on the camera axis has no bearing to point at.
	var angle: float = atan2(planar.x,planar.y) if planar.length()>0.001 else 0.0
	for mark in marks:
		if absf(angle_difference(mark.angle,angle))<0.3:
			mark.age=0.0
			mark.weight=minf(1.0,mark.weight+0.35)
			queue_redraw()
			return
	if marks.size()>=6: marks.pop_front()
	marks.append({"angle":angle,"age":0.0,"weight":0.55})
	queue_redraw()

func advance(delta: float) -> void:
	# Whatever was showing is redrawn once more as it ends, so nothing lingers.
	var busy := not marks.is_empty() or flash>0.0 or low or readout_time>0.0
	if low: pulse=fmod(pulse+delta,1.2)
	else: pulse=0.0
	if readout_time>0.0:
		readout_time=maxf(0.0,readout_time-delta);readout_clock=fmod(readout_clock+delta,BLINK_PERIOD)
	if not busy: return
	flash=maxf(0.0,flash-delta*2.4)
	for mark in marks: mark.age+=delta
	marks=marks.filter(func(mark): return mark.age<FADE)
	queue_redraw()

func edge(strength: float) -> void:
	"""A red band fading inwards from every side of the view."""
	if strength<=0.005: return
	var depth := minf(size.x,size.y)*.16
	var outer := Color(.85,.08,.05,strength)
	var inner := Color(.85,.08,.05,0.0)
	var o := [Vector2.ZERO,Vector2(size.x,0),size,Vector2(0,size.y)]
	var i := [Vector2(depth,depth),Vector2(size.x-depth,depth),size-Vector2(depth,depth),Vector2(depth,size.y-depth)]
	for side in 4:
		var next := (side+1)%4
		draw_polygon(PackedVector2Array([o[side],o[next],i[next],i[side]]),PackedColorArray([outer,outer,inner,inner]))

func _draw() -> void:
	edge((flash*.42 if flash_enabled else 0.0)+(0.10+0.14*(0.5-0.5*cos(pulse/1.2*TAU)) if low else 0.0))
	if readout_enabled and readout_time>0.0 and readout_clock>=BLINK_PERIOD*.5:
		var label := "%s %d%%"%[EngineLanguage.translate("Hull").to_upper(),hull_percent]
		var pixels := 26
		var width := font.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,pixels).x
		var at := Vector2((size.x-width)*.5,readout_top+pixels)
		draw_string_outline(font,at,label,HORIZONTAL_ALIGNMENT_LEFT,-1,pixels,6,Color(0,0,0,.65))
		draw_string(font,at,label,HORIZONTAL_ALIGNMENT_LEFT,-1,pixels,Color("ff8a6e") if hull_percent<=LOW_HULL else Color("f0c27a"))
	if marks.is_empty(): return
	var middle := size*0.5
	var radius := minf(size.x,size.y)*REACH
	for mark in marks:
		var strength: float = clampf(1.0-mark.age/FADE,0.0,1.0)*mark.weight
		if strength<=0.01: continue
		var width := 5.0+10.0*strength
		# Screen y grows downward; the bearing is drawn in the same handedness
		# as the arc sweep so an arc sits over the direction it names.
		var centre: float = mark.angle-PI*0.5
		draw_arc(middle,radius,centre-0.34,centre+0.34,20,
			Color(1.0,0.36,0.3,clampf(strength,0.0,0.85)),width,true)
		draw_arc(middle,radius+width*0.55,centre-0.2,centre+0.2,12,
			Color(1.0,0.75,0.6,clampf(strength*0.6,0.0,0.6)),2.0,true)
