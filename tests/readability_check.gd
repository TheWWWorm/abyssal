extends SceneTree
var failures:=0
func expect(ok: bool,why: String) -> void:
 if not ok:failures+=1;push_error(why)
func _initialize():call_deferred("run")
func settle():
 for i in 5:await process_frame
func run():
 var args:=OS.get_cmdline_user_args()
 var content=load("res://native/content.gd").new()
 if not content.load_cache(args[0]):quit(1);return
 root.size=Vector2i(1280,720)
 var app=load("res://native/gameplay.gd").new();app.content=content;app.settings_path="user://readability-test.cfg";app.save_path="user://readability-test.json"
 DirAccess.remove_absolute(app.settings_path);root.add_child(app);await settle()
 app.set_process(false);app.view.set_process(false);app.abyss.set_process(false)
 expect(app.world.region.creatures.size()==6,"Initial ambient population is six animals")
 for modern in [false,true]:
  for detail in [false,true]:
   app.modern_graphics=modern;app.graphics.detail=detail;app.apply_graphics()
   expect(app.abyss.particles.visible,"Sea bubbles remain enabled across lighting/detail presets")
 app.modern_graphics=true;app.graphics.detail=true;app.apply_graphics()
 app.show_graphics();await settle()
 expect(not app.column.find_children("*","Button",true,false).any(func(button):return button.text.contains("Modern weapon effects")),"Removed weapon effect switch is absent")
 app.close_page()
 var first=app.world.region.creatures[0];var second=app.world.region.creatures[3]
 expect(Vector3(first.habitat_center[0],0,first.habitat_center[2]).distance_to(Vector3(second.habitat_center[0],0,second.habitat_center[2]))>40000,"Schools have open water between them")
 var trail=load("res://native/simulation/bubble_trail.gd").new();trail.advance([0,0,0],120,null);trail.advance([0,0,0],120,null)
 expect(trail.position[0][1]<0,"Bubbles rise in the simulation coordinate system")
 var player=app.world.region.player
 var saved_pose=player.pose.copy_pose()
 app.session.docked=false
 player.pose.set_euler(250,600,300);app.world.previous_render_poses.clear();app.view._process(0)
 var model=app.view.player_model
 var hull_center: Vector3=model.global_transform*model.solid_bounds().get_center()
 expect(absf(app.camera.unproject_position(hull_center).x-app.ui.size.x*.5)<1,"Chase view centers the actual hull horizontally")
 expect(app.camera.global_basis.x.dot(app.world.render_pose(player).basis.x)>.999,"Chase camera follows ship attitude without cosmetic steering bank")
 var TestPlayer=load("res://native/simulation/player.gd")
 var level=TestPlayer.new();level.configure(player.stats,22500,app.world.region.sine);level.unbounded_world=true
 level.pose.set_euler(250,600,300);level.throttle=0;level.set_throttle(0)
 var heading: Vector3=level.pose.basis().z
 for i in 150:level.advance(40)
 expect(absf(level.pose.basis().x.y)<.015,"Roll settles in open-world flight")
 expect(heading.dot(level.pose.basis().z)>.999,"Roll leveling preserves heading and dive angle")
 # Two complete pitch revolutions in each direction, including exact poles.
 var loop_pose=player.pose.copy_pose()
 for direction in [-1,1]:
  var previous_camera := Quaternion.IDENTITY
  var first_camera := Transform3D.IDENTITY
  for angle in range(0,8193,32):
   player.pose.set_euler(direction*angle,430,0);app.world.previous_render_poses.clear();app.view._process(0)
   var rotation: Quaternion=app.camera.global_basis.get_rotation_quaternion()
   if angle>0:expect(previous_camera.angle_to(rotation)<.07,"Camera stays continuous through pitch %d"%(direction*angle))
   else:first_camera=app.camera.global_transform
   expect(app.camera.global_transform.is_finite(),"Full-loop camera transform stays finite")
   previous_camera=rotation
  expect(app.camera.global_position.distance_to(first_camera.origin)<.05,"Two loops return the chase camera to its original position")
 player.pose=loop_pose;app.world.previous_render_poses.clear();app.view._process(0)
 var mouse_player=TestPlayer.new();mouse_player.configure(player.stats,22500,app.world.region.sine);mouse_player.set_throttle(0)
 mouse_player.pose.set_euler(1850,300,100)
 var expected_pose=mouse_player.pose.copy_pose()
 for i in 100:
  mouse_player.mouse_steer(2,8);expected_pose.rotate_local("yaw",2);expected_pose.rotate_local("pitch",8);mouse_player.advance(40)
 expect(mouse_player.pose.basis().get_rotation_quaternion().angle_to(expected_pose.basis().get_rotation_quaternion())<.001,"Auto-leveling does not oppose sustained mouse steering")
 mouse_player.pose.set_euler(2048,0,0)
 for i in 100:mouse_player.advance(40)
 expect(mouse_player.pose.basis().y.y<-.999,"Releasing controls after a half-loop preserves inverted flight")
 var effects=app.view.combat;effects.reset()
 for i in 20:effects.update(app.world.region,40)
 expect(effects.player_wake.size()>8 and effects.bubble_count>0,"Player has a rendered stern wake")
 var emitted: Vector3=effects.player_wake[-1].at-app.world.geography.anchor
 expect((model.global_transform.affine_inverse()*emitted).z>model.solid_bounds().end.z,"Wake emits outside the stern")
 var anchored: Vector3=effects.player_wake[0].at
 app.world.geography.anchor+=Vector3(1000,0,0);effects.update(app.world.region,0)
 expect(effects.player_wake[0].at==anchored,"Existing wake stays in world coordinates")
 app.world.geography.anchor-=Vector3(1000,0,0)
 var tracked: Dictionary=effects.player_wake[0]
 var before_age: float=tracked.age
 app.world.accumulator=8;app.view._process(.008)
 expect(is_equal_approx(tracked.age,before_age+.008),"Wake advances on frames between simulation ticks")
 app.world.accumulator=16;app.view._process(.008)
 app.world.region.elapsed_ms+=40;app.world.accumulator=0;app.view._process(.024)
 expect(is_equal_approx(tracked.age,before_age+.040),"Wake does not double-count interpolation at the next tick")
 app.view._process(0)
 expect(is_equal_approx(tracked.age,before_age+.040),"Paused simulation does not age its wake")
 effects.update(app.world.region,5000)
 expect(effects.player_wake.size()<=16,"Expired wake clears after a long step, with bounded replacement particles")
 player.pose=saved_pose;app.session.docked=true;effects.update(app.world.region,0)
 expect(effects.player_wake.is_empty(),"Docking stops the wake")
 app.world.previous_render_poses.clear();app.view._process(0)
 app.abyss._process(0)
 var eye: Vector3=app.abyss.particle_material.get_shader_parameter("eye")+app.world.geography.anchor
 var phase: Vector3=app.abyss.particle_material.get_shader_parameter("eye_phase")
 var shift:=Vector3(4000,0,1200);app.world.geography.anchor+=shift;app.camera.position-=shift;app.abyss._process(0)
 expect((app.abyss.particle_material.get_shader_parameter("eye")+app.world.geography.anchor as Vector3).is_equal_approx(eye),"Particle world coordinates survive region rebasing")
 expect((app.abyss.particle_material.get_shader_parameter("eye_phase") as Vector3).is_equal_approx(phase),"Particle wrapping phase survives region rebasing")
 expect(app.abyss.particles.global_position.is_equal_approx(app.camera.global_position),"Particle bounds follow the rebased camera")
 app.world.geography.anchor-=shift;app.camera.position+=shift
 app.session.docked=true
 for mode in [2,1]:
  app.touch.mode=mode
  app.show_station();await settle()
  var footer=app.column.get_child(app.column.get_child_count()-1)
  expect(app.sheet_scroll.get_global_rect().encloses(footer.get_global_rect()),"Dock footer fits without clipping; touch mode "+str(mode))
  expect(not app.sheet_scroll.get_v_scroll_bar().visible,"Dock menu does not need a scrollbar at 720p; touch mode "+str(mode))
  if args.size()>1:
   root.get_texture().get_image().save_png(args[1]+"/dock-"+str(mode)+".png")
  for kind in ["trade","manufacture"]:
   app.show_market(kind);await settle()
   var list=app.column.find_child("StockRows",true,false)
   var detail=app.column.find_child("SelectedItem",true,false)
   expect(list!=null and detail!=null,kind+" uses the shared list/detail presentation")
   if detail==null:continue
   expect(app.sheet_scroll.get_global_rect().encloses(detail.get_global_rect()),kind+" detail and actions fit at 720p; touch mode "+str(mode))
   var choices=list.get_children().filter(func(node):return node is Button)
   if choices.size()>1:
    choices[1].pressed.emit();await settle()
    expect(app.market_selection==1,"Choosing a row updates "+kind+" selection")
    expect(root.gui_get_focus_owner().name=="Stock_1","Row selection retains controller focus")
   if args.size()>1:
    root.get_texture().get_image().save_png(args[1]+"/"+kind+"-"+str(mode)+".png")
   var station: Dictionary=app.session.stations[app.session.station_id]
   var count: int=app.economy.recipes(station).size() if kind=="manufacture" else app.economy.market(station).size()
   for index in count:
    app.market_selection=index;app.show_market(kind);await settle()
    detail=app.column.find_child("SelectedItem",true,false)
    expect(app.sheet_scroll.get_global_rect().encloses(detail.get_global_rect()),"Detail fits for %s item %d touch %d"%[kind,index,mode])
 # Exercise the actual new transaction buttons, not just the economy methods.
 app.touch.mode=2;app.market_selection=0;app.show_market("trade");await settle()
 var station: Dictionary=app.session.stations[app.session.station_id]
 var rows: Array=app.economy.market(station);rows.sort_custom(func(a,b):return a.id<b.id)
 var credits: int=app.session.credits;var cargo: int=app.session.ship.cargo_used;var price: int=rows[0].price
 var detail=app.column.find_child("SelectedItem",true,false)
 var actions=detail.get_children().filter(func(node):return node is Button)
 expect(not actions[0].disabled,"Affordable cargo can be bought")
 actions[0].pressed.emit();await settle()
 expect(app.session.credits==credits-price and app.session.ship.cargo_used==cargo+1,"Buy button updates wallet and hold")
 detail=app.column.find_child("SelectedItem",true,false);actions=detail.get_children().filter(func(node):return node is Button)
 expect(not actions[1].disabled,"Owned cargo can be sold")
 actions[1].pressed.emit();await settle()
 expect(app.session.credits==credits and app.session.ship.cargo_used==cargo,"Sell button updates wallet and hold")
 var recipes: Array=app.economy.recipes(station);recipes.sort_custom(func(a,b):return a.id<b.id)
 var recipe=recipes[0];var ingredients: Array=[]
 for index in recipe.ingredients.size():ingredients.append(app.session.make_goods(recipe.ingredients[index],recipe.ingredient_counts[index]))
 app.session.ship.set_cargo(ingredients);app.show_market("manufacture");await settle()
 detail=app.column.find_child("SelectedItem",true,false);actions=detail.get_children().filter(func(node):return node is Button)
 expect(not actions[0].disabled,"Craft button enables when materials are present")
 actions[0].pressed.emit();await settle()
 expect(app.session.ship.cargo.any(func(item):return item.id==recipe.id and item.owned==1),"Craft button creates the selected recipe")
 app.queue_free();await process_frame
 for name in ["readability-test.cfg","readability-test.json","readability-test.json.bak"]:DirAccess.remove_absolute("user://"+name)
 print("READABILITY ",failures," failures");quit(1 if failures else 0)
