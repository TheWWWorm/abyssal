extends Node3D
## Presentation-only pools. All positions and ages come from fixed simulation ticks.
const Library = preload("res://scripts/model_library.gd")
const Pose = preload("res://native/simulation/ship_transform.gd")
const Math = preload("res://native/simulation/fixed_math.gd")
var owner_view
var projectile_nodes: Dictionary = {}
var modern_forms: Dictionary = {}
var impact_forms: Array=[]
var impact_count:=0
const WeaponForm=preload("res://native/presentation/weapon_form.gd")
var segments := MultiMeshInstance3D.new()
var ribbons := MultiMeshInstance3D.new()
var cables := MultiMeshInstance3D.new()
var hook_heads := MultiMeshInstance3D.new()
var bursts := MultiMeshInstance3D.new()
var bubbles := MultiMeshInstance3D.new()
var puffs := MultiMeshInstance3D.new()
var lights: Array[OmniLight3D] = []
var segment_count := 0
var ribbon_count := 0
var hook_count := 0
var visual_time := 0.0
var burst_count := 0
var bubble_count := 0
var projectile_count := 0
var light_count := 0
var pose := Pose.new()
var player_wake: Array=[]
var wake_timer := 0.0
var wake_serial := 0
var torpedo_wakes: Array=[]
var torpedo_tails: Dictionary={}
var wake_previous: Array[Vector3]=[]
var effect_bounds: Dictionary={}
var wrecks := preload("res://native/presentation/wreck_effects.gd").new()
var aftermath_enabled := true
## Independent of the lighting preset and the audio preference.
var enhanced_weapons := true
## A creature's death, and the aquar's (a ship that dies as a fish): the
## original's ao(1,2) sets the fischtod model (resource 9995) at the body at
## half scale (f(2048)), steps its animation once at 60 ms a frame (e(60),
## played with a((byte)1)) and draws it until 4000 ms. Its ten double-sided
## quads carry the dark red cloud of fx.bmp, added to the water by the MBAC
## blend: the red cloud that marks a kill.
const BLOOD_MODEL := 9995
const BLOOD_FRAME_MS := 60
## fischtod's 40 frames: the cloud billows, then shrinks to nothing by the
## last (2.4 s), and the remaining time to 4000 ms draws nothing more.
const BLOOD_FRAMES := 40
const BLOOD_LIFETIME_MS := 4000
const BLOOD_SCALE := 0.5
## Clouds drawn at once; in a larger fight the latest kills go unshown.
const BLOOD_CAPACITY := 12
## fx.bmp's blood cloud, in texels of its 128-texel atlas, for a JAR whose
## cache has no fischtod model: a small dark red puff stands in.
const BLOOD_REGION := Rect2(96,96,31,31)
const BLOOD_ATLAS := "data/textures/fx.bmp"
## The harpoon line (cx): two crossed strips 40 units either side of the
## line, wearing one texel of fx.bmp picked by the harpoon (items 15, 16 and
## 17), added to the water. So each harpoon draws its own colour, see-through.
const HARPOON_TEXELS := {15:Vector2i(34,104),16:Vector2i(29,101),17:Vector2i(2,104)}
const HARPOON_WIDTH := 0.4
const HARPOON_OPACITY := 0.45
## For a JAR whose cache has no fx atlas.
const HARPOON_FALLBACK := Color("649a9b")
var harpoon_colors := {}
var projectile_colors := {}
var projectile_materials := {}
var projectile_bounds := {}
var blood_clouds: Array = []
var blood_count := 0
var puff_count := 0

func set_aftermath(on: bool) -> void:
	if aftermath_enabled==on:return
	aftermath_enabled=on
	if not is_node_ready():return
	if not on:wrecks.reset()
	if owner_view!=null and owner_view.world!=null and owner_view.world.region!=null:
		update(owner_view.world.region,0,0.0)

func set_enhanced_weapons(on: bool) -> void:
	if enhanced_weapons==on:return
	enhanced_weapons=on
	if is_node_ready():reset(true)

func pool(node: MultiMeshInstance3D, mesh: Mesh, capacity: int) -> void:
	var instances := MultiMesh.new(); instances.transform_format=MultiMesh.TRANSFORM_3D
	instances.use_colors=true; instances.use_custom_data=true; instances.mesh=mesh
	instances.instance_count=capacity; instances.visible_instance_count=0; node.multimesh=instances
	node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.custom_aabb=AABB(Vector3.ONE*-1,Vector3.ONE*2); add_child(node)

func include_bounds(node: MultiMeshInstance3D, at: Vector3, radius: float) -> void:
	var box := AABB(at-Vector3.ONE*radius,Vector3.ONE*radius*2)
	effect_bounds[node]=box if not effect_bounds.has(node) else effect_bounds[node].merge(box)

func refresh_bounds() -> void:
	for node in [segments,ribbons,cables,hook_heads,bursts,bubbles,puffs]:
		node.custom_aabb=effect_bounds.get(node,AABB(Vector3.ONE*-1,Vector3.ONE*2))
func _ready() -> void:
	add_child(wrecks)
	var tube := CylinderMesh.new(); tube.top_radius=1; tube.bottom_radius=1; tube.height=1; tube.radial_segments=6; tube.rings=1
	var glow := ShaderMaterial.new(); glow.shader=preload("res://native/presentation/combat_line.gdshader")
	tube.material=glow; pool(segments,tube,128)
	var ribbon := QuadMesh.new();ribbon.size=Vector2.ONE
	var ribbon_material := ShaderMaterial.new();ribbon_material.shader=preload("res://native/presentation/weapon_ribbon.gdshader")
	ribbon.material=ribbon_material;pool(ribbons,ribbon,384)
	var cable := CylinderMesh.new();cable.top_radius=1; cable.bottom_radius=1; cable.height=1; cable.radial_segments=10; cable.rings=1
	var cable_material:=ShaderMaterial.new();cable_material.shader=preload("res://native/presentation/weapon_tether.gdshader");cable_material.set_shader_parameter("cable",true)
	cable_material.render_priority=1
	var cable_glow:=ShaderMaterial.new();cable_glow.shader=cable_material.shader
	cable_glow.set_shader_parameter("cable",true);cable_glow.set_shader_parameter("pulse_glow",true)
	cable_glow.render_priority=2;cable_material.next_pass=cable_glow
	cable.material=cable_material;pool(cables,cable,32)
	var head:=hook_mesh();var head_material:=ShaderMaterial.new();head_material.shader=preload("res://native/presentation/weapon_tether.gdshader")
	head.surface_set_material(0,head_material);pool(hook_heads,head,32)
	var quad := QuadMesh.new(); quad.size=Vector2.ONE
	var material := ShaderMaterial.new(); material.shader=preload("res://native/presentation/combat_sprite.gdshader"); quad.material=material
	pool(bursts,quad,256)
	var bubble_quad := QuadMesh.new();bubble_quad.size=Vector2.ONE
	var bubble_material := ShaderMaterial.new();bubble_material.shader=preload("res://native/presentation/bubble.gdshader")
	bubble_quad.material=bubble_material;pool(bubbles,bubble_quad,1024)
	var puff_quad := QuadMesh.new();puff_quad.size=Vector2.ONE
	var puff_material := ShaderMaterial.new();puff_material.shader=preload("res://native/presentation/blood_puff.gdshader")
	puff_quad.material=puff_material;pool(puffs,puff_quad,BLOOD_CAPACITY)
	for i in 4:
		var light := OmniLight3D.new(); light.shadow_enabled=false; light.omni_range=55; light.light_volumetric_fog_energy=0.2; light.hide(); add_child(light); lights.append(light)
func reset(keep_player_wake: bool=false) -> void:
	effect_bounds.clear()
	torpedo_wakes.clear();torpedo_tails.clear()
	if not keep_player_wake:player_wake.clear();wake_previous.clear();wake_timer=0.0;wake_serial=0
	if not keep_player_wake:wrecks.reset()
	for node in projectile_nodes.values(): node.queue_free()
	projectile_nodes.clear()
	for form in modern_forms.values():form.queue_free()
	modern_forms.clear()
	for form in impact_forms:form.queue_free()
	impact_forms.clear();impact_count=0
	# A full rebuild may change the graphics mode the clouds were built for.
	for node in blood_clouds:
		if keep_player_wake: node.hide()
		else: node.queue_free()
	if not keep_player_wake: blood_clouds.clear(); puffs.multimesh.mesh.material.remove_meta("atlas_checked"); harpoon_colors.clear();projectile_colors.clear()
	projectile_materials.clear();projectile_bounds.clear()
	for node in [segments,ribbons,cables,hook_heads,bursts,bubbles,puffs]: node.multimesh.visible_instance_count=0
	refresh_bounds()
	for light in lights: light.hide()
	segment_count=0; ribbon_count=0; hook_count=0; burst_count=0; bubble_count=0; projectile_count=0; light_count=0; blood_count=0; puff_count=0
static func hook_mesh() -> ArrayMesh:
	# Three compact emitter silhouettes, selected per instance. The original
	# shared a white tip; colour and form now remain legible from behind.
	var surface:=SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for kind in 3:
		var profile: Array=[Vector2(.09,-.5),Vector2(.12,-.12),Vector2(.20,.12),Vector2(0,.5)]
		if kind==1:profile=[Vector2(.12,-.5),Vector2(.23,-.12),Vector2(.23,.18),Vector2(0,.5)]
		if kind==2:profile=[Vector2(.09,-.5),Vector2(.14,-.08),Vector2(.16,.3),Vector2(0,.5)]
		for ring in profile.size()-1:
			for side in 12:
				var a:=float(side)*TAU/12;var b:=float(side+1)*TAU/12
				var lo: Vector2=profile[ring];var hi: Vector2=profile[ring+1]
				var points:=[Vector3(cos(a)*lo.x,lo.y,sin(a)*lo.x),Vector3(cos(b)*lo.x,lo.y,sin(b)*lo.x),Vector3(cos(a)*hi.x,hi.y,sin(a)*hi.x),Vector3(cos(b)*hi.x,hi.y,sin(b)*hi.x)]
				for index in [0,2,1,1,2,3]:
					surface.set_uv2(Vector2(kind,0));surface.add_vertex(points[index])
		var prongs: int=[2,4,3][kind]
		for side in prongs:
			var axis:=Basis(Vector3.UP,float(side)*TAU/prongs)
			var reach: float=[.48,.57,.68][kind]
			var points:=[Vector3(.10,.22,-.10),Vector3(reach,-.12,0),Vector3(.13,-.30,.10),Vector3(.10,.22,.10)]
			for index in [0,1,2,0,3,1,3,2,1,0,2,3]:
				surface.set_uv2(Vector2(kind,1));surface.add_vertex(axis*points[index])
		if kind>0:
			# An induction collar on F-Traxx, an open three-lobed containment
			# ring on the SMI military tractor-beam emitter.
			for side in 24:
				var a:=float(side)*TAU/24;var b:=float(side+1)*TAU/24
				var ra:=.43 if kind==1 else .48+.10*cos(a*3)
				var rb:=.43 if kind==1 else .48+.10*cos(b*3)
				var points:=[Vector3(cos(a)*(ra-.035),-.10,sin(a)*(ra-.035)),Vector3(cos(a)*(ra+.035),-.10,sin(a)*(ra+.035)),Vector3(cos(b)*(rb-.035),-.10,sin(b)*(rb-.035)),Vector3(cos(b)*(rb+.035),-.10,sin(b)*(rb+.035))]
				for index in [0,2,1,1,2,3]:
					surface.set_uv2(Vector2(kind,1));surface.add_vertex(points[index])
	surface.generate_normals();return surface.commit()
static func segment_pose(start: Vector3, end: Vector3, width: float) -> Transform3D:
	var delta := end-start
	if delta.length_squared()<0.000001: return Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO),start)
	var direction := delta.normalized()
	var right := direction.cross(Vector3.RIGHT if absf(direction.y)>0.99 else Vector3.UP).normalized()
	return Transform3D(Basis(right*width,delta,right.cross(direction)*width),(start+end)/2)
func segment(start: Vector3, end: Vector3, width: float, color: Color) -> void:
	if segment_count>=segments.multimesh.instance_count: return
	include_bounds(segments,start,maxf(width,0.1));include_bounds(segments,end,maxf(width,0.1))
	segments.multimesh.set_instance_transform(segment_count,segment_pose(start,end,width))
	segments.multimesh.set_instance_color(segment_count,color); segment_count+=1
func ribbon(start: Vector3, end: Vector3, width: float, color: Color, trail: bool=false, style: float=0.0) -> void:
	if ribbon_count>=ribbons.multimesh.instance_count or start.distance_squared_to(end)<.000001:return
	# Use the same expanded bounds as the other filtered sprites at distance.
	var radius: float=maxf(width,end.distance_to(owner_view.camera.global_position)*4.0/maxf(1,owner_view.camera.get_viewport().get_visible_rect().size.y))
	include_bounds(ribbons,start,radius);include_bounds(ribbons,end,radius)
	ribbons.multimesh.set_instance_transform(ribbon_count,segment_pose(start,end,width))
	ribbons.multimesh.set_instance_color(ribbon_count,color)
	ribbons.multimesh.set_instance_custom_data(ribbon_count,Color(1 if trail else 0,visual_time,style,0));ribbon_count+=1
func modern_form(key: String, id: int, color: Color, at: Vector3, direction: Vector3, rear: float=1000.0) -> void:
	if modern_forms.has(key) and modern_forms[key].equipment!=id:
		modern_forms[key].queue_free();modern_forms.erase(key)
	if not modern_forms.has(key):
		var form:=WeaponForm.new();form.configure(id,color);add_child(form);modern_forms[key]=form
	var form: Node3D=modern_forms[key]
	form.position=at
	if direction.length_squared()>.00001:form.basis=Basis.looking_at(direction.normalized(),Vector3.RIGHT if absf(direction.normalized().y)>.99 else Vector3.UP)
	form.show();form.advance(visual_time,owner_view.camera,rear)
func hook_line(start: Vector3, end: Vector3, weapon) -> void:
	var color:=harpoon_color(weapon)
	if enhanced_weapons:
		if start.distance_squared_to(end)<.000001:return
		if hook_count<cables.multimesh.instance_count:
			var direction: Vector3=(end-start).normalized()
			var length: float=minf(2.0,start.distance_to(end))
			modern_form("hook:"+str(hook_count),weapon.equipment_id,Color(color,1),end,direction,start.distance_to(end))
			cables.multimesh.set_instance_transform(hook_count,segment_pose(start,end,.12 if weapon.equipment_id==15 else .16))
			cables.multimesh.set_instance_color(hook_count,WeaponForm.HARPOON_COLORS[clampi(weapon.equipment_id-15,0,2)])
			cables.multimesh.set_instance_custom_data(hook_count,Color(clampi(weapon.equipment_id-15,0,2),visual_time,0,0))
			hook_heads.multimesh.set_instance_transform(hook_count,segment_pose(end-direction*length,end,1.0))
			hook_heads.multimesh.set_instance_color(hook_count,Color(color,1))
			hook_heads.multimesh.set_instance_custom_data(hook_count,Color(clampi(weapon.equipment_id-15,0,2),visual_time,0,0))
			var wire_bound: float=maxf(.1,maxf(start.distance_to(owner_view.camera.global_position),end.distance_to(owner_view.camera.global_position))*2.0/maxf(1.0,owner_view.camera.get_viewport().get_visible_rect().size.y))
			include_bounds(cables,start,wire_bound);include_bounds(cables,end,wire_bound);include_bounds(hook_heads,end,maxf(length,wire_bound*4))
			hook_count+=1
	else:segment(start,end,HARPOON_WIDTH,color)
static func projectile_position(weapon, index: int, fraction: float) -> Vector3:
	var current:=Library.point(weapon.positions[index])
	if index>=weapon.previous_positions.size():return current
	return Library.point(weapon.previous_positions[index]).lerp(current,clampf(fraction,0,1))
static func trail_length(weapon, index: int, fraction: float, maximum: float) -> float:
	var age := maxf(0,float(weapon.lifetime-weapon.remaining[index])-(1.0-clampf(fraction,0,1))*weapon.velocity_step_ms)
	return minf(maximum,weapon.speed*age*Library.UNIT)
func hook_muzzle(region, weapon) -> Vector3:
	return owner_view.world.render_pose(region.player)*Library.point(weapon.muzzle)
func shade_projectile(visual, disc: bool) -> void:
	if visual.figure==null:return
	var mesh: MeshInstance3D=visual.figure.get_node("Mesh")
	for i in mesh.mesh.get_surface_count():
		var original:=mesh.get_active_material(i) as ShaderMaterial
		if original==null:continue
		if original.has_meta("weapon_original"):original=original.get_meta("weapon_original")
		if not enhanced_weapons:
			mesh.set_surface_override_material(i,original);continue
		if int(visual.record.id)==16:
			var key:=original.get_instance_id()
			if not projectile_materials.has(key):
				var own:=ShaderMaterial.new();own.shader=preload("res://native/presentation/weapon_torpedo.gdshader")
				own.set_meta("weapon_original",original)
				for parameter in ["source_bones","albedo","texture_size"]:own.set_shader_parameter(parameter,original.get_shader_parameter(parameter))
				projectile_materials[key]=own
			mesh.set_surface_override_material(i,projectile_materials[key]);continue
		if not original.shader.code.contains("blend_add") and not original.shader.code.contains("blend_sub"):continue
		var key:=original.get_instance_id()
		if not projectile_materials.has(key):
			if projectile_materials.size()>=512:projectile_materials.clear()
			var own:=ShaderMaterial.new();own.shader=preload("res://native/presentation/weapon_surface.gdshader")
			own.set_meta("weapon_original",original)
			own.set_shader_parameter("source_bones",original.get_shader_parameter("source_bones"))
			var box:=projectile_source_bounds(visual)
			own.set_shader_parameter("effect_center",box.get_center());own.set_shader_parameter("effect_extent",box.size*.5)
			own.set_shader_parameter("long_axis",box.size.max_axis_index())
			own.set_shader_parameter("disc",disc)
			own.set_shader_parameter("family",2 if int(visual.record.id)==6766 else 1 if int(visual.record.id) in [6754,6755,6756] else 0)
			own.set_shader_parameter("subtractive",original.shader.code.contains("blend_sub"))
			own.set_shader_parameter("pigment",projectile_color(visual))
			projectile_materials[key]=own
		var material: ShaderMaterial=projectile_materials[key]
		material.set_shader_parameter("visual_time",visual_time)
		mesh.set_surface_override_material(i,material)
func projectile_source_bounds(visual) -> AABB:
	var id: int=visual.record.id
	if not projectile_bounds.has(id):
		var points: Array=visual.source.vertices
		var box:=AABB(Library.point(points),Vector3.ZERO)
		for i in range(1,points.size()/3):box=box.expand(Library.point(points,i*3))
		projectile_bounds[id]=box
	return projectile_bounds[id]
func projectile_color(visual) -> Color:
	# Sample the projectile's own UV patches, including a replacement atlas.
	# Modern forms retain the imported pigment; Classic retains the mesh.
	var id: int=visual.record.id
	if projectile_colors.has(id):return projectile_colors[id]
	var total:=Vector3.ZERO;var weight:=0.0
	if not visual.record.get("textures",[]).is_empty():
		var atlas: String=visual.record.textures[0]
		var texture: Texture2D=owner_view.library.texture(atlas)
		var image: Image=texture.get_image() if texture!=null else null
		if image!=null and not image.is_empty():
			if image.is_compressed():image.decompress()
			var scale: Vector2=Vector2(image.get_size())/owner_view.library.texture_size(atlas)
			for polygon in visual.source.polygons:
				# Subtractive faces carry the complementary colour that used to
				# darken the water, not the emitted projectile's pigment.
				if int(polygon.texture)!=0 or int(polygon.blend)!=4:continue
				var low:=Vector2(INF,INF);var high:=Vector2(-INF,-INF)
				for j in polygon.indices.size():
					var uv:=Vector2(polygon.attributes[j*5],polygon.attributes[j*5+1])
					low=low.min(uv);high=high.max(uv)
				for y in 3:
					for x in 3:
						var uv:=((low+(high-low)*Vector2((x+.5)/3.0,(y+.5)/3.0))+Vector2(.5,.5))*scale
						var pixel:=image.get_pixelv(Vector2i(uv).clamp(Vector2i.ZERO,image.get_size()-Vector2i.ONE))
						# Pure white is the source atlas's transparent key.
						if minf(pixel.r,minf(pixel.g,pixel.b))>.98:continue
						var w: float=pixel.a*maxf(pixel.r,maxf(pixel.g,pixel.b))
						total+=Vector3(pixel.r,pixel.g,pixel.b)*w;weight+=w
	var color:=Color(.55,.75,.8)
	if weight>.001:total/=weight;color=Color(total.x,total.y,total.z)
	projectile_colors[id]=color;return color
func sprite(node: MultiMeshInstance3D, index: int, at: Vector3, diameter: float, age: float, kind: float, color: Color) -> void:
	# Quads expand in the vertex shader, beyond their unit-mesh bounds.
	# Include billboard corners and the minimum on-screen bubble diameter.
	var radius := maxf(diameter,1.0)
	if owner_view!=null and is_instance_valid(owner_view.camera):
		var eye: Camera3D=owner_view.camera
		radius=maxf(radius,at.distance_to(eye.global_position)*20.0/maxf(1.0,eye.get_viewport().get_visible_rect().size.y))
	include_bounds(node,at,radius)
	node.multimesh.set_instance_transform(index,Transform3D(Basis.IDENTITY,at))
	node.multimesh.set_instance_color(index,color)
	node.multimesh.set_instance_custom_data(index,Color(diameter,clampf(age,0,1),kind,0))
func burst(at: Vector3, radius: float, age: float, color: Color, debris: bool=false) -> void:
	if burst_count>=bursts.multimesh.instance_count: return
	sprite(bursts,burst_count,at,radius*2,age,0,color); burst_count+=1
	if debris and age<0.65:
		for j in 8:
			var direction := Vector3(cos(j*2.399),sin(j*1.83)*0.6,sin(j*2.399)).normalized()
			var start := at+direction*radius*(0.05+age)*1.2
			segment(start,start+direction*radius*0.22*(1-age),0.045*(1-age),Color(color,1-age/0.65))
	if age<0.25 and light_count<lights.size() and at.distance_to(owner_view.camera.global_position)<300:
		var light := lights[light_count]; light.position=at; light.light_color=color; light.light_energy=3*(1-age*4); light.show(); light_count+=1
func coil_color(equipment: int) -> Color:
	return Color(line_color(clampi(equipment-3,0,2)+15),1.0)
func impact(event: Dictionary, age: float) -> void:
	var at:=Library.point(event.position)
	if not enhanced_weapons:
		burst(at,3.0,age,Color("d2dfd7"),true);return
	var color:=Color("91c5d7")
	if event.get("beam",false):color=coil_color(int(event.get("equipment",3)))
	elif not event.get("homing",false):
		var model_id:=int(event.get("model",-1))
		if model_id>=0 and not projectile_colors.has(model_id):
			var sample=owner_view.model(model_id,32,self,false)
			if sample!=null:sample.hide();projectile_color(sample);sample.queue_free()
		color=projectile_colors.get(model_id,color)
	var radius:=clampf(1.2+sqrt(maxf(0,float(event.get("damage",3))))*.35,1.8,4.0)
	if impact_count<64:
		var id: int=event.get("equipment",0)
		if impact_count==impact_forms.size():impact_forms.append(null)
		if impact_forms[impact_count]==null or impact_forms[impact_count].equipment!=id:
			if impact_forms[impact_count]!=null:impact_forms[impact_count].queue_free()
			var form:=WeaponForm.new();form.configure_impact(id,color);add_child(form);impact_forms[impact_count]=form
		var form: Node3D=impact_forms[impact_count];impact_count+=1
		form.position=at
		var direction:=Library.point(event.get("direction",[0,0,4096])).normalized()
		form.basis=Basis.looking_at(direction,Vector3.RIGHT if absf(direction.y)>.99 else Vector3.UP)
		form.show();form.advance_impact(visual_time,age,radius*(1.6 if event.get("homing",false) else 1.0))
	var normal: Vector3=-Library.point(event.get("direction",[0,0,4096])).normalized()
	var right:=normal.cross(Vector3.RIGHT if absf(normal.y)>.98 else Vector3.UP).normalized()
	var up:=right.cross(normal)
	if event.get("homing",false):
		for i in 8:
			var angle:=i*2.399963
			var direction: Vector3=(right*cos(angle)+up*sin(angle)+normal*.6).normalized()
			bubble(at+direction*radius*age*2+Vector3.UP*age*.8,.15+age*.35,(1-age)*.4)
	elif age<.65:
		for i in 5:
			var angle:=i*2.399963
			var direction: Vector3=(right*cos(angle)+up*sin(angle)+normal*.75).normalized()
			var tip:=at+direction*radius*(.1+age*1.6)
			ribbon(tip-direction*radius*.28*(1-age),tip,.12,Color(color,(1-age)*.45),true)
func blood(at: Vector3, age_ms: int) -> void:
	if owner_view.registry.has(BLOOD_MODEL):
		if blood_count>=BLOOD_CAPACITY: return
		if blood_count==blood_clouds.size():
			var created=owner_view.model(BLOOD_MODEL,BLOOD_FRAME_MS,self,false)
			if created==null: return
			blood_clouds.append(created)
		var visual=blood_clouds[blood_count]; blood_count+=1
		visual.transform=Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*BLOOD_SCALE),at)
		# The frame follows the event's age, so a paused or frozen
		# simulation holds the cloud and a reopened view resumes it.
		visual.clock.playing=false
		visual.clock.frame=mini(visual.clock.end_frame,age_ms/BLOOD_FRAME_MS)
		visual.refresh(); visual.show()
		return
	# fischtod has shrunk away by its last frame; the stand-in fades with it.
	var fade: float=float(age_ms)/float(BLOOD_FRAME_MS*BLOOD_FRAMES)
	if fade>=1.0 or puff_count>=puffs.multimesh.instance_count: return
	sprite(puffs,puff_count,at,6.0,fade,0,Color("5a0606")); puff_count+=1
func blood_atlas() -> void:
	# The stand-in puff wears the atlas's cloud when the JAR supplied one.
	var material: ShaderMaterial=puffs.multimesh.mesh.material
	var path: String=owner_view.library.root.path_join(BLOOD_ATLAS)+".png"
	var atlas: Texture2D=owner_view.library.texture(BLOOD_ATLAS) if FileAccess.file_exists(path) else null
	material.set_shader_parameter("cloud_enabled",atlas!=null)
	if atlas!=null:
		var size: Vector2=owner_view.library.texture_size(BLOOD_ATLAS)
		material.set_shader_parameter("cloud",atlas)
		material.set_shader_parameter("cloud_region",Vector4(BLOOD_REGION.position.x/size.x,BLOOD_REGION.position.y/size.y,BLOOD_REGION.size.x/size.x,BLOOD_REGION.size.y/size.y))
func harpoon_color(weapon) -> Color:
	"""The texel of the atlas the harpoon's line wears, read where a player's
	own atlas has it, at whatever size that atlas is drawn."""
	return line_color(weapon.equipment_id)
func line_color(id: int) -> Color:
	if not harpoon_colors.has(id):
		var color := HARPOON_FALLBACK
		var path: String=owner_view.library.root.path_join(BLOOD_ATLAS)+".png"
		var atlas: Texture2D=owner_view.library.texture(BLOOD_ATLAS) if HARPOON_TEXELS.has(id) and FileAccess.file_exists(path) else null
		var image: Image=atlas.get_image() if atlas!=null else null
		if image!=null and not image.is_empty():
			if image.is_compressed(): image.decompress()
			var texels: Vector2=owner_view.library.texture_size(BLOOD_ATLAS)
			var at: Vector2=(Vector2(HARPOON_TEXELS[id])+Vector2(.5,.5))*Vector2(image.get_size())/texels
			color=image.get_pixelv(Vector2i(clampi(int(at.x),0,image.get_width()-1),clampi(int(at.y),0,image.get_height()-1)))
		harpoon_colors[id]=Color(color.r,color.g,color.b,HARPOON_OPACITY)
	return harpoon_colors[id]
func bubble(at: Vector3, scale: float, opacity: float, kind: int=1) -> void:
	if bubble_count>=bubbles.multimesh.instance_count or at.distance_squared_to(owner_view.camera.global_position)>160000: return
	var distance: float=at.distance_to(owner_view.camera.global_position)
	var visibility: float=(1.0-smoothstep(240.0,400.0,distance))*smoothstep(0.0,.12,1.0-opacity)
	sprite(bubbles,bubble_count,at,maxf(0.04,scale),1-opacity*visibility,kind,Color("8bbbc8")); bubble_count+=1
func torpedo_tail(weapon, index: int, visual, at: Vector3) -> void:
	var key:=str(weapon.get_instance_id())+":"+str(index)
	var serial: int=weapon.launch_serials[index]
	var anchor: Vector3=owner_view.world.geography.anchor
	var rear: float=2.25*(1.0+clampi(weapon.equipment_id-12,0,2)*.2) if enhanced_weapons else maxf(0,visual.bounds().end.z)*2.0
	var tail: Vector3=at+visual.basis.z.normalized()*rear+anchor
	if not torpedo_tails.has(key) or torpedo_tails[key].serial!=serial:
		torpedo_tails[key]={"serial":serial,"at":tail,"time":visual_time};return
	var previous: Dictionary=torpedo_tails[key]
	var distance: float=tail.distance_to(previous.at)
	var kind: int=clampi(weapon.equipment_id-12,0,2)
	var spacing: float=[.8,1.2,1.1][kind]
	if distance<spacing:return
	var count:=mini(12,floori(distance/spacing))
	var right: Vector3=visual.basis.x.normalized();var up: Vector3=visual.basis.y.normalized()
	for n in count:
		var fraction: float=float(n+1)/count
		var birth: float=lerpf(previous.time,visual_time,fraction)
		var angle:=birth*25.0+n*2.39996
		var radial: Vector3=right*cos(angle)+up*sin(angle)
		var size: float=[.32,.13,.28][kind]
		var spread: float=[.20,.10,.28][kind]
		var point: Vector3=previous.at.lerp(tail,fraction)+radial*spread
		torpedo_wakes.append({"at":point,"time":birth,"kind":kind,"size":size*(.8+.3*sin(angle)),"drift":radial*.25+Vector3.UP*.4})
		if torpedo_wakes.size()>512:torpedo_wakes.pop_front()
	torpedo_tails[key]={"serial":serial,"at":tail,"time":visual_time}
func show_torpedo_wakes() -> void:
	var anchor: Vector3=owner_view.world.geography.anchor
	torpedo_wakes=torpedo_wakes.filter(func(p):return visual_time-p.time<1.0)
	for key in torpedo_tails.keys():
		if visual_time-torpedo_tails[key].time>1.5:torpedo_tails.erase(key)
	for particle in torpedo_wakes:
		var age: float=maxf(0,visual_time-particle.time)
		var span: float=[1.0,.60,.80][particle.kind]
		if age>=span:continue
		var opacity: float=[.58,.38,.48][particle.kind]*(1.0-age/span)
		bubble(particle.at+particle.drift*age-anchor,particle.size*(1.0+age*.8),opacity,6 if particle.kind==2 else 5)
func update_player_wake(region, milliseconds: float) -> void:
	var dt := maxf(0,milliseconds*.001)
	var anchor: Vector3=owner_view.world.geography.anchor
	for particle in player_wake:
		particle.age+=dt;particle.at+=particle.velocity*dt
	player_wake=player_wake.filter(func(particle):return particle.age<2.4)
	if owner_view.world.session.docked:
		player_wake.clear();wake_previous.clear();wake_timer=0;return
	var model=owner_view.player_model
	if model==null:return
	var frame: Transform3D=model.global_transform
	var outlets: Array[Vector3]=[]
	for local in model.exhaust_outlets():outlets.append(frame*local+anchor)
	if wake_previous.size()!=outlets.size():wake_previous=outlets.duplicate()
	# A lost hull runs no engines; the bubbles already out rise on.
	if dt>0 and region.player.health.hull>0:
		var power: float=clampf(region.player.throttle/100.0,0,1)
		var boosting: bool=region.player.boost_active and not region.cinematic()
		var interval := .012 if boosting else lerpf(.24,.035,power)
		wake_timer=minf(wake_timer+dt,interval*8)
		while wake_timer>=interval:
			wake_timer-=interval
			for side in outlets.size():
				var at := wake_previous[side].lerp(outlets[side],clampf(1.0-wake_timer/dt,0,1))
				# Deterministic turbulence is sampled once at birth, never per frame.
				var phase := float(wake_serial)*2.399963
				var scatter := frame.basis.x*cos(phase)+frame.basis.y*sin(phase)
				var size := .16+.22*(sin(phase*1.7)*.5+.5)
				# Boost leaves a dense white wash from the same engine outlets.
				# Each particle keeps its birth state so the trail fades naturally
				# when boost ends, without changing speed or gameplay randomness.
				player_wake.append({"at":at+scatter*(.38 if boosting else .22),"velocity":frame.basis.z*(18.0 if boosting else 3+power*4)+scatter*(1.4 if boosting else .85)+Vector3.UP*.9,"age":0.0,"power":power,"size":size*(2.8 if boosting else 1.0),"boost":boosting})
				wake_serial+=1
		wake_previous=outlets.duplicate()
	for particle in player_wake:
		var age: float=particle.age/2.4
		var boosted: bool=particle.get("boost",false)
		var opacity: float=smoothstep(0.0,.02,age)*pow(1.0-age,1.4)*(1.0 if boosted else lerpf(.28,.8,particle.power))
		var at: Vector3=particle.at-anchor
		var distance: float=at.distance_to(owner_view.camera.global_position)
		opacity*=smoothstep(4.0,12.0,distance)*(1.0-smoothstep(240.0,400.0,distance))
		if opacity<=.001 or bubble_count>=bubbles.multimesh.instance_count:continue
		sprite(bubbles,bubble_count,at,particle.size*(1.0+age*1.8),1-opacity,3 if boosted else 2,Color("eefaff") if boosted else Color("c4e3e9"));bubble_count+=1
func update(region, milliseconds: int, render_milliseconds: float=-1.0) -> void:
	effect_bounds.clear()
	segment_count=0; ribbon_count=0; hook_count=0; burst_count=0; bubble_count=0; projectile_count=0; light_count=0; blood_count=0; puff_count=0
	# Simulation time keeps filaments and tether detail still in Action Freeze.
	visual_time=float(region.elapsed_ms+owner_view.world.accumulator)*.001
	update_player_wake(region,float(milliseconds) if render_milliseconds<0 else render_milliseconds)
	wrecks.update(region,float(milliseconds) if render_milliseconds<0 else render_milliseconds,owner_view.world.geography.anchor,owner_view.camera.global_position,owner_view.modern_graphics and aftermath_enabled)
	for light in lights: light.hide()
	for node in projectile_nodes.values(): node.hide()
	for form in modern_forms.values():form.hide()
	for form in impact_forms:form.hide()
	impact_count=0
	pose.math.sine_table=region.sine
	var weapons: Array = region.weapons.duplicate()
	for weapon in region.loadout.all_weapons():
		if not weapon in weapons: weapons.append(weapon)
	for weapon in weapons:
		for i in weapon.remaining.size():
			if weapon.remaining[i]<=0: continue
			var fraction: float=clampf(owner_view.world.accumulator/owner_view.world.STEP_MS,0,1) if owner_view.world.render_interpolation_enabled else 1.0
			var at := projectile_position(weapon,i,fraction)
			var velocity := Library.point(weapon.velocities[i])
			if weapon.beam:
				# bc.f renders the travelling segment, two velocity steps long.
				var color:=coil_color(weapon.equipment_id)
				var length := trail_length(weapon,i,fraction,velocity.length()*2)
				if length>.001:
					if enhanced_weapons:
						modern_form(str(weapon.get_instance_id())+":"+str(i),clampi(weapon.equipment_id,3,5),color,at,velocity,trail_length(weapon,i,fraction,30.0))
						# A fine axial streak connects the compressed fields into one pulse.
						ribbon(at-velocity.normalized()*length,at,.16,color,false,0)
					else:segment(at-velocity.normalized()*length,at,0.10,color)
			elif weapon.fishing:
				# From the drawn hull, not the stepped one: the model is rendered
				# between ticks, and a line anchored a tick ahead of it judders.
				hook_line(hook_muzzle(region,weapon),at,weapon)
			elif weapon.model_id>=0:
				var key := str(weapon.get_instance_id())+":"+str(i)
				if not projectile_nodes.has(key):
					var visual=owner_view.model(weapon.model_id,32,self)
					if visual==null: continue
					projectile_nodes[key]=visual
				var visual=projectile_nodes[key]
				pose.origin=weapon.positions[i]; pose.face(Math.normalize_vector(weapon.velocities[i]))
				visual.transform=pose.godot_transform()
				visual.position=at
				if weapon.homing: visual.basis=visual.basis.scaled_local(Vector3.ONE*2)
				visual.show(); visual.advance(milliseconds); projectile_count+=1
				shade_projectile(visual,weapon.equipment_id in [6,7,8])
				if enhanced_weapons:
					var id: int=weapon.equipment_id
					if id<0:id=12 if weapon.homing else 42 if weapon.model_id in [6766,6767] else weapon.model_id-6754
					modern_form(key,id,projectile_color(visual),at,velocity,1000.0 if weapon.homing else trail_length(weapon,i,fraction,30.0))
					visual.hide()
				# The imported energy round is the whole shot. A separate bright
				# wake behind it looked like an extra projectile from the chase view.
				if weapon.homing:
					if enhanced_weapons:torpedo_tail(weapon,i,visual,at)
					else:
						var available := trail_length(weapon,i,fraction,velocity.length()*2.8)
						for j in 14:
							if velocity.length()*float(j)/5>available:break
							var side := Vector3(sin(j*2.4+region.elapsed_ms*.002),cos(j*1.7),0)*float(j)*.035
							bubble(at-velocity*float(j)/5+side,.12+float(j)*.014,.36-float(j)*.023)
	if enhanced_weapons:show_torpedo_wakes()

	for hook in region.fishing:
		if hook.target!=null:
			hook_line(hook_muzzle(region,hook.weapon),owner_view.world.render_pose(hook.target).origin,hook.weapon)
	for actor in region.enemies+region.friends:
		if actor.state in [3,4] and not (actor.capturable and actor.health.enabled): continue
		if owner_view.pack.enabled: continue
		for i in actor.trail.life.size():
			var fraction: float=owner_view.world.accumulator
			var remaining: float=maxf(0,float(actor.trail.life[i])-fraction)
			if remaining>0:
				var at: Vector3=Library.point(actor.trail.position[i])+Vector3.UP*float(actor.trail.rise[i])*.01*fraction*.001
				bubble(at,remaining/1800.0*1.4,remaining/1800.0)
	for event in region.visual_events:
		var age_ms: int = region.elapsed_ms-event.time
		if event.kind=="impact":
			var duration:=650.0 if enhanced_weapons and event.get("homing",false) else 400.0
			if age_ms>=0 and age_ms<duration:impact(event,float(age_ms)/duration)
		elif event.creature:
			# A kill leaves only the blood cloud: the original draws no flash.
			if age_ms>=0 and age_ms<BLOOD_LIFETIME_MS: blood(Library.point(event.position),age_ms)
		else:
			for i in event.delays.size():
				var duration := 550.0 if owner_view.modern_graphics and aftermath_enabled else (1000.0 if event.delays.size()>1 else 4000.0)
				var age: float = float(age_ms-int(event.delays[i]))/duration
				if age<0 or age>=1: continue
				var offset: Array = event.offsets[i] if i<event.offsets.size() else [0,0,0]
				burst(Library.point(Math.added(event.position,offset)),36 if event.delays.size()>1 else 24,age,Color("ffbe85"),not owner_view.modern_graphics)
	for i in range(blood_count,blood_clouds.size()): blood_clouds[i].hide()
	if puff_count>0 and not puffs.multimesh.mesh.material.has_meta("atlas_checked"):
		puffs.multimesh.mesh.material.set_meta("atlas_checked",true); blood_atlas()
	segments.multimesh.visible_instance_count=segment_count
	ribbons.multimesh.visible_instance_count=ribbon_count
	cables.multimesh.visible_instance_count=hook_count;hook_heads.multimesh.visible_instance_count=0
	bursts.multimesh.visible_instance_count=burst_count
	bubbles.multimesh.visible_instance_count=bubble_count
	puffs.multimesh.visible_instance_count=puff_count
	refresh_bounds()
func _exit_tree() -> void:
	for node in [segments,ribbons,cables,hook_heads,bursts,bubbles,puffs]: node.multimesh=null
