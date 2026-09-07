extends RefCounted
## Runtime-only material hints inferred from the user's imported color atlas.
## R: shallow relief, G: roughness, B: small warm lights. Albedo is untouched.
static func derive(source: Image) -> Image:
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
	var result := Image.create(width,height,false,Image.FORMAT_RGBA8)
	for y in height:
		for x in width:
			var i := y*width+x;var c := source.get_pixel(x,y)
			var blurred := 0.0
			for oy in range(-1,2):
				for ox in range(-1,2):blurred+=luma[clampi(y+oy,0,height-1)*width+clampi(x+ox,0,width-1)]/9.0
			var saturation := maxf(c.r,maxf(c.g,c.b))-minf(c.r,minf(c.g,c.b))
			var roughness := clampf(.68-luma[i]*.16+saturation*.18,.48,.82)
			result.set_pixel(x,y,Color(lerpf(blurred,.5,lights[i]),roughness,float(lights[i])*smoothstep(.35,.8,luma[i]),1))
	result.generate_mipmaps()
	return result
