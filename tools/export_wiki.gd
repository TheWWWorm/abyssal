extends SceneTree
## Writes the reference of an imported game as a web page folder:
##   godot-4 --headless --path game --script ../tools/export_wiki.gd -- CACHE OUTPUT [--chapter=N]
## (from the repository root; Godot finds the script from the game folder)
## Without --headless, a window opens while ships, creatures and stations are
## rendered for their pages.
## CACHE is the imported content folder (or its native-data.json). The pages
## hold that game's own text, so keep OUTPUT outside this repository. With
## --chapter the story stops there, as it does in the game. The engine's own
## words follow the game's language, or --language=CODE.
const Catalog = preload("res://native/wiki/wiki_catalog.gd")
const WikiExport = preload("res://native/wiki/wiki_export.gd")
const EngineLanguage = preload("res://native/presentation/engine_language.gd")
const ImportedArt = preload("res://native/presentation/imported_art.gd")
const WikiSnapshots = preload("res://native/wiki/wiki_snapshots.gd")
const Content = preload("res://native/content.gd")

func _initialize() -> void: run.call_deferred()

func run() -> void:
	var paths: Array = []
	var chapter := -1
	var language := EngineLanguage.AUTO
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--chapter="): chapter = argument.trim_prefix("--chapter=").to_int()
		elif argument.begins_with("--language="): language = argument.trim_prefix("--language=")
		# --path moves Godot into the project; a relative path means the shell's.
		elif argument.is_relative_path() and not OS.get_environment("PWD").is_empty(): paths.append(OS.get_environment("PWD").path_join(argument))
		else: paths.append(argument)
	if paths.size() != 2:
		printerr("Usage: -- CACHE OUTPUT [--chapter=N]"); quit(2); return
	var source: String = paths[0] if str(paths[0]).ends_with(".json") else str(paths[0]).path_join("native-data.json")
	var data = JSON.parse_string(FileAccess.get_file_as_string(source))
	if data is not Dictionary or not data.has_all(["tables", "constants", "strings", "campaign"]):
		printerr("Not an imported content cache: ", source); quit(1); return
	EngineLanguage.apply(EngineLanguage.resolve(language, EngineLanguage.content_language(str(data.get("language", "")), data.strings)))
	var catalog := Catalog.new(data, chapter)
	var art := ImportedArt.new(); art.root = source.get_base_dir()
	# With a window (no --headless) ships, creatures and stations are
	# rendered for their pages too.
	var renders := {}
	var content := Content.new()
	if WikiSnapshots.available() and content.load_cache(source.get_base_dir()):
		var camera = WikiSnapshots.new(); root.add_child(camera)
		renders = await camera.render(catalog, content, paths[1])
		print("Rendered %d pictures" % renders.size())
	# Every language the reference is written in; the page offers a switch.
	var result := WikiExport.write(catalog, paths[1], art, renders, EngineLanguage.codes())
	if result != OK:
		printerr("Could not write ", paths[1], ": ", error_string(result)); quit(1); return
	print("Wrote %d pages in %d languages to %s" % [catalog.ordered.size(), EngineLanguage.codes().size(), paths[1]])
	quit(0)
