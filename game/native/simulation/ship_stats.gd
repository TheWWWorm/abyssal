extends RefCounted
## Imported ship/equipment fields aggregated into native, bounded statistics.
const Math = preload("res://native/simulation/fixed_math.gd")
var id := 0
var hull := 0
var base_cargo := 0
var cargo_used := 0
var price := 0
var total_value := 0
var slots := 0
var base_steering := 0.0
var equipment: Array = []
var cargo: Array = []
var weapons: Array = []
var shield := 0
var armor := 0
var shield_interval := 0
var cargo_bonus := 0
var cargo_percent := 0
var passive_radar := 0
var boost_factor := 0
var boost_cooldown := 0
var boost_duration := 0
var steering_bonus := 0
var engine_bonus := 0
var weapon_power := 0
var self_repair := false
var upgraded := false
var minimum_depth := 22000
var maximum_depth := 23000
var shallow_percent := 0
var deep_percent := 0
var selected_weapon := 0

func configure(row: Array) -> void:
 id=int(row[0]); hull=int(row[1]); base_cargo=int(row[2]); price=int(row[3]); slots=int(row[4])
 base_steering=maxf(.1,float(row[5])/100.0)
 equipment.resize(slots)
 recompute()

func recompute() -> void:
 shield=0; armor=0; shield_interval=0; cargo_bonus=0; cargo_percent=0
 passive_radar=0; boost_factor=0; boost_cooldown=0; boost_duration=0
 steering_bonus=0; engine_bonus=0; weapon_power=0; self_repair=false
 minimum_depth=22000; maximum_depth=23000; total_value=price
 weapons.clear()
 for item in equipment:
  if item == null: continue
  if item.is_weapon(): weapons.append(item)
  match item.kind:
   0,1: weapon_power+=int(item.parameters[0])
   3:
    shield=int(item.parameters[0]); shield_interval=int(item.parameters[1]); minimum_depth=int(item.parameters[2])
   4:
    armor=int(item.parameters[0]); maximum_depth=int(item.parameters[1])
   5: cargo_percent+=int(item.parameters[0])
   6: engine_bonus=int(item.parameters[0])
   7: steering_bonus=int(item.parameters[0])
   8: passive_radar=int(item.parameters[0])
   9:
    boost_factor=int(item.parameters[0]); boost_duration=int(item.parameters[1]); boost_cooldown=int(item.parameters[2])
   10: self_repair=true
  total_value+=item.total_price()
 cargo_bonus=roundi(base_cargo*maxi(0,cargo_percent)/100.0)
 shallow_percent=Math.depth_percent(minimum_depth)
 deep_percent=Math.depth_percent(maximum_depth)
 total_value+=cargo_value()

func equip(item) -> void:
 if item==null or not permits_kind(item.kind):return
 var slot:=equipment.find(null)
 if slot<0:return
 equipment[slot]=item;recompute()

func remove(item) -> void:
 var slot:=equipment.find(item)
 if slot<0:return
 equipment[slot]=null;recompute()

func permits_kind(kind: int) -> bool:
 return kind in [0,5] or not equipment.any(func(item):return item!=null and item.kind==kind)

func has_slot() -> bool:return equipment.has(null)

func capacity() -> int:
 return base_cargo+cargo_bonus

func can_carry(count: int) -> bool:
 return count>=0 and cargo_used+count <= capacity()

func engine_range() -> int:
 return roundi(275.0*(1+maxi(0,engine_bonus)/100.0))

func steering() -> float:
 return maxf(.1,base_steering+steering_bonus/100.0)

func cargo_value() -> int:
 var result := 0
 for item in cargo: result+=item.total_price()
 return result

func set_cargo(items: Array) -> void:
 cargo=items
 cargo_used=0
 for item in cargo: cargo_used+=item.owned
 recompute()

func values() -> Array:
 return [shield,armor,shield_interval,cargo_bonus,cargo_percent,passive_radar,boost_factor,boost_cooldown,boost_duration,steering_bonus,engine_bonus,weapon_power,self_repair,minimum_depth,maximum_depth,shallow_percent,deep_percent,total_value,capacity(),engine_range(),weapons.size()]
