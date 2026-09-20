extends RefCounted
## Player-supplied replacements for the imported art. Nothing here ships with
## the game: a `mods` folder next to the executable, or `mods` in the user
## data folder, may hold `textures/<atlas>.png` in place of an imported atlas
## and `models/<name>.glb` (or .gltf) in place of an imported model. A texture
## may be any size: the imported art addresses it in the original's texels, so
## a sharper atlas is simply drawn at more pixels per texel. A model is scaled
## and centred onto the imported model's own extent, so it stands where the
## original stood, and if it carries animations the first one loops. The
## simulation still uses the imported geometry for collision, aim and camera.
static var templates: Dictionary = {}
static var missing: Dictionary = {}
## Set by the engine checks, so a test never reads a player's real mods.
static var only_root := ""

static func roots() -> Array[String]:
	if not only_root.is_empty(): return [only_root]
	var found: Array[String] = ["user://mods"]
	if not OS.has_feature("web") and not OS.has_feature("android"):
		var beside := OS.get_executable_path().get_base_dir().path_join("mods")
		if OS.has_feature("macos"): beside=OS.get_executable_path().get_base_dir().path_join("../../../mods").simplify_path()
		found.append(beside)
	return found

static func find(relative: String) -> String:
	for root in roots():
		var path := root.path_join(relative)
		if FileAccess.file_exists(path): return path
	return ""

static func texture_path(resource: String) -> String:
	# data/textures/deep.bmp -> textures/deep.png
	return find("textures/"+resource.get_file().get_basename()+".png")

static func model_path(resource: String) -> String:
	# data/v3d/u0.mbac -> models/u0.glb, or models/u0.gltf
	var stem := resource.get_file().get_basename()
	var path := find("models/"+stem+".glb")
	return path if not path.is_empty() else find("models/"+stem+".gltf")

static func has_model(resource: String) -> bool:
	if missing.get(resource,false): return false
	return templates.has(resource) or not model_path(resource).is_empty()

static func template(resource: String) -> Node3D:
	if templates.has(resource): return templates[resource]
	var path := model_path(resource)
	if path.is_empty(): missing[resource]=true; return null
	var document := GLTFDocument.new(); var state := GLTFState.new()
	if document.append_from_file(path,state)!=OK:
		push_warning("Could not read replacement model: "+path); missing[resource]=true; return null
	var scene := document.generate_scene(state)
	if scene==null: missing[resource]=true; return null
	templates[resource]=scene
	return scene

static func instance_model(resource: String, bounds: AABB) -> Node3D:
	var source := template(resource)
	if source==null: return null
	var node := source.duplicate() as Node3D
	fit(node,bounds)
	for player in node.find_children("*","AnimationPlayer",true,false):
		var names: PackedStringArray = player.get_animation_list()
		if names.is_empty(): continue
		player.get_animation(names[0]).loop_mode=Animation.LOOP_LINEAR
		player.play(names[0])
		break
	return node

static func mesh_bounds(node: Node3D) -> AABB:
	"""The extent of every mesh under node, in node's own space."""
	var result := AABB(); var first := true
	var inverse := node.global_transform.affine_inverse() if node.is_inside_tree() else node.transform.affine_inverse()
	for mesh in node.find_children("*","MeshInstance3D",true,false):
		if mesh.mesh==null: continue
		var local: Transform3D = mesh.transform
		var parent: Node = mesh.get_parent()
		while parent!=null and parent!=node:
			if parent is Node3D: local=parent.transform*local
			parent=parent.get_parent()
		var box: AABB = local*mesh.mesh.get_aabb()
		result=box if first else result.merge(box); first=false
	return result

static func fit(node: Node3D, bounds: AABB) -> void:
	"""Scale uniformly so the longest extents agree, then centre on the
	imported model's centre. Orientation is the modeller's: face the same
	way the imported model does in the content inspector."""
	var box := mesh_bounds(node)
	if box.size.length_squared()<0.000001 or bounds.size.length_squared()<0.000001: return
	var scale := bounds.get_longest_axis_size()/box.get_longest_axis_size()
	node.scale=Vector3.ONE*scale
	node.position=bounds.get_center()-box.get_center()*scale
