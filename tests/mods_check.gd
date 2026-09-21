extends SceneTree
## Player-supplied art: an atlas of any size stands in for an imported one and
## is still addressed in the original's texels; a glTF stands in for a model,
## fitted onto the imported model's own extent; without a mods folder nothing
## changes. Runs headless: nothing here needs a frame drawn.
var failures := 0
func expect(ok: bool, why: String) -> void:
	if not ok: failures+=1; push_error(why)
func _initialize(): call_deferred("run")
func run():
	var args := OS.get_cmdline_user_args()
	var content=load("res://native/content.gd").new()
	if not content.load_cache(args[0]): quit(1); return
	var Mods=load("res://native/presentation/mods.gd")
	var folder := "user://mods-check"
	Mods.only_root=folder;Mods.templates.clear();Mods.missing.clear()
	for sub in ["textures","models"]: DirAccess.make_dir_recursive_absolute(folder.path_join(sub))
	var Library=load("res://scripts/model_library.gd")
	var plain=Library.new();plain.root=content.root
	var atlas: Texture2D=plain.texture("data/textures/deep.bmp")
	var original: Vector2=Vector2(atlas.get_width(),atlas.get_height())
	expect(not Mods.has_model("data/v3d/u0.mbac") and Mods.texture_path("data/textures/deep.bmp").is_empty(),"No mods folder content means no replacements")
	expect(plain.texture_size("data/textures/deep.bmp")==original,"Without a replacement the atlas is drawn at its own size")
	# A doubled atlas.
	var doubled := Image.create(int(original.x)*2,int(original.y)*2,false,Image.FORMAT_RGBA8);doubled.fill(Color(1,0,1,1))
	expect(doubled.save_png(ProjectSettings.globalize_path(folder.path_join("textures/deep.png")))==OK,"Test atlas written")
	var modded=Library.new();modded.root=content.root
	var drawn: Texture2D=modded.texture("data/textures/deep.bmp")
	expect(drawn.get_width()==int(original.x)*2 and drawn.get_height()==int(original.y)*2,"A replacement atlas is drawn at its own, larger size")
	expect(modded.texture_size("data/textures/deep.bmp")==original,"Geometry keeps addressing the replacement atlas in the original's texels")
	var material: ShaderMaterial=modded.affine_material("data/textures/deep.bmp",0,false,true,false)
	expect(material.get_shader_parameter("texture_size")==original,"Materials receive the original texel count, not the replacement's pixel count")
	expect(modded.texture("data/textures/deep.bmp",true).get_width()==int(original.x)*2,"The cut-out variant uses the replacement's own alpha")
	# A cut-out replacement of its own, at yet another size, serves the cut-out
	# variant alone; the opaque one keeps the opaque replacement.
	var mask := Image.create(int(original.x)*4,int(original.y)*4,false,Image.FORMAT_RGBA8);mask.fill(Color(0,1,1,.5))
	expect(mask.save_png(ProjectSettings.globalize_path(folder.path_join("textures/deep.alpha.png")))==OK,"Test mask written")
	var masked=Library.new();masked.root=content.root
	expect(masked.texture("data/textures/deep.bmp",true).get_width()==int(original.x)*4 and masked.texture("data/textures/deep.bmp").get_width()==int(original.x)*2,"A deep.alpha.png of its own stands for the cut-out variant only")
	expect(Mods.texture_status(content.root,Mods.ATLASES[0],true).own and not Mods.texture_status(content.root,Mods.ATLASES[0],false).own,"The status tells a cut-out replacement of its own from a shared one")
	expect(Mods.remove_texture("deep",true) and Mods.texture_path("data/textures/deep.bmp",true).ends_with("deep.png"),"Removing the cut-out replacement leaves the opaque one serving both")
	# The Mods page: a library already drawing takes a replacement up on
	# reload, reports it, and gives the original back when it is removed.
	plain.reload_textures()
	expect(atlas.get_width()==int(original.x)*2,"Reloading textures swaps the replacement into the texture the materials hold")
	var status: Dictionary=Mods.texture_status(content.root,Mods.ATLASES[0])
	expect(status.replaced and status.size==Vector2i(int(original.x)*2,int(original.y)*2) and status.image!=null,"The atlas status reports the replacement and its size")
	expect(Mods.remove_texture("deep") and Mods.texture_path("data/textures/deep.bmp").is_empty(),"Restoring the original removes the replacement file")
	plain.reload_textures()
	expect(atlas.get_width()==int(original.x),"After the restore the texture is the original again")
	expect(not Mods.texture_status(content.root,Mods.ATLASES[0]).replaced,"The status reports the original")
	expect(Mods.install_texture("skybox",ProjectSettings.globalize_path(folder.path_join("nothing.png")))!="","Installing what is not an image is refused")
	var sample := Image.create(16,16,false,Image.FORMAT_RGBA8);sample.fill(Color(0,1,0,1))
	expect(sample.save_png(ProjectSettings.globalize_path(folder.path_join("sample.png")))==OK,"Sample written")
	expect(Mods.install_texture("skybox",ProjectSettings.globalize_path(folder.path_join("sample.png")))=="" and FileAccess.file_exists(Mods.user_texture_path("skybox")),"Installing a PNG places it in the user mods folder")
	DirAccess.remove_absolute(Mods.user_texture_path("skybox"))
	# A glTF hull: a box, off-centre and twice too long, with a looping animation.
	var scene := Node3D.new();scene.name="Hull"
	var body := MeshInstance3D.new();var box := BoxMesh.new();box.size=Vector3(2,1,8);body.mesh=box;body.position=Vector3(5,0,0);body.name="Body";scene.add_child(body)
	var player := AnimationPlayer.new();scene.add_child(player)
	var animation := Animation.new();animation.length=1.0;var track := animation.add_track(Animation.TYPE_VALUE);animation.track_set_path(track,"Body:position");animation.track_insert_key(track,0.0,Vector3(5,0,0));animation.track_insert_key(track,1.0,Vector3(5,1,0))
	var clips := AnimationLibrary.new();clips.add_animation("bob",animation);player.add_animation_library("",clips)
	root.add_child(scene)
	var document := GLTFDocument.new();var state := GLTFState.new()
	expect(document.append_from_scene(scene,state)==OK and document.write_to_filesystem(state,ProjectSettings.globalize_path(folder.path_join("models/u0.glb")))==OK,"Test glTF written")
	scene.queue_free()
	expect(Mods.has_model("data/v3d/u0.mbac") and not Mods.has_model("data/v3d/u1.mbac"),"A replacement is found by the imported model's file name")
	var bounds := AABB(Vector3(-1,-0.5,-3),Vector3(2,1,6))
	var fitted: Node3D=Mods.instance_model("data/v3d/u0.mbac",bounds)
	expect(fitted!=null,"A replacement model instances")
	if fitted!=null:
		root.add_child(fitted)
		var extent: AABB=Mods.mesh_bounds(fitted)
		var placed := AABB(fitted.transform*extent.position,extent.size*fitted.scale)
		expect(absf(placed.get_longest_axis_size()-bounds.get_longest_axis_size())<0.01,"The replacement is scaled to the imported model's longest extent")
		expect(placed.get_center().distance_to(bounds.get_center())<0.01,"The replacement is centred on the imported model")
		var players: Array=fitted.find_children("*","AnimationPlayer",true,false)
		expect(players.size()==1 and players[0].is_playing() and players[0].get_animation(players[0].current_animation).loop_mode==Animation.LOOP_LINEAR,"A replacement's first animation loops")
		fitted.queue_free()
	# Through a Model: the imported figure yields to the replacement.
	var record: Dictionary={}
	for entry in content.registry:
		if int(entry.id)==0: record=entry
	var model=load("res://native/presentation/model.gd").new();model.use_replacement_geometry=true;root.add_child(model)
	model.configure(content.root,record)
	expect(model.replacement!=null and (model.figure==null or not model.figure.visible),"A modded hull replaces the imported figure")
	expect(model.solid_bounds().size.length()>1,"Collision, aim and camera keep the imported extent")
	var compact=load("res://native/presentation/model.gd").new();compact.use_replacement_geometry=false;root.add_child(compact)
	compact.configure(content.root,record)
	expect(compact.replacement==null and compact.figure!=null,"Compact distant models keep the imported figure")
	for node in [model,compact]: node.release_mesh();node.queue_free()
	await process_frame;await process_frame
	for name in ["textures/deep.png","models/u0.glb"]: DirAccess.remove_absolute(folder.path_join(name))
	for sub in ["textures","models",""]: DirAccess.remove_absolute(folder.path_join(sub))
	for template in Mods.templates.values(): template.free()
	Mods.only_root="";Mods.templates.clear();Mods.missing.clear()
	await process_frame
	print("MODS %d failures"%failures)
	quit(1 if failures>0 else 0)
