extends RefCounted
## Finite market selection, explicit player transactions and atomic crafting.
const Goods=preload("res://native/simulation/goods.gd")
const Ship=preload("res://native/simulation/ship_stats.gd")
const Contracts=preload("res://native/simulation/contracts.gd")
var session
func configure(owner_session) -> void:session=owner_session
func ship_price(vessel) -> int:return maxi(0,vessel.price)
static func distance_xy(a: Dictionary,b: Dictionary) -> int:return roundi(Vector2(a.x-b.x,a.y-b.y).length())
static func distance(a: Dictionary,b: Dictionary) -> float:return Vector3(a.x-b.x,a.y-b.y,(a.percent-b.percent)*.1).length()*20.0
func choose(candidates: Array,count: int) -> Array:
 var pool:=candidates.duplicate();var result: Array=[]
 for index in mini(count,pool.size()):result.append(pool.pop_at(session.rng.next_int(pool.size())))
 return result
func generate(station: Dictionary) -> void:
 station.cargo=generate_goods(station);station.equipment=generate_equipment(station);station.ships=generate_ships(station)
 var board:=Contracts.new();board.session=session;station.missions=board.generate(station);station.generated=true
func generate_goods(station: Dictionary) -> Array:
 var candidates: Array=[]
 for row in session.data.tables.goods:
  if int(row[1])<=station.tech and int(row[4])>0:candidates.append(int(row[0]))
 var result: Array=[]
 for id in choose(candidates,6):result.append(session.make_goods(id,4+session.rng.next_int(9)))
 return result
func generate_equipment(station: Dictionary) -> Array:
 var candidates: Array=[]
 for row in session.data.tables.equipment:
  if int(row[2])>0:candidates.append(int(row[0]))
 var result: Array=[]
 for id in choose(candidates,clampi(4+station.tech/2,4,10)):
  var item=session.make_equipment(id);item.station_price(station.tech);result.append(item)
 return result
func generate_ships(station: Dictionary) -> Array:
 var result: Array=[]
 var available:=range(session.data.tables.ships.size())
 for id in choose(available,3):
  var ship:=Ship.new();ship.configure(session.data.tables.ships[id]);ship.price=roundi(ship.price*(1-clampf(station.tech,0,10)*.015));ship.recompute();result.append(ship)
 return result
func restock(station: Dictionary) -> void:
 for item in station.cargo:item.owned=mini(20,item.owned+1+session.rng.next_int(3))
 if station.cargo.is_empty():station.cargo=generate_goods(station)
func price_goods(station: Dictionary) -> void:
 for inventory in [session.ship.cargo,station.cargo]:
  for item in inventory:
   var home: Dictionary=session.stations[clampi(item.origin_station,0,session.stations.size()-1)]
   var destination: Dictionary=session.stations[clampi(item.destination_station,0,session.stations.size()-1)]
   var journey:=maxi(1,distance_xy(home,destination))
   var proportion:=clampf(float(distance_xy(home,station))/journey,0,1)
   item.price=maxi(1,roundi(lerpf(item.minimum_price,item.maximum_price,proportion)))
func market(station: Dictionary) -> Array:
 price_goods(station);return Goods.market_rows(session.ship.cargo,station.cargo)
func trade(station: Dictionary,id: int,buying: bool) -> bool:
 var rows:=market(station)
 for item in rows:
  if item.id!=id:continue
  var payment: int=item.transact(buying,session.credits,session.ship.cargo_used,session.ship.capacity())
  if payment==0:return false
  session.credits+=payment;session.ship.set_cargo(Goods.owned_items(rows));station.cargo=Goods.owned_items(rows,true)
  session.medals.observe_credits(session.credits);return true
 return false
func has_equipment(id: int) -> bool:return session.ship.equipment.any(func(item):return item!=null and item.id==id)
func buy_equipment(station: Dictionary,item) -> int:
 if item not in station.equipment or not session.ship.permits_kind(item.kind):return 144
 if item.price<0 or item.price>session.credits:return 85
 if not session.ship.has_slot():return 145
 var installed=item.copy_stack();installed.station_price(station.tech,true);installed.discounted=true
 session.ship.equip(installed);session.credits-=item.price;station.equipment.erase(item)
 session.counters.s+=1;session.medals.observe_credits(session.credits);return -1
func sell_equipment(station: Dictionary,item) -> int:
 if item not in session.ship.equipment:return 144
 var preview:=Ship.new();preview.configure(session.data.tables.ships[session.ship.id]);preview.equipment=session.ship.equipment.duplicate()
 preview.remove(item)
 if preview.capacity()<session.ship.cargo_used:return 88
 var sale=item.copy_stack();sale.station_price(station.tech,true);sale.discounted=true
 session.ship.remove(item);session.credits+=sale.price;station.equipment.append(sale)
 session.medals.observe_credits(session.credits);return -1
func buy_ship(station: Dictionary,offered) -> int:
 if offered not in station.ships:return 85
 var old=session.ship;var installed: Array=old.equipment.filter(func(item):return item!=null)
 if offered.slots<installed.size():return 86
 var purchased:=Ship.new();purchased.configure(session.data.tables.ships[offered.id])
 purchased.upgraded=offered.upgraded
 for item in installed:
  if not purchased.permits_kind(item.kind):return 144
  purchased.equip(item)
 if purchased.capacity()<old.cargo_used:return 87
 var trade_in:=roundi(old.price*.65)
 if offered.price<0 or session.credits+trade_in<offered.price:return 85
 purchased.price=offered.price;purchased.set_cargo(old.cargo)
 var sold:=Ship.new();sold.configure(session.data.tables.ships[old.id]);sold.price=maxi(1,roundi(old.price*.8));sold.upgraded=old.upgraded
 var index: int=station.ships.find(offered)
 session.credits+=trade_in-offered.price;session.ship=purchased;station.ships[index]=sold
 session.medals.observe_credits(session.credits);return -1
func recipes(station: Dictionary) -> Array:
 var owned: Dictionary={}
 for item in session.ship.cargo:owned[item.id]=int(owned.get(item.id,0))+item.owned
 var result: Array=[]
 for row in session.data.tables.goods:
  var recipe=session.make_goods(int(row[0]),0)
  if recipe.ingredients.is_empty() or recipe.ingredients.size()!=recipe.ingredient_counts.size() or recipe.tech_level>station.tech:continue
  var batches:=100000;var consumed:=0
  for index in recipe.ingredients.size():
   var cost:=int(recipe.ingredient_counts[index]);consumed+=cost
   if cost<=0:batches=0;break
   var available:=int(owned.get(recipe.ingredients[index],0))
   if available<cost:recipe.missing_ingredients+=1
   batches=mini(batches,available/cost)
  if consumed<1:batches=0
  recipe.owned=maxi(0,batches);result.append(recipe)
 return result
func manufacture(station: Dictionary,id: int,count: int) -> bool:
 if count<=0:return false
 for recipe in recipes(station):
  if recipe.id!=id or recipe.owned<count:continue
  var inventory: Array=session.ship.cargo.map(func(item):return item.copy_stack(item.owned))
  var result: Array=Goods.owned_items(recipe.manufacture(inventory,count))
  var used:=0
  for item in result:used+=item.owned
  if used>session.ship.capacity():return false
  session.ship.set_cargo(result);session.counters.n+=count;session.goods_found[id]=true;price_goods(station);return true
 return false
