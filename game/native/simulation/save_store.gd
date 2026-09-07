extends RefCounted
## Native save schema. Only data is read; no scripts/resources are instantiated
## from file paths in a save. The owner's content profile must match on load.
const Session = preload("res://native/simulation/session.gd")
const Mission = preload("res://native/simulation/mission.gd")
const Ship = preload("res://native/simulation/ship_stats.gd")
const MISSION_FIELDS := ["kind","sponsor","sponsor_faction","portrait","reward","deposit","destination","destination_name","difficulty","jump_limit","jumps","terminal","story","failed","completed","briefing","item_id","item_count","target_kind","total","minimum","percentage","threshold"]
const SESSION_FIELDS := ["name","credits","elapsed_ms","counters","discovered","fish_found","goods_found","station_id","recent_stations","hull","shield","armor","docked","entered_gate","last_arrival_ms","pending_cargo_payment","notices"]
var failure := ""

static func fields(object, names: Array) -> Dictionary:
	var result: Dictionary = {}
	for key in names: result[key]=object.get(key)
	return result

static func integral(value):
	if value is float: return int(value)
	if value is Array: return value.map(integral)
	if value is Dictionary:
		var result: Dictionary = {}
		for key in value: result[key]=integral(value[key])
		return result
	return value

static func restore_fields(object, values: Dictionary, names: Array) -> void:
	for key in names:
		if values.has(key): object.set(key,integral(values[key]))

static func gear(item) -> Variant:
	return null if item==null else fields(item,["id","price","quantity","discounted"])

static func cargo(items: Array) -> Array:
	return items.map(func(item): return {"id":item.id,"owned":item.owned,"price":item.price})

static func ship_state(ship) -> Dictionary:
	return {"id":ship.id,"price":ship.price,"upgraded":ship.upgraded,"selected_weapon":ship.selected_weapon,"equipment":ship.equipment.map(gear),"cargo":cargo(ship.cargo)}

static func mission_state(mission) -> Dictionary:
	return fields(mission,MISSION_FIELDS)

static func capture(session) -> Dictionary:
	var result := fields(session,SESSION_FIELDS)
	result.face_layers=session.face_layers.duplicate()
	result.schema=2; result.random_engine="godot-pcg"; result.jar_sha256=session.data.jar_sha256
	result.medals=session.medals.state(); result.pending_bounty=session.pending_bounty
	# Store the native 64-bit PRNG as decimal text, avoiding JSON number round trips.
	result.random_state=str(session.rng.state)
	result.ship=ship_state(session.ship)
	result.chapter=session.campaign.chapter; result.rebel_stations=session.campaign.rebel_stations
	result.primary=mission_state(session.campaign.primary); result.secondary=mission_state(session.campaign.secondary)
	result.active=0 if session.campaign.active==session.campaign.primary else (1 if session.campaign.active==session.campaign.secondary else -1)
	result.stations=[]
	for station in session.stations:
		if not station.generated: continue
		result.stations.append({"id":station.id,"equipment":station.equipment.map(gear),"ships":station.ships.map(ship_state),"cargo":cargo(station.cargo),"missions":station.missions.map(mission_state)})
	return result

static func load_gear(session, value):
	if value==null: return null
	var item = session.make_equipment(int(value.id))
	restore_fields(item,value,["price","quantity","discounted"])
	return item

static func load_cargo(session, values: Array) -> Array:
	var result: Array = []
	for value in values:
		var item = session.make_goods(int(value.id),int(value.owned)); item.price=int(value.price); result.append(item)
	return result

static func load_ship(session, value: Dictionary):
	var ship := Ship.new(); ship.configure(session.data.tables.ships[int(value.id)])
	restore_fields(ship,value,["price","upgraded","selected_weapon"])
	ship.equipment=value.equipment.map(func(item): return load_gear(session,item))
	ship.set_cargo(load_cargo(session,value.cargo))
	return ship

static func load_mission(value: Dictionary):
	var mission := Mission.new(); restore_fields(mission,value,MISSION_FIELDS); return mission

func restore(data: Dictionary, value: Dictionary):
	if int(value.get("schema",0)) not in [1,2] or value.get("jar_sha256","")!=data.jar_sha256:
		failure="This save needs a matching DEEP content profile."; return null
	if not validate(value,data): failure="The native save is incomplete or invalid."; return null
	var session := Session.new(); session.new_game(data,str(value.name),0)
	restore_fields(session,value,SESSION_FIELDS)
	if value.has("face_layers"): session.face_layers=integral(value.face_layers)
	if value.get("schema",1)==1:session.rng.seed_from(str(value.random_state).to_int())
	else:session.rng.state=str(value.random_state).to_int()
	session.ship=load_ship(session,value.ship)
	if value.has("medals"): session.medals.restore(value.medals)
	session.pending_bounty=int(value.get("pending_bounty",0))
	session.campaign.chapter=int(value.chapter); session.campaign.rebel_stations=value.rebel_stations
	session.campaign.primary=load_mission(value.primary); session.campaign.secondary=load_mission(value.secondary)
	session.campaign.active=Mission.new() if int(value.active)<0 else (session.campaign.primary if int(value.active)==0 else session.campaign.secondary)
	for saved in value.stations:
		var station: Dictionary = session.stations[int(saved.id)]
		station.generated=true; station.equipment=saved.equipment.map(func(item): return load_gear(session,item))
		station.cargo=load_cargo(session,saved.cargo); station.ships=saved.ships.map(func(item): return load_ship(session,item))
		station.missions=saved.missions.map(load_mission)
	return session

func validate(value: Dictionary, data: Dictionary) -> bool:
	if value.has("face_layers"):
		if value.face_layers is not Array or value.face_layers.size()!=6: return false
		for layer in value.face_layers:
			if (layer is not int and layer is not float) or int(layer)!=layer or layer< -1 or layer>94: return false
	if value.has("medals"):
		if value.medals is not Dictionary: return false
		for key in ["levels","pending"]:
			if not value.medals.has(key) or value.medals[key] is not Array or value.medals[key].size()!=24: return false
			for id in value.medals[key].size():
				var tier=value.medals[key][id]
				if tier is not float and tier is not int: return false
				if int(tier)!=tier or tier<0 or tier>data.constants.f["a:[[I"][id].size(): return false
		for key in ["kills","catches","pirates","weapon_count","maximum_credits","minimum_credits"]:
			if not value.medals.has(key) or (value.medals[key] is not float and value.medals[key] is not int): return false
			if int(value.medals[key])!=value.medals[key] or value.medals[key]<0: return false
	if value.has("pending_bounty") and (value.pending_bounty is not int and value.pending_bounty is not float or int(value.pending_bounty)!=value.pending_bounty or value.pending_bounty<0): return false
	for key in SESSION_FIELDS+["random_state","ship","chapter","rebel_stations","primary","secondary","active","stations"]:
		if not value.has(key): return false
	if int(value.station_id)<0 or int(value.station_id)>=data.tables.stations.size(): return false
	if value.discovered.size()!=200 or value.rebel_stations.size()!=200: return false
	if int(value.chapter)<1 or int(value.chapter)>data.campaign.size(): return false
	if value.stations is not Array or value.stations.size()>3: return false
	var ships: Array = [value.ship]
	var cargo_rows: Array = []
	var equipment: Array = []
	for station in value.stations:
		if station is not Dictionary or not station.has_all(["id","equipment","cargo","ships","missions"]): return false
		if int(station.id)<0 or int(station.id)>=200: return false
		ships.append_array(station.ships); cargo_rows.append_array(station.cargo); equipment.append_array(station.equipment)
	for ship in ships:
		if ship is not Dictionary or not ship.has_all(["id","price","equipment","cargo"]): return false
		if int(ship.id)<0 or int(ship.id)>=data.tables.ships.size(): return false
		if ship.equipment.size()!=int(data.tables.ships[int(ship.id)][4]): return false
		equipment.append_array(ship.equipment); cargo_rows.append_array(ship.cargo)
	for item in equipment:
		if item==null: continue
		if item is not Dictionary or not item.has_all(["id","price","quantity","discounted"]): return false
		if int(item.id)<0 or int(item.id)>=data.tables.equipment.size(): return false
	for item in cargo_rows:
		if item is not Dictionary or not item.has_all(["id","price","owned"]): return false
		if int(item.id)<0 or int(item.id)>=data.tables.goods.size() or int(item.owned)<0: return false
	return true

func write(path: String, session) -> bool:
	failure=""
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path+".tmp",FileAccess.WRITE)
	if file==null: failure="Could not write the save file."; return false
	file.store_string(JSON.stringify(capture(session))); file.flush(); file.close()
	if FileAccess.file_exists(path):
		var backup_error := DirAccess.copy_absolute(path,path+".bak")
		if backup_error!=OK: failure="Could not preserve the previous checkpoint."; return false
	var error := DirAccess.rename_absolute(path+".tmp",path)
	if error!=OK: failure="Could not finish saving."; return false
	return true

func read(path: String, data: Dictionary):
	failure=""
	var file := FileAccess.open(path,FileAccess.READ)
	if file==null: failure="No native save was found."; return null
	var value = JSON.parse_string(file.get_as_text())
	if value is not Dictionary: failure="The save file could not be read."; return null
	return restore(data,value)
