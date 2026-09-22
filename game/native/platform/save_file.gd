extends Node
## Choosing and delivering expedition export files on each platform. Only the
## save record travels; nothing here reads imported game content. Browser exports
## are handed straight to the download the player started, never uploaded.
signal chosen(path: String)
signal delivered(message: String)
signal failed(message: String)
const STAGED := "user://expedition-transfer.abyssave"
const EXTENSION_NAME := "abyssave"
var open_dialog := FileDialog.new()
var save_dialog := FileDialog.new()
var callback: JavaScriptObject
var browser: JavaScriptObject
var android: Object
var pending_text := ""

func _ready() -> void:
	if OS.has_feature("android") and Engine.has_singleton("AbyssalImporter"):
		var plugin: Object = Engine.get_singleton("AbyssalImporter")
		# Older installs predate the save transfer methods; the menu hides the
		# actions rather than calling into a plugin that cannot answer. Probe the
		# signals: has_method() cannot see methods a JNISingleton registers.
		if plugin.has_signal("save_selected") and plugin.has_signal("save_exported"):
			android=plugin
			android.connect("save_selected",func(path):
				chosen.emit(path)
				DirAccess.remove_absolute(path))
			android.connect("save_exported",func(message):delivered.emit(message))
			android.connect("save_failed",func(message):failed.emit(message))
	elif OS.has_feature("web"):
		callback=JavaScriptBridge.create_callback(received)
		JavaScriptBridge.eval("""
window.abyssalSaves = {
 choose:function(callback) {
  const input=document.createElement('input');input.type='file';input.accept='.abyssave,.json';input.hidden=true;
  document.body.appendChild(input);
  input.addEventListener('cancel',()=>{input.remove();callback('cancel','');},{once:true});
  input.addEventListener('change',async()=>{
   const file=input.files[0];input.remove();
   if(!file){callback('cancel','');return;}
   if(file.size>8388608){callback('error','Choose an expedition export under 8 MiB.');return;}
   try{callback('file',new Uint8Array(await file.arrayBuffer()));}
   catch(error){callback('error','The selected export could not be read.');}
  },{once:true});
  input.click();
 },
 save:function(name,text,callback) {
  try {
   const blob=new Blob([text],{type:'application/json'});
   const url=URL.createObjectURL(blob);
   const link=document.createElement('a');link.href=url;link.download=name;link.hidden=true;
   document.body.appendChild(link);link.click();link.remove();
   setTimeout(()=>URL.revokeObjectURL(url),20000);
   callback('saved',name);
  } catch(error) { callback('error','The browser refused the download.'); }
 }
};
""",true)
		browser=JavaScriptBridge.get_interface("abyssalSaves")
	else:
		for dialog in [open_dialog,save_dialog]:
			add_child(dialog)
			dialog.access=FileDialog.ACCESS_FILESYSTEM
			dialog.use_native_dialog=true
			dialog.filters=PackedStringArray(["*.abyssave ; Abyssal expedition export"])
		open_dialog.file_mode=FileDialog.FILE_MODE_OPEN_FILE
		open_dialog.file_selected.connect(func(path):chosen.emit(path))
		save_dialog.file_mode=FileDialog.FILE_MODE_SAVE_FILE
		save_dialog.file_selected.connect(write_chosen)

func available() -> bool:
	return android!=null or OS.has_feature("web") or not OS.has_feature("android")

func choose_import() -> void:
	if android!=null: android.choose_save()
	elif OS.has_feature("web"): browser.choose(callback)
	else: open_dialog.popup_centered_ratio(.8)

func export_text(suggested_name: String, text: String) -> void:
	pending_text=text
	if android!=null: android.export_save(suggested_name,text)
	elif OS.has_feature("web"): browser.save(suggested_name,text,callback)
	else:
		save_dialog.current_file=suggested_name
		save_dialog.popup_centered_ratio(.8)

func write_chosen(path: String) -> void:
	if path.get_extension().to_lower()!=EXTENSION_NAME: path+="."+EXTENSION_NAME
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file==null:
		failed.emit("Could not write to that folder.")
		return
	file.store_string(pending_text)
	file.flush()
	var ok := file.get_error()==OK
	file.close()
	if ok: delivered.emit("Expedition exported to "+path.get_file())
	else:
		DirAccess.remove_absolute(path)
		failed.emit("Could not finish writing the export.")

func received(args: Array) -> void:
	if args.size()<2: return
	match str(args[0]):
		"cancel": return
		"error": failed.emit(str(args[1]))
		"saved": delivered.emit("Expedition downloaded as "+str(args[1]))
		"file":
			var bytes := JavaScriptBridge.js_buffer_to_packed_byte_array(args[1])
			var file := FileAccess.open(STAGED,FileAccess.WRITE)
			if file==null:
				failed.emit("Browser storage is unavailable.")
				return
			file.store_buffer(bytes)
			var result := file.get_error()
			file.close()
			if result!=OK:
				DirAccess.remove_absolute(STAGED)
				failed.emit("Browser storage is full. Free space and try again.")
				return
			chosen.emit(STAGED)
			DirAccess.remove_absolute(STAGED)
