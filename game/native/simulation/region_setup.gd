extends RefCounted
## Mission-kind encounter builder. No chapter cases or authored scene coordinates.
## Imported mission metadata supplies objectives; engine policies supply staging.
const NPC=preload("res://native/simulation/npc.gd")
const Special=preload("res://native/simulation/special_actor.gd")
const Creature=preload("res://native/simulation/creature.gd")
const Route=preload("res://native/simulation/route.gd")
const Goal=preload("res://native/simulation/encounter_goal.gd")
const Shape=preload("res://native/simulation/collision_shape.gd")
var r
var s
var data: Dictionary
var layout_rng := RandomNumberGenerator.new()
var staged_events: Array=[]
var center: Array=[]
var encounter_radius := 0.0
var threat := 1

func configure(region) -> void:
 r=region;s=r.session;data=s.data
 # Layout gets a separate stable stream; rendering and spawn layout cannot
 # consume combat/trading RNG or vary with frame rate and draw distance.
 layout_rng.seed=int(s.station_id)*1009+int(s.campaign.chapter)*9176+int(r.mission.kind)*3571
 staged_events=data.timelines.get(str(s.campaign.chapter),[]) if r.mission.story else []
 threat=clampi(1+int(s.counters.k)/4+maxi(0,r.mission.difficulty)/12,1,8)
 encounter_radius=maxf(62000,float(r.station.extent)+42000)
 var angle := layout_rng.randf_range(-.65,.65)
 center=[roundi(sin(angle)*encounter_radius),0,roundi(cos(angle)*encounter_radius)]

func path(points: Array, repeat_path: bool=false):
 var result:=Route.new();result.configure(points.reduce(func(flat,point):return flat+point,[]),repeat_path);return result
func position_in_formation(index: int, count: int, origin: Array, spacing: float=6500.0) -> Array:
 var columns:=maxi(1,ceili(sqrt(count)))
 var column:=index%columns;var row:=index/columns
 return [origin[0]+roundi((column-(columns-1)*.5)*spacing),origin[1]+(row%2)*900,origin[2]+roundi(row*spacing)]
func route_points() -> Array:
 var perpendicular:=Vector2(center[2],-center[0]).normalized()*12000
 return [[center[0]-roundi(perpendicular.x),0,center[2]-roundi(perpendicular.y)],center.duplicate(),[center[0]+roundi(perpendicular.x),0,center[2]+roundi(perpendicular.y)]]
func ship_id() -> int:
 var ids: Array=data.constants.ah["e:[S"]
 return int(ids[layout_rng.randi_range(0,ids.size()-1)])
func make_ship(id: int, hostile: bool, location: Array, team: int=-1):
 var actor:=NPC.new()
 actor.configure(id,(2 if hostile else 1) if team<0 else team,hostile,location,data,s.campaign.chapter,s.rng)
 actor.radius=int(data.constants.ah["c:[S"][id]) if id<20 else 2000
 var hull:=int(data.constants.ah["d:[S"][id]) if id<20 else 80
 actor.health.configure(maxi(35,hull+threat*16),0,0)
 actor.player=r.player;actor.activate()
 return actor
func ships(count: int, hostile: bool, location: Array, id: int=-1) -> Array:
 var result: Array=[]
 for index in count:
  var actor=make_ship(ship_id() if id<0 else id,hostile,position_in_formation(index,count,location))
  result.append(actor)
 if hostile:r.enemies.append_array(result)
 else:r.friends.append_array(result)
 return result
func special(kind: String, id: int, hostile: bool, location: Array):
 var actor:=Special.new();actor.configure_special(kind,id,hostile,location,data,s.rng)
 actor.player=r.player;actor.radius=1200 if kind in ["mine","debris"] else 2400
 actor.health.configure(8 if kind in ["mine","debris"] else 80+threat*30,0,0)
 if kind=="freighter":
  var shape:=Shape.new();shape.origin=location.duplicate();shape.offset=[0,0,0];shape.half_size=[3500,3500,14000];actor.shapes=[shape]
  actor.explosion_delays=[0,450,1100];actor.explosion_offsets=[[0,0,0],[0,0,5000],[0,0,-5000]];actor.explosion_duration=3600
 return actor
func fish(species: int, location: Array):
 species=clampi(species,0,data.tables.creatures.size()-1)
 var actor:=Creature.new();actor.configure(int(data.constants.ah["b:[S"][species]),data.tables.creatures[species],s.rng,r.sine,location)
 return actor
func populate_habitat() -> void:
 var habitat: Array=data.habitats[s.station_id]
 var weighted: Array=[]
 for index in range(0,habitat.size()-1,2):
  for sample in maxi(1,int(habitat[index+1])/10):weighted.append(int(habitat[index]))
 if weighted.is_empty():return
 # Two small schools outside the station footprint, with open water between.
 var player_position:=Vector3(r.player.pose.origin[0],0,r.player.pose.origin[2])
 var bearing:=atan2(player_position.x,player_position.z)
 var radius:=maxf(float(r.station.extent)+22000,player_position.length()+26000)
 for school in 2:
  var angle:=bearing+school*1.5
  var home: Array=[roundi(sin(angle)*radius),0,roundi(cos(angle)*radius)]
  var species:=int(weighted[layout_rng.randi_range(0,weighted.size()-1)])
  for index in 3:
   r.creatures.append(fish(species,position_in_formation(index,3,home,6500)))
func reference_count(kinds: Array) -> int:
 var count:=0
 for event in staged_events:
  if int(event.kind) in kinds:
   for value in event.values:count=maxi(count,int(value)+1)
 return mini(count,32)
func hostile_ship_count() -> int:
 # Targeted story encounters describe specific actors. Difficulty may improve
 # those actors, but must not silently turn one named target into a squad.
 # Radio indices are a lower bound, preserving all referenced target slots.
 var referenced:=reference_count([1,8,9,12,14,17,18,19])
 if r.mission.kind==0 or (r.mission.story and r.mission.kind in [1,2,3]):
  return maxi(1,referenced)
 # Fleet, escort and generated contract encounters retain scalable opposition.
 return maxi(threat+1,referenced)
func goal(name: String, actors: Array=[], count: int=0, species: int=-1):return Goal.new().configure(name,actors,count,species)

func populate() -> void:
 var mission=r.mission
 populate_habitat()
 if mission.kind<0 or mission.kind>=8 and mission.kind not in [9,10,11,12]:
  # Quiet station traffic; no artificial hostile encounter during tutorials.
  var traffic=ships(mini(3,s.stations[s.station_id].ships.size()),false,center)
  for actor in traffic:actor.route=path(route_points(),true)
  return
 r.route=path(route_points())
 var count:=hostile_ship_count()
 match mission.kind:
  0,1,2,3:
   ships(count,true,center)
   if mission.kind in [1,2]:
    # Recovery missions keep a designated objective ship available for towing.
    var targets: Array=r.enemies if mission.kind==1 and mission.story else [r.enemies[0]]
    for actor in targets:actor.protect(true);actor.capturable=true;actor.smart_boost=false
    r.success=goal("recover",targets);r.failure=goal("lost_target",targets)
   else:r.success=goal("clear_hostiles",r.enemies)
  4:
   ships(count,true,center)
   for index in 3:
    var freighter=special("freighter",11,false,position_in_formation(index,3,[center[0],0,center[2]-18000]))
    freighter.moving=false;r.friends.append(freighter)
   r.success=goal("clear_hostiles",r.enemies);r.failure=goal("protect",r.friends,1)
  5:
   # Use ordinary hostile ships for story fleets so all imported radio target
   # indices remain interactive. Contracts include transport targets.
   if mission.story:ships(count,true,center)
   else:
    for index in 2:r.enemies.append(special("freighter",11,true,position_in_formation(index,2,center)))
    ships(threat,true,[center[0],0,center[2]+14000])
   ships(2,false,[center[0],0,center[2]-16000])
   r.success=goal("clear_hostiles",r.enemies)
  6:
   r.creatures.clear();r.school_route=path(route_points())
   for index in maxi(1,mission.total):
    var actor=fish(mission.target_kind,position_in_formation(index,mission.total,center,2200));actor.constrained=true;r.creatures.append(actor)
   ships(count,true,[center[0],0,center[2]+26000]);ships(2,false,[center[0],0,center[2]-12000])
   r.success=goal("clear_hostiles",r.enemies);r.failure=goal("school_losses",r.creatures,maxi(1,mission.minimum))
  7:
   for index in maxi(1,mission.total)+3:r.creatures.append(fish(mission.target_kind,position_in_formation(index,mission.total+3,center,2200)))
   r.success=goal("harvest",r.creatures,maxi(1,mission.total),mission.target_kind)
  9,10:
   var hazards: Array=[]
   for index in 8+threat*2:
    var actor=special("mine" if mission.kind==10 else "debris",13 if mission.kind==10 else 9996,true,position_in_formation(index,8+threat*2,center))
    r.enemies.append(actor);hazards.append(actor)
   r.success=goal("clear_hostiles",hazards)
  11,12:
   ships(count,true,center)
   var capsules: Array=[]
   for index in maxi(1,mission.total):
    var actor=special("capsule",9994,mission.kind==12,position_in_formation(index,mission.total,center,4200))
    capsules.append(actor)
   if mission.kind==11:r.friends.append_array(capsules)
   else:r.enemies.append_array(capsules)
   r.success=goal("clear_hostiles",r.enemies)
   if mission.kind==11:r.failure=goal("rescue_losses",capsules,maxi(1,mission.minimum))
 # Radio metadata determines only required target slots, not original geometry.
 var extra_friends: int=reference_count([2,10])-r.friends.size()
 if extra_friends>0:ships(extra_friends,false,[center[0],0,center[2]-22000])
