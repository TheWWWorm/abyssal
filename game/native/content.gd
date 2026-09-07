extends RefCounted
## File-only runtime boundary. Content is prepared offline from the owner's JAR.
var root := ""
var data: Dictionary = {}
var registry: Array = []
var failure := ""
## SHA-256 of the JAR this cache was converted from. The engine is developed against
## the Sony Ericsson release of DEEP 1.0.8; any DEEP build that converts is playable.
var profile := ""

static func is_digest(value) -> bool:
	if value is not String or value.length()!=64: return false
	for character in value:
		if not "0123456789abcdef".contains(character): return false
	return true

func load_cache(directory: String) -> bool:
	failure=""
	var path := directory.path_join("native-data.json")
	if not FileAccess.file_exists(path):
		failure="Import your DEEP JAR to prepare the native content."
		return false
	var parsed=JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is not Dictionary or not is_digest(parsed.get("jar_sha256","")) or parsed.get("schema",0)!=1:
		failure="The content profile is unsupported. Reimport your JAR."
		return false
	if parsed.get("importer","")!="native-6":
		failure="This native content cache needs an update. Reimport your JAR."
		return false
	var registry_path := directory.path_join("resource_registry.json")
	if not FileAccess.file_exists(registry_path):
		failure="The resource index is missing. Reimport your JAR.";return false
	var entries=JSON.parse_string(FileAccess.get_file_as_string(registry_path))
	if entries is not Array or entries.is_empty() or not parsed.has_all(["tables","constants","strings","campaign","habitats","timelines"]):
		failure="The content cache is incomplete. Reimport your JAR.";return false
	for entry in entries:
		if entry is not Dictionary or not entry.has_all(["id","model","textures"]) or entry.textures is not Array:
			failure="The resource index is invalid. Reimport your JAR.";return false
		for resource in [entry.model]+entry.textures:
			if resource is not String or not resource.begins_with("data/") or resource.contains("..") or resource.contains("\\"):
				failure="The resource index contains an unsafe path.";return false
	root=directory;data=parsed;registry=entries;profile=str(parsed.jar_sha256)
	return true

func text(id: int) -> String:
	return str(data.strings[id]) if id>=0 and id<data.strings.size() else ""

func ship_name(id: int) -> String:
	var ids: Array = data.constants.e["d:[[S"]
	return text(int(ids[id][0]))

func record_name(record: Dictionary) -> String:
	var id := int(record.id)
	if id>=0 and id<data.tables.ships.size(): return ship_name(id)
	return str(record.model).get_file().get_basename().replace("_"," ").capitalize()
