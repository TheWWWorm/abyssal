extends RefCounted
## Owner-imported UI images stay in the JAR cache, never in the original art pack.
var root := ""
var textures := {}
func image(path: String) -> Texture2D:
	if textures.has(path): return textures[path]
	var file := root.path_join("data/interface/"+path+".png")
	if not FileAccess.file_exists(file): return null
	var pixels := Image.load_from_file(file)
	if pixels==null: return null
	var texture := ImageTexture.create_from_image(pixels)
	textures[path]=texture
	return texture
func item(id: int, kind: String="goods") -> Texture2D:
	return image(("equipment/slot_" if kind=="equipment" else "equipment/u" if kind=="ships" else "cargo_")+str(id)+("a" if kind=="ships" else ""))
func portrait(layers: Array, photo: String="") -> Texture2D:
	"""A face as the original draws it (ab.a): its layers over one another in
	order, or an imported picture in their place (dc.a draws either)."""
	if not photo.is_empty():
		var photo_key := "photo:"+photo.md5_text()
		if textures.has(photo_key): return textures[photo_key]
		var pixels := photo_image(photo)
		if pixels!=null:
			textures[photo_key]=ImageTexture.create_from_image(pixels)
			return textures[photo_key]
	if layers.is_empty(): return null
	if int(layers[0])<0: return image("mai")
	var key := "portrait:"+str(layers)
	if textures.has(key): return textures[key]
	var composite := Image.create(40,40,false,Image.FORMAT_RGBA8)
	composite.fill(Color.TRANSPARENT)
	for layer in layers:
		if int(layer)<0: continue
		var texture := image("faces/"+str(int(layer)))
		if texture!=null:
			var pixels := texture.get_image(); pixels.convert(Image.FORMAT_RGBA8)
			composite.blend_rect(pixels,Rect2i(Vector2i.ZERO,pixels.get_size()),Vector2i.ZERO)
	textures[key]=ImageTexture.create_from_image(composite)
	return textures[key]

## The longest stored portrait picture accepted, in base64 characters.
const PHOTO_TEXT_LIMIT := 16384

static func photo_image(text: String) -> Image:
	"""A stored portrait picture, or null unless it is a 40×40 PNG."""
	if text.is_empty() or text.length()>PHOTO_TEXT_LIMIT or text.length()%4!=0: return null
	if RegEx.create_from_string("^[A-Za-z0-9+/]+={0,2}$").search(text)==null: return null
	var bytes := Marshalls.base64_to_raw(text)
	if bytes.size()<8 or bytes.slice(0,4)!=PackedByteArray([0x89,0x50,0x4e,0x47]): return null
	var pixels := Image.new()
	if pixels.load_png_from_buffer(bytes)!=OK or pixels.get_size()!=Vector2i(40,40): return null
	pixels.convert(Image.FORMAT_RGBA8)
	return pixels

static func make_photo(bytes: PackedByteArray) -> String:
	"""The original's camera portrait (bs.a): the snapshot scaled to the face's
	40 pixels across, its middle cut out square and drawn opaque. Here any PNG,
	JPEG, WebP or BMP will do: its shorter side becomes 40 pixels and the
	middle is kept. Returns the stored form (photo_image), or "" when the file
	is not a picture."""
	var source := Image.new()
	var error := ERR_FILE_UNRECOGNIZED
	if bytes.size()>=8 and bytes.slice(0,4)==PackedByteArray([0x89,0x50,0x4e,0x47]): error=source.load_png_from_buffer(bytes)
	elif bytes.size()>=3 and bytes[0]==0xff and bytes[1]==0xd8: error=source.load_jpg_from_buffer(bytes)
	elif bytes.size()>=12 and bytes.slice(0,4).get_string_from_ascii()=="RIFF" and bytes.slice(8,12).get_string_from_ascii()=="WEBP": error=source.load_webp_from_buffer(bytes)
	elif bytes.size()>=2 and bytes.slice(0,2).get_string_from_ascii()=="BM": error=source.load_bmp_from_buffer(bytes)
	if error!=OK or source.is_empty(): return ""
	if source.is_compressed(): source.decompress()
	source.convert(Image.FORMAT_RGBA8)
	# Halve large pictures first, so the last step reads every pixel.
	while mini(source.get_width(),source.get_height())>=160: source.resize(maxi(1,source.get_width()/2),maxi(1,source.get_height()/2),Image.INTERPOLATE_BILINEAR)
	var scale := 40.0/mini(source.get_width(),source.get_height())
	var size := Vector2i(maxi(40,roundi(source.get_width()*scale)),maxi(40,roundi(source.get_height()*scale)))
	source.resize(size.x,size.y,Image.INTERPOLATE_LANCZOS)
	var photo := Image.create(40,40,false,Image.FORMAT_RGBA8)
	photo.fill(Color.BLACK)
	photo.blend_rect(source,Rect2i((size-Vector2i(40,40))/2,Vector2i(40,40)),Vector2i.ZERO)
	photo.convert(Image.FORMAT_RGB8)
	return Marshalls.raw_to_base64(photo.save_png_to_buffer())

func symbol(path: String) -> Texture2D:
	# The JAR's monochrome instruments use dark ink with transparent cutouts.
	# Recolour their opaque pixels for a readable overlay on dark water.
	var key := "symbol:"+path
	if textures.has(key):return textures[key]
	var source := image(path)
	if source==null:return null
	var pixels := source.get_image()
	for y in pixels.get_height():
		for x in pixels.get_width():
			var alpha := pixels.get_pixel(x,y).a
			pixels.set_pixel(x,y,Color(1,1,1,alpha))
	textures[key]=ImageTexture.create_from_image(pixels)
	return textures[key]
