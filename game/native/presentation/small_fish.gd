extends MultiMeshInstance3D
## Small fish: schools, loose groups and single fish swimming through the
## open water round the camera, each fleeing as the hull comes near. Art
## direction only, in one draw (small_fish.gdshader); they are not actors,
## cannot be caught and never touch the simulation or its random numbers.
##
## Each slot keeps a home in a block of water that repeats round the camera,
## as the distant plankton does, and wanders slowly about it. The blocks are
## anchored in the open world: fish stay put in the water while the hull
## passes, and the next block over may hold other fish or none. Which block
## it is also picks the fish's kind, size and markings. A block changes only
## beyond the distance its fish fade out at.

enum {SCHOOL,GROUP,SINGLE}
## Slots of each kind: schools of tiny to small fish, loose groups whose
## fish swim each their own way, and single fish (at most 128 in all).
const KIND_SLOTS := [48,32,48]
## Small fish are seen only close by, so the smaller kinds repeat in smaller,
## denser blocks of water and fade out sooner (REACH, in metres).
const PERIODS := [Vector3(200.0,60.0,200.0),Vector3(120.0,40.0,120.0),Vector3(60.0,30.0,60.0)]
const WANDERS := [Vector3(18.0,3.0,18.0),Vector3(10.0,2.5,10.0),Vector3(5.0,2.0,5.0)]
const REACH := [72.0,46.0,24.0]
## Species (small_fish.gdshader): 0 sardine, 1 bream, 2 needlefish,
## 3 grouper, 4 bannerfish, 5 redfish, 6 neon, 7 lanternfish. Each kind
## draws from its own list; redfish and lanternfish grow commoner deeper.
const SPECIES := [[0,0,0,1,1,6,6,2],[1,1,2,4,4,6,3,0],[2,3,3,4,4,1,0,6]]
const DEEP_SPECIES := [[5,7,7],[5,5,7],[5,5,3]]
## Station modules the fish keep clear of, refreshed this often in seconds.
const OBSTACLE_REFRESH := .5
const OBSTACLE_MARGIN := 4.0

var material := ShaderMaterial.new()
var data := Image.create_empty(4,128,false,Image.FORMAT_RGBAF)
var data_texture := ImageTexture.create_from_image(data)
var kinds := PackedInt32Array()
var counts := PackedInt32Array()
var homes: Array[Vector3] = []
var rates: Array[Vector3] = []
var phases: Array[Vector3] = []
var radii := PackedFloat32Array()
## How fast each slot's fish dash away, in metres a second.
var dashes := PackedFloat32Array()
var blocked := PackedFloat32Array()
var alarms := PackedFloat32Array()
var offsets: Array[Vector3] = []
var flights: Array[Vector3] = []
var blocks: Array[Vector3] = []
## Each slot's centre round the camera and its presence, as last drawn.
var places := PackedVector4Array()
var obstacles: Array[AABB] = []
var obstacles_at := -INF
var last_hull := Vector3.INF
var hull_motion := Vector3.ZERO

func _init() -> void:
	name="SmallFish"
	top_level=true;visible=false
	cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	material.shader=preload("res://native/presentation/small_fish.gdshader")
	material.set_shader_parameter("school_data",data_texture)
	var body := fish_mesh();body.surface_set_material(0,material)
	var rng := RandomNumberGenerator.new();rng.seed=731149
	var fish: Array[Color] = []
	for kind in KIND_SLOTS.size():
		for i in KIND_SLOTS[kind]:
			var slot := kinds.size()
			var count := 1;var length := rng.randf_range(.15,.7);var spread := 0.0
			if kind==SCHOOL:
				count=rng.randi_range(8,40)
				# Bigger schools are of smaller fish.
				length=lerpf(.4,.14,(count-8)/32.0)*rng.randf_range(.85,1.15);spread=.15
			elif kind==GROUP:
				count=rng.randi_range(3,7);length=rng.randf_range(.25,.6);spread=.3
			kinds.append(kind);counts.append(count)
			homes.append(Vector3(rng.randf(),rng.randf(),rng.randf())*PERIODS[kind])
			rates.append(Vector3(rng.randf_range(.035,.065),rng.randf_range(.05,.09),rng.randf_range(.035,.065))*(.7 if kind==SINGLE else 1.0))
			phases.append(Vector3(rng.randf(),rng.randf(),rng.randf())*TAU)
			radii.append((.9+.55*sqrt(count))*length*2.0 if kind==SCHOOL else (rng.randf_range(4.0,9.0) if kind==GROUP else 0.0))
			# Small fish dart slower than large ones, never as fast as a hull.
			dashes.append(clampf(3.0+10.0*length,3.5,9.0)*rng.randf_range(.85,1.15))
			blocked.append(0.0);alarms.append(0.0)
			offsets.append(Vector3.ZERO);flights.append(Vector3.ZERO);blocks.append(Vector3.INF)
			for f in count:
				# Slot, seed, length in metres and whether it swims its own way.
				fish.append(Color(slot,rng.randf(),length*rng.randf_range(1.0-spread,1.0+spread),0.0 if kind==SCHOOL else 1.0))
	var school := MultiMesh.new()
	school.transform_format=MultiMesh.TRANSFORM_3D;school.use_custom_data=true;school.mesh=body
	school.instance_count=fish.size()
	for index in fish.size():
		school.set_instance_transform(index,Transform3D.IDENTITY)
		school.set_instance_custom_data(index,fish[index])
	multimesh=school
	# The vertex shader places every fish within reach of the camera.
	custom_aabb=AABB(-Vector3(100,100,100),Vector3(200,200,200))

static func fish_mesh() -> ArrayMesh:
	"""A one-metre fish along +z, snout forward: a laterally flattened body,
	a forked tail and a dorsal fin. COLOR.r runs from the snout (0) to the
	tail's tip (1), which the shader bends; COLOR.g marks the fins."""
	var stations := [0.0,.06,.16,.3,.45,.6,.72,.78]
	var heights := [0.0,.07,.11,.125,.115,.085,.05,.03]
	var sides := 10
	var points := PackedVector3Array();var normals := PackedVector3Array();var colors := PackedColorArray();var faces := PackedInt32Array()
	for ring in stations.size():
		var z: float=.5-stations[ring]
		var h: float=heights[ring];var w: float=h*.45
		var before: float=heights[maxi(ring-1,0)];var after: float=heights[mini(ring+1,stations.size()-1)]
		var slope: float=(after-before)/maxf(stations[mini(ring+1,stations.size()-1)]-stations[maxi(ring-1,0)],.001)
		for side in sides:
			var angle := TAU*side/sides
			points.append(Vector3(cos(angle)*w,sin(angle)*h,z))
			normals.append(Vector3(cos(angle)/.45,sin(angle),slope).normalized())
			colors.append(Color(stations[ring],0,0))
	for ring in stations.size()-1:
		for side in sides:
			var a: int=ring*sides+side;var b: int=ring*sides+(side+1)%sides
			faces.append_array([a,b,a+sides,b,b+sides,a+sides])
	# The peduncle's open end is hidden by the tail fin.
	var fin := func(corners: Array) -> void:
		for corner in corners:
			faces.append(points.size())
			points.append(corner);normals.append(Vector3.RIGHT);colors.append(Color(.5-corner.z,1,0))
	var root: float=.5-stations[-1]
	fin.call([Vector3(0,.035,root),Vector3(0,.17,-.5),Vector3(0,0,-.41)])
	fin.call([Vector3(0,.035,root),Vector3(0,0,-.41),Vector3(0,-.035,root)])
	fin.call([Vector3(0,-.035,root),Vector3(0,0,-.41),Vector3(0,-.17,-.5)])
	fin.call([Vector3(0,.118,.18),Vector3(0,.2,.02),Vector3(0,.085,-.12)])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=points;arrays[Mesh.ARRAY_NORMAL]=normals;arrays[Mesh.ARRAY_COLOR]=colors;arrays[Mesh.ARRAY_INDEX]=faces
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh

static func block_hash(block: Vector3, slot: int, salt: float) -> float:
	return fposmod(sin(block.dot(Vector3(127.1,311.7,74.7))+slot*19.19+salt)*43758.5453,1.0)

func refresh_obstacles(roots: Array, clock: float) -> void:
	"""The station modules close enough to matter, as world boxes."""
	if absf(clock-obstacles_at)<OBSTACLE_REFRESH:return
	obstacles_at=clock;obstacles.clear()
	for root in roots:
		if root is Node3D and is_instance_valid(root):collect_boxes(root)

func collect_boxes(node: Node) -> void:
	if node is MeshInstance3D and node.is_visible_in_tree():
		var box: AABB=node.global_transform*node.get_aabb()
		obstacles.append(box.grow(OBSTACLE_MARGIN))
	for child in node.get_children():collect_boxes(child)

static func touches(box: AABB, centre: Vector3, radius: float) -> bool:
	var nearest := centre.clamp(box.position,box.end)
	return nearest.distance_squared_to(centre)<radius*radius

func update(seconds: float, clock: float, eye: Array, drift: Vector3, current: Vector3, camera_position: Vector3, hull: Vector3, depth: float) -> void:
	"""eye is the camera in the open world as doubles (abyss.absolute_eye)."""
	global_transform=Transform3D(Basis.IDENTITY,camera_position)
	# The hull's velocity, eased; a region change moves it by far more.
	if seconds>0.0:
		var moved: Vector3=(hull-last_hull)/seconds if last_hull.is_finite() else Vector3.ZERO
		if moved.length()>400.0:moved=hull_motion
		hull_motion=hull_motion.lerp(moved,1.0-exp(-seconds*6.0))
		last_hull=hull
	var near_hull := hull-camera_position
	var pace := hull_motion.length()
	var path := hull_motion/pace if pace>.5 else Vector3.ZERO
	# Fewer fish in the deep, and more of them red or dark.
	var deep := clampf((depth-15000.0)/15000.0,0.0,1.0)
	var density := lerpf(.9,.6,deep)
	places.resize(kinds.size())
	var rows := PackedFloat32Array();rows.resize(data.get_width()*data.get_height()*4)
	for slot in kinds.size():
		var kind: int=kinds[slot]
		var period: Vector3=PERIODS[kind]
		# The home's offset from the eye, in doubles, then reduced to the
		# block round the camera; which block it is picks the fish.
		var home: Vector3=homes[slot]+drift
		var reach := Vector3.ZERO;var block := Vector3.ZERO
		for axis in 3:
			var offset: float=float(home[axis])-float(eye[axis])+period[axis]*.5
			block[axis]=floorf(offset/period[axis])
			reach[axis]=fposmod(offset,period[axis])-period[axis]*.5
		if block!=blocks[slot]:
			blocks[slot]=block;offsets[slot]=Vector3.ZERO;flights[slot]=Vector3.ZERO;alarms[slot]=0.0
		var shift := block_hash(block,slot,3.1)*TAU
		var angle: Vector3=rates[slot]*clock+phases[slot]+Vector3.ONE*shift
		var wander: Vector3=WANDERS[kind]
		var centre: Vector3=reach+wander*Vector3(sin(angle.x),sin(angle.y),sin(angle.z))+offsets[slot]
		var velocity: Vector3=wander*rates[slot]*Vector3(cos(angle.x),cos(angle.y),cos(angle.z))+current
		# Fish that sense the hull coming, sooner the faster it is, turn and
		# swim away from it, off its path rather than racing ahead of it,
		# then calm down and drift home.
		var from_hull: Vector3=centre-near_hull
		var apart := from_hull.length()
		if apart<8.0+minf(pace*.6,18.0)+radii[slot]:alarms[slot]=1.0
		else:alarms[slot]=move_toward(alarms[slot],0.0,seconds/3.0)
		var dash := Vector3.ZERO
		if alarms[slot]>0.0 and apart>.001:
			var away: Vector3=from_hull/apart
			var ahead_of := maxf(away.dot(path),0.0)
			var aside := Vector3.UP.cross(path)*(1.0 if block_hash(block,slot,19.1)<.5 else -1.0)
			away+=aside*ahead_of*.8-path*ahead_of*.6
			away.y*=.5
			dash=away.normalized()*dashes[slot]*alarms[slot]
		flights[slot]=flights[slot].lerp(dash,1.0-exp(-seconds*4.0))
		var settle: Vector3=Vector3.ZERO if alarms[slot]>0.0 else -offsets[slot].limit_length(.4)
		offsets[slot]=(offsets[slot]+(flights[slot]+settle)*seconds).limit_length(period.x*.2)
		velocity+=flights[slot]+settle
		var clear := true
		for box in obstacles:
			if touches(box,camera_position+centre,radii[slot]+1.0):clear=false;break
		blocked[slot]=move_toward(blocked[slot],0.0 if clear else 1.0,seconds/.8)
		# Fade out before the block wraps to the other side of the camera.
		var edge := 1.0-smoothstep(.36,.47,maxf(absf(reach.x)/period.x,absf(reach.z)/period.z))
		edge*=1.0-smoothstep(.33,.47,absf(reach.y)/period.y)
		var present := block_hash(block,slot,7.7)<density
		var presence := (1.0-blocked[slot])*edge if present else 0.0
		var pick := block_hash(block,slot,11.3)
		var species: int=DEEP_SPECIES[kind][int(pick*97.0)%3] if pick<.1+.4*deep else SPECIES[kind][int(block_hash(block,slot,5.9)*8.0)%8]
		var size := lerpf(.6,1.6,block_hash(block,slot,13.7)) if kind==SINGLE else lerpf(.75,1.35,block_hash(block,slot,13.7))
		places[slot]=Vector4(centre.x,centre.y,centre.z,presence)
		var at := slot*16
		for value in [centre.x,centre.y,centre.z,presence,velocity.x,velocity.y,velocity.z,radii[slot],
				species,shift*7.0,alarms[slot],REACH[kind],size,block_hash(block,slot,17.3),0.0,0.0]:
			rows[at]=value;at+=1
	data.set_data(data.get_width(),data.get_height(),false,Image.FORMAT_RGBAF,rows.to_byte_array())
	data_texture.update(data)
	material.set_shader_parameter("hull",near_hull)
	material.set_shader_parameter("hull_motion",hull_motion)
	material.set_shader_parameter("clock",clock)
