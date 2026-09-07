extends SceneTree
func _initialize() -> void:
	var path := OS.get_cmdline_user_args()[0]
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var session := preload("res://native/simulation/session.gd").new()
	session.new_game(data,"Player",12345)
	var economy := preload("res://native/simulation/economy.gd").new(); economy.configure(session)
	economy.generate(session.stations[0])
	var body := preload("res://native/simulation/station_body.gd").new()
	body.configure(session.stations[0],true,data.constants.dt["a:[S"])
	var loadout := preload("res://native/simulation/weapon_loadout.gd").new()
	loadout.configure(session.ship,data)
	print("NATIVE_SESSION_INITIALIZED ",session.name," ",session.ship.values()," ",body.parts.size()," ",loadout.groups.size())

	var saves := preload("res://native/simulation/save_store.gd").new()
	session.prepare_station(0)
	session.register_catch(0,8)
	var encoded: Dictionary = JSON.parse_string(JSON.stringify(saves.capture(session)))
	var restored = saves.restore(data,encoded)
	assert(restored!=null,saves.failure)
	var actual: Dictionary = JSON.parse_string(JSON.stringify(saves.capture(restored)))
	for key in encoded:
		if actual[key]!=encoded[key]: print("DIFF ",key," actual ",actual[key]," expected ",encoded[key])
	assert(actual==encoded,"Native save round trip")
	var credits_before: int=restored.credits
	restored.arrive()
	assert(restored.ship.cargo_used==0,"Colonist docking takes all cargo")
	assert(restored.pending_cargo_payment==0 and restored.credits==credits_before+restored.make_goods(0,8).total_price(),"Colonist settlement pays the fixed catalog value immediately")
	var paid: int=restored.credits;restored.arrive()
	assert(restored.credits==paid,"Repeated docking cannot pay twice")
	restored.campaign.rebel_stations[restored.station_id]=true
	restored.ship.set_cargo([restored.make_goods(0,2),restored.make_goods(22,1)])
	restored.arrive()
	assert(restored.ship.cargo_used==3 and restored.credits==paid,"Non-colonist docking preserves fish and manufactured cargo")
	restored.campaign.rebel_stations[restored.station_id]=false
	var fixed_payment: int=restored.make_goods(0,2).total_price()+restored.make_goods(22,1).total_price()
	for stack in restored.ship.cargo:stack.price=99999
	restored.arrive()
	assert(restored.ship.cargo_used==0 and restored.credits==paid+fixed_payment,"All cargo settles at fixed values, not stale market quotes")
	assert(saves.restore(data,{"schema":1,"jar_sha256":data.jar_sha256})==null,"Reject incomplete save")
	print("NATIVE_SAVE_ROUND_TRIP passed")
	quit()
