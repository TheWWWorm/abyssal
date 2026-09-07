extends RefCounted
## Engine session, starter equipment, persistent milestones and settlement.
const Math = preload("res://native/simulation/fixed_math.gd")
const Ship = preload("res://native/simulation/ship_stats.gd")
const Equipment = preload("res://native/simulation/equipment.gd")
const Goods = preload("res://native/simulation/goods.gd")
const Random = preload("res://native/simulation/java_random.gd")
const Campaign = preload("res://native/simulation/campaign.gd")
const Economy = preload("res://native/simulation/economy.gd")
const Mission = preload("res://native/simulation/mission.gd")
var data: Dictionary = {}
var face_layers: Array = [85,65,75,16,43,-1]
var name := "Player"
var credits := 15000
var elapsed_ms := 0
var counters: Dictionary = {}
var medals := preload("res://native/simulation/medals.gd").new()
var pending_bounty := 0
var discovered: Array = []
var fish_found: Array = []
var goods_found: Array = []
var station_id := 0
var stations: Array = []
var recent_stations: Array = []
var ship := Ship.new()
var campaign := Campaign.new()
var rng := Random.new()
var hull := 0
var shield := 0
var armor := 0
var docked := false
var entered_gate := false
var last_arrival_ms := 0
var pending_cargo_payment := 0
var notices: Array = []
var cargo_receipt := ""

func new_game(owner_data: Dictionary, player_name: String, random_seed: int) -> void:
 data=owner_data; name=player_name; credits=15000; elapsed_ms=0
 medals=preload("res://native/simulation/medals.gd").new(); pending_bounty=0
 counters={"e":0,"f":0,"g":0,"h":0,"i":0,"j":0,"k":1,"l":15,"m":0,"n":0,"o":0,"p":0,"q":0,"r":0,"s":0,"t":22500,"u":22500}
 rng.seed_from(random_seed)
 discovered.resize(200); discovered.fill(false)
 fish_found.resize(data.constants.ah["b:[S"].size()); fish_found.fill(false)
 goods_found.resize(42); goods_found.fill(false)
 stations=[]; recent_stations=[]
 for id in data.tables.stations.size():
  var row: Array = data.tables.stations[id]
  var percent := int(row[4])
  if percent == 0: percent=-10
  elif percent == 100: percent=115
  stations.append({"id":id,"name":row[0],"tech":int(row[1]),"x":int(row[2]),"y":int(row[3]),"percent":percent,"depth":Math.depth_from_percent(percent),"equipment":[],"cargo":[],"ships":[],"missions":[],"generated":false})
 station_id=0
 campaign=Campaign.new(); campaign.configure(data); campaign.next_chapter(counters); campaign.active=campaign.primary
 ship=Ship.new(); ship.configure(data.tables.ships[0]); ship.price=int(Math.f32(float(ship.price)/1.25))
 # Starter gear is selected by category and price from the imported catalog.
 for kind in [2,3,4,8]:
  var candidates: Array=data.tables.equipment.filter(func(row):return int(row[1])==kind)
  candidates.sort_custom(func(a,b):return int(a[3])<int(b[3]))
  if candidates.is_empty():continue
  var item=make_equipment(int(candidates[0][0]));item.station_price(stations[0].tech,true);item.discounted=true;ship.equip(item)
 hull=ship.hull; shield=ship.shield; armor=ship.armor

func make_equipment(id: int):
 var item := Equipment.new(); item.configure(data.tables.equipment[id]); item.quantity=1
 return item

func make_goods(id: int, count: int):
 var item := Goods.new(); item.configure(data.tables.goods[id]); item.owned=count
 return item

func is_colonist_station(id: int = -1) -> bool:
 return not campaign.rebel_stations[station_id if id < 0 else id]

func service_denial(_service: String) -> int:
 return -1 # Core station tools stay accessible throughout the campaign.

func register_catch(creature_id: int,count: int) -> bool:
 if creature_id<0 or creature_id>=data.tables.goods.size() or count<=0 or not ship.can_carry(count):return false
 ship.set_cargo(Goods.merge(ship.cargo,[make_goods(creature_id,count)]))
 if creature_id<fish_found.size():
  fish_found[creature_id]=true;counters.h+=1;medals.catches+=1
 return true

func update_rank() -> void:
 var milestones:=maxi(0,int(counters.h)+int(counters.f)*2+int(counters.n)+int(counters.j)*4)
 counters.k=maxi(int(counters.k),1+floori(sqrt(milestones/8.0)))
 counters.l=maxi(int(counters.l),milestones)

func text(id: int, replacement: String = "") -> String:
 if id < 0 or id>=data.strings.size(): return ""
 var value := str(data.strings[id])
 return value.replace("#",replacement)

func prepare_station(id: int) -> void:
 station_id=id
 var station: Dictionary = stations[id]
 var economy := Economy.new(); economy.configure(self)
 if not id in recent_stations:
  economy.generate(station)
  if recent_stations.size()<3: recent_stations.push_front(id)
  else:
   var old: int = recent_stations.pop_back()
   stations[old].generated=false; stations[old].equipment=[]; stations[old].cargo=[]; stations[old].ships=[]; stations[old].missions=[]
   recent_stations.push_front(id)
 campaign.select_at_station(id)

func arrive() -> void:
 cargo_receipt=""
 prepare_station(station_id)
 var station: Dictionary = stations[station_id]
 var economy := Economy.new(); economy.configure(self)
 if elapsed_ms-last_arrival_ms>30000: economy.restock(station)
 last_arrival_ms=elapsed_ms
 if not discovered[station_id]: discovered[station_id]=true; counters.m+=1
 docked=true
 var awarded: Array = medals.commit()
 if not awarded.is_empty():
  var names: Array = awarded.map(func(id): return text(int(data.constants.e["a:[[S"][id][0])))
  notices.append({"kind":"notice","text":"Medals awarded: "+", ".join(names)})
 if medals.pirates>0 and pending_bounty==0:
  pending_bounty=medals.pirates*250
  notices.append({"kind":"pirate_bounty","text":"Pirate bounty · %d defeated · %d cr"%[medals.pirates,pending_bounty]})
 medals.observe_credits(credits)
 # Complete deliveries addressed here before the port settles the remainder.
 if is_colonist_station():
  for objective in [campaign.primary,campaign.secondary]:
   if objective.kind in [13,14] and not objective.failed and not objective.completed and objective.destination==station_id and Goods.contains(ship.cargo,objective.item_id,objective.item_count):complete_mission(objective)
  settle_colonist_cargo()
 station_story_stock()

func settle_colonist_cargo() -> void:
 if not is_colonist_station() or ship.cargo.is_empty():return
 var payment := 0
 var count := 0
 var fish := 0
 for stack in ship.cargo:
  # Fixed catalog valuation, independent of market prices last seen by the UI.
  var catalog_item=make_goods(stack.id,stack.owned)
  payment+=catalog_item.total_price();count+=stack.owned
  if stack.id<fish_found.size():fish+=stack.owned
 ship.set_cargo([])
 credits+=payment;medals.observe_credits(credits)
 cargo_receipt=("Fish automatically sold" if fish==count else "Cargo automatically sold")+" · %d t · +%d cr"%[count,payment]
 notices.append({"kind":"cargo_settlement","text":cargo_receipt})

func station_story_stock() -> void:
 # Imported objectives guarantee the availability of required equipment.
 # Delivery supplies are offered away from the receiving station, so cargo
 # still needs to be transported rather than collected at the destination.
 var station: Dictionary=stations[station_id]
 var objectives: Array=[campaign.primary]
 if campaign.chapter<data.campaign.size():
  var upcoming:=Mission.new();upcoming.from_record(data.campaign[campaign.chapter].mission);objectives.append(upcoming)
 for objective in objectives:
  if objective.kind==17 and objective.threshold>=0 and objective.threshold<data.tables.equipment.size():
   if not station.equipment.any(func(item):return item.id==objective.threshold):station.equipment.append(make_equipment(objective.threshold))
  if objective.kind in [13,14] and objective.destination!=station_id and objective.item_id>=0 and objective.item_id<data.tables.goods.size():
   if not Goods.contains(station.cargo,objective.item_id):station.cargo=Goods.merge(station.cargo,[make_goods(objective.item_id,maxi(1,objective.item_count))])

func acknowledge_notice(notice: Dictionary) -> void:
 if notice.kind=="cargo_payment": credits+=pending_cargo_payment; pending_cargo_payment=0
 elif notice.kind=="pirate_bounty":
  credits+=pending_bounty; pending_bounty=0; medals.pirates=0
 if docked: medals.observe_credits(credits)

func depart_denial() -> int:
 return -1 # Equipment advice belongs in the journal, not a hidden chapter lock.

func depart() -> bool:
 if depart_denial()>=0: return false
 credits+=pending_cargo_payment; pending_cargo_payment=0
 credits+=pending_bounty; pending_bounty=0
 medals.observe_credits(credits); medals.reset_trip()
 campaign.secondary.count_jump()
 prepare_station(station_id)
 docked=false; entered_gate=false
 # Station departure begins with repaired defenses.
 hull=ship.hull; shield=ship.shield; armor=ship.armor
 return true

func accept_contract(mission) -> bool:
 if mission.deposit>credits or not mission in stations[station_id].missions: return false
 campaign.secondary=mission; credits-=mission.deposit
 stations[station_id].missions.erase(mission)
 return true

func abandon_contract() -> void:
 if campaign.active==campaign.secondary: campaign.active=Mission.new()
 campaign.secondary=Mission.new()

func complete_mission(mission) -> void:
 # Completion dialogues can outlive their mission object. Only the current
 # owned objectives may settle, and failed contracts never pay success rewards.
 if mission==null or mission.kind<0 or mission.failed or mission not in [campaign.primary,campaign.secondary]: return
 if mission.kind in [13,14]:
  if not docked or station_id!=mission.destination or not Goods.contains(ship.cargo,mission.item_id,mission.item_count):return
  for item in ship.cargo:
   if item.id==mission.item_id: item.owned-=mission.item_count
  ship.set_cargo(Goods.owned_items(ship.cargo))
 credits+=mission.reward
 if mission.story: campaign.next_chapter(counters)
 else: counters.j+=1; campaign.secondary=Mission.new()
 if campaign.active==mission: campaign.active=Mission.new()
 if docked: station_story_stock()

func title(mission) -> String:
 var key := "g:[S" if mission.story else "i:[S"
 var index: int = campaign.chapter if mission.story else mission.kind
 if index < 0 or index>=data.constants.e[key].size(): return ""
 return text(int(data.constants.e[key][index]),mission.destination_name)

func description(mission) -> String:
 var key := "h:[S" if mission.story else "j:[S"
 var index: int = campaign.chapter if mission.story else mission.kind
 if index < 0 or index>=data.constants.e[key].size(): return ""
 return text(int(data.constants.e[key][index]),str(mission.percentage) if mission.kind==6 else mission.destination_name)

func dialogue(mission, phase: int) -> Array:
 if mission.story:
  if phase==2:
   var failures: Array = data.constants.e["o:[S"]
   return [{"speaker":"M.A.I.","portrait":[-1],"text":text(int(failures[rng.next_int(failures.size())]),name)+"\n\n"+text(139)}]
  var result: Array = []
  for line in campaign.dialogue(mission,phase):
   var speaker: String = name if line.speaker==0 else str(data.constants.ah["a:[Ljava.lang.String;"][line.speaker])
   if speaker in ["Colonist","Rebel","Pirate"]: speaker=text({"Colonist":238,"Rebel":239,"Pirate":240}[speaker])
   result.append({"speaker":speaker,"text":text(line.text_id,name),"portrait":data.constants.ah["a:[[B"][line.speaker] if line.speaker>0 else []})
  return result
 var key := "l:[S" if phase==0 else ("m:[S" if phase==1 else "n:[S")
 var choices: Array = data.constants.e[key]
 var ending := text(int(choices[rng.next_int(choices.size())]),name)
 var message := text(int(data.constants.e["k:[S"][mission.kind]),name)+"\n\n"+ending if phase==0 else ending+"\n\n"+text(92 if phase==1 else 228)
 return [{"speaker":mission.sponsor,"text":message,"portrait":mission.portrait}]
