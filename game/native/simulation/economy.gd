extends RefCounted
## The stations' trade, as the phone game runs it: what a market stocks
## (cp), how goods are priced by how far they have come (dj), how ships and
## gear change hands (ai) and how goods are made (di). Every draw is from
## the session's stream, in the original's order: goods, then ships, then
## gear, then the job board.
const Math=preload("res://native/simulation/fixed_math.gd")
const Goods=preload("res://native/simulation/goods.gd")
const Ship=preload("res://native/simulation/ship_stats.gd")
const Contracts=preload("res://native/simulation/contracts.gd")
## The story's own goods, never on a shelf.
const STORY_GOODS := [36,37,38]
## The three imports a rebel market brings in between visits.
const IMPORTS := [33,34,35]
## The finished collection buys the Aquarius at this price.
const COLLECTORS_SHIP := 10
const COLLECTORS_PRICE := 50000
var session

func configure(owner_session) -> void:session=owner_session

func ship_price(vessel) -> int:
	return COLLECTORS_PRICE if vessel.id==COLLECTORS_SHIP and session.medals.complete_set() else vessel.price

static func distance_xy(a: Dictionary,b: Dictionary) -> int:
	return roundi(Vector2(a.x-b.x,a.y-b.y).length())

static func distance(a: Dictionary,b: Dictionary) -> float:
	if a.id==b.id:return 0.0
	return Math.f32(Vector3(a.x-b.x,a.y-b.y,int(a.percent)/10-int(b.percent)/10).length()*18.85)

func roll(bound: int) -> int:return session.rng.next_int(maxi(1,bound))

func generate(station: Dictionary) -> void:
	station.cargo=generate_goods(station)
	station.ships=generate_ships(station)
	station.equipment=generate_equipment(station)
	var board:=Contracts.new();board.session=session;station.missions=board.generate(station)
	station.generated=true

func generate_goods(station: Dictionary) -> Array:
	# Up to four lines of goods. A product is offered the more readily the
	# nearer its home station, only at a station of its technology, and
	# then only as often as its availability; a market that cannot fill a
	# line in a hundred tries stays empty.
	var result: Array=[]
	var goods: Array=session.data.tables.goods
	var first_product: int=session.data.constants.ah["b:[S"].size()+1
	for _line in roll(5):
		var tries := 0
		while true:
			var id: int=first_product+roll(goods.size()-first_product)
			while id in STORY_GOODS:id=first_product+roll(goods.size()-first_product)
			var item=session.make_goods(id,0)
			var chance := 0
			if not item.ingredient_counts.is_empty():chance=100-distance_xy(station,session.stations[item.origin_station])
			var accepted: bool=roll(100)<chance and item.tech_level<=station.tech
			if accepted:accepted=roll(100)<=item.availability if not result.any(func(other):return other.id==id) else false
			tries+=1
			if tries>100:return []
			if accepted:item.owned=5+roll(15);result.append(item);break
	return result

func generate_equipment(station: Dictionary) -> Array:
	# Two to five pieces, each drawn until one comes up whose rarity, plus
	# the chapter, beats the roll; the outfitting station of the map's
	# special holdings shows the whole catalogue.
	var result: Array=[]
	var catalogue: Array=session.data.tables.equipment
	var everything: bool=station.percent<0
	for index in (catalogue.size() if everything else 2+roll(4)):
		var id := index
		if not everything:
			while true:
				id=roll(catalogue.size())
				var rarity: int=int(catalogue[id][2])
				if rarity<=0 or result.any(func(item):return item.id==id):continue
				if roll(100)<rarity+session.campaign.chapter:break
		var item=session.make_equipment(id);item.station_price(station.tech);result.append(item)
	return result

func generate_ships(station: Dictionary) -> Array:
	# Up to three hulls, none more than a chapter or so ahead of the story
	# (a hull of index n needs chapter 5(n-2)); the shipyard holding shows
	# every hull. Rebel yards sell the upgraded variants. A station's
	# technology takes that many percent off.
	var result: Array=[]
	var hulls: Array=session.data.tables.ships
	var everything: bool=station.percent>100
	for index in (hulls.size() if everything else roll(4)):
		var id := index
		if not everything:
			while true:
				id=roll(session.data.constants.ah["e:[S"].size())
				if (id-2)*5<=session.campaign.chapter:break
		var vessel:=Ship.new();vessel.configure(hulls[id])
		vessel.upgraded=not session.is_colonist_station(station.id)
		var listed: int=ship_price(vessel)
		vessel.price=listed-int(Math.f32(Math.f32(float(station.tech)/100.0)*float(listed)))
		vessel.recompute();result.append(vessel)
	return result

func restock(station: Dictionary) -> void:
	# Between visits the imports come in, more of them as the story goes
	# on, and a little of everything on the shelves is sold.
	for id in IMPORTS:
		if Goods.contains(station.cargo,id):continue
		var count: int=roll(maxi(5,session.campaign.chapter/2))
		if count>0:station.cargo.append(session.make_goods(id,count))
	for item in station.cargo:
		var sold: int=roll(3)
		if sold<item.owned:item.owned-=sold

func price_goods(station: Dictionary) -> void:
	# A product is worth its floor at home and its ceiling at its market,
	# and in between by how far along that way this station lies; the
	# imports run the other way, from their market.
	for inventory in [session.ship.cargo,station.cargo]:
		for item in inventory:
			var home: Dictionary=session.stations[clampi(item.origin_station,0,session.stations.size()-1)]
			var away: Dictionary=session.stations[clampi(item.destination_station,0,session.stations.size()-1)]
			var spread:=distance_xy(home,away)
			var travelled:=distance_xy(away if item.id in IMPORTS else home,station)
			var proportion:=1.0 if spread==0 else minf(1.0,Math.f32(Math.f32(Math.f32(100.0/float(spread))*float(travelled))/100.0))
			item.price=item.minimum_price+int(Math.f32(proportion*float(item.maximum_price-item.minimum_price)))

func market(station: Dictionary) -> Array:
	price_goods(station);return Goods.market_rows(session.ship.cargo,station.cargo)

func trade(station: Dictionary,id: int,buying: bool) -> bool:
	# Colonists do not trade; they take a cargo at the fixed price on arrival.
	if session.is_colonist_station(station.id):return false
	var rows:=market(station)
	for item in rows:
		if item.id!=id:continue
		var payment: int=item.transact(buying,session.credits,session.ship.cargo_used,session.ship.capacity())
		if payment==0:return false
		session.credits+=payment;session.ship.set_cargo(Goods.owned_items(rows));station.cargo=Goods.owned_items(rows,true)
		session.medals.observe_credits(session.credits);return true
	return false

func has_equipment(id: int) -> bool:return session.ship.equipment.any(func(item):return item!=null and item.id==id)

func buy_equipment(station: Dictionary,item) -> int:
	# The notice on refusal, -1 when bought. One of each kind but weapons
	# and cargo units; one Eclipse ever.
	if item not in station.equipment:return 144
	if item.price>session.credits:return 85
	if not session.ship.has_slot():return 145
	if not session.ship.permits_kind(item.kind) or (item.id==42 and has_equipment(42)):return 144
	var installed=item.copy_stack()
	if not installed.discounted:session.counters.s+=1
	installed.station_price(station.tech,true);installed.discounted=true
	session.ship.equip(installed);session.credits-=item.price;station.equipment.erase(item)
	session.medals.observe_credits(session.credits);return -1

func sell_equipment(station: Dictionary,item) -> int:
	# The Eclipse stays until the war is won; a cargo unit cannot go while
	# the hold needs it.
	if item.id==42 and not session.campaign.finished():return 290
	if item not in session.ship.equipment:return 144
	if item.kind==5:
		var without: int=int(Math.f32(float(session.ship.capacity())-Math.f32(Math.f32(float(item.parameters[0])/100.0)*float(session.ship.base_cargo))))
		if without<session.ship.cargo_used:return 88
	session.ship.remove(item);session.credits+=item.price
	session.medals.observe_credits(session.credits)
	var sale=item.copy_stack();sale.station_price(station.tech,true);sale.discounted=true
	station.equipment.append(sale);return -1

func buy_ship(station: Dictionary,offered) -> int:
	# The old hull is taken in part exchange at its own price; its gear and
	# cargo move across, so the new hull needs the slots and the room.
	var old=session.ship
	if offered not in station.ships:return 85
	if ship_price(offered)>session.credits+ship_price(old):return 85
	var installed: Array=old.equipment.filter(func(item):return item!=null)
	if offered.slots<installed.size():return 86
	var room: int=int(Math.f32(float(offered.capacity())+Math.f32(Math.f32(float(old.cargo_percent)/100.0)*float(offered.capacity()))))
	if room<old.cargo_used:return 87
	var index: int=station.ships.find(offered)
	session.credits+=ship_price(old)-ship_price(offered)
	session.medals.observe_credits(session.credits)
	var purchased:=Ship.new();purchased.configure(session.data.tables.ships[offered.id]);purchased.upgraded=offered.upgraded
	# Owned, a hull is worth a fifth less than the catalogue.
	purchased.price=int(Math.f32(float(session.data.tables.ships[offered.id][3])/1.25))
	for item in installed:purchased.equip(item)
	purchased.set_cargo(old.cargo)
	session.ship=purchased
	var sold:=Ship.new();sold.configure(session.data.tables.ships[old.id]);sold.upgraded=old.upgraded
	sold.price=int(Math.f32(float(sold.price)/1.25));sold.recompute();station.ships[index]=sold
	return -1

func recipes(station: Dictionary) -> Array:
	# Every product of the station's technology, with how many the hold's
	# ingredients could make and how many ingredients are wanting.
	var owned: Dictionary={}
	for item in session.ship.cargo:owned[item.id]=int(owned.get(item.id,0))+item.owned
	var result: Array=[]
	for row in session.data.tables.goods:
		var recipe=session.make_goods(int(row[0]),0)
		if recipe.ingredients.is_empty() or recipe.ingredients.size()!=recipe.ingredient_counts.size() or recipe.tech_level>station.tech:continue
		var batches:=100000;var consumed:=0
		for index in recipe.ingredients.size():
			var cost:=int(recipe.ingredient_counts[index]);consumed+=cost
			if cost<=0:batches=0;break
			var available:=int(owned.get(recipe.ingredients[index],0))
			if available<cost:recipe.missing_ingredients+=1
			batches=mini(batches,available/cost)
		if consumed<1:batches=0
		recipe.owned=maxi(0,batches);result.append(recipe)
	return result

func manufacture(station: Dictionary,id: int,count: int) -> bool:
	if session.is_colonist_station(station.id) or count<=0:return false
	for recipe in recipes(station):
		if recipe.id!=id or recipe.owned<count:continue
		var inventory: Array=session.ship.cargo.map(func(item):return item.copy_stack(item.owned))
		var result: Array=Goods.owned_items(recipe.manufacture(inventory,count))
		var used:=0
		for item in result:used+=item.owned
		if used>session.ship.capacity():return false
		session.ship.set_cargo(result);session.counters.n+=count;session.goods_found[id]=true;price_goods(station);return true
	return false
