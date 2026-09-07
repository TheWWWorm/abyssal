extends RefCounted
## Bounded contract offers based on reachability, cargo capacity and player rank.
## Imported tables supply names/art/content; engine policy supplies each offer.
const Mission=preload("res://native/simulation/mission.gd")
var session
func roll(bound: int) -> int:return session.rng.next_int(maxi(1,bound))
func nearby_stations(station: Dictionary) -> Array:
 var candidates: Array=[]
 for target in session.stations:
  if target.id==station.id:continue
  if target.percent<session.ship.shallow_percent or target.percent>session.ship.deep_percent:continue
  candidates.append(target)
 candidates.sort_custom(func(a,b):return distance(station,a)<distance(station,b))
 return candidates.slice(0,12)
func distance(a: Dictionary,b: Dictionary) -> float:
 return Vector3(a.x-b.x,a.y-b.y,(a.percent-b.percent)*.1).length()
func destination(station: Dictionary) -> int:
 var candidates:=nearby_stations(station)
 return station.id if candidates.is_empty() else int(candidates[roll(candidates.size())].id)
func portrait(variant: bool,faction: int) -> Array:
 # The layer/category schema is part of the imported portrait format.
 var art: Dictionary=session.data.constants.ab
 var category:=roll(2) if variant else 2
 var result: Array=[]
 for layer in art["a:[[[B"].size():
  if layer==0:result.append(int(art["f:[B"][faction]));continue
  var source_layer: int=3-layer if not variant and layer in [1,2] else layer
  var options: Array=art["a:[[[B"][source_layer][category]
  result.append(-1 if options.is_empty() else int(options[roll(options.size())]))
 return result
func cargo_candidates(fish: bool) -> Array:
 var candidates: Array=[]
 var species_count: int=session.data.constants.ah["b:[S"].size()
 for id in session.data.tables.goods.size():
  var row: Array=session.data.tables.goods[id]
  if int(row[4])>0 and (id<species_count)==fish:candidates.append(id)
 return candidates
func generate(station: Dictionary) -> Array:
 var result: Array=[]
 var remote:=nearby_stations(station)
 var types: Array=[0,1,2,3,4,5,6,7,9,11,12]
 if not remote.is_empty():types.append_array([8,10])
 var cargo:=cargo_candidates(false);var fish:=cargo_candidates(true)
 if session.ship.capacity()>0:
  if not cargo.is_empty():types.append(13)
  if not fish.is_empty():types.append(14)
 var rank:=clampi(int(session.counters.k),1,40)
 var combat_tier:=clampi(1+rank/5,1,8)
 for index in 4:
  var mission:=Mission.new();mission.kind=int(types[roll(types.size())])
  var target: Dictionary=station
  if mission.kind in [8,10] or not remote.is_empty() and mission.kind not in [13,14] and roll(2)==0:
   target=remote[roll(remote.size())]
  mission.destination=target.id;mission.destination_name=target.name
  mission.sponsor_faction=0 if session.is_colonist_station(station.id) else 1
  var variant:=roll(2)==0
  var names: Array=session.data.name_pools[1 if variant else 0]
  mission.sponsor="Contract office" if names.is_empty() else str(names[roll(names.size())])
  mission.portrait=portrait(variant,mission.sponsor_faction)
  mission.difficulty=combat_tier*clampi(rank/2,1,20)
  # No random jump expiry: players may explore or stop for upgrades en route.
  mission.jump_limit=-1
  if mission.kind in [13,14]:
   var goods: Array=cargo if mission.kind==13 else fish
   mission.item_id=int(goods[roll(goods.size())])
   mission.item_count=1+roll(mini(12,maxi(1,session.ship.capacity()/2)))
  if mission.kind in [6,7]:
   var total:=4+combat_tier if mission.kind==7 else 8+combat_tier
   mission.parameters(roll(mini(13,session.data.tables.creatures.size())),total,maxi(1,ceili(total*.6)) if mission.kind==6 else 0)
  elif mission.kind in [11,12]:
   var total:=4+combat_tier/2;mission.parameters(0,total,maxi(1,ceili(total*.6)) if mission.kind==11 else total)
  var reward:=1500.0+combat_tier*450+distance(station,target)*40
  if mission.kind in [4,6,11]:reward*=1.25
  if mission.kind in [13,14]:reward+=mission.item_count*int(session.data.tables.goods[mission.item_id][6])*1.3
  mission.reward=maxi(500,roundi(reward/50.0)*50)
  mission.deposit=mini(roundi(mission.reward*.1/50.0)*50,maxi(0,session.credits/10))
  result.append(mission)
 return result
