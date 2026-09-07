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
func portrait(layers: Array) -> Texture2D:
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
