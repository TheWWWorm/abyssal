extends Control
## Where a hit came from, as arcs around the centre of the view. Presentation
## only: bearings are read from impacts the simulation already reported and
## nothing here is written back, so the same dive plays out identically without it.
const FADE := 1.4
const REACH := 0.34
var marks: Array = []
var flash := 0.0

func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(queue_redraw)

func clear() -> void:
	marks.clear()
	flash=0.0
	queue_redraw()

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
	flash=1.0
	queue_redraw()

func advance(delta: float) -> void:
	if marks.is_empty() and flash<=0.0: return
	flash=maxf(0.0,flash-delta*2.4)
	for mark in marks: mark.age+=delta
	marks=marks.filter(func(mark): return mark.age<FADE)
	queue_redraw()

func _draw() -> void:
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
