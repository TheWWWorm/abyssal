extends RefCounted
## The reference: articles about the player's own imported DEEP content. Nothing
## is bundled. Every name, description and line of dialogue comes from the
## converted JAR, and the figures come from the simulation's own rules. Keys
## are language-independent navigation tokens ("station/12"); only imported
## names and engine text reach a page.
##
## The reference's own writing (WikiProse) explains the world, the rules and
## the story around those facts in the player's language; it names things
## only through link tokens, so a translated JAR's names appear in it.
##
## Pages are small, well-formed HTML fragments: h1, h2, p, ul, li, table (with
## data-columns), tr, th, td, strong, em, br, figure and wiki:// links. The
## in-game reader turns them into rich text and shows each page's picture
## (media) beside it; the HTML export shows them as they are. Imported text
## is always escaped.
##
## Story pages stop at a chapter limit, so a player is not shown what lies
## ahead of their save: later chapters, characters not yet met, and stations
## that have not yet changed sides stay out of every page.
const Math = preload("res://native/simulation/fixed_math.gd")
const Equipment = preload("res://native/simulation/equipment.gd")
const EquipmentInfo = preload("res://native/presentation/equipment_info.gd")
const Economy = preload("res://native/simulation/economy.gd")
const Contracts = preload("res://native/simulation/contracts.gd")
const EngineLanguage = preload("res://native/presentation/engine_language.gd")
const WikiProse = preload("res://native/wiki/wiki_prose.gd")

const CATEGORIES := ["world", "story", "characters", "factions", "stations", "ships", "equipment", "species", "goods", "contracts", "medals", "guide"]
## The Ino's outfit as the game hands it over (Session.new_game).
const STARTING_EQUIPMENT := [15, 18, 22, 35]
## What the job board leaves out (Contracts.offer_kind).
const COLONIST_EXCLUDED := [13, 14, 6, 12]
const REBEL_EXCLUDED := [12, 5, 4, 7, 11]
## Algae models stand on the sea bed (Creature.configure).
const ALGAE_MODELS := [4443, 4444, 4445, 4446, 4447]
## Speakers the dialogue tables name by role, and the game's words for them.
const ROLE_SPEAKERS := {"Colonist": 238, "Rebel": 239, "Pirate": 240}

var data: Dictionary
var entries := {}
var ordered: Array[String] = []
var species_count := 0
var chapters := 0
## The last chapter shown: the save's own, or every chapter.
var limit := 0
var rebel_since := {}
var prose: WikiProse
## The language of the reference's own text; imported names stay the JAR's.
var language := "en"
## The imported JAR's own language, and the project's names for this
## reference's language when the two differ (native/wiki/names/<code>.gd).
var jar_language := "en"
var names := {}

func _init(owner_data: Dictionary, chapter_limit := -1, code := "") -> void:
	data = owner_data
	language = code if code in EngineLanguage.codes() else EngineLanguage.current
	prose = WikiProse.new(language)
	jar_language = EngineLanguage.content_language(str(data.get("language", "")), data.strings)
	var list := "res://native/wiki/names/%s.gd" % language
	if language != jar_language and ResourceLoader.exists(list): names = load(list).NAMES
	species_count = data.constants.ah["b:[S"].size()
	chapters = data.campaign.size()
	limit = chapters if chapter_limit < 0 else clampi(chapter_limit, 1, chapters)
	for record: Dictionary in data.campaign:
		if int(record.chapter) > limit: continue
		for id in record.rebel_stations:
			if not rebel_since.has(int(id)): rebel_since[int(id)] = int(record.chapter)
	rebuild()

## Engine text in the reference's language, whatever the interface uses.
func translate(text: String) -> String: return EngineLanguage.text_in(language, text)

func all_sections() -> String: return translate("All sections")

## True when no station is left to the colonists at that chapter.
func all_rebel(as_of: int) -> bool:
	for id in data.tables.stations.size():
		if not rebel_since.has(id) or rebel_since[id] > as_of: return false
	return true

## The chart's legend at a chapter.
func chart_caption(as_of: int) -> String:
	if all_rebel(as_of): return translate("Every station has joined the rebels.")
	return translate("Blue: %s · orange: %s") % [faction_name(false), faction_name(true)]

func complete() -> bool: return limit >= chapters

# --- names ----------------------------------------------------------------

func text(id: int, replacement := "") -> String:
	if id < 0 or id >= data.strings.size() or data.strings[id] == null: return ""
	var value := str(data.strings[id])
	return value.replace("#", replacement) if not replacement.is_empty() else value

func pair(key: String, id: int, part: int) -> String:
	var table: Array = data.constants.e.get(key, [])
	if id < 0 or id >= table.size() or part >= table[id].size(): return ""
	return text(int(table[id][part]))

static func named(value: String, fallback: String) -> String:
	return value.strip_edges() if not value.strip_edges().is_empty() else fallback

## A name in the reference's language: the project's own where the JAR is
## in another language, the JAR's otherwise.
func local(key: String, value: String) -> String: return str(names[key]) if names.has(key) else value

## Whether the JAR's descriptions and dialogue are in the reference's language.
func jar_speaks() -> bool: return language == jar_language

## A description from the JAR, shown in italics when it is in the reader's
## language; the reference's own text covers the rest.
func jar_lead(value: String) -> String:
	return p("<em>%s</em>" % esc(value)) if jar_speaks() and not value.strip_edges().is_empty() else ""

func ship_name(id: int) -> String: return named(pair("d:[[S", id, 0), translate("Ship %d") % (id + 1))
func equipment_name(id: int) -> String: return local("equipment/%d" % id, named(pair("b:[[S", id, 0), translate("Equipment %d") % (id + 1)))
func goods_name(id: int) -> String: return local(("species/%d" if id < species_count else "goods/%d") % id, named(pair("c:[[S", id, 0), translate("Goods %d") % (id + 1)))
func medal_name(id: int) -> String: return local("medal/%d" % id, named(pair("a:[[S", id, 0), translate("Medal %d") % (id + 1)))
func station_name(id: int) -> String: return str(data.tables.stations[id][0]) if id >= 0 and id < data.tables.stations.size() else "?"
func faction_name(rebel: bool) -> String: return translate("Rebels") if rebel else translate("Colonists")

func contract_name(kind: int) -> String:
	var ids: Array = data.constants.e["i:[S"]
	return local("contract/%d" % kind, named(text(int(ids[kind])) if kind < ids.size() else "", objective_name(kind)))

func speaker_name(id: int) -> String:
	if id == 0: return translate("Pilot")
	var names: Array = data.constants.ah["a:[Ljava.lang.String;"]
	var value := str(names[id]) if id > 0 and id < names.size() and names[id] != null else ""
	if ROLE_SPEAKERS.has(value): return local("character/%d" % id, named(text(ROLE_SPEAKERS[value]), value))
	return named(value, translate("Speaker %d") % id)

func chapter_title(chapter: int) -> String:
	var mission: Dictionary = data.campaign[chapter - 1].mission
	var ids: Array = data.constants.e["g:[S"]
	var raw := text(int(ids[chapter])) if chapter < ids.size() else ""
	if int(mission.get("a:int", -1)) < 0: return translate("Ending")
	return local("chapter/%d" % chapter, named(raw.replace("#", str(mission.get("b:java.lang.String", ""))), translate("Chapter %d") % chapter))

func category_name(category: String) -> String:
	match category:
		"stations": return translate("Stations")
		"factions": return translate("Factions")
		"ships": return translate("Ships")
		"equipment": return translate("Equipment")
		"species": return translate("Species")
		"goods": return translate("Goods")
		"story": return translate("Story")
		"characters": return translate("Characters")
		"contracts": return translate("Contracts")
		"medals": return translate("Medals")
		"guide": return translate("Guide")
		"world": return translate("World")
	return category

## Objective kinds, as Campaign and Region evaluate them.
func objective_name(kind: int) -> String:
	match kind:
		0: return translate("Destroy the wanted ship")
		1: return translate("Disable and recover a ship")
		2: return translate("Salvage a disabled ship")
		3: return translate("Defeat the pirates")
		4: return translate("Escort friendly ships")
		5: return translate("Intercept hostile ships")
		6: return translate("Protect the creatures")
		7: return translate("Hunt the creatures")
		8: return translate("Travel to the station")
		9: return translate("Clear the debris")
		10: return translate("Clear the minefield")
		11: return translate("Defend the capsules")
		12: return translate("Destroy the capsules")
		13: return translate("Deliver goods")
		14: return translate("Deliver a catch")
		15: return translate("Complete contracts")
		16: return translate("Defeat enemies")
		17: return translate("Install equipment")
		18: return translate("Discover stations")
		19: return translate("Catch creatures")
		20: return translate("Fill the cargo hold")
		21: return translate("Produce goods")
		22: return translate("Leave the station")
	return translate("Objective")

## What starts a radio line during a story encounter (Timeline.poll).
func trigger_name(kind: int, value: int) -> String:
	match kind:
		0: return translate("after waypoint %d") % value
		1: return translate("when a marked hostile is destroyed")
		2: return translate("when a marked friend is lost")
		3: return translate("when no hostiles remain")
		4: return translate("when no friends remain")
		5: return translate("after %.0f s or once the encounter is resolved") % (value / 1000.0)
		6: return translate("after line %d") % (value + 1)
		8: return translate("when a marked hostile appears")
		9: return translate("when every marked hostile is destroyed")
		10: return translate("when a marked friend is present")
		12: return translate("when a marked hostile is below half hull")
		13: return translate("after the first catch")
		14: return translate("when a marked ship is rescued")
		15: return translate("when any enemy is destroyed")
		16: return translate("while enemies are present")
		17: return translate("when all but one enemy are destroyed")
		18: return translate("when a marked hostile is captured")
		19: return translate("when a marked hostile is below three quarters hull")
	return translate("during the encounter")

# --- registry -------------------------------------------------------------

func add(key: String, title: String, category: String, subtitle := "") -> void:
	entries[key] = {"key": key, "title": title, "category": category, "subtitle": subtitle}
	ordered.append(key)

func rebuild() -> void:
	entries.clear(); ordered.clear()
	add("home", translate("Reference"), "")
	add("chart", translate("Station chart"), "stations", translate("%d stations") % data.tables.stations.size())
	for id in data.tables.stations.size():
		add("station/%d" % id, station_name(id), "stations", translate("Tech %d · %d m") % [int(data.tables.stations[id][1]), depth(id)])
	add("faction/colonists", faction_name(false), "factions")
	add("faction/rebels", faction_name(true), "factions")
	add("faction/pirates", translate("Pirates"), "factions")
	for id in data.tables.ships.size():
		add("ship/%d" % id, ship_name(id), "ships", translate("Hull %d · %d slots") % [int(data.tables.ships[id][1]), int(data.tables.ships[id][4])])
	for id in data.tables.equipment.size():
		add("equipment/%d" % id, equipment_name(id), "equipment", EquipmentInfo.kind_name(item(id)))
	for id in data.tables.goods.size():
		if id < species_count: add("species/%d" % id, goods_name(id), "species", translate("Algae") if is_algae(id) else translate("Creature"))
		else: add("goods/%d" % id, goods_name(id), "goods", translate("Product · tech %d") % int(data.tables.goods[id][1]) if is_product(id) else translate("Goods"))
	for chapter in range(1, limit + 1):
		add("chapter/%d" % chapter, chapter_title(chapter), "story", translate("Chapter %d") % chapter if chapter < chapters else "")
	# A chapter's dialogue is its own page, linked from the chapter, so the
	# chapter page reads as a summary rather than a script.
	for chapter in range(1, limit + 1):
		if has_dialogue(chapter): add("dialogue/%d" % chapter, translate("Dialogue: %s") % chapter_title(chapter), "", translate("Chapter %d") % chapter)
	add("character/0", speaker_name(0), "characters", translate("You"))
	for id in range(1, data.constants.ah["a:[Ljava.lang.String;"].size()):
		if not appearances(id).is_empty(): add("character/%d" % id, speaker_name(id), "characters")
	for kind in data.constants.e["i:[S"].size():
		add("contract/%d" % kind, contract_name(kind), "contracts")
	for id in data.constants.e["a:[[S"].size():
		add("medal/%d" % id, medal_name(id), "medals")
	for key: String in prose.pages:
		var info: Dictionary = prose.pages[key]
		if int(info.get("from", 1)) <= limit and not entries.has(key): add(key, str(info.title), str(info.get("category", "guide")), str(info.get("subtitle", "")))
	add("guide/help", translate("Controls"), "guide")
	add("guide/tips", translate("Tips"), "guide")
	for category: String in CATEGORIES: add("section/" + category, category_name(category), "")

func page(key: String) -> String:
	if not entries.has(key): return h1(translate("Not found")) + p(esc(translate("There is no such page in this reference.")))
	var parts := key.split("/")
	var id := int(parts[1]) if parts.size() > 1 and parts[1].is_valid_int() else -1
	match parts[0]:
		"home": return home_page()
		"chart": return chart_page()
		"station": return station_page(id)
		"faction": return faction_page(parts[1])
		"ship": return ship_page(id)
		"equipment": return equipment_page(id)
		"species": return species_page(id)
		"goods": return goods_page(id)
		"chapter": return chapter_page(id)
		"dialogue": return dialogue_page(id)
		"character": return character_page(id)
		"contract": return contract_page(id)
		"medal": return medal_page(id)
		"guide", "world":
			if parts[1] in ["help", "tips"]: return guide_page(parts[1])
			return h1(entries[key].title, entries[key].subtitle) + prose_html(key)
		"section": return section_page(parts[1])
	return ""

## The page's own words for search: its title and subtitle.
func search_text(key: String) -> String:
	var entry: Dictionary = entries[key]
	return "%s %s" % [entry.title, entry.subtitle]

# --- HTML -----------------------------------------------------------------

static func esc(value: String) -> String:
	return value.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;").replace("\n", "<br/>")

func a(key: String) -> String:
	return "<a href=\"wiki://%s\">%s</a>" % [key, esc(entries[key].title)] if entries.has(key) else ""

func chapter_link(chapter: int) -> String:
	return a("chapter/%d" % chapter) if chapter <= limit else esc(translate("a later chapter"))

func h1(title: String, subtitle := "") -> String:
	return "<h1>%s</h1>" % esc(title) + (p("<em>%s</em>" % esc(subtitle)) if not subtitle.is_empty() else "")

func h2(title: String) -> String: return "<h2>%s</h2>" % esc(title)
func p(html: String) -> String: return "<p>%s</p>" % html
func bullets(items: Array) -> String: return "<ul><li>" + "</li><li>".join(items) + "</li></ul>" if not items.is_empty() else ""

## Rows of [label, html] as a two-column table.
func facts(rows: Array) -> String:
	var out := "<table data-columns=\"2\">"
	for row: Array in rows: out += "<tr><th>%s</th><td>%s</td></tr>" % [esc(row[0]), row[1]]
	return out + "</table>"

## A table with a header row; cells are already HTML.
func grid(header: Array, rows: Array) -> String:
	if rows.is_empty(): return ""
	var out := "<table data-columns=\"%d\"><tr>" % header.size()
	for cell in header: out += "<th>%s</th>" % esc(cell)
	out += "</tr>"
	for row: Array in rows:
		out += "<tr>"
		for cell in row: out += "<td>%s</td>" % str(cell)
		out += "</tr>"
	return out + "</table>"

func links(keys: Array) -> String:
	var parts := PackedStringArray()
	for key in keys:
		var html := a(key)
		if not html.is_empty(): parts.append(html)
	return ", ".join(parts) if not parts.is_empty() else esc(translate("None"))

func money(value: int) -> String: return esc(translate("%d cr") % value)

## The page's own prose a save at this chapter may read, as HTML.
func prose_html(key: String) -> String:
	var out := ""
	var items: Array = []
	# Like any wiki, a name is a link where it first appears, plain text after.
	var named_ := {key: true}
	for block: Array in prose.visible(key, limit):
		var heading := str(block[1])
		if (not block[3] or not heading.is_empty()) and not items.is_empty():
			out += bullets(items); items = []
		if not heading.is_empty(): out += h2(heading)
		if block[3]: items.append(linked(str(block[2]), named_))
		else: out += p(linked(str(block[2]), named_))
	return out + bullets(items)

## Prose text with its [[key]] tokens as links. A page the save may not see
## yet keeps the token's own words, or is left unnamed.
func linked(value: String, named_ := {}) -> String:
	var out := ""
	var at := 0
	for found in RegEx.create_from_string("\\[\\[([a-z]+(?:/[a-z0-9]+)?)(?:\\|([^\\]]*))?\\]\\]").search_all(value):
		out += esc(value.substr(at, found.get_start() - at))
		var key := found.get_string(1)
		var words := found.get_string(2)
		if entries.has(key):
			# Chapter titles repeat (several are "travel to" a station), so
			# prose names a chapter by its number.
			var title := str(entries[key].title)
			if key.begins_with("chapter/") and int(key.get_slice("/", 1)) < chapters: title = translate("Chapter %d") % int(key.get_slice("/", 1))
			var shown := esc(words if not words.is_empty() else title)
			out += shown if named_.has(key) else "<a href=\"wiki://%s\">%s</a>" % [key, shown]
			named_[key] = true
		elif not words.is_empty(): out += esc(words)
		elif key.begins_with("chapter/"): out += esc(translate("a later chapter"))
		at = found.get_end()
	return out + esc(value.substr(at))

## One section's pages in a table, after its introduction.
func section_page(category: String) -> String:
	var out := h1(category_name(category), translate("Section"))
	out += prose_html("intro/" + category)
	var keys: Array = ordered.filter(func(key): return entries[key].category == category)
	if category != "story": keys.sort_custom(func(x, y): return str(entries[x].title).naturalnocasecmp_to(entries[y].title) < 0)
	return out + grid([translate("Page"), translate("Details")], keys.map(func(key): return [a(key), esc(str(entries[key].subtitle))]))

# --- rules ----------------------------------------------------------------

func percent(id: int) -> int:
	# Session.new_game: the chart's 0 and 100 are the two special holdings.
	var value := int(data.tables.stations[id][4])
	return -10 if value == 0 else (115 if value == 100 else value)

func depth(id: int) -> int: return Math.depth_from_percent(percent(id))

func item(id: int):
	var result := Equipment.new(); result.configure(data.tables.equipment[id]); return result

func is_algae(id: int) -> bool:
	return id < species_count and int(data.constants.ah["b:[S"][id]) in ALGAE_MODELS

func is_product(id: int) -> bool:
	var row: Array = data.tables.goods[id]
	return row.size() > 8 and not row[7].is_empty()

func distance(first: int, second: int) -> int:
	return Economy.distance_xy(station_point(first), station_point(second))

func station_point(id: int) -> Dictionary:
	return {"x": int(data.tables.stations[id][2]), "y": int(data.tables.stations[id][3])}

func habitat(id: int) -> Array:
	var result: Array = []
	var pairs: Array = preload("res://native/simulation/habitat.gd").prevalence(data, id)
	for index in range(0, pairs.size(), 2):
		if int(pairs[index + 1]) > 0 and not int(pairs[index]) in result: result.append(int(pairs[index]))
	return result

func mission(chapter: int) -> Dictionary: return data.campaign[chapter - 1].mission
func kind_of(chapter: int) -> int: return int(mission(chapter).get("a:int", -1))

func destination(chapter: int) -> int:
	var kind := kind_of(chapter)
	return int(mission(chapter).get("e:int", -1)) if kind >= 0 and kind <= 14 else -1

## Visible chapters whose objective matches.
func chapters_where(test: Callable) -> Array:
	var result: Array = []
	for chapter in range(1, limit + 1):
		if test.call(chapter, mission(chapter)): result.append("chapter/%d" % chapter)
	return result

func story_lines(chapter: int, phase: int) -> Array:
	# Campaign.dialogue: speaker and line pairs, the briefing then the
	# completion; a zero line is an empty slot.
	var table: Array = data.constants.bo["a:[[S" if phase == 0 else "b:[[S"]
	var result: Array = []
	if chapter < 0 or chapter >= table.size(): return result
	var ids: Array = table[chapter]
	for i in range(0, ids.size() - 1, 2):
		if int(ids[i + 1]) != 0: result.append({"speaker": int(ids[i]), "text_id": int(ids[i + 1])})
	return result

func radio_lines(chapter: int) -> Array: return data.timelines.get(str(chapter), [])

## Visible lines spoken by one speaker, by chapter. The current chapter's
## completion is still ahead of the player.
func appearances(speaker: int) -> Dictionary:
	var result := {}
	for chapter in range(1, limit + 1):
		var lines: Array = []
		for phase in (2 if chapter < limit or complete() else 1):
			for line in story_lines(chapter, phase): if line.speaker == speaker: lines.append(line.text_id)
		for line: Dictionary in radio_lines(chapter): if int(line.speaker) == speaker: lines.append(int(line.text_id))
		if not lines.is_empty(): result[chapter] = lines
	return result

func line_text(text_id: int) -> String: return text(text_id, translate("[Pilot]"))

func speaker_link(speaker: int) -> String:
	var html := a("character/%d" % speaker)
	return html if not html.is_empty() else esc(speaker_name(speaker))

func dialogue(lines: Array) -> String:
	var out := "<table data-columns=\"2\">"
	for line: Dictionary in lines:
		out += "<tr><th>%s</th><td>%s</td></tr>" % [speaker_link(line.speaker), esc(line_text(line.text_id))]
	return out + "</table>"

func objective(chapter: int) -> String:
	var record := mission(chapter)
	var kind := kind_of(chapter)
	if kind < 0: return esc(translate("The story is complete."))
	var out := esc(objective_name(kind))
	var threshold := int(record.get("r:int", 0))
	var where := int(record.get("e:int", -1))
	match kind:
		13, 14:
			var goods := int(record.get("l:int", 0))
			out += ": %d × %s → %s" % [int(record.get("m:int", 1)), a(("species/%d" if goods < species_count else "goods/%d") % goods), a("station/%d" % where)]
		17: out += ": " + a("equipment/%d" % threshold)
		15, 16, 18, 21: out += " · " + esc(translate("%d more") % threshold)
		19, 20: out += " · " + str(threshold)
		6, 7:
			var target := int(record.get("n:int", -1))
			if target >= 0 and target < species_count: out += ": " + a("species/%d" % target)
			if where >= 0: out += " · " + a("station/%d" % where)
		_:
			if where >= 0: out += ": " + a("station/%d" % where)
	return out

## Where the HTML export draws the station chart. The page only marks the
## spot; the export's reader draws every station from one shared list, and
## the in-game reader leaves figures out. Control is as of the given chapter.
func chart(highlight: int, as_of: int, joining: Array = []) -> String:
	return "<figure class=\"chart\" data-highlight=\"%d\" data-as-of=\"%d\" data-joining=\"%s\"></figure>" % [highlight, as_of, ",".join(joining.map(func(id): return str(int(id))))]

# --- pages ----------------------------------------------------------------

func home_page() -> String:
	var out := h1(translate("Reference"), translate("Compiled from your imported game"))
	out += prose_html("home")
	out += p("<em>%s</em>" % esc(translate("Names, descriptions and dialogue come from the DEEP JAR you imported; figures follow the engine's rules.")))
	if not complete(): out += p("<em>%s</em>" % esc(translate("Story pages end at chapter %d, where your latest save is. Later chapters appear as you reach them.") % limit))
	var start: Array = ["chapter/%d" % limit, "world/ocean", "world/history", "guide/basics", "chart"].filter(func(key): return entries.has(key))
	out += h2(translate("Start here")) + bullets(start.map(func(key): return a(key) + ("  ·  " + esc(entries[key].subtitle) if not str(entries[key].subtitle).is_empty() else "")))
	for category: String in CATEGORIES:
		var count := ordered.filter(func(key): return entries[key].category == category).size()
		if count == 0: continue
		out += h2(category_name(category))
		var intro: Array = prose.visible("intro/" + category, limit)
		if not intro.is_empty(): out += p(linked(str(intro[0][2])))
		out += p("<a href=\"wiki://section/%s\">%s</a>" % [category, esc(translate("All %d pages") % count)])
	return out

func chart_page() -> String:
	var out := h1(translate("Station chart"), translate("%d stations") % data.tables.stations.size())
	out += p(esc(translate("Every station starts under the colonists; the rebels take them over chapter by chapter.")))
	out += prose_html("chart")
	out += chart(-1, limit)
	var ids := range(data.tables.stations.size())
	ids.sort_custom(func(x, y): return station_name(x).naturalnocasecmp_to(station_name(y)) < 0)
	var rows: Array = ids.map(func(id): return [a("station/%d" % id), str(int(data.tables.stations[id][1])), esc(translate("%d m") % depth(id)), "%d, %d" % [int(data.tables.stations[id][2]), int(data.tables.stations[id][3])], control(id)])
	return out + grid([translate("Station"), translate("Tech"), translate("Depth"), translate("Chart"), translate("Control")], rows)

func control(id: int) -> String:
	if rebel_since.has(id): return esc(faction_name(true)) + " · " + chapter_link(rebel_since[id])
	return esc(faction_name(false))

func station_page(id: int) -> String:
	var row: Array = data.tables.stations[id]
	var out := h1(station_name(id), translate("Station"))
	out += chart(id, limit)
	var rows: Array = [[translate("Tech level"), str(int(row[1]))], [translate("Depth"), esc(translate("%d m") % depth(id))], [translate("Chart position"), "%d, %d" % [int(row[2]), int(row[3])]], [translate("Control"), control(id)]]
	if percent(id) < 0: rows.append([translate("Role"), esc(translate("Outfitter: every piece of equipment is on sale here."))])
	elif percent(id) > 100: rows.append([translate("Role"), esc(translate("Shipyard: every hull is on sale here."))])
	out += facts(rows)
	out += h2(translate("Reaching it")) + p(reach(depth(id)))
	out += h2(translate("Species found here")) + p(links(habitat(id).map(func(s): return "species/%d" % s)))
	var home: Array = []; var market: Array = []
	for g in range(species_count, data.tables.goods.size()):
		if int(data.tables.goods[g][2]) == id: home.append("goods/%d" % g)
		if int(data.tables.goods[g][3]) == id: market.append("goods/%d" % g)
	var recipes := range(data.tables.goods.size()).filter(func(g): return is_product(g) and int(data.tables.goods[g][1]) <= int(row[1])).size()
	out += h2(translate("Trade")) + facts([[translate("Home of"), links(home)], [translate("Best market for"), links(market)], [translate("Recipes in the factory"), str(recipes)]])
	var story := chapters_where(func(chapter, _record): return destination(chapter) == id)
	if not story.is_empty(): out += h2(translate("In the story")) + p(links(story))
	var near := range(data.tables.stations.size()).filter(func(other): return other != id)
	near.sort_custom(func(x, y): return distance(id, x) < distance(id, y))
	out += h2(translate("Nearest stations")) + grid([translate("Station"), translate("Chart distance"), translate("Depth")], near.slice(0, 6).map(func(other): return [a("station/%d" % other), str(distance(id, other)), esc(translate("%d m") % depth(other))]))
	return out

func reach(metres: int) -> String:
	# ShipStats.recompute: without a shield a ship rises no higher than
	# 22,000 m, and without armour sinks no deeper than 23,000 m.
	var needs: Array = []
	if metres < 22000:
		var shields := range(data.tables.equipment.size()).filter(func(e): return int(data.tables.equipment[e][1]) == 3 and int(data.tables.equipment[e][7]) <= metres)
		needs.append(esc(translate("Needs a shield rated to %d m or shallower:") % metres) + " " + links(shields.map(func(e): return "equipment/%d" % e)))
	if metres > 23000:
		var armour := range(data.tables.equipment.size()).filter(func(e): return int(data.tables.equipment[e][1]) == 4 and int(data.tables.equipment[e][6]) >= metres)
		needs.append(esc(translate("Needs armour rated to %d m or deeper:") % metres) + " " + links(armour.map(func(e): return "equipment/%d" % e)))
	return "<br/>".join(needs) if not needs.is_empty() else esc(translate("Any ship can dock here without depth equipment."))

func faction_page(which: String) -> String:
	if which == "pirates":
		var out := h1(translate("Pirates"), translate("Faction")) + prose_html("faction/pirates")
		out += h2(translate("In the game")) + p(esc(translate("Pirates attack in open water. The bounty for a trip grows with the square of the pirates destroyed: %d cr a head at a colonist station, %d cr at a rebel one.") % [100, 50]))
		var story := chapters_where(func(chapter, _record): return kind_of(chapter) in [0, 3] or appearances(10).has(chapter))
		if not story.is_empty(): out += h2(translate("In the story")) + p(links(story))
		return out + h2(translate("Contracts")) + p(links(["contract/0", "contract/3"]))
	var rebel := which == "rebels"
	var out := h1(faction_name(rebel), translate("Faction")) + prose_html("faction/" + which)
	out += h2(translate("In the game"))
	if rebel:
		out += p(esc(translate("Rebel stations trade freely and post the full job board. Stations join the rebels as the story goes on, and stay with them.")))
		var rows: Array = []
		for record: Dictionary in data.campaign:
			if record.rebel_stations.is_empty() or int(record.chapter) > limit: continue
			rows.append([chapter_link(int(record.chapter)), str(record.rebel_stations.size()), links(record.rebel_stations.map(func(s): return "station/%d" % int(s)))])
		if not rows.is_empty(): out += h2(translate("Stations joining, by chapter")) + grid([translate("Chapter"), translate("Count"), translate("Stations")], rows)
	else:
		out += p(esc(translate("Colonist stations do not trade: on arrival they take the whole cargo at its floor price. Their job board opens in chapter 9.")))
		out += chart(-1, 0)
		out += p(esc(translate("Colonist stations so far: %d of %d.") % [data.tables.stations.size() - rebel_since.size(), data.tables.stations.size()]))
	var offered: Array = []
	for kind in data.constants.e["i:[S"].size():
		if not kind in (REBEL_EXCLUDED if rebel else COLONIST_EXCLUDED): offered.append("contract/%d" % kind)
	out += h2(translate("Contracts posted")) + p(links(offered))
	var people := links(["character/%d" % (7 if rebel else 6)])
	if people != esc(translate("None")): out += h2(translate("Characters")) + p(people)
	return out

func ship_page(id: int) -> String:
	var row: Array = data.tables.ships[id]
	var out := h1(ship_name(id), translate("Ship"))
	out += jar_lead(pair("d:[[S", id, 1)) + prose_html("ship/%d" % id)
	out += h2(translate("Specifications")) + facts([[translate("Hull"), str(int(row[1]))], [translate("Cargo"), esc(translate("%d t") % int(row[2]))], [translate("Equipment slots"), str(int(row[4]))], [translate("Steering"), "%.2f" % maxf(.1, int(row[5]) / 100.0)], [translate("List price"), money(int(row[3]))]])
	var notes: Array = []
	if id == 0: notes.append(esc(translate("Your first ship, fitted with:")) + " " + links(STARTING_EQUIPMENT.map(func(e): return "equipment/%d" % e)))
	if id < data.constants.ah["e:[S"].size():
		# Economy.generate_ships: a hull of index n waits for chapter 5(n-2).
		var from := maxi(1, (id - 2) * 5)
		notes.append(esc(translate("Ordinary shipyards offer it from chapter %d.") % from))
	notes.append(esc(translate("The shipyard station lists every hull. A station's tech level takes that many percent off the price, and rebel yards sell the upgraded model.")))
	if id == Economy.COLLECTORS_SHIP: notes.append(esc(translate("With every medal won, it sells for %d cr.") % Economy.COLLECTORS_PRICE))
	out += h2(translate("Availability")) + bullets(notes)
	var rows: Array = range(data.tables.ships.size()).map(func(other):
		var hull: Array = data.tables.ships[other]
		return ["<strong>%s</strong>" % esc(ship_name(other)) if other == id else a("ship/%d" % other), str(int(hull[1])), str(int(hull[2])), str(int(hull[4])), money(int(hull[3]))])
	return out + h2(translate("Compare")) + grid([translate("Ship"), translate("Hull"), translate("Cargo"), translate("Slots"), translate("Price")], rows)

func equipment_page(id: int) -> String:
	var gear = item(id)
	var out := h1(equipment_name(id), EquipmentInfo.kind_name(gear))
	out += jar_lead(pair("b:[[S", id, 1)) + prose_html("equipment/%d" % id)
	out += h2(translate("Specifications"))
	var rows: Array = EquipmentInfo.figures(gear).map(func(figure): return [figure[0], esc(figure[1])])
	rows.append([translate("Price range"), "%s – %s" % [money(gear.minimum_price), money(gear.maximum_price)]])
	rows.append([translate("Shop rarity"), esc(translate("Not on ordinary shelves") if gear.rarity <= 0 else translate("%d, more likely each chapter") % gear.rarity)])
	rows.append([translate("Per ship"), esc(translate("Several can be fitted") if gear.kind in [0, 5] else translate("One of this kind"))])
	out += facts(rows)
	var header := [translate("Tech level")]; var prices := [translate("Price")]
	for tech in range(1, 11):
		gear.station_price(tech); header.append(str(tech)); prices.append(str(gear.price))
	out += h2(translate("Price by station tech level")) + grid(header, [prices])
	out += p(esc(translate("Selling back, or buying gear already owned once, is a fifth cheaper.")))
	var story: Array = []
	if id in STARTING_EQUIPMENT: story.append(esc(translate("Fitted to your first ship:")) + " " + a("ship/0"))
	for key in chapters_where(func(chapter, record): return kind_of(chapter) == 17 and int(record.get("r:int", -1)) == id):
		story.append(esc(translate("Must be installed in:")) + " " + a(key))
	if not story.is_empty(): out += h2(translate("In the story")) + bullets(story)
	var same := range(data.tables.equipment.size()).filter(func(other): return other != id and EquipmentInfo.kind_name(item(other)) == EquipmentInfo.kind_name(gear))
	if not same.is_empty(): out += h2(translate("Same kind")) + p(links(same.map(func(other): return "equipment/%d" % other)))
	return out

func price_rows(id: int) -> Array:
	var row: Array = data.tables.goods[id]
	return [[translate("Price range"), "%s – %s" % [money(int(row[5])), money(int(row[6]))]], [translate("Availability"), "%d%%" % int(row[4])]]

func ingredient_of(id: int) -> Array:
	return range(data.tables.goods.size()).filter(func(g): return is_product(g) and id in data.tables.goods[g][7].map(func(v): return int(v))).map(func(g): return "goods/%d" % g)

func species_page(id: int) -> String:
	var out := h1(goods_name(id), translate("Algae") if is_algae(id) else translate("Creature"))
	out += jar_lead(pair("c:[[S", id, 1)) + prose_html("species/%d" % id)
	out += h2(translate("Specifications"))
	var rows: Array = []
	if id < data.tables.creatures.size():
		var creature: Array = data.tables.creatures[id]
		var mass := int(creature[1]); var resistance := int(creature[2])
		# Creature.configure: hull twice the mass, a quarter either way for
		# swimmers; the harpoon struggle lasts 2.1 s plus a tenth per point.
		rows.append([translate("Mass"), esc((translate("%d t") % mass) + ("" if is_algae(id) else " " + translate("(±25%)")))])
		rows.append([translate("Toughness"), str(mass * 2)])
		rows.append([translate("Harpoon struggle"), esc(translate("%.1f s") % ((2100 + resistance / 10.0 * 2100) / 1000.0))])
	out += facts(rows + price_rows(id))
	var homes := range(data.tables.stations.size()).filter(func(station): return id in habitat(station))
	homes.sort_custom(func(x, y): return station_name(x).naturalnocasecmp_to(station_name(y)) < 0)
	out += h2(translate("Found at %d stations") % homes.size()) + p(links(homes.map(func(s): return "station/%d" % s)))
	var uses := ingredient_of(id)
	if not uses.is_empty(): out += h2(translate("Ingredient of")) + p(links(uses))
	var story := chapters_where(func(chapter, record): return (kind_of(chapter) in [6, 7] and int(record.get("n:int", -1)) == id) or (kind_of(chapter) in [13, 14] and int(record.get("l:int", -1)) == id))
	if not story.is_empty(): out += h2(translate("In the story")) + p(links(story))
	return out + h2(translate("Contracts")) + p(links(["contract/6", "contract/7", "contract/14"]))

func goods_page(id: int) -> String:
	var row: Array = data.tables.goods[id]
	var out := h1(goods_name(id), translate("Goods"))
	out += jar_lead(pair("c:[[S", id, 1)) + prose_html("goods/%d" % id)
	out += h2(translate("Trade")) + facts([[translate("Tech level"), str(int(row[1]))], [translate("Home station"), a("station/%d" % int(row[2]))], [translate("Best market"), a("station/%d" % int(row[3]))]] + price_rows(id))
	out += p(esc(translate("The price rises from its floor at the home station towards its ceiling at the best market, with the chart distance travelled.")))
	if is_product(id):
		var recipe: Array = []
		for i in row[7].size():
			var ingredient := int(row[7][i])
			recipe.append([a(("species/%d" if ingredient < species_count else "goods/%d") % ingredient), str(int(row[8][i]))])
		out += h2(translate("Recipe")) + grid([translate("Ingredient"), translate("Per unit")], recipe)
		out += p(esc(translate("Made in the factory of any station of tech level %d or higher.") % int(row[1])))
	var uses := ingredient_of(id)
	if not uses.is_empty(): out += h2(translate("Ingredient of")) + p(links(uses))
	var notes: Array = []
	if id in Economy.STORY_GOODS: notes.append(esc(translate("A story item: markets never stock it.")))
	if id in Economy.IMPORTS: notes.append(esc(translate("An import: rebel markets restock it between visits.")))
	if id in Contracts.UNDELIVERABLE and not id in Economy.STORY_GOODS: notes.append(esc(translate("Delivery contracts never ask for it.")))
	if not notes.is_empty(): out += h2(translate("Notes")) + bullets(notes)
	var story := chapters_where(func(chapter, record): return kind_of(chapter) in [13, 14] and int(record.get("l:int", -1)) == id)
	if not story.is_empty(): out += h2(translate("In the story")) + p(links(story))
	return out

func chapter_page(chapter: int) -> String:
	var record: Dictionary = data.campaign[chapter - 1]
	var out := h1(chapter_title(chapter), translate("Chapter %d of %d") % [mini(chapter, chapters - 1), chapters - 1] if chapter < chapters else translate("Ending"))
	var steps := PackedStringArray()
	if chapter > 1: steps.append("← " + a("chapter/%d" % (chapter - 1)))
	if chapter < limit: steps.append(a("chapter/%d" % (chapter + 1)) + " →")
	if not steps.is_empty(): out += p(" · ".join(steps))
	var ids: Array = data.constants.e["h:[S"]
	var place := str(mission(chapter).get("b:java.lang.String", ""))
	var summary := text(int(ids[chapter]), place) if chapter < ids.size() else ""
	out += jar_lead(summary)
	var rows: Array = [[translate("Objective"), objective(chapter)]]
	if int(mission(chapter).get("c:int", 0)) > 0: rows.append([translate("Reward"), money(int(mission(chapter).get("c:int", 0)))])
	if not record.rebel_stations.is_empty(): rows.append([translate("Stations joining the rebels"), links(record.rebel_stations.map(func(s): return "station/%d" % int(s)))])
	var speakers := chapter_speakers(chapter)
	if not speakers.is_empty(): rows.append([translate("Characters"), links(speakers.map(func(id): return "character/%d" % id))])
	if entries.has("dialogue/%d" % chapter): rows.append([translate("Dialogue"), "<a href=\"wiki://dialogue/%d\">%s</a>" % [chapter, esc(translate("Briefing, radio and debriefing"))]])
	out += facts(rows)
	out += prose_html("chapter/%d" % chapter)
	if not record.rebel_stations.is_empty(): out += chart(destination(chapter), chapter, record.rebel_stations.map(func(s): return int(s)))
	return out

func has_dialogue(chapter: int) -> bool:
	return not (story_lines(chapter, 0).is_empty() and story_lines(chapter, 1).is_empty() and radio_lines(chapter).is_empty())

## Who speaks in a chapter, in order of first line. The completion counts once
## the chapter is behind the player.
func chapter_speakers(chapter: int) -> Array:
	var found: Array = []
	var lines: Array = story_lines(chapter, 0) + radio_lines(chapter).map(func(line): return {"speaker": int(line.speaker)})
	if chapter < limit or complete(): lines += story_lines(chapter, 1)
	for line in lines:
		var speaker := int(line.speaker)
		if speaker > 0 and not speaker in found and entries.has("character/%d" % speaker): found.append(speaker)
	return found

func dialogue_page(chapter: int) -> String:
	var out := h1(translate("Dialogue: %s") % chapter_title(chapter), translate("Chapter %d") % chapter)
	out += p("← " + a("chapter/%d" % chapter))
	if not jar_speaks(): out += p("<em>%s</em>" % esc(translate("The dialogue is shown as written in your imported game.")))
	var briefing := story_lines(chapter, 0)
	if not briefing.is_empty(): out += h2(translate("Briefing")) + dialogue(briefing)
	var radio := radio_lines(chapter)
	if not radio.is_empty():
		var lines: Array = radio.map(func(line: Dictionary):
			var values: Array = line.get("values", [])
			return [speaker_link(int(line.speaker)), esc(line_text(int(line.text_id))), esc(trigger_name(int(line.kind), int(values[0]) if not values.is_empty() else 0))])
		out += h2(translate("Radio during the mission")) + grid([translate("Speaker"), translate("Line"), translate("When")], lines)
	var completion := story_lines(chapter, 1)
	if not completion.is_empty():
		if chapter < limit or complete(): out += h2(translate("On completion")) + dialogue(completion)
		else: out += h2(translate("On completion")) + p("<em>%s</em>" % esc(translate("Shown once you finish this chapter.")))
	return out

func character_page(id: int) -> String:
	var out := h1(speaker_name(id), translate("Character") if id != 0 else translate("You"))
	if id == 0: out += p("<em>%s</em>" % esc(translate("You, the pilot. Your chosen name appears here as [Pilot].")))
	var seen: Array = appearances(id).keys()
	seen.sort()
	var rows: Array = []
	if id == 6: rows.append([translate("Faction"), a("faction/colonists")])
	elif id == 7: rows.append([translate("Faction"), a("faction/rebels")])
	elif id == 10: rows.append([translate("Faction"), a("faction/pirates")])
	if not seen.is_empty():
		rows.append([translate("First appearance"), "<a href=\"wiki://chapter/%d\">%s</a> · %s" % [seen[0], esc(translate("Chapter %d") % seen[0]), esc(chapter_title(seen[0]))]])
		rows.append([translate("Chapters"), str(seen.size())])
	out += facts(rows)
	out += prose_html("character/%d" % id)
	# Where to read on: the chapters, not every line spoken in them.
	if not seen.is_empty():
		var numbers: Array = seen.map(func(chapter): return "<a href=\"wiki://chapter/%d\">%d</a>" % [chapter, chapter])
		out += h2(translate("Appearances")) + p("%s: %s" % [esc(translate("Chapters")), ", ".join(numbers)])
	return out

func contract_page(kind: int) -> String:
	var out := h1(contract_name(kind), translate("Job board contract"))
	var summary: Array = data.constants.e["j:[S"]
	if kind < summary.size(): out += jar_lead(text(int(summary[kind]), translate("[station]")))
	out += prose_html("contract/%d" % kind)
	var offer: Array = data.constants.e["k:[S"]
	if kind < offer.size() and jar_speaks(): out += h2(translate("Offer")) + p(esc(line_text(int(offer[kind]))))
	var posted: Array = []
	if not kind in COLONIST_EXCLUDED: posted.append(a("faction/colonists"))
	if not kind in REBEL_EXCLUDED: posted.append(a("faction/rebels"))
	var rows: Array = [[translate("Objective"), esc(objective_name(kind))], [translate("Posted by"), ", ".join(posted) if not posted.is_empty() else esc(translate("Nobody"))]]
	if kind in [13, 14]: rows.append([translate("Where"), esc(translate("Only at stations past the first twenty"))])
	if kind == 6: rows.append([translate("Note"), esc(translate("Rebels stop posting it once the story is complete."))])
	out += facts(rows)
	var story := chapters_where(func(chapter, _record): return kind_of(chapter) == kind)
	if not story.is_empty(): out += h2(translate("Story chapters of this kind")) + p(links(story))
	return out

func medal_page(id: int) -> String:
	var out := h1(medal_name(id), translate("Medal")) + prose_html("medal/%d" % id)
	var table: Array = data.constants.f["a:[[I"]
	var thresholds: Array = table[id] if id < table.size() else []
	# Medals.evaluate: the first tier is gold, the last bronze.
	var tiers := [translate("Gold"), translate("Silver"), translate("Bronze")]
	var rows: Array = []
	for tier in thresholds.size():
		rows.append([tiers[tier] if thresholds.size() > 1 else translate("Award"), esc(text(int(data.constants.e["a:[[S"][id][1]), str(int(thresholds[tier]))))])
	out += facts(rows)
	# The last medal is for holding all the others.
	if id == table.size() - 1: out += p(esc(translate("Winning every medal also lowers the price of:")) + " " + a("ship/%d" % Economy.COLLECTORS_SHIP))
	return out

## The reference's own guide to the controls and station screens, or its
## tips; the game's own help and loading tips follow when the imported game
## speaks the reader's language.
func guide_page(which: String) -> String:
	var out := h1(entries["guide/" + which].title, translate("Guide")) + prose_html("guide/" + which)
	if not jar_speaks(): return out
	if which == "tips":
		var seen := {}
		var tips: Array = []
		for tip in data.constants.e["e:[S"]:
			if seen.has(int(tip)): continue
			seen[int(tip)] = true; tips.append(esc(text(int(tip))))
		return out + (h2(translate("Loading tips")) + bullets(tips) if not tips.is_empty() else "")
	var titles: Array = data.constants.e["a:[S"]; var bodies: Array = data.constants.e["b:[S"]
	if mini(titles.size(), bodies.size()) > 1: out += h2(translate("In-game help"))
	for i in range(1, mini(titles.size(), bodies.size())):
		var title := text(int(titles[i]))
		out += p("<strong>%s</strong><br>%s" % [esc(title), esc(text(int(bodies[i])).trim_prefix("[%s]\n" % title.to_upper()).strip_edges())])
	return out

# --- pictures -------------------------------------------------------------

## What the reader shows beside a page: {"model": registry id, "faction"},
## {"image": interface path}, {"portrait": face layers}, {"chart": {highlight,
## as_of, joining}} or {"glyph": station icon}. Pictures come from the
## player's imported art, as the game itself shows them.
func media(key: String) -> Dictionary:
	var parts := key.split("/")
	var id := int(parts[1]) if parts.size() > 1 and parts[1].is_valid_int() else -1
	match parts[0]:
		"ship": return {"model": id, "faction": 0, "image": "equipment/u%da" % id}
		"species": return {"model": int(data.constants.ah["b:[S"][id]), "image": "cargo_%d" % id}
		"equipment": return {"image": "equipment/slot_%d" % id}
		"goods": return {"image": "cargo_%d" % id}
		"medal": return {"image": "medal_1"}
		"contract": return {"image": "mission_%d" % id}
		"character": return portrait(id)
		# The chart as it stood when the station changed sides, with the others
		# joining then: by the end of the story every station is orange.
		"station":
			var since: int = rebel_since.get(id, limit)
			var joining: Array = data.campaign[since - 1].rebel_stations.map(func(s): return int(s)) if rebel_since.has(id) else []
			return {"station": id, "colonist": not rebel_since.has(id), "chart": {"highlight": id, "as_of": since, "joining": joining}}
		"section": return {}
		"chart", "home": return {"chart": {"highlight": -1, "as_of": limit, "joining": []}}
		"faction":
			if parts[1] == "pirates": return {"model": 4, "faction": 2}
			return {"image": "logo_1" if parts[1] == "rebels" else "logo_0", "chart": {"highlight": -1, "as_of": limit if parts[1] == "rebels" else 0, "joining": []}}
		"dialogue": return media("chapter/%d" % id)
		"chapter":
			var joining: Array = data.campaign[id - 1].rebel_stations.map(func(s): return int(s))
			if not joining.is_empty() or destination(id) >= 0: return {"chart": {"highlight": destination(id), "as_of": id, "joining": joining}}
			for phase in 2:
				for line in story_lines(id, phase):
					if line.speaker > 0 and entries.has("character/%d" % line.speaker): return portrait(line.speaker)
			return {"image": "mission_story"}
		"world":
			if parts[1] == "aquarians": return {"model": 19, "creature": false, "upright": true}
			if parts[1] in ["history", "colony", "stream"]: return {"chart": {"highlight": -1, "as_of": limit, "joining": []}}
			if parts[1] == "ocean": return {"model": 4427}
			if parts[1] == "abel": return {"glyph": "status"}
			return {"glyph": "world"}
	return {"glyph": GUIDE_GLYPHS.get(parts[1] if parts.size() > 1 else "", "book")}

const GUIDE_GLYPHS := {"basics": "help", "depth": "shield", "navigation": "map", "fishing": "cargo", "trading": "trade",
	"combat": "status", "fitting": "workshop", "contracts": "contracts", "allegiance": "world", "medals": "medal", "help": "controls", "tips": "help"}

func portrait(speaker: int) -> Dictionary:
	if speaker == 0: return {"glyph": "person"}
	var faces: Array = data.constants.ah.get("a:[[B", [])
	if speaker < faces.size() and faces[speaker] is Array and not faces[speaker].is_empty(): return {"portrait": faces[speaker]}
	return {"glyph": "person"}

## The small picture beside a page's name in the lists.
func icon(key: String) -> Dictionary:
	var parts := key.split("/")
	var id := int(parts[1]) if parts.size() > 1 and parts[1].is_valid_int() else -1
	match parts[0]:
		"ship": return {"image": "equipment/u%da" % id}
		"species", "goods": return {"image": "cargo_%d" % id}
		"station": return {"image": "logo_1" if rebel_since.has(id) else "logo_0"}
		"chapter": return {"image": "mission_story"}
		"faction":
			# The job board's own picture for hunting pirates.
			if parts[1] == "pirates": return {"image": "mission_3"}
			return {"image": "logo_1" if parts[1] == "rebels" else "logo_0"}
		"character", "equipment", "medal", "contract":
			var shown := media(key)
			shown.erase("chart")
			return shown
		"chart": return {"glyph": "map"}
		"world": return {"glyph": "world"}
	return media(key) if parts[0] == "guide" else {"glyph": "book"}
