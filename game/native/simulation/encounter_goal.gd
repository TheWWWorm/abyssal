extends RefCounted
## What an encounter asks, as the phone game's dh puts it: a named test on
## the region, with an index, a count or a species where the test needs one.
var metric := "no_enemies"
var subjects: Array=[]
var minimum := 0
var species := -1
var remaining := 0
var value := 0
func configure(name: String,actors: Array=[],count: int=0,target_species: int=-1):
	metric=name;subjects=actors;minimum=count;species=target_species;remaining=count;value=count
	return self
func dead(actor) -> bool:return actor.state==4
func evaluate(region,elapsed_ms: int) -> bool:
	match metric:
		"no_enemies":return region.enemy_count==0
		"no_friends":return region.friendly_count==0
		"enemy_dead":return value<region.enemies.size() and dead(region.enemies[value])
		"friend_dead":return value<region.friends.size() and dead(region.friends[value])
		"route":return region.route.complete()
		"elapsed":return elapsed_ms>value
		"radio":return value<region.timeline.size() and region.timeline[value].fired
		"first_enemies_dead":
			# The first so many of the hostile list, mines and debris among
			# them, all gone.
			var count := 0
			for index in mini(value,region.enemies.size()):
				if dead(region.enemies[index]):count+=1
			return count==value
		"school_losses":return region.creatures.filter(dead).size()>value
		"enemy_rescued":return value<region.enemies.size() and region.enemies[value].rescued()
		"enemy_escaped":return value<region.enemies.size() and region.enemies[value].escaped
		"harvest":
			var caught := 0
			for actor in region.creatures:
				if actor.species==species and (dead(actor) or actor.subdued):caught+=1
			remaining=maxi(0,minimum-caught);return caught>=minimum
		"capsules_destroyed":return region.special_destroyed>=value
		"all_rescued":return region.enemies.all(func(actor):return actor.rescued())
		"any_escaped":return region.enemies.any(func(actor):return actor.escaped)
		# Kept for callers that name their own subjects.
		"clear_hostiles":return subjects.all(func(actor):return actor.health.hull<=0 or actor.rescued())
		"recover":return not subjects.is_empty() and subjects.all(func(actor):return actor.rescued())
		"lost_target":return subjects.any(func(actor):return actor.escaped)
		"protect":return subjects.filter(func(actor):return actor.health.hull>0).size()<minimum
		"rescue_losses":return region.special_destroyed>subjects.size()-minimum
	return false
