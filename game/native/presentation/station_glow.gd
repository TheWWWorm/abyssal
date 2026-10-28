extends MultiMeshInstance3D
## A lit station seen from afar. Its window texels and lamp sprites shrink to
## less than a pixel a few hundred metres out, and the water haze takes what
## is left, so a station a kilometre off was a dark block. This draws one soft
## glow for each patch of windows and for each lamp, exactly where the window
## texels and the lamp sprite are on the module, in a single draw for the
## module. The glows fade in only with distance (none where the real lights
## still read), are hidden by whatever hides their place on the hull, keep a
## few pixels on screen, and dim through the same water as the hull. Enhanced
## only; no lights and no shadows.
const Library = preload("res://scripts/model_library.gd")
const Mods = preload("res://native/presentation/mods.gd")
## Distances where the glows begin and finish fading in; station_glow.gdshader
## takes the same values.
const FADE_BEGIN := 380.0
const FADE_END := 1500.0
## Window texels within one cell of this size, on walls facing the same way,
## share a glow.
const CELL := 20.0
## The surface hint (imported_surface.gd) above which a texel is a window.
const WINDOW_HINT := .05

## Window patches of a module resource, per pattern and atlas, in bone space.
static var windows_cache := {}
## The window texels of an atlas: texel, hint and linear colour.
static var texels_cache := {}
static var shared_material: ShaderMaterial
static var shared_quad: QuadMesh

var visual
var built_figure: Node3D
var lamps: Array = []
var sync_clock := 0.0

static func attach(module) -> void:
	"""Gives a station module its distant glow, once."""
	if module.figure==null or module.has_node("StationGlow"):return
	var id := int(module.record.id)
	if id<3300 or id>=3400 or Mods.has_model(str(module.record.model)):return
	var glow := new();glow.name="StationGlow";glow.visual=module
	module.add_child(glow)
	glow.build()

func build() -> void:
	built_figure=visual.figure
	lamps=[]
	var points: Array=[]
	var figure_transform: Transform3D=built_figure.transform
	for patch: Dictionary in windows(visual.library,str(visual.record.model),visual.last_pattern,visual.record.textures):
		var bone: Transform3D=Library.matrix(visual.current_bones[patch.bone]) if patch.bone<visual.current_bones.size() else Transform3D.IDENTITY
		var normal: Vector3=(figure_transform.basis*bone.basis*patch.normal).normalized()
		# Lifted off the wall a little, so the glow is not half inside it.
		var at: Vector3=figure_transform*(bone*patch.position)+normal*.5
		points.append([at,patch.radius,patch.color,patch.strength,normal,0.0])
	for point: Dictionary in built_figure.get_meta("lamps",[]):
		var holder: Node3D=point.node
		var tint: Color=point.lamp.tint
		lamps.append([holder,points.size()])
		points.append([figure_transform*holder.transform.origin,clampf(float(point.lamp.radius)*2.5,4.0,10.0),tint.srgb_to_linear(),1.0 if holder.visible else 0.0,Vector3.UP,1.0])
	if points.is_empty():
		visible=false;set_process(false);return
	if shared_material==null:
		shared_material=ShaderMaterial.new();shared_material.shader=preload("res://native/presentation/station_glow.gdshader")
		shared_quad=QuadMesh.new();shared_quad.size=Vector2.ONE
	var mesh := MultiMesh.new();mesh.transform_format=MultiMesh.TRANSFORM_3D
	mesh.use_colors=true;mesh.use_custom_data=true;mesh.mesh=shared_quad
	mesh.instance_count=points.size()
	for i in points.size():
		var p: Array=points[i]
		mesh.set_instance_transform(i,Transform3D(Basis().scaled(Vector3.ONE*float(p[1])),p[0]))
		var color: Color=p[2];color.a=float(p[3])
		mesh.set_instance_color(i,color)
		var normal: Vector3=p[4]
		mesh.set_instance_custom_data(i,Color(normal.x,normal.y,normal.z,float(p[5])))
	multimesh=mesh;visible=true
	material_override=shared_material
	cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gi_mode=GeometryInstance3D.GI_MODE_DISABLED
	# Nothing to draw near the station: the renderer culls the whole module's
	# glows before the shader would fade them to nothing.
	var reach: float=mesh.get_aabb().size.length()*.5
	visibility_range_begin=maxf(0.0,FADE_BEGIN-reach)
	visibility_range_end=9600.0+reach
	set_process(not lamps.is_empty())

func _process(delta: float) -> void:
	# A station's animation blinks some lamps by hiding them; their glows
	# follow, a few times a second, and only once they can be seen.
	sync_clock-=delta
	if sync_clock>0.0:return
	sync_clock=.1
	if visual.figure!=built_figure:build();return
	var camera := get_viewport().get_camera_3d()
	if camera==null or camera.global_position.distance_to(global_position)<visibility_range_begin:return
	for lamp: Array in lamps:
		var holder: Node3D=lamp[0]
		var color: Color=multimesh.get_instance_color(lamp[1])
		var lit := 1.0 if holder.visible else 0.0
		if color.a!=lit:
			color.a=lit;multimesh.set_instance_color(lamp[1],color)
			var at: Vector3=built_figure.transform*holder.transform.origin
			var place: Transform3D=multimesh.get_instance_transform(lamp[1]);place.origin=at
			multimesh.set_instance_transform(lamp[1],place)

static func windows(library, resource: String, pattern: int, textures: Array) -> Array:
	"""The window patches of a module: each a bone, a position and outward
	normal in that bone's space, a size, the window colour and a strength."""
	var key := str([library.root,resource,pattern,textures])
	if windows_cache.has(key):return windows_cache[key]
	var source: Dictionary=library.data(resource)
	var vertex_bones: Array[int]=[]
	for i in source.bones.size():
		for j in int(source.bones[i].vertices):vertex_bones.append(i)
	var cells := {}
	for polygon: Dictionary in source.polygons:
		if int(polygon.blend)!=0 or int(polygon.texture)<0 or int(polygon.texture)>=textures.size():continue
		if int(polygon.pattern)!=0 and (int(polygon.pattern)&pattern)==0:continue
		var texels: Array=window_texels(library,textures[int(polygon.texture)])
		if texels.is_empty():continue
		var a: Array=polygon.attributes;var indices: Array=polygon.indices
		for t in range(0,indices.size()-2,3):
			var p: Array[Vector3]=[];var uv: Array[Vector2]=[];var n := Vector3.ZERO
			for k in 3:
				var index := int(indices[t+k])
				p.append(Library.point(source.vertices,index*3))
				uv.append(Vector2(float(a[(t+k)*5]),float(a[(t+k)*5+1])))
				if source.normals.size()>index*3+2:n+=Library.point(source.normals,index*3).normalized()
			var face_area := (p[1]-p[0]).cross(p[2]-p[0]).length()*.5
			var e1: Vector2=uv[1]-uv[0];var e2: Vector2=uv[2]-uv[0]
			var uv_area: float=e1.cross(e2)
			if absf(uv_area)<.5 or face_area<=0.0:continue
			if n.length()<.01:n=(p[1]-p[0]).cross(p[2]-p[0])
			n=n.normalized()
			var texel_area: float=face_area/(absf(uv_area)*.5)
			var bone: int=vertex_bones[int(indices[t])]
			var axis := n.abs().max_axis_index()
			var side := axis*2+(1 if n[axis]>0.0 else 0)
			var low: Vector2=uv[0].min(uv[1]).min(uv[2])-Vector2.ONE*.001;var high: Vector2=uv[0].max(uv[1]).max(uv[2])+Vector2.ONE*.001
			for texel: Array in texels:
				var at_uv: Vector2=texel[0]
				if at_uv.x<low.x or at_uv.y<low.y or at_uv.x>high.x or at_uv.y>high.y:continue
				# Barycentric weights of the texel centre in the face.
				var d: Vector2=at_uv-uv[0]
				var w1: float=d.cross(e2)/uv_area;var w2: float=e1.cross(d)/uv_area
				if w1< -.001 or w2< -.001 or w1+w2>1.001:continue
				var b: float=texel[1]
				var at: Vector3=p[0]*(1.0-w1-w2)+p[1]*w1+p[2]*w2
				var cell := str([bone,side,(at/CELL).floor()])
				if not cells.has(cell):cells[cell]={"bone":bone,"weight":0.0,"area":0.0,"position":Vector3.ZERO,"normal":Vector3.ZERO,"color":Color(0,0,0,0),"low":at,"high":at}
				var entry: Dictionary=cells[cell]
				entry.weight+=b;entry.area+=b*texel_area
				entry.position+=at*b;entry.normal+=n*b
				entry.color+=texel[2]*b
				entry.low=entry.low.min(at);entry.high=entry.high.max(at)
	var patches: Array=[]
	for entry: Dictionary in cells.values():
		var weight: float=entry.weight
		var color: Color=entry.color/weight
		# Window paint is near white; keep its hue, at the shader's level.
		var peak := maxf(color.r,maxf(color.g,color.b))
		if peak<=0.0:continue
		color=Color(color.r/peak,color.g/peak,color.b/peak)
		var extent: float=(entry.high-entry.low).length()
		patches.append({"bone":entry.bone,"position":entry.position/weight,"normal":(entry.normal/weight).normalized(),
			"radius":clampf(extent*.5+4.0,5.0,14.0),"color":color,"strength":clampf(sqrt(float(entry.area))/6.0,.25,1.0)})
	windows_cache[key]=patches
	return patches

static func window_texels(library, atlas: String) -> Array:
	"""The texels of an atlas that the station material lights as windows
	(imported_surface.gd's warm light hint), read on the atlas's own texel
	grid whatever size the drawn atlas is."""
	var key: String=library.root.path_join(atlas)
	if texels_cache.has(key):return texels_cache[key]
	var texels: Array=[]
	var hint_texture: Texture2D=library.surface_map(atlas)
	var color_texture: Texture2D=library.texture(atlas)
	var hint: Image=hint_texture.get_image() if hint_texture!=null else null
	var paint: Image=color_texture.get_image() if color_texture!=null else null
	if hint!=null and paint!=null and not hint.is_compressed() and not paint.is_compressed():
		var size: Vector2=library.texture_size(atlas)
		var hint_scale := Vector2(hint.get_width(),hint.get_height())/size
		var paint_scale := Vector2(paint.get_width(),paint.get_height())/size
		for y in int(size.y):
			for x in int(size.x):
				var b: float=hint.get_pixel(mini(int((x+.5)*hint_scale.x),hint.get_width()-1),mini(int((y+.5)*hint_scale.y),hint.get_height()-1)).b
				if b<WINDOW_HINT:continue
				var color: Color=paint.get_pixel(mini(int((x+.5)*paint_scale.x),paint.get_width()-1),mini(int((y+.5)*paint_scale.y),paint.get_height()-1)).srgb_to_linear()
				texels.append([Vector2(x,y),b,color])
	texels_cache[key]=texels
	return texels
