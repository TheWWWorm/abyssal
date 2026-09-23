extends MeshInstance3D
## Station shadows use only solid surfaces. Blinking sprites and water shading
## must not make every nearby work light redraw its six shadow-map faces.
var bone_bounds: Dictionary = {}
var posed_bones: Array[Transform3D] = []
var materials: Array[ShaderMaterial] = []
var coverage := {"stream_visibility":1.0,"hangar_open":0.0,"smoothed":false}

func configure(library, call: Dictionary, mesh_data: Array) -> void:
	name="StationShadow"
	cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	var key := str([call.resource,call.pattern])
	if not library.station_shadow_meshes.has(key):
		library.station_shadow_meshes[key]=build_geometry(mesh_data)
	var geometry: Dictionary=library.station_shadow_meshes[key]
	mesh=geometry.mesh;bone_bounds=geometry.bones
	for surface: Array in geometry.surfaces:
		var texture_index: int=surface[0]
		var material := ShaderMaterial.new()
		# Keep opaque and cutout shaders separate: a varying palette mask
		# prevents the OpenGL driver from optimizing opaque shadow fragments.
		var variant := str(surface.slice(1))
		if not library.station_shadow_shaders.has(variant):
			var shader := Shader.new()
			shader.code=("#define PALETTE_CUTOUT\n" if surface[1] else "")+("#define HANGAR_DOOR\n" if surface[2] else "")+preload("res://native/presentation/station_shadow.gdshader").code
			library.station_shadow_shaders[variant]=shader
		material.shader=library.station_shadow_shaders[variant]
		if texture_index>=0 and texture_index<call.textures.size():
			var resource: String=call.textures[texture_index]
			var texture: Texture2D=library.texture(resource)
			material.set_shader_parameter("albedo_crisp",texture)
			material.set_shader_parameter("albedo_smooth",texture)
			material.set_shader_parameter("texture_size",library.texture_size(resource))
		set_surface_override_material(materials.size(),material);materials.append(material)
	set_coverage("smoothed",bool(call.get("smoothed_station",false)))

static func build_geometry(mesh_data: Array) -> Dictionary:
	var source: ArrayMesh=mesh_data[0]
	var groups := {};var bones := {};var surfaces: Array=[]
	for i in mesh_data[1].size():
		var surface: Dictionary=mesh_data[1][i]
		if int(surface.blend)!=0:continue
		var texture_index: int=surface.texture
		var material_key := [texture_index,bool(surface.alpha),bool(surface.get("door",false))]
		var key := str(material_key)
		if not groups.has(key):
			groups[key]={"vertices":PackedVector3Array(),"normals":PackedVector3Array(),"uv":PackedVector2Array(),"bones":PackedVector2Array()}
			surfaces.append(material_key)
		var group: Dictionary=groups[key]
		var arrays := source.surface_get_arrays(i)
		for j in arrays[Mesh.ARRAY_VERTEX].size():
			var point: Vector3=arrays[Mesh.ARRAY_VERTEX][j]
			var bone := int(arrays[Mesh.ARRAY_TEX_UV2][j].x)
			group.vertices.append(point);group.uv.append(arrays[Mesh.ARRAY_TEX_UV][j])
			group.normals.append(arrays[Mesh.ARRAY_NORMAL][j])
			group.bones.append(Vector2(bone,0))
			bones[bone]=bones[bone].expand(point) if bones.has(bone) else AABB(point,Vector3.ZERO)
	var compact := ArrayMesh.new()
	for group: Dictionary in groups.values():
		var arrays := [];arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX]=group.vertices;arrays[Mesh.ARRAY_NORMAL]=group.normals
		arrays[Mesh.ARRAY_TEX_UV]=group.uv;arrays[Mesh.ARRAY_TEX_UV2]=group.bones
		compact.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return {"mesh":compact,"surfaces":surfaces,"bones":bones}

func pose(transforms: Array[Transform3D]) -> void:
	var solid_pose: Array[Transform3D]=[]
	for bone: int in bone_bounds:solid_pose.append(transforms[bone])
	if solid_pose==posed_bones:return
	posed_bones=solid_pose
	var bounds := AABB();var first := true
	for bone: int in bone_bounds:
		var moved: AABB=transforms[bone]*bone_bounds[bone]
		bounds=moved if first else bounds.merge(moved);first=false
	for material in materials:material.set_shader_parameter("source_bones",transforms)
	# Resubmitting bounds invalidates cached shadows when actual solids move.
	# A lamp-only bone change leaves both bounds and shadow materials alone.
	custom_aabb=bounds.grow(.001)
	invalidate_shadows()

func invalidate_shadows() -> void:
	# GeometryInstance3D skips an unchanged custom_aabb property assignment.
	# Submit to the server explicitly for a pose with the same outer bounds.
	RenderingServer.instance_set_custom_aabb(get_instance(),custom_aabb)

func set_coverage(parameter: String, value) -> void:
	if coverage[parameter]==value:return
	coverage[parameter]=value
	for material in materials:material.set_shader_parameter(parameter,value)
	# A door or fade changes coverage without moving vertices. Notify the
	# renderer so the affected lights refresh their cached shadow maps too.
	invalidate_shadows()
