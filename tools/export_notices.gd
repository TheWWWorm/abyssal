extends SceneTree
## Ask the actual Godot binary for its own copyright and dependency notices.
func _initialize() -> void:
 var args:=OS.get_cmdline_user_args()
 if args.is_empty():quit(1);return
 var file:=FileAccess.open(args[0],FileAccess.WRITE)
 if file==null:quit(1);return
 file.store_line(Engine.get_license_text())
 for entry in Engine.get_copyright_info():
  file.store_line("\n"+str(entry.name))
  for part in entry.parts:
   file.store_line("\n"+"\n".join(part.copyright))
   file.store_line("License: "+str(part.license))
   file.store_line("Files: "+", ".join(part.files))
 var licenses:=Engine.get_license_info()
 for name in licenses:file.store_line("\n\n"+str(name)+"\n"+str(licenses[name]))
 file.close();quit()
