extends RefCounted
## Data-driven chapter progression and persistent player milestones.
const Mission = preload("res://native/simulation/mission.gd")
const Goods = preload("res://native/simulation/goods.gd")
var data: Dictionary = {}
var chapter := 0
var primary := Mission.new()
var secondary := Mission.new()
var active := Mission.new()
var rebel_stations: Array = []

func configure(owner_data: Dictionary) -> void:
	data=owner_data
	rebel_stations.resize(200); rebel_stations.fill(false)

func next_chapter(counters: Dictionary) -> void:
	chapter+=1
	if chapter > data.campaign.size(): return
	var definition: Dictionary = data.campaign[chapter-1]
	primary=Mission.new()
	primary.from_record(definition.mission)
	var relative_counters := {15:"j",21:"n",18:"m",16:"f"}
	if relative_counters.has(primary.kind):
		primary.threshold+=int(counters.get(relative_counters[primary.kind],0))
		if primary.kind==18:primary.threshold=mini(primary.threshold,data.tables.stations.size())
	for id in definition.rebel_stations: rebel_stations[int(id)]=true

func completion(docked: bool, elapsed_ms: int, station_id: int, ship, counters: Dictionary):
	# Resolve story first when two objectives finish on the same tick.
	for mission in [primary,secondary]:
		if mission.completed or mission.failed: continue
		match mission.kind:
			22:
				if not docked and elapsed_ms > 10000: return mission
			13,14:
				if docked and station_id == mission.destination and Goods.contains(ship.cargo,mission.item_id,mission.item_count): return mission
			8:
				if docked and station_id == mission.destination: return mission
			17:
				for item in ship.equipment:
					if item != null and item.id == mission.threshold: return mission
			21,16,15,18,19,20:
				var count: int = ship.cargo_used if mission.kind == 20 else int(counters.get({21:"n",16:"f",15:"j",18:"m",19:"h"}[mission.kind],0))
				if count >= mission.threshold:
					mission.completed=true
					return mission
	return null

func select_at_station(station_id: int, show_briefing: bool = true) -> void:
	active=Mission.new()
	for mission in [primary,secondary]:
		if mission.failed or mission.completed or mission.kind < 0 or mission.destination != station_id or mission.kind in [13,14,21,18,16,15]: continue
		if (mission.jumps > mission.jump_limit and mission.jump_limit >= 0) or (not mission.story and mission.kind == 8): continue
		if show_briefing and mission.story and mission.kind in [0,1,2,3,4,5,6,7,9,10,11,12]: mission.briefing=true
		active=mission
		return

func dialogue(mission, phase: int) -> Array:
	if not mission.story: return []
	var tables: Dictionary = data.constants.bo
	var key := "a:[[S" if phase == 0 else "b:[[S"
	if chapter >= tables[key].size(): return []
	var ids: Array = tables[key][chapter]
	var result: Array = []
	for i in range(0,ids.size(),2):
		if int(ids[i+1]) != 0: result.append({"speaker":int(ids[i]),"text_id":int(ids[i+1])})
	return result

func finished() -> bool:
	return chapter >= data.campaign.size()
