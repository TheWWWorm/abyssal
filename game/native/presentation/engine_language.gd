extends RefCounted
## The language of the engine's own text: menus, settings, notices and help
## that the imported game does not provide. The game's text always comes from
## the JAR in whatever language that build was made in; this picks the engine
## text to match it, or the language a player chose in Settings.
##
## Every catalog maps the English source text to its translation. Code marks
## engine text with tr() (or translate() where no Object is at hand); text
## without an entry stays English. tools/engine_text.py checks the catalogs
## against the code.

## Code, name in its own language, catalog script. English has no catalog.
const LANGUAGES := [
	["en","English",""],
	["ru","Русский","res://native/locale/ru.gd"],
	["uk","Українська","res://native/locale/uk.gd"],
	["de","Deutsch","res://native/locale/de.gd"],
	["fr","Français","res://native/locale/fr.gd"],
	["es","Español","res://native/locale/es.gd"],
	["pt","Português (Brasil)","res://native/locale/pt.gd"],
	["it","Italiano","res://native/locale/it.gd"],
	["pl","Polski","res://native/locale/pl.gd"],
	["tr","Türkçe","res://native/locale/tr.gd"],
	["id","Bahasa Indonesia","res://native/locale/id.gd"],
	["vi","Tiếng Việt","res://native/locale/vi.gd"],
	["zh","简体中文","res://native/locale/zh.gd"],
	["ja","日本語","res://native/locale/ja.gd"],
	["ko","한국어","res://native/locale/ko.gd"],
]

## The interface font has no CJK glyphs and the web build has no system
## fonts, so these languages carry a subset of Noto Sans CJK with every
## character their catalog uses. tools/engine_text.py fonts writes them.
const FONTS := {"zh":"res://native/locale/noto_sans_sc.otf","ja":"res://native/locale/noto_sans_jp.otf","ko":"res://native/locale/noto_sans_kr.otf"}

## What the settings file holds when the engine follows the game's language.
const AUTO := "auto"

static var current := "en"
static var loaded := {}

static func codes() -> Array:
	return LANGUAGES.map(func(entry): return entry[0])

static func native_name(code: String) -> String:
	for entry in LANGUAGES:
		if entry[0]==code: return entry[1]
	return code

static func supported(code: String) -> String:
	"""The catalog for a locale such as pt_BR or zh-Hans, or "" when none fits."""
	var wanted := code.to_lower().replace("-","_")
	if wanted in codes(): return wanted
	var base := wanted.get_slice("_",0)
	return base if base in codes() else ""

static func resolve(setting: String, content_language: String) -> String:
	"""A chosen language wins. Auto follows the imported game, then the system,
	then English."""
	if setting!=AUTO and setting in codes(): return setting
	for candidate in [content_language,OS.get_locale()]:
		var found := supported(str(candidate))
		if not found.is_empty(): return found
	return "en"

static func apply(code: String) -> void:
	if not code in codes(): code="en"
	if not loaded.has(code) and code!="en":
		var path: String=LANGUAGES[codes().find(code)][2]
		var catalog := Translation.new();catalog.locale=code
		var source: Dictionary=load(path).TEXT
		for key in source: catalog.add_message(key,source[key])
		TranslationServer.add_translation(catalog);loaded[code]=catalog
	current=code
	TranslationServer.set_locale(code)
	# The names in the language list need every script whatever the language.
	var fallbacks: Array[Font]=[]
	for script_code in [code]+FONTS.keys().filter(func(other): return other!=code):
		var font := cjk_font(script_code)
		if font!=null: fallbacks.append(font)
	ThemeDB.fallback_font.fallbacks=fallbacks

static func cjk_font(code: String) -> Font:
	"""The bundled glyphs for a language, or null. An export keeps the file
	as it is, so the raw font is read in both a source run and a build."""
	if not FONTS.has(code): return null
	if loaded.has("font:"+code): return loaded["font:"+code]
	var font := FontFile.new()
	if font.load_dynamic_font(FONTS[code])!=OK: return null
	loaded["font:"+code]=font
	return font

static func translate(text: String) -> String:
	"""tr() for code with no Object at hand, such as a static function."""
	return String(TranslationServer.translate(text))

# ------------------------------------------------- the imported game's language

## Words common in running text of each Latin-script language and rare in the
## others. A localized build often keeps the en folder name, so the text itself
## is read as well.
const COMMON_WORDS := {
	"en":["the","and","you","your","to","of","is","with"],
	"de":["der","die","und","das","sie","nicht","mit","ist"],
	"fr":["le","les","des","vous","et","est","une","pour"],
	"es":["el","los","las","que","para","una","con","del"],
	"it":["il","della","che","per","una","sono","non","gli"],
	"pt":["os","que","para","uma","não","você","com","seu"],
	"pl":["się","nie","jest","na","że","do","jak","przez"],
	"tr":["ve","bir","bu","için","ile","çok","daha","olarak"],
	"id":["yang","dan","untuk","dengan","anda","ini","tidak","dari"],
	"vi":["và","của","bạn","không","có","được","những","một"],
}

static func content_language(folder: String, strings: Array) -> String:
	"""The language of an imported build: its localisation folder name, unless
	the text says otherwise. Fan builds commonly replace the English text but
	keep the en folder."""
	var named := folder.to_lower()
	var sample := ""
	for value in strings:
		sample+=" "+str(value)
		if sample.length()>20000: break
	var cyrillic := 0;var han := 0;var kana := 0;var hangul := 0;var latin := 0
	for character in sample:
		var c := character.unicode_at(0)
		if c>=0x400 and c<=0x4ff: cyrillic+=1
		elif c>=0x3040 and c<=0x30ff: kana+=1
		elif c>=0xac00 and c<=0xd7af: hangul+=1
		elif c>=0x4e00 and c<=0x9fff: han+=1
		elif (c>=0x41 and c<=0x5a) or (c>=0x61 and c<=0x7a): latin+=1
	if cyrillic>latin:
		# Ukrainian letters that Russian does not use.
		for letter in ["і","ї","є","ґ"]:
			if sample.count(letter)>sample.length()/2000: return "uk"
		return named if named in ["ru","uk","be","bg","sr"] else "ru"
	if kana>0 and kana*4>han: return "ja"
	if hangul>latin: return "ko"
	if han>latin: return "zh"
	if named!="en" and not named.is_empty(): return named
	var words := {}
	for word in sample.to_lower().replace("\n"," ").split(" ",false):
		var bare := word.strip_edges().trim_suffix(".").trim_suffix(",").trim_suffix("!").trim_suffix("?")
		words[bare]=int(words.get(bare,0))+1
	var best := "en";var best_score := 0
	for code in COMMON_WORDS:
		var score := 0
		for word in COMMON_WORDS[code]: score+=int(words.get(word,0))
		if score>best_score: best=code;best_score=score
	return best
