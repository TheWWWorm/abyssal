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
 expect(app.world.region.creatures.size()==20,"The water is stocked with the original's twenty creatures")
 for modern in [false,true]:
  for detail in [false,true]:
   app.modern_graphics=modern;app.graphics.detail=detail;app.apply_graphics()
   expect(app.abyss.particles.visible,"Sea bubbles remain enabled across lighting/detail presets")
 app.modern_graphics=true;app.graphics.detail=true;app.apply_graphics()
 app.show_graphics();await settle()
 expect(not app.column.find_children("*","Button",true,false).any(func(button):return button.text.contains("Modern weapon effects")),"Removed weapon effect switch is absent")
 app.close_page()
 # Wildlife follows the camera: anything left four hundred metres behind is
 # set down three hundred metres out again, so open water is never empty.
 var region=app.world.region;var far_player=region.player.pose.origin.duplicate();far_player[0]+=250000
 for creature in region.creatures:creature.advance(40,app.session.rng,far_player)
 var near:=0
 for creature in region.creatures:
  if creature.constrained or not creature.health.enabled:continue
  if Vector3(creature.pose.origin[0]-far_player[0],creature.pose.origin[1]-far_player[1],creature.pose.origin[2]-far_player[2]).length()<=30500:near+=1
 expect(near==region.creatures.size(),"Creatures left behind reappear three hundred metres from the camera")
 # They are brought in out of the haze, not switched on: fresh on arrival,
 # and the view's coverage of them climbs from nothing over a couple of seconds.
 expect(region.creatures.all(func(c):return c.fresh or c.constrained or not c.health.enabled),"A creature set down anew is marked fresh for the view")
 app.world.previous_render_poses.clear();app.view._process(0.1)
 var revealing: int=region.creatures.filter(func(c):return app.view.objects.has(c.get_instance_id()) and app.view.objects[c.get_instance_id()].reveal<1.0 and app.view.objects[c.get_instance_id()].visual.stream_visibility<1.0).size()
 expect(revealing>=region.creatures.size()/2 and not region.creatures.any(func(c):return c.fresh),"The view fades a fresh creature in and takes the mark")
 for i in 30:app.view._process(0.1)
 expect(region.creatures.all(func(c):return not app.view.objects.has(c.get_instance_id()) or app.view.objects[c.get_instance_id()].visual.stream_visibility>=1.0),"Three seconds on, every creature is whole")
 # A headlight beam stops at a fish rather than lighting the water behind it.
 var fish=region.creatures.filter(func(c):return app.view.objects.has(c.get_instance_id()))
 if not fish.is_empty():
  var visual: Node3D=app.view.objects[fish[0].get_instance_id()].visual
  var occluders: Array=visual.find_children("*","StaticBody3D",true,false).filter(func(body):return body.collision_layer==app.view.BEAM_OCCLUDER_LAYER)
  expect(occluders.size()==1,"A creature carries a beam occluder on its own layer")
  var Abyss=load("res://native/presentation/abyss.gd")
  var lamp:=SpotLight3D.new();app.view.add_child(lamp)
  var middle: Vector3=visual.global_transform*visual.solid_bounds().get_center()
  lamp.look_at_from_position(middle+Vector3(0,0,20),middle)
  var beam=Abyss.create_beam();app.view.add_child(beam)
  await physics_frame;await physics_frame
  Abyss.shade_beam_in(app.view.get_world_3d().direct_space_state,lamp,beam,0);Abyss.shade_beam_in(app.view.get_world_3d().direct_space_state,lamp,beam,1)
  var reach: Image=beam.get_meta("occlusion_image")
  var centre: float=reach.get_pixel(Abyss.OCCLUSION_SIZE/2,Abyss.OCCLUSION_SIZE/2).r
  expect(centre<20,"The beam's reach ends at the fish in front of the lamp")
  # A submarine blocks a beam as well, but not the beams of its own lamps.
  var sub=load("res://native/simulation/npc.gd").new()
  var away: Array=region.player.pose.origin.duplicate();away[0]+=40000
  sub.configure(1,2,true,away,app.content.data,app.session.campaign.chapter,app.session.rng)
  sub.state=1;region.enemies.append(sub);app.view._process(0)
  var hull_visual: Node3D=app.view.objects[sub.get_instance_id()].visual
  var hull_body: Array=hull_visual.find_children("*","StaticBody3D",true,false).filter(func(body):return body.collision_layer==app.view.BEAM_OCCLUDER_LAYER)
  expect(hull_body.size()==1 and is_instance_valid(app.view.player_occluder),"Vessels, the player's included, carry beam occluders")
  var hull_middle: Vector3=hull_visual.global_transform*hull_visual.solid_bounds().get_center()
  lamp.look_at_from_position(hull_middle+Vector3(0,0,20),hull_middle)
  await physics_frame;await physics_frame
  var space: PhysicsDirectSpaceState3D=app.view.get_world_3d().direct_space_state
  Abyss.shade_beam_in(space,lamp,beam,0);Abyss.shade_beam_in(space,lamp,beam,1)
  expect(reach.get_pixel(Abyss.OCCLUSION_SIZE/2,Abyss.OCCLUSION_SIZE/2).r<20,"A beam stops at another submarine")
  var own: Array[RID]=[hull_body[0].get_rid()]
  lamp.look_at_from_position(hull_middle,hull_middle+Vector3(0,0,-20))
  Abyss.shade_beam_in(space,lamp,beam,0,own);Abyss.shade_beam_in(space,lamp,beam,1,own)
  expect(reach.get_pixel(Abyss.OCCLUSION_SIZE/2,Abyss.OCCLUSION_SIZE/2).r>Abyss.BEAM_LENGTH,"A vessel's own lamps shine out through its hull box")
  region.enemies.erase(sub);app.view._process(0)
  lamp.queue_free();beam.queue_free()
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
 mouse_player.smooth_steering=false
 mouse_player.pose.set_euler(1850,300,100)
 var expected_pose=mouse_player.pose.copy_pose()
 for i in 100:
  mouse_player.mouse_steer(2,8);expected_pose.rotate_local("yaw",2);expected_pose.rotate_local("pitch",8);mouse_player.advance(40)
 expect(mouse_player.pose.basis().get_rotation_quaternion().angle_to(expected_pose.basis().get_rotation_quaternion())<.001,"Auto-leveling does not oppose sustained mouse steering")
 mouse_player.pose.set_euler(2048,0,0)
 for i in 40:mouse_player.advance(40)
 expect(mouse_player.pose.basis().y.y<-.2 and absf(mouse_player.pose.basis().x.y)>.3,"Released on its back the hull is rolling the short way towards upright")
 for i in 160:mouse_player.advance(40)
 expect(mouse_player.pose.basis().y.y>.99 and absf(mouse_player.pose.basis().x.y)<.04,"Releasing controls after a half-loop rolls the hull upright, as bb.a does")
 check_helm_response(TestPlayer,player.stats,app.world.region.sine)
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
 # Trade and the workshop are rebel services; Gosu is a colonist holding.
 app.session.campaign.rebel_stations[app.session.station_id]=true
 # The market carries nought to four lines by the session's draw; the pages
 # are what is under test, so make sure there is a line to show and buy.
 var holding: Dictionary=app.session.stations[app.session.station_id]
 while app.economy.market(holding).is_empty(): holding.cargo=app.economy.generate_goods(holding)
 app.show_ship_status();await settle()
 expect(app.column.find_children("*","Label",true,false).any(func(item):return item.text.contains("Equipment") and item.text.contains("slots") and item.text.contains("Cargo")),"Ship and Cargo page shows equipment slots alongside cargo capacity")
 app.show_market("equipment");await settle()
 var tabs=app.column.find_child("EquipmentTabs",true,false)
 expect(tabs!=null and tabs.get_child_count()==2,"Equipment store offers Shop and Ship equipment tabs")
 expect(app.column.find_children("*","Label",true,false).any(func(item):return item.text.contains("EQUIPMENT SLOTS")),"Equipment store shows fitted and total ship slots")
 expect(app.column.find_children("*","Label",true,false).any(func(item):return item.text=="SHOP STOCK"),"Shop tab lists station stock")
 tabs.get_node("ShipEquipmentTab").pressed.emit();await settle()
 expect(app.equipment_tab==1 and app.column.find_children("*","Label",true,false).any(func(item):return item.text=="INSTALLED SYSTEMS"),"Ship equipment tab lists fitted systems separately")
 app.column.find_child("ShopTab",true,false).pressed.emit();await settle()
 expect(app.equipment_tab==0,"Shop tab returns to station stock")
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

func check_helm_response(TestPlayer,stats,sine: Array) -> void:
 # Direct is the original: the full key rate on the first tick, none on the
 # tick after release. Smooth leans in over a few ticks, eases out after
 # release, and still arrives at the same heading for the same held key.
 var direct=TestPlayer.new();direct.configure(stats,22500,sine);direct.set_throttle(0);direct.smooth_steering=false
 var smooth=TestPlayer.new();smooth.configure(stats,22500,sine);smooth.set_throttle(0);smooth.smooth_steering=true
 var full_step: int=roundi(stats.steering()*40/3.0)
 direct.steer(1,0,40);direct.advance(40)
 expect(direct.yaw_step==full_step,"Direct helm turns at the original's full rate on the first tick")
 smooth.steer(1,0,40);smooth.advance(40)
 expect(smooth.yaw_step>0 and smooth.yaw_step<full_step,"Smooth helm leans into a turn rather than snapping to full rate")
 for i in 30:smooth.steer(1,0,40);smooth.advance(40)
 expect(smooth.yaw_step==full_step,"Smooth helm reaches the original's full rate once held")
 smooth.advance(40)
 expect(smooth.yaw_step>0 and smooth.yaw_step<full_step,"Smooth helm eases out after the key is released")
 for i in 40:smooth.advance(40)
 expect(smooth.yaw_step==0 and smooth.yaw_level==0,"Smooth helm comes fully to rest")
 # The mouse is held to a ceiling in smooth mode, and a wide flick is not
 # carried on for seconds afterwards.
 var flick=TestPlayer.new();flick.configure(stats,22500,sine);flick.set_throttle(0);flick.smooth_steering=true
 var before: Vector3=Vector3(flick.pose.forward[0],flick.pose.forward[1],flick.pose.forward[2]).normalized()
 flick.mouse_steer(4000,0);flick.advance(40)
 var after: Vector3=Vector3(flick.pose.forward[0],flick.pose.forward[1],flick.pose.forward[2]).normalized()
 var ceiling: float=stats.steering()*flick.MOUSE_RATE_FACTOR*40/3.0
 expect(before.angle_to(after)<=(ceiling+1)*TAU/4096.0,"Smooth helm holds mouse turning to the ceiling rate")
 for i in 50:flick.advance(40)
 after=Vector3(flick.pose.forward[0],flick.pose.forward[1],flick.pose.forward[2]).normalized()
 expect(before.angle_to(after)<=(flick.MOUSE_BACKLOG+ceiling+1)*TAU/4096.0 and flick.mouse_remainder.is_zero_approx(),"A wide mouse flick is bounded and does not keep the hull turning")
 var direct_flick=TestPlayer.new();direct_flick.configure(stats,22500,sine);direct_flick.set_throttle(0);direct_flick.smooth_steering=false
 direct_flick.mouse_steer(300,0);direct_flick.advance(40)
 after=Vector3(direct_flick.pose.forward[0],direct_flick.pose.forward[1],direct_flick.pose.forward[2]).normalized()
 expect(absf(before.angle_to(after)-300*TAU/4096.0)<.002,"Direct helm turns one step per mouse unit at once")
 # Lateral thrust leans the rendered hull a few degrees and settles after
 # release; the flight pose itself keeps level, so aim and collision do not.
 var sidestep=TestPlayer.new();sidestep.configure(stats,22500,sine);sidestep.set_throttle(0);sidestep.smooth_steering=false
 var level: Array=sidestep.pose.copy_pose().forward
 for i in 40:sidestep.set_strafe(1);sidestep.advance(40)
 expect(sidestep.visual_bank>=60 and sidestep.visual_bank<=80,"Strafing leans the hull about seven degrees (%d)"%sidestep.visual_bank)
 expect(sidestep.pose.forward==level and sidestep.bank==0,"The lean is only on the rendered hull")
 for i in 40:sidestep.advance(40)
 expect(absi(sidestep.visual_bank)<=2,"The lean settles after the key is released (%d)"%sidestep.visual_bank)
 # bb: a turn leans the hull a unit a millisecond to 384, holds it while
 # the helm is over, and lets it back upright at a fifth of that.
 var leaning=TestPlayer.new();leaning.configure(stats,22500,sine);leaning.set_throttle(0);leaning.smooth_steering=false
 leaning.steer(1,0,40);leaning.advance(40)
 expect(leaning.bank==40,"The lean builds a unit a millisecond (%d)"%leaning.bank)
 for i in 20:leaning.steer(1,0,40);leaning.advance(40)
 expect(leaning.bank==384 and leaning.visual_bank==384,"The lean holds at 384 while the helm is over (%d)"%leaning.bank)
 leaning.advance(40)
 expect(leaning.bank==376,"The hull comes back upright at a fifth of the rate (%d)"%leaning.bank)
 for i in 46:leaning.advance(40)
 expect(leaning.bank>0,"It is still leaning well over a second after the helm centres (%d)"%leaning.bank)
 for i in 4:leaning.advance(40)
 expect(leaning.bank==0,"Level again after about two seconds (%d)"%leaning.bank)
