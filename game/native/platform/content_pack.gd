extends RefCounted
## Private data transfer, never a resource PCK mount. No imported script execution.
const Content = preload("res://native/content.gd")
const LIMIT := 128*1024*1024
const FILE_LIMIT := 32*1024*1024
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
func install(path: String, base: String="user://content") -> String:
	failure="Invalid or unsupported content pack. Prepare a new .abyss file on your desktop."
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
	var stage:=base.path_join("incoming-"+str(Time.get_ticks_usec()))
	if DirAccess.make_dir_recursive_absolute(stage)!=OK:zip.close();failure="Cannot create local content storage.";return ""
	var valid:=true
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
	zip.close()
	var content:=Content.new()
	# The pack must describe the same JAR its converted data records.
	if valid:valid=content.load_cache(stage) and content.profile==manifest.profile
	if not valid:remove_tree(stage);return ""
	if DirAccess.dir_exists_absolute(destination):
		var existing_valid:=true
		for name: String in manifest.files:
			var target:=destination.path_join(name)
			if not FileAccess.file_exists(target) or FileAccess.get_sha256(target)!=manifest.files[name].sha256:existing_valid=false;break
		if existing_valid and content.load_cache(destination):remove_tree(stage);failure="";return destination
	# A new unique destination makes replacement non-destructive even if an old pack is corrupt.
	if DirAccess.dir_exists_absolute(destination):destination+="-"+str(Time.get_ticks_usec())
	if DirAccess.rename_absolute(stage,destination)!=OK:remove_tree(stage);failure="Cannot activate local content.";return ""
	failure="";return destination
func remove_tree(path: String) -> void:
	var directory:=DirAccess.open(path)
	if directory==null:return
	for name in directory.get_files():directory.remove(name)
	for name in directory.get_directories():remove_tree(path.path_join(name))
	DirAccess.remove_absolute(path)
