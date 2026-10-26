extends SceneTree
const Session=preload("res://native/simulation/session.gd")
const Demo=preload("res://native/simulation/demo_session.gd")
const World=preload("res://native/simulation/world.gd")
const Store=preload("res://native/simulation/save_store.gd")
var failures:=0
var checks:=0
func expect(ok: bool, why: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(why)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var content=preload("res://native/content.gd").new()
	expect(content.load_cache(OS.get_cmdline_user_args()[0]),"Compatible imported content loads")
	if content.data.is_empty():quit(1);return
	var session:=Session.new();session.new_game(content.data,"Campaign sentinel",12345)
	var store:=Store.new()
	var path: String="user://demo-check/campaign.json"
	expect(store.write(path,session),"Normal campaign checkpoint remains writable")
	expect(store.write(path,session),"A normal backup can be created")
	var saved:=FileAccess.get_file_as_bytes(path);var backup:=FileAccess.get_file_as_bytes(path+".bak")
	Demo.initialize(session)
	var draft:=Demo.new();draft.apply(session)
	expect(session.demo_mode and session.campaign.primary.kind<0 and session.campaign.secondary.kind<0,"Demo has no active campaign mission or contract")
	for id in content.data.tables.ships.size():
		draft.select_ship(session,id);draft.apply(session)
		expect(session.ship.id==id and session.ship.slots==int(content.data.tables.ships[id][4]),"Imported hull %d retains its actual slot count"%id)
		expect(session.ship.hull==int(content.data.tables.ships[id][1]),"Imported hull %d retains its actual strength"%id)
	for id in content.data.tables.equipment.size():
		draft.select_equipment(session,0,id);draft.apply(session)
		expect(session.ship.equipment[0]!=null and session.ship.equipment[0].id==id,"Imported equipment %d can be tested without progression"%id)
		expect(session.ship.equipment.filter(func(item):return item!=null and item.kind==int(content.data.tables.equipment[id][1])).size()==1 or int(content.data.tables.equipment[id][1]) in [0,5],"Unique systems remain unique for equipment %d"%id)
	draft.select_equipment(session,0,15);draft.select_equipment(session,1,17)
	expect(draft.equipment[0]==-1 and draft.equipment[1]==17,"Replacing the harpoon moves the unique system into the chosen slot")
	draft.select_equipment(session,0,0);draft.select_equipment(session,2,0);draft.apply(session)
	expect(session.ship.equipment[0].id==0 and session.ship.equipment[2].id==0,"Multiple ordinary gun mounts remain allowed")
	draft=Demo.new();draft.apply(session)
	var world:=World.new();world.configure(session)
	expect(world.depart(),"Demo departs without tutorial or quest requirements")
	var r=world.region
	expect(r.enemies.size()==3 and r.creatures.size()==3 and r.friends.is_empty(),"Range provides gun and live hook targets")
	expect(r.weapons.size()==1 and r.enemies.all(func(actor):return actor.weapons.is_empty()),"Targets are unarmed; only equipped guns enter the projectile pool")
	expect(r.timeline.is_empty() and r.success==null and r.failure==null,"No story event or encounter goal can interrupt the range")
	var target=r.enemies[0];var initial_hull: int=target.health.hull
	for frame in 300:r.step(40,{"guns":true})
	expect(r.loadout.all_weapons()[0].launch_serial>0 and target.health.hull<initial_hull,"Real gun shots launch and damage a target in front of the spawn")
	expect(not r.failed and r.pending_mission==null,"Sustained firing does not trigger a mission or harm the pilot")
	draft.apply(session);world.depart();r=world.region
	var fish=r.creatures[0]
	r.player.pose.face(preload("res://native/simulation/fixed_math.gd").subtracted(fish.pose.origin,r.player.pose.origin))
	var hooked:=false
	for frame in 300:
		r.step(40,{"hook":true,"hook_aim":fish.pose.origin})
		hooked=hooked or r.fishing[0].hooked
		if session.ship.cargo_used>0:break
	expect(hooked and session.ship.cargo_used>0,"Real harpoon flies, hooks, tows and collects a live range target")
	draft.apply(session);world.depart();r=world.region
	expect(session.ship.cargo_used==0 and r.player.health.hull==session.ship.hull and r.enemies.size()==3 and r.creatures.size()==3,"Reset restores defenses, clears cargo and recreates all targets")
	expect(r.loadout.all_weapons().all(func(weapon):return weapon.launch_serial==0),"Reset removes all old shots and tether state")
	var outfit: Array=session.ship.equipment.duplicate()
	var player=r.player;var enemies: Array=r.enemies.duplicate();var position: Array=player.pose.origin.duplicate()
	var ids: Array=Demo.weapon_ids(session)
	expect(ids.size()==19 and ids.has(15) and ids.has(16) and ids.has(17) and ids.has(42),"Quick test includes every gun, torpedo, hook and the story weapon")
	draft.quick_test=true
	for id in ids:
		draft.quick_weapon=id;draft.refresh_weapons(world)
		var active: Array=r.loadout.all_weapons()
		expect(active.size()==1 and active[0].equipment_id==id,"Quick test isolates weapon %d"%id)
		expect(active[0].elapsed==active[0].cooldown and active[0].terrain_collision.is_valid(),"Weapon %d is ready and still uses world collisions"%id)
		r.loadout.fire(player.pose,40)
		expect(active[0].launch_serial==1,"The first test press launches exactly once for weapon %d"%id)
		expect(r.player==player and r.enemies==enemies and player.pose.origin==position and session.ship.equipment==outfit,"Weapon %d leaves the hull, outfit, pose and targets intact"%id)
		expect(r.weapons.size()+r.fishing.size()==1,"Weapon %d retires previous projectiles and fishing state"%id)
	draft.quick_weapon=ids.back();draft.step_weapon(world,1)
	expect(draft.quick_weapon==ids[0],"Quick cycling wraps from last to first")
	draft.step_weapon(world,-1)
	expect(draft.quick_weapon==ids.back(),"Quick cycling wraps backward")
	draft.quick_weapon=15;draft.refresh_weapons(world)
	r.fishing[0].attach(r.creatures[0]);var caught=r.creatures[0]
	draft.step_weapon(world,1)
	expect(not caught.towing and r.fishing[0].target==null,"Switching hooks releases the old catch and tether")
	draft.quick_test=false;draft.refresh_weapons(world)
	expect(r.loadout.all_weapons().map(func(w):return w.equipment_id)==[0,15] and session.ship.equipment==outfit,"Leaving comparison restores the full original outfit")
	session.docked=true
	expect(not store.write(path,session),"Demo write is refused even if it becomes docked")
	expect(not store.write("user://demo-check/new-slot.json",session) and not FileAccess.file_exists("user://demo-check/new-slot.json"),"Demo cannot create a manual slot")
	expect(FileAccess.get_file_as_bytes(path)==saved and FileAccess.get_file_as_bytes(path+".bak")==backup and not FileAccess.file_exists(path+".tmp"),"Checkpoint, backup and temporary paths are unchanged")
	var restored=store.read(path,content.data)
	expect(restored!=null and not restored.demo_mode and restored.name=="Campaign sentinel","Loading a campaign after a demo restores normal play")
	var normal_world:=World.new();normal_world.configure(restored);normal_world.depart()
	var normal_weapons: Array=normal_world.region.loadout.all_weapons()
	draft.quick_test=true;draft.quick_weapon=42;draft.refresh_weapons(normal_world)
	expect(normal_world.region.loadout.all_weapons()==normal_weapons,"Quick test cannot replace a campaign loadout")
	normal_world.dispose()
	world.dispose();world.region=null
	print("DEMO_SESSION ",checks," checks; ",failures," failures");quit(1 if failures else 0)
