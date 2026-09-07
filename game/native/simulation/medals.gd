extends RefCounted
## Monotonic achievement tiers over session metrics and imported badge metadata.
var levels: Array=[]
var pending: Array=[]
var kills:=0
var catches:=0
var pirates:=0
var weapon_count:=0
var maximum_credits:=0
var minimum_credits:=1000000
const COUNTER_BADGES: Dictionary={4:"f",5:"h",6:"m",8:"n",12:"j",13:"q",14:"o",18:"r",20:"s",21:"u",22:"t"}
func _init() -> void:
 levels.resize(24);levels.fill(0);levels[0]=1;reset_trip()
func reset_trip() -> void:
 pending.resize(24);pending.fill(0);kills=0;catches=0;pirates=0;weapon_count=0
func observe_credits(credits: int) -> void:
 maximum_credits=maxi(maximum_credits,credits);minimum_credits=mini(minimum_credits,credits)
func complete_set() -> bool:return levels.all(func(value):return value>0)
func gold_set() -> bool:return levels.all(func(value):return value==1)
func evaluate(session,hull_percent: int) -> void:
 weapon_count=session.ship.equipment.filter(func(item):return item!=null and item.kind in [0,1]).size()
 var thresholds: Array=session.data.constants.f["a:[[I"]
 for id in mini(levels.size(),thresholds.size()):
  for tier in thresholds[id].size():
   if not qualifies(id,int(thresholds[id][tier]),session,hull_percent):continue
   var candidate: int=tier+1
   if (levels[id]==0 or candidate<levels[id]) and (pending[id]==0 or candidate<pending[id]):pending[id]=candidate
   break
func qualifies(id: int,threshold: int,session,hull_percent: int) -> bool:
 if COUNTER_BADGES.has(id):
  var value:=int(session.counters.get(COUNTER_BADGES[id],0))
  return value<=threshold if id==21 else value>=threshold
 var metrics: Dictionary={1:hull_percent,9:kills,10:catches,11:session.elapsed_ms/3600000,16:weapon_count,19:maximum_credits}
 if metrics.has(id):return metrics[id]<=threshold if id==1 else metrics[id]>=threshold
 if id in [2,3]:
  var indices:=range(session.fish_found.size()).filter(func(species):return (species>=13)==(id==2))
  return not indices.is_empty() and indices.all(func(species):return session.fish_found[species])
 if id==7:
  var products: Array=session.data.tables.goods.filter(func(row):return row.size()>7 and not row[7].is_empty())
  return not products.is_empty() and products.all(func(row):return session.goods_found[int(row[0])])
 if id==15:return weapon_count==0 and kills==0
 if id==17:return session.campaign.finished()
 if id==23:return levels.slice(0,23).all(func(value):return value>0)
 return false
func commit() -> Array:
 var changed: Array=[]
 for id in levels.size():
  if pending[id]>0 and (levels[id]==0 or pending[id]<levels[id]):levels[id]=pending[id];changed.append(id)
  pending[id]=0
 if levels[23]==0 and levels.slice(0,23).all(func(value):return value>0):levels[23]=1;changed.append(23)
 return changed
func state() -> Dictionary:
 return {"levels":levels.duplicate(),"pending":pending.duplicate(),"kills":kills,"catches":catches,"pirates":pirates,"weapon_count":weapon_count,"maximum_credits":maximum_credits,"minimum_credits":minimum_credits}
func restore(value: Dictionary) -> void:
 for key in state():
  if value.has(key):set(key,value[key].map(func(tier):return int(tier)) if value[key] is Array else int(value[key]))
