extends RefCounted
## The expedition (dj): the pilot, the ship and its outfit, the credits, the
## record, the chart of two hundred holdings and the story's place in it.
const Math = preload("res://native/simulation/fixed_math.gd")
const Ship = preload("res://native/simulation/ship_stats.gd")
const Equipment = preload("res://native/simulation/equipment.gd")
const Goods = preload("res://native/simulation/goods.gd")
const Random = preload("res://native/simulation/java_random.gd")
const Campaign = preload("res://native/simulation/campaign.gd")
const Economy = preload("res://native/simulation/economy.gd")
const Mission = preload("res://native/simulation/mission.gd")
const WorldLayout = preload("res://native/simulation/world_layout.gd")
var world_layout := WorldLayout.new()
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
## One-time M.A.I. guidance already shown during this expedition. This belongs
## to the checkpoint rather than the view, so restarting the game cannot make
## old tutorial messages begin again.
var hints_said: Dictionary = {}
## The last areas visited, oldest first, ending with this one: the chart
## draws them as the original's fading line of recent trips.
var trail: Array = []
const TRAIL_LENGTH := 6

func new_game(owner_data: Dictionary, player_name: String, random_seed: int) -> void:
 data=owner_data; name=player_name; credits=15000; elapsed_ms=0
 world_layout=WorldLayout.new()
 hints_said={}
 medals=preload("res://native/simulation/medals.gd").new(); pending_bounty=0
 counters={"e":0,"f":0,"g":0,"h":0,"i":0,"j":0,"k":1,"l":15,"m":0,"n":0,"o":0,"p":0,"q":0,"r":0,"s":0,"t":22500,"u":22500}
 rng.seed_from(random_seed)
 discovered.resize(200); discovered.fill(false)
 fish_found.resize(data.constants.ah["b:[S"].size()); fish_found.fill(false)
 goods_found.resize(42); goods_found.fill(false)
 stations=[]; recent_stations=[]; trail=[]
 for id in data.tables.stations.size():
  var row: Array = data.tables.stations[id]
  var percent := int(row[4])
  if percent == 0: percent=-10
  elif percent == 100: percent=115
  stations.append({"id":id,"name":row[0],"tech":int(row[1]),"x":int(row[2]),"y":int(row[3]),"percent":percent,"depth":Math.depth_from_percent(percent),"equipment":[],"cargo":[],"ships":[],"missions":[],"generated":false})
 station_id=0
 campaign=Campaign.new(); campaign.configure(data); campaign.next_chapter(counters); campaign.active=campaign.primary
 ship=Ship.new(); ship.configure(data.tables.ships[0]); ship.price=int(Math.f32(float(ship.price)/1.25))
 # The Ino is fitted out as the phone game hands it over: a Holorope, the
 # Veto shield, Ballistic armour and the Nucom radar, at Gosu's prices.
 for id in [15,18,22,35]:
  var item=make_equipment(id);item.station_price(stations[0].tech,true);item.discounted=true;ship.equip(item)
 hull=ship.hull; shield=ship.shield; armor=ship.armor

func make_equipment(id: int):
 var item := Equipment.new(); item.configure(data.tables.equipment[id]); item.quantity=1
 return item

func make_goods(id: int, count: int):
 var item := Goods.new(); item.configure(data.tables.goods[id]); item.owned=count
 return item

func is_colonist_station(id: int = -1) -> bool:
 return not campaign.rebel_stations[station_id if id < 0 else id]

func service_denial(service: String) -> int:
 # What the station will not open yet (ch.c): colonists do not trade; the
 # job board waits for the ninth chapter and the chart for the seventh;
 # and in the forty-second both wait on the Eclipse being aboard.
 if service=="trade" and is_colonist_station():return 256
 if (service=="missions" and campaign.chapter<9) or (service=="map" and campaign.chapter<7):return 282
 if service in ["missions","map"] and campaign.chapter==42 and not ship.equipment.any(func(item):return item!=null and item.id==42):return 289
 return -1

func register_catch(creature_id: int,count: int) -> bool:
 if creature_id<0 or creature_id>=data.tables.goods.size() or count<=0 or not ship.can_carry(count):return false
 ship.set_cargo(Goods.merge(ship.cargo,[make_goods(creature_id,count)]))
 if creature_id<fish_found.size():
  fish_found[creature_id]=true;counters.h+=1;medals.catches+=1
 return true

func update_rank() -> void:
 # Rank rises each time the score, of catches, kills twice, goods made and
 # contracts three times, has grown by a third since the last rise.
 var score: int=counters.h+2*counters.f+counters.n+3*counters.j
 if Math.f32(float(counters.l)*1.3)<float(score):counters.l=score;counters.k+=1

func text(id: int, replacement: String = "") -> String:
 if id < 0 or id>=data.strings.size(): return ""
 var value := str(data.strings[id])
 return value.replace("#",replacement)

func prepare_station(id: int) -> void:
 station_id=id
 if trail.is_empty() or trail.back()!=id:
  trail.append(id)
  if trail.size()>TRAIL_LENGTH:trail.pop_front()
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
 # ch.e: each medal won or bettered on the trip is announced on its own.
 for id in medals.commit():
  notices.append({"kind":"medal","id":id,"tier":int(medals.levels[id]),"text":"New medal: "+text(int(data.constants.e["a:[[S"][id][0]))})
 # The bounty on the trip's pirates grows with the square of their number,
 # a hundred a head at a colonist holding and fifty at a rebel one.
 if medals.pirates>0 and pending_bounty==0:
  var rate: int=100 if is_colonist_station() else 50
  var count: int=medals.pirates
  pending_bounty=count*count*rate
  var praise: int=284 if count<4 else 285 if count<7 else 286 if count<12 else 287
  notices.append({"kind":"pirate_bounty","text":"%s: %d\n%d x %d x %d $\n%s: %d $\n\n%s"%[text(283),count,count,count,rate,text(40),pending_bounty,text(praise)]})
 medals.observe_credits(credits)
 # Deliveries addressed here settle before the colonists take the rest.
 if is_colonist_station():
  for objective in [campaign.primary,campaign.secondary]:
   if objective.kind in [13,14] and not objective.failed and not objective.completed and objective.destination==station_id and Goods.contains(ship.cargo,objective.item_id,objective.item_count):complete_mission(objective)
  settle_colonist_cargo()
 elif campaign.chapter==12 and station_id==3:notices.append({"text":text(258),"kind":"notice"})
 station_story_stock()

func settle_colonist_cargo() -> void:
 # Colonists take whatever is in the hold at its floor price.
 if not is_colonist_station() or ship.cargo.is_empty():return
 var payment := 0
 var count := 0
 var fish := 0
 for stack in ship.cargo:
  payment+=int(Math.f32(float(stack.owned)*float(stack.minimum_price)));count+=stack.owned
  if stack.id<fish_found.size():fish+=stack.owned
 ship.set_cargo([])
 credits+=payment;medals.observe_credits(credits)
 cargo_receipt=text(257)+" %d $"%payment+"\n"+("Fish" if fish==count else "Cargo")+" · %d t"%count
 notices.append({"kind":"cargo_settlement","text":cargo_receipt})

func station_story_stock() -> void:
 # What the story puts on a shelf (ch): the Railgun alone at Gosu in the
 # second chapter; the Biotek generator and the incubator at the holdings
 # of chapters 33-34 and 36-37; and the Eclipse at Choral (14) once the
 # incubator is aboard, or in the forty-second chapter.
 var station: Dictionary=stations[station_id]
 if campaign.chapter==2:station.equipment=[make_equipment(0)]
 if campaign.chapter in [33,34,36,37] and station_id==campaign.primary.destination:
  var id: int=37 if campaign.chapter in [33,34] else 38
  if not Goods.contains(station.cargo,id):station.cargo=Goods.merge(station.cargo,[make_goods(id,1)])
 if ((campaign.chapter==41 and Goods.contains(ship.cargo,36)) or campaign.chapter==42) and station_id==14:
  var aboard: bool=ship.equipment.any(func(item):return item!=null and item.id==42)
  if not aboard and not station.equipment.any(func(item):return item.id==42):station.equipment.append(make_equipment(42))

func acknowledge_notice(notice: Dictionary) -> void:
 if notice.kind=="cargo_payment": credits+=pending_cargo_payment; pending_cargo_payment=0
 elif notice.kind=="pirate_bounty":
  credits+=pending_bounty; pending_bounty=0; medals.pirates=0
 if docked: medals.observe_credits(credits)

func depart_denial() -> int:
 # The third chapter does not leave Gosu without the Railgun, nor the
 # forty-second Choral without the Eclipse.
 if campaign.chapter==3:return 288
 if campaign.chapter==42 and not ship.equipment.any(func(item):return item!=null and item.id==42):return 289
 return -1

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
  # The incubator stays aboard at the fortieth chapter: the next one wants it at Fiir.
  if not mission.story or mission.item_id!=36 or campaign.chapter==41:
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
