extends RefCounted
## Closed, clockwise-wound hardware for the enhanced torpedo family.
const SIDES=32
const TAIL_Z=.32

static func build() -> ArrayMesh:
	var surface:=SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Follow the imported model's long body and tail-origin layout: after
	# its in-flight 2x scale, the source extends from -7.04 to +0.32 on Z.
	# A hemispherical nose joins the cylinder without a pointed rocket tip.
	var profile: Array[Vector2]=[]
	for i in 9:
		var angle:=PI*.5*i/8
		profile.append(Vector2(.56*sin(angle),-6.48-.56*cos(angle)))
	profile.append_array([Vector2(.56,-1.85),Vector2(.54,-1.50),Vector2(.48,-1.15),Vector2(.37,-.80),Vector2(.23,-.44),Vector2(.11,-.16),Vector2(.085,.10),Vector2(0,.10)])
	lathe(surface,profile,0)
	# Small, straight stabilisers sit only at the tapered stern.
	for side in 4:fin(surface,TAU*side/4)
	# A thin, closed pump-jet guard surrounds the screw. Four small stator
	# supports join it to the shaft ahead of the rotating blades.
	lathe(surface,[Vector2(.48,-.18),Vector2(.535,-.14),Vector2(.535,.25),Vector2(.50,.30),Vector2(.475,.27),Vector2(.475,-.13),Vector2(.48,-.18)],6)
	for side in 4:
		var rotation:=Basis(Vector3.BACK,TAU*side/4)
		var center:=rotation*Vector3(.29,0,-.11)
		var corners: Array[Vector3]=[]
		for z in [-.145,-.075]:
			for y in [-.018,.018]:
				for x in [.07,.49]:corners.append(rotation*Vector3(x,y,z))
		for face in [[0,1,3,2],[4,6,7,5],[0,4,5,1],[2,3,7,6],[0,2,6,4],[1,5,7,3]]:
			flat_triangle(surface,[corners[face[0]],corners[face[1]],corners[face[2]]],center,6)
			flat_triangle(surface,[corners[face[0]],corners[face[2]],corners[face[3]]],center,6)
	return surface.commit()

static func propeller() -> ArrayMesh:
	var surface:=SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	lathe(surface,[Vector2(0,-.08),Vector2(.12,-.08),Vector2(.13,.12),Vector2(.10,.24),Vector2(0,TAIL_Z)],2)
	# Five pitched blades, mounted on the shaft rather than a glowing nozzle.
	for side in 5:
		var rotation:=Basis(Vector3.BACK,TAU*side/5)
		var center:=Vector3.ZERO
		var face: Array[Vector3]=[]
		for p in [Vector3(.08,-.045,0),Vector3(.40,-.10,0),Vector3(.46,.035,0),Vector3(.16,.08,0)]:
			p.z=.08+.8*p.y+.12*p.x
			face.append(rotation*p);center+=rotation*p/4.0
		var front: Array[Vector3]=[];var back: Array[Vector3]=[]
		for p in face:front.append(p+Vector3(0,0,.014));back.append(p-Vector3(0,0,.014))
		for panel in [front,back]:
			flat_triangle(surface,[panel[0],panel[1],panel[2]],center,2)
			flat_triangle(surface,[panel[0],panel[2],panel[3]],center,2)
		for i in 4:
			var j: int=(i+1)%4
			flat_triangle(surface,[front[i],front[j],back[i]],center,2)
			flat_triangle(surface,[front[j],back[j],back[i]],center,2)
	return surface.commit()

static func triangle(surface: SurfaceTool, vertices: Array[Vector3], normals: Array[Vector3], part: int) -> void:
	# Godot's front faces are clockwise. Explicit outward normals also avoid
	# shading a nose cap or fin as though it were the inside of the hull.
	var order: Array[int]=[0,1,2]
	if (vertices[1]-vertices[0]).cross(vertices[2]-vertices[0]).dot(normals[0]+normals[1]+normals[2])>0:order=[0,2,1]
	surface.set_color(Color(float(part)/8.0,0,0))
	for i in order:
		surface.set_normal(normals[i]);surface.add_vertex(vertices[i])

static func lathe(surface: SurfaceTool, profile: Array[Vector2], part: int) -> void:
	for r in range(profile.size()-1):
		var p:=profile[r];var q:=profile[r+1];var delta:=q-p
		for i in SIDES:
			var a:=TAU*i/SIDES;var b:=TAU*(i+1)/SIDES
			var na:=Vector3(delta.y*cos(a),delta.y*sin(a),-delta.x).normalized()
			var nb:=Vector3(delta.y*cos(b),delta.y*sin(b),-delta.x).normalized()
			var pa:=Vector3(p.x*cos(a),p.x*sin(a),p.y);var pb:=Vector3(p.x*cos(b),p.x*sin(b),p.y)
			var qa:=Vector3(q.x*cos(a),q.x*sin(a),q.y);var qb:=Vector3(q.x*cos(b),q.x*sin(b),q.y)
			if p.x>0:triangle(surface,[pa,qa,pb],[na,na,nb],part)
			if q.x>0:triangle(surface,[pb,qa,qb],[nb,na,nb],part)

static func fin(surface: SurfaceTool, angle: float) -> void:
	var outline:=PackedVector2Array([Vector2(.38,-1.28),Vector2(.69,-1.16),Vector2(.69,-.39),Vector2(.12,-.34)])
	var center:=Vector2(.47,-.81)
	var rotation:=Basis(Vector3.BACK,angle)
	var origin:=rotation*Vector3(center.x,0,center.y)
	var edge: Array[Vector3]=[];var top: Array[Vector3]=[];var bottom: Array[Vector3]=[]
	for p in outline:
		var inset:=center+(p-center)*.84
		edge.append(rotation*Vector3(p.x,0,p.y))
		top.append(rotation*Vector3(inset.x,.025,inset.y));bottom.append(rotation*Vector3(inset.x,-.025,inset.y))
	for face in [top,bottom]:
		flat_triangle(surface,[face[0],face[1],face[2]],origin,3)
		flat_triangle(surface,[face[0],face[2],face[3]],origin,3)
		for i in 4:
			var j: int=(i+1)%4
			flat_triangle(surface,[face[i],edge[i],edge[j]],origin,3)
			flat_triangle(surface,[face[i],edge[j],face[j]],origin,3)

static func flat_triangle(surface: SurfaceTool, vertices: Array[Vector3], center: Vector3, part: int) -> void:
	var normal: Vector3=(vertices[1]-vertices[0]).cross(vertices[2]-vertices[0]).normalized()
	if normal.dot((vertices[0]+vertices[1]+vertices[2])/3.0-center)<0:normal=-normal
	triangle(surface,vertices,[normal,normal,normal],part)
