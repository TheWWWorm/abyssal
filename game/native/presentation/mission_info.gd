extends RefCounted
## Read-only objective information. Completion remains owned by Campaign/Region.
static func progress(session, mission) -> String:
	var count := 0
	var counter: Dictionary = {21:["n","Goods produced"],16:["f","Enemies defeated"],15:["j","Contracts completed"],18:["m","Stations discovered"],19:["h","Creatures caught"]}
	if counter.has(mission.kind):
		var key: Array = counter[mission.kind]
		count=int(session.counters.get(key[0],0))
		var target: int=mission.threshold
		var baseline:=0
		if mission==session.campaign.primary and mission.story and mission.kind in [15,16,18,21] and session.campaign.chapter>0:
			var definition: Dictionary=session.data.campaign[session.campaign.chapter-1].mission
			target=int(definition.get("r:int",mission.threshold));baseline=maxi(0,mission.threshold-target)
		return "%s: %d / %d · %d remaining"%[key[1],clampi(count-baseline,0,target),target,maxi(0,mission.threshold-count)]
	if mission.kind==20:
		return "Cargo aboard: %d / %d units"%[session.ship.cargo_used,mission.threshold]
	if mission.kind in [13,14]:
		for item in session.ship.cargo:
			if item.id==mission.item_id: count+=item.owned
		var name: String = session.text(int(session.data.constants.e["c:[[S"][mission.item_id][0]))
		return "%s aboard: %d / %d units"%[name,count,mission.item_count]
	if mission.kind==17:
		var name: String = session.text(int(session.data.constants.e["b:[[S"][mission.threshold][0]))
		var installed: bool = session.ship.equipment.any(func(item): return item!=null and item.id==mission.threshold)
		return "%s · %s"%[name,"Installed" if installed else "Not installed"]
	return ""

static func requirements(mission) -> String:
	if mission.total<=0: return ""
	match mission.kind:
		6: return "Protect at least %d of %d creatures"%[mission.minimum,mission.total]
		7: return "Targets required: %d"%mission.total
		11: return "Protect at least %d of %d capsules"%[mission.minimum,mission.total]
		12: return "Capsules to destroy: %d"%mission.total
	return ""

static func deadline(mission) -> String:
	if mission.jump_limit<0: return ""
	if mission.jumps>mission.jump_limit: return "Departure limit exceeded"
	# The accepted contract starts at -1 and its first launch advances to zero.
	return "Departures used: %d / %d · %d remaining"%[maxi(0,mission.jumps+1),mission.jump_limit+1,maxi(0,mission.jump_limit-mission.jumps)]

static func instruction(mission) -> String:
	if mission.completed:return "Objective complete"
	if mission.failed:return "Objective failed"
	match mission.kind:
		0,3,5: return "Follow the mission waypoint and defeat the hostile targets."
		1,2: return "Disable the designated ship, then recover it with the harpoon."
		4: return "Protect the convoy and defeat its attackers."
		7: return "Catch the required creatures at the mission waypoint."
		9: return "Clear the debris at the mission waypoint."
		10: return "Destroy the mines at the mission waypoint."
		6: return "Protect the marked creatures and defeat their attackers."
		11: return "Protect the rescue capsules from attackers."
		12: return "Destroy the marked capsules."
		13,14: return "Bring the required cargo to "+mission.destination_name+" and dock."
		15: return "Complete station contracts. Accept them from the dock’s Contracts menu."
		16: return "Find and defeat hostile ships."
		17: return "Buy and install the required equipment at a station."
		18: return "Visit and dock at undiscovered stations."
		19: return "Catch creatures with your fishing equipment."
		20: return "Collect cargo until the required amount is aboard."
		21: return "Manufacture goods using cargo materials at a station."
	if mission.destination>=0:return "Travel to "+mission.destination_name+" and dock."
	return "Check the mission journal for the next task."

static func encounter_progress(region) -> String:
	var goal=region.success
	if goal==null:return ""
	match goal.metric:
		"clear_hostiles":
			var done: int=goal.subjects.filter(func(actor):return actor.health.hull<=0 or actor.rescued()).size()
			return "Targets cleared: %d / %d"%[done,goal.subjects.size()]
		"recover":
			return "Ships recovered: %d / %d"%[goal.subjects.filter(func(actor):return actor.rescued()).size(),goal.subjects.size()]
		"harvest":
			var caught: int=goal.subjects.filter(func(actor):return actor.species==goal.species and (actor.subdued or actor.state==4)).size()
			return "Creatures caught: %d / %d"%[mini(caught,goal.minimum),goal.minimum]
		"route":return "Waypoints reached: %d / %d"%[region.route.index,region.route.points.size()]
	return ""
