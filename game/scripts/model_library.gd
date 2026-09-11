extends RefCounted
## Geometry is decoded from the supplied JAR, never generated as replacement art.

const UNIT := 0.01
var root := ""
var models: Dictionary = {}
var meshes: Dictionary = {}
var textures: Dictionary = {}
var surface_maps: Dictionary = {}
var shaders: Dictionary = {}
var native_pose_cache: Dictionary = {}
var native_bones_cache: Dictionary = {}
var native_animations: Dictionary = {}
var enhanced := true
var station_smoothing := false
var surface_roughness := 0.62
var surface_specular := 0.35
var water_to_world := Transform3D.IDENTITY
var ocean_strength := 0.0
var effect_glow := 1.6

static func point(v: Array, offset: int = 0) -> Vector3:
	return Vector3(float(v[offset]), -float(v[offset+1]), -float(v[offset+2])) * UNIT

static func matrix(v: Array, fixed: bool = false) -> Transform3D:
	var d := 4096.0 if fixed else 1.0
	var b := Basis(Vector3(v[0], -v[4], -v[8])/d, Vector3(-v[1], v[5], v[9])/d, Vector3(-v[2], v[6], v[10])/d)
	return Transform3D(b, Vector3(v[3], -v[7], -v[11]) * UNIT)

func texture(resource: String, alpha: bool = false) -> Texture2D:
	var path := root.path_join(resource)
	if resource.ends_with(".bmp"):
		path += ".alpha.png" if alpha else ".png"
	if not textures.has(path):
		var img := Image.load_from_file(path)
		if img == null:
			push_error("Missing imported texture: " + path)
			return null
		img.convert(Image.FORMAT_RGBA8)
		img.generate_mipmaps()
		textures[path] = ImageTexture.create_from_image(img)
	return textures[path]

func data(resource: String) -> Dictionary:
	if not models.has(resource):
		var path := root.path_join(resource + ".json")
		models[resource] = JSON.parse_string(FileAccess.get_file_as_string(path))
		var bounds: Array = []
		var cursor := 0
		for bone: Dictionary in models[resource].bones:
			var box := AABB()
			for index in int(bone.vertices):
				var vertex := point(models[resource].vertices,cursor*3)
				box = AABB(vertex,Vector3.ZERO) if index == 0 else box.expand(vertex)
				cursor += 1
			bounds.append(box if int(bone.vertices) > 0 else null)
		models[resource]["segment_bounds"] = bounds
		if resource.get_file() in ["station_engine.mbac","station_bridge_02.mbac"]:seal_station_sockets(models[resource])
	return models[resource]

func seal_station_sockets(source: Dictionary) -> void:
	# Imported connector ends are open triangular sockets. Close their exact
	# boundary, reusing the owner's vertices/UVs; leave the rotor aperture alone.
	var edges: Dictionary={};var points: Array=[];var transforms: Array=[];var cursor:=0
	for bone in source.bones:
		var pose:=matrix(bone.matrix)
		if int(bone.parent)>=0:pose=transforms[int(bone.parent)]*pose
		transforms.append(pose)
		for i in int(bone.vertices):
			points.append((pose*point(source.vertices,cursor*3)).snapped(Vector3.ONE*.001));cursor+=1
	for poly in source.polygons:
		if int(poly.blend)!=0:continue
		for offset in range(0,poly.indices.size(),3):
			for corner in 3:
				var a:int=poly.indices[offset+corner];var b:int=poly.indices[offset+(corner+1)%3]
				var pa:Vector3=points[a];var pb:Vector3=points[b]
				if pa.is_equal_approx(pb):continue
				var key:=str([pa,pb] if str(pa)<str(pb) else [pb,pa])
				if edges.has(key):edges[key].count+=1
				else:edges[key]={"count":1,"a":a,"b":b,"poly":poly}
	var boundary: Array=edges.values().filter(func(e):return e.count==1)
	var caps: Array=[]
	for edge in boundary:
		for next in boundary:
			if points[edge.b]!=points[next.a]:continue
			for last in boundary:
				if points[next.b]!=points[last.a] or points[last.b]!=points[edge.a]:continue
				var ids: Array=[edge.a,edge.b,next.b]
				# Each loop is visited three times; emit only its lowest index start.
				if edge.a!=ids.min():continue
				var cap:Dictionary=edge.poly.duplicate(true);cap.indices=[ids[2],ids[1],ids[0]];cap.double_sided=true;cap.attributes=[]
				for e in [next,edge,last]:
					var index:=0
					for j in e.poly.indices.size():
						if int(e.poly.indices[j])==int(e.a):index=j;break
					cap.attributes.append_array(e.poly.attributes.slice(index*5,index*5+5))
				caps.append(cap)
	source.polygons.append_array(caps)
	source["socket_caps"]=caps.size()

func surface_map(resource: String) -> Texture2D:
	var key := root.path_join(resource)
	if not surface_maps.has(key):
		var source := texture(resource).get_image()
		surface_maps[key]=ImageTexture.create_from_image(preload("res://native/presentation/imported_surface.gd").derive(source))
	return surface_maps[key]

func mesh_for(resource: String, pattern: int) -> Array:
	var key := resource + ":" + str(pattern)
	if meshes.has(key):
		return meshes[key]
	var source := data(resource)
	var vertex_bones: Array[int] = []
	for i in source.bones.size():
		for j in int(source.bones[i].vertices):
			vertex_bones.append(i)
	var groups: Dictionary = {}
	for polygon: Dictionary in source.polygons:
		if int(polygon.pattern) != 0 and (int(polygon.pattern) & pattern) == 0:
			continue
		var a: Array = polygon.attributes
		var is_textured := int(polygon.texture) >= 0
		var lit := int(a[2 if is_textured else 3]) != 0
		var alpha := is_textured and int(a[4]) != 0
		var door:bool=resource.ends_with("station_hangar_ve.mbac") and polygon.indices.all(func(i):return i>=40 and i<=45)
		var two_sided:bool=polygon.double_sided or (resource.get_file().begins_with("station_") and int(polygon.blend)==0)
		var group_key := str([polygon.texture, polygon.blend, two_sided, lit, alpha,door])
		if not groups.has(group_key):
			groups[group_key] = {"texture": int(polygon.texture), "blend": int(polygon.blend), "double": two_sided, "door":door, "lit": lit, "alpha": alpha, "faces": []}
		groups[group_key].faces.append(polygon)
	var mesh := ArrayMesh.new()
	var surfaces: Array = []
	for g: Dictionary in groups.values():
		var verts := PackedVector3Array()
		var norms := PackedVector3Array()
		var uvs := PackedVector2Array()
		var segments := PackedVector2Array()
		var colors := PackedColorArray()
		for poly: Dictionary in g.faces:
			for j in poly.indices.size():
				var index := int(poly.indices[j])
				verts.append(point(source.vertices, index*3))
				segments.append(Vector2(vertex_bones[index],0))
				if source.normals.size() > index*3+2:
					norms.append(point(source.normals, index*3).normalized())
				else:
					norms.append(Vector3.UP)
				uvs.append(Vector2(poly.attributes[j*5], poly.attributes[j*5+1]))
				colors.append(Color(float(poly.attributes[j*5])/255.0, float(poly.attributes[j*5+1])/255.0, float(poly.attributes[j*5+2])/255.0))
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = norms
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_TEX_UV2] = segments
		arrays[Mesh.ARRAY_COLOR] = colors
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		surfaces.append(g)
	meshes[key] = [mesh, surfaces]
	return meshes[key]

func figure(call: Dictionary) -> Node3D:
	var node := Node3D.new()
	var instance := MeshInstance3D.new()
	instance.name = "Mesh"
	node.add_child(instance)
	instance.mesh = mesh_for(call.resource, int(call.pattern))[0]
	apply_figure_materials(node,call)
	return node

func apply_figure_materials(node: Node3D, call: Dictionary) -> void:
	var instance := node.get_node("Mesh") as MeshInstance3D
	var mesh_data := mesh_for(call.resource, int(call.pattern))
	for i in mesh_data[1].size():
		var g: Dictionary = mesh_data[1][i]
		var resource_name := ""
		if g.texture >= 0 and g.texture < call.textures.size():
			resource_name = call.textures[g.texture]
		var blend: int = g.blend if call.effect.get("transparency",true) else 0
		var look: Dictionary = call.get("replacement",{})
		var mat := affine_material(resource_name,blend,g.double,(g.lit or not look.is_empty()) and call.effect.lit,g.alpha,int(call.get("sky_pass",0)),bool(call.get("pixelated_station",false)),bool(call.get("smoothed_station",false)))
		if not look.is_empty() and blend==0 and sky_pass_for_call(call)==0:
			mat.set_shader_parameter("replacement_enabled",true)
			mat.set_shader_parameter("replacement_albedo",call.replacement_texture)
			mat.set_shader_parameter("replacement_tint",Color(look.color))
			mat.set_shader_parameter("replacement_roughness",float(look.roughness))
			mat.set_shader_parameter("replacement_metallic",float(look.metallic))
			mat.set_shader_parameter("replacement_scale",float(look.scale))
			mat.set_shader_parameter("replacement_relief",float(look.get("relief",0.0)))
			mat.set_shader_parameter("replacement_panels",bool(look.get("panels",true)))
			mat.set_shader_parameter("architecture_enabled",bool(look.get("architecture",false)))
			var biology: Dictionary = call.get("biology",{})
			if not biology.is_empty():
				mat.set_shader_parameter("biology_enabled",true)
				mat.set_shader_parameter("biology_dorsal",biology.dorsal)
				mat.set_shader_parameter("biology_ventral",biology.ventral)
				mat.set_shader_parameter("biology_height",Vector2(biology.low,biology.high))
				if biology.eyes.size()==2:
					mat.set_shader_parameter("biology_eye_left",biology.eyes[0])
					mat.set_shader_parameter("biology_eye_right",biology.eyes[1])
		mat.set_shader_parameter("hangar_door",g.get("door",false))
		instance.set_surface_override_material(i, mat)
	node.set_meta("station_smoothing",station_smoothing)

static func sky_pass_for_call(call: Dictionary) -> int:
	return int(call.get("sky_pass",0))

func pose(node: Node3D, call: Dictionary) -> void:
	node.transform = matrix(call.layout.transform, true)
	var mesh := node.get_node("Mesh") as MeshInstance3D
	var pose_key: String = call.get("native_pose_key","")
	if not pose_key.is_empty() and native_pose_cache.has(pose_key):
		var cached: Dictionary = native_pose_cache[pose_key]
		mesh.custom_aabb=cached.bounds
		for i in cached.materials.size(): mesh.set_surface_override_material(i,cached.materials[i])
		return
	var transforms: Array[Transform3D] = []
	for values: Array in call.bones:
		transforms.append(matrix(values))
	while transforms.size() < 64:
		transforms.append(Transform3D.IDENTITY)
	mesh.custom_aabb = pose_bounds(call.resource,transforms)
	var pose_materials: Array = []
	for i in mesh.mesh.get_surface_count():
		var mat := mesh.get_surface_override_material(i) as ShaderMaterial
		if not pose_key.is_empty():
			mat=mat.duplicate(); mesh.set_surface_override_material(i,mat)
			pose_materials.append(mat)
		mat.set_shader_parameter("source_bones",transforms)
		mat.set_shader_parameter("water_to_world",water_to_world)
		mat.set_shader_parameter("ocean_strength",ocean_strength)
		mat.set_shader_parameter("distance_haze",float(call.get("distance_haze",0.0)))
		mat.set_shader_parameter("source_glow_visible",bool(call.get("source_glow_visible",true)))
		mat.set_shader_parameter("source_ambient",float(call.effect.ambient)/4096.0)
		mat.set_shader_parameter("source_intensity",float(call.effect.intensity)/4096.0)
		mat.set_shader_parameter("source_light",point(call.effect.direction).normalized())
		mat.set_shader_parameter("station_coating",bool(call.get("station_coating",false)))
		mat.set_shader_parameter("hull_coating",bool(call.get("hull_coating",false)))
		mat.set_shader_parameter("bioluminescence",float(call.get("bioluminescence",0.0)))
		mat.set_shader_parameter("surface_roughness",surface_roughness)
		mat.set_shader_parameter("surface_specular",surface_specular)
		mat.set_shader_parameter("effect_glow",maxf(effect_glow,1.1) if bool(call.get("station_coating",false)) else effect_glow)
	if not pose_key.is_empty():
		if native_pose_cache.size()>=512: native_pose_cache.erase(native_pose_cache.keys()[0])
		native_pose_cache[pose_key]={"materials":pose_materials,"bounds":mesh.custom_aabb}

func pose_bounds(resource: String, transforms: Array[Transform3D]) -> AABB:
	var bounds: Array = data(resource).segment_bounds
	var result := AABB()
	var first := true
	for i in bounds.size():
		if bounds[i] == null:
			continue
		var moved: AABB = transforms[i] * bounds[i]
		result = moved if first else result.merge(moved)
		first = false
	# Keep zero-thickness faces and float-rounding at the boundary visible.
	return result.grow(0.001)

func affine_material(resource: String, blend: int, double_sided: bool, lit: bool, alpha: bool, sky_pass: int = 0, pixelated: bool = false, smoothed: bool = false) -> ShaderMaterial:
	var modern := enhanced and sky_pass == 0
	var key := str([blend,double_sided,lit,alpha,enhanced,resource != "",sky_pass,pixelated,smoothed])
	if not shaders.has(key):
		var modes := ["cull_disabled" if double_sided else "cull_back"]
		if not lit or not modern:
			modes.append("unshaded")
		if sky_pass == 0:
			if blend == 4:
				modes.append("blend_add")
				modes.append("fog_disabled")
			elif blend == 6:
				modes.append("blend_sub")
				modes.append("fog_disabled")
		# Sky ramps must never share mip levels with the neighboring ramp.
		var filtering := "filter_linear" if sky_pass != 0 and enhanced else ("filter_linear_mipmap_anisotropic" if modern else "filter_nearest")
		if smoothed:filtering="filter_linear_mipmap_anisotropic"
		elif pixelated:filtering="filter_nearest_mipmap"
		var code := "shader_type spatial;\nrender_mode %s;\n" % ", ".join(modes)
		code += '#include "res://native/presentation/ocean_background.gdshaderinc"\nuniform float distance_haze=0.0;\n'
		# Sky samples are numeric byte-color data. Avoid losing dark ramp values
		# in Compatibility's 8-bit linear intermediate target.
		code += "uniform sampler2D albedo : %s%s, repeat_disable;\n" % ["source_color, " if sky_pass == 0 else "",filtering]
		code += """
uniform bool replacement_enabled=false;
uniform bool replacement_panels=true;
uniform bool architecture_enabled=false;
uniform bool biology_enabled=false;
uniform vec4 biology_dorsal : source_color=vec4(0.3,0.5,0.5,1.0);
uniform vec4 biology_ventral : source_color=vec4(0.8,0.85,0.8,1.0);
uniform vec2 biology_height=vec2(-1.0,1.0);
uniform vec4 biology_eye_left=vec4(0.0);
uniform vec4 biology_eye_right=vec4(0.0);
uniform sampler2D replacement_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 replacement_tint : source_color=vec4(1.0);
uniform float replacement_roughness=0.55;
uniform float replacement_metallic=0.4;
uniform float replacement_scale=0.1;
uniform bool hangar_door=false;
uniform float hangar_open=0.0;
uniform float stream_visibility=1.0;
uniform bool source_glow_visible=true;
uniform float replacement_relief=0.0;
varying vec3 material_position;
varying vec3 material_normal;
varying vec3 architecture_position;
varying vec3 architecture_normal;
uniform mat4 source_bones[64];
uniform vec2 texture_size = vec2(1.0);
uniform float source_ambient = 1.0;
uniform float source_intensity = 0.0;
uniform vec3 source_light = vec3(0.0,1.0,0.0);
uniform bool portal_clip_enabled = false;
uniform vec4 portal_clip_plane = vec4(0.0);
uniform bool station_coating = false;
uniform bool hull_coating = false;
uniform float bioluminescence = 0.0;
uniform sampler2D surface_map : filter_linear_mipmap_anisotropic, repeat_disable;
uniform float surface_roughness = 0.62;
uniform float surface_specular = 0.35;
uniform float effect_glow = 1.6;
uniform mat4 water_to_world;
uniform float ocean_strength = 0.0;
varying vec3 water_position;
varying vec3 water_normal;
varying vec3 original_normal;
float caustic(vec2 p) {
	vec2 cell=floor(p),f=fract(p); float nearest=2.0,second=2.0;
	for(int y=-1;y<=1;y++){for(int x=-1;x<=1;x++){vec2 g=vec2(float(x),float(y)); vec2 id=cell+g; vec2 seed=fract(sin(vec2(dot(id,vec2(127.1,311.7)),dot(id,vec2(269.5,183.3))))*43758.5453); vec2 r=g+0.5+0.36*sin(TIME*0.48+6.2831*seed)-f; float d=dot(r,r); if(d<nearest){second=nearest;nearest=d;}else{second=min(second,d);}}}
	return pow(max(0.0,1.0-(second-nearest)*9.0),4.0);
}
vec3 to_linear(vec3 c) {
	return mix(c/12.92,pow((c+0.055)/1.055,vec3(2.4)),step(vec3(0.04045),c));
}
vec3 to_srgb(vec3 c) {
	return mix(c*12.92,1.055*pow(max(c,vec3(0.0)),vec3(1.0/2.4))-0.055,step(vec3(0.0031308),c));
}
void vertex() {
	// Coatings follow the undeformed surface through both bone and world poses.
	material_position=VERTEX;
	material_normal=NORMAL;
	mat4 bone = source_bones[int(UV2.x+0.5)];
	VERTEX = (bone*vec4(VERTEX,1.0)).xyz;
	vec3 n = mat3(bone)*NORMAL;
	original_normal = mat3(MODEL_MATRIX)*n;
	water_position = (water_to_world*MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
	water_normal = mat3(water_to_world)*original_normal;
""".replace("\n+","\n")
		if modern:
			# Enhanced lighting uses the geometric normal even for sheared poses.
			code += "if(abs(determinant(mat3(bone)))>0.000001){n=transpose(inverse(mat3(bone)))*NORMAL;}\n"
		code += "NORMAL=length(n)>0.00001?normalize(n):vec3(0.0,1.0,0.0); architecture_position=VERTEX; architecture_normal=NORMAL; }\nvoid fragment(){\n"
		code += "bool door_panel=hangar_door && UV.x>49.0 && UV.x<60.0 && UV.y>99.0 && UV.y<108.0; if(door_panel && hangar_open>0.0 && abs(UV.x-54.5)<5.6*hangar_open){discard;} vec2 surface_uv=UV; if(door_panel){surface_uv.x-=sign(UV.x-54.5)*5.5*hangar_open;}\n"
		if sky_pass == 0:
			# Dither keeps opaque depth ordering; imported alpha/additive faces fade too.
			code += "if(portal_clip_enabled && dot(portal_clip_plane,INV_VIEW_MATRIX*vec4(VERTEX,1.0))<0.0){discard;}\n"
			code += "float far_visibility=1.0-smoothstep(7000.0,9600.0,length(VERTEX));float coverage=stream_visibility*(IN_SHADOW_PASS?1.0:far_visibility);float threshold=fract(52.9829189*fract(dot(floor(FRAGCOORD.xy),vec2(0.06711056,0.00583715))));if(coverage<=threshold){discard;}\n"
		if blend == 4 or blend == 6:
			code += "if(IN_SHADOW_PASS){discard;}\n"
			if sky_pass==0:code += "if(!source_glow_visible){discard;}\n"
		if sky_pass != 0 and sky_pass != blend:
			code += "discard;\n"
		# Perspective interpolation can turn a constant integer U=4 into 3.999999.
		# Stabilize the source's integer texel convention at sub-texel precision.
		var coords := "(surface_uv+vec2(0.5))/texture_size" if (enhanced or smoothed) and not pixelated else "(floor(surface_uv+vec2(0.0001))+vec2(0.5))/texture_size"
		code += "vec4 color="+("texture(albedo,%s)" % coords if resource != "" else "vec4(OUTPUT_IS_SRGB?COLOR.rgb:to_linear(COLOR.rgb),COLOR.a)")+";\n"
		if alpha:
			code += "if(color.a<0.5){discard;}\n"
		if lit and not modern:
			# Mascot applies per-fragment Lambert lighting to byte-space colors.
			code += "float brightness=clamp(clamp(source_ambient,0.0,1.0)+clamp(source_intensity,0.0,4.0)*max(dot(normalize(original_normal),-source_light),0.0),0.0,1.0);\n"
			code += "color.rgb=OUTPUT_IS_SRGB?color.rgb*brightness:to_linear(to_srgb(color.rgb)*brightness);\n"
		if sky_pass != 0:
			code += "if(OUTPUT_IS_SRGB){color.rgb=to_srgb(color.rgb);}\n"
		code += "ALBEDO=color.rgb; ROUGHNESS=surface_roughness; METALLIC=0.0; SPECULAR=surface_specular;\n"
		if modern and lit and blend == 0:
			code += """
// Station paint should catch the local work lights, not acquire the blue
// sky's grazing-angle Fresnel reflection. Initialize the other material path
// too, because writing RADIANCE opts the whole shader into this override.
RADIANCE=vec4(0.0);
if(station_coating){
 RADIANCE=vec4(0.0,0.0,0.0,1.0);
	// Preserve imported paint and panels. Only warm, bright window texels
	// emit; pale bulkheads must still depend on the scene's actual lights.
	vec3 hints=texture(surface_map,(UV+vec2(0.5))/texture_size).rgb;
	EMISSION=color.rgb*vec3(1.0,0.83,0.56)*hints.b*2.2;
	ROUGHNESS=hints.g; SPECULAR=0.38; METALLIC=0.08;
}
if(hull_coating && !replacement_enabled){
	vec3 hints=texture(surface_map,(UV+vec2(0.5))/texture_size).rgb;
	ROUGHNESS=hints.g;
	// Tiny relief follows the imported panels through the deformed geometry.
	// Clamp the slope and fade it at distance to keep low-resolution art stable.
	float height=hints.r*(station_coating?0.65:0.14)*(1.0-smoothstep(80.0,500.0,length(VERTEX)));
	vec3 dx=dFdx(VERTEX),dy=dFdy(VERTEX),r1=cross(dy,NORMAL),r2=cross(NORMAL,dx);
	float det=dot(dx,r1);
	if(abs(det)>0.00000001){
		vec3 gradient=(dFdx(height)*r1+dFdy(height)*r2)/det;
		gradient*=min(1.0,0.16/max(0.00001,length(gradient)));
		NORMAL=normalize(NORMAL-gradient);
	}
}
if(bioluminescence>0.0){
	// The imported jelly's pale markings provide the luminous tissue mask.
	// Low, steady blue-green radiance retains its original painted anatomy.
	float tissue=smoothstep(0.12,0.55,max(color.r,max(color.g,color.b)));
	EMISSION+=color.rgb*vec3(0.32,0.8,1.0)*tissue*bioluminescence;
}
if(replacement_enabled){
	vec3 w=pow(abs(normalize(material_normal)),vec3(4.0)); w/=max(0.001,w.x+w.y+w.z);
	vec3 p=material_position*replacement_scale;
	vec3 t=texture(replacement_albedo,p.yz).rgb*w.x+texture(replacement_albedo,p.xz).rgb*w.y+texture(replacement_albedo,p.xy).rgb*w.z;
	float panel=replacement_panels?step(0.04,fract(p.x*0.4))*step(0.025,fract(p.z*0.25)):1.0;
	ALBEDO=t*replacement_tint.rgb*(0.68+panel*0.32); ROUGHNESS=replacement_roughness; METALLIC=replacement_metallic;
	float seam=step(0.94,fract(p.y*0.7))*step(0.64,fract(p.x*0.5)); EMISSION=vec3(0.12,0.42,0.38)*seam*replacement_metallic*float(replacement_panels);
	// The sampled new albedo supplies a shallow surface gradient. Work in the
	// deformed geometric frame so the relief follows animated and sheared parts.
	if(replacement_relief>0.0){
		float height=dot(t,vec3(0.333333))*replacement_relief;
		vec3 dx=dFdx(VERTEX),dy=dFdy(VERTEX),r1=cross(dy,NORMAL),r2=cross(NORMAL,dx);
		float det=dot(dx,r1);
		if(abs(det)>0.00000001){
			vec3 gradient=(dFdx(height)*r1+dFdy(height)*r2)/det;
			gradient*=min(1.0,0.45/max(0.00001,length(gradient)));
			NORMAL=normalize(NORMAL-gradient);
		}
	}
}
"""
		if modern and lit and blend == 0:
			code += "float light_net=caustic(water_position.xz*0.13+vec2(TIME*0.014,0.0)); float facing=max(normalize(water_normal).y,0.0); float sunlit=clamp(source_intensity/2.0,0.0,1.0); ALBEDO*=1.0+light_net*facing*sunlit*ocean_strength*0.65; ROUGHNESS=clamp(ROUGHNESS+(sin(water_position.x*29.0)*sin(water_position.z*31.0))*0.045*ocean_strength,0.0,1.0);\n"
		if modern and lit and blend == 0:
			code += """
if(replacement_enabled && biology_enabled){
	float height=clamp((material_position.y-biology_height.x)/max(0.01,biology_height.y-biology_height.x),0.0,1.0);
	vec3 pigment=mix(biology_ventral.rgb,biology_dorsal.rgb,smoothstep(0.18,0.7,height));
	ALBEDO*=pigment/max(replacement_tint.rgb,vec3(0.001));
	if(biology_eye_left.w>0.0 && biology_eye_right.w>0.0){
		float eye=min(length(material_position-biology_eye_left.xyz)/biology_eye_left.w,length(material_position-biology_eye_right.xyz)/biology_eye_right.w);
		float border=1.0-smoothstep(0.85,1.05,eye);
		float pupil=1.0-smoothstep(0.38,0.6,eye);
		vec3 iris=mix(vec3(0.24,0.19,0.095),vec3(0.006,0.011,0.018),pupil);
		ALBEDO=mix(ALBEDO,iris,border); ROUGHNESS=mix(ROUGHNESS,0.08,border); SPECULAR=mix(SPECULAR,0.65,border);
	}
}
"""
		if modern and lit and blend == 0:
			code += """
if(replacement_enabled && architecture_enabled){
	// New modular observation strips. Coordinates stay attached to each part.
	vec3 facing=abs(normalize(architecture_normal));
	vec2 wall=facing.x>facing.z?architecture_position.zy:architecture_position.xy;
	vec2 grid=wall/vec2(12.0,8.0),cell=floor(grid),f=fract(grid);
	vec2 aa=max(fwidth(grid)*1.3,vec2(0.001));
	float horizontal=smoothstep(0.18-aa.x,0.18+aa.x,f.x)*(1.0-smoothstep(0.80-aa.x,0.80+aa.x,f.x));
	float vertical=smoothstep(0.43-aa.y,0.43+aa.y,f.y)*(1.0-smoothstep(0.61-aa.y,0.61+aa.y,f.y));
	float window=horizontal*vertical*(1.0-smoothstep(0.15,0.45,facing.y));
	float occupied=step(0.28,fract(sin(dot(cell,vec2(12.9898,78.233)))*43758.5453));
	ALBEDO=mix(ALBEDO,vec3(0.018,0.035,0.042),window);
	ROUGHNESS=mix(ROUGHNESS,0.22,window); METALLIC=mix(METALLIC,0.05,window);
	EMISSION+=vec3(1.0,0.48,0.16)*window*occupied*0.75;
}
"""
		if modern and blend == 4:
			# Only a source additive surface receives bloom; no guessed light masks.
			code += "ALBEDO=color.rgb*effect_glow;\n" if not lit else "ALBEDO=vec3(0.0); EMISSION=color.rgb*effect_glow;\n"
		if sky_pass == 0:
			if blend == 2:
				code += "ALPHA=0.5;\n"
			elif blend == 4 or blend == 6:
				code += "ALPHA=1.0;\n"
		# Godot requires every FOG-writing shader path to initialize its output.
		# Classic rendering disables distance haze; an unwritten FOG becomes black.
		if sky_pass==0 and blend in [4,6]:
			# Add/subtract surfaces must attenuate toward zero. Their fog-disabled
			# blend path ignores FOG; otherwise distant effects keep full brightness.
			code += "FOG=vec4(0.0);float transmission=exp(-length(VERTEX)*max(distance_haze,0.0));ALBEDO*=transmission;EMISSION*=transmission;\n"
		else:
			# Near station haze absorbs light without lifting shadows into blue.
			# Scattered water radiance enters gradually across the distant silhouette.
			code += "FOG=vec4(0.0);if(distance_haze>0.0){vec3 ray=normalize((INV_VIEW_MATRIX*vec4(VERTEX,0.0)).xyz);FOG=ocean_fog(ray,length(VERTEX),distance_haze);if(station_coating){FOG.rgb*=smoothstep(250.0,2400.0,length(VERTEX));}}\n"
		code += "}\n"
		var shader := Shader.new()
		shader.code = code
		shaders[key] = shader
	var mat := ShaderMaterial.new()
	mat.shader = shaders[key]
	if resource != "":
		var tex := texture(resource,alpha)
		mat.set_shader_parameter("albedo",tex)
		mat.set_shader_parameter("texture_size",Vector2(tex.get_width(),tex.get_height()))
		if modern and lit and blend==0:mat.set_shader_parameter("surface_map",surface_map(resource))
	return mat
