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
	coin.resize(coin.get_width()*SCALE,coin.get_height()*SCALE,Image.INTERPOLATE_NEAREST)
	# A colour font keeps its gold in any text colour; a plain image glyph
	# would be tinted by it, green in a receipt and red in a debt.
	var colour:=FontFile.new()
	colour.data=colour_font(coin)
	colour.fixed_size=BASE
	colour.fixed_size_scale_mode=TextServer.FIXED_SIZE_SCALE_ENABLED
	colour.allow_system_fallback=false
	if colour.has_char(CHAR.unicode_at(0)):return colour
	return image_font(coin)

static func image_font(coin: Image) -> FontFile:
	"""The coin as an image glyph, for a text server without FreeType."""
	var side:=maxi(coin.get_width(),coin.get_height())
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

static func colour_font(coin: Image) -> PackedByteArray:
	"""A one-glyph OpenType colour font (CBDT/CBLC, as colour emoji fonts
	are made) that maps CHAR to the coin's PNG, one strike of BASE pixels.
	The text server leaves the colours of such a glyph alone, where an
	image glyph added to a FontFile takes the colour of the text around it."""
	var png:=coin.save_png_to_buffer()
	var w:=coin.get_width();var h:=coin.get_height()
	var ascent:=BASE-3;var descent:=3
	var tables:={}
	# The bitmap: glyph 1, small metrics then the PNG (image format 17).
	var cbdt:=Writer.new();cbdt.u16(3);cbdt.u16(0)
	cbdt.u8(h);cbdt.u8(w);cbdt.s8(1);cbdt.s8(h-1);cbdt.u8(w+2);cbdt.u32(png.size());cbdt.bytes(png)
	tables["CBDT"]=cbdt.data
	var cblc:=Writer.new();cblc.u16(3);cblc.u16(0);cblc.u32(1)
	cblc.u32(8+48);cblc.u32(24);cblc.u32(1);cblc.u32(0)
	for direction in 2:
		for value in [ascent,-descent,w+2,1,0,0,0,0,ascent,-descent,0,0]:cblc.s8(value)
	cblc.u16(1);cblc.u16(1);cblc.u8(BASE);cblc.u8(BASE);cblc.u8(32);cblc.s8(1)
	# One index subtable (format 1) for glyph 1 at the strike's data.
	cblc.u16(1);cblc.u16(1);cblc.u32(8)
	cblc.u16(1);cblc.u16(17);cblc.u32(4);cblc.u32(0);cblc.u32(9+png.size())
	tables["CBLC"]=cblc.data
	var cmap:=Writer.new();cmap.u16(0);cmap.u16(1);cmap.u16(3);cmap.u16(10);cmap.u32(12)
	cmap.u16(12);cmap.u16(0);cmap.u32(28);cmap.u32(0);cmap.u32(1)
	cmap.u32(CHAR.unicode_at(0));cmap.u32(CHAR.unicode_at(0));cmap.u32(1)
	tables["cmap"]=cmap.data
	var head:=Writer.new();head.u32(0x00010000);head.u32(0x00010000);head.u32(0);head.u32(0x5F0F3CF5)
	head.u16(0x000B);head.u16(BASE);head.u32(0);head.u32(0);head.u32(0);head.u32(0)
	for value in [0,-descent,w+2,ascent]:head.s16(value)
	head.u16(0);head.u16(8);head.s16(2);head.s16(0);head.s16(0)
	tables["head"]=head.data
	var hhea:=Writer.new();hhea.u32(0x00010000);hhea.s16(ascent);hhea.s16(-descent);hhea.s16(0)
	hhea.u16(w+2);hhea.s16(0);hhea.s16(0);hhea.s16(w+1);hhea.s16(1);hhea.s16(0);hhea.s16(0)
	for _reserved in 4:hhea.s16(0)
	hhea.s16(0);hhea.u16(2)
	tables["hhea"]=hhea.data
	var hmtx:=Writer.new();hmtx.u16(w+2);hmtx.s16(0);hmtx.u16(w+2);hmtx.s16(1)
	tables["hmtx"]=hmtx.data
	var maxp:=Writer.new();maxp.u32(0x00005000);maxp.u16(2)
	tables["maxp"]=maxp.data
	var post:=Writer.new();post.u32(0x00030000);post.u32(0);post.s16(-1);post.s16(1);post.u32(0)
	for _memory in 4:post.u32(0)
	tables["post"]=post.data
	# The table directory, then each table on a four-byte boundary.
	var tags:=tables.keys();tags.sort()
	var font:=Writer.new();font.u32(0x00010000);font.u16(tags.size())
	var power:=1;var exponent:=0
	while power*2<=tags.size():power*=2;exponent+=1
	font.u16(power*16);font.u16(exponent);font.u16(tags.size()*16-power*16)
	var at:=12+tags.size()*16
	for tag in tags:
		var body: PackedByteArray=tables[tag]
		font.bytes(tag.to_ascii_buffer());font.u32(checksum(body));font.u32(at);font.u32(body.size())
		at+=(body.size()+3)&~3
	for tag in tags:
		var body: PackedByteArray=tables[tag]
		font.bytes(body)
		while font.data.size()%4!=0:font.u8(0)
	return font.data

static func checksum(body: PackedByteArray) -> int:
	var total:=0
	for index in range(0,body.size(),4):
		var word:=0
		for offset in 4:word=(word<<8)|(body[index+offset] if index+offset<body.size() else 0)
		total=(total+word)&0xffffffff
	return total

## Big-endian writing for the font tables.
class Writer:
	var data:=PackedByteArray()
	func u8(value: int) -> void:data.append(value&0xff)
	func s8(value: int) -> void:data.append(value&0xff)
	func u16(value: int) -> void:u8(value>>8);u8(value)
	func s16(value: int) -> void:u16(value&0xffff)
	func u32(value: int) -> void:u16((value>>16)&0xffff);u16(value&0xffff)
	func bytes(value: PackedByteArray) -> void:data.append_array(value)
