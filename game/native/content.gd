extends RefCounted
## File-only runtime boundary. Content is prepared offline from the owner's JAR.
var root := ""
var data: Dictionary = {}
var registry: Array = []
var failure := ""
## SHA-256 of the JAR this cache was converted from. The engine is developed against
## the Sony Ericsson release of DEEP 1.0.8; any DEEP build that converts is playable.
var profile := ""
## Keys that only carry text, plus the two this loader adds. A translated or
## reworded JAR changes them and its file hash, but plays by the same rules, so
## its saves stay loadable.
const TEXT_KEYS := ["jar_sha256","language","strings","name_pools","rules_id","cache_directory"]
static var imported_rules := {}

static func rules_id(parsed: Dictionary) -> String:
	"""Fingerprint of everything in a cache except its text, station names
	included: two JARs that differ only in wording share it."""
	var rules := {}
	for key in parsed:
		if key not in TEXT_KEYS: rules[key]=parsed[key]
	if rules.get("tables") is Dictionary and rules.tables.get("stations") is Array:
		rules.tables=rules.tables.duplicate()
		rules.tables.stations=rules.tables.stations.map(func(row): return row.slice(1) if row is Array else row)
	return JSON.stringify(rules,"",true).sha256_text()

static func rules_of_import(jar_sha256: String, cache_directory: String) -> String:
	"""Rules of an earlier import of the given JAR, found beside the open cache.
	Saves from before rules_id existed name only their JAR; this lets them load
	once that JAR is replaced by a reworded copy. Empty when it is not on disk."""
	if not is_digest(jar_sha256) or cache_directory.is_empty(): return ""
	if imported_rules.has(jar_sha256): return imported_rules[jar_sha256]
	var parent := cache_directory.get_base_dir()
	for name in DirAccess.get_directories_at(parent):
		var path := parent.path_join(name).path_join("native-data.json")
		if not FileAccess.file_exists(path): continue
		var parsed=JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is not Dictionary or parsed.get("importer","")!="native-6" or not is_digest(parsed.get("jar_sha256","")): continue
		imported_rules[parsed.jar_sha256]=rules_id(parsed)
		if parsed.jar_sha256==jar_sha256: return imported_rules[jar_sha256]
	return ""

static func is_digest(value) -> bool:
	if value is not String or value.length()!=64: return false
	for character in value:
		if not "0123456789abcdef".contains(character): return false
	return true

func load_cache(directory: String) -> bool:
	failure=""
	var path := directory.path_join("native-data.json")
	if not FileAccess.file_exists(path):
		failure=tr("Import your DEEP JAR to prepare the native content.")
		return false
	var parsed=JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is not Dictionary or not is_digest(parsed.get("jar_sha256","")) or parsed.get("schema",0)!=1:
		failure=tr("The content profile is unsupported. Reimport your JAR.")
		return false
	if parsed.get("importer","")!="native-6":
		failure=tr("This native content cache needs an update. Reimport your JAR.")
		return false
	var registry_path := directory.path_join("resource_registry.json")
	if not FileAccess.file_exists(registry_path):
		failure=tr("The resource index is missing. Reimport your JAR.");return false
	var entries=JSON.parse_string(FileAccess.get_file_as_string(registry_path))
	if entries is not Array or entries.is_empty() or not parsed.has_all(["tables","constants","strings","campaign","habitats","timelines"]):
		failure=tr("The content cache is incomplete. Reimport your JAR.");return false
	for entry in entries:
		if entry is not Dictionary or not entry.has_all(["id","model","textures"]) or entry.textures is not Array:
			failure=tr("The resource index is invalid. Reimport your JAR.");return false
		for resource in [entry.model]+entry.textures:
			if resource is not String or not resource.begins_with("data/") or resource.contains("..") or resource.contains("\\"):
				failure=tr("The resource index contains an unsafe path.");return false
	parsed.rules_id=rules_id(parsed); parsed.cache_directory=directory
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
