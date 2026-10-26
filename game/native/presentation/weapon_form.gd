extends Node3D
## Procedural modern weapon forms. Original simulation and Classic assets stay separate.
const FIELD=preload("res://native/presentation/weapon_field.gdshader")
const SOLID=preload("res://native/presentation/weapon_solid.gdshader")
const HOOK_GLOW=preload("res://native/presentation/weapon_hook_glow.gdshader")
const HARPOON_COLORS=[Color("e6c519"),Color("e67b09"),Color("db231b")]
const HARPOON_HEAD_SCALE=1.005
var pieces: Array[MeshInstance3D]=[]
var moving: Array[Dictionary]=[]
var materials: Array[ShaderMaterial]=[]
var equipment: int
var family: String
var tier: int
var tint: Color

func material(part: int, color: Color) -> ShaderMaterial:
	var m:=ShaderMaterial.new();m.shader=HOOK_GLOW if part==8 else SOLID if part in [1,6,7] else FIELD
	if m.shader==SOLID:m.render_priority=1
	if part==8:m.render_priority=2
	if m.shader==SOLID:m.set_shader_parameter("harpoon",family=="hook")
	m.set_shader_parameter("pigment",color);m.set_shader_parameter("part",part)
	m.set_shader_parameter("family",0 if family=="rail" else 1 if family=="fusion" else 2 if family=="coil" else 3)
	materials.append(m);return m
func add_piece(mesh: Mesh, part: int=0, at: Vector3=Vector3.ZERO, size: Vector3=Vector3.ONE) -> MeshInstance3D:
	var n:=MeshInstance3D.new();n.mesh=mesh;n.material_override=material(part,tint)
	n.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;n.position=at;n.scale=size
	add_child(n);pieces.append(n);return n
static func spindle(profile: Array[Vector2], sides: int=24) -> ArrayMesh:
	var s:=SurfaceTool.new();s.begin(Mesh.PRIMITIVE_TRIANGLES)
	for r in range(profile.size()-1):
		for i in sides:
			var a:=TAU*i/sides;var b:=TAU*(i+1)/sides
			var p: Vector2=profile[r];var q: Vector2=profile[r+1]
			var v:=[Vector3(p.x*cos(a),p.x*sin(a),p.y),Vector3(p.x*cos(b),p.x*sin(b),p.y),Vector3(q.x*cos(a),q.x*sin(a),q.y),Vector3(q.x*cos(b),q.x*sin(b),q.y)]
			for k in [0,1,2,1,3,2]:s.add_vertex(v[k])
	s.generate_normals();return s.commit()
static func orb() -> SphereMesh:
	var s:=SphereMesh.new();s.radius=1;s.height=2;s.radial_segments=32;s.rings=16;return s
static func loop(radius: float, width: float, arc: float=TAU, lobes: int=0) -> ArrayMesh:
	var s:=SurfaceTool.new();s.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 64:
		var a:=arc*i/64;var b:=arc*(i+1)/64
		var ra:=radius*(1.0+.10*sin(a*lobes));var rb:=radius*(1.0+.10*sin(b*lobes))
		for j in 6:
			var c:=TAU*j/6;var d:=TAU*(j+1)/6
			var v:=[Vector3((ra+cos(c)*width)*cos(a),(ra+cos(c)*width)*sin(a),sin(c)*width),Vector3((ra+cos(d)*width)*cos(a),(ra+cos(d)*width)*sin(a),sin(d)*width),Vector3((rb+cos(c)*width)*cos(b),(rb+cos(c)*width)*sin(b),sin(c)*width),Vector3((rb+cos(d)*width)*cos(b),(rb+cos(d)*width)*sin(b),sin(d)*width)]
			for k in [0,1,2,1,3,2]:s.add_vertex(v[k])
	s.generate_normals();return s.commit()
func ring(radius: float, width: float, z: float, speed: float, tilt: Vector3=Vector3.ZERO, arc: float=TAU, lobes: int=0) -> void:
	var n:=add_piece(loop(radius,width,arc,lobes),2,Vector3(0,0,z));n.rotation=tilt
	moving.append({"node":n,"base":tilt,"speed":speed})

static func blade(outline: PackedVector2Array, thickness: float) -> ArrayMesh:
	# A solid silhouette in the X/Z plane, with the tip towards -Z.
	var surface:=SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var triangles:=Geometry2D.triangulate_polygon(outline)
	for face in [-1.0,1.0]:
		for i in range(0,triangles.size(),3):
			for j in ([0,1,2] if face>0 else [2,1,0]):
				var p: Vector2=outline[triangles[i+j]]
				surface.add_vertex(Vector3(p.x,thickness*face,p.y))
	for i in outline.size():
		var a:=outline[i];var b:=outline[(i+1)%outline.size()]
		var v:=[Vector3(a.x,-thickness,a.y),Vector3(b.x,-thickness,b.y),Vector3(a.x,thickness,a.y),Vector3(b.x,thickness,b.y)]
		for j in [0,1,2,1,3,2]:surface.add_vertex(v[j])
	surface.generate_normals();return surface.commit()

func harpoon_tip() -> void:
	# The imported icons depict a gold/amber/red shaft and one, two or three
	# swept-back teeth underneath. The shaft follows -Z; rotate the single
	# row of teeth down to -Y, preserving the one-sided icon silhouette.
	tint=HARPOON_COLORS[tier]
	add_piece(spindle([Vector2(0,-3.0),Vector2(.24,-2.3),Vector2(.24,2.4),Vector2(.32,2.6),Vector2(0,2.8)],8),6)
	harpoon_glow(Vector3(0,0,-3.0),Vector3(0,0,2.8),.24)
	for tooth in tier+1:
		var z: float=-2.6+tooth*1.45
		var profile:=PackedVector2Array([Vector2(.08,z),Vector2(1.10,z+1.85),Vector2(.39,z+1.30),Vector2(.20,z+1.55)])
		var n:=add_piece(blade(profile,.12),6)
		n.rotation.z=-PI*.5
		harpoon_glow(Vector3(0,-.08,z),Vector3(0,-1.10,z+1.85),.18)
	# Rear shaft bands echo the small perforated grid in the equipment icon.
	for i in 4:
		add_piece(spindle([Vector2(.245,1.15+i*.34),Vector2(.27,1.20+i*.34),Vector2(.245,1.29+i*.34)],8),7)
func harpoon_glow(start: Vector3, end: Vector3, radius: float) -> void:
	# Follow the shaft and individual teeth, so the halo retains their shape.
	var tube:=CylinderMesh.new();tube.top_radius=1; tube.bottom_radius=1; tube.height=1
	tube.radial_segments=16;tube.rings=1;tube.cap_top=false;tube.cap_bottom=false
	var delta:=end-start;var direction:=delta.normalized()
	var right:=direction.cross(Vector3.RIGHT).normalized()
	var halo:=add_piece(tube,8)
	halo.transform=Transform3D(Basis(right*radius,delta,right.cross(direction)*radius),(start+end)*.5)
func configure(id: int, color: Color) -> void:
	equipment=id;tint=color;tier=clampi(id%3,0,2)
	family="rail" if id in [0,1,2] else "coil" if id in [3,4,5] else "fusion" if id in [6,7,8] else "mass" if id in [9,10,11] else "torpedo" if id in [12,13,14] else "hook" if id in [15,16,17] else "eclipse"
	var power:=1.0+tier*.20
	if family=="rail":
		add_piece(spindle([Vector2(0,-2.2),Vector2(.16,-1.6),Vector2(.30,-.4),Vector2(.18,1.0),Vector2(0,3.0)]),0,Vector3.ZERO,Vector3(power,power,1.0+tier*.2))
		# A continuous swept field opens directly from the dart, with no second head.
		add_piece(spindle([Vector2(.12,-.2),Vector2(.50,1.1),Vector2(.24,4.0),Vector2(0,7.5)]),4,Vector3.ZERO,Vector3(power,power,power))
		for side in 3:
			var a:=TAU*side/3
			var fin:=BoxMesh.new();fin.size=Vector3(.72,.035,1.8)
			var n:=add_piece(fin,2,Vector3(0,0,.4),Vector3.ONE*power);n.rotation.z=a
	elif family=="fusion":
		add_piece(orb(),5,Vector3.ZERO,Vector3(1.0,1.0,.80)*power)
		add_piece(orb(),0,Vector3.ZERO,Vector3(.48,.48,.52)*power)
		ring(1.08*power,.09,0,2.5,Vector3(.60,.25,0),TAU*.86,3)
		ring(.87*power,.055,.1,-4,Vector3(-.65,.3,0),TAU*.78,2)
		add_piece(spindle([Vector2(.65,0),Vector2(.48,1.4),Vector2(.3,2.7),Vector2(0,4.5)]),4,Vector3.ZERO,Vector3(power,power,1))
	elif family=="mass":
		add_piece(spindle([Vector2(0,-2.0),Vector2(.33,-1.1),Vector2(.35,1.8),Vector2(.52,2.1),Vector2(.52,2.35),Vector2(0,2.45)],16),1,Vector3.ZERO,Vector3(power,power,power))
		for side in 4:
			var a:=TAU*side/4
			var strut:=add_piece(spindle([Vector2(.025,-1.3),Vector2(.065,.1),Vector2(.035,2.25)],8),2,Vector3(cos(a)*.40,sin(a)*.40,0)*power,Vector3(power,power,power))
			strut.rotation.z=a
		for side in 4:
			var a:=TAU*side/4
			var fin:=BoxMesh.new();fin.size=Vector3(.55,.075,.36)
			var n:=add_piece(fin,2,Vector3(cos(a)*.5,sin(a)*.5,1.8)*power,Vector3.ONE*power);n.rotation.z=a
		add_piece(spindle([Vector2(.42,2.1),Vector2(.7,3),Vector2(0,7)]),4,Vector3.ZERO,Vector3(power,power,1))
	elif family=="coil":
		add_piece(spindle([Vector2(0,-3.5),Vector2(.16,-1),Vector2(.21,1.0),Vector2(0,7.5)]),0,Vector3.ZERO,Vector3(power,power,power))
		for i in 3+tier:
			ring((.42+i*.16)*power,.045+i*.007,1.0+i*1.45,(3+i)*(-1 if i%2 else 1),Vector3(.08*i,.12*i,0),TAU*.86)
		add_piece(spindle([Vector2(.1,-2.5),Vector2(.7,2),Vector2(0,9)]),4,Vector3.ZERO,Vector3(power,power,power))
	elif family=="torpedo":
		tint=Color("69969d")
		add_piece(spindle([Vector2(0,-2.7),Vector2(.22,-2.5),Vector2(.42,-1.9),Vector2(.46,.9),Vector2(.34,1.8),Vector2(.3,2.25)],24),1,Vector3.ZERO,Vector3.ONE*power)
		for side in 4:
			var a:=TAU*side/4
			var fin:=BoxMesh.new();fin.size=Vector3(.6,.075,1.1)
			var n:=add_piece(fin,1,Vector3(cos(a)*.65,sin(a)*.65,1.4)*power,Vector3.ONE*power);n.rotation.z=a
		tint=[Color("66cbb6"),Color("51aaff"),Color("ffc65b")][tier]
		ring(.34*power,.075,2.2*power,0)
		ring(.46*power,.045,-1.55*power,0)
		add_piece(spindle([Vector2(.23,2.2),Vector2(.35,2.7),Vector2(.22,3.7),Vector2(0,5.2+tier*1.2)]),4,Vector3.ZERO,Vector3.ONE*power)
	elif family=="hook":
		harpoon_tip()
	else:
		tier=2
		add_piece(orb(),5,Vector3.ZERO,Vector3(1.4,1.4,2.6))
		add_piece(spindle([Vector2(0,-3),Vector2(.25,0),Vector2(0,4)]),0)
		for side in 3:ring(1.6,.10,0,3.0,Vector3(.6,TAU*side/3,0),TAU*.9,3)
		add_piece(spindle([Vector2(.7,1),Vector2(1.2,3),Vector2(0,9)]),4)
func advance(time: float, camera: Camera3D, rear: float=1000.0) -> void:
	for m in materials:
		m.set_shader_parameter("phase",time);m.set_shader_parameter("rear_limit",rear)
		m.set_shader_parameter("flight_origin",global_position);m.set_shader_parameter("flight_rear",global_basis.z.normalized())
	for motion in moving:
		motion.node.rotation=motion.base+Vector3(0,0,time*motion.speed)
	# Preserve a readable coloured silhouette in the player view, while still
	# obeying depth and never inflating into a white bloom sprite.
	var distance:=global_position.distance_to(camera.global_position)
	var pixel:=distance*2.0*tan(deg_to_rad(camera.fov*.5))/maxf(1,camera.get_viewport().get_visible_rect().size.y)
	var base: float={"rail":1.8,"fusion":1.4,"coil":1.5,"mass":1.7,"torpedo":1.0,"hook":1.7,"eclipse":1.5}.get(family,1.0)
	var factor:=clampf(maxf(base,pixel*(5.0 if family in ["mass","coil"] else 6.0)),base,8.0 if family=="hook" else 4.0)
	scale=Vector3(factor,factor,1.0)
	if family=="hook":scale*=HARPOON_HEAD_SCALE

func configure_impact(id: int, color: Color) -> void:
	equipment=id;tint=color;family="impact"
	var fusion:=id in [6,7,8,42];var torpedo:=id in [12,13,14]
	add_piece(orb(),5,Vector3.ZERO,Vector3(.7,.7,.35) if fusion else Vector3(.25,.25,.6))
	if fusion or torpedo:
		ring(1.0,.06,0,2.5,Vector3(.18,.1,0),TAU*.96,3 if fusion else 0)
		ring(.7,.045,-.15,-3.5,Vector3(-.2,.4,0),TAU*.85)
	if not torpedo:
		for i in (9 if fusion else 6):
			var a:=TAU*i/(9 if fusion else 6)
			var n:=add_piece(spindle([Vector2(0,-.6),Vector2(.025,0),Vector2(0,.6)],6),2,Vector3(cos(a)*.58,sin(a)*.58,-.1))
			n.rotation=Vector3(sin(a)*1.1,cos(a)*1.1,0)
func advance_impact(time: float, age: float, radius: float) -> void:
	for m in materials:
		m.set_shader_parameter("phase",time);m.set_shader_parameter("opacity",pow(1.0-age,1.4))
	for motion in moving:motion.node.rotation=motion.base+Vector3(0,0,time*motion.speed)
	scale=Vector3.ONE*radius*(.20+age*1.4)
