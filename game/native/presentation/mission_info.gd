extends RefCounted
## Read-only objective information. Completion remains owned by Campaign/Region.
const EngineLanguage = preload("res://native/presentation/engine_language.gd")
static func progress(session, mission) -> String:
	var count := 0
	var counter: Dictionary = {21:["n",EngineLanguage.translate("Goods produced: %d / %d · %d remaining")],16:["f",EngineLanguage.translate("Enemies defeated: %d / %d · %d remaining")],15:["j",EngineLanguage.translate("Contracts completed: %d / %d · %d remaining")],18:["m",EngineLanguage.translate("Stations discovered: %d / %d · %d remaining")],19:["h",EngineLanguage.translate("Creatures caught: %d / %d · %d remaining")]}
	if counter.has(mission.kind):
		var key: Array = counter[mission.kind]
		count=int(session.counters.get(key[0],0))
		var target: int=mission.threshold
		var baseline:=0
		if mission==session.campaign.primary and mission.story and mission.kind in [15,16,18,21] and session.campaign.chapter>0:
			var definition: Dictionary=session.data.campaign[session.campaign.chapter-1].mission
			target=int(definition.get("r:int",mission.threshold));baseline=maxi(0,mission.threshold-target)
		return key[1]%[clampi(count-baseline,0,target),target,maxi(0,mission.threshold-count)]
	if mission.kind==20:
		return EngineLanguage.translate("Cargo aboard: %d / %d units")%[session.ship.cargo_used,mission.threshold]
	if mission.kind in [13,14]:
		for item in session.ship.cargo:
			if item.id==mission.item_id: count+=item.owned
		var name: String = session.text(int(session.data.constants.e["c:[[S"][mission.item_id][0]))
		return EngineLanguage.translate("%s aboard: %d / %d units")%[name,count,mission.item_count]
	if mission.kind==17:
		var name: String = session.text(int(session.data.constants.e["b:[[S"][mission.threshold][0]))
		var installed: bool = session.ship.equipment.any(func(item): return item!=null and item.id==mission.threshold)
		return (EngineLanguage.translate("%s · Installed") if installed else EngineLanguage.translate("%s · Not installed"))%name
	return ""

static func target_species(mission) -> int:
	"""The one species a creature job is about: the school to guard (6) or the
	quarry to catch (7), story chapters included. Other kinds carry none."""
	return mission.target_kind if mission.kind in [6,7] and mission.target_kind>=0 else -1

static func target(session, mission) -> String:
	var species := target_species(mission)
	var names: Array = session.data.constants.e["c:[[S"]
	if species<0 or species>=names.size(): return ""
	return (EngineLanguage.translate("Protect: %s") if mission.kind==6 else EngineLanguage.translate("Target species: %s"))%(session.text(int(names[species][0])))

static func requirements(mission) -> String:
	if mission.total<=0: return ""
	match mission.kind:
		6: return EngineLanguage.translate("Protect at least %d of %d creatures")%[mission.minimum,mission.total]
		7: return EngineLanguage.translate("Targets required: %d")%mission.total
		11: return EngineLanguage.translate("Protect at least %d of %d capsules")%[mission.minimum,mission.total]
		12: return EngineLanguage.translate("Capsules to destroy: %d")%mission.total
	return ""

static func deadline(mission) -> String:
	if mission.jump_limit<0: return ""
	if mission.jumps>mission.jump_limit: return EngineLanguage.translate("Departure limit exceeded")
	# The accepted contract starts at -1 and its first launch advances to zero.
	return EngineLanguage.translate("Departures used: %d / %d · %d remaining")%[maxi(0,mission.jumps+1),mission.jump_limit+1,maxi(0,mission.jump_limit-mission.jumps)]

static func instruction(mission) -> String:
	if mission.completed:return EngineLanguage.translate("Objective complete")
	if mission.failed:return EngineLanguage.translate("Objective failed")
	match mission.kind:
		0,3,5: return EngineLanguage.translate("Follow the mission waypoint and defeat the hostile targets.")
		1,2: return EngineLanguage.translate("Disable the designated ship, then recover it with the harpoon.")
		4: return EngineLanguage.translate("Protect the convoy and defeat its attackers.")
		7: return EngineLanguage.translate("Catch the required creatures at the mission waypoint.")
		9: return EngineLanguage.translate("Clear the debris at the mission waypoint.")
		10: return EngineLanguage.translate("Destroy the mines at the mission waypoint.")
		6: return EngineLanguage.translate("Protect the marked creatures and defeat their attackers.")
		11: return EngineLanguage.translate("Protect the supply capsules from attackers.")
		12: return EngineLanguage.translate("Destroy the marked capsules.")
		13,14: return EngineLanguage.translate("Bring the required cargo to %s and dock.")%mission.destination_name
		15: return EngineLanguage.translate("Complete station contracts. Accept them from the dock’s Contracts menu.")
		16: return EngineLanguage.translate("Find and defeat hostile ships.")
		17: return EngineLanguage.translate("Buy and install the required equipment at a station.")
		18: return EngineLanguage.translate("Visit and dock at undiscovered stations.")
		19: return EngineLanguage.translate("Catch creatures with your fishing equipment.")
		20: return EngineLanguage.translate("Collect cargo until the required amount is aboard.")
		21: return EngineLanguage.translate("Manufacture goods using cargo materials at a station.")
	if mission.has_destination():return EngineLanguage.translate("Travel to %s and dock.")%mission.destination_name
	return EngineLanguage.translate("Check the mission journal for the next task.")

static func encounter_progress(region) -> String:
	var goal=region.success
	if goal==null:return ""
	var hostile: Array=region.enemies.filter(func(actor):return not actor.excluded_from_objectives)
	match goal.metric:
		"no_enemies","enemy_dead","first_enemies_dead":
			var subjects: Array=hostile if goal.metric=="no_enemies" else region.enemies.slice(0,goal.value if goal.metric=="first_enemies_dead" else goal.value+1)
			var done: int=subjects.filter(func(actor):return actor.health.hull<=0 or actor.rescued()).size()
			return EngineLanguage.translate("Targets cleared: %d / %d")%[done,subjects.size()]
		"enemy_rescued","all_rescued":
			var subjects: Array=region.enemies if goal.metric=="all_rescued" else region.enemies.slice(goal.value,goal.value+1)
			return EngineLanguage.translate("Ships recovered: %d / %d")%[subjects.filter(func(actor):return actor.rescued()).size(),subjects.size()]
		"harvest":
			var caught: int=region.creatures.filter(func(actor):return actor.species==goal.species and (actor.subdued or actor.state==4)).size()
			return EngineLanguage.translate("Creatures caught: %d / %d")%[mini(caught,goal.minimum),goal.minimum]
		"clear_hostiles":
			var done: int=goal.subjects.filter(func(actor):return actor.health.hull<=0 or actor.rescued()).size()
			return EngineLanguage.translate("Targets cleared: %d / %d")%[done,goal.subjects.size()]
		"recover":
			return EngineLanguage.translate("Ships recovered: %d / %d")%[goal.subjects.filter(func(actor):return actor.rescued()).size(),goal.subjects.size()]
		"route":return EngineLanguage.translate("Waypoints reached: %d / %d")%[region.route.index,region.route.points.size()]
	return ""
