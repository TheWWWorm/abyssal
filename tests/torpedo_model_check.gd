extends SceneTree
const Form=preload("res://native/presentation/weapon_form.gd")
var checks:=0
var failures:=0
var output:=""
func expect(ok: bool, why: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(why)
func _initialize() -> void:call_deferred("run")
func point_key(p: Vector3) -> String:
	return str(Vector3i((p*100000.0).round()))
func check_closed_mesh() -> void:
	for mesh in [Form.TorpedoMesh.build(),Form.TorpedoMesh.propeller()]:check_mesh(mesh)
	var bounds:=Form.TorpedoMesh.build().get_aabb()
	expect(is_equal_approx(bounds.position.z,-7.04) and bounds.size.z>7.1 and bounds.size.x<1.5,"The hull follows the original length, tail origin and small stabilisers")
func check_mesh(mesh: ArrayMesh) -> void:
	var arrays:=mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
	var edges: Dictionary={};var inward:=0;var degenerate:=0
	for i in range(0,vertices.size(),3):
		var cross: Vector3=(vertices[i+1]-vertices[i]).cross(vertices[i+2]-vertices[i])
		if cross.length_squared()<1e-14:degenerate+=1
		if cross.dot(normals[i]+normals[i+1]+normals[i+2])>=0:inward+=1
		for j in 3:
			var a:=point_key(vertices[i+j]);var b:=point_key(vertices[i+(j+1)%3])
			var key: String=a+":"+b if a<b else b+":"+a
			edges[key]=int(edges.get(key,0))+1
	expect(degenerate==0,"The torpedo has no collapsed nose or tail triangles")
	expect(inward==0,"Every torpedo triangle is front-facing from its outward normal")
	expect(edges.values().all(func(count):return count==2),"Hull, fins, collars and drive are closed without exposed mesh boundaries")
func settle(viewport: SubViewport) -> Image:
	for i in 4:await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()
func run() -> void:
	var args:=OS.get_cmdline_user_args()
	if not args.is_empty():output=args[0]
	check_closed_mesh()
	if DisplayServer.get_name()!="headless":await check_render()
	print("TORPEDO_MODEL ",checks," checks; ",failures," failures");quit(1 if failures else 0)
func check_render() -> void:
	var viewport:=SubViewport.new();viewport.size=Vector2i(320,320);viewport.own_world_3d=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;viewport.add_child(env)
	var camera:=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=8;viewport.add_child(camera)
	for id in [12,13,14]:
		var form:=Form.new();form.configure(id,Color.WHITE);viewport.add_child(form)
		var center:=Vector3(0,0,-3.36)
		for piece in form.pieces:piece.visible=piece.material_override.shader==Form.TORPEDO
		for direction in [Vector3.BACK,Vector3.FORWARD,Vector3.RIGHT,Vector3.LEFT,Vector3.UP,Vector3.DOWN,Vector3(1,.6,1).normalized()]:
			camera.position=center+direction*12;camera.look_at(center,Vector3.FORWARD if absf(direction.y)>.99 else Vector3.UP)
			form.advance(.35,camera)
			expect(form.scale==Vector3.ONE,"The torpedo stays cylindrical rather than widening at distance")
			env.environment.background_color=Color(.8,.05,.02)
			var red:=await settle(viewport)
			env.environment.background_color=Color(.02,.8,.05)
			var green:=await settle(viewport)
			var leaks:=0
			for y in range(157,163):
				for x in range(157,163):
					if red.get_pixel(x,y)!=green.get_pixel(x,y):leaks+=1
			expect(leaks==0,"Torpedo %d fully hides the far side at viewing direction %s"%[id,direction])
			if not output.is_empty() and direction in [Vector3.BACK,Vector3.FORWARD,Vector3(1,.6,1).normalized()]:
				env.environment.background_color=Color("263e48");var capture:=await settle(viewport)
				capture.save_png(output.path_join("torpedo-%d-%s.png"%[id,"tail" if direction==Vector3.BACK else "nose" if direction==Vector3.FORWARD else "side"]))
		form.queue_free();await process_frame
	viewport.queue_free();await process_frame
