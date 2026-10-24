extends RefCounted
## CPU renderer for the shaded vector recipe. Work yields at scanline boundaries
## so the same implementation stays cancellable in single-threaded Web builds.
## Geometry, gradients and density contours are fitted artwork; no raster
## textures or pixel residuals are bundled in the recipe.
signal progress(value: float, stage: String)
const SCALE := 8
const SIDE := 128*SCALE
const Geometry = preload("res://native/textures/source_geometry.gd")
const Normals = preload("res://native/textures/normal_recipe.gd")
var cancel_lock := Mutex.new()
var cancelled_value := false
var cancelled: bool:
	get:
		cancel_lock.lock();var value := cancelled_value;cancel_lock.unlock();return value
	set(value):
		cancel_lock.lock();cancelled_value=value;cancel_lock.unlock()
var threaded := false
var tree: SceneTree
var deadline := 0
var completed := 0
var total := 1
var stage := ""
var peak_slice_usec := 0
var slice_started := 0

func checkpoint() -> void:
	if cancelled:return
	var now := Time.get_ticks_usec()
	if now<deadline:return
	peak_slice_usec=maxi(peak_slice_usec,now-slice_started)
	progress.emit(minf(.98,float(completed)/total),stage)
	if not threaded:await tree.process_frame
	slice_started=Time.get_ticks_usec();deadline=slice_started+6000

func render(sources: Dictionary, recipe: Dictionary, scene_tree: SceneTree) -> Dictionary:
	tree=scene_tree;total=0;completed=0
	for kind in ["deep","fx"]:
		for patch in recipe.atlases[kind]:total+=patch.get("shapes",[]).size()+2
		for field in recipe.soft_fields[kind]:
			total+=field.gaussians.size()+2
			for contour in field.get("contour_fields",[]):total+=contour.layers.size()
		total+=recipe.colour_curves[kind].size()+1
	total+=24
	var result := {}
	slice_started=Time.get_ticks_usec();deadline=slice_started+6000
	for kind in ["deep","fx"]:
		stage=kind
		var source: Image=sources[kind]
		var out := source.duplicate() as Image
		out.convert(Image.FORMAT_RGBAF);out.resize(SIDE,SIDE,Image.INTERPOLATE_BILINEAR)
		for patch in recipe.atlases[kind]:
			if cancelled:return {}
			await render_patch(out,source,patch)
		for curve in recipe.colour_curves[kind]:
			if cancelled:return {}
			await render_curve(out,source,curve)
		for field in recipe.soft_fields[kind]:
			if cancelled:return {}
			await render_field(out,source,field)
		if kind=="fx":await render_bubble(out,source,recipe.bubble)
		else:await Geometry.apply(out,source,self)
		out.convert(Image.FORMAT_RGBA8);result[kind]=out
		completed+=1;await checkpoint()
	if cancelled:return {}
	stage="normals";result["deep.normal"]=await Normals.generate(self)
	return {} if cancelled else result

static func rect_of(values: Array) -> Rect2i:
	return Rect2i(int(values[0])*SCALE,int(values[1])*SCALE,int(values[2])*SCALE,int(values[3])*SCALE)

static func source_gain(source: Image, region: Array, reference: Variant) -> Vector3:
	var sum := Vector3.ZERO
	for y in range(int(region[1]),int(region[1]+region[3])):
		for x in range(int(region[0]),int(region[0]+region[2])):
			var c := source.get_pixel(x,y);sum+=Vector3(c.r,c.g,c.b)
	sum/=float(region[2]*region[3])
	var ref := Vector3(reference[0],reference[1],reference[2]) if reference is Array else Vector3.ONE*float(reference)
	return ((sum+Vector3.ONE*.025)/(ref+Vector3.ONE*.025)).clamp(Vector3.ONE*.2,Vector3.ONE*3)

## Even/odd contours, four coverage samples per output pixel. Every contour
## uses original-atlas coordinates, independent of the output resolution.
func coverage(paths: Array, area: Rect2i) -> PackedByteArray:
	var mask := PackedByteArray();mask.resize(area.size.x*area.size.y)
	var edges: Array[Vector4]=[]
	for path in paths:
		for i in path.size():
			var a: Array=path[i];var b: Array=path[(i+1)%path.size()]
			if a[1]!=b[1]:edges.append(Vector4(a[0]*SCALE*2,a[1]*SCALE*2,b[0]*SCALE*2,b[1]*SCALE*2))
	for sy in range(area.position.y*2,area.end.y*2):
		if cancelled:return mask
		var crossings := PackedFloat32Array();var scan := float(sy)+.5
		for edge in edges:
			if scan>=minf(edge.y,edge.w) and scan<maxf(edge.y,edge.w):
				crossings.append(edge.x+(scan-edge.y)*(edge.z-edge.x)/(edge.w-edge.y))
		crossings.sort()
		var row := (sy/2-area.position.y)*area.size.x
		for i in range(0,crossings.size()-1,2):
			var left := maxi(area.position.x*2,ceili(crossings[i]-.5))
			var right := mini(area.end.x*2,ceili(crossings[i+1]-.5))
			for sx in range(left,right):mask[row+sx/2-area.position.x]+=1
		await checkpoint()
	return mask

static func noise(x: int, y: int, seed_value: int) -> float:
	# Integer mixing avoids platform-dependent random-number streams.
	var h := (x*374761393+y*668265263+seed_value*1442695041)&0x7fffffff
	h=((h^(h>>13))*1274126177)&0x7fffffff
	return float(h^(h>>16))/1073741824.0-1.0

static func grain(x: int, y: int, seed_value: int) -> float:
	return (noise(x,y,seed_value)*.8+noise(x/2,y/2,seed_value+1)*.5+noise(x/6,y/6,seed_value+2)*.16)*1.8

func render_patch(out: Image, source: Image, patch: Dictionary) -> void:
	var box := rect_of(patch.rect);var area := Rect2i(Vector2i.ZERO,box.size)
	var colors := PackedVector3Array();colors.resize(box.size.x*box.size.y)
	var weights := PackedFloat32Array();weights.resize(colors.size())
	var gain := source_gain(source,patch.rect,patch.source_mean)
	completed+=1
	if patch.has("mask_paths"):
		var alpha := await coverage(patch.mask_paths,area)
		for y in box.size.y:
			for x in box.size.x:out.set_pixel(box.position.x+x,box.position.y+y,Color(0,0,0,alpha[y*box.size.x+x]*.25))
			await checkpoint()
		completed+=1;return
	for shape in patch.shapes:
		if cancelled:return
		var b: Array=shape.bounds
		var lo := Vector2i(floori(b[0]*SCALE)-2,floori(b[1]*SCALE)-2)
		var hi := Vector2i(ceili((b[0]+b[2])*SCALE)+2,ceili((b[1]+b[3])*SCALE)+2)
		var bound := Rect2i(lo,hi-lo).intersection(area)
		var mask := await coverage(shape.paths,bound)
		var coefficients: Array[Vector3]=[]
		for c in shape.colour:coefficients.append(Vector3(c[0],c[1],c[2]))
		var low := Vector3(shape.limits[0][0],shape.limits[0][1],shape.limits[0][2])
		var high := Vector3(shape.limits[1][0],shape.limits[1][1],shape.limits[1][2])
		var degree := int(shape.degree)
		for y in range(bound.position.y,bound.end.y):
			var ny: float= ((y+.5)/SCALE-b[1])/b[3]*2-1
			var yp := PackedFloat64Array([1,ny,ny*ny,ny*ny*ny,ny*ny*ny*ny])
			for x in range(bound.position.x,bound.end.x):
				var weight := mask[(y-bound.position.y)*bound.size.x+x-bound.position.x]*.25
				if weight==0:continue
				var nx: float= ((x+.5)/SCALE-b[0])/b[2]*2-1
				var color := Vector3.ZERO;var term := 0;var xp := 1.0
				for i in degree+1:
					for j in degree+1-i:
						color+=coefficients[term]*(xp*yp[j]);term+=1
					xp*=nx
				color=((color.clamp(low,high)+Vector3.ONE*grain(x,y,int(patch.seed))*float(shape.grain))*gain).clamp(Vector3.ZERO,Vector3.ONE)
				var at := y*box.size.x+x
				colors[at]+=color*weight;weights[at]+=weight
			await checkpoint()
		completed+=1
	# Fill only uncovered numerical seams from a covered neighbour. Preserve
	# alpha separately, so transparent regions never become opaque.
	for y in box.size.y:
		for x in box.size.x:
			var at := y*box.size.x+x;var weight := weights[at]
			var color := colors[at]/maxf(weight,.000001)
			if weight<.01:
				var best := INF
				for dy in range(-3,4):
					for dx in range(-3,4):
						var ax := x+dx;var ay := y+dy
						if ax<0 or ay<0 or ax>=box.size.x or ay>=box.size.y:continue
						var near := ay*box.size.x+ax;var distance := dx*dx+dy*dy
						if weights[near]>.01 and distance<best:best=distance;color=colors[near]/weights[near]
			var alpha := minf(1,weight) if patch.transparent else 1.0
			out.set_pixel(box.position.x+x,box.position.y+y,Color(color.x,color.y,color.z,alpha))
		await checkpoint()
	completed+=1

func render_curve(out: Image, source: Image, curve: Dictionary) -> void:
	var box := rect_of(curve.rect)
	var base := source.get_region(Rect2i(int(curve.rect[0]),int(curve.rect[1]),int(curve.rect[2]),int(curve.rect[3])))
	base.convert(Image.FORMAT_RGBF);base.resize(box.size.x,box.size.y,Image.INTERPOLATE_BILINEAR)
	var sigma := float(curve.get("blur_sigma",0))*SCALE
	var radius := ceili(4*sigma);var kernel := PackedFloat32Array();var sum := 0.0
	for i in range(-radius,radius+1):var v := exp(-.5*i*i/(sigma*sigma));kernel.append(v);sum+=v
	for i in kernel.size():kernel[i]/=sum
	for axis in 2:
		var temp := base.duplicate() as Image
		for y in box.size.y:
			for x in box.size.x:
				var c := Color(0,0,0,0)
				for i in range(-radius,radius+1):
					c+=base.get_pixel(clampi(x+i if axis==0 else x,0,box.size.x-1),clampi(y+i if axis==1 else y,0,box.size.y-1))*kernel[i+radius]
				temp.set_pixel(x,y,c)
			await checkpoint()
		base=temp
	for y in box.size.y:
		for x in box.size.x:
			var rgb := base.get_pixel(x,y);var color := Color(0,0,0,1)
			for ch in 3:
				var p := 1.0
				for v in curve.coefficients[ch]:color[ch]+=v*p;p*=rgb[ch]
			out.set_pixel(box.position.x+x,box.position.y+y,color)
		await checkpoint()
	completed+=1

func render_field(out: Image, source: Image, field: Dictionary) -> void:
	var box := rect_of(field.rect);var area := Rect2i(Vector2i.ZERO,box.size)
	var colors := PackedVector3Array();colors.resize(box.size.x*box.size.y)
	colors.fill(Vector3(field.base[0],field.base[1],field.base[2]))
	var contours: Array=field.get("contour_fields",[])
	# Three colour contours replace the Gaussian colours entirely.
	if contours.size()!=3:
		for gaussian in field.gaussians:
			if cancelled:return
			var cx := float(gaussian[0])*SCALE;var cy := float(gaussian[1])*SCALE;var radius := float(gaussian[2])*SCALE
			var color := Vector3(gaussian[3],gaussian[4],gaussian[5])
			var low := Vector2i(maxi(0,floori(cx-radius*5)),maxi(0,floori(cy-radius*5)))
			var high := Vector2i(mini(box.size.x,ceili(cx+radius*5)),mini(box.size.y,ceili(cy+radius*5)))
			var ex := PackedFloat32Array();ex.resize(box.size.x)
			for x in range(low.x,high.x):ex[x]=exp(-pow(x+.5-cx,2)/(2*radius*radius))
			for y in range(low.y,high.y):
				var ey := exp(-pow(y+.5-cy,2)/(2*radius*radius))
				for x in range(low.x,high.x):colors[y*box.size.x+x]+=color*(ex[x]*ey)
				await checkpoint()
			completed+=1
	else:completed+=field.gaussians.size()
	for contour in contours:
		var density := PackedFloat32Array();density.resize(colors.size())
		for layer in contour.layers:
			if cancelled:return
			var mask := await coverage(layer,area)
			for i in mask.size():density[i]+=mask[i]*(.25*float(contour.step))
			completed+=1;await checkpoint()
		for i in colors.size():
			if contour.channel is String:
				var c := colors[i];var hue := (c/maxf(c.dot(Vector3(.2126,.7152,.0722)),.005)).clamp(Vector3.ZERO,Vector3.ONE*3)
				colors[i]=hue*density[i]
			else:
				var c := colors[i];c[int(contour.channel)]=density[i];colors[i]=c
			if i%2048==0:await checkpoint()
	var gain := source_gain(source,field.rect,field.source_mean)
	for y in box.size.y:
		for x in box.size.x:
			var c := colors[y*box.size.x+x]*gain
			var old := out.get_pixel(box.position.x+x,box.position.y+y)
			if field.has("feather"):
				var edge := minf(minf(x+.5,y+.5),minf(box.size.x-x-.5,box.size.y-y-.5))/SCALE
				c=Vector3(old.r,old.g,old.b).lerp(c,clampf(edge/field.feather,0,1))
			out.set_pixel(box.position.x+x,box.position.y+y,Color(c.x,c.y,c.z,old.a))
		await checkpoint()
	completed+=2

func render_bubble(out: Image, source: Image, bubble: Dictionary) -> void:
	var box := rect_of(bubble.rect);var gain := source_gain(source,bubble.rect,bubble.source_mean)
	var brightness := (gain.x+gain.y+gain.z)/3
	for y in box.size.y:
		for x in box.size.x:
			var px := (x+.5)/SCALE;var py := (y+.5)/SCALE
			var d := Vector2(px-bubble.circle[0],py-bubble.circle[1]);var rr := d.length()/float(bubble.circle[2]);var angle := d.angle();var value := 0.0
			for i in bubble.profiles.size():
				var profile: Array=bubble.profiles[i];var c: Array=bubble.coefficients[i]
				value+=exp(-.5*pow((rr-profile[0])/profile[1],2))*(c[0]+c[1]*sin(angle)+c[2]*cos(angle))
			for reflection in bubble.reflections:
				var q := float(bubble.reference_scale);var dx: float= px-reflection[0]/q;var dy: float= py-reflection[1]/q
				var ux: float= cos(reflection[4])*dx+sin(reflection[4])*dy;var uy: float= -sin(reflection[4])*dx+cos(reflection[4])*dy
				value+=reflection[6]*exp(-.5*pow(pow(ux/(reflection[2]/q),2)+pow(uy/(reflection[3]/q),2),reflection[5]))
			value*=brightness;out.set_pixel(box.position.x+x,box.position.y+y,Color(value,value,value,1))
		await checkpoint()
