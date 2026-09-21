extends RefCounted
## The job board, as the phone game's cp fills it: one to eight offers,
## each of a kind the station's side will post, to a destination within the
## story's reach, paid by difficulty and distance with a deposit of a tenth
## or so, and fronted by a face from the imported portrait parts.
const Math=preload("res://native/simulation/fixed_math.gd")
const Mission=preload("res://native/simulation/mission.gd")
## The story's own goods and the imports never make a delivery order.
const UNDELIVERABLE := [33,34,35,37,38,39,40]
var session

func roll(bound: int) -> int:return session.rng.next_int(maxi(1,bound))

func destination(station: Dictionary) -> int:
	# A holding past the first twenty, mostly within the ship's depth band,
	# and no further off on the chart than the chapter allows.
	while true:
		var id: int=maxi(20,roll(200))
		var target: Dictionary=session.stations[id]
		if roll(100)<70 and (target.percent>session.ship.deep_percent or target.percent<session.ship.shallow_percent):continue
		if roll(100)<100 and (absi(target.x-station.x)>20+session.campaign.chapter or absi(target.y-station.y)>20+session.campaign.chapter):continue
		return id
	return 20

func portrait(variant: bool,faction: int) -> Array:
	# The face is assembled layer by layer from the imported parts: the
	# faction's own first layer, then one of each category, the last layer
	# only sometimes.
	var parts: Dictionary=session.data.constants.ab
	var special: bool=variant and roll(100)<int(parts["c:byte"])
	var result: Array=[]
	for layer in parts["a:[[[B"].size():
		var category: int=(1 if special else 0) if variant else 2
		if layer==0:result.append(int(parts["f:[B"][faction]))
		elif layer!=5 or roll(100)<int(parts["d:byte"]):
			var source: int=(2 if layer==1 else 1) if not variant and layer in [1,2] else layer
			var options: Array=parts["a:[[[B"][source][category]
			result.append(int(options[roll(options.size())]))
		else:result.append(-1)
	return result

func offer_kind(station: Dictionary,colonist: bool) -> int:
	# Colonists post no deliveries, fish defences or capsule raids; rebels
	# post no escorts, intercepts, fish hunts, capsule raids or capsule
	# defences, and no fish defence once the war is won.
	while true:
		var kind: int=roll(15)
		if kind in [13,14] and station.id<=20:continue
		if colonist and kind in [13,14,6,12]:continue
		if not colonist and ((session.campaign.finished() and kind==6) or kind in [12,5,4,7,11]):continue
		return kind
	return 3

func generate(station: Dictionary) -> Array:
	var result: Array=[]
	var goods: Array=session.data.tables.goods
	var species: int=session.data.constants.ah["b:[S"].size()
	var colonist: bool=session.is_colonist_station(station.id)
	for _offer in 1+roll(8):
		var target := 0
		while target<=20:target=station.id if roll(100)<40 else destination(station)
		var kind: int=offer_kind(station,colonist)
		if kind in [13,14]:target=station.id
		var mission:=Mission.new()
		mission.kind=kind;mission.sponsor_faction=0 if colonist else 1
		var variant: bool=roll(100)<60
		var names: Array=session.data.name_pools[1 if variant else 0]
		mission.sponsor=str(names[roll(names.size())])
		mission.portrait=portrait(variant,mission.sponsor_faction)
		var difficulty := 0
		if kind in [13,14]:
			# A product (13) or a fish (14) that is actually traded, in a
			# quantity; deliveries are rated by the product's technology,
			# fishing orders by the size of the catch.
			while true:
				var id: int=species+1+roll(goods.size()-species-1) if kind==13 else roll(species)
				if id in UNDELIVERABLE or roll(100)>=int(goods[id][4]):continue
				mission.item_id=id;break
			mission.item_count=3+roll(22) if kind==14 else 1+roll(9)
			difficulty=int(Math.f32(Math.f32(float(mission.item_count)/25.0)*10.0)) if kind==14 else int(goods[mission.item_id][1])+2
		else:difficulty=1+roll(2 if session.campaign.chapter<10 else 9)
		if kind in [10,8]:
			while target==station.id:target=destination(station)
		elif kind in [12,11]:
			# Capsules are raided at rebel holdings and defended at colonist
			# ones; failing to find one, the offer becomes a pirate hunt.
			var attempts := 100
			while (session.campaign.rebel_stations[target] if kind==12 else not session.campaign.rebel_stations[target]) and attempts>0:
				target=destination(station);attempts-=1
			if attempts<=0:kind=3;mission.kind=3
		mission.destination=target;mission.destination_name=session.stations[target].name
		mission.difficulty=difficulty*clampi(session.counters.k/2,1,20)
		mission.jump_limit=roll(6)-1 if kind==8 else -1
		# The fee: 3,500 plus up to 9,500 by difficulty, raised by the
		# distance, adjusted by kind, and rounded to the fifty.
		var journey: float=preload("res://native/simulation/economy.gd").distance(station,session.stations[target])
		var reward: float=float(3500+int(Math.f32(Math.f32(float(mission.difficulty)/200.0)*9500.0)))
		reward=Math.f32(reward*Math.f32(1.0+Math.f32(journey/1500.0)))
		match kind:
			9:reward=Math.f32(reward*0.7)
			6,4,11:reward=Math.f32(reward*1.3)
			12,7:reward=Math.f32(reward*1.2)
			13:reward=Math.f32(Math.f32(reward/2.0)+float(mission.item_count*int(goods[mission.item_id][6])*3))
			8:
				if mission.jump_limit>=0:reward=Math.f32(reward+float(int(Math.f32(Math.f32(float(6-mission.jump_limit)*reward)/20.0))))
		mission.reward=to_fifty(reward)
		var deposit: int=int(Math.f32(Math.f32(reward/10.0)+float(roll(int(reward)/10))))
		if kind in [13,14]:deposit=int(Math.f32(float(deposit)*0.5))
		mission.deposit=to_fifty(float(deposit))
		var ratio: float=Math.f32(float(difficulty)/10.0)
		match kind:
			7:mission.parameters(roll(13),3+int(Math.f32(ratio*7.0)),0)
			6:
				var kind_of_fish := 0
				while kind_of_fish in [0,2,9,11,12]:kind_of_fish=roll(13)
				var total: int=15+roll(10)
				mission.parameters(kind_of_fish,total,total-int(Math.f32(Math.f32(1.0-ratio)*Math.f32(float(total)*0.35))))
			11:
				var total: int=5+roll(10)
				mission.parameters(0,total,total-int(Math.f32(Math.f32(1.0-ratio)*float(total))))
			12:
				var total: int=3+roll(3);mission.parameters(0,total,total)
		result.append(mission)
	return result

static func to_fifty(amount: float) -> int:
	# Rounded to the fifty the phone game's way: the remainder is added when
	# that lands on a fifty, otherwise taken off.
	var remainder: int=int(amount)%50
	return int(amount+remainder) if fmod(amount+remainder,50.0)==0 else int(amount-remainder)
