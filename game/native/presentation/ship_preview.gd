extends SubViewportContainer
## Isolated showroom: imported vessel, real lights and flowing sea particles.
var selected_id := -1
var elapsed := 0.0
var viewport := SubViewport.new()
var camera := Camera3D.new()
var vessel
var center := Vector3.ZERO
var particles := ShaderMaterial.new()
var radius := 20.0
var bounds := AABB()
var wake := MultiMesh.new()

func configure(content, id: int, modern: bool) -> void:
 selected_id=id;name="ShipPreview";stretch=true
 custom_minimum_size=Vector2(280,280);size_flags_horizontal=Control.SIZE_EXPAND_FILL
 size_flags_vertical=Control.SIZE_EXPAND_FILL;mouse_filter=Control.MOUSE_FILTER_IGNORE
 viewport.own_world_3d=true;viewport.size=Vector2i(360,320)
 viewport.render_target_update_mode=SubViewport.UPDATE_WHEN_VISIBLE;add_child(viewport)
 var environment:=WorldEnvironment.new();var env:=Environment.new();environment.environment=env;viewport.add_child(environment)
 env.background_mode=Environment.BG_SKY
 var sky:=Sky.new();var water:=ShaderMaterial.new();water.shader=load("res://native/presentation/abyss_sky.gdshader");sky.sky_material=water;env.sky=sky
 env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color("c0d3d8");env.ambient_light_energy=.55
 var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-35,-40,0);light.light_color=Color("ffe6bf");light.light_energy=1.4;viewport.add_child(light)
 viewport.add_child(camera);camera.current=true;camera.fov=42
 for entry in content.registry:
  if int(entry.id)!=id:continue
  vessel=load("res://native/presentation/model.gd").new();vessel.modern_graphics=modern;viewport.add_child(vessel)
  vessel.configure(content.root,entry);vessel.apply_range(vessel.ship_animation_range(id,0))
  bounds=vessel.solid_bounds();center=bounds.get_center();radius=maxf(8,bounds.size.length()*.45)
  break
 var cloud:=MultiMeshInstance3D.new();var mesh:=QuadMesh.new();mesh.size=Vector2.ONE
 particles.shader=load("res://native/presentation/particulate.gdshader");particles.set_shader_parameter("lamps_on",0.0);mesh.material=particles
 var instances:=MultiMesh.new();instances.transform_format=MultiMesh.TRANSFORM_3D;instances.use_custom_data=true;instances.mesh=mesh;instances.instance_count=220
 var rng:=RandomNumberGenerator.new();rng.seed=67103
 for i in instances.instance_count:
  instances.set_instance_transform(i,Transform3D(Basis.IDENTITY,Vector3(rng.randf_range(-45,45),rng.randf_range(-45,45),rng.randf_range(-45,45))))
  instances.set_instance_custom_data(i,Color(rng.randf(),1 if i%3==0 else 0,.2 if i%3==0 else .04,1))
 cloud.multimesh=instances;cloud.custom_aabb=AABB(Vector3.ONE*-200,Vector3.ONE*400);cloud.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;viewport.add_child(cloud)
 var trail:=MultiMeshInstance3D.new();var bubble:=QuadMesh.new();bubble.size=Vector2.ONE
 var foam:=ShaderMaterial.new();foam.shader=load("res://native/presentation/bubble.gdshader");bubble.material=foam
 wake.transform_format=MultiMesh.TRANSFORM_3D;wake.use_custom_data=true;wake.use_colors=true;wake.mesh=bubble;wake.instance_count=32
 trail.multimesh=wake;trail.custom_aabb=AABB(Vector3.ONE*-200,Vector3.ONE*400);trail.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;viewport.add_child(trail)
 _process(0)

func _process(delta: float) -> void:
 if selected_id<0 or not is_visible_in_tree():return
 elapsed+=delta
 if vessel!=null:
  vessel.advance(roundi(delta*1000))
  var attitude:=Basis.from_euler(Vector3(sin(elapsed*.7)*.025,0,sin(elapsed*.5)*.035))
  vessel.transform=Transform3D(attitude,-(attitude*center)+Vector3(0,sin(elapsed)*radius*.015,0))
 if vessel!=null:
  for i in wake.instance_count:
   var age:=fposmod(float(i/2)/16.0+elapsed*.55,1.0)
   var side: float=-1 if i%2==0 else 1
   var at:=bounds.get_center()+Vector3(side*bounds.size.x*(.25+age*.06),sin(i+elapsed)*.2,bounds.size.z*.52+age*radius*1.5)
   wake.set_instance_transform(i,Transform3D(Basis.IDENTITY,vessel.transform*at))
   wake.set_instance_custom_data(i,Color(radius*(.025+age*.045),age,0,0))
   wake.set_instance_color(i,Color(.7,.9,1,.55))
 camera.position=Vector3(1.25+sin(elapsed*.18)*.15,.65,-1.9)*radius;camera.look_at(Vector3.ZERO)
 particles.set_shader_parameter("eye",camera.position)
 particles.set_shader_parameter("eye_phase",Vector3(0,0,-elapsed*6))
 particles.set_shader_parameter("drift_time",elapsed)
