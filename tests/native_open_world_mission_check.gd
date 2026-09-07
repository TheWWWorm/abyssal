extends SceneTree
const Session=preload("res://native/simulation/session.gd")
const World=preload("res://native/simulation/world.gd")
const Mission=preload("res://native/simulation/mission.gd")
const Math=preload("res://native/simulation/fixed_math.gd")
var failures:=0
var checks:=0
var data: Dictionary
func expect(ok: bool, why: String):
 checks+=1
 if not ok:failures+=1;push_error(why)
func fixture(kind: int):
 var s=Session.new();s.new_game(data,"Encounter navigation",91)
 while s.campaign.chapter<9:s.campaign.next_chapter(s.counters)
 s.campaign.primary.kind=-1
 var m=Mission.new();m.kind=kind;m.destination=113;m.destination_name=s.stations[113].name;m.difficulty=2
 s.campaign.secondary=m
 var w=World.new();w.configure(s);w.depart()
 return w
func _initialize():
 data=JSON.parse_string(FileAccess.get_file_as_string(OS.get_cmdline_user_args()[0]))
 # Every encounter with a local patrol route must guide arrivals to that route.
 for kind in [0,1,2,3,5]:
  var w=fixture(kind)
  expect(w.route_to(113),"Encounter destination is accessible")
  var arrival=Math.subtracted(w.station_origin(113),w.station_origin(0));arrival[2]-=59000
  w.region.player.pose.origin=arrival
  var global_before=w.global_position()
  w.update_autopilot()
  expect(w.session.station_id==113,"Destination simulation activates before the station walls")
  expect(w.global_position()==global_before,"Area activation preserves the world position")
  expect(w.region.mission==w.session.campaign.secondary and not w.region.enemies.is_empty(),"Accepted encounter spawns on open-water arrival")
  expect(w.autopilot and w.local_target==w.region.route.current(),"Arrival targets the mission patrol point instead of the locked dock")
  # Reach by actual fixed-step flight, with normal proximity activation.
  var waypoint: Array=w.region.route.current().duplicate()
  w.region.player.pose.origin=Math.added(waypoint,[0,0,-13000])
  w.region.player.pose.face([0,0,4096]);w.region.player.health.configure(100000,100000,100000)
  for i in 800:
   w.advance(.04)
   if not w.autopilot:break
  expect(not w.autopilot and w.region.route.index>=1,"Local autopilot crosses the strict mission trigger for kind "+str(kind))
  expect(w.region.enemies.any(func(a):return a.health.enabled),"Proximity activates mission enemies")
  w.region.player.pose.origin=[0,0,-14000]
  expect(not w.dock() and "autopilot" in w.message and "quest objective" in w.message,"Encounter docking lock offers an actionable explanation")
  # Mission completion acknowledgement must remove the restriction.
  w.region.pending_mission=w.region.mission;w.region.mission.completed=true;w.region.acknowledge_completion()
  expect(w.dock(),"Docking unlocks after encounter completion")
  w.dispose()
 # A full arrival from the far side must steer around the station and reach
 # the encounter, rather than getting pinned against a module on the way.
 var crossing=fixture(5)
 crossing.route_to(113)
 crossing.region.player.pose.origin=Math.added(Math.subtracted(crossing.station_origin(113),crossing.station_origin(0)),[0,0,-59000])
 crossing.update_autopilot()
 crossing.region.player.health.configure(100000,100000,100000)
 for i in 8000:
  crossing.advance(.04)
  if not crossing.autopilot:break
 expect(not crossing.autopilot and crossing.region.route.index>0,"Continuous station approach reaches the encounter past station collision volumes")
 crossing.dispose()
 # A waypoint-controlled radio trigger must actually fire, not merely show
 # an arrival message before the original strict trigger radius is crossed.
 var scripted=fixture(3);scripted.enter_region(113)
 var line=preload("res://native/simulation/timeline.gd").new();line.kind=0;line.values=[0];scripted.region.timeline=[line]
 scripted.region.player.pose.origin=Math.added(scripted.region.route.current(),[0,0,-13000]);scripted.region.player.pose.face([0,0,4096])
 scripted.region.player.health.configure(100000,100000,100000);scripted.navigate_encounter()
 for i in 800:
  scripted.advance(.04)
  if line.fired:break
 expect(line.fired and scripted.region.active_transmission==line,"Waypoint radio event fires during real autopilot movement")
 scripted.dispose()
 # Manual approaches activate the destination as well, without teleporting.
 var manual=fixture(3)
 var p=Math.subtracted(manual.station_origin(113),manual.station_origin(0));p[2]-=59000
 manual.region.player.pose.origin=p;manual.explore()
 expect(manual.session.station_id==113 and not manual.region.enemies.is_empty(),"Manual flight activates the encounter outside the dock")
 manual.dispose()
 audit_story_target_counts()
 audit_objectives()
 audit_milestone_handoff()
 audit_persistent_chapters()
 audit_failure_and_saves()
 audit_radio_predicates()
 audit_swept_waypoints()
 audit_shared_gates()
 print("NATIVE_OPEN_WORLD_MISSION ",checks," checks across 48 chapters; ",failures," failures")
 quit(1 if failures else 0)

func audit_shared_gates() -> void:
 var w=fixture(-1)
 expect(w.region.gate_index(1)==0,"Starting station uses one shared portal")
 expect(w.region.gates[0]==w.region.gates[1],"Arrival and departure use the visible gate position")
 w.region.player.pose.origin=w.region.gates[0].duplicate()
 expect(w.nearest_safe_gate()==0,"Navigation selects the visible portal")
 w.region.audio_events.clear();w.update_gates(40)
 expect(w.gate_time[0]>0 and w.gate_time[0]==w.gate_time[1],"Shared gate has one opening clock")
 expect(w.region.audio_events.filter(func(e):return e.kind=="gate").size()==1,"Shared gate emits one opening sound")
 w.region.gates=[[0,0,0],[70000,0,0]];w.region.consolidate_gates()
 expect(w.region.gate_index(1)==1 and w.region.gates[0]!=w.region.gates[1],"Distant gates remain separate")
 w.dispose()

func audit_objectives() -> void:
 # Apply gameplay actions to objective actors, then let Region detect and
 # acknowledge success. Never assign pending_mission or completed here.
 for kind in [0,1,2,3,4,5,6,7,9,10,11,12]:
  var world=fixture(kind)
  var mission=world.session.campaign.secondary
  mission.total=5;mission.minimum=3;mission.target_kind=0
  world.enter_region(113)
  var region=world.region
  region.player.health.configure(100000,100000,100000)
  region.player.set_throttle(0)
  for actor in region.enemies:
   actor.health.damage(100000)
   actor.advance(40)
   if kind in [1,2] and actor.protected_target:actor.capture(world.session)
  if kind==7:
   for actor in region.creatures:
    if actor.species==mission.target_kind:actor.health.damage(100000)
  for tick in 150:
   region.step(40)
   if region.active_transmission!=null:region.acknowledge_transmission()
   if region.pending_mission!=null or region.failed:break
  expect(not region.failed and region.pending_mission==mission,"Contract type %d completes through its objective actions"%kind)
  if region.pending_mission!=null:
   var reward_before: int=world.session.credits
   region.acknowledge_completion()
   expect(world.session.credits==reward_before+mission.reward,"Contract reward settles once")
   expect(region.route.current()==null,"Resolved contract removes waypoint")
  world.dispose()
 # Campaign encounters: two different completion orders, with no traversal
 # of optional patrol markers. Enter from opposite sides of the station.
 for chapter in range(1,data.campaign.size()):
  var record: Dictionary=data.campaign[chapter-1].mission
  if int(record.get("a:int",-1)) not in [0,1,2,3,4,5,6,7,9,10,11,12]:continue
  for approach in 3:
   var reverse: bool=approach==1
   var session=Session.new();session.new_game(data,"Campaign trigger audit",91)
   while session.campaign.chapter<chapter:session.campaign.next_chapter(session.counters)
   var destination: int=session.campaign.primary.destination
   session.prepare_station((destination+1)%session.stations.size())
   var world=World.new();world.configure(session);world.depart()
   var before=Math.added(world.station_origin(destination),[59000 if reverse else -59000,0,0])
   world.region.player.pose.origin=Math.subtracted(before,world.station_origin(session.station_id))
   if approach==2:
    session.ship.engine_bonus=1000;session.ship.minimum_depth=0;session.ship.maximum_depth=50000
    expect(world.plan_stream(destination),"Chapter %d permits a prepared STREAM approach"%chapter)
    world.region.player.pose.origin=world.region.gates[world.departure_gate].duplicate()
    world.update_gates(1000)
    expect(world.stream_transfer(),"Chapter %d activates through a real gate transfer"%chapter)
   else:world.explore()
   var region=world.region;var mission=session.campaign.primary
   expect(session.station_id==destination and region.mission==mission,"Chapter %d activates on arrival mode %d"%[chapter,approach])
   region.player.health.configure(100000,100000,100000);region.player.set_throttle(0)
   # Isolate event sequencing from combat balance; actors still take real
   # damage/capture actions and Region owns every completion decision.
   var targets: Array=region.enemies.duplicate()
   if reverse:targets.reverse()
   for actor in targets:
    actor.health.damage(100000);actor.advance(40)
    if actor.protected_target:actor.capture(session)
   if mission.kind==7:
    for actor in region.creatures:
     if actor.species==mission.target_kind:actor.health.damage(100000)
   for tick in 1700:
    region.step(40)
    if region.active_transmission!=null:region.acknowledge_transmission()
    if region.ending_pending:region.acknowledge_credits()
    if region.pending_mission!=null or region.failed:break
   expect(not region.failed and region.pending_mission==mission,"Chapter %d resolves without prescribed waypoints, arrival mode=%d"%[chapter,approach])
   for entry in region.timeline:
    if entry.kind==5:expect(entry.acknowledged,"Chapter %d preserves timed radio when objectives finish early"%chapter)
   if region.pending_mission!=null:
    region.acknowledge_completion()
    expect(session.campaign.chapter==chapter+1,"Chapter %d advances exactly once"%chapter)
   world.dispose()

func audit_milestone_handoff() -> void:
 var session=Session.new();session.new_game(data,"Third contract handoff",901)
 while session.campaign.chapter<9:session.campaign.next_chapter(session.counters)
 session.counters.j=2
 session.prepare_station(session.campaign.primary.destination)
 var contract=Mission.new();contract.kind=3;contract.destination=session.station_id
 session.campaign.secondary=contract
 var world=World.new();world.configure(session);world.depart()
 world.region.player.health.configure(100000,100000,100000);world.region.player.set_throttle(0)
 for actor in world.region.enemies:actor.health.damage(100000)
 world.region.step(40)
 expect(world.region.pending_mission==contract,"Third contract is resolved before the global milestone")
 world.region.events.clear();world.region.acknowledge_completion()
 world.advance(.04)
 expect(world.region.pending_mission==session.campaign.primary,"Third contract triggers story milestone in open water")
 world.region.events.clear();world.region.acknowledge_completion()
 expect(session.campaign.chapter==10,"Milestone advances to the next encounter")
 var location: Array=world.global_position();var journeys: int=session.counters.q
 world.advance(.04)
 expect(world.region.mission==session.campaign.primary and world.region.mission.kind==11,"Next encounter at the same station activates without docking or teleporting")
 expect(world.global_position()==location and session.counters.q==journeys,"Local story handoff preserves position and journey count")
 expect(world.region.events.filter(func(event):return event.kind=="briefing").size()==1,"Open-world encounter produces one arrival briefing")
 world.dispose()

func audit_persistent_chapters() -> void:
 for chapter in range(1,data.campaign.size()+1):
  var kind: int=data.campaign[chapter-1].mission.get("a:int",-1)
  if kind in [0,1,2,3,4,5,6,7,9,10,11,12]:continue
  var session=Session.new();session.new_game(data,"Persistent chapter audit",501)
  while session.campaign.chapter<chapter:session.campaign.next_chapter(session.counters)
  var mission=session.campaign.primary
  session.prepare_station(mission.destination)
  var world=World.new();world.configure(session);world.depart()
  world.region.player.health.configure(100000,100000,100000)
  world.region.player.throttle=0;world.region.player.set_throttle(0)
  match kind:
   -1:
    expect(session.campaign.finished(),"Final chapter is free play")
    world.dispose();continue
   8:
    world.region.player.pose.origin=[0,0,-14000]
    expect(world.dock(),"Dock visit chapter %d accepts direct approach"%chapter)
   13,14:
    session.ship.set_cargo([session.make_goods(mission.item_id,mission.item_count)])
    world.region.player.pose.origin=[0,0,-14000]
    expect(world.dock(),"Delivery chapter %d permits docking with cargo"%chapter)
   17:session.ship.equip(session.make_equipment(mission.threshold))
   20:expect(session.register_catch(0,mission.threshold),"Cargo milestone can be satisfied by catching fish")
   15:
    for index in mission.threshold:
     var contract=Mission.new();contract.kind=8;contract.destination=session.station_id
     session.campaign.secondary=contract
     var completed=session.campaign.completion(true,0,session.station_id,session.ship,session.counters)
     expect(completed==contract,"Passenger contract completes through docking predicate")
     session.complete_mission(completed)
   16:
    for index in mission.threshold:
     var enemy=preload("res://native/simulation/npc.gd").new()
     enemy.configure(0,2,true,[0,0,90000],data,chapter,session.rng);enemy.health.configure(10,0,0)
     world.region.enemies.append(enemy);enemy.health.damage(10)
    world.region.step(40)
   18:
    var count:=0
    for station in session.stations:
     if session.discovered[station.id]:continue
     session.prepare_station(station.id);session.arrive();count+=1
     if count>=mission.threshold:break
   21:
    var economy=preload("res://native/simulation/economy.gd").new();economy.configure(session)
    var recipes: Array=economy.recipes(session.stations[session.station_id])
    expect(not recipes.is_empty(),"Manufacturing chapter has an available recipe")
    if not recipes.is_empty():
     var recipe=recipes[0];var ingredients: Array=[]
     for index in recipe.ingredients.size():ingredients.append(session.make_goods(recipe.ingredients[index],recipe.ingredient_counts[index]))
     for index in mission.threshold:
      session.ship.set_cargo(ingredients.map(func(item):return item.copy_stack(item.owned)))
      expect(economy.manufacture(session.stations[session.station_id],recipe.id,1),"Manufacture action increments the story counter")
   22:
    for tick in 260:
     world.region.step(40)
     if world.region.pending_mission!=null:break
  # Colonist delivery may settle during docking; otherwise use the same
  # predicate/acknowledgement as the station or flight UI.
  if session.campaign.chapter==chapter:
   var completed=world.region.pending_mission
   if completed==null:completed=session.campaign.completion(session.docked,world.region.elapsed_ms,session.station_id,session.ship,session.counters)
   expect(completed==mission,"Chapter %d detects its real milestone action"%chapter)
   if completed!=null:session.complete_mission(completed)
  expect(session.campaign.chapter==chapter+1,"Persistent chapter %d advances once"%chapter)
  var after: int=session.credits;session.complete_mission(mission)
  expect(session.campaign.chapter==chapter+1 and session.credits==after,"Old chapter acknowledgement cannot pay twice")
  world.dispose()

func audit_failure_and_saves() -> void:
 for kind in [1,2,4,6,11]:
  var world=fixture(kind);var mission=world.session.campaign.secondary
  mission.total=5;mission.minimum=3;mission.target_kind=0;mission.reward=500
  world.enter_region(113);var region=world.region
  region.player.health.configure(100000,100000,100000)
  match kind:
   1,2:
    for actor in region.failure.subjects:actor.escaped=true
   4,11:
    for actor in region.friends:actor.health.damage(100000)
   6:
    for actor in region.creatures:actor.health.damage(100000)
  region.step(40)
  expect(region.failed and mission.failed and region.pending_mission==null,"Loss of protected targets fails contract type %d"%kind)
  var credits: int=world.session.credits
  world.session.complete_mission(mission)
  expect(world.session.credits==credits,"Failed contract cannot pay a success reward")
  world.dispose()
 var saves=preload("res://native/simulation/save_store.gd").new()
 for chapter in range(1,data.campaign.size()+1):
  var session=Session.new();session.new_game(data,"Chapter checkpoint",901)
  while session.campaign.chapter<chapter:session.campaign.next_chapter(session.counters)
  session.prepare_station(session.campaign.primary.destination)
  var saved: Dictionary=JSON.parse_string(JSON.stringify(saves.capture(session)))
  var loaded=saves.restore(data,saved)
  expect(loaded!=null,"Chapter %d checkpoint reloads"%chapter)
  if loaded!=null:
   expect(loaded.campaign.chapter==chapter and loaded.campaign.primary.values()==session.campaign.primary.values(),"Chapter %d checkpoint preserves objective thresholds and state"%chapter)
   expect(loaded.counters==session.counters,"Checkpoint cannot reset persistent milestone counters")
func audit_radio_predicates() -> void:
 var Timeline=preload("res://native/simulation/timeline.gd")
 var NPC=preload("res://native/simulation/npc.gd")
 for kind in [0,1,2,3,4,5,6,8,9,10,12,13,14,15,16,17,18,19]:
  var enemy=NPC.new();enemy.health.configure(100,0,0)
  var other=NPC.new();other.health.configure(100,0,0)
  var friend=NPC.new();friend.health.configure(100,0,0)
  var prior=Timeline.new()
  var route=preload("res://native/simulation/route.gd").new();route.configure([0,0,10000])
  var region: Dictionary={"enemies":[enemy,other],"friends":[friend],"route":route,"enemy_count":2,"friendly_count":1,"elapsed_ms":0,"encounter_resolved":false,"timeline":[prior],"session":{"counters":{"h":0}}}
  var line=Timeline.new();line.kind=kind;line.values=[100] if kind==5 else [0]
  if kind in [8,16]:enemy.health.enabled=false;other.health.enabled=false
  if kind==10:friend.health.enabled=false
  expect(not line.evaluate(region),"Radio trigger %d waits for its condition"%kind)
  match kind:
   0:route.advance([0,0,10000])
   1,9,12,15,19:enemy.health.damage(100)
   2:friend.health.damage(100)
   3:region.enemy_count=0
   4:region.friendly_count=0
   5:region.elapsed_ms=100
   6:prior.acknowledged=true
   8,16:enemy.health.enabled=true
   10:friend.health.enabled=true
   13:region.session.counters.h=1
   14:enemy.protect(true);enemy.capturable=false
   17:other.health.damage(100)
   18:enemy.towing=true
  line.poll(region)
  # Eligibility survives a transient condition while another line is on screen.
  if kind in [8,16]:enemy.health.enabled=false
  if kind==10:friend.health.enabled=false
  expect(line.evaluate(region),"Radio trigger %d becomes deliverable"%kind)
  expect(not line.evaluate(region),"Radio trigger %d fires only once"%kind)

func audit_swept_waypoints() -> void:
 var Route=preload("res://native/simulation/route.gd")
 for axis in [Vector3.RIGHT,Vector3.UP,Vector3.FORWARD]:
  var route=Route.new();route.configure([0,0,0])
  var start: Vector3=axis*-10000;var finish: Vector3=axis*10000
  route.advance([start.x,start.y,start.z]);route.advance([finish.x,finish.y,finish.z])
  expect(route.complete(),"Fast waypoint crossing is detected from every axis")
 var miss=Route.new();miss.configure([0,0,0])
 miss.advance([-10000,2300,0]);miss.advance([10000,2300,0])
 expect(not miss.complete(),"Passing outside the waypoint radius does not count")
 var ordered=Route.new();ordered.configure([10000,0,0,0,0,0])
 ordered.advance([-10000,0,0]);ordered.advance([15000,0,0])
 expect(ordered.index==1,"Crossing a later waypoint first does not reorder a route")
 ordered.advance([-5000,0,0]);expect(ordered.complete(),"Returning from the other side reaches the remaining waypoint")

func audit_story_target_counts() -> void:
 var indexed_kinds: Array=[1,8,9,12,14,17,18,19]
 for definition in data.campaign:
  var kind:=int(definition.mission.get("a:int",-1))
  if kind not in [0,1,2,3]:continue
  var referenced:=0
  for event in data.timelines.get(str(int(definition.chapter)),[]):
   if int(event.kind) in indexed_kinds:
    for value in event.values:referenced=maxi(referenced,int(value)+1)
  for rank in [0,40,200]:
   var s=Session.new();s.new_game(data,"Story target count",rank+91)
   while s.campaign.chapter<int(definition.chapter):s.campaign.next_chapter(s.counters)
   s.counters.k=rank;s.prepare_station(s.campaign.primary.destination)
   var w=World.new();w.configure(s);w.depart()
   expect(w.region.enemies.size()==maxi(1,referenced),"Targeted story mission %d preserves its %d referenced targets at rank %d"%[definition.chapter,maxi(1,referenced),rank])
   expect(w.region.success.subjects.size()==w.region.enemies.size(),"Completion tracks the actual story target set")
   var original: Array=w.region.enemies.map(func(actor):return [actor.model_id,actor.pose.origin.duplicate()])
   w.enter_region(s.station_id)
   expect(w.region.enemies.map(func(actor):return [actor.model_id,actor.pose.origin.duplicate()])==original,"Re-entering a story area recreates one deterministic target set without duplicates")
   for actor in w.region.enemies:actor.health.hull=0;actor.capturable=false
   expect(w.region.success.evaluate(w.region,0),"Resolving the advertised targets satisfies the encounter without a hidden extra enemy")
   w.dispose()
 # A generated hunt may still scale, unlike a story's specified target set.
 var contract=fixture(3);contract.enter_region(113)
 expect(contract.region.enemies.size()>=2,"Generated hunt contracts retain their squad policy")
 contract.dispose()
