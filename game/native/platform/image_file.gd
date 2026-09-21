extends Node
## The Mods page's way in and out for a PNG: the desktop's own file
## dialogs, Android's document picker through the importer plugin, and in
## the browser a file input and a download. Nothing leaves the machine.
signal chosen(path: String)
signal failed(message: String)
signal delivered(message: String)
var open_dialog := FileDialog.new()
var save_dialog := FileDialog.new()
var android: Object
var callback: JavaScriptObject
## What the save dialog is to write, once the player names the place.
var pending := ""

func _ready() -> void:
	if OS.has_feature("android") and Engine.has_singleton("AbyssalImporter"):
		var plugin: Object=Engine.get_singleton("AbyssalImporter")
		if plugin.has_signal("image_selected"):
			android=plugin
			android.connect("image_selected",func(path):chosen.emit(path))
			android.connect("image_failed",func(message):failed.emit(message))
			android.connect("file_exported",func(message):delivered.emit(message))
	elif OS.has_feature("web"):
		callback=JavaScriptBridge.create_callback(received)
		JavaScriptBridge.eval("""
window.abyssalImages = {
 choose:function(callback) {
  const input=document.createElement('input');input.type='file';input.accept='.png,image/png';
  input.onchange=async()=>{
   const file=input.files[0];if(!file)return;
   if(file.size>67108864){callback('error','That image is larger than 64 MiB.');return;}
   try { callback('complete',await file.arrayBuffer()); }
   catch(error){callback('error',String(error.message||error));}
  };input.click();
 }
};
""",true)
	else:
		for dialog in [open_dialog,save_dialog]:
			add_child(dialog);dialog.access=FileDialog.ACCESS_FILESYSTEM;dialog.use_native_dialog=true
			dialog.filters=PackedStringArray(["*.png ; PNG image ; image/png"])
		open_dialog.file_mode=FileDialog.FILE_MODE_OPEN_FILE
		save_dialog.file_mode=FileDialog.FILE_MODE_SAVE_FILE
		open_dialog.file_selected.connect(func(path):chosen.emit(path))
		save_dialog.file_selected.connect(write_pending)

func available() -> bool:
	return android!=null or OS.has_feature("web") or not OS.has_feature("android")

func choose() -> void:
	if android!=null:android.choose_image()
	elif OS.has_feature("web"):JavaScriptBridge.get_interface("abyssalImages").choose(callback)
	elif available():open_dialog.popup_centered_ratio(.8)
	else:failed.emit("No file picker is available on this device.")

func export_png(name: String, source: String) -> void:
	"""Hands the player a copy of a PNG the game holds, by whatever the
	platform offers for saving a file."""
	if not FileAccess.file_exists(source):failed.emit("There is nothing to copy yet.");return
	if android!=null:android.export_file(name,"image/png",ProjectSettings.globalize_path(source))
	elif OS.has_feature("web"):
		JavaScriptBridge.download_buffer(FileAccess.get_file_as_bytes(source),name,"image/png")
		delivered.emit("Your browser is downloading "+name+".")
	elif available():
		pending=source;save_dialog.current_file=name;save_dialog.popup_centered_ratio(.8)
	else:failed.emit("No file picker is available on this device.")

func write_pending(path: String) -> void:
	var source := pending;pending=""
	if source.is_empty():return
	if DirAccess.copy_absolute(source,path)==OK:delivered.emit("Copied to "+path.get_file()+".")
	else:failed.emit("Could not write "+path.get_file()+".")

func received(args: Array) -> void:
	if args.size()<2:return
	if str(args[0])!="complete":failed.emit(str(args[1]));return
	var bytes:=JavaScriptBridge.js_buffer_to_packed_byte_array(args[1])
	var path:="user://chosen-texture.png"
	var file:=FileAccess.open(path,FileAccess.WRITE)
	if file==null:failed.emit("Browser storage is unavailable.");return
	file.store_buffer(bytes);var result:=file.get_error();file.close()
	if result!=OK:DirAccess.remove_absolute(path);failed.emit("Browser storage is full.");return
	chosen.emit(path)
