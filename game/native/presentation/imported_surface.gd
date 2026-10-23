extends RefCounted
## Runtime-only material hints inferred from the user's imported color atlas.
## R: shallow relief, G: roughness, B: small warm lights, A: dark glazing.
## Vessel materials distinguish cabin glass from lamp lenses sharing this tile.
## Albedo is untouched.
static func derive(source: Image, atlas_size: Vector2=Vector2(128,128)) -> Image:
	var width := source.get_width();var height := source.get_height()
	var count := width*height
	var luma := PackedFloat32Array();luma.resize(count)
	var candidates := PackedByteArray();candidates.resize(count)
	var lights := PackedByteArray();lights.resize(count)
	var visited := PackedByteArray();visited.resize(count)
	for y in height:
		for x in width:
			var c := source.get_pixel(x,y);var i := y*width+x
			luma[i]=c.r*.2126+c.g*.7152+c.b*.0722
			candidates[i]=int(c.a>.5 and c.r>.45 and c.r-c.b>.08 and c.g-c.b>.05 and c.g>c.r*.65)
	# Broad painted panels are not lamps. Keep only small, compact warm islands
	# surrounded by darker texture, independently of atlas size or coordinates.
	for first in count:
		if candidates[first]==0 or visited[first]!=0:continue
		var component: Array[int]=[first];visited[first]=1;var cursor := 0
		var low := Vector2i(first%width,first/width);var high := low
		while cursor<component.size():
			var i: int=component[cursor];cursor+=1
			var x := i%width;var y := i/width
			low=low.min(Vector2i(x,y));high=high.max(Vector2i(x,y))
			for step in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
				var p: Vector2i=Vector2i(x,y)+step
				if p.x<0 or p.x>=width or p.y<0 or p.y>=height:continue
				var next := p.y*width+p.x
				if candidates[next]!=0 and visited[next]==0:visited[next]=1;component.append(next)
		var extent := high-low+Vector2i.ONE
		if component.size()<=maxi(12,count/256) and maxi(extent.x,extent.y)<=maxi(6,mini(width,height)/10):
			for i in component:lights[i]=1
	# Infer geometry at the imported atlas's scale. A three-pixel kernel on
	# an 8x replacement would otherwise turn paint grain into rapidly changing
	# normals. Keep the sharper colour, emission and glass masks independent.
	var relief := relief_image(luma,width,height,atlas_size)
	var enlarged := width>atlas_size.x or height>atlas_size.y
	# Smooth height ramps need more than eight bits: quantizing them again at
	# replacement resolution would reintroduce steps in the screen derivative.
	var result := Image.create(width,height,false,Image.FORMAT_RGBAH if enlarged else Image.FORMAT_RGBA8)
	for y in height:
		for x in width:
			var i := y*width+x;var c := source.get_pixel(x,y)
			var blurred := relief.get_pixel(x,y).r
			var saturation := maxf(c.r,maxf(c.g,c.b))-minf(c.r,minf(c.g,c.b))
			var roughness := clampf(.68-luma[i]*.16+saturation*.18,.48,.82)
			# The original cockpit pane sits inside a metal frame, immediately
			# above the separate grille tile. Scale UVs for higher-resolution mods.
			var uv := (Vector2(x,y)+Vector2.ONE*.5)*atlas_size/Vector2(width,height)-Vector2.ONE*.5
			var glass := float(uv.x>=50 and uv.x<=59 and uv.y>=99 and uv.y<=108)*(1.0-smoothstep(.10,.24,luma[i]))
			result.set_pixel(x,y,Color(lerpf(blurred,.5,lights[i]),roughness,float(lights[i])*smoothstep(.35,.8,luma[i]),glass))
	result.generate_mipmaps()
	return result

static func relief_image(luma: PackedFloat32Array, width: int, height: int, atlas_size: Vector2) -> Image:
	var coarse := Image.create_from_data(width,height,false,Image.FORMAT_RF,luma.to_byte_array())
	var w := mini(width,maxi(1,roundi(atlas_size.x)))
	var h := mini(height,maxi(1,roundi(atlas_size.y)))
	if w!=width or h!=height:coarse.resize(w,h,Image.INTERPOLATE_TRILINEAR)
	var filtered := Image.create(w,h,false,Image.FORMAT_RF)
	for y in h:
		for x in w:
			var value := 0.0
			for oy in range(-1,2):
				for ox in range(-1,2):value+=coarse.get_pixel(clampi(x+ox,0,w-1),clampi(y+oy,0,h-1)).r/9.0
			filtered.set_pixel(x,y,Color(value,0,0))
	if w!=width or h!=height:filtered.resize(width,height,Image.INTERPOLATE_BILINEAR)
	return filtered
