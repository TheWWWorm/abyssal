extends RefCounted
## Portable data-only expedition exports. A transfer carries the save record and
## nothing else: no scripts, no resource paths and no imported game content. The
## content profile in the save has to match the JAR the receiving copy imported,
## so an export never turns into a save for a game it was not played on.
const Save = preload("res://native/simulation/save_store.gd")
const FORMAT := "abyssal-native-save"
const VERSION := 1
const MAX_BYTES := 8 * 1024 * 1024
const EXTENSION := "abyssave"
var failure := ""

func validate(data: Dictionary, value: Variant) -> Dictionary:
	"""Accepts only this build's envelope around a save this content can restore."""
	failure=""
	if value is not Dictionary or value.get("format")!=FORMAT or int(value.get("version",0))!=VERSION:
		failure="This is not an Abyssal expedition export."
		return {}
	if str(value.get("content_id",""))!=str(data.jar_sha256):
		failure="This expedition was played on different game content. Import the same JAR first."
		return {}
	var record: Variant = value.get("save")
	if record is not Dictionary:
		failure="The export contains no expedition."
		return {}
	var store := Save.new()
	# Restoring is the validation: the same reader the title screen uses.
	if store.restore(data,record)==null:
		failure=store.failure if not store.failure.is_empty() else "The exported expedition is invalid."
		return {}
	return {"format":FORMAT,"version":VERSION,"content_id":str(data.jar_sha256),"save":record.duplicate(true)}

func read_export(data: Dictionary, path: String) -> Dictionary:
	failure=""
	var file := FileAccess.open(path,FileAccess.READ)
	if file==null:
		failure="The export could not be opened."
		return {}
	if file.get_length()>MAX_BYTES:
		failure="The export exceeds %d MiB." % (MAX_BYTES/1048576)
		return {}
	var text := file.get_as_text()
	file.close()
	return validate(data,Save.quiet_parse(text))

func collect(data: Dictionary, save_path: String) -> Dictionary:
	"""Wraps the save on disk, having confirmed this build can still read it."""
	failure=""
	if not FileAccess.file_exists(save_path):
		failure="There is no expedition to export yet."
		return {}
	var value: Variant = Save.quiet_parse(FileAccess.get_file_as_string(save_path))
	return validate(data,{"format":FORMAT,"version":VERSION,"content_id":str(data.jar_sha256),"save":value})

func write(path: String, value: Dictionary) -> bool:
	failure=""
	var text := JSON.stringify(value)
	if text.to_utf8_buffer().size()>MAX_BYTES:
		failure="The export exceeds %d MiB." % (MAX_BYTES/1048576)
		return false
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file==null:
		failure="Could not write the export. Check the destination folder."
		return false
	file.store_string(text)
	file.flush()
	var ok := file.get_error()==OK
	file.close()
	if not ok:
		failure="Could not finish writing the export. The disk may be full."
		DirAccess.remove_absolute(path)
	return ok

func install(data: Dictionary, save_path: String, value: Dictionary) -> bool:
	"""Replaces the local expedition, keeping the displaced one as the backup the
	title screen already falls back to. Either the imported save becomes the
	current one or nothing on disk changes."""
	var checked := validate(data,value)
	if checked.is_empty(): return false
	DirAccess.make_dir_recursive_absolute(save_path.get_base_dir())
	var staged := save_path+".import"
	var file := FileAccess.open(staged,FileAccess.WRITE)
	if file==null:
		failure="Could not stage the imported expedition."
		return false
	file.store_string(JSON.stringify(checked.save))
	file.flush()
	var ok := file.get_error()==OK
	file.close()
	if not ok:
		failure="Could not stage the imported expedition. The disk may be full."
		DirAccess.remove_absolute(staged)
		return false
	if FileAccess.file_exists(save_path) and DirAccess.copy_absolute(save_path,save_path+".bak")!=OK:
		failure="Could not preserve the expedition already on this device."
		DirAccess.remove_absolute(staged)
		return false
	if DirAccess.rename_absolute(staged,save_path)!=OK:
		failure="Could not finish importing the expedition."
		DirAccess.remove_absolute(staged)
		return false
	return true

static func default_name(session) -> String:
	var stem := "abyssal-expedition"
	if session!=null and not str(session.name).is_empty():
		# A pilot name reaches a filesystem here, so keep it to safe characters.
		var cleaned := ""
		for character in str(session.name).to_lower():
			cleaned += character if character in "abcdefghijklmnopqrstuvwxyz0123456789" else "-"
		cleaned=cleaned.lstrip("-").rstrip("-")
		if not cleaned.is_empty(): stem=cleaned
	return "%s-%s.%s" % [stem,Time.get_datetime_string_from_system(false,false).replace(":","").replace("-",""),EXTENSION]
