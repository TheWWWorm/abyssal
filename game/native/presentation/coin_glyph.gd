extends RefCounted
## The phone game wrote money with a gold coin: glyph 4 of its font stood for
## "$" in every text, and prices drew coin.png after the number (bf). The
## imported coin joins the interface font as a private-use character, so a
## label, a button or a drawn string can carry it like any letter. Without the
## image (a build that lacks it) the engine's "cr" stays.
const CHAR := "\uE000"
## The coin's 7 pixels become 14 at the font's base size of 16; the font
## scales with the text it sits in.
const BASE := 16
const SCALE := 2
static var font: FontFile = null
static var root := ""
static var amount := RegEx.create_from_string("(\\d+)\\s*(?:cr|CR|Cr|кр|Кр|КР)(?![\\p{L}])")
static var leading := RegEx.create_from_string("(?<![\\p{L}])(?:Cr|CR|cr|Кр|кр|КР)\\s+(\\d+)")
static var dollar := RegEx.create_from_string("\\s?\\$")

static func install(content_root: String) -> void:
	"""Build the coin glyph from a content cache and add it to the interface
	font's fallbacks. Once per cache; a reimport may bring another coin."""
	if content_root==root and font!=null:return
	root=content_root;font=null
	var path:=content_root.path_join("data/interface/coin.png")
	if FileAccess.file_exists(path):
		var source:=Image.load_from_file(path)
		if source!=null and not source.is_empty():font=build(source)
	refresh()

static func build(source: Image) -> FontFile:
	var coin:=source.duplicate() as Image
	coin.convert(Image.FORMAT_RGBA8)
	var side:=maxi(coin.get_width(),coin.get_height())*SCALE
	coin.resize(coin.get_width()*SCALE,coin.get_height()*SCALE,Image.INTERPOLATE_NEAREST)
	# A transparent border keeps filtering from reaching the atlas edge.
	var sheet:=Image.create(side+4,side+4,false,Image.FORMAT_RGBA8)
	sheet.blit_rect(coin,Rect2i(Vector2i.ZERO,coin.get_size()),Vector2i(2,2))
	var result:=FontFile.new()
	result.fixed_size=BASE
	result.fixed_size_scale_mode=TextServer.FIXED_SIZE_SCALE_ENABLED
	result.allow_system_fallback=false
	var size:=Vector2i(BASE,0)
	var glyph:=CHAR.unicode_at(0)
	result.set_cache_ascent(0,BASE,13)
	result.set_cache_descent(0,BASE,3)
	result.set_texture_image(0,size,0,sheet)
	result.set_glyph_texture_idx(0,size,glyph,0)
	result.set_glyph_uv_rect(0,size,glyph,Rect2(2,2,coin.get_width(),coin.get_height()))
	result.set_glyph_size(0,size,glyph,Vector2(coin.get_size()))
	# Sitting on the baseline with the height of a capital, a little apart.
	result.set_glyph_offset(0,size,glyph,Vector2(1,-coin.get_height()+1))
	result.set_glyph_advance(0,BASE,glyph,Vector2(coin.get_width()+2,0))
	return result

static func refresh() -> void:
	var fallbacks: Array[Font]=[]
	for other in ThemeDB.fallback_font.fallbacks:
		if other is FontFile and other.has_meta("coin_glyph"):continue
		fallbacks.append(other)
	if font!=null:
		font.set_meta("coin_glyph",true)
		fallbacks.append(font)
	ThemeDB.fallback_font.fallbacks=fallbacks

static func ready() -> bool:
	return font!=null

static func money(value: int) -> String:
	"""An amount as the phone game showed it: the number, then the coin."""
	return "%d %s"%[value,CHAR] if ready() else "%d cr"%value

static func coins(text: String) -> String:
	"""Translated engine text with its "cr" amounts drawn with the coin."""
	if not ready():return text
	text=leading.sub(text,"$1 "+CHAR,true)
	return amount.sub(text,"$1 "+CHAR,true)

static func dollars(text: String) -> String:
	"""Imported text, whose "$" was the coin glyph of the phone's font."""
	if not text.contains("$"):return text
	return dollar.sub(text," "+CHAR,true) if ready() else dollar.sub(text," Cr",true)
