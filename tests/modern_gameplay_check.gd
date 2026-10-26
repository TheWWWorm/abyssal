extends SceneTree
const Session=preload("res://native/simulation/session.gd")
const World=preload("res://native/simulation/world.gd")
const Fishing=preload("res://native/simulation/fishing.gd")
const Creature=preload("res://native/simulation/creature.gd")
const Weapon=preload("res://native/simulation/weapon.gd")
const NPC=preload("res://native/simulation/npc.gd")
const Math=preload("res://native/simulation/fixed_math.gd")
var failures := 0
var checks := 0
var data: Dictionary
func expect(ok: bool,why: String) -> void:
 checks+=1
 if not ok:failures+=1;push_error(why)
func fixture(chapter: int):
 var session:=Session.new();session.new_game(data,"Modern campaign",812)
 while session.campaign.chapter<chapter:session.campaign.next_chapter(session.counters)
 session.prepare_station(session.campaign.primary.destination)
 var world:=World.new();world.configure(session);world.build_docked_view();session.docked=false;return world
func _initialize():call_deferred("run")
func run():
 data=JSON.parse_string(FileAccess.get_file_as_string(OS.get_cmdline_user_args()[0]))
 # Build every imported chapter; encounter goals must have a realizable outcome.
 for chapter in range(1,data.campaign.size()+1):
  var world=fixture(chapter);var region=world.region
  expect(region!=null,"Chapter builds %d"%chapter)
  if region==null:continue
  for tick in 4:region.step(40)
  if region.success!=null:
   expect(not region.success.evaluate(region,region.elapsed_ms),"Objective starts incomplete %d"%chapter)
   match region.success.metric:
    "harvest":
     # A catch still on the line does not count; one in the hold does.
     for actor in region.creatures:
      if actor.species==region.success.species:actor.subdued=true
     expect(not region.success.evaluate(region,region.elapsed_ms),"Fish being reeled in do not count yet %d"%chapter)
     for actor in region.creatures:
      if actor.species==region.success.species:actor.health.enabled=false
    "enemy_rescued":region.enemies[region.success.value].protect(true);region.enemies[region.success.value].capturable=false
    "all_rescued":
     for actor in region.enemies:actor.protect(true);actor.capturable=false
    _:
     for actor in region.enemies:actor.health.hull=0;actor.state=4;actor.health.enabled=false
     region.recount()
   expect(region.success.evaluate(region,region.elapsed_ms),"Goal has an attainable completion %d"%chapter)
   # The mission completes after the objective has stayed met for a while.
   if chapter==7:
    region.step(40)
    expect(region.pending_mission==null,"Mission complete waits after the last catch")
    for tick in region.COMPLETION_DELAY_MS/40:
     if region.pending_mission!=null:break
     region.step(40)
    expect(region.pending_mission==region.mission,"Mission completes once the wait has run")
  # Radio references remain bounded even for a changed formation.
  for entry in region.timeline:entry.evaluate(region)
  world.dispose()
 # A board board_offer's Check location marks its destination on the chart (bp.a(al)).
 var chart_world=fixture(12);var board_offer=preload("res://native/simulation/mission.gd").new()
 board_offer.kind=3;board_offer.destination=(chart_world.session.station_id+1)%chart_world.session.stations.size()
 var Chart=preload("res://native/presentation/overworld_map.gd")
 expect(Chart.objectives(chart_world,board_offer.destination).is_empty(),"An offer not taken on is unmarked")
 Chart.preview_mission=board_offer
 expect(not Chart.objectives(chart_world,board_offer.destination).is_empty(),"Check location marks the offer's destination")
 Chart.preview_mission=null
 # A species' range is drawn about its home station.
 var chart:=Chart.new();chart.world=chart_world
 expect(not chart.species_home(0).is_empty(),"A fish has a home station for its range")
 chart.free();chart_world.dispose()
 # The radar's picture sits under the caption and grows the marker to fit.
 var mark:=preload("res://native/presentation/contact_marker.gd").new();root.add_child(mark)
 mark.display("","","",Color.WHITE,50.0,ImageTexture.create_from_image(Image.create(18,15,false,Image.FORMAT_RGBA8)))
 expect(mark.picture!=null and mark.size.y>=mark.PICTURE_SIZE.y and mark.size.x>=mark.ICON_WIDTH+mark.PICTURE_SIZE.x,"A scanned contact shows its picture")
 mark.display("x","","",Color.WHITE,50.0)
 expect(mark.picture==null,"A reused marker drops the picture")
 mark.queue_free()
 # Completion cannot suppress a side contract because a previous mission is done.
 var side=fixture(12);var session=side.session;session.campaign.primary.completed=true
 session.campaign.secondary.kind=8;session.campaign.secondary.destination=session.station_id
 expect(session.campaign.completion(true,0,session.station_id,session.ship,session.counters)==session.campaign.secondary,"Completed story does not block side-contract reward")
 side.dispose()
 # The finale is the phone game's staged one: Raoul's ship beaten down,
 # turned into the capsule that runs for the station, the shots of the
 # player and the friends, and the credits at the twenty-fifth call.
 var finale=fixture(data.campaign.size()-1);var region=finale.region
 expect(region.enemies.size()>=9 and region.friends.size()==5,"The last chapter fields five freighters, three pirates, Raoul and five friends")
 for index in region.enemies.size()-1:
  var actor=region.enemies[index];actor.health.hull=0;actor.health.enabled=false;actor.state=4
 var transmissions:=0;var credits:=0
 for tick in 3000:
  region.step(40)
  if region.finale_stage==1 and region.enemies[-1].health.hull>0:region.enemies[-1].health.hull=0
  if region.finale_stage==2:region.enemies[-1].pose.origin=[0,0,0]
  if region.active_transmission!=null:transmissions+=1;region.acknowledge_transmission()
  var event=region.events.filter(func(entry):return entry.kind=="credits")
  if not event.is_empty():credits+=1;region.events.clear();break
 expect(transmissions>=25,"The finale's radio calls are all delivered (%d)"%transmissions)
 expect(credits==1 and region.finale_stage==8 and region.pending_mission==null,"The credits roll after the last call")
 region.acknowledge_credits()
 expect(region.pending_mission==region.mission,"Acknowledging the credits ends the chapter")
 region.acknowledge_completion();expect(finale.session.campaign.finished(),"Finale advances to free play")
 finale.dispose()
 # Fishing as the phone game runs it: the creature's own fight decides
 # the countdown, the catch is lost the moment it is out of view, and a
 # subdued catch is drawn in and taken aboard once.
 var a=fish_fixture();var b=fish_fixture()
 for i in 50:a.hook.advance(40);a.fish.advance(40,a.world.session.rng,a.world.region.player.pose.origin)
 expect(a.hook.hooked and a.fish.fleeing and a.fish.struggle_remaining<a.fish.struggle_total,"A hooked creature runs and spends its strength")
 a.hook.visible_to_camera=func(_point):return false
 a.hook.advance(40)
 expect(not a.hook.hooked and not a.fish.towing and a.world.session.counters.i==1,"Losing sight of the catch loses it, and the log counts it")
 expect(not a.hook.weapon.request_fire(a.world.region.player.pose,40),"A harpoon line that comes free reloads before the next shot")
 a.world.region.loadout.groups.append([a.hook.weapon]) # As region.configure shares it.
 var gun:=Weapon.new();gun.configure(5,10,1000,800,10,[0,0,0]);var cannon:=Weapon.new();cannon.configure(5,10,1000,2000,10,[0,0,0])
 a.world.region.loadout.groups.push_front([gun,cannon]);gun.elapsed=0;cannon.elapsed=1000
 var guns: Dictionary=preload("res://native/presentation/flight_instruments.gd").guns_state(a.world.region)
 expect(guns.mode=="reloading" and is_equal_approx(guns.fraction,.5),"The fire button follows the gun with the longest firing interval")
 a.world.region.loadout.groups.pop_front()
 var reload: Dictionary=preload("res://native/presentation/flight_instruments.gd").harpoon_state(a.world.region)
 expect(reload.mode=="reloading" and reload.fraction<1.0,"The HUD shows the harpoon reloading like the booster")
 a.hook.weapon.advance(300)
 expect(preload("res://native/presentation/flight_instruments.gd").harpoon_state(a.world.region).mode=="ready","The HUD shows the harpoon ready once it has reloaded")
 expect(a.hook.weapon.request_fire(a.world.region.player.pose,40),"The harpoon fires again once it has reloaded")
 b.fish.subdued=true;b.fish.pose.origin=[0,0,-25000]
 var before: int=b.world.session.counters.h
 for i in 200:
  b.hook.advance(40)
  if not b.hook.hooked:break
 expect(not b.hook.hooked and not b.fish.health.enabled,"Successful catch detaches and deactivates target")
 expect(b.world.session.counters.h==before+1,"Catch recorded exactly once")
 a.world.dispose();b.world.dispose()
 # A creature that will not fit stays on the water, off the line.
 var c=fish_fixture();c.fish.mass=c.world.session.ship.capacity()+1;c.fish.subdued=true;c.fish.pose.origin=c.world.region.player.pose.origin.duplicate()
 c.hook.advance(40)
 expect(c.fish.health.enabled and c.fish.capturable and not c.hook.hooked,"Full hold preserves the catch and releases safely")
 c.world.dispose()
 check_harpoon_targets()
 # Cho's export capsules carry goods toward the surface. The simulation's
 # positive Y is depth, so both placement and travel must use negative Y.
 var export_world=fixture(10);var exports: Array=export_world.region.friends.filter(func(actor):return actor.get("kind")=="capsule")
 expect(exports.size()==export_world.region.mission.total,"The Cho mission launches its full export-capsule stream")
 for capsule in exports:
  expect(capsule.pose.origin[1]<=0 and capsule.pose.origin[1]>-75000,"Export capsules start above their station")
  capsule.pose.origin[1]=-10000
  var start: Vector3=capsule.pose.godot_transform().origin
  capsule.advance(40)
  expect(capsule.pose.godot_transform().origin.y>start.y and not capsule.capturable,"An export capsule rises in the rendered world and cannot be hooked")
  expect(capsule.pose.forward[1]<0,"An ascending capsule points toward shallower water")
  capsule.pose.origin[1]=-75001;capsule.advance(40)
  expect(capsule.pose.origin==[0,-3000,0] and capsule.state==0 and capsule.health.enabled,"Past the ascent limit the next capsule launches above the station")
  expect(capsule.events.is_empty(),"An intact capsule leaving the encounter does not count as a loss")
 # Recycling must not bypass the mission's destruction counter or failure.
 var losses: int=export_world.region.mission.minimum
 for index in losses:exports[index].health.hull=0
 export_world.region.step(40)
 expect(export_world.region.special_destroyed==losses and export_world.region.failed,"Destroyed export capsules still trigger the Cho loss limit")
 export_world.dispose()
 # Swept hits catch a small target between frame endpoints, and a full pool
 # cannot consume cooldown or report a fictitious launch.
 var target:=NPC.new();target.health.configure(30,0,0);target.pose.origin=[0,0,2000];target.radius=100
 var shot:=Weapon.new();shot.configure(10,1,3000,200,100,[0,0,0]);shot.targets=[target]
 var pose=preload("res://native/simulation/ship_transform.gd").new();pose.math.sine_table=data.constants.dt["a:[S"];pose.origin=[0,0,0]
 var launch_hook:=Weapon.new();launch_hook.configure(0,1,2000,100,20,[0,0,700]);launch_hook.fishing=true
 for angle in [0,700,1024,1400,2048,3000]:
  pose.set_euler(angle,450,0)
  var forward:=Weapon.vector(pose.forward).normalized()
  var muzzle:=Weapon.vector(pose.origin)+Weapon.vector(pose.rotate_direction(launch_hook.mount))
  for wrong in [muzzle,muzzle-forward*100,muzzle+Weapon.vector(pose.up)*5]:
   launch_hook.remaining[0]=-1;launch_hook.launch(pose,40,Weapon.coordinates(wrong))
   expect(Weapon.vector(launch_hook.velocities[0]).normalized().dot(forward)>.999,"Close, backward and sideways hook aim uses the launcher heading through a full flip")
  var valid:=muzzle+forward*4000+Weapon.vector(pose.right)*.15
  launch_hook.remaining[0]=-1;launch_hook.launch(pose,40,Weapon.coordinates(valid))
  expect(Weapon.vector(launch_hook.velocities[0]).normalized().dot((valid-muzzle).normalized())>.999,"Valid forward hook aim preserves reticle convergence")
 pose.set_euler(0,0,0)
 shot.elapsed=200;expect(shot.request_fire(pose,40,[0,0,4000]),"Weapon fires at the cooldown boundary")
 var serial:=shot.launch_serial;shot.elapsed=200
 expect(not shot.request_fire(pose,40,[0,0,4000]) and shot.launch_serial==serial and shot.elapsed==200,"Full pool preserves fire state")
 shot.advance(40);expect(target.health.hull==20,"Swept hit catches target between samples")
 shot.advance(40);expect(target.health.hull==20,"One projectile damages its target only once")
 check_projectile_contacts()
 check_torpedo_retirement()
 check_torpedo_region()
 var layers=preload("res://native/simulation/health.gd").new();layers.configure(50,10,20);layers.damage(35)
 expect(layers.hull==45 and layers.shield==0 and layers.armor==0,"Damage flows through defensive layers")
 layers.configure(50,10,20);layers.damage(15,"armor");layers.damage(15,"armor")
 expect(layers.armor==0 and layers.hull==50,"Pressure damage is borne by its layer alone while any of it is left")
 layers.damage(15,"armor");expect(layers.hull==35,"Once the layer is gone the hull takes the pressure")
 # The AI takes the first live target of its list within five hundred
 # metres, and drops one that dies.
 var pilot:=NPC.new();pilot.pose.math.sine_table=data.constants.dt["a:[S"];pilot.rng=Session.new().rng
 var far:=NPC.new();far.health.configure(30,0,0);far.pose.origin=[0,0,60000]
 pilot.targets=[far,target];pilot.choose_target(40)
 expect(pilot.target==target,"AI takes the first live target within notice")
 target.health.hull=0;target.health.enabled=false;pilot.choose_target(40);expect(pilot.target==null or pilot.target!=target,"AI drops defeated targets")
 # A course only a fraction off the bow used to alternate by a whole turn
 # step: normalising the tiny heading error magnified it, then the next tick
 # corrected the overshoot in the other direction.
 var cruiser:=NPC.new();cruiser.configure(0,1,false,[0,0,0],data,10,Session.new().rng)
 cruiser.health.configure(100,0,0);cruiser.activate();cruiser.pose.face([0,0,4096])
 cruiser.route=preload("res://native/simulation/route.gd").new();cruiser.route.configure([1000,0,1000000])
 cruiser.advance(40)
 var previous_heading: Array=cruiser.pose.forward.duplicate();var heading_jump:=0
 for _tick in 12:
  cruiser.advance(40)
  heading_jump=maxi(heading_jump,preload("res://native/simulation/fixed_math.gd").length_of(preload("res://native/simulation/fixed_math.gd").subtracted(cruiser.pose.forward,previous_heading)))
  previous_heading=cruiser.pose.forward.duplicate()
 expect(heading_jump<=2,"AI holds a nearly aligned course without alternating steering steps (%d)"%heading_jump)
 pilot.targets=[];pilot.target=null;shot.targets=[]
 # The job board as the phone game posts it: one to eight offers, kinds
 # by the station's side, fees on the fifty with a deposit, and never a
 # delivery of the story's own goods.
 var contracts=preload("res://native/simulation/contracts.gd").new()
 contracts.session=Session.new();contracts.session.new_game(data,"Contract check",901)
 var bounded:=true;var sided:=true;var priced:=true
 var portrait_offers: Array=[]
 for station in contracts.session.stations:
  var colonist: bool=contracts.session.is_colonist_station(station.id)
  var offers: Array=contracts.generate(station);bounded=bounded and offers.size()>=1 and offers.size()<=8
  portrait_offers.append_array(offers)
  for offer in offers:
   if colonist:sided=sided and offer.kind not in [13,14,6,12]
   else:sided=sided and offer.kind not in [12,5,4,7,11]
   priced=priced and offer.reward%50==0 and offer.deposit%50==0 and offer.reward>0
   if offer.kind in [13,14]:priced=priced and offer.item_id not in [33,34,35,37,38,39,40] and offer.item_count>0
 expect(bounded,"Every board carries one to eight offers")
 expect(sided,"Offers follow the station's side")
 expect(priced,"Fees and deposits fall on the fifty and deliveries avoid the story's goods")
 check_contract_portraits(portrait_offers)
 var delivery_session=contracts.session
 delivery_session.ship.set_cargo([delivery_session.make_goods(0,3)])
 var delivery=preload("res://native/simulation/mission.gd").new()
 delivery.kind=14;delivery.destination=0;delivery.item_id=0;delivery.item_count=2;delivery.reward=500
 delivery_session.campaign.primary.completed=true;delivery_session.campaign.secondary=delivery
 delivery_session.campaign.rebel_stations[0]=true
 delivery_session.arrive()
 expect(delivery_session.ship.cargo_used==3,"Docking preserves cargo for deliveries and player-directed trading")
 expect(delivery_session.campaign.completion(true,0,0,delivery_session.ship,delivery_session.counters)==delivery,"Delivery remains eligible after docking")
 var payment_before: int=delivery_session.credits
 delivery_session.complete_mission(delivery);delivery_session.complete_mission(delivery)
 expect(delivery_session.ship.cargo_used==1 and delivery_session.credits==payment_before+500,"Delivery consumes required goods and pays only once")
 delivery_session.campaign.rebel_stations[0]=false
 delivery_session.ship.set_cargo([delivery_session.make_goods(0,3)])
 var colonial_delivery=preload("res://native/simulation/mission.gd").new()
 colonial_delivery.kind=14;colonial_delivery.destination=0;colonial_delivery.item_id=0;colonial_delivery.item_count=2;colonial_delivery.reward=500
 delivery_session.campaign.secondary=colonial_delivery
 var prior: int=delivery_session.credits
 delivery_session.arrive()
 expect(delivery_session.ship.cargo_used==0 and delivery_session.credits==prior+500+delivery_session.make_goods(0,1).minimum_price,"Colonist docking completes a due delivery before cashing out the remainder")
 # Close-range pilots must keep a firing solution instead of orbiting forever.
 var regression_duel=fixture(10)
 var regression_pilot=NPC.new();regression_pilot.configure(0,2,true,[0,0,0],data,10,regression_duel.session.rng)
 regression_pilot.health.configure(100,0,0);regression_pilot.activate()
 var regression_victim=NPC.new();regression_victim.configure(0,1,false,[0,0,12000],data,10,regression_duel.session.rng)
 regression_victim.health.configure(100,0,0);regression_pilot.targets=[regression_victim]
 var regression_gun=Weapon.new();regression_gun.configure(5,2,3000,200,20,[0,0,0]);regression_pilot.weapons=[regression_gun]
 for tick in 200:
  regression_gun.advance(40);regression_pilot.advance(40)
 expect(regression_gun.launch_serial>2,"An opponent with its nose on a target inside 350 m fires")
 # A mark straight behind once left a ship flying away from it for good:
 # the correction lay back along its heading and never turned it.
 var runaway=NPC.new();runaway.configure(0,2,true,[0,0,0],data,10,regression_duel.session.rng)
 runaway.health.configure(100,0,0);runaway.activate()
 var left_behind=NPC.new();left_behind.configure(0,1,false,[0,0,-30000],data,10,regression_duel.session.rng)
 left_behind.health.configure(100,0,0);runaway.targets=[left_behind]
 var furthest:=0
 for tick in 500:
  runaway.advance(40);runaway.straight=false
  furthest=maxi(furthest,runaway.pose.origin[2])
 expect(furthest<20000 and Math.dot_long(runaway.pose.forward,Math.normalize_vector(Math.subtracted(left_behind.pose.origin,runaway.pose.origin)))>0,"A ship turns round for a target straight behind it")
 regression_pilot.targets=[];regression_pilot.weapons=[];regression_duel.dispose()
 var regression_navigation=fixture(10);regression_navigation.session.docked=false
 regression_navigation.region.route.configure([0,0,30000,0,0,60000])
 expect(regression_navigation.navigate_encounter(),"Encounter regression_navigation starts")
 regression_navigation.region.route.advance([0,0,30000]);regression_navigation.update_autopilot()
 expect(regression_navigation.local_target==[0,0,60000],"Encounter autopilot follows the new route point immediately")
 regression_navigation.region.success=null;regression_navigation.region.failure=null;regression_navigation.update_autopilot()
 expect(not regression_navigation.autopilot and regression_navigation.encounter_navigation_point()==null,"Resolved encounter cannot keep an obsolete regression_navigation target")
 regression_navigation.dispose()
 check_mission_navigation_subjects()
 check_full_hold()
 print("MODERN_GAMEPLAY ",checks," checks; ",failures," failures")
 quit(1 if failures else 0)
func check_contract_portraits(offers: Array) -> void:
 # The imported sheet deliberately shares some hairstyles between columns.
 # Face parts must stay in one column, while the female column draws its
 # chin before its suit. A hairstyle's appearance cannot identify a column.
 var parts: Dictionary=data.constants.ab
 var table: Array=parts["a:[[[B"].duplicate(true)
 for row in table:
  for column in row.size():row[column]=row[column].map(func(id):return int(id))
 var layered:=true;var coherent:=true;var named:=true;var sided:=true
 var columns_seen: Dictionary={};var hair_seen: Array=[{},{},{}]
 var accessories_seen: Dictionary={}
 for offer in offers:
  var layers: Array=offer.portrait
  if layers.size()!=6:layered=false;continue
  var column: int=-1
  for candidate in 3:
   var suit_layer: int=2 if candidate==2 else 1
   var chin_layer: int=1 if candidate==2 else 2
   if layers[suit_layer] in table[1][candidate] and layers[chin_layer] in table[2][candidate]:column=candidate;break
  if column<0:layered=false;continue
  columns_seen[column]=true;hair_seen[column][int(layers[4])]=true
  accessories_seen[int(layers[5])>=0]=true
  coherent=coherent and layers[3] in table[3][column] and layers[4] in table[4][column] and (int(layers[5])<0 or layers[5] in table[5][column])
  named=named and offer.sponsor in data.name_pools[0 if column==2 else 1]
  sided=sided and int(layers[0])==int(parts["f:[B"][offer.sponsor_faction])
 expect(layered,"Contract portraits keep all six layers and the original chin/suit draw order")
 expect(coherent,"Each contract portrait takes eyes, hair and accessories from its face column")
 expect(named and sided,"A contract's portrait matches its sponsor name pool and faction")
 expect(columns_seen.size()==3 and accessories_seen.size()==2,"The seeded boards exercise all face columns and both accessory states")
 var shared_seen:=true
 for hair in table[4][0]:
  if hair in table[4][2]:shared_seen=shared_seen and hair_seen[0].has(int(hair)) and hair_seen[2].has(int(hair))
 expect(shared_seen,"Hairstyles shared by the original sheet remain reachable in both portrait columns")
func check_mission_navigation_subjects() -> void:
 var world=fixture(10);var region=world.region
 region.route.configure([]);region.player.pose.origin=[0,0,0]
 var pirate:=NPC.new();pirate.health.configure(100,0,0);pirate.pose.origin=[100,0,0]
 var debris=preload("res://native/simulation/special_actor.gd").new();debris.kind="debris";debris.health.configure(1,0,0);debris.pose.origin=[20000,0,0]
 region.enemies=[debris,pirate]
 region.success=preload("res://native/simulation/encounter_goal.gd").new().configure("first_enemies_dead",[],1)
 expect(world.encounter_navigation_subject()==debris and world.encounter_navigation_point()==debris.pose.origin,"Junk-removal navigation follows debris rather than the nearer incidental pirate")
 debris.health.hull=0;debris.state=3
 expect(world.encounter_navigation_point()==null,"Clearing every mission subject never redirects the waypoint to an unrelated pirate")
 region.success.configure("enemy_dead",[],0);debris.health.hull=1;debris.state=0
 expect(world.encounter_navigation_subject()==debris,"A named kill objective selects its indexed target")
 debris.excluded_from_objectives=true
 expect(world.encounter_navigation_point()==null,"An actor excluded from objectives receives no mission destination")
 debris.excluded_from_objectives=false
 region.enemies=[pirate];pirate.protect(true);pirate.health.hull=0;pirate.state=4
 region.success.configure("enemy_rescued",[],0)
 expect(world.encounter_navigation_subject()==pirate,"A rescue destination follows the recoverable wreck after combat")
 pirate.capture(world.session)
 expect(world.encounter_navigation_point()==null,"A recovered mission subject leaves no stale waypoint")
 region.route.configure([0,0,10000])
 expect(world.encounter_navigation_point()==[0,0,10000] and world.encounter_navigation_subject()==null,"An authored route remains separate from actor targeting")
 region.route.configure([])
 var fish=region.creatures[0];fish.health.hull=1;fish.health.enabled=true;fish.state=0;region.creatures=[fish]
 region.success.configure("harvest",[],1,fish.species)
 expect(world.encounter_navigation_subject()==fish,"A harvest mission follows its requested species")
 fish.health.enabled=false
 expect(world.encounter_navigation_point()==null,"A collected catch is no longer a navigation target")
 world.dispose()
func fish_fixture() -> Dictionary:
 var world=fixture(12);var fish:=Creature.new();fish.configure(int(data.constants.ah["b:[S"][0]),data.tables.creatures[0],world.session.rng,world.region.sine,[0,0,-10000]);fish.mass=1
 var hook:=Fishing.new();hook.player=world.region.player;hook.session=world.session
 hook.weapon=Weapon.new();hook.weapon.configure(0,1,2000,300,10,[0,0,0]);hook.weapon.fishing=true
 hook.visible_to_camera=func(_point):return true
 hook.attach(fish)
 return {"world":world,"fish":fish,"hook":hook}
func fire_harpoon_at(actor, world):
 var line:=Fishing.new();line.player=world.region.player;line.session=world.session
 line.player.pose.origin=[0,0,0];line.player.pose.face([0,0,4096])
 actor.pose.origin=[0,0,4000]
 line.weapon=preload("res://native/simulation/weapon_loadout.gd").create(world.session.make_equipment(15),data)
 line.weapon.targets=[actor];line.slow_percent=line.weapon.slow_percent
 line.visible_to_camera=func(_point):return true
 expect(line.weapon.request_fire(line.player.pose,40),"A fresh harpoon launches toward the target")
 for _tick in ceili(line.weapon.lifetime/40.0)+1:
  line.advance(40)
  if not line.weapon.impacts.is_empty() or not line.weapon.active:break
 return line
func check_projectile_contacts() -> void:
 var pose=preload("res://native/simulation/ship_transform.gd").new()
 var small:=NPC.new();small.health.configure(100,0,0);small.radius=100;small.pose.origin=[0,0,2000]
 var large:=NPC.new();large.health.configure(100,0,0);large.radius=1000;large.pose.origin=[0,0,2200]
 for targets in [[small,large],[large,small]]:
  small.health.hull=100;large.health.hull=100
  var shot:=Weapon.new();shot.configure(10,1,3000,200,100,[0,0,0]);shot.targets=targets
  shot.request_fire(pose,40);shot.advance(40)
  expect(large.health.hull==90 and small.health.hull==100 and shot.impacts.size()==1,"The first hull surface takes the shot regardless of target-list order")
  expect(shot.positions[0]==[0,0,1200] and not shot.active and shot.remaining[0]<0,"A projectile retires at the surface, without penetrating to the target centre")
  shot.targets=[]
 var travel:=Vector3(0,0,1000)
 expect(is_equal_approx(Weapon.sphere_entry(Vector3.ZERO,travel,Vector3(100,0,500),100),.5),"A tangent segment detects exactly one surface contact")
 expect(Weapon.sphere_entry(Vector3.ZERO,travel,Vector3(101,0,500),100)<0,"A close pass outside the hull remains a miss")
 expect(Weapon.sphere_entry(Vector3.ZERO,travel,Vector3(0,0,-500),100)<0,"A target behind a departing shot is not hit")
 expect(Weapon.sphere_entry(Vector3.ZERO,travel,Vector3(0,0,50),100)==0,"A shot starting inside a target impacts immediately")
 expect(Weapon.sphere_entry(Vector3.ZERO,Vector3.ZERO,Vector3(0,0,500),100)<0,"A stationary shot outside a target does not create an impact")
func check_torpedo_retirement() -> void:
 var session:=Session.new();session.new_game(data,"Torpedo impacts",1942)
 var pose=preload("res://native/simulation/ship_transform.gd").new()
 for id in [12,13,14]:
  var shot=preload("res://native/simulation/weapon_loadout.gd").create(session.make_equipment(id),data)
  var first:=NPC.new();first.health.configure(100,0,0);first.radius=2000
  first.pose.origin=[0,0,roundi(shot.speed*2000)+2000]
  var adjacent:=NPC.new();adjacent.health.configure(100,0,0);adjacent.radius=2000
  adjacent.pose.origin=[3500,0,first.pose.origin[2]+4000]
  shot.targets=[adjacent,first]
  shot.request_fire(pose,40)
  for _tick in ceili(shot.lifetime/40.0)+1:
   shot.advance(40)
   if not shot.impacts.is_empty() or not shot.active:break
  expect(shot.impacts.size()==1 and shot.impacts[0].target==first and first.health.hull==100-shot.damage,"Torpedo %d hits the first ship after its homing phase begins"%id)
  var impact_position: Array=shot.positions[0].duplicate()
  expect(not shot.active and shot.remaining[0]<0 and adjacent.health.hull==100,"Torpedo %d retires at its first impact without hitting the adjacent ship"%id)
  first.health.enabled=false
  for _tick in 200:shot.advance(40)
  expect(shot.positions[0]==impact_position and shot.impacts.size()==1 and adjacent.health.hull==100 and shot.launch_serial==1,"Retired torpedo %d cannot retarget, bounce, or damage a second ship on later ticks"%id)
  expect(shot.request_fire(pose,40) and shot.launch_serial==2 and shot.positions[0]==[0,0,0] and shot.previous_positions[0]==[0,0,0],"Reusing torpedo %d's pool slot is a separate launch from the muzzle"%id)
  shot.impacts.clear()
  for _tick in ceili(shot.lifetime/40.0)+1:
   shot.advance(40)
   if not shot.impacts.is_empty() or not shot.active:break
  expect(shot.impacts.size()==1 and shot.impacts[0].target==adjacent and adjacent.health.hull==100-shot.damage,"Only the second launched torpedo %d can hit the adjacent ship"%id)
  shot.targets=[]
func check_harpoon_targets() -> void:
 # A hit and a retained line are different: the phone game stops a harpoon
 # on a live hull, but only keeps the line on wildlife, salvage and mines.
 var world=fixture(12)
 var ship:=NPC.new();ship.configure(0,2,true,[0,0,4000],data,12,world.session.rng);ship.health.configure(100,0,0);ship.activate()
 var line=fire_harpoon_at(ship,world)
 expect(line.weapon.impacts.size()==1 and line.weapon.impacts[0].target==ship,"A live hull stops the harpoon instead of letting it pass through")
 expect(not line.hooked and line.target==null and not line.weapon.hook_busy and line.weapon.hooked_target==null and not line.weapon.active,"A live hull does not retain a harpoon line")
 expect(ship.health.hull==100 and world.session.counters.i==0,"The live-hull hit causes no gun damage or lost-catch count")
 expect(not line.weapon.request_fire(line.player.pose,40),"A rejected attachment still keeps the shot's normal reload")
 line.weapon.targets=[]
 for wreck_state in [3,4]:
  ship.health.hull=0;ship.state=wreck_state
  line=fire_harpoon_at(ship,world)
  expect(line.hooked and line.target==ship and line.ready_to_tow(),"A recoverable wreck retains the line in state %d"%wreck_state)
  var before: int=ship.pose.origin[2];line.advance(40)
  expect(line.towing and ship.pose.origin[2]<before,"The wreck is actually drawn toward the player")
  line.release();line.weapon.targets=[]
 ship.capturable=false;ship.state=4
 line=fire_harpoon_at(ship,world)
 expect(not line.hooked and not line.weapon.active,"A nonrecoverable wreck cannot retain a line")
 line.weapon.targets=[]
 var fish:=Creature.new();fish.configure(int(data.constants.ah["b:[S"][0]),data.tables.creatures[0],world.session.rng,world.region.sine,[0,0,4000])
 line=fire_harpoon_at(fish,world)
 expect(line.hooked and fish.hooked and not line.ready_to_tow(),"Live wildlife retains the line and must struggle before it can be towed")
 fish.subdued=true;line.advance(40)
 expect(line.towing and fish.towing,"A subdued creature starts towing")
 line.release();line.weapon.targets=[]
 fish.state=4;fish.health.hull=0;fish.subdued=false
 line=fire_harpoon_at(fish,world)
 expect(line.hooked and line.ready_to_tow(),"A carcass can be hooked and towed without another struggle")
 line.release();line.weapon.targets=[]
 var special=preload("res://native/simulation/special_actor.gd").new()
 special.configure_special("capsule",9994,true,[0,0,4000],data,world.session.rng);special.health.configure(32,0,0)
 line=fire_harpoon_at(special,world)
 expect(line.weapon.impacts.size()==1 and not line.hooked and not line.weapon.active,"A supply capsule stops the shot but cannot be collected with a harpoon")
 line.weapon.targets=[]
 special.configure_special("mine",13,true,[0,0,4000],data,world.session.rng);special.health.configure(4,0,0)
 line=fire_harpoon_at(special,world)
 expect(not special.capturable and line.hooked and line.ready_to_tow(),"The original mine exception remains hookable without a salvage flag")
 special.pose.origin=line.player.pose.origin.duplicate();line.advance(40)
 expect(special.state==999 and not special.health.enabled and not line.hooked,"Reeling a mine all the way in detonates it and releases the line")
 line.weapon.targets=[]
 ship.health.enabled=false
 line=fire_harpoon_at(ship,world)
 expect(line.weapon.impacts.is_empty() and not line.hooked,"An inactive or already collected actor cannot stop or retain a harpoon")
 line.weapon.targets=[];world.dispose()
func check_torpedo_region() -> void:
 # Exercise the same Region.step path used in the playable range, including
 # actor movement/avoidance and forwarding the projectile's impact event.
 var session:=Session.new();session.new_game(data,"Adjacent targets",1942)
 var Demo=preload("res://native/simulation/demo_session.gd")
 Demo.initialize(session)
 var draft=Demo.new();draft.select_equipment(session,0,14);draft.apply(session)
 var world:=World.new();world.configure(session);expect(world.depart(),"The torpedo reproduction enters the playable test range")
 var region=world.region
 var shot=region.weapons[0]
 var first=region.enemies[0];var adjacent=region.enemies[1]
 first.set_position([0,0,-86000]);adjacent.set_position([3500,0,-90000])
 first.health.configure(200,0,0);adjacent.health.configure(200,0,0)
 shot.targets=[adjacent,first]
 var impact_count:=0;var impact_position: Array=[]
 for tick in 200:
  region.step(40,{"guns":true} if tick==0 else {})
  for event in region.visual_events:
   if event.kind=="impact" and event.time==region.elapsed_ms:
    impact_count+=1;impact_position=event.position.duplicate()
  if impact_count>0:
   first.health.enabled=false;first.capturable=false;first.state=4
 expect(shot.launch_serial==1 and impact_count==1 and first.health.hull==200-shot.damage,"A single torpedo creates exactly one hit through the gameplay update path")
 expect(adjacent.health.hull==200 and not shot.active and shot.remaining[0]<0 and shot.positions[0]==impact_position,"The range torpedo stays retired even when the first ship disappears beside another target")
 expect(not region.player.contact,"Ship collision avoidance is not engaged in the adjacent-target reproduction")
 world.dispose()
func check_full_hold() -> void:
 # A carcass or a crate that will not fit stays on the water, as a live catch
 # does, instead of being spent; with room it is taken as before.
 var parts:=fish_fixture();var world=parts.world;var carcass=parts.fish
 var room: int=world.session.ship.capacity()-world.session.ship.cargo_used
 carcass.state=4;carcass.meat=true;carcass.mass=room+1;carcass.render_scale=[800,800,800]
 expect(not carcass.capture(world.session) and carcass.health.enabled and carcass.capturable and carcass.render_scale==[4096,4096,4096] and carcass.events.has("cargo_full"),"A carcass that will not fit stays on the water, full size")
 carcass.mass=1;carcass.events.clear()
 expect(carcass.capture(world.session) and not carcass.health.enabled and carcass.events.has("meat_collected"),"A carcass that fits goes into the hold")
 var crate:=NPC.new();crate.health.configure(30,0,0);crate.capturable=true;crate.loot=world.session.make_goods(18,room+5)
 expect(not crate.capture(world.session) and crate.capturable and crate.health.enabled and crate.state!=4 and crate.events.has("cargo_full"),"A crate that will not fit stays on the water")
 crate.loot=world.session.make_goods(18,1);crate.events.clear()
 expect(crate.capture(world.session) and not crate.capturable and crate.events.has("salvaged"),"A crate that fits is salvaged")
 world.dispose()
