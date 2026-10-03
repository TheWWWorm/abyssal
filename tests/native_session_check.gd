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
	session.hints_said={"dock":true,"gate":true}
	var encoded: Dictionary = JSON.parse_string(JSON.stringify(saves.capture(session)))
	var restored = saves.restore(data,encoded)
	assert(restored!=null,saves.failure)
	var actual: Dictionary = JSON.parse_string(JSON.stringify(saves.capture(restored)))
	for key in encoded:
		if actual[key]!=encoded[key]: print("DIFF ",key," actual ",actual[key]," expected ",encoded[key])
	assert(actual==encoded,"Native save round trip")
	assert(restored.hints_said==session.hints_said,"One-time hint history survives a checkpoint round trip")
	var legacy: Dictionary=encoded.duplicate(true);legacy.erase("hints_said");legacy.elapsed_ms=30000
	var migrated=saves.restore(data,legacy)
	assert(migrated!=null and migrated.hints_said.has("dock"),"An established old checkpoint does not restart the docking tutorial")
	var credits_before: int=restored.credits
	restored.arrive()
	assert(restored.ship.cargo_used==0,"Colonist docking takes all cargo")
	assert(restored.pending_cargo_payment==0 and restored.credits==credits_before+8*restored.make_goods(0,8).minimum_price,"Colonist settlement pays the floor price at once, as the phone game does")
	var paid: int=restored.credits;restored.arrive()
	assert(restored.credits==paid,"Repeated docking cannot pay twice")
	restored.campaign.rebel_stations[restored.station_id]=true
	restored.ship.set_cargo([restored.make_goods(0,2),restored.make_goods(22,1)])
	restored.arrive()
	assert(restored.ship.cargo_used==3 and restored.credits==paid,"Non-colonist docking preserves fish and manufactured cargo")
	restored.campaign.rebel_stations[restored.station_id]=false
	var fixed_payment: int=2*restored.make_goods(0,2).minimum_price+restored.make_goods(22,1).minimum_price
	for stack in restored.ship.cargo:stack.price=99999
	restored.arrive()
	assert(restored.ship.cargo_used==0 and restored.credits==paid+fixed_payment,"All cargo settles at fixed values, not stale market quotes")
	assert(saves.restore(data,{"schema":1,"jar_sha256":data.jar_sha256})==null,"Reject incomplete save")
	var Content = preload("res://native/content.gd")
	data.rules_id=Content.rules_id(data)
	var reworded: Dictionary=encoded.duplicate(true); reworded.jar_sha256="1".repeat(64); reworded.rules_id=data.rules_id
	assert(saves.restore(data,reworded)!=null,"A save from a JAR that differs only in text loads")
	var relabelled: Dictionary=data.duplicate(true); relabelled.strings[0]="x"; relabelled.tables.stations[0][0]="Renamed"
	assert(Content.rules_id(relabelled)==data.rules_id,"Text and station names leave the rules unchanged")
	var older_import: Dictionary=data.duplicate(true); older_import.erase("music"); older_import.erase("water_palette"); older_import.importer_note="x"
	assert(Content.rules_id(older_import)==data.rules_id,"Optional presentation keys from newer importers leave the rules unchanged")
	data.legacy_rules_id=Content.legacy_rules_id(data)
	var from_1_16: Dictionary=reworded.duplicate(true); from_1_16.rules_id=data.legacy_rules_id
	assert(saves.restore(data,from_1_16)!=null,"A save fingerprinted by 1.16.1 still loads")
	relabelled.tables.ships[0][1]+=1
	assert(Content.rules_id(relabelled)!=data.rules_id,"A changed table changes the rules")
	reworded.rules_id="2".repeat(64)
	assert(saves.restore(data,reworded)==null,"A save from different rules is refused")
	print("NATIVE_SAVE_ROUND_TRIP passed")
	quit()
