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
## Turned by dragging across the picture.
var turn := 0.0
var tilt := 0.0
var dragging := false
## A sea creature rather than a vessel (make_creature): drawn as the water
## draws it, from the creature's own life, and leaving no propeller wake.
var creature := false
## A standing character, framed from the front rather than like a swimming hull.
var upright := false
var display_basis := Basis.IDENTITY
## The simulated creature whose life poses the body, and its second part (a
## head or tail) where the species has one.
var actor
var part
var creature_ms := 0
const Creature = preload("res://native/simulation/creature.gd")
const ModelLibrary = preload("res://scripts/model_library.gd")

func configure(content, id: int, modern: bool, library=null) -> void:
 selected_id=id;name="ShipPreview";stretch=true
 custom_minimum_size=Vector2(280,280);size_flags_horizontal=Control.SIZE_EXPAND_FILL
 size_flags_vertical=Control.SIZE_EXPAND_FILL;mouse_filter=Control.MOUSE_FILTER_STOP
 mouse_default_cursor_shape=Control.CURSOR_DRAG
 viewport.own_world_3d=true;viewport.size=Vector2i(360,320)
 viewport.render_target_update_mode=SubViewport.UPDATE_WHEN_VISIBLE;add_child(viewport)
 var environment:=WorldEnvironment.new();var env:=Environment.new();environment.environment=env;viewport.add_child(environment)
 env.background_mode=Environment.BG_SKY
 var sky:=Sky.new();var water:=ShaderMaterial.new();water.shader=load("res://native/presentation/abyss_sky.gdshader");sky.sky_material=water;env.sky=sky
 preload("res://native/presentation/showroom_light.gd").apply(viewport,env)
 viewport.add_child(camera);camera.current=true;camera.fov=42
 for entry in content.registry:
  if int(entry.id)!=id:continue
  vessel=load("res://native/presentation/model.gd").new();vessel.modern_graphics=modern
  # The showroom is rebuilt on every selection. Sharing the dive's library
  # means the hull, its textures and its shaders are already decoded and
  # compiled, so a change of selection costs a frame rather than a stall.
  if library!=null:vessel.library=library
  viewport.add_child(vessel)
  vessel.configure(content.root,entry)
  if id<=11:vessel.apply_range(vessel.ship_animation_range(id,0))
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
 # The showroom's texture is shown the frame the container is drawn, before
 # the viewport behind it has rendered into it once; on Vulkan that first
 # frame is whatever the memory held. Keep the picture clear until the
 # viewport has drawn, then show it.
 self_modulate.a=0
 RenderingServer.frame_post_draw.connect(reveal,CONNECT_ONE_SHOT)

## Turns the showroom's model into the creature it is: its body breathing,
## swaying and turned over as the game draws creatures, with its second
## part joined where the two meet, all from Creature.animate as in the water.
func make_creature(content) -> void:
 creature=true
 # Hulls are shown from ahead; a creature is shown from its side, where its
 # shape reads, and can still be turned by hand.
 turn=.8
 if vessel==null:return
 var sine: Array=content.data.constants.dt["a:[S"]
 actor=Creature.new();actor.model_id=selected_id
 for pose in [actor.pose,actor.turn,actor.secondary_pose,actor.hinge_pose]:pose.math.sine_table=sine
 actor.pose.face([0,0,4096])
 if selected_id in [4424,4427,4430,4432,4434,4440,4436,4438]:actor.secondary_model=selected_id+1
 vessel.apply_actor_animation(actor)
 for entry in content.registry:
  if actor.secondary_model<0 or int(entry.id)!=actor.secondary_model:continue
  part=load("res://native/presentation/model.gd").new();part.modern_graphics=vessel.modern_graphics;part.library=vessel.library
  viewport.add_child(part);part.configure(content.root,entry)
  break
 # Frame the creature whole through one cycle of its life, as it breathes,
 # sways and bends: the body turned over as drawn, and the part. A swarm
 # of sprites has no solid shape and keeps the showroom's framing.
 var body: AABB=vessel.solid_bounds();var tail: AABB=part.solid_bounds() if part!=null else AABB()
 if body.size==Vector3.ZERO and tail.size==Vector3.ZERO:radius*=1.45;return
 var whole:=AABB()
 for step in 8:
  actor.phase=step*512;actor.animate()
  var drawn:=Transform3D(body_basis(),Vector3.ZERO)*body
  if part!=null:drawn=drawn.merge(Transform3D(part_basis(),Vector3.ZERO)*tail)
  whole=drawn if step==0 else whole.merge(drawn)
 bounds=whole;center=bounds.get_center();radius=maxf(2,bounds.size.length()*.45)

## The Aquarian is authored swimming along the hull axis. Stand it on its
## tail and face the reader, retaining the complete silhouette and trident.
func make_upright() -> void:
 upright=true;turn=0;tilt=0
 display_basis=Basis(Vector3.UP,PI)*Basis(Vector3.RIGHT,PI/2)
 if vessel!=null:
  bounds=Transform3D(display_basis,Vector3.ZERO)*vessel.solid_bounds()
  center=bounds.get_center()
 _process(0)

## The body relative to its heading, as world_view draws it: its swing and
## half turn in the game's frame, then the breathing scale.
func body_basis() -> Basis:
 var tilt: Array=actor.render_tilt
 var drawn: Basis=ModelLibrary.SIM_FLIP*Basis.from_euler(Vector3(tilt[0],tilt[1],tilt[2])*TAU/4096.0,EULER_ORDER_XYZ)*ModelLibrary.SIM_FLIP
 if not (vessel.replacement!=null and actor.model_id==4422):drawn=drawn.scaled_local(Vector3(actor.render_scale[0],actor.render_scale[1],actor.render_scale[2])/4096.0)
 return drawn

## The second part relative to the body's heading, bent at the join with
## enhanced graphics as in the water.
func part_basis() -> Basis:
 var bent: bool=vessel.modern_graphics and actor.hinge_axis!=""
 var body: Basis=actor.pose.godot_transform().basis.orthonormalized()
 var relative: Basis=body.inverse()*(actor.hinge_pose if bent else actor.secondary_pose).godot_transform().basis
 return relative.scaled_local(Vector3(actor.secondary_scale[0],actor.secondary_scale[1],actor.secondary_scale[2])/4096.0)

func _gui_input(event: InputEvent) -> void:
 # Touch arrives as emulated mouse events, so one path serves both.
 if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
  dragging=event.pressed;accept_event()
 elif event is InputEventMouseMotion and dragging:
  turn+=event.relative.x*.012;tilt=clampf(tilt+event.relative.y*.006,-.5,.5);accept_event()

func reveal() -> void:
 if is_inside_tree():self_modulate.a=1

func _process(delta: float) -> void:
 if selected_id<0 or not is_visible_in_tree():return
 preload("res://native/presentation/showroom_light.gd").apply_antialiasing(viewport)
 elapsed+=delta
 if vessel!=null:
  vessel.advance(roundi(delta*1000))
  var attitude:=Basis(Vector3.RIGHT,tilt)*Basis(Vector3.UP,turn)
  if not upright:attitude*=Basis.from_euler(Vector3(sin(elapsed*.7)*.025,0,sin(elapsed*.5)*.035))
  var origin:=-(attitude*center)
  if not upright:origin+=Vector3(0,sin(elapsed)*radius*.015,0)
  if actor!=null:
   creature_ms+=roundi(delta*1000);actor.phase=creature_ms&0xFFF;actor.animate()
   vessel.transform=Transform3D(attitude*body_basis(),origin)
   if part!=null:
    part.advance(roundi(delta*1000))
    part.transform=Transform3D(attitude*part_basis(),origin)
    var bent: bool=vessel.modern_graphics and actor.hinge_axis!=""
    if bent:part.set_hinge(1 if actor.hinge_axis=="yaw" else 0,(-1.0 if actor.hinge_axis=="yaw" else 1.0)*actor.hinge_angle*TAU/4096.0)
    else:part.set_hinge(1,0.0)
  else:vessel.transform=Transform3D(attitude*display_basis,origin)
 wake.visible_instance_count=0 if creature or upright else -1
 if vessel!=null and not creature and not upright:
  for i in wake.instance_count:
   var age:=fposmod(float(i/2)/16.0+elapsed*.55,1.0)
   var side: float=-1 if i%2==0 else 1
   var at:=bounds.get_center()+Vector3(side*bounds.size.x*(.25+age*.06),sin(i+elapsed)*.2,bounds.size.z*.52+age*radius*1.5)
   wake.set_instance_transform(i,Transform3D(Basis.IDENTITY,vessel.transform*at))
   wake.set_instance_custom_data(i,Color(radius*(.025+age*.045),age,0,0))
   wake.set_instance_color(i,Color(.7,.9,1,.55))
 if upright:
  var facing:=Basis(Vector3.RIGHT,tilt)*Basis(Vector3.UP,turn)
  var framed:=Transform3D(facing,-(facing*center))*bounds
  var aspect:=float(viewport.size.x)/maxi(1,viewport.size.y)
  var distance:=maxf(framed.size.y,framed.size.x/aspect)*.5/tan(deg_to_rad(camera.fov)*.5)*1.12+framed.size.z*.5
  camera.position=Vector3(0,0,-maxf(1,distance))
 else:camera.position=Vector3(1.25+sin(elapsed*.18)*.15,.65,-1.9)*radius
 camera.look_at(Vector3.ZERO)
 particles.set_shader_parameter("eye",camera.position)
 particles.set_shader_parameter("eye_phase",Vector3(0,0,-elapsed*6))
 particles.set_shader_parameter("drift_time",elapsed)
