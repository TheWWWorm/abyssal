extends Node
## The Mods page's way in for a PNG: the desktop's own file dialog,
## Android's document picker through the importer plugin, and in the
## browser a file input. Nothing leaves the machine.
signal chosen(path: String)
signal failed(message: String)
var open_dialog := FileDialog.new()
var android: Object
var callback: JavaScriptObject

func _ready() -> void:
	if OS.has_feature("android") and Engine.has_singleton("AbyssalImporter"):
		var plugin: Object=Engine.get_singleton("AbyssalImporter")
		if plugin.has_signal("image_selected"):
			android=plugin
			android.connect("image_selected",func(path):chosen.emit(path))
			android.connect("image_failed",func(message):failed.emit(message))
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
		add_child(open_dialog);open_dialog.access=FileDialog.ACCESS_FILESYSTEM;open_dialog.use_native_dialog=true
		open_dialog.filters=PackedStringArray(["*.png ; PNG image ; image/png"])
		open_dialog.file_mode=FileDialog.FILE_MODE_OPEN_FILE
		open_dialog.file_selected.connect(func(path):chosen.emit(path))

func available() -> bool:
	return android!=null or OS.has_feature("web") or not OS.has_feature("android")

func choose() -> void:
	if android!=null:android.choose_image()
	elif OS.has_feature("web"):JavaScriptBridge.get_interface("abyssalImages").choose(callback)
	elif available():open_dialog.popup_centered_ratio(.8)
	else:failed.emit("No file picker is available on this device.")

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
