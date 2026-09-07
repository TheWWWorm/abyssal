extends SceneTree
const Session=preload("res://native/simulation/session.gd")
const World=preload("res://native/simulation/world.gd")
const Fishing=preload("res://native/simulation/fishing.gd")
const Creature=preload("res://native/simulation/creature.gd")
const Weapon=preload("res://native/simulation/weapon.gd")
const NPC=preload("res://native/simulation/npc.gd")
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
   for actor in region.success.subjects:
    match region.success.metric:
     "recover":actor.capturable=false;actor.health.hull=0
     "harvest":
      if actor.species==region.success.species:actor.subdued=true
     _:actor.health.hull=0
   expect(region.success.evaluate(region,region.elapsed_ms),"Goal has an attainable completion %d"%chapter)
  # Radio references remain bounded even for a changed formation.
  for entry in region.timeline:entry.evaluate(region)
  world.dispose()
 # Completion cannot suppress a side contract because a previous mission is done.
 var side=fixture(12);var session=side.session;session.campaign.primary.completed=true
 session.campaign.secondary.kind=8;session.campaign.secondary.destination=session.station_id
 expect(session.campaign.completion(true,0,session.station_id,session.ship,session.counters)==session.campaign.secondary,"Completed story does not block side-contract reward")
 side.dispose()
 # Finale uses radio dependencies and a credits acknowledgement, without indexed
 # chapter-specific camera/formation actions. Exercise all ending transmissions.
 var finale=fixture(data.campaign.size()-1);var region=finale.region
 for actor in region.enemies:actor.health.hull=0;actor.health.enabled=false;actor.state=4
 region.elapsed_ms=60000
 var transmissions:=0;var credits:=0
 for tick in 200:
  region.step(40)
  if region.active_transmission!=null:transmissions+=1;region.acknowledge_transmission()
  if region.ending_pending:credits+=1;region.acknowledge_credits();break
 expect(transmissions==region.timeline.size(),"All ending radio lines are acknowledged")
 expect(credits==1 and region.pending_mission==region.mission,"Finale finishes through one credits acknowledgement")
 region.acknowledge_completion();expect(finale.session.campaign.finished(),"Finale advances to free play")
 finale.dispose()
 # Fishing: compare two step partitions; brief camera slips do not discard work.
 var a=fish_fixture();var b=fish_fixture()
 for i in 50:a.hook.advance(40)
 for i in 100:b.hook.advance(20)
 expect(a.fish.struggle_remaining==b.fish.struggle_remaining,"Fishing progress is time-based, independent of step partition")
 a.hook.visible_to_camera=func(_point):return false
 for i in 25:a.hook.advance(40)
 expect(a.hook.hooked,"One-second camera slip keeps the line")
 for i in 110:a.hook.advance(40)
 expect(not a.hook.hooked and not a.fish.towing,"Extended loss of sight releases the line cleanly")
 # No teleporting/shrinking during towing; successful collection detaches once.
 b.fish.subdued=true;b.fish.pose.origin=[0,0,-25000]
 var before: int=b.world.session.counters.h
 for i in 200:
  b.hook.advance(40)
  if not b.hook.hooked:break
 expect(not b.hook.hooked and not b.fish.health.enabled,"Successful catch detaches and deactivates target")
 expect(b.world.session.counters.h==before+1,"Catch recorded exactly once")
 a.world.dispose();b.world.dispose()
 # Cargo-full recovery keeps a salvageable target instead of losing its cargo.
 var c=fish_fixture();c.fish.mass=c.world.session.ship.capacity()+1;c.fish.subdued=true;c.fish.pose.origin=c.world.region.player.pose.origin.duplicate()
 c.hook.advance(40)
 expect(c.fish.health.enabled and c.fish.capturable and not c.hook.hooked,"Full hold preserves the catch and releases safely")
 c.world.dispose()
 # Rescue capsules can be collected alive; the tether must not require damage.
 var rescue=fish_fixture();rescue.hook.detach(false)
 var capsule=preload("res://native/simulation/special_actor.gd").new()
 capsule.configure_special("capsule",9994,false,rescue.world.region.player.pose.origin.duplicate(),data,rescue.world.session.rng)
 capsule.health.configure(30,0,0)
 var credits_before: int=rescue.world.session.credits
 rescue.hook.attach(capsule);rescue.hook.advance(40)
 expect(capsule.state==4 and not rescue.hook.hooked and rescue.world.session.credits==credits_before+100,"Live capsule is rescued and rewarded once")
 rescue.world.dispose()
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
 var layers=preload("res://native/simulation/health.gd").new();layers.configure(50,10,20);layers.damage(35)
 expect(layers.hull==45 and layers.shield==0 and layers.armor==0,"Damage flows through defensive layers")
 layers.damage(-10);expect(layers.hull==45,"Negative damage cannot heal")
 # AI chooses nearby live threats, without duplicated targets or frame RNG.
 var pilot:=NPC.new();pilot.pose.math.sine_table=data.constants.dt["a:[S"]
 var far:=NPC.new();far.health.configure(30,0,0);far.pose.origin=[0,0,50000]
 pilot.targets=[far,target];pilot.choose_target(40)
 expect(pilot.target==target,"AI selects closest live threat")
 target.health.hull=0;pilot.choose_target(40);expect(pilot.target==far,"AI drops defeated targets")
 pilot.targets=[];pilot.target=null;shot.targets=[]
 # Every station gets a finite offer list; travel offers are pressure-compatible.
 var contracts=preload("res://native/simulation/contracts.gd").new()
 contracts.session=Session.new();contracts.session.new_game(data,"Contract check",901)
 var bounded:=true;var reachable:=true;var deliverable:=true
 for station in contracts.session.stations:
  var offers: Array=contracts.generate(station);bounded=bounded and offers.size()==4
  for offer in offers:
   var destination: Dictionary=contracts.session.stations[offer.destination]
   if offer.destination!=station.id:
    reachable=reachable and destination.percent>=contracts.session.ship.shallow_percent and destination.percent<=contracts.session.ship.deep_percent
   if offer.kind in [13,14]:deliverable=deliverable and offer.item_count>0 and offer.item_count<=contracts.session.ship.capacity()
 expect(bounded,"All stations receive a bounded four-contract board")
 expect(reachable,"Remote contracts stay inside current ship pressure limits")
 expect(deliverable,"Delivery quantities fit the current hold")
 contracts.session.ship.shallow_percent=1000;contracts.session.ship.deep_percent=1001
 expect(contracts.destination(contracts.session.stations[0])==0,"No reachable destination falls back without retry loops")
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
 expect(delivery_session.ship.cargo_used==0 and delivery_session.credits==prior+500+delivery_session.make_goods(0,1).total_price(),"Colonist docking completes a due delivery before cashing out the remainder")
 # Close-range pilots must keep a firing solution instead of orbiting forever.
 var regression_duel=fixture(10)
 var regression_pilot=NPC.new();regression_pilot.configure(0,2,true,[0,0,0],data,10,regression_duel.session.rng)
 regression_pilot.health.configure(100,0,0);regression_pilot.activate()
 var regression_victim=NPC.new();regression_victim.configure(0,1,false,[0,0,-8000],data,10,regression_duel.session.rng)
 regression_victim.health.configure(100,0,0);regression_pilot.targets=[regression_victim]
 var regression_gun=Weapon.new();regression_gun.configure(5,2,3000,200,20,[0,0,0]);regression_pilot.weapons=[regression_gun]
 for tick in 200:
  regression_gun.advance(40);regression_pilot.advance(40)
 expect(regression_gun.launch_serial>2,"Close-range opponent fires rather than orbiting without alignment")
 regression_pilot.targets=[];regression_pilot.weapons=[];regression_duel.dispose()
 var regression_navigation=fixture(10);regression_navigation.session.docked=false
 regression_navigation.region.route.configure([0,0,30000,0,0,60000])
 expect(regression_navigation.navigate_encounter(),"Encounter regression_navigation starts")
 regression_navigation.region.route.advance([0,0,30000]);regression_navigation.update_autopilot()
 expect(regression_navigation.local_target==[0,0,60000],"Encounter autopilot follows the new route point immediately")
 regression_navigation.region.success=null;regression_navigation.region.failure=null;regression_navigation.update_autopilot()
 expect(not regression_navigation.autopilot and regression_navigation.encounter_navigation_point()==null,"Resolved encounter cannot keep an obsolete regression_navigation target")
 regression_navigation.dispose()
 print("MODERN_GAMEPLAY ",checks," checks; ",failures," failures")
 quit(1 if failures else 0)
func fish_fixture() -> Dictionary:
 var world=fixture(12);var fish:=Creature.new();fish.configure(int(data.constants.ah["b:[S"][0]),data.tables.creatures[0],world.session.rng,world.region.sine,[0,0,-10000]);fish.mass=1
 var hook:=Fishing.new();hook.player=world.region.player;hook.session=world.session
 hook.weapon=Weapon.new();hook.weapon.configure(0,1,2000,300,10,[0,0,0]);hook.weapon.fishing=true
 hook.visible_to_camera=func(_point):return true
 hook.attach(fish)
 return {"world":world,"fish":fish,"hook":hook}
