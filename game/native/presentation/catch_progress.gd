extends Range
## A read-only picture of the current cast, struggle and tow.
const Icon=preload("res://native/presentation/station_icon.gd")
const Weapon=preload("res://native/simulation/weapon.gd")
const Form=preload("res://native/presentation/weapon_form.gd")
const COLORS=Form.HARPOON_COLORS
const ROPE=preload("res://native/presentation/catch_rope.gdshader")
var stage := "flight"
var target_kind := "fish"
var equipment := 15
var phase := 0.0
var tint := COLORS[0]
var ship := Icon.new("hangar",Color("8bd6ee"),40)
var cargo := Icon.new("cargo",Color("c7e7ed"),26)
var timer := Label.new()
var rope := ColorRect.new()
var rope_material := ShaderMaterial.new()

func _init() -> void:
	step=.01;mouse_filter=Control.MOUSE_FILTER_IGNORE
func _ready() -> void:
	add_child(rope);rope.mouse_filter=Control.MOUSE_FILTER_IGNORE;rope.show_behind_parent=true
	rope.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rope_material.shader=ROPE;rope.material=rope_material
	add_child(ship);add_child(cargo);cargo.hide()
	add_child(timer);timer.mouse_filter=Control.MOUSE_FILTER_IGNORE
	timer.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	timer.add_theme_font_size_override("font_size",13)
	timer.add_theme_color_override("font_color",Color("b8e3eb"))
	timer.add_theme_color_override("font_outline_color",Color("020d16"))
	timer.add_theme_constant_override("outline_size",3);timer.hide()
	value_changed.connect(func(_value):queue_redraw())
	resized.connect(queue_redraw)

func present(mode: String, progress: float, id: int, time: float, kind: String="fish", seconds: float=-1.0) -> void:
	stage=mode;target_kind=kind;equipment=clampi(id,15,17);tint=COLORS[equipment-15]
	phase=time;value=clampf(progress,0,100)
	timer.visible=seconds>=0 and not kind.is_empty()
	timer.text=tr("%.1f s")%maxf(0,seconds) if timer.visible else ""
	place_timer();queue_redraw()

static func flight(weapon, fraction: float) -> Dictionary:
	if weapon==null:return {}
	for i in weapon.remaining.size():
		if weapon.remaining[i]<=0:continue
		var start:=Weapon.vector(weapon.launch_positions[i])
		var point:=Weapon.vector(weapon.previous_positions[i]).lerp(Weapon.vector(weapon.positions[i]),fraction)
		var reach: float=weapon.speed*weapon.lifetime
		var travel:=Weapon.vector(weapon.velocities[i]).normalized()*reach
		var nearest:=1.0;var target=null
		# Use the same collision bounds as the shot. An empty cast has no
		# promised fish at the end, and a live hull is never shown as a catch.
		for actor in weapon.targets:
			if not actor.health.enabled:continue
			var hit:=Weapon.sphere_entry(start,travel,Weapon.vector(actor.pose.origin),maxf(1,weapon.fishing_radius))
			if hit>=0 and hit<nearest:nearest=hit;target=actor
		var kind: String="fish" if target!=null and target.is_creature else "cargo" if target!=null and target.capturable and target.state in [3,4] else ""
		return {"progress":100.0*clampf(start.distance_to(point)/maxf(1,reach*nearest),0,1),"kind":kind}
	return {}

func line_start() -> Vector2:return Vector2(43,24)
func target_position() -> Vector2:
	var start:=line_start();var far:=maxf(start.x+64,size.x-36)
	var x:=lerpf(far,start.x+22,value*.01) if stage=="reel" else far
	return Vector2(x,start.y+(sin(phase*9.0)*1.3 if stage=="struggle" else 0.0))
func hook_position() -> Vector2:
	var target:=target_position()-Vector2(16,0)
	return line_start().lerp(target,value*.01) if stage=="flight" else target
func place_timer() -> void:
	timer.size=Vector2(64,20)
	timer.position=Vector2(clampf(target_position().x+3.5-timer.size.x*.5,0,maxf(0,size.x-timer.size.x)),40)

func stroke(points: PackedVector2Array, color: Color, width: float=1.6) -> void:
	draw_polyline(points,Color(.005,.02,.03,.8),width+2,true)
	draw_polyline(points,color,width,true)

func _draw() -> void:
	ship.position=Vector2.ZERO;ship.size=Vector2(48,40)
	place_timer()
	var start:=line_start();var head:=hook_position();var target:=target_position()
	# A single soft silhouette joins the rope and teeth without dark seams
	# or overlapping glow at their corners. It follows simulation time.
	rope_material.set_shader_parameter("canvas_size",size)
	rope_material.set_shader_parameter("line_start",start)
	rope_material.set_shader_parameter("head",head)
	rope_material.set_shader_parameter("head_scale",Form.HARPOON_HEAD_SCALE)
	rope_material.set_shader_parameter("teeth",equipment-14)
	rope_material.set_shader_parameter("phase",phase)
	rope_material.set_shader_parameter("tint",tint)
	cargo.visible=target_kind=="cargo"
	if cargo.visible:cargo.size=Vector2(26,26);cargo.position=target-Vector2(10,13)
	if target_kind=="fish":
		var body:=PackedVector2Array()
		for i in 25:
			var a:=TAU*i/24.0
			body.append(target+Vector2(cos(a)*13,sin(a)*6))
		draw_colored_polygon(body,Color("061923"));stroke(body,Color("c7e7ed"))
		stroke(PackedVector2Array([target+Vector2(10,0),target+Vector2(20,-7),target+Vector2(20,7),target+Vector2(10,0)]),Color("c7e7ed"))
		draw_circle(target+Vector2(-6,-1),1.3,Color("c7e7ed"),true,-1,true)
