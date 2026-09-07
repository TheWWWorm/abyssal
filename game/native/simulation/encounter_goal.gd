extends RefCounted
## Named, composable goals. Scene generation decides the actor roles once.
var metric := "clear_hostiles"
var subjects: Array=[]
var minimum := 0
var species := -1
var remaining := 0
func configure(name: String, actors: Array=[], count: int=0, target_species: int=-1):
 metric=name;subjects=actors;minimum=count;species=target_species;remaining=count
 return self
func evaluate(region, _elapsed_ms: int) -> bool:
 match metric:
  "clear_hostiles":return subjects.all(func(actor):return actor.health.hull<=0 or actor.rescued())
  "recover":return not subjects.is_empty() and subjects.all(func(actor):return actor.rescued())
  "lost_target":return subjects.any(func(actor):return actor.escaped)
  "protect":return subjects.filter(func(actor):return actor.health.hull>0).size()<minimum
  "school_losses":return subjects.filter(func(actor):return actor.state!=4).size()<minimum
  "rescue_losses":return region.special_destroyed>subjects.size()-minimum
  "harvest":
   var caught := subjects.filter(func(actor):return actor.species==species and (actor.subdued or actor.state==4)).size()
   remaining=maxi(0,minimum-caught);return remaining==0
  "route":return region.route.complete()
 return false
