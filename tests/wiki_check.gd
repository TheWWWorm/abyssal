extends SceneTree
## The reference: every page of the imported content renders, parses and
## links only to pages that exist; a chapter limit keeps later story out of
## every page, prose included; every page's picture and list icon is in the
## imported art; the web page export and the reader work. Runs headless with
## native-data.json as its argument.
const EngineLanguage = preload("res://native/presentation/engine_language.gd")
const Catalog = preload("res://native/wiki/wiki_catalog.gd")
const WikiHtml = preload("res://native/wiki/wiki_html.gd")
const WikiExport = preload("res://native/wiki/wiki_export.gd")
const WikiPanel = preload("res://native/wiki/wiki_panel.gd")
const WikiProse = preload("res://native/wiki/wiki_prose.gd")
const Content = preload("res://native/content.gd")
const ImportedArt = preload("res://native/presentation/imported_art.gd")
var failures := 0
func expect(ok: bool, why: String) -> void:
	if not ok: failures += 1; push_error(why)
func _initialize(): call_deferred("run")

func check_pages(catalog: Catalog, label: String) -> Dictionary:
	var linked := {}
	for key: String in catalog.ordered:
		var html := catalog.page(key)
		var parser := XMLParser.new()
		var parsed := parser.open_buffer(("<div>" + html + "</div>").to_utf8_buffer()) == OK
		while parsed:
			var result := parser.read()
			if result == ERR_FILE_EOF: break
			if result != OK: parsed = false
		expect(parsed, "%s: %s is well-formed" % [label, key])
		expect(not WikiHtml.to_bbcode(html, Color.WHITE, Color.GRAY).is_empty(), "%s: %s renders" % [label, key])
		var title := str(catalog.entries[key].title)
		expect(not title.strip_edges().is_empty() and title != key, "%s: %s has a real title" % [label, key])
		for target in WikiHtml.links(html):
			expect(catalog.entries.has(target), "%s: %s links to a page that exists (%s)" % [label, key, target])
			linked[target] = true
	return linked

func run():
	var content := Content.new()
	expect(content.load_cache(OS.get_cmdline_user_args()[0].get_base_dir()), "The imported content loads")
	var data: Dictionary = content.data
	var art := ImportedArt.new(); art.root = content.root
	var full := Catalog.new(data)
	var stations: int = data.tables.stations.size()
	expect(full.complete() and full.limit == data.campaign.size(), "No limit shows the whole story")
	expect(full.entries.has("station/%d" % (stations - 1)) and full.entries.has("chapter/%d" % data.campaign.size()), "Every station and chapter has a page")
	expect(full.entries.has("ship/%d" % (data.tables.ships.size() - 1)) and full.entries.has("equipment/%d" % (data.tables.equipment.size() - 1)), "Every ship and piece of equipment has a page")
	expect(full.entries.has("medal/%d" % (data.constants.e["a:[[S"].size() - 1)) and full.entries.has("contract/0"), "Medals and contracts have pages")
	var linked := check_pages(full, "full")
	for key: String in full.ordered:
		if key != "home": expect(linked.has(key), "%s is reachable from another page" % key)
	expect(full.rebel_since.size() <= stations, "Rebel control stays within the chart")

	# Pictures: every list icon and page picture is in the imported art, and
	# every model is in the resource registry.
	var models := content.registry.map(func(entry): return int(entry.id))
	for key: String in full.ordered:
		for shown: Dictionary in [full.icon(key), full.media(key)]:
			if shown.has("image"): expect(art.image(shown.image) != null, "%s: picture %s is imported" % [key, shown.image])
			if shown.has("portrait"): expect(art.portrait(shown.portrait) != null, "%s has a portrait" % key)
			if shown.has("model"): expect(int(shown.model) in models, "%s: model %d is imported" % [key, int(shown.model)])

	# Prose: every link names a page of the whole story, and every page the
	# prose is written for exists.
	var english := WikiProse.new("en")
	for key: String in english.blocks:
		var page_key := key.trim_prefix("intro/")
		expect(full.entries.has(page_key if not key.begins_with("intro/") else "section/" + page_key), "Prose for %s belongs to a page" % key)
		for block: Array in english.blocks[key]:
			for token in WikiProse.tokens(str(block[2])):
				expect(full.entries.has(token[1]), "%s links to a page that exists (%s)" % [key, token[1]])
	for code in WikiProse.LANGUAGES:
		var local = WikiProse.source(code)
		if local == null: continue
		for key: String in local.BLOCKS:
			expect(english.blocks.has(key), "%s prose for %s has an English original" % [code, key])
			for block: Array in local.BLOCKS[key]:
				expect(int(block[0]) >= 1 and not str(block[2]).strip_edges().is_empty(), "%s prose for %s is well-formed" % [code, key])
				for token in WikiProse.tokens(str(block[2])): expect(full.entries.has(token[1]), "%s prose for %s links to %s" % [code, key, token[1]])

	# A save in chapter 5 sees nothing beyond it.
	var early := Catalog.new(data, 5)
	check_pages(early, "chapter 5")
	expect(early.entries.has("chapter/5") and not early.entries.has("chapter/6"), "Story pages stop at the save's chapter")
	for key: String in early.ordered:
		var html := early.page(key)
		for chapter in range(6, data.campaign.size() + 1):
			if ("wiki://chapter/%d\"" % chapter) in html: expect(false, "%s mentions chapter %d" % [key, chapter])
	for station in early.rebel_since: expect(early.rebel_since[station] <= 5, "Stations change sides only up to the save's chapter")
	for key: String in english.blocks:
		for block: Array in english.blocks[key]:
			if int(block[0]) > 5 and early.entries.has(key):
				expect(not early.linked(str(block[2])) in early.page(key), "%s keeps prose from chapter %d hidden" % [key, int(block[0])])
	if not early.story_lines(5, 1).is_empty():
		expect(early.esc(early.translate("Shown once you finish this chapter.")) in early.page("dialogue/5"), "The current chapter's ending stays hidden")
	expect("wiki://dialogue/5" in early.page("chapter/5") and not "<h2>%s</h2>" % early.esc(early.translate("Briefing")) in early.page("chapter/5"), "A chapter links its dialogue rather than holding it")
	expect(not early.entries.has("dialogue/6") and early.entries["dialogue/5"].category.is_empty(), "Dialogue pages follow the save and stay out of the lists")
	expect(early.page("character/1").count("<li>") == 0 and early.esc(early.translate("Appearances")) in early.page("character/1"), "A character page tells the story rather than listing lines")
	var history := full.page("world/history")
	expect(history.count("wiki://character/9") == 1, "A name is linked where it first appears on a page")
	var unmet := 0
	for id in range(1, data.constants.ah["a:[Ljava.lang.String;"].size()):
		if not full.appearances(id).is_empty() and early.appearances(id).is_empty():
			unmet += 1
			expect(not early.entries.has("character/%d" % id), "A character not yet met has no page")
	expect(unmet > 0, "Some characters are met only later in the story")

	# Engine rules agree with the simulation.
	var Session = preload("res://native/simulation/session.gd")
	var session = Session.new(); session.new_game(data, "Pilot", 1)
	for id in [0, stations / 2, stations - 1]: expect(full.depth(id) == int(session.stations[id].depth), "Station %d depth matches the session" % id)

	var directory := OS.get_user_data_dir().path_join("wiki-check")
	expect(WikiExport.write(early, directory, art, {}, ["ru"]) == OK, "The web page export writes")
	expect(FileAccess.file_exists(directory.path_join("images/equipment-u0a.png")), "The export writes the pictures")
	for name in ["index.html", "wiki.css", "wiki.js", "languages.js", "content-%s.js" % early.language, "content-ru.js"]: expect(FileAccess.file_exists(directory.path_join(name)), "%s is written" % name)
	var bundle := FileAccess.get_file_as_string(directory.path_join("content-%s.js" % early.language))
	expect(bundle.begins_with("(window.DEEP_WIKI_LANGS=") and not "chapter/6\"" in bundle, "The export keeps the chapter limit")
	expect("\"stations\":[[" in bundle and not "<svg" in bundle, "The chart is drawn from one station list")
	var russian := FileAccess.get_file_as_string(directory.path_join("content-ru.js"))
	expect("Справочник" in russian or "Обзор" in russian, "The Russian edition carries Russian text")
	expect("\"ru\"" in FileAccess.get_file_as_string(directory.path_join("languages.js")), "languages.js lists the editions")
	var index_page := FileAccess.get_file_as_string(directory.path_join("index.html"))
	expect(WikiExport.SOURCE_URL in index_page and WikiExport.PLAY_URL in index_page and "\"play\":" in bundle, "The header links the source and the browser game")
	expect("\"sprites\":" in bundle, "The export lists the sprites shown under renders")

	# Name lists: the same keys in every language, each naming a real page.
	var english_names: Dictionary = load("res://native/wiki/names/en.gd").NAMES
	for code in EngineLanguage.codes():
		var path := "res://native/wiki/names/%s.gd" % code
		if not ResourceLoader.exists(path): continue
		var listed: Dictionary = load(path).NAMES
		expect(listed.keys().size() == english_names.size() and listed.keys().all(func(key): return english_names.has(key) and not str(listed[key]).strip_edges().is_empty()), "The %s name list matches the English keys" % code)
	for key: String in english_names: expect(full.entries.has(key), "Name list key %s is a page" % key)
	var foreign = Catalog.new(data, 5, "en" if full.jar_language != "en" else "ru")
	if not foreign.names.is_empty():
		expect(foreign.entries["species/8"].title == str(foreign.names["species/8"]) and not foreign.jar_speaks(), "Another language uses the project's names, not the JAR's")
		# The controls and tips are the reference's own; the game's own help
		# and loading tips only follow in the game's language.
		for which in ["help", "tips"]:
			var own: String = foreign.page("guide/" + which)
			expect("<li>" in own and not foreign.translate("Loading tips" if which == "tips" else "In-game help") in own, "guide/%s is the reference's own text in another language" % which)
		if early.jar_speaks(): expect(early.translate("In-game help") in early.page("guide/help"), "The game's own help follows in its language")
	var german = Catalog.new(data, 5, "de")
	expect(german.language == "de" and german.category_name("ships") != "Ships" and german.page("guide/depth") != early.page("guide/depth"), "A catalog can be built in another language")

	var panel = WikiPanel.new(); panel.configure(content, 5)
	panel.size = Vector2(1280, 720); root.add_child(panel)
	await process_frame
	expect(panel.history == ["home"] and not panel.article.text.is_empty(), "The reader opens on its home page")
	panel.open("station/0"); panel.open("ship/0")
	panel.step(-1)
	expect(panel.history[panel.cursor] == "station/0" and not panel.forward.disabled, "Back returns to the previous page")
	var before: String = panel.article.text
	panel.switch_language("de")
	expect(panel.catalog.language == "de" and panel.history[panel.cursor] == "station/0" and panel.article.text != before, "The language menu rebuilds the open page")
	panel.switch_language(early.language)
	panel.open("ship/1")
	expect(panel.media.visible and panel.media.shown == "image", "A ship page shows its picture")
	panel.open("character/1")
	expect(panel.media.shown == "portrait", "A character page shows the portrait")
	panel.open("station/0")
	expect(panel.media.shown == "chart", "A station page shows the chart")
	panel.step(-1); panel.step(-1); panel.step(-1)
	panel.search.text = full.station_name(0); panel.fill_list()
	expect(not panel.listed.is_empty() and panel.listed[0] == "station/0", "Search finds a station by name")
	expect(panel.related.item_count > 1, "Linked pages are offered for a controller")
	# Touch and controller: a long page scrolls under a finger without
	# selecting text, with the right stick, and hands focus on at its end.
	panel.open("guide/help")
	for frame in 4: await process_frame
	var bar: VScrollBar = panel.article.get_v_scroll_bar()
	expect(bar.max_value > bar.page, "The controls page is long enough to scroll")
	var touch = preload("res://native/input/touch_scroll.gd").new(); root.add_child(touch)
	var middle: Vector2 = panel.article.get_global_rect().get_center()
	var press := InputEventScreenTouch.new(); press.index = 0; press.pressed = true; press.position = middle
	touch._input(press)
	for i in 6:
		var drag := InputEventScreenDrag.new(); drag.index = 0; drag.position = middle - Vector2(0, 30 * (i + 1)); touch._input(drag)
	var lift := InputEventScreenTouch.new(); lift.index = 0; lift.position = middle - Vector2(0, 180); touch._input(lift)
	expect(bar.value > 100 and not panel.article.selection_enabled, "A finger drag scrolls the article instead of selecting")
	var click := InputEventMouseButton.new(); click.button_index = MOUSE_BUTTON_LEFT; click.pressed = true; click.position = middle; click.device = 0
	touch._input(click)
	expect(panel.article.selection_enabled, "A mouse selects text again")
	touch.queue_free()
	bar.value = 0
	var stick := InputEventJoypadMotion.new(); stick.axis = JOY_AXIS_RIGHT_Y; stick.axis_value = 1.0
	panel._input(stick)
	for frame in 6: await process_frame
	stick.axis_value = 0.0; panel._input(stick)
	expect(bar.value > 0, "The right stick scrolls the article")
	panel.article.grab_focus(); bar.value = bar.max_value
	var down := InputEventAction.new(); down.action = "ui_down"; down.pressed = true
	panel.article_keys(down)
	expect(panel.related.has_focus(), "At the end of the article, down moves on to the linked pages")
	var pages_before: int = panel.cursor
	var shoulder := InputEventJoypadButton.new(); shoulder.button_index = JOY_BUTTON_LEFT_SHOULDER; shoulder.pressed = true
	panel._unhandled_input(shoulder)
	expect(panel.cursor == pages_before - 1, "LB goes back a page")
	panel.step(1)
	panel.size = Vector2(600, 900); panel.arrange()
	expect(panel.browse.visible and not panel.side.visible, "A narrow reader shows the page with a Browse button")
	panel.show_list(true)
	expect(panel.side.visible and not panel.reader.visible, "Browse swaps to the list")
	panel.queue_free()
	for frame in 3: await process_frame
	print("WIKI_CHECK ", full.ordered.size(), " pages, ", early.ordered.size(), " at chapter 5, ", failures, " failures")
	quit(1 if failures > 0 else 0)
