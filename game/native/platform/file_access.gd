extends Node
## Browser JAR conversion runs in a disposable worker; no user bytes are uploaded.
signal selected(path: String)
signal failed(message: String)
signal progress(message: String)
signal busy_changed(active: bool)
var dialog := FileDialog.new()
var callback: JavaScriptObject
var browser: JavaScriptObject
var busy := false
func _ready() -> void:
	if OS.has_feature("web"):
		callback=JavaScriptBridge.create_callback(received)
		JavaScriptBridge.eval("""
window.abyssalFiles = {
 worker:null, generation:0, busy:false,
 cancel:function(callback) {
  this.generation++; if(this.worker)this.worker.terminate(); this.worker=null;
  this.busy=false; callback('cancel','Import cancelled.');
 },
 choose:function(callback) {
  if(this.busy){this.cancel(callback);return;}
  const input=document.createElement('input');input.type='file';input.accept='.jar,.abyss';
  input.onchange=async()=>{
   const file=input.files[0];if(!file)return;
   const jar=file.name.toLowerCase().endsWith('.jar');
   if(!jar&&!file.name.toLowerCase().endsWith('.abyss')){callback('error','Choose a .jar or .abyss file.');return;}
   if(file.size>(jar?16777216:134217728)){callback('error','The selected file exceeds import limits.');return;}
   this.busy=true;const generation=++this.generation;callback('progress','Reading your local file…');
   const finish=(type,value)=>{
    if(generation!==this.generation)return;
    if(this.worker)this.worker.terminate();this.worker=null;this.busy=false;callback(type,value);
   };
   try {
    const bytes=await file.arrayBuffer();if(generation!==this.generation)return;
    if(!jar){finish('complete',bytes);return;}
    this.worker=new Worker(new URL('importer/worker.js',document.baseURI));
    this.worker.onerror=()=>finish('error','The browser importer could not start. Check that the complete Web export is served over HTTPS or localhost.');
    this.worker.onmessage=({data})=>{
     if(generation!==this.generation)return;
     if(data.type==='progress')callback('progress',data.message);
     else if(data.type==='complete')finish('complete',data.buffer);
     else if(data.type==='error')finish('error',data.message);
    };
    this.worker.postMessage(bytes,[bytes]);
   }catch(error){finish('error',String(error.message||error));}
  };input.click();
 }
};
""",true)
		browser=JavaScriptBridge.get_interface("abyssalFiles")
	else:
		add_child(dialog);dialog.access=FileDialog.ACCESS_FILESYSTEM;dialog.file_mode=FileDialog.FILE_MODE_OPEN_FILE
		dialog.use_native_dialog=true;dialog.filters=PackedStringArray(["*.abyss ; Private Abyssal content pack ; application/octet-stream,application/zip"])
		dialog.file_selected.connect(func(path):selected.emit(path))
func choose() -> void:
	if OS.has_feature("web"):browser.choose(callback)
	else:dialog.popup_centered_ratio(.8)
func set_busy(value: bool) -> void:
	if busy==value:return
	busy=value;busy_changed.emit(value)
func received(args: Array) -> void:
	if args.size()<2:return
	if str(args[0])=="progress":
		set_busy(true);progress.emit(str(args[1]));return
	set_busy(false)
	if str(args[0])!="complete":failed.emit(str(args[1]));return
	var bytes:=JavaScriptBridge.js_buffer_to_packed_byte_array(args[1])
	var path:="user://selected.abyss"
	var file:=FileAccess.open(path,FileAccess.WRITE)
	if file==null:failed.emit("Browser storage is unavailable.");return
	file.store_buffer(bytes)
	var result:=file.get_error();file.close()
	if result!=OK:
		DirAccess.remove_absolute(path);failed.emit("Browser storage is full. Free space and try again.");return
	selected.emit(path);DirAccess.remove_absolute(path)
func _exit_tree() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("if(window.abyssalFiles){window.abyssalFiles.generation++;if(window.abyssalFiles.worker)window.abyssalFiles.worker.terminate();window.abyssalFiles.worker=null;}",true)
