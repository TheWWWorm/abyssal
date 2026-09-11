extends SceneTree
var failures := 0
func expect(ok: bool, why: String) -> void:
 if not ok:failures+=1;push_error(why)
func _initialize():call_deferred("run")
func check_imported_material_hints() -> void:
 var original:=Image.create(32,32,false,Image.FORMAT_RGBA8);original.fill(Color(.08,.1,.12))
 original.fill_rect(Rect2i(2,2,3,2),Color(1,.85,.4))
 original.fill_rect(Rect2i(12,2,14,12),Color(1,.85,.4))
 original.fill_rect(Rect2i(2,20,5,5),Color(.85,.85,.85))
 var bytes:=original.get_data()
 var map: Image=load("res://native/presentation/imported_surface.gd").derive(original)
 expect(original.get_data()==bytes,"Material analysis does not modify imported albedo")
 expect(map.get_size()==original.get_size() and map.has_mipmaps(),"Derived channels match the atlas and filter at distance")
 expect(map.get_pixel(3,2).b>.5,"Compact warm window marks receive emission")
 expect(map.get_pixel(18,6).b==0 and map.get_pixel(3,22).b==0,"Broad warm paint and white bulkheads do not become lamps")
 for y in 32:
  for x in 32:
   var c:=map.get_pixel(x,y)
   expect(c.g>=.47 and c.g<=.83,"Derived hull roughness stays in the restrained paint/metal range")
func light_frame(viewport: SubViewport) -> Image:
 for i in 3:await process_frame
 await RenderingServer.frame_post_draw
 return viewport.get_texture().get_image()
func check_station_filtering() -> void:
 if DisplayServer.get_name()=="headless":return
 var viewport:=SubViewport.new();viewport.size=Vector2i(128,128);viewport.own_world_3d=true
 viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
 var camera:=Camera3D.new();camera.position.z=3;camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=2;viewport.add_child(camera)
 var wall:=MeshInstance3D.new();var quad:=QuadMesh.new();quad.size=Vector2(2,2);wall.mesh=quad;viewport.add_child(wall)
 var library=load("res://scripts/model_library.gd").new()
 var pixels:=Image.create(2,2,false,Image.FORMAT_RGBA8);pixels.fill(Color.BLACK)
 pixels.set_pixel(1,0,Color.WHITE);pixels.set_pixel(1,1,Color.WHITE);pixels.generate_mipmaps()
 library.textures["filter-probe.png"]=ImageTexture.create_from_image(pixels)
 var bones: Array[Transform3D]=[]
 for i in 64:bones.append(Transform3D.IDENTITY)
 for modern in [false,true]:
  library.enhanced=modern
  for smoothing in [false,true,false]:
   var mat: ShaderMaterial=library.affine_material("filter-probe.png",0,true,false,false,0,not smoothing,smoothing)
   mat.set_shader_parameter("source_bones",bones);wall.material_override=mat
   var rendered:=await light_frame(viewport)
   var shades: Dictionary={}
   for x in range(8,120):shades[rendered.get_pixel(x,64).to_rgba32()]=true
   expect(shades.size()>16 if smoothing else shades.size()<=2,"Rendered station texels blend only with smoothing enabled, lighting mode %s"%modern)
 viewport.queue_free();await process_frame

func check_headlight_surfaces() -> void:
 expect(not ProjectSettings.get_setting("rendering/lights_and_shadows/positional_shadow/atlas_16_bits",true),"Long-range spot shadows retain depth precision in exported configuration")
 if DisplayServer.get_name()=="headless":return
 var viewport:=SubViewport.new();viewport.size=Vector2i(256,256);viewport.own_world_3d=true
 # Use the browser's atlas resolution. The former 16-bit depth buffer turns
 # this unobstructed flat wall into a false shadow at only 80 metres.
 viewport.positional_shadow_atlas_size=2048
 viewport.positional_shadow_atlas_16_bits=ProjectSettings.get_setting("rendering/lights_and_shadows/positional_shadow/atlas_16_bits")
 viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
 var camera:=Camera3D.new();camera.position=Vector3(0,0,50);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=80;viewport.add_child(camera)
 var environment:=WorldEnvironment.new();var env:=Environment.new();environment.environment=env
 env.background_mode=Environment.BG_COLOR;env.background_color=Color.BLACK
 env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color.WHITE;env.ambient_light_energy=.05;viewport.add_child(environment)
 var Lighting=load("res://native/presentation/abyss.gd")
 var lamps: Array=[]
 for x in [-1.8,1.8]:
  var lamp: SpotLight3D=Lighting.create_headlight(x);viewport.add_child(lamp);lamp.position.y=0;lamps.append(lamp)
 var wall:=MeshInstance3D.new();var quad:=QuadMesh.new();quad.size=Vector2(80,80);wall.mesh=quad;viewport.add_child(wall)
 var library=load("res://scripts/model_library.gd").new();library.enhanced=true
 var material: ShaderMaterial=library.affine_material("",0,true,true,false)
 var bones: Array[Transform3D]=[]
 for i in 64:bones.append(Transform3D.IDENTITY)
 material.set_shader_parameter("source_bones",bones);material.set_shader_parameter("distance_haze",0.0);wall.material_override=material
 for distance in [40,80,160]:
  wall.position=Vector3(0,0,-distance)
  for angle in [-6,0,6]:
   for lamp in lamps:lamp.rotation_degrees.y=angle
   var rendered:=await light_frame(viewport)
   var low:=1.0;var high:=0.0
   for x in range(116,141):
    var pixel:=rendered.get_pixel(x,128);low=minf(low,pixel.r);high=maxf(high,pixel.r)
    if x>116:expect(absf(pixel.r-rendered.get_pixel(x-1,128).r)<.05,"Headlight has no pixel-width shadow stripes")
   expect(low>.27,"Headlight reaches an unobstructed wall at %d m / %d degrees without false shadow bands"%[distance,angle])
   expect(high<.94 and high-low<.24,"Headlight preserves a smooth, unsaturated surface at %d m / %d degrees"%[distance,angle])
 wall.position.z=-80
 for lamp in lamps:lamp.rotation=Vector3.ZERO
 var lit:=await light_frame(viewport)
 expect(lit.get_pixel(128,128).r>lit.get_pixel(190,128).r+.04,"Headlight cone feathers toward its rim")
 var blocker:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=Vector3(10,10,1);blocker.mesh=box
 blocker.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY;blocker.position=Vector3(0,0,-40);viewport.add_child(blocker)
 var blocked:=await light_frame(viewport)
 expect(blocked.get_pixel(128,128).r<.26 and lit.get_pixel(128,128).r>blocked.get_pixel(128,128).r+.08,"Opaque geometry still blocks the headlights")
 viewport.queue_free();await process_frame
func particle_energy(viewport: SubViewport) -> float:
 await process_frame;await RenderingServer.frame_post_draw
 var rendered:=viewport.get_texture().get_image()
 var energy:=0.0
 for y in rendered.get_height():
  for x in rendered.get_width():
   var pixel:=rendered.get_pixel(x,y);energy+=pixel.r+pixel.g+pixel.b
 return energy
func check_particle_motion() -> void:
 if DisplayServer.get_name()=="headless":return
 var viewport:=SubViewport.new();viewport.size=Vector2i(128,128);viewport.own_world_3d=true
 viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
 var environment:=WorldEnvironment.new();environment.environment=Environment.new()
 environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color.BLACK;viewport.add_child(environment)
 var camera:=Camera3D.new();camera.near=.1;viewport.add_child(camera)
 var quad:=QuadMesh.new();quad.size=Vector2.ONE
 var material:=ShaderMaterial.new();quad.material=material
 var cloud:=MultiMesh.new();cloud.transform_format=MultiMesh.TRANSFORM_3D
 cloud.use_custom_data=true;cloud.use_colors=true;cloud.mesh=quad;cloud.instance_count=1
 cloud.set_instance_transform(0,Transform3D.IDENTITY);cloud.set_instance_color(0,Color.WHITE)
 var mesh:=MultiMeshInstance3D.new();mesh.multimesh=cloud
 mesh.custom_aabb=AABB(Vector3.ONE*-100000,Vector3.ONE*200000);viewport.add_child(mesh)
 for kind in 4:
  material.shader=load("res://native/presentation/projectile.gdshader" if kind==3 else ("res://native/presentation/bubble.gdshader" if kind==2 else "res://native/presentation/particulate.gdshader"))
  material.set_shader_parameter("lamps_on",0.0)
  cloud.set_instance_custom_data(0,Color(.15,.15,0,0) if kind==3 else (Color(.15,.3,2,0) if kind==2 else Color(.5,kind,.15,1)))
  var smallest:=INF;var largest:=0.0
  for frame in 48:
   var angle:=frame*TAU/24
   camera.position=Vector3(sin(angle)*20,0,cos(angle)*20) if frame<24 else Vector3(0,sin(angle)*19,cos(angle)*19)
   camera.look_at(Vector3.ZERO,Vector3.FORWARD if absf(camera.position.normalized().y)>.99 else Vector3.UP)
   material.set_shader_parameter("eye",camera.position);material.set_shader_parameter("eye_phase",camera.position)
   var energy:=await particle_energy(viewport)
   smallest=minf(smallest,energy);largest=maxf(largest,energy)
  expect(smallest>.01,"Particle type %d never disappears between camera-angle samples"%kind)
  expect(largest<smallest*2.5,"Particle type %d avoids large subpixel brightness flashes"%kind)
  camera.position=Vector3(0,0,20);camera.look_at(Vector3.ZERO);material.set_shader_parameter("eye",camera.position);material.set_shader_parameter("eye_phase",camera.position)
  # An opaque object still hides the particles behind it: stability must not
  # come from disabling depth testing and drawing bubbles through the hull.
  var blocker:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=Vector3(10,10,1);blocker.mesh=box
  var black:=StandardMaterial3D.new();black.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;black.albedo_color=Color.BLACK;blocker.material_override=black
  viewport.add_child(blocker);blocker.position=Vector3(0,0,10)
  expect(await particle_energy(viewport)<.001,"Particle type %d remains occluded by solid geometry"%kind)
  blocker.queue_free();await process_frame
  if kind<2:
   for distance in [44.0,46.0]:
    camera.position=Vector3(0,0,distance);camera.look_at(Vector3.ZERO);material.set_shader_parameter("eye",camera.position);material.set_shader_parameter("eye_phase",camera.position)
    expect(await particle_energy(viewport)<.001,"Ambient particle is invisible on both sides of its wrap boundary")
 viewport.queue_free();await process_frame
func check_ambient_cloud_angles() -> void:
 if DisplayServer.get_name()=="headless":return
 var viewport:=SubViewport.new();viewport.size=Vector2i(160,100);viewport.own_world_3d=true
 viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
 var camera:=Camera3D.new();camera.fov=65;camera.near=.5;camera.far=10000;viewport.add_child(camera)
 var abyss=load("res://native/presentation/abyss.gd").new();abyss.camera=camera;viewport.add_child(abyss);abyss.set_process(false)
 abyss.environment.environment.background_mode=Environment.BG_COLOR
 abyss.environment.environment.background_color=Color.BLACK
 abyss.environment.environment.glow_enabled=false;abyss.environment.environment.volumetric_fog_enabled=false
 # Exercise the complete moving cloud, not just a billboard fixed at zero.
 # Include world travel beyond the former fixed bounds and wrap-cell edges.
 for location in [Vector3(0,0,-300),Vector3(44.9,45.1,-90.1),Vector3(100100,800,-2000)]:
  camera.position=location;abyss._process(0)
  var smallest:=INF
  for pitch in range(-90,91,30):
   for yaw in range(0,360,30):
    camera.basis=Basis.from_euler(Vector3(deg_to_rad(pitch),deg_to_rad(yaw),.15))
    smallest=minf(smallest,await particle_energy(viewport))
  expect(smallest>5,"Full ambient cloud remains visible through pitch/yaw/roll at "+str(location)+" (minimum energy "+str(smallest)+")")
  var bounds: AABB=abyss.particles.global_transform*abyss.particles.custom_aabb
  expect(bounds.has_point(camera.global_position) and bounds.size.length()<250,"Ambient culling bounds follow the camera without spanning the whole world")
 abyss.particles.hide()
 var effects=load("res://native/presentation/combat_effects.gd").new();viewport.add_child(effects)
 var center:=Vector3(100100,800,-2000)
 effects.sprite(effects.bubbles,0,center,.5,.2,2,Color.WHITE)
 effects.bubbles.multimesh.visible_instance_count=1;effects.refresh_bounds()
 var wake_minimum:=INF
 for angle in range(0,360,15):
  camera.position=center+Vector3(sin(deg_to_rad(angle))*20,0,cos(deg_to_rad(angle))*20)
  camera.look_at(center)
  wake_minimum=minf(wake_minimum,await particle_energy(viewport))
 expect(wake_minimum>.1,"Real wake pool remains visible from every heading beyond the old fixed bounds")
 expect(effects.bubbles.custom_aabb.has_point(center) and effects.bubbles.custom_aabb.size.length()<10,"Wake culling bounds cover the expanded live sprite")
 viewport.queue_free();await process_frame

func check_station_reflections() -> void:
 if DisplayServer.get_name()=="headless":return
 var viewport:=SubViewport.new();viewport.size=Vector2i(160,160);viewport.own_world_3d=true
 viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
 var environment:=WorldEnvironment.new();var env:=Environment.new();environment.environment=env;viewport.add_child(environment)
 var sky:=Sky.new();var sky_material:=ProceduralSkyMaterial.new()
 sky_material.sky_top_color=Color(0,0,.3);sky_material.sky_horizon_color=Color(0,0,.3)
 sky_material.ground_bottom_color=Color(0,0,.3);sky_material.ground_horizon_color=Color(0,0,.3)
 sky.sky_material=sky_material;env.sky=sky;env.background_mode=Environment.BG_SKY
 env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color.WHITE;env.ambient_light_energy=.12
 env.reflected_light_source=Environment.REFLECTION_SOURCE_SKY
 var camera:=Camera3D.new();viewport.add_child(camera)
 var wall:=MeshInstance3D.new();var quad:=QuadMesh.new();quad.size=Vector2(200,200);var arrays:=quad.get_mesh_arrays()
 var paint:=PackedColorArray();paint.resize(arrays[Mesh.ARRAY_VERTEX].size());paint.fill(Color(.002,.002,.002))
 arrays[Mesh.ARRAY_COLOR]=paint
 var painted:=ArrayMesh.new();painted.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);wall.mesh=painted;viewport.add_child(wall)
 var library=load("res://scripts/model_library.gd").new()
 var mat: ShaderMaterial=library.affine_material("",0,true,true,false)
 var bones: Array[Transform3D]=[]
 for i in 64:bones.append(Transform3D.IDENTITY)
 mat.set_shader_parameter("source_bones",bones);mat.set_shader_parameter("station_coating",true)
 var hints:=Image.create(2,2,false,Image.FORMAT_RGB8);hints.fill(Color(.5,.65,0))
 mat.set_shader_parameter("surface_map",ImageTexture.create_from_image(hints));wall.material_override=mat
 for angle in [-75,-35,0,35,75,0]:
  camera.position=Vector3(sin(deg_to_rad(angle))*100,0,cos(deg_to_rad(angle))*100);camera.look_at(Vector3.ZERO)
  var frame:=await light_frame(viewport);var pixel:=frame.get_pixel(80,80)
  expect(pixel.b-maxf(pixel.r,pixel.g)<.025,"Station paint stays neutral under a blue sky reflection after turning: %d"%angle)
 viewport.queue_free();await process_frame

func check_ocean_visibility() -> void:
 # Render actual imported-model shader code on synthetic surfaces. A numeric
 # falloff-only test misses a fog/sky color-space mismatch on the browser GPU.
 if DisplayServer.get_name()=="headless":return
 var viewport:=SubViewport.new();viewport.size=Vector2i(1000,300);viewport.own_world_3d=true
 viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
 var environment:=WorldEnvironment.new();viewport.add_child(environment)
 var env:=Environment.new();environment.environment=env
 var sky:=Sky.new();var sky_material:=ShaderMaterial.new()
 sky_material.shader=load("res://native/presentation/abyss_sky.gdshader");sky.sky_material=sky_material
 env.sky=sky;env.background_mode=Environment.BG_SKY
 var camera:=Camera3D.new();viewport.add_child(camera)
 camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=60;camera.far=10000
 var library=load("res://scripts/model_library.gd").new();library.enhanced=true
 var bones: Array[Transform3D]=[]
 for index in 64:bones.append(Transform3D.IDENTITY)
 var distances: Array=[200,800,1600,3000,6500]
 for index in distances.size():
  var mesh:=MeshInstance3D.new();var quad:=QuadMesh.new();quad.size=Vector2(26,26);mesh.mesh=quad
  viewport.add_child(mesh);mesh.position=Vector3(-80+index*40,0,-distances[index])
  var mat: ShaderMaterial=library.affine_material("",0,false,false,false)
  mat.set_shader_parameter("source_bones",bones)
  mat.set_shader_parameter("distance_haze",.02 if index==4 else .0015);mat.set_shader_parameter("station_coating",true);mesh.material_override=mat
 await process_frame;await process_frame;await RenderingServer.frame_post_draw
 var rendered:=viewport.get_texture().get_image()
 var previous:=1.0
 for index in distances.size():
  var pixel:=rendered.get_pixel(100+index*200,150)
  var luminance:=Vector3(pixel.r,pixel.g,pixel.b).dot(Vector3(.2126,.7152,.0722))
  expect(luminance<previous-.025,"Rendered station brightness falls with distance: sample %d"%index)
  previous=luminance
 var fogged:=rendered.get_pixel(900,150);var water:=rendered.get_pixel(995,150)
 expect(Vector3(fogged.r-water.r,fogged.g-water.g,fogged.b-water.b).length()<.01,"Fully absorbed geometry matches dark water, without a bright fog silhouette")
 # A shadowed near bulkhead must stay dark rather than acquire blue fill
 # from distance haze. Test the actual generated material on a black surface.
 var dark:=MeshInstance3D.new();var dark_quad:=QuadMesh.new();dark_quad.size=Vector2(26,26)
 var arrays:=dark_quad.get_mesh_arrays();var colors:=PackedColorArray()
 for vertex in 4:colors.append(Color.BLACK)
 arrays[Mesh.ARRAY_COLOR]=colors
 var dark_mesh:=ArrayMesh.new();dark_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);dark.mesh=dark_mesh
 viewport.add_child(dark);dark.position=Vector3(-80,0,-350)
 # Move the first white panel out of the test ray.
 for child in viewport.get_children():
  if child is MeshInstance3D and child!=dark and child.position.x==-80:child.position.x=-1000
 var dark_mat: ShaderMaterial=library.affine_material("",0,false,false,false)
 dark_mat.set_shader_parameter("source_bones",bones);dark_mat.set_shader_parameter("distance_haze",.0015);dark_mat.set_shader_parameter("station_coating",true);dark.material_override=dark_mat
 for frame in 3:await process_frame
 await RenderingServer.frame_post_draw
 var shadow:=viewport.get_texture().get_image().get_pixel(100,150)
 expect(shadow.b<.035 and shadow.g<.035,"Nearby station shadows do not turn into a blue fog wash")
 var args:=OS.get_cmdline_user_args()
 if args.size()>1 and args[1].ends_with(".png"):rendered.save_png(args[1])
 camera.projection=Camera3D.PROJECTION_PERSPECTIVE;camera.fov=65
 camera.look_at(Vector3(-.25,.95,-.15).normalized(),Vector3.UP)
 for i in 3:await process_frame
 await RenderingServer.frame_post_draw
 var sun_image:=viewport.get_texture().get_image()
 var core:=sun_image.get_pixel(500,150);var edge:=sun_image.get_pixel(800,150)
 expect(core.r>edge.r+.2 and core.g>edge.g+.15,"Overhead sun has a visible soft core above the surrounding water")
 if args.size()>1 and args[1].ends_with(".png"):sun_image.save_png(args[1].get_basename()+"-sun.png")
 camera.look_at(Vector3(0,-.7,-1),Vector3.UP)
 for i in 3:await process_frame
 await RenderingServer.frame_post_draw
 var below:=viewport.get_texture().get_image().get_pixel(500,150)
 expect(core.r>below.r+.2,"Sun glow remains overhead rather than following the camera")
 viewport.queue_free();await process_frame
func check_blend_distance() -> void:
 if DisplayServer.get_name()=="headless":return
 var viewport:=SubViewport.new();viewport.size=Vector2i(600,200);viewport.own_world_3d=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
 var environment:=WorldEnvironment.new();environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color(.4,.4,.4);viewport.add_child(environment)
 var camera:=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=20;camera.far=10000;viewport.add_child(camera)
 var library=load("res://scripts/model_library.gd").new();library.enhanced=true
 var bones: Array[Transform3D]=[]
 for index in 64:bones.append(Transform3D.IDENTITY)
 for blend in [4,6]:
  var nodes: Array=[]
  for index in 3:
   var quad:=QuadMesh.new();quad.size=Vector2(15,15)
   var arrays:=quad.get_mesh_arrays();var colors:=PackedColorArray()
   for vertex in 4:colors.append(Color(.2,.2,.2) if index<2 else Color.BLACK)
   arrays[Mesh.ARRAY_COLOR]=colors
   var shape:=ArrayMesh.new();shape.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
   var node:=MeshInstance3D.new();node.mesh=shape;node.position=Vector3(-20+index*20,0,-(200 if index==0 else 4500));viewport.add_child(node);nodes.append(node)
   var material: ShaderMaterial=library.affine_material("",blend,false,false,false)
   material.set_shader_parameter("source_bones",bones);material.set_shader_parameter("distance_haze",.00055);node.material_override=material
  await process_frame;await process_frame;await RenderingServer.frame_post_draw
  var rendered:=viewport.get_texture().get_image();var water:=rendered.get_pixel(598,100)
  var background:=Vector3(water.r,water.g,water.b)
  var near_color:=rendered.get_pixel(100,100);var far_color:=rendered.get_pixel(300,100);var black_color:=rendered.get_pixel(500,100)
  var near_contrast:=Vector3(near_color.r,near_color.g,near_color.b).distance_to(background)
  var far_contrast:=Vector3(far_color.r,far_color.g,far_color.b).distance_to(background)
  expect(near_contrast>far_contrast*3 and near_contrast>.03,"Blend %d attenuates with underwater distance"%blend)
  expect(Vector3(black_color.r,black_color.g,black_color.b).distance_to(background)<.005,"Black additive/subtractive texels do not create fog rectangles")
  nodes[0].material_override.set_shader_parameter("source_glow_visible",false)
  await process_frame;await RenderingServer.frame_post_draw
  var hidden:=viewport.get_texture().get_image().get_pixel(100,100)
  expect(Vector3(hidden.r,hidden.g,hidden.b).distance_to(background)<.005,"Modern glow suppression removes the legacy effect surface")
  for node in nodes:node.queue_free()
  await process_frame
 viewport.queue_free();await process_frame
func check_scene_particle_pitch(app) -> void:
 if DisplayServer.get_name()=="headless":return
 # Exercise the real headlight rig and both MultiMesh pools together. An
 # isolated particle without scene lights does not expose the additive-pass
 # fault: looking up/down previously replaced its alpha mask with a square.
 app.set_process(false);app.abyss.set_process(false)
 app.session.docked=false;app.view.modern_graphics=true;app.view.rebuild()
 app.ui.hide();app.touch.hide()
 app.abyss.environment.environment.volumetric_fog_enabled=false
 var player=app.world.region.player;player.throttle=100;player.set_throttle(100)
 for pitch in [-850,0,850]:
  player.pose.origin=[0,0,-100000];player.pose.set_euler(pitch,0,0)
  app.view.combat.reset()
  for i in 40:
   player.advance(40);app.world.region.elapsed_ms+=40;app.world.previous_render_poses.clear()
   app.view._process(.04);app.abyss._process(.04)
  for node in app.view.get_children():
   if node is Node3D and node!=app.view.combat:node.hide()
  app.abyss.particle_material.set_shader_parameter("lamps_on",0.0)
  # Freeze simulation and the ambient drift uniform between both exposures.
  for i in 3:await process_frame
  await RenderingServer.frame_post_draw
  var lit:=root.get_texture().get_image()
  for lamp in app.abyss.lamps:lamp.hide()
  for i in 3:await process_frame
  await RenderingServer.frame_post_draw
  var unlit:=root.get_texture().get_image()
  var changed:=0
  for y in range(0,lit.get_height(),2):
   for x in range(0,lit.get_width(),2):
    var a:=lit.get_pixel(x,y);var b:=unlit.get_pixel(x,y)
    if Vector3(a.r-b.r,a.g-b.g,a.b-b.b).length()>.025:changed+=1
  expect(changed<8,"Headlights do not relight transparent particle cards at pitch %d (%d changed samples)"%[pitch,changed])
  app.abyss.particles.hide()
  for i in 3:await process_frame
  await RenderingServer.frame_post_draw
  var empty:=root.get_texture().get_image();var visible_samples:=0
  for y in range(0,unlit.get_height(),2):
   for x in range(0,unlit.get_width(),2):
    var a:=unlit.get_pixel(x,y);var b:=empty.get_pixel(x,y)
    if Vector3(a.r-b.r,a.g-b.g,a.b-b.b).length()>.015:visible_samples+=1
  expect(visible_samples>12,"Ambient water particles actually render at pitch %d (%d samples)"%[pitch,visible_samples])
  app.abyss.particles.show()
func check_depth_lighting() -> void:
 var palette=load("res://native/presentation/abyss.gd")
 expect(palette.sky_profile(11000).x>palette.sky_profile(22500).x,"Shallow water retains the warm sky band")
 expect(palette.sky_profile(22500).z>palette.sky_profile(22500).x*2,"The middle-depth sky remains blue")
 var last: Vector3=palette.sky_profile(0)
 for depth in range(100,45000,100):
  var next: Vector3=palette.sky_profile(depth);expect(next.distance_to(last)<.02,"Sky hue changes continuously with depth");last=next
 var Abyss=load("res://native/presentation/abyss.gd")
 var previous: Vector3=Abyss.light_profile(500)
 for depth in range(1000,60001,500):
  var profile: Vector3=Abyss.light_profile(depth)
  expect(profile.x<=previous.x and profile.y<=previous.y and profile.z<=previous.z,"Water and daylight darken together at depth %d"%depth)
  expect(profile.distance_to(previous)<.06,"Depth lighting remains continuous at %d"%depth)
  expect(profile.x>0 and profile.z>0,"Deep water retains readable ambient light")
  previous=profile

func run():
 check_imported_material_hints()
 check_depth_lighting()
 await check_station_filtering()
 await check_headlight_surfaces()
 await check_blend_distance()
 await check_particle_motion()
 await check_ambient_cloud_angles()
 await check_ocean_visibility()
 await check_station_reflections()
 var args := OS.get_cmdline_user_args()
 var content=load("res://native/content.gd").new()
 if not content.load_cache(args[0]):quit(1);return
 var config:=ConfigFile.new();config.set_value("input","touch",1);config.save("user://stream-check.cfg")
 var app=load("res://native/gameplay.gd").new();app.content=content;app.settings_path="user://stream-check.cfg";app.save_path="user://stream-check.json";root.add_child(app)
 await process_frame
 app.set_process(false);app.view.set_process(false);app.close_page();app.view._process(0)
 var view=app.view
 var mine=load("res://native/simulation/special_actor.gd").new()
 mine.configure_special("mine",13,true,app.world.region.player.pose.origin.duplicate(),content.data,app.session.rng)
 app.world.region.enemies.append(mine);view._process(0)
 expect(view.objects[mine.get_instance_id()].visual.visible,"Armed bomb has a visible body")
 mine.detonate();view._process(0)
 expect(not view.objects[mine.get_instance_id()].visual.visible,"Bomb body disappears on the detonation frame")
 expect(mine.state==3 and mine.events.has("killed"),"Hiding a bomb preserves its explosion event and lifecycle")
 app.world.region.enemies.erase(mine);view._process(0)
 var salvage=load("res://native/simulation/npc.gd").new()
 salvage.configure(0,2,true,app.world.region.player.pose.origin.duplicate(),content.data,app.session.campaign.chapter,app.session.rng)
 salvage.model_id=17;salvage.state=3;salvage.health.hull=0;salvage.capturable=true
 app.world.region.enemies.append(salvage);view._process(0)
 expect(view.objects[salvage.get_instance_id()].visual.visible,"Salvage remains visible before collection during the explosion lifetime")
 expect(salvage.capture(app.session),"Salvage transaction succeeds")
 view._process(0)
 expect(not view.objects[salvage.get_instance_id()].visual.visible,"Collected salvage disappears on the collection frame without waiting for the explosion timer")
 app.world.region.enemies.erase(salvage);view._process(0)
 app.abyss._process(0)
 expect(app.abyss.beam_lamps.all(func(lamp):return lamp.light_cull_mask==0),"Scattering lights never add duplicate surface lighting")
 if RenderingServer.get_current_rendering_method()!="forward_plus":
  expect(app.abyss.beam_lamps.all(func(lamp):return not lamp.visible),"Non-volumetric renderers disable scattering lights")
 var player_mesh: MeshInstance3D=view.player_model.figure.get_node("Mesh")
 expect(player_mesh.get_surface_override_material(0).get_shader_parameter("source_glow_visible")==false,"Modern ships suppress legacy glow geometry")
 # Imported ships must clip too; clipping previously only supported replacement meshes.
 var clip_frame:=Transform3D(Basis.IDENTITY,Vector3.ZERO)
 view.clip_player_at_gate(clip_frame,1)
 expect(view.player_model.portal_enabled and player_mesh.get_surface_override_material(0).get_shader_parameter("portal_clip_enabled"),"Original imported ship receives portal clipping")
 view.player_model.sampled_frame=-1;view.player_model.refresh()
 expect(player_mesh.get_surface_override_material(0).get_shader_parameter("portal_clip_enabled"),"Portal clipping survives animation material refresh")
 view.clear_player_clip()
 expect(not player_mesh.get_surface_override_material(0).get_shader_parameter("portal_clip_enabled"),"Portal exit restores the imported ship material")
 await check_station_machinery(view)
 var station_triangles:=station_surface_triangles(view)
 for id in [3302,3304]:
  var record=content.registry.filter(func(r):return int(r.id)==id)[0]
  var source:Dictionary=view.library.data(record.model)
  expect(int(source.get("socket_caps",0))>0,"Imported open connector ends are closed")
  var hit:=false
  for triangle in station_triangles[id]:
   if Geometry3D.segment_intersects_triangle(Vector3(0,-272,4200),Vector3(0,-272,3800),triangle[0],triangle[1],triangle[2])!=null:hit=true
  if id==3304:expect(hit,"Fan mounting end blocks a ray through its previously open socket")
 var large_layout=load("res://native/simulation/station_layout.gd").new()
 var large_parts:Array=large_layout.generate(5,22500,10,[],content.data.station_geometry)
 var large_bounds:AABB=large_layout.measured(large_parts[0])
 for part in large_parts:large_bounds=large_bounds.merge(large_layout.measured(part))
 expect(large_parts.size()>25 and large_bounds.size.y>25000,"Large high-tech stations include many vertically stacked modules")
 # Every imported station is a connected assembly, with an unobstructed berth.
 var Layout=load("res://native/simulation/station_layout.gd")
 var vertical_count:=0
 for station in app.session.stations:
  var layout=Layout.new();var parts=layout.generate(station.id,station.depth,station.tech,app.world.region.sine,content.data.station_geometry)
  if parts.any(func(part):return absf(part.origin[1])>3000):vertical_count+=1
  for part in parts:
   if int(part.model_id) not in [3304,3309]:continue
   var rotation:=Basis(Vector3.UP,part.yaw*TAU/4096.0)
   # Sample the imported open mounting end, not only overlapping AABBs.
   var socket:=Vector3(part.origin[0],part.origin[1],part.origin[2])+rotation*Vector3(0,-272,3980)
   var seated:=false
   for parent in parts:
    if parent==part or int(parent.model_id) not in [3305,3306] or not layout.measured(parent).has_point(socket):continue
    var parent_rotation:=Basis(Vector3.UP,parent.yaw*TAU/4096.0)
    var parent_origin:=Vector3(parent.origin[0],parent.origin[1],parent.origin[2])
    var local_socket:=parent_rotation.inverse()*(socket-parent_origin)
    var ray_from:=parent_rotation.inverse()*(Vector3(part.origin[0],part.origin[1],part.origin[2])-parent_origin)
    var ray_to:=Vector3(0,-272,1154)
    var entry_distance:=INF
    for triangle in station_triangles[int(parent.model_id)]:
     var hit=Geometry3D.segment_intersects_triangle(ray_from,ray_to,triangle[0],triangle[1],triangle[2])
     if hit!=null:entry_distance=minf(entry_distance,ray_from.distance_to(hit))
    if entry_distance<ray_from.distance_to(local_socket):seated=true
   expect(seated,"Station %d mounting socket penetrates the actual habitat surface"%station.id)
  var reached: Array=[0]
  for pass_index in parts.size():
   for index in parts.size():
    if index in reached:continue
    for parent in reached.duplicate():
     if layout.measured(parts[index]).grow(1).intersects(layout.measured(parts[parent])):reached.append(index);break
  expect(parts.all(func(part):return not layout.measured(part).has_point(Vector3(0,0,-16000))),"Departure berth stays clear")
  expect(reached.size()==parts.size(),"Station %d has no disconnected modules"%station.id)
  expect(parts.all(func(part):return part.model_id not in [3300,3311]),"Self-roofed habitats have no detached caps")
 expect(vertical_count>=100,"The world includes substantial stacked-station variety")
 for visual in view.station_nodes:
  var frame: int=visual.sampled_frame;var pattern: int=visual.last_pattern
  visual.advance(12000)
  expect(visual.sampled_frame==frame and visual.last_pattern==pattern,"Station emblem/configuration does not cycle")
 var prior_mission=app.session.campaign.secondary
 var quest=load("res://native/simulation/mission.gd").new();quest.kind=8;quest.destination=1;quest.destination_name=app.session.stations[1].name
 app.session.campaign.secondary=quest
 var saved_camera: Transform3D=app.camera.global_transform
 for heading in [0.0,PI]:
  app.camera.rotation.y=heading
  app.update_markers()
  expect(app.marker_by_contact.has("station") and app.markers[app.marker_by_contact.get("station",0)].visible,"Current station label survives projection and label overlap")
  expect(app.marker_by_contact.has("station:1") and app.markers[app.marker_by_contact.get("station:1",0)].visible,"Quest station is identified even outside the view")
  expect(app.markers.any(func(marker):return marker.visible and marker.text.contains("Quest destination")),"Quest destination has an explicit label")
 app.camera.global_transform=saved_camera;app.session.campaign.secondary=prior_mission
 app.update_markers()
 expect(app.markers.filter(func(marker):return marker.visible).size()<=app.MAX_CONTACT_LABELS,"HUD has a bounded contact budget")
 expect(app.markers.all(func(marker):return not marker.text.contains("◇")),"Contact icon does not depend on a missing font glyph")
 expect(view.far_visibility(6900)==1 and view.far_visibility(9700)==0,"Fade completes before clipping")
 var previous := 1.0
 for distance in range(7000,9700,100):
  var amount: float=view.far_visibility(distance)
  expect(amount<=previous and amount>=0,"Distance fade is monotonic");previous=amount
 for i in 30:view.stream_neighbors();await process_frame
 expect(view.neighbors.size()>4,"Open-world station coverage preserved")
 var distant: int=-1
 for id in view.neighbors:
  if not view.neighbors[id].detail:distant=id;break
 expect(distant>=0,"Fixture has a distant station")
 var entry=view.neighbors[distant];var node=entry.root
 expect(entry.age==0,"New stations begin transparent")
 view._process(.6)
 expect(is_equal_approx(entry.age,.6),"Fade runs on real frame time")
 for model in node.get_children():
  expect(is_equal_approx(model.stream_visibility,.5),"Station halfway visible at fade midpoint")
  for index in model.figure.get_node("Mesh").mesh.get_surface_count():
   expect(is_equal_approx(model.figure.get_node("Mesh").get_surface_override_material(index).get_shader_parameter("stream_visibility"),.5),"Actual shader receives fade")
 view._process(.7)
 for model in node.get_children():
  expect(model.stream_visibility==1,"Station fade completes")
  var frame: int=model.sampled_frame;var pattern: int=model.last_pattern
  model.advance(12000)
  expect(model.sampled_frame==frame and model.last_pattern==pattern,"Streamed station configuration does not cycle")
 var target: Vector3=node.global_position
 app.camera.position=target+Vector3(0,0,2100)
 for i in 40:view.stream_neighbors();await process_frame
 expect(view.neighbors[distant].detail and view.neighbors[distant].root==node,"Detail promotion keeps existing mesh")
 app.camera.position=target+Vector3(0,0,2400);view.stream_neighbors()
 expect(view.neighbors[distant].detail,"Detail hysteresis")
 app.camera.position=target+Vector3(0,0,3000)
 for i in 40:view.stream_neighbors();await process_frame
 expect(not view.neighbors[distant].detail and view.neighbors[distant].root==node,"Demotion keeps existing silhouette")
 expect(node.find_children("*","StaticBody3D",true,false).is_empty(),"Distant collision released")
 app.camera.position=target+Vector3(0,0,11000);view.stream_neighbors();await process_frame
 expect(not view.neighbors.has(distant),"Invisible station unloads outside range")
 # Region entry must not replace every visible station and restart its fade.
 var destination: int=view.neighbors.keys()[0]
 var incoming=view.neighbors[destination].root.get_child(0)
 var old_station: int=app.session.station_id;var old_main=view.station_nodes[0]
 var retained: Dictionary={}
 for id in view.neighbors:
  if id!=destination:retained[id]={"node":view.neighbors[id].root,"global":view.neighbors[id].root.position+app.world.geography.anchor,"age":view.neighbors[id].age}
 var old_player=view.player_model
 app.session.docked=false;view.combat.update(app.world.region,120)
 var wake_count: int=view.combat.player_wake.size()
 app.world.enter_region(destination);view.rebuild()
 expect(view.station_nodes[0]==incoming,"Incoming station promotes existing meshes")
 expect(view.neighbors[old_station].root.get_child(0)==old_main,"Departing station retains existing meshes")
 expect(view.player_model==old_player and view.combat.player_wake.size()==wake_count,"Region entry preserves player mesh and wake")
 for id in retained:
  expect(view.neighbors[id].root==retained[id].node and view.neighbors[id].age==retained[id].age,"Neighbor retains its mesh and fade state")
  expect((view.neighbors[id].root.position+app.world.geography.anchor).distance_to(retained[id].global)<.02,"Neighbor preserves world position after rebasing")
 var light_count: int=view.station_nodes[0].find_children("*","Light3D",true,false).size()
 view.rebuild()
 expect(view.station_nodes[0]==incoming and incoming.find_children("*","Light3D",true,false).size()==light_count,"Repeated rebuild does not duplicate lights or geometry")
 view.modern_graphics=not view.modern_graphics;view.rebuild()
 expect(view.station_nodes[0]!=incoming,"Changing rendering mode still rebuilds materials")
 player_mesh=view.player_model.figure.get_node("Mesh")
 expect(player_mesh.get_surface_override_material(0).get_shader_parameter("source_glow_visible")==true,"Classic ships retain their original glow geometry")
 await check_scene_particle_pitch(app)
 app.queue_free();await process_frame
 DirAccess.remove_absolute("user://stream-check.cfg")
 print("ENGINE_STREAM ",failures," failures")
 quit(1 if failures else 0)

func check_station_machinery(view) -> void:
 var engine=view.model(3304)
 engine.configure_station({"animation_range":[0,0]})
 var before: Array=engine.current_bones.duplicate(true)
 var pattern: int=engine.last_pattern
 engine.advance(137)
 expect(engine.current_bones[2]!=before[2],"Imported station fan rotates")
 for index in [0,1,3,4]:expect(engine.current_bones[index]==before[index],"Fan animation leaves the housing and beacons fixed")
 expect(engine.last_pattern==pattern and engine.sampled_frame==0,"Fan animation does not change emblems or station configuration")
 var mesh: MeshInstance3D=engine.figure.get_node("Mesh")
 var uploaded: Array=mesh.get_surface_override_material(0).get_shader_parameter("source_bones")
 expect(uploaded[2]==load("res://scripts/model_library.gd").matrix(engine.current_bones[2]),"Animated rotor reaches the actual render material")
 engine.advance(863)
 expect(engine.current_bones==before,"Three-blade rotor closes its repeating cycle without a pose jump")
 engine.queue_free()
 await process_frame

func station_surface_triangles(view) -> Dictionary:
 var result: Dictionary={}
 var Math=load("res://native/simulation/fixed_math.gd")
 for id in [3302,3304,3305,3306,3308]:
  var model=view.model(id);model.configure_station({"animation_range":[0,0]})
  var points: Array=[];var cursor:=0
  for index in model.source.bones.size():
   var values: Array=model.current_bones[index]
   var basis:=Basis(Vector3(values[0],values[4],values[8]),Vector3(values[1],values[5],values[9]),Vector3(values[2],values[6],values[10]))
   var translation:=Vector3(values[3],values[7],values[11])
   for count in int(model.source.bones[index].vertices):
    points.append(basis*Math.vector(model.source.vertices.slice(cursor*3,cursor*3+3))+translation);cursor+=1
  var triangles: Array=[]
  for polygon in model.source.polygons:
   if int(polygon.blend)!=0 or (int(polygon.pattern)!=0 and (int(polygon.pattern)&model.last_pattern)==0):continue
   for index in range(0,polygon.indices.size(),3):triangles.append([points[int(polygon.indices[index])],points[int(polygon.indices[index+1])],points[int(polygon.indices[index+2])]])
  result[id]=triangles
  if id in [3302,3304]:model.queue_free();continue
  # Probe both roof and floor across the habitable interior, not just bounds.
  for x in [-1500,0,1500]:
   for z in [-1000,500,2000]:
    for side in [-1,1]:
     var inside:=Vector3(x,0,z);var outside:=Vector3(x,side*6000,z)
     expect(triangles.any(func(t):return Geometry3D.segment_intersects_triangle(inside,outside,t[0],t[1],t[2])!=null),"Imported module %d has a closed roof/floor at %d/%d"%[id,x,z])
  model.queue_free()
 return result
