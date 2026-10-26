extends RefCounted
## A disposable firing range. The outfit uses the same slots, equipment and
## weapon construction as a campaign; only availability and the encounter differ.
const Ship = preload("res://native/simulation/ship_stats.gd")
const Mission = preload("res://native/simulation/mission.gd")
const Setup = preload("res://native/simulation/region_setup.gd")
var ship_id := 0
var equipment: Array = [0,15,18,22,35,39]
var quick_test := false
var quick_weapon := -1

static func weapon_ids(session) -> Array:
	var ids: Array=[]
	for row in session.data.tables.equipment:
		if int(row[1]) in [0,1,2]:ids.append(int(row[0]))
	return ids

func step_weapon(world, direction: int) -> void:
	if not world.session.demo_mode:return
	var ids := weapon_ids(world.session)
	if ids.is_empty():return
	quick_weapon=ids[posmod(ids.find(quick_weapon)+direction,ids.size())]
	quick_test=true;refresh_weapons(world)

func refresh_weapons(world) -> void:
	if not world.session.demo_mode or world.region==null:return
	var session=world.session
	if quick_test:
		var ids := weapon_ids(session)
		if ids.is_empty():quick_test=false
		elif quick_weapon not in ids:
			var fitted: Array=session.ship.equipment.filter(func(item):return item!=null and item.is_weapon())
			quick_weapon=ids[0] if fitted.is_empty() else fitted[0].id
	# The test launcher borrows this hull's mount; the fitted outfit and all
	# ship statistics remain intact so leaving comparison restores them.
	var outfit={"id":session.ship.id,"equipment":[session.make_equipment(quick_weapon)]} if quick_test else session.ship
	world.region.configure_player_weapons(outfit)
	world.weapon_pending.clear()
	for weapon in world.region.loadout.all_weapons():weapon.terrain_collision=world.collides_station
	for hook in world.region.fishing:hook.capture_distance=1400;hook.tow_speed=24

static func initialize(session) -> void:
	session.demo_mode=true
	# No story, contract, opening, chapter triggers or campaign rewards.
	session.campaign.chapter=9
	session.campaign.primary=Mission.new()
	session.campaign.secondary=Mission.new()
	session.campaign.active=session.campaign.primary
	session.discovered.fill(true)
	session.pending_bounty=0

func read_outfit(session) -> void:
	ship_id=session.ship.id
	equipment=session.ship.equipment.map(func(item):return -1 if item==null else item.id)

func select_ship(session, id: int) -> void:
	if id<0 or id>=session.data.tables.ships.size():return
	ship_id=id
	var count: int=session.data.tables.ships[id][4]
	while equipment.size()<count:equipment.append(-1)
	equipment.resize(count)

func select_equipment(session, slot: int, id: int) -> void:
	if slot<0 or slot>=equipment.size() or id< -1 or id>=session.data.tables.equipment.size():return
	if id>=0:
		var kind: int=session.data.tables.equipment[id][1]
		# Unique systems move to the chosen slot, matching the outfitter's
		# rules; ordinary guns and cargo modules may occupy several slots.
		if kind not in [0,5]:
			for index in equipment.size():
				if equipment[index]>=0 and int(session.data.tables.equipment[equipment[index]][1])==kind:equipment[index]=-1
	equipment[slot]=id

func apply(session) -> void:
	assert(session.demo_mode)
	select_ship(session,ship_id)
	var vessel := Ship.new();vessel.configure(session.data.tables.ships[ship_id])
	for slot in equipment.size():
		var id: int=equipment[slot]
		if id<0 or id>=session.data.tables.equipment.size():continue
		var item=session.make_equipment(id)
		if vessel.permits_kind(item.kind):vessel.equipment[slot]=item
	vessel.recompute();session.ship=vessel
	session.hull=vessel.hull;session.shield=vessel.shield;session.armor=vessel.armor
	session.station_id=0;session.docked=false
	session.pending_bounty=0;session.notices.clear()
	# Even an outfit with no shield or armour starts at a safe depth.
	session.stations[0].depth=clampi(22500,vessel.minimum_depth,vessel.maximum_depth)
	read_outfit(session)

static func populate(region) -> void:
	var setup := Setup.new();setup.configure(region)
	region.player.pose.origin=[0,0,-60000]
	region.player.stop()
	# Unarmed ships ahead: close enough for the shortest gun, with lateral
	# targets for following a tracer, beam or homing torpedo.
	for index in 3:
		var actor=setup.ship(int(setup.ship_ids()[[0,6,10][index]]),true)
		actor.set_position([[0,0,-72000],[-8000,0,-78000],[-15000,0,-85000]][index])
		actor.set_speed(0);actor.state=1
		region.enemies.append(actor)
	# Live creatures to port retain normal movement and hook resistance.
	for index in 3:
		var fish=setup.fish([0,2,1][index])
		fish.pose.origin=[5000+index*4000,0,-70000-index*4000]
		fish.pose.face([-4096,0,0]);fish.constrained=true
		region.creatures.append(fish)
