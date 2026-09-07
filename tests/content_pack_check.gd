extends SceneTree
var failures:=0
func expect(ok: bool, message: String) -> void:
 if not ok:failures+=1;push_error(message)
func _initialize() -> void:call_deferred("run")
func run() -> void:
 var loader=preload("res://native/platform/content_pack.gd").new()
 var args:=OS.get_cmdline_user_args()
 var bytes:=FileAccess.get_file_as_bytes(args[0])
 var sizes: Dictionary=loader.preflight(bytes)
 expect(sizes.has("native-data.json"),"Generated pack passes bounded ZIP preflight")
 expect(loader.preflight(bytes.slice(0,bytes.size()-1)).is_empty(),"Truncated ZIP is rejected")
 for name in ["../escape","data/../../escape","/tmp/escape","data\\escape","data/foo.gd","data//foo","data/C:foo"]:expect(not loader.safe_name(name),"Reject unsafe entry "+name)
 var path: String=loader.install(args[0],"user://pack-check")
 expect(not path.is_empty(),"Private pack installs: "+loader.failure)
 var content=preload("res://native/content.gd").new()
 expect(loader.install(args[0],"user://pack-check")==path,"Reinstalling a valid pack reuses its content directory")
 expect(content.load_cache(path),"Installed pack loads into engine")
 var previous: String=content.root
 expect(not content.load_cache("user://missing-content") and content.root==previous,"Failed content load preserves active cache")
 # Corrupt one payload without changing the signed-by-hash manifest.
 var reader:=ZIPReader.new();reader.open(args[0]);var writer:=ZIPPacker.new();writer.open("user://bad.abyss")
 for name in reader.get_files():
  writer.start_file(name)
  var data:=reader.read_file(name)
  if name=="native-data.json":data[0]=0
  writer.write_file(data);writer.close_file()
 reader.close();writer.close()
 expect(loader.install("user://bad.abyss","user://pack-check").is_empty(),"Checksum mismatch never activates")
 expect(content.load_cache(previous),"Bad import leaves existing content usable")
 loader.remove_tree("user://pack-check");DirAccess.remove_absolute("user://bad.abyss")
 print("CONTENT_PACK ",failures," failures");quit(1 if failures else 0)
