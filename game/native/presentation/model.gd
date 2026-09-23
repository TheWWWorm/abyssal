extends Node3D
## Native pose hierarchy from imported MBAC/MTRA data. No bridge frame required.
const Library = preload("res://scripts/model_library.gd")
const Math = preload("res://native/simulation/fixed_math.gd")
const Clock = preload("res://native/simulation/animation_clock.gd")
const Special = preload("res://native/simulation/special_actor.gd")
const Mods = preload("res://native/presentation/mods.gd")
## Every station module is turned half a turn about its socket axis: the
## imported station meshes stand the other way up and the other way round
## from the phone game, so a hangar's berth door read as a roof and each
## module hung mirrored on a layout whose positions were already right. The
## roll is applied where a part is placed; the aperture and the collision
## boxes are read through the same turn.
const STATION_ROLL := Transform3D(Basis(Vector3(0,0,1),PI),Vector3.ZERO)
static func station_transform(pose: Transform3D) -> Transform3D:
	return pose*STATION_ROLL

## The imported vessel meshes use the opposite dorsal direction from the
## actor frame. Turn every independent hull root half a turn about the travel
## axis before its animation is composed; child bones then inherit the turn
## once. Keeping this in the bone pose makes the rendered mesh, bounds, lamps,
## headlights and replacement fitting agree in every view of the vessel.
const HULL_ROLL_SOURCE := [-1.0,0.0,0.0,0.0,0.0,-1.0,0.0,0.0,0.0,0.0,1.0,0.0]
static func is_hull_id(id: int) -> bool:
	return id>=0 and id<12
var library := Library.new()
var clock := Clock.new()
var source: Dictionary = {}
var record: Dictionary = {}
var animation: Array = []
var solid_aabb := AABB()
var solid_aabb_ready := false
var replacement: Node3D
var figure: Node3D
var pattern_figures: Dictionary = {}
var last_pattern := -1
var sampled_frame := -1
var current_bones: Array = []
var elapsed := 0
var machinery := false
var machinery_sample := -1
var pack
var modern_graphics := true
var use_replacement_geometry := false
var companion_resource := ""
var material_look: Dictionary = {}
var biological_look: Dictionary = {}
var applied_range: Array = []
var stream_visibility := 1.0
var fade_materials := {}
var hangar_open := 0.0
var hangar_materials: Dictionary={}
var hangar_interior: MeshInstance3D
# Raises this model's own additive effect surfaces above the level the rest of
# the game's effects are toned to. Poses are cached by key, so it belongs to the
# call rather than being written onto a material after the fact.
var effect_boost := 0.0
var posed_boost := 0.0
var portal_enabled := false
var portal_plane := Vector4.ZERO
var portal_materials := {}

var hinge_axis := 1
var hinge_bend := 0.0
var hinge_materials: Dictionary = {}

func set_hinge(axis: int, bend: float) -> void:
	"""Bends this part at its join with the body by a Godot-space angle
	about its local X (pitch) or Y (yaw). Only a bending model owns these
	material overrides; the shared poses and rigid models stay undeformed."""
	hinge_axis=axis;hinge_bend=bend;apply_hinge()

func apply_hinge() -> void:
	if figure==null:return
	var mesh := figure.get_node("Mesh") as MeshInstance3D
	# Instance uniforms reserve global-buffer slots even for rigid models and
	# hidden warmup/animation variants. Mobile WebGL can exhaust that buffer;
	# an invalid offset can read ocean lighting as a bend. Ordinary uniforms
	# on model-owned materials keep deformation out of that shared buffer.
	for index in mesh.mesh.get_surface_count():
		var material := mesh.get_surface_override_material(index) as ShaderMaterial
		if material==null:continue
		if not material.has_meta("hinge_original"):
			if hinge_bend==0.0:continue
			var key := material.get_instance_id()
			if not hinge_materials.has(key):
				if hinge_materials.size()>=128:hinge_materials.clear()
				var own := material.duplicate() as ShaderMaterial
				own.set_meta("hinge_original",material);hinge_materials[key]=own
			material=hinge_materials[key];mesh.set_surface_override_material(index,material)
		material.set_shader_parameter("hinge_axis",hinge_axis)
		material.set_shader_parameter("hinge_bend",hinge_bend)
	Library.set_lamp_hinge(figure,hinge_axis,hinge_bend)

func set_stream_visibility(value: float) -> void:
	stream_visibility=clampf(value,0.0,1.0)
	apply_stream_visibility()
	apply_hinge()

func apply_stream_visibility() -> void:
	if figure==null:return
	var shadow := figure.get_node_or_null("StationShadow")
	if shadow!=null:shadow.set_coverage("stream_visibility",stream_visibility)
	var mesh := figure.get_node("Mesh") as MeshInstance3D
	# Keep pose-cache materials immutable. Only fading instances own overrides.
	for index in mesh.mesh.get_surface_count():
		var original := mesh.get_surface_override_material(index) as ShaderMaterial
		if original==null:continue
		if stream_visibility>=1.0:
			# A hidden animation variant may still wear the fade it was given
			# before the frame moved on; it is undone whenever it is worn again.
			if original.has_meta("stream_original"):mesh.set_surface_override_material(index,original.get_meta("stream_original"))
			continue
		if not original.has_meta("stream_original"):
			var key := original.get_instance_id()
			if not fade_materials.has(key):
				if fade_materials.size()>128:fade_materials.clear()
				var own := original.duplicate() as ShaderMaterial
				own.set_meta("stream_original",original);fade_materials[key]=own
			original=fade_materials[key];mesh.set_surface_override_material(index,original)
		original.set_shader_parameter("stream_visibility",stream_visibility)
	if stream_visibility>=1.0:fade_materials.clear()
	Library.set_lamp_visibility(figure,stream_visibility)


func configure(cache: String, entry: Dictionary, preview_frame_ms: int = 32) -> void:
	library.root=cache
	library.enhanced=modern_graphics
	library.ocean_strength=0.08 if modern_graphics else 0.0
	record=entry
	if pack!=null: material_look=pack.look_for(int(record.id))
	source=library.data(record.model)
	if material_look.get("biology",false): biological_look=preload("res://native/presentation/biological_surface.gd").definition(int(record.id),source)
	var path := cache.path_join(str(record.model).replace(".mbac",".mtra.json"))
	if not library.native_animations.has(path):
		library.native_animations[path]=JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else []
	animation=library.native_animations[path]
	clock.configure(int(animation[0].last_frame) if not animation.is_empty() else 0,preview_frame_ms)
	if animation.is_empty(): clock.mode=0
	refresh()

static func ship_animation_range(id: int, faction: int) -> Array:
	if faction<0 or faction>2: return []
	if id in [2,4,5,6,7,8]: return [faction*3,faction*3+2]
	if id in [0,1,3,9,10,11]: return [faction,faction]
	return []

func apply_actor_animation(actor) -> void:
	clock.frame_ms=64 if actor.model_id==19 else 32
	var interval: Array = []
	if not actor.is_creature:
		interval=ship_animation_range(actor.model_id,actor.faction)
		if actor is Special and not actor.animation_range.is_empty(): interval=actor.animation_range
	apply_range(interval)

func apply_range(interval: Array) -> void:
	if interval==applied_range: return
	applied_range=interval.duplicate()
	if not interval.is_empty(): clock.set_range(interval[0],interval[1]); clock.play(2)
	refresh()

static func multiply(a: Array,b: Array) -> Array:
	var out: Array = []
	out.resize(12)
	for r in 3:
		for c in 4:
			var value := Math.f32(Math.f32(a[r*4]*b[c])+Math.f32(a[r*4+1]*b[4+c]))
			value=Math.f32(value+Math.f32(a[r*4+2]*b[8+c]))
			out[r*4+c]=Math.f32(value+a[r*4+3]) if c==3 else value
	return out

func configure_station(part: Dictionary) -> void:
	# The range is the faction's: its emblem and configuration, and for the
	# hangars and caps a short loop the original runs at the part's interval.
	# The engine's rotor is turned continuously instead of stepping through
	# its four coarse source poses, so its own frames stay still.
	apply_range(part.animation_range)
	machinery=int(record.id)==3304 and source.bones.size()>2
	var interval: Array=part.animation_range
	clock.playing=not machinery and interval.size()==2 and int(interval[0])!=int(interval[1])
	sampled_frame=-1;refresh()

func is_hangar() -> bool:
	return int(record.id) in [3307,3308]

func hangar_aperture() -> AABB:
	# The berth door is the imported panel between the blue lamps, on either
	# hangar. Read its actual pose instead of the whole station bounds.
	var box:=AABB();var first:=true
	for polygon in source.polygons:
		if not Library.is_hangar_door(str(record.model),polygon):continue
		for index in polygon.indices:
			var p:=Library.matrix(current_bones[0])*Library.point(source.vertices,int(index)*3)
			box=AABB(p,Vector3.ZERO) if first else box.expand(p);first=false
	return box

func set_hangar_open(value: float) -> void:
	hangar_open=clampf(value,0,1);apply_hangar_open()
func apply_hangar_open() -> void:
	if figure==null or not is_hangar():return
	var shadow := figure.get_node_or_null("StationShadow")
	if shadow!=null:shadow.set_coverage("hangar_open",hangar_open)
	var mesh:=figure.get_node("Mesh") as MeshInstance3D
	for i in mesh.mesh.get_surface_count():
		var material:=mesh.get_surface_override_material(i) as ShaderMaterial
		if not material.get_shader_parameter("hangar_door"):continue
		if not material.has_meta("hangar_instance"):
			var key:=material.get_instance_id()
			if not hangar_materials.has(key):
				var own:=material.duplicate() as ShaderMaterial;own.set_meta("hangar_instance",true);hangar_materials[key]=own
			material=hangar_materials[key];mesh.set_surface_override_material(i,material)
		material.set_shader_parameter("hangar_open",hangar_open)
	if hangar_interior==null:
		var aperture:=hangar_aperture()
		hangar_interior=MeshInstance3D.new();hangar_interior.name="HangarInterior";add_child(hangar_interior)
		var panel:=QuadMesh.new();panel.size=Vector2(aperture.size.x,aperture.size.y)
		var mat:=StandardMaterial3D.new();mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;mat.albedo_color=Color("010306");mat.cull_mode=BaseMaterial3D.CULL_DISABLED;panel.material=mat
		hangar_interior.mesh=panel;hangar_interior.position=aperture.get_center()-Vector3(0,0,.15)
	# The dark interior is only there to be seen through the open door. The
	# door itself is fogged and dithered with distance; this plain panel is
	# not, so left showing it was the black rectangle every far station wore.
	hangar_interior.visible=hangar_open>0.0

func sample_bones(sample: int) -> Array:
	var matrices: Array = []
	var action: Array = []
	var hull:=is_hull_id(int(record.id))
	if not animation.is_empty(): action=animation[0].matrices[clampi(sample,0,int(animation[0].last_frame))]
	for i in source.bones.size():
		var bone: Dictionary = source.bones[i]
		var parent := int(bone.parent)
		var mat: Array = bone.matrix.duplicate()
		if parent>=0: mat=multiply(matrices[parent],mat)
		elif hull: mat=multiply(HULL_ROLL_SOURCE,mat)
		if machinery and i==2:
			# The owner's engine resource rotates this local Y bone; its three
			# blades repeat every 120 degrees. Two-degree samples avoid stepping
			# through the four coarse source poses or animating the housing.
			var angle:=deg_to_rad(float(machinery_sample)*2.0)
			mat=multiply(mat,[cos(angle),0,sin(angle),0,0,1,0,0,-sin(angle),0,cos(angle),0])
		elif action.size() >= (i+1)*12: mat=multiply(mat,action.slice(i*12,(i+1)*12))
		matrices.append(mat)
	return matrices

func pattern_at(sample: int) -> int:
	var pattern := 0
	var latest := -1
	if not animation.is_empty():
		for key in animation[0].patterns:
			var at := int(key)
			if at<=sample and at>latest:
				latest=at
				pattern=int(animation[0].patterns[key])
	return pattern

func refresh_station_filtering() -> void:
	if int(record.id)<3300 or int(record.id)>=3400:return
	# Keep mesh nodes and their attached collision bodies/shadow settings.
	# Hidden animation variants refresh their materials when next selected.
	fade_materials.clear();portal_materials.clear();sampled_frame=-1
	refresh()

func refresh() -> void:
	var sample := clock.sample()
	var pattern := pattern_at(sample)
	var motion:=int(elapsed*60/1000)%60 if machinery else -1
	# effect_boost belongs here too: a gate holds one pose while its glow still
	# rises with the player's approach, and skipping the re-pose freezes it.
	if sample==sampled_frame and pattern==last_pattern and motion==machinery_sample and is_equal_approx(effect_boost,posed_boost): return
	posed_boost=effect_boost
	machinery_sample=motion
	sampled_frame=sample
	var hull:=is_hull_id(int(record.id))
	var bone_key: String = str(record.model)+":"+str(sample)+":"+str(machinery_sample)+":"+str(hull)
	if not library.native_bones_cache.has(bone_key):
		if library.native_bones_cache.size()>=1024: library.native_bones_cache.erase(library.native_bones_cache.keys()[0])
		library.native_bones_cache[bone_key]=sample_bones(sample)
	current_bones=library.native_bones_cache[bone_key]
	if use_replacement_geometry and replacement==null and Mods.has_model(str(record.model)):
		replacement=Mods.instance_model(str(record.model),replacement_bounds())
		if replacement!=null: add_child(replacement)
	if replacement!=null:
		last_pattern=pattern
		if figure!=null: figure.hide()
		return
	var call := {"biology":biological_look,"replacement":material_look,"replacement_texture":pack.texture_for(int(record.id)) if pack!=null else null,"resource":record.model,"textures":record.textures,"pattern":pattern,"bones":current_bones,"layout":{"transform":[4096,0,0,0,0,4096,0,0,0,0,4096,0]},"effect":{"lit":true,"ambient":300 if modern_graphics else 1800,"intensity":512 if modern_graphics else 2200,"direction":[1134,3929,0]}}
	call.pixelated_station=int(record.id)>=3300 and int(record.id)<3400 and not library.station_smoothing
	call.smoothed_station=int(record.id)>=3300 and int(record.id)<3400 and library.station_smoothing
	call.station_coating=modern_graphics and int(record.id)>=3300 and int(record.id)<3400
	call.hull_coating=modern_graphics and (call.station_coating or hull)
	call.bioluminescence=.38 if modern_graphics and int(record.id)==4426 else 0.0
	call.distance_haze=0.0015 if int(record.id)>=3300 and int(record.id)<3400 else 0.00032
	# Ship glow geometry was a lighting approximation. Modern flight supplies
	# actual headlights and wakes; these large meshes clip through front views.
	# Hulls only, which is ids 0-11 and the range hull_coating already uses. The
	# cut ran to 20 and took the mine, the torpedo and the S.T.R.E.A.M. gate with
	# it, whose additive geometry is not a lighting stand-in: on the gate it is
	# the flare in the aperture and the trails that stream off the arms.
	call.source_glow_visible=not (modern_graphics and hull)
	call.effect_boost=effect_boost
	call.native_pose_key=str([record.id,sample,machinery_sample,pattern,material_look,modern_graphics,library.station_smoothing,library.ocean_strength,library.effect_glow,effect_boost])
	if figure==null or pattern!=last_pattern:
		if figure!=null: figure.hide()
		if not pattern_figures.has(pattern):
			pattern_figures[pattern]=library.figure(call)
			add_child(pattern_figures[pattern])
		figure=pattern_figures[pattern]; figure.show()
		last_pattern=pattern
	if (call.pixelated_station or call.smoothed_station) and figure.get_meta("station_smoothing",false)!=library.station_smoothing:
		library.apply_figure_materials(figure,call)
	library.pose(figure,call)
	apply_stream_visibility();apply_hinge()
	apply_portal_clip()
	if is_hangar():apply_hangar_open()

func set_full_detail(value: bool) -> void:
	"""A streamed station is built compact and promoted when it is near: a
	player's replacement model belongs to the near form, so it is fetched on
	promotion rather than only on construction."""
	if use_replacement_geometry==value: return
	use_replacement_geometry=value
	if value: sampled_frame=-1; refresh()

func advance(milliseconds: int, render_pose: bool=true) -> void:
	elapsed+=milliseconds
	clock.advance(elapsed)
	if render_pose: refresh()

func bounds() -> AABB:
	var transforms: Array[Transform3D] = []
	for bone: Array in current_bones: transforms.append(Library.matrix(bone))
	return library.pose_bounds(record.model,transforms)

func release_mesh() -> void:
	# Detach the render instance before its shader materials lose their owners.
	for variant in pattern_figures.values():
		var mesh := variant.get_node("Mesh") as MeshInstance3D
		mesh.mesh=null
		var shadow := variant.get_node_or_null("StationShadow") as MeshInstance3D
		if shadow!=null:shadow.mesh=null
func _exit_tree() -> void:
	# Reparenting a station during region promotion also exits the tree.
	# Detach GPU resources only when the model or its owner is being deleted.
	var owner_node: Node=self
	while owner_node!=null:
		if owner_node.is_queued_for_deletion():release_mesh();return
		owner_node=owner_node.get_parent()

func solid_bounds() -> AABB:
	if solid_aabb_ready: return solid_aabb
	var bone_for_vertex: Array = []
	for i in source.bones.size():
		for _v in int(source.bones[i].vertices): bone_for_vertex.append(i)
	var used := {}; var result := AABB(); var first := true
	for polygon in source.polygons:
		if int(polygon.blend)!=0: continue
		for raw_index in polygon.indices:
			var index := int(raw_index)
			if used.has(index): continue
			used[index]=true
			var point := Library.matrix(current_bones[bone_for_vertex[index]])*Library.point(source.vertices,index*3)
			if first: result=AABB(point,Vector3.ZERO); first=false
			else: result=result.expand(point)
	solid_aabb=result; solid_aabb_ready=true
	return result

func headlight_mounts() -> Array:
	"""Where the headlights sit: the two front corners of the hull, either
	side of the cockpit, where the original draws them - not the pods. Each
	is placed a fifth of the hull's width out from the centreline, a little
	below the middle, on the foremost surface found there. Mods still name
	their own mounts."""
	if replacement!=null and not replacement.get_meta("headlight_mounts",[]).is_empty(): return replacement.get_meta("headlight_mounts")
	if has_meta("lamp_mounts"): return get_meta("lamp_mounts")
	var box := solid_bounds()
	var bone_for_vertex: Array = []
	for i in source.bones.size():
		for _v in int(source.bones[i].vertices): bone_for_vertex.append(i)
	var points := {}
	for polygon in source.polygons:
		if int(polygon.blend)!=0: continue
		for raw_index in polygon.indices:
			var index := int(raw_index)
			if not points.has(index): points[index]=Library.matrix(current_bones[bone_for_vertex[index]])*Library.point(source.vertices,index*3)
	var mounts: Array = []
	for side in [-1,1]:
		var target := Vector3(box.get_center().x+side*box.size.x*.22,box.get_center().y-box.size.y*.1,box.position.z)
		# The foremost surface in a narrow column at the mount, widening the
		# column only if nothing is there; a wide one caught the cockpit's
		# nose and hung the lamp a metre ahead of the hull.
		var front := INF
		for width in [.04,.08,.16]:
			for point in points.values():
				if absf(point.x-target.x)<box.size.x*width and absf(point.y-target.y)<box.size.y*.25: front=minf(front,point.z)
			if front!=INF: break
		if front==INF: front=box.position.z
		mounts.append(Vector3(target.x,target.y,front-.05))
	set_meta("lamp_mounts",mounts)
	return mounts

func replacement_bounds() -> AABB:
	var result := solid_bounds()
	if result.size.length_squared()<0.001: result=bounds()
	# A replacement creature includes its original paired appendage. Fitting
	# uses the complete rest anatomy; collision and original pose bounds stay exact.
	if not companion_resource.is_empty():
		var companion: Dictionary = library.data(companion_resource)
		var transforms: Array = []; var cursor := 0
		for bone in companion.bones:
			var transform: Array = bone.matrix.duplicate()
			if int(bone.parent)>=0: transform=multiply(transforms[int(bone.parent)],transform)
			transforms.append(transform)
			for _vertex in int(bone.vertices):
				result=result.expand(Library.matrix(transform)*Library.point(companion.vertices,cursor*3)); cursor+=1
	return result

func set_portal_clip(enabled: bool, plane: Vector4=Vector4.ZERO) -> void:
	portal_enabled=enabled;portal_plane=plane;apply_portal_clip()
func apply_portal_clip() -> void:
	if figure==null:return
	var mesh: MeshInstance3D=figure.get_node("Mesh")
	for index in mesh.mesh.get_surface_count():
		var original: ShaderMaterial=mesh.get_surface_override_material(index)
		if original.has_meta("portal_original"):original=original.get_meta("portal_original")
		if not portal_enabled:
			mesh.set_surface_override_material(index,original);continue
		var key:=original.get_instance_id()
		if not portal_materials.has(key):
			var own: ShaderMaterial=original.duplicate();own.set_meta("portal_original",original);portal_materials[key]=own
		var material: ShaderMaterial=portal_materials[key]
		material.set_shader_parameter("portal_clip_enabled",true);material.set_shader_parameter("portal_clip_plane",portal_plane)
		mesh.set_surface_override_material(index,material)
	if not portal_enabled:portal_materials.clear()
