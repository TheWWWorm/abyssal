extends RefCounted
## Radio conditions read from local content, evaluated against semantic state.
## Chained lines wait for acknowledgement; absent references never index arrays.
var text_id := 0
var speaker := 0
var kind := 0
var values: Array=[]
var fired := false
var eligible := false
var acknowledged := false
var previous_waypoint := 0
func configure(record: Dictionary):
 text_id=int(record.get("text_id",0));speaker=int(record.get("speaker",0));kind=int(record.get("kind",0));values=record.get("values",[]).map(func(value):return int(value));return self
func selected(group: Array) -> Array:
 var result: Array=[]
 for index in values:
  if index>=0 and index<group.size():result.append(group[index])
 return result
func poll(region) -> void:
 if fired:return
 var hostile:=selected(region.enemies);var friendly:=selected(region.friends)
 var first:=int(values[0]) if not values.is_empty() else -1
 var ready:=false
 match kind:
  0:ready=region.route.index>first
  1:ready=hostile.any(func(actor):return actor.health.hull<=0)
  2:ready=friendly.any(func(actor):return actor.health.hull<=0)
  3:ready=region.enemy_count==0
  4:ready=region.friendly_count==0
  5:ready=region.elapsed_ms>=first or region.encounter_resolved
  6:
   if first>=0 and first<region.timeline.size() and region.timeline[first]!=self:ready=region.timeline[first].acknowledged
   # Malformed/self-referencing source radio records become post-objective
   # flavour lines; they cannot deadlock the campaign.
   elif region.encounter_resolved:ready=true
  8,16:ready=(hostile if kind==8 else region.enemies).any(func(actor):return actor.health.enabled and not actor.excluded_from_objectives)
  9:ready=not hostile.is_empty() and hostile.all(func(actor):return actor.health.hull<=0)
  10:ready=friendly.any(func(actor):return actor.health.enabled)
  12:ready=hostile.any(func(actor):return actor.health.hull*2<actor.health.max_hull)
  13:ready=int(region.session.counters.get("h",0))>0
  14:ready=hostile.any(func(actor):return actor.rescued())
  15:ready=region.enemies.any(func(actor):return actor.health.hull<=0 and not actor.excluded_from_objectives)
  17:
   ready=true
   for index in region.enemies.size():
    if index!=first and region.enemies[index].health.hull>0 and not region.enemies[index].excluded_from_objectives:ready=false;break
  18:ready=hostile.any(func(actor):return not actor.capturable or actor.towing)
  19:ready=hostile.any(func(actor):return actor.health.hull*4<actor.health.max_hull*3)
 if ready:eligible=true
func evaluate(region) -> bool:
 poll(region)
 if fired or not eligible:return false
 fired=true
 return true
