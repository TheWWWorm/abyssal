extends RefCounted
## Who is in the water when a region is entered, as the phone game's cy
## fills it: twenty creatures of the local habitat (forty-nine in the algae
## chapter), the station's own ships on their rounds, a chance of pirates in
## the later chapters, and the encounter of the chapter or the contract in
## hand, each with its own layout, numbers and objective. Positions are the
## game's units about the station's centre; every draw is from the session's
## own random stream, in the order the original makes them.
const Math=preload("res://native/simulation/fixed_math.gd")
const NPC=preload("res://native/simulation/npc.gd")
const Special=preload("res://native/simulation/special_actor.gd")
const Creature=preload("res://native/simulation/creature.gd")
const Route=preload("res://native/simulation/route.gd")
const Goal=preload("res://native/simulation/encounter_goal.gd")
const Shape=preload("res://native/simulation/collision_shape.gd")
const WILDLIFE := 20
const ALGAE_WILDLIFE := 49
var r
var s
var data: Dictionary

func configure(region) -> void:
	r=region;s=r.session;data=s.data

func roll(bound: int) -> int:return s.rng.next_int(maxi(1,bound))
func ship_ids() -> Array:return data.constants.ah["e:[S"]
func random_ship() -> int:return int(ship_ids()[roll(ship_ids().size()-1)])
func path(points: Array,repeating: bool=false):
	var result:=Route.new();result.configure(points,repeating);return result
func path_copy(source):
	var copy:=Route.new();copy.configure(source.points.reduce(func(flat,point):return flat+point,[]),source.loop);return copy
func goal(name: String,count: int=0,target_species: int=-1):return Goal.new().configure(name,[],count,target_species)
func scatter(center: Array,spread: int) -> Array:
	var result: Array=[]
	for axis in 3:result.append(center[axis]+roll(spread)-spread/2)
	return result

func fish(species: int,center: Array=[0,0,0]):
	var actor:=Creature.new()
	var home: Array=center.duplicate()
	# A school gathers two hundred metres short of its mark.
	if home!=[0,0,0]:home[2]-=20000
	actor.configure(int(data.constants.ah["b:[S"][species]),data.tables.creatures[species],s.rng,r.sine,home)
	return actor

func ship(id: int,hostile: bool,center: Array=[0,0,0],team: int=2):
	# Somewhere in the four hundred metre cube about the mark; a tenth of
	# that when a school is being guarded.
	var location: Array=scatter(center,40000)
	if r.mission.kind==6:
		for axis in 3:location[axis]=center[axis]+(location[axis]-center[axis])/10
	var actor:=NPC.new();actor.configure(id,team,hostile,location,data,s.campaign.chapter,s.rng)
	actor.player=r.player
	actor.radius=int(data.constants.ah["c:[S"][id]) if id<20 else 2000
	# Hulls harden with the pilot's rank and the chapter.
	actor.health.configure(int(data.constants.ah["d:[S"][id])+s.counters.k*15+s.campaign.chapter*4,0,0)
	return actor

func special(kind: String,id: int,hostile: bool,center: Array=[0,0,0],team: int=2):
	var location: Array=[0,0,0] if kind=="capsule" else scatter(center,40000)
	var actor:=Special.new();actor.configure_special(kind,id,hostile,location,data,s.rng)
	actor.player=r.player;actor.radius=2000
	actor.health.configure(20,0,0)
	match kind:
		"capsule":actor.health.configure(32 if r.mission.kind==12 else 65,0,0)
		"freighter":
			actor.faction=team
			var shape:=Shape.new();shape.origin=location.duplicate();shape.offset=[0,300,0];shape.half_size=[4000,4000,15000];actor.shapes=[shape]
			# Six bursts along the hull, one to two seconds apart (ao(6,0)).
			actor.explosion_delays=[0]
			actor.explosion_offsets=[[360,186,-3370],[-844,-507,880],[-449,437,-983],[880,-275,-983],[360,186,4243],[0,0,0]]
			for _burst in 5:actor.explosion_delays.append(actor.explosion_delays[-1]+roll(1000)+1000)
			actor.explosion_duration=actor.explosion_delays[-1]+1000
	return actor

func hazard(id: int,center: Array):
	# A mine (13) or a piece of debris in the two hundred metre cube.
	var actor:=Special.new();actor.configure_special("mine" if id==13 else "debris",id,true,scatter(center,20000),data,s.rng)
	actor.player=r.player;actor.radius=1000;actor.health.configure(4 if id==13 else 1,0,0);actor.targets=[r.player]
	return actor

func enemies(count: int,center: Array=[0,0,0],id: int=-1,team: int=2,waiting: bool=false) -> void:
	for _i in count:
		var actor=ship(random_ship() if id<0 else id,true,center,team)
		if waiting:actor.dormant()
		r.enemies.append(actor)

func friends(count: int,center: Array=[0,0,0],id: int=-1,team: int=1) -> void:
	for _i in count:r.friends.append(ship(random_ship() if id<0 else id,false,center,team))

func wandering_route(count: int):
	var coordinates: Array=[]
	for _i in count:coordinates.append_array([60000+roll(40000),0,60000+roll(40000)])
	return path(coordinates)

func gate_approach(divisor: int) -> Array:
	var gate: Array=r.gates[1]
	return gate.map(func(v):return v+Math.i32(-v<<12)/divisor)

func wildlife() -> void:
	# The habitat table pairs species with a percentage; the original draws
	# down the table, taking each species when its roll comes in, round
	# and round until the water is stocked. The algae chapter stocks the
	# five algae, ten of each, instead.
	if r.mission.kind==6:return
	var habitat: Array=data.habitats[s.station_id]
	var algae_only: bool=r.mission.story and s.campaign.chapter==7 and r.mission.target_kind>=13
	if algae_only:
		for index in ALGAE_WILDLIFE:r.creatures.append(fish(13+index/10))
		return
	var cursor := 0
	for _i in WILDLIFE:
		for _attempt in 10000:
			if roll(100)<int(habitat[cursor+1]):
				r.creatures.append(fish(int(habitat[cursor])));cursor=(cursor+2)%habitat.size();break
			cursor=0

func station_rounds() -> void:
	# The station's own ships go round past both gates, half of them
	# starting from the second mark; from the twelfth chapter on there is a
	# growing chance of a pirate or three waiting a hundred and fifty metres
	# ahead.
	var rounds=path(Math.added(r.gates[0],[0,0,3000])+Math.added(r.gates[1],[0,0,3000])+[0,0,6000],true)
	r.school_route=rounds
	for record in s.stations[s.station_id].ships:
		var actor=ship(int(ship_ids()[record.id]),false,[0,0,0],0 if s.is_colonist_station() else 1)
		actor.route=path_copy(rounds);r.friends.append(actor)
		if roll(2)==0:actor.route.index=1;actor.route.reached[0]=true
	if s.campaign.chapter>11 and roll(100)<25+s.campaign.chapter:enemies(roll(4),[0,0,15000])

func guarded_school(center: Array,route) -> void:
	r.creatures=[]
	for _i in r.mission.total:
		var creature=fish(r.mission.target_kind,center);creature.constrained=true
		creature.pose.face([0,0,4096]);creature.advance(-1024+roll(2048),s.rng,r.player.pose.origin)
		creature.health.set_hull(10);creature.previous_hull=10;creature.health.set_hull(20)
		r.creatures.append(creature)
	r.school_route=route

func populate() -> void:
	wildlife()
	var mission=r.mission
	if mission.kind<0:station_rounds()
	elif mission.story:story()
	else:contract()

func contract() -> void:
	var m=r.mission
	var difficulty: float=float(m.normalized_difficulty(s.counters.k))/10.0
	match m.kind:
		0:
			# Wanted: one hardened ship, waiting four to twelve hundred metres out.
			r.route=path([(40000+roll(80000))*(1 if roll(2)==0 else -1),0,(40000+roll(80000))*(1 if roll(2)==0 else -1)])
			enemies(1,r.route.points[0],-1,2,true);r.enemies[0].health.configure(300+m.difficulty*s.counters.k,0,0);r.success=goal("enemy_dead",0)
		1,2,3:
			# Recovery, rescue and pirate hunts: a gang along a wandering route;
			# the ship to be recovered is the last of them, at the last mark.
			r.route=wandering_route(2+roll(2))
			var count: int=3+int(3*difficulty)
			for i in count:
				var id:=random_ship()
				enemies(1,r.route.points[-1] if i==count-1 and m.kind!=3 else r.route.points[roll(r.route.points.size())],id,2,true)
			if m.kind==3:r.success=goal("no_enemies")
			else:r.enemies[-1].protect(true);r.success=goal("enemy_rescued",count-1);r.failure=goal("enemy_escaped",count-1)
		4:
			# Escort: five freighters under way, raiders along their track.
			var track=path([10000,0,100000,10000,0,150000,10000,0,200000])
			for _i in 2+int(4*difficulty):enemies(1,track.points[roll(3)],random_ship(),1 if m.sponsor_faction==0 else 0,true)
			for mark in [[5500,-300,20000],[14500,3000,17000],[4000,-2000,12000],[17000,-6000,10000],[11000,7000,8000]]:
				var freighter=special("freighter",11,false,[0,0,0],m.sponsor_faction);freighter.set_position(mark);freighter.moving=true
				freighter.health.configure(100+s.counters.k*2+s.campaign.chapter*2,0,0);r.friends.append(freighter)
			r.success=goal("no_enemies");r.failure=goal("no_friends")
		5:
			# Intercept: a convoy of two or three freighters at the second mark, with its guard.
			r.route=path([-2500+roll(5000),-2500+roll(5000),80000+roll(30000),-2500+roll(5000),-2500+roll(5000),120000+roll(30000)])
			var count: int=2+roll(2)
			for _i in count:
				var freighter=special("freighter",11,true,r.route.points[1],1 if m.sponsor_faction==0 else 0);freighter.dormant();r.enemies.append(freighter)
				freighter.set_position(Math.added(r.route.points[1],[-10000+roll(20000),-10000+roll(20000),-10000+roll(20000)]))
			for _i in 2+int(2*difficulty):enemies(1,r.route.points[roll(2)],random_ship(),1 if m.sponsor_faction==0 else 0,true)
			r.success=goal("first_enemies_dead",count)
		6:
			# Defend fishes: the school swims its course; hunters lie along it.
			var track=path([20000,0,-40000,20000,0,40000,20000,0,90000]);guarded_school(track.points[0],track)
			for _i in 2+int(4*difficulty):enemies(1,track.points[1+roll(2)],random_ship(),0,true)
			r.success=goal("no_enemies");r.failure=goal("school_losses",m.total-m.minimum)
		7:
			# Attack fishes: the quarry among the wildlife, with hunters of the other side.
			enemies(int(3*difficulty),[0,0,0],-1,1)
			for i in mini(m.total+3,r.creatures.size()):r.creatures[i]=fish(m.target_kind)
			r.success=goal("harvest",m.total,m.target_kind)
		9,10:
			# Junk removal, on the clock, and the minefield: a field two to
			# six hundred metres out, with a guard.
			var center:=[-20000+roll(40000),0,20000+roll(40000)]
			var count: int=15+int(15*difficulty) if m.kind==9 else 15+roll(11)
			for _i in count:r.enemies.append(hazard(9996 if m.kind==9 else 13,center))
			enemies(int(2*difficulty) if m.kind==9 else 1,[0,0,0] if m.kind==9 else center,-1 if m.kind==9 else 1)
			r.success=goal("first_enemies_dead",count)
			if m.kind==9:r.time_limit=151000
		11:
			# Defend the capsules against the aquar.
			enemies(2+int(4*difficulty),[0,0,0],19,3)
			for _i in m.total:r.friends.append(special("capsule",9994,false,[0,0,0],3))
			r.success=goal("no_enemies");r.failure=goal("capsules_destroyed",m.minimum)
		12:
			# Attack the capsules, past their colonist guard, with aquar alongside.
			for _i in m.total:r.enemies.append(special("capsule",9994,true,[0,0,0],3))
			enemies(2+int(4*difficulty),[0,0,0],-1,0);friends(int(3*difficulty),[0,0,0],19,3)
			r.success=goal("first_enemies_dead",m.total)

func story() -> void:
	var m=r.mission
	match s.campaign.chapter:
		5:enemies(1,[0,0,0],1);r.success=goal("no_enemies")
		7:
			for i in mini(m.total,r.creatures.size()):r.creatures[i]=fish(m.target_kind)
			r.success=goal("harvest",m.total,m.target_kind)
		10:
			enemies(4,[0,0,0],19,3)
			for _i in m.total:r.friends.append(special("capsule",9994,false,[0,0,0],3))
			r.failure=goal("capsules_destroyed",m.minimum);r.success=goal("no_enemies")
		19:
			var track=path([-20000,0,-40000,-20000,0,30000,-20000,0,100000,-20000,0,130000]);guarded_school(track.points[1],track)
			for i in 3:enemies(1,track.points[2 if i==0 else 3],-1,0,true)
			friends(3,track.points[0],19,0);r.success=goal("no_enemies");r.failure=goal("school_losses",m.total-m.minimum)
		21:
			# The companion waits short of the far gate; three pirates at the mark.
			r.route=path([0,0,200000]);friends(1,[0,0,0],5)
			roll(1400);roll(1400)
			r.friends[0].health.set_hull(9999999);r.friends[0].route=path_copy(r.route)
			r.friends[0].set_position(Math.added(gate_approach(12288),[0,0,-10000]));r.friends[0].dormant()
			enemies(3,r.route.points[0],-1,2,true);r.success=goal("no_enemies")
		23:
			# Seventeen mines and a guard of three at (800, 1200) m; the original
			# lays an eighteenth and replaces it with a ship, and counts to eighteen.
			for _i in 17:r.enemies.append(hazard(13,[80000,0,120000]))
			hazard(13,[80000,0,120000])
			enemies(3,[80000,0,120000]);r.success=goal("first_enemies_dead",18)
		25:
			for i in 3:
				friends(1,[0,0,0],5 if i==0 else 2);r.friends[-1].set_position(Math.added(r.player.pose.origin,[[800,340,700],[-1000,-130,-500],[-30,-300,-100]][i]));r.friends[-1].health.configure(32000,0,0)
			r.friends[0].route=path([-200000,0,-200000])
			for i in 6:enemies(1,[0,0,0],-1,0);r.enemies[-1].set_position([-40000+i*2000,-6000+i*2000,10000+i*2000])
			r.success=goal("no_enemies")
		27:
			r.route=path([120000,0,130000]);enemies(1,r.route.points[0],5,1,true)
			r.enemies[0].health.configure(r.enemies[0].health.max_hull*5,0,0);r.enemies[0].set_speed(5);r.enemies[0].protect(true)
			r.success=goal("enemy_rescued",0);r.failure=goal("enemy_escaped",0)
		29:
			var track=path([-30000,0,30000,-30000,0,130000,-30000,0,200000]);var id:=random_ship()
			for i in 5:enemies(1,track.points[0 if i<2 else (1 if i<3 else 2)],id,0,true)
			for mark in [[-37500,-1300,20000],[-22500,4000,17000],[-31000,-3000,13000],[-20000,-7000,10000],[-29000,8000,8000]]:
				var freighter=special("freighter",11,false,[0,0,0],1);freighter.set_position(mark);freighter.moving=true;freighter.activate()
				freighter.health.configure(150+s.counters.k*5,0,0);r.friends.append(freighter)
			r.success=goal("no_enemies");r.failure=goal("no_friends")
		31:
			r.route=path([-160000,0,30000]);enemies(4,r.route.points[0],-1,0,true)
			for actor in r.enemies:actor.protect(true)
			friends(2)
			for i in 2:r.friends[i].set_position(Math.added(r.player.pose.origin,[400,40,400] if i==0 else [-300,-30,-300]));r.friends[i].health.configure(32000,0,0)
			for actor in r.friends:actor.route=path_copy(r.route)
			r.success=goal("all_rescued");r.failure=goal("any_escaped")
		35:
			r.route=path([20000,0,120000])
			for i in 3:enemies(1,r.route.points[0],10 if i==0 else 0,2,true)
			r.enemies[0].health.configure(r.enemies[0].health.max_hull*5,0,0);r.enemies[0].set_speed(5);r.success=goal("enemy_dead",0)
		42:
			r.route=path([170000,0,0,240000,0,0])
			for i in 6:enemies(1,r.route.points[0 if i<3 else 1],-1,2,true)
			r.success=goal("no_enemies")
		43:
			r.school_route=path([150000,0,0,0,0,0])
			enemies(8,[0,0,0],-1,0);friends(2)
			for _i in 5:
				friends(1,[150000,0,0],19,3);r.friends[-1].dormant();r.friends[-1].route=path([150000,0,0,0,0,0])
			r.success=goal("no_enemies")
		45,47:
			var chapter: int=s.campaign.chapter
			for i in (4 if chapter==45 else 5):
				friends(1)
				if i<2:r.friends[-1].health.set_hull(32000)
				if chapter==45:r.friends[-1].set_position(Math.added(gate_approach(28672),[-3000+roll(6000),-3000+roll(6000),-3000+roll(6000)]))
			if chapter==45:
				r.school_route=path([0,-60000,0,0,0,0])
				for _i in 3:friends(1,[0,-60000,0],19,3);r.friends[-1].route=path([0,-60000,0,0,0,0])
			for _i in 5:
				var freighter=special("freighter",11,true,[0,0,0],0);freighter.set_position([10000+roll(20000),-10000+roll(20000),10000+roll(20000)]);r.enemies.append(freighter)
				if chapter==45:freighter.health.set_hull(freighter.health.hull*2)
			enemies(7 if chapter==45 else 3,[0,0,0],-1,0)
			if chapter==47:
				enemies(1,[0,0,0],7,0);r.enemies[-1].health.set_hull(32000);r.enemies[-1].set_speed(6);r.enemies[-1].capturable=false
			r.success=goal("no_enemies")
		_:
			# A story chapter with a destination but no encounter of its own.
			pass
