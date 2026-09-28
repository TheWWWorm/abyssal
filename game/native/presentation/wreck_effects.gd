extends Node3D
## A finite aftermath for vessel explosions, surviving the source flash event.
## Absolute positions preserve the cloud when open-world travel rebases a region.
const Library=preload("res://scripts/model_library.gd")
const Math=preload("res://native/simulation/fixed_math.gd")
const CAPACITY := 12
const CLOUDS := 6
const FRAGMENTS := 12
const LIFETIME := 10.0
var clouds := MultiMeshInstance3D.new()
var fragments := MultiMeshInstance3D.new()
var events: Array=[]
var seen := {}
var observed_region := 0

func make_pool(node: MultiMeshInstance3D, mesh: Mesh, count: int, debris: bool) -> void:
	var material := ShaderMaterial.new();material.shader=preload("res://native/presentation/wreck_cloud.gdshader")
	material.set_shader_parameter("debris",debris);mesh.material=material
	var pool := MultiMesh.new();pool.transform_format=MultiMesh.TRANSFORM_3D;pool.use_colors=true;pool.use_custom_data=true;pool.mesh=mesh
	pool.instance_count=count;pool.visible_instance_count=0;node.multimesh=pool
	node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;add_child(node)

func _ready() -> void:
	var quad := QuadMesh.new();quad.size=Vector2.ONE;make_pool(clouds,quad,CAPACITY*CLOUDS,false)
	var shard := BoxMesh.new();shard.size=Vector3.ONE;make_pool(fragments,shard,CAPACITY*FRAGMENTS,true)

func reset() -> void:
	events.clear();seen.clear();observed_region=0
	for node in [clouds,fragments]:node.multimesh.visible_instance_count=0

func update(region, milliseconds: float, anchor: Vector3, eye: Vector3, enhanced: bool) -> void:
	if not enhanced:
		if not events.is_empty() or not seen.is_empty():reset()
		return
	var seconds := maxf(0.0,milliseconds*.001)
	for event in events:event.age+=seconds
	events=events.filter(func(event):return event.age<LIFETIME)
	if observed_region!=region.get_instance_id():seen.clear();observed_region=region.get_instance_id()
	var present := {}
	for event in region.visual_events:
		if event.kind!="explosion" or event.creature:continue
		for i in event.delays.size():
			var key := str(event.time)+":"+str(event.position)+":"+str(i)
			if seen.has(key):present[key]=true;continue
			var age := float(region.elapsed_ms-event.time-int(event.delays[i]))*.001
			if age<0:continue
			present[key]=true
			# Opening a menu or streaming in cannot replay an old detonation.
			if age>.65:continue
			var offset: Array=event.offsets[i] if i<event.offsets.size() else [0,0,0]
			var at := Library.point(Math.added(event.position,offset))
			if at.distance_to(eye)>650:continue
			if events.size()>=CAPACITY:events.pop_front()
			events.append({"at":at+anchor,"age":age,"radius":16.0 if event.delays.size()>1 else 12.0,"seed":float(absi(key.hash())%10000)*.001})
	seen=present
	var cloud_count := 0;var fragment_count := 0
	var bounds := AABB();var first := true
	for event in events:
		var age: float=event.age;var seed: float=event.seed;var radius: float=event.radius
		var center: Vector3=event.at-anchor
		var box := AABB(center-Vector3.ONE*80,Vector3.ONE*160)
		bounds=box if first else bounds.merge(box);first=false
		if age<7.5:
			for i in CLOUDS:
				var angle := i*2.399963+seed
				var direction := Vector3(cos(angle),sin(angle*1.7)*.35,sin(angle))
				var at := center+direction*radius*(.13+.5*(1.0-exp(-age*.7)))+Vector3.UP*age*(1.4+float(i)*.16)
				var diameter := radius*(.9+sqrt(age)*.65)*(1.0+sin(angle*3)*.12)
				var opacity := .38*smoothstep(0.0,.18,age)*pow(1.0-age/7.5,1.4)
				clouds.multimesh.set_instance_transform(cloud_count,Transform3D(Basis.IDENTITY,at))
				clouds.multimesh.set_instance_color(cloud_count,Color(.55,.7,.73,opacity))
				clouds.multimesh.set_instance_custom_data(cloud_count,Color(diameter,age,seed+i,0));cloud_count+=1
		for i in FRAGMENTS:
			var angle := i*2.399963+seed
			var direction := Vector3(cos(angle),sin(angle*2.3)*.55,sin(angle))
			# Initial scatter is arrested by water drag; fragments then sink.
			var at := center+direction*radius*.9*(1.0-exp(-age*1.7))+Vector3.DOWN*age*(.5+float(i%4)*.22)
			var spin := Basis.from_euler(Vector3(angle*.7,angle,angle*.4)+Vector3(.7,.45,.3)*age)
			var size := .14+float(i%4)*.1
			fragments.multimesh.set_instance_transform(fragment_count,Transform3D(spin.scaled_local(Vector3(size*2.8,size*.35,size)),at))
			fragments.multimesh.set_instance_color(fragment_count,Color(.34,.4,.42,1.0-smoothstep(7.0,LIFETIME,age)))
			fragment_count+=1
	clouds.multimesh.visible_instance_count=cloud_count;fragments.multimesh.visible_instance_count=fragment_count
	for node in [clouds,fragments]:node.custom_aabb=bounds if not first else AABB(Vector3.ONE*-1,Vector3.ONE*2)

func _exit_tree() -> void:
	for node in [clouds,fragments]:node.multimesh=null
