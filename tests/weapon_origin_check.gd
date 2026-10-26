extends SceneTree
const Content=preload("res://native/content.gd")
const Model=preload("res://native/presentation/model.gd")
const Mounts=preload("res://native/simulation/weapon_mounts.gd")
const Loadout=preload("res://native/simulation/weapon_loadout.gd")
const Pose=preload("res://native/simulation/ship_transform.gd")
const Effects=preload("res://native/presentation/combat_effects.gd")
const Library=preload("res://scripts/model_library.gd")
var checks:=0
var failures:=0
var models: Dictionary={}
func expect(ok: bool, why: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(why)
func _initialize() -> void:call_deferred("run")
func visual(content, id: int):
	if not models.has(id):
		var node:=Model.new();node.configure(content.root,content.registry.filter(func(e):return int(e.id)==id)[0]);root.add_child(node);models[id]=node
	return models[id]
func run() -> void:
	var args:=OS.get_cmdline_user_args();var content:=Content.new()
	if args.is_empty() or not content.load_cache(args[0]):push_error("Pass an imported content directory");quit(1);return
	var raw: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(args[0].path_join("native-data.json")))
	expect(Content.rules_id(raw)==Content.rules_id(content.data) and Content.previous_rules_id(raw)==Content.previous_rules_id(content.data) and Content.legacy_rules_id(raw)==Content.legacy_rules_id(content.data),"Derived launch geometry preserves current and historical save fingerprints")
	var session=preload("res://native/simulation/session.gd").new();session.new_game(content.data,"Launch check",712)
	for hull in content.data.tables.ships.size():
		# Compare with the renderer's posed opaque hull, not the helper's own
		# geometry. Light cones extend much farther than this solid bow.
		var bow: float=visual(content,hull).solid_bounds().position.z
		for id in [0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,42]:
			var weapon=Loadout.create(session.make_equipment(id),content.data)
			Mounts.fit(weapon,content.data,hull)
			var safe:=true
			for target in [[0,0,50000],[16000,0,50000],[-16000,0,50000],[0,16000,50000],[0,-16000,50000]]:
				weapon.remaining.fill(-1);weapon.launch(Pose.new(),40,target)
				var frame:=Pose.new();frame.origin=weapon.positions[0];frame.face(weapon.velocities[0])
				var box:=AABB(Vector3(-.4,-.4,0),Vector3(.8,.8,2)) if weapon.fishing else AABB()
				if not weapon.beam and not weapon.fishing:box=visual(content,weapon.model_id).bounds()
				var transform: Transform3D=frame.godot_transform()
				if weapon.homing:transform.basis=transform.basis.scaled_local(Vector3.ONE*2)
				for corner in 8:
					if (transform*box.get_endpoint(corner)).z>bow-.01:safe=false
			expect(safe,"Hull %d / weapon %d clears the rendered bow at launch, including converged shots"%[hull,id])
			if weapon.beam:
				weapon.advance(40)
				for fraction in [0.0,.25,.5,1.0]:
					var head:=Effects.projectile_position(weapon,0,fraction)
					var length:=Effects.trail_length(weapon,0,fraction,10000)
					var tail:=head-Library.point(weapon.velocities[0]).normalized()*length
					expect(tail.distance_to(Library.point(weapon.launch_positions[0]))<.02,"A newborn coil segment grows forward from its actual launch point")
		# More than one gun must use distinct, symmetric launchers ahead of
		# the same hull; the hook keeps its own centre-line attachment.
		var ship=preload("res://native/simulation/ship_stats.gd").new();ship.configure(content.data.tables.ships[hull])
		ship.equipment[0]=session.make_equipment(0);ship.equipment[1]=session.make_equipment(0)
		var loadout:=Loadout.new();loadout.configure(ship,content.data)
		var guns:=loadout.all_weapons()
		expect(guns.size()==2 and guns[0].muzzle[0]==-guns[1].muzzle[0] and guns[0].muzzle[0]!=0,"Twin guns remain symmetric on hull %d"%hull)
	var shared=Loadout.create(session.make_equipment(0),content.data)
	var original: Array=shared.mount.duplicate()
	var small:=Mounts.for_actor(shared,content.data,0);var large:=Mounts.for_actor(shared,content.data,6)
	shared.launch(Pose.new(),40,null,small);shared.launch(Pose.new(),40,null,large)
	expect(shared.positions[0]==small and shared.positions[1]==large and shared.mount==original,"Shared NPC pools retain the firing actor's own bow without changing another ship's launcher")
	for node in models.values():node.queue_free()
	await process_frame
	print("WEAPON_ORIGIN ",checks," checks; ",failures," failures");quit(1 if failures else 0)
