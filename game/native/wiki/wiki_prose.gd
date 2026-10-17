extends RefCounted
## The reference's own writing: overviews, guides, story synopses and
## descriptions, kept per language in native/wiki/prose/<code>.gd. Imported
## names never appear in it; a [[key]] token stands for the page's title in the
## player's game, and [[key|words]] links the given words instead.
##
## Every block names the chapter a player must have reached to read it, so a
## synopsis or biography grows with the save and never runs ahead of it.
## A language without its own text for a page falls back to English.

const LANGUAGES := {
	"en": "res://native/wiki/prose/en.gd",
	"ru": "res://native/wiki/prose/ru.gd",
	"de": "res://native/wiki/prose/de.gd",
	"fr": "res://native/wiki/prose/fr.gd",
	"es": "res://native/wiki/prose/es.gd",
	"it": "res://native/wiki/prose/it.gd",
	"pt": "res://native/wiki/prose/pt.gd",
	"pl": "res://native/wiki/prose/pl.gd",
	"uk": "res://native/wiki/prose/uk.gd",
	"tr": "res://native/wiki/prose/tr.gd",
	"id": "res://native/wiki/prose/id.gd",
	"vi": "res://native/wiki/prose/vi.gd",
	"zh": "res://native/wiki/prose/zh.gd",
	"ja": "res://native/wiki/prose/ja.gd",
	"ko": "res://native/wiki/prose/ko.gd",
}

## Pages of their own: key -> {title, subtitle, category, from}.
var pages := {}
## Key -> blocks; a block is [from, heading, text, list item].
var blocks := {}

static func source(code: String):
	if not LANGUAGES.has(code) or not ResourceLoader.exists(LANGUAGES[code]): return null
	return load(LANGUAGES[code])

func _init(code := "en") -> void:
	var english = source("en")
	if english != null:
		pages = english.PAGES.duplicate(true); blocks = english.BLOCKS.duplicate(true)
	if code == "en": return
	var local = source(code)
	if local == null: return
	for key: String in local.PAGES:
		if pages.has(key):
			for field in ["title", "subtitle"]:
				if not str(local.PAGES[key].get(field, "")).is_empty(): pages[key][field] = local.PAGES[key][field]
	for key: String in local.BLOCKS: blocks[key] = local.BLOCKS[key]

## The blocks of a page a save at the given chapter may read.
func visible(key: String, limit: int) -> Array:
	return blocks.get(key, []).filter(func(block: Array): return int(block[0]) <= limit)

## Every [[key]] or [[key|words]] token in a text: [whole, key, words].
static func tokens(text: String) -> Array:
	var result: Array = []
	for found in RegEx.create_from_string("\\[\\[([a-z]+(?:/[a-z0-9]+)?)(?:\\|([^\\]]*))?\\]\\]").search_all(text):
		result.append([found.get_string(0), found.get_string(1), found.get_string(2)])
	return result
