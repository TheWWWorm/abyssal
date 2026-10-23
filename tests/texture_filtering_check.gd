extends SceneTree
## Synthetic high-resolution paint must minify consistently even when the
## source texel positions are snapped for the pixelated look. Needs a GPU.
const Library = preload("res://scripts/model_library.gd")
const Mods = preload("res://native/presentation/mods.gd")
const DIRECTORY := "user://texture-filtering-check"
var failures := 0

func _initialize() -> void:run.call_deferred()
func expect(ok: bool, message: String) -> void:
	if not ok:failures+=1;push_error(message)

func mesh_for(span: float) -> ArrayMesh:
	var quad := QuadMesh.new();quad.size=Vector2(2,2)
	var arrays := quad.surface_get_arrays(0)
	var uv: PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV]
	for i in uv.size():uv[i]=Vector2(8,8)+uv[i]*span
	arrays[Mesh.ARRAY_TEX_UV]=uv
	var result := ArrayMesh.new();result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return result

func run() -> void:
	if DisplayServer.get_name()=="headless":
		print("TEXTURE_FILTERING skipped: render with a GPU to check minification");quit();return
	var cleanup := preload("res://native/platform/content_pack.gd").new();cleanup.remove_tree(DIRECTORY)
	Mods.only_root=DIRECTORY.path_join("mods")
	DirAccess.make_dir_recursive_absolute(DIRECTORY.path_join("data/textures"));DirAccess.make_dir_recursive_absolute(Mods.only_root.path_join("textures"))
	var original := Image.create(128,128,false,Image.FORMAT_RGBA8);original.fill(Color(.5,.5,.5));original.save_png(DIRECTORY.path_join("data/textures/sample.bmp.png"))
	var enlarged := Image.create(1024,1024,false,Image.FORMAT_RGBA8)
	for y in 1024:
		for x in 1024:
			var c := .9 if (x+y)%2 else .1;enlarged.set_pixel(x,y,Color(c,c,c))
	enlarged.save_png(Mods.only_root.path_join("textures/sample.png"))
	var library := Library.new();library.root=DIRECTORY
	var material := library.affine_material("data/textures/sample.bmp",0,false,false,false,0,true,false)
	var bones: Array[Transform3D]=[];bones.resize(64);bones.fill(Transform3D.IDENTITY);material.set_shader_parameter("source_bones",bones)
	var viewport := SubViewport.new();viewport.size=Vector2i(64,64);viewport.own_world_3d=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var camera := Camera3D.new();camera.position=Vector3(0,0,3);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=2;camera.current=true;viewport.add_child(camera)
	var node := MeshInstance3D.new();node.mesh=mesh_for(32);node.material_override=material;viewport.add_child(node)
	var worst := 0.0
	for frame in 8:
		camera.position.x=frame*.25*2.0/64.0
		for settle in 3:await process_frame
		await RenderingServer.frame_post_draw
		var drawn := viewport.get_texture().get_image()
		for y in range(8,56):
			for x in range(8,56):worst=maxf(worst,absf(drawn.get_pixel(x,y).r-.5))
	expect(worst<.035,"Minified high-resolution paint stays averaged while the camera crosses snapped texels (error %f)"%worst)
	# A replacement has eight real texels inside each imported texel. All of
	# them must be visible, rather than one arbitrary sample enlarged eightfold.
	for y in 1024:
		for x in 1024:
			var c := .9 if x%2 else .1;enlarged.set_pixel(x,y,Color(c,c,c))
	enlarged.save_png(Mods.only_root.path_join("textures/sample.png"));library.reload_textures()
	node.mesh=mesh_for(1.0);camera.position.x=0
	for settle in 3:await process_frame
	await RenderingServer.frame_post_draw
	var close := viewport.get_texture().get_image()
	var low := 1.0;var high := 0.0
	for x in range(4,60):low=minf(low,close.get_pixel(x,32).r);high=maxf(high,close.get_pixel(x,32).r)
	expect(low<.15 and high>.85,"Magnified replacement texels retain their own sharp light/dark details instead of snapping to the source grid")
	# Some imported faces use a constant UV as a paint swatch. A nearly-zero
	# footprint must not amplify interpolation roundoff into flashing colour.
	node.mesh=mesh_for(0.0)
	var constant_error := 0.0
	# Forward+ filters sRGB texels in linear space; Compatibility blends the
	# stored values. The stationary half-texel sample is stable in both.
	var constant_value := .5
	if RenderingServer.get_current_rendering_method()!="gl_compatibility":
		constant_value=Color(.1,.1,.1).srgb_to_linear().lerp(Color(.9,.9,.9).srgb_to_linear(),.5).linear_to_srgb().r
	for frame in 4:
		camera.position.x=frame*.17*2.0/64.0
		for settle in 3:await process_frame
		await RenderingServer.frame_post_draw
		var swatch := viewport.get_texture().get_image()
		for y in range(20,44):
			for x in range(20,44):constant_error=maxf(constant_error,absf(swatch.get_pixel(x,y).r-constant_value))
	expect(constant_error<.035,"Constant-UV paint samples remain stable on enlarged atlases (error %f)"%constant_error)
	# Removing the mod restores the original texel convention without
	# rebuilding the material. No smooth blend with the next source texel.
	original.fill(Color(.1,.1,.1))
	for y in 128:original.set_pixel(9,y,Color(.9,.9,.9))
	original.save_png(DIRECTORY.path_join("data/textures/sample.bmp.png"))
	DirAccess.remove_absolute(Mods.only_root.path_join("textures/sample.png"));library.reload_textures()
	node.mesh=mesh_for(1.0);camera.position.x=0
	for settle in 3:await process_frame
	await RenderingServer.frame_post_draw
	var native := viewport.get_texture().get_image()
	for x in range(4,60):expect(native.get_pixel(x,32).r<.15,"Original pixels retain their exact sampling convention after removing the mod")
	viewport.queue_free();await process_frame;cleanup.remove_tree(DIRECTORY);Mods.only_root=""
	print("TEXTURE_FILTERING ",failures," failures; minification error=",worst,"; constant-UV error=",constant_error);quit(1 if failures else 0)
