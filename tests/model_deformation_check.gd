extends SceneTree
## Synthetic geometry checks run without imported game content.
const Library = preload("res://scripts/model_library.gd")
const Model = preload("res://native/presentation/model.gd")
const View = preload("res://native/presentation/world_view.gd")
var failures := 0

func expect(ok: bool, why: String) -> void:
	if not ok:failures+=1;push_error(why)
func _initialize() -> void:call_deferred("run")

func figure(library) -> Node3D:
	var model:=Model.new();model.library=library;model.modern_graphics=false
	model.record={"id":4431,"model":"synthetic.mbac","textures":[]}
	model.source=library.models["synthetic.mbac"];model.refresh()
	return model

func material(model) -> ShaderMaterial:
	return model.figure.get_node("Mesh").get_surface_override_material(0)

func frame(viewport: SubViewport) -> Image:
	for i in 3:await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()

func check_triangle(viewport: SubViewport, camera: Camera3D, model, label: String) -> void:
	if DisplayServer.get_name()=="headless":return
	var image:=await frame(viewport)
	var polygon:=PackedVector2Array()
	for i in 3:
		var point:=Library.point(model.source.vertices,i*3)
		point=Library.bend_lamp(Transform3D(Basis.IDENTITY,point),model.hinge_axis,model.hinge_bend).origin
		polygon.append(camera.unproject_position(model.transform*point))
	var mismatches:=0;var covered:=0
	for y in image.get_height():
		for x in image.get_width():
			var pixel:=Vector2(x+.5,y+.5);var edge:=false
			for i in 3:
				if Geometry2D.get_closest_point_to_segment(pixel,polygon[i],polygon[(i+1)%3]).distance_to(pixel)<2:edge=true;break
			if edge:continue
			var inside:=Geometry2D.is_point_in_polygon(pixel,polygon)
			var drawn:=image.get_pixel(x,y).r>.25
			if inside:covered+=1
			if inside!=drawn:mismatches+=1
	expect(covered>100 and mismatches<5,label+" matches its projected geometry (%d pixels differ)"%mismatches)

func run() -> void:
	var library:=Library.new();library.enhanced=false
	library.models["synthetic.mbac"]={
		"vertices":[-200,-100,500,200,-100,500,0,200,500],"normals":[],
		"bones":[{"vertices":3,"parent":-1,"matrix":[1,0,0,0,0,1,0,0,0,0,1,0]}],
		"segment_bounds":[AABB(Vector3(-2,-2,-5),Vector3(4,3,.001))],
		"polygons":[{"indices":[0,1,2],"attributes":[255,255,255,0,0,255,255,255,0,0,255,255,255,0,0],"texture":-1,"blend":0,"pattern":0,"double_sided":true}]}
	var viewport:=SubViewport.new();viewport.size=Vector2i(240,240);viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color.BLACK;viewport.add_child(environment)
	var camera:=Camera3D.new();camera.position=Vector3(0,0,12);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=12;viewport.add_child(camera)
	# Catalogue warmup and hidden animation variants also occupy shader instance
	# slots. Rigid geometry must stay upright after that small GPU buffer fills.
	for i in 300:
		var hidden=figure(library);viewport.add_child(hidden);hidden.hide()
	await process_frame
	var first=figure(library);var second=figure(library);viewport.add_child(first);viewport.add_child(second);second.hide()
	expect(material(first)==material(second),"Rigid instances share the undeformed pose")
	for gain in [.4,1.0,1.8]:
		RenderingServer.global_shader_parameter_set("ocean_light_gain",gain)
		await check_triangle(viewport,camera,first,"Rigid model at ocean light %s"%gain)
	for axis in [0,1]:
		first.set_hinge(axis,.45)
		expect(material(first)!=material(second) and material(second).get_shader_parameter("hinge_bend")==0.0,"Creature deformation leaves the shared rigid pose untouched")
		expect(material(first).get_shader_parameter("hinge_axis")==axis and is_equal_approx(material(first).get_shader_parameter("hinge_bend"),.45),"Bend parameters belong to the model's material")
		await check_triangle(viewport,camera,first,"Creature bend on axis %d"%axis)
	first.set_stream_visibility(.35);first.set_stream_visibility(1.0)
	await check_triangle(viewport,camera,first,"Creature after its stream fade")
	first.set_portal_clip(true,Vector4(0,0,1,100))
	# A previously unseen pose must not cache the current model's own bend.
	first.clock.frame=1;first.refresh();second.clock.frame=1;second.refresh()
	expect(material(second).get_shader_parameter("hinge_bend")==0.0 and not material(second).has_meta("hinge_original"),"A new cached animation pose remains undeformed")
	await check_triangle(viewport,camera,first,"Creature after a pose refresh")
	first.set_portal_clip(false);first.set_hinge(1,0.0)
	await check_triangle(viewport,camera,first,"Creature returned to rest")
	first.hide();second.show()
	var rest:=Transform3D(Basis(Vector3.UP,.6),Vector3.ZERO)
	for units in [0,512,1024,2048]:
		second.transform=View.gate_idle_transform(rest,units)
		await check_triangle(viewport,camera,second,"Gate frame at %d rotation units"%units)
	RenderingServer.global_shader_parameter_set("ocean_light_gain",1.0)
	viewport.queue_free();await process_frame
	print("MODEL_DEFORMATION %d failures"%failures)
	quit(1 if failures else 0)
