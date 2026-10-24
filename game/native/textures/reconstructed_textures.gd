extends RefCounted
## Private, versioned reconstruction cache. The imported originals and player
## mods are never overwritten. A completion manifest is published only after
## all three images have been saved and verified.
const Renderer = preload("res://native/textures/recipe_renderer.gd")
const RECIPE := "res://native/textures/reconstruction_recipe.json"
const REVISION := "vector-1-godot-1"
const OFFER_VERSION := 1
const FILES := ["deep","fx","deep.normal"]
static var cache_base := "user://native/reconstructed"
static var active := {}
signal progress(value: float, stage: String)
var renderer
var failure := ""
var cancelled := false
var worker: Thread
var progress_lock := Mutex.new()
var latest_progress: Array=[]

static func enabled(settings: ConfigFile) -> bool:
	return settings.get_value("graphics","reconstructed_textures",false)==true

static func inspect(content_root: String) -> Dictionary:
	var sources := {};var hashes := []
	for kind in ["deep","fx"]:
		var path := content_root.path_join("data/textures/"+kind+".bmp.png")
		if not FileAccess.file_exists(path):return {}
		var source := Image.load_from_file(path)
		if source==null or source.get_size()!=Vector2i(128,128):return {}
		source.convert(Image.FORMAT_RGBA8);sources[kind]=source
		hashes.append(FileAccess.get_sha256(path))
	var data: Variant=JSON.parse_string(FileAccess.get_file_as_string(content_root.path_join("native-data.json"))) if FileAccess.file_exists(content_root.path_join("native-data.json")) else {}
	var profile := str(data.get("jar_sha256",content_root.simplify_path().sha256_text())) if data is Dictionary else content_root.simplify_path().sha256_text()
	var id := profile.sha256_text()
	var fingerprint := (REVISION+FileAccess.get_sha256(RECIPE)+JSON.stringify(hashes)).sha256_text()
	return {"id":id,"root":content_root,"sources":sources,"fingerprint":fingerprint,
		"directory":cache_base.path_join(id).path_join(fingerprint)}

static func ready(info: Dictionary) -> bool:
	if info.is_empty():return false
	var manifest := str(info.directory).path_join("complete.json")
	if not FileAccess.file_exists(manifest):return false
	var record: Variant=JSON.parse_string(FileAccess.get_file_as_string(manifest))
	if record is not Dictionary or record.get("fingerprint","")!=info.fingerprint or record.get("files") is not Dictionary:return false
	for kind in FILES:
		var path := str(info.directory).path_join(kind+".png")
		if not FileAccess.file_exists(path) or record.files.get(kind,"")!=FileAccess.get_sha256(path):return false
		var image := Image.load_from_file(path)
		if image==null or image.get_size()!=Vector2i(Renderer.SIDE,Renderer.SIDE):return false
	return true

static func restore(content_root: String, config: ConfigFile) -> Dictionary:
	active.erase(content_root)
	var info := inspect(content_root)
	if enabled(config) and ready(info):active[content_root]=info.directory
	return info

static func offered(config: ConfigFile, info: Dictionary) -> bool:
	return info.is_empty() or config.get_value("texture_reconstruction",info.id,0)==OFFER_VERSION

static func save_choice(settings_path: String, info: Dictionary, value: bool) -> Error:
	var config := ConfigFile.new();config.load(settings_path)
	config.set_value("graphics","reconstructed_textures",value)
	if not info.is_empty():config.set_value("texture_reconstruction",info.id,OFFER_VERSION)
	var err := DirAccess.make_dir_recursive_absolute(settings_path.get_base_dir())
	if err!=OK:return err
	err=config.save(settings_path)
	if err==OK and not info.is_empty():
		if value:active[info.root]=info.directory
		else:active.erase(info.root)
	return err

static func texture_path(content_root: String, resource: String, normal := false) -> String:
	if not active.has(content_root):return ""
	var kind := resource.get_file().get_basename()+(".normal" if normal else "")
	if kind not in FILES:return ""
	var path := str(active[content_root]).path_join(kind+".png")
	return path if FileAccess.file_exists(path) else ""

func cancel() -> void:
	cancelled=true
	if renderer!=null:renderer.cancelled=true

func renderer_progress(value: float, stage: String) -> void:
	progress_lock.lock();latest_progress=[value*.95,stage];progress_lock.unlock()

func report_progress() -> void:
	progress_lock.lock();var latest := latest_progress;latest_progress=[];progress_lock.unlock()
	if not latest.is_empty():progress.emit(latest[0],latest[1])

func render_worker(sources: Dictionary, recipe: Dictionary) -> Dictionary:
	return await renderer.render(sources,recipe,null)

func shutdown() -> void:
	cancel()
	if worker!=null and worker.is_started():worker.wait_to_finish()
	worker=null

static func clear_partial(directory: String) -> void:
	# Only files this generator owns, under its own staging directory.
	for name in FILES+["complete"]:
		var path := directory.path_join(name+(".json" if name=="complete" else ".png"))
		if FileAccess.file_exists(path):DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(directory)

func generate(info: Dictionary, tree: SceneTree) -> bool:
	failure="";cancelled=false
	if info.is_empty():failure="source";return false
	if ready(info):return true
	progress.emit(0,"prepare");await tree.process_frame;await tree.process_frame
	if cancelled:return false
	var recipe: Variant=JSON.parse_string(FileAccess.get_file_as_string(RECIPE))
	if recipe is not Dictionary or recipe.get("format")!="shaded-vector-recipe" or recipe.get("version")!=1:failure="recipe";return false
	renderer=Renderer.new();renderer.progress.connect(renderer_progress)
	var results := {}
	# Native builds use a worker, leaving the game/UI thread entirely free.
	# Single-threaded Web exports use the same renderer's bounded scanline slices.
	if not OS.has_feature("web"):
		worker=Thread.new();renderer.threaded=true
		if worker.start(render_worker.bind(info.sources,recipe))!=OK:worker=null;renderer.threaded=false
	if worker!=null:
		while worker!=null and worker.is_alive():report_progress();await tree.process_frame
		if worker!=null:results=worker.wait_to_finish();worker=null
	else:
		renderer.progress.disconnect(renderer_progress)
		renderer.progress.connect(func(value,stage):progress.emit(value*.95,stage))
		results=await renderer.render(info.sources,recipe,tree)
	if renderer.progress.is_connected(renderer_progress):renderer.progress.disconnect(renderer_progress)
	report_progress();renderer=null
	if cancelled or results.size()!=FILES.size():return false
	progress.emit(.96,"save");await tree.process_frame
	var directory := str(info.directory)
	# Like content-pack installation, Web stages outside IDBFS. Moving a
	# persistent directory during a sync invalidates the browser's file list.
	var staging := "/tmp/abyssal-reconstruction-"+str(Time.get_ticks_usec()) if OS.has_feature("web") else directory+".partial"
	if DirAccess.dir_exists_absolute(staging):clear_partial(staging)
	if DirAccess.make_dir_recursive_absolute(staging)!=OK:failure="write";return false
	var hashes := {}
	for kind in FILES:
		if cancelled:clear_partial(staging);return false
		var path := staging.path_join(kind+".png")
		if results[kind].save_png(path)!=OK:failure="write";clear_partial(staging);return false
		hashes[kind]=FileAccess.get_sha256(path)
		await tree.process_frame
	results.clear();renderer=null;recipe=null
	if cancelled:clear_partial(staging);return false
	var file := FileAccess.open(staging.path_join("complete.json"),FileAccess.WRITE)
	if file==null:failure="write";clear_partial(staging);return false
	file.store_string(JSON.stringify({"fingerprint":info.fingerprint,"revision":REVISION,"files":hashes}));file.close()
	var check := info.duplicate();check.directory=staging
	if not ready(check):failure="write";clear_partial(staging);return false
	if OS.has_feature("web"):
		# Immutable final names first, completion manifest last. Never rename or
		# delete paths that an IndexedDB transaction may already be reading.
		if DirAccess.make_dir_recursive_absolute(directory)!=OK:failure="write";clear_partial(staging);return false
		for name in FILES+["complete"]:
			if cancelled:clear_partial(staging);return false
			var filename: String=name+(".json" if name=="complete" else ".png")
			if DirAccess.copy_absolute(staging.path_join(filename),directory.path_join(filename))!=OK:failure="write";clear_partial(staging);return false
			await tree.process_frame
		clear_partial(staging)
	else:
		# A damaged cache is replaced only after the new generation is complete.
		if DirAccess.dir_exists_absolute(directory):clear_partial(directory)
		if DirAccess.rename_absolute(staging,directory)!=OK:failure="write";clear_partial(staging);return false
	progress.emit(1,"done");return true
