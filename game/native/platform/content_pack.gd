extends RefCounted
## Private data transfer, never a resource PCK mount. No imported script execution.
const Content = preload("res://native/content.gd")
const LIMIT := 128*1024*1024
const FILE_LIMIT := 32*1024*1024
signal progress(done: int, total: int)
var failure := ""
func safe_name(name: String) -> bool:
	if name.is_empty() or name.contains("\\") or name.contains(":") or name.begins_with("/"):return false
	for character in name:
		if not "abcdefghijklmnopqrstuvwxyz0123456789_./-".contains(character):return false
	for part in name.split("/"):
		if part in ["",".",".."]:return false
	if name in ["pack.json","native-data.json","resource_registry.json","bindings.json"]:return true
	return name.begins_with("data/") and name.get_extension().to_lower() not in ["gd","gdc","tscn","tres","pck","class","jar","exe","dll","so","py","js"]
func preflight(bytes: PackedByteArray) -> Dictionary:
	# Bound decompression before ZIPReader allocates. Our format excludes ZIP64/comments.
	var sizes: Dictionary={}
	var end:=bytes.size()-22
	if end<0 or bytes.size()>LIMIT or bytes.decode_u32(end)!=0x06054b50:return {}
	if bytes.decode_u16(end+4)!=0 or bytes.decode_u16(end+6)!=0 or bytes.decode_u16(end+20)!=0:return {}
	var count:=bytes.decode_u16(end+10)
	if count<4 or count>4096 or bytes.decode_u16(end+8)!=count:return {}
	var offset:=bytes.decode_u32(end+16)
	if offset+bytes.decode_u32(end+12)!=end:return {}
	var total:=0
	for i in count:
		if offset+46>end or bytes.decode_u32(offset)!=0x02014b50:return {}
		var flags:=bytes.decode_u16(offset+8);var method:=bytes.decode_u16(offset+10)
		var expanded:=bytes.decode_u32(offset+24)
		var length:=bytes.decode_u16(offset+28);var extra:=bytes.decode_u16(offset+30);var comment:=bytes.decode_u16(offset+32)
		if flags&1 or method not in [0,8] or expanded>FILE_LIMIT or offset+46+length+extra+comment>end:return {}
		var name:=bytes.slice(offset+46,offset+46+length).get_string_from_utf8()
		if not safe_name(name) or sizes.has(name):return {}
		sizes[name]=expanded;total+=expanded
		if total>LIMIT:return {}
		offset+=46+length+extra+comment
	if offset!=end:return {}
	return sizes
func install(path: String, base: String="user://content", tree: SceneTree=null) -> String:
	failure=tr("Invalid or unsupported content pack. Prepare a new .abyss file on your desktop.")
	var file:=FileAccess.open(path,FileAccess.READ)
	if file==null or file.get_length()>LIMIT:return ""
	var bytes:=file.get_buffer(file.get_length());file.close()
	var sizes:=preflight(bytes)
	if sizes.is_empty():return ""
	var zip:=ZIPReader.new()
	if zip.open(path)!=OK:return ""
	var manifest_bytes:=zip.read_file("pack.json")
	var manifest=JSON.parse_string(manifest_bytes.get_string_from_utf8())
	if manifest is not Dictionary or manifest.get("format")!="abyssal-content-1" or not Content.is_digest(manifest.get("profile")) or manifest.get("files") is not Dictionary:zip.close();return ""
	if manifest.files.size()!=sizes.size()-1:zip.close();return ""
	var digest:=HashingContext.new();digest.start(HashingContext.HASH_SHA256);digest.update(manifest_bytes)
	var destination:=base.path_join(digest.finish().hex_encode())
	# IDBFS can be synchronizing between batches. Keep unpacking outside its
	# mount: renaming a persistent staging tree during sync invalidates the
	# file list being saved and can leave the next startup with a partial cache.
	var stage:=("/tmp/abyssal-incoming-" if OS.has_feature("web") else base.path_join("incoming-"))+str(Time.get_ticks_usec())
	if DirAccess.make_dir_recursive_absolute(stage)!=OK:zip.close();failure=tr("Cannot create local content storage.");return ""
	var valid:=true
	var done:=0
	var total_work: int=manifest.files.size()*(2 if OS.has_feature("web") else 1)
	var frame_started:=Time.get_ticks_usec()
	for name: String in manifest.files:
		var record=manifest.files[name]
		if not safe_name(name) or name=="pack.json" or not sizes.has(name) or record is not Dictionary or record.get("size",-1)!=sizes[name]:valid=false;break
		var payload:=zip.read_file(name)
		digest.start(HashingContext.HASH_SHA256);digest.update(payload)
		if payload.size()!=sizes[name] or digest.finish().hex_encode()!=record.get("sha256",""):valid=false;break
		var target:=stage.path_join(name)
		if DirAccess.make_dir_recursive_absolute(target.get_base_dir())!=OK:valid=false;break
		var output:=FileAccess.open(target,FileAccess.WRITE)
		if output==null:valid=false;break
		output.store_buffer(payload);output.flush()
		if output.get_error()!=OK:valid=false
		output.close()
		if not valid:break
		done+=1
		if tree!=null and (done%16==0 or Time.get_ticks_usec()-frame_started>=6000):
			progress.emit(done,total_work)
			await tree.process_frame
			frame_started=Time.get_ticks_usec()
	zip.close()
	var content:=Content.new()
	# The pack must describe the same JAR its converted data records.
	if valid:valid=content.load_cache(stage) and content.profile==manifest.profile
	if not valid:remove_tree(stage);return ""
	# Keep the inventory with the cache. Reopening can detect an incomplete or
	# damaged browser restore before any of its resources reach the renderer.
	var inventory:=FileAccess.open(stage.path_join("pack.json"),FileAccess.WRITE)
	if inventory==null:remove_tree(stage);failure=tr("Cannot create local content storage.");return ""
	inventory.store_buffer(manifest_bytes);inventory.flush()
	valid=inventory.get_error()==OK;inventory.close()
	if not valid:remove_tree(stage);failure=tr("Cannot create local content storage.");return ""
	if DirAccess.dir_exists_absolute(destination):
		var existing_valid:=true
		done=0
		for name: String in manifest.files:
			var target:=destination.path_join(name)
			if not FileAccess.file_exists(target) or FileAccess.get_sha256(target)!=manifest.files[name].sha256:existing_valid=false;break
			done+=1
			if tree!=null and done%16==0:await tree.process_frame
		if existing_valid and content.load_cache(destination):
			# A reimport also repairs the inventory itself and upgrades a legacy
			# cache, even when every game resource already matches.
			if DirAccess.copy_absolute(stage.path_join("pack.json"),destination.path_join("pack.json"))!=OK:
				remove_tree(stage);failure=tr("Cannot activate local content.");return ""
			remove_tree(stage);failure="";return destination
	# A new unique destination makes replacement non-destructive even if an old pack is corrupt.
	if DirAccess.dir_exists_absolute(destination):destination+="-"+str(Time.get_ticks_usec())
	if OS.has_feature("web"):
		# Copy immutable files into their final names, then the inventory. No
		# persistent path moves while a browser transaction is reading it.
		done=manifest.files.size()
		for name: String in manifest.files.keys()+["pack.json"]:
			var target:=destination.path_join(name)
			if DirAccess.make_dir_recursive_absolute(target.get_base_dir())!=OK or DirAccess.copy_absolute(stage.path_join(name),target)!=OK:
				remove_tree(stage);failure=tr("Cannot activate local content.");return ""
			done+=1
			if tree!=null and (done%16==0 or Time.get_ticks_usec()-frame_started>=6000):
				progress.emit(mini(done,total_work),total_work)
				await tree.process_frame
				frame_started=Time.get_ticks_usec()
		remove_tree(stage)
	elif DirAccess.rename_absolute(stage,destination)!=OK:remove_tree(stage);failure=tr("Cannot activate local content.");return ""
	failure="";return destination

func verify(directory: String, tree: SceneTree=null) -> bool:
	"""Older caches have no inventory and retain the original structural check.
	New installs verify every payload before resuming after a browser restart."""
	failure=tr("The content cache is incomplete. Reimport your JAR.")
	var path:=directory.path_join("pack.json")
	if not FileAccess.file_exists(path):return await verify_legacy(directory,tree)
	var file:=FileAccess.open(path,FileAccess.READ)
	if file==null or file.get_length()>FILE_LIMIT:return false
	var manifest=JSON.parse_string(file.get_as_text());file.close()
	if manifest is not Dictionary or manifest.get("format")!="abyssal-content-1" or not Content.is_digest(manifest.get("profile")) or manifest.get("files") is not Dictionary:return false
	if not manifest.files.has_all(["native-data.json","resource_registry.json","bindings.json"]) or manifest.files.size()>4095:return false
	var done:=0;var total:=0;var frame_started:=Time.get_ticks_usec()
	for name in manifest.files:
		var record=manifest.files[name]
		if not safe_name(name) or name=="pack.json" or record is not Dictionary or not Content.is_digest(record.get("sha256")):return false
		var size:=int(record.get("size",-1))
		total+=size
		if size<0 or size>FILE_LIMIT or total>LIMIT:return false
		var payload:=FileAccess.open(directory.path_join(name),FileAccess.READ)
		if payload==null or payload.get_length()!=size:return false
		payload.close()
		if FileAccess.get_sha256(directory.path_join(name))!=record.sha256:return false
		done+=1
		if tree!=null and (done%16==0 or Time.get_ticks_usec()-frame_started>=6000):
			progress.emit(done,manifest.files.size())
			await tree.process_frame
			frame_started=Time.get_ticks_usec()
	failure="";return true

func verify_legacy(directory: String, tree: SceneTree) -> bool:
	var content:=Content.new()
	if not content.load_cache(directory):failure=content.failure;return false
	var paths: Dictionary={"bindings.json":true}
	for record in content.registry:
		paths[str(record.model)+".json"]=true
		for texture: String in record.textures:paths[texture+".png" if texture.ends_with(".bmp") else texture]=true
	var done:=0
	for name: String in paths:
		var file:=FileAccess.open(directory.path_join(name),FileAccess.READ)
		if file==null or file.get_length()==0:return false
		file.close();done+=1
		if tree!=null and done%16==0:
			progress.emit(done,paths.size());await tree.process_frame
	failure="";return true

func discard_incomplete(base: String="user://content") -> void:
	# An interrupted install never becomes the active cache. Its staging files
	# can be discarded without touching completed imports or campaign saves.
	if not DirAccess.dir_exists_absolute(base):return
	for name in DirAccess.get_directories_at(base):
		if name.begins_with("incoming-"):remove_tree(base.path_join(name))

func remove_tree(path: String) -> void:
	var directory:=DirAccess.open(path)
	if directory==null:return
	for name in directory.get_files():directory.remove(name)
	for name in directory.get_directories():remove_tree(path.path_join(name))
	DirAccess.remove_absolute(path)
