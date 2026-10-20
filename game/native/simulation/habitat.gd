extends RefCounted
## cl.a: the species living in a station's water and how common each is.
## Every species has a home station (its goods row's third field); its share
## falls by one per map unit away from home, nothing under fifty counts, the
## list is sorted by share and each entry then loses two per place. The
## result is the flat [species, percent, species, percent, ...] list the
## wildlife draw walks down, the first alga in it colouring the water.

## dt.a: the fixed-point square root, x·4096 ≥ 0 in and its root·64 out.
static func root(value: int) -> int:
	if value==0:return 0
	var step := 2147483647
	var guess := 2147483647
	for _i in 31:
		step>>=1
		var difference: int=value-((guess*guess)>>12)
		if difference>0:guess+=step
		elif difference<0:guess-=step
		else:return guess
	return guess

static func byte(value: int) -> int:
	return ((value+128)&255)-128

static func distance(ax: int, ay: int, bx: int, by: int) -> int:
	return root(((bx-ax)*(bx-ax)+(by-ay)*(by-ay))<<12)>>12

static func prevalence(data: Dictionary, station_id: int) -> Array:
	var tables: Dictionary=data.get("tables",{})
	var stations: Array=tables.get("stations",[])
	var goods: Array=tables.get("goods",[])
	# One entry per species, as many as ah.b has models.
	var count: int=data.get("constants",{}).get("ah",{}).get("b:[S",[]).size()
	if station_id<0 or station_id>=stations.size():return []
	var here: Array=stations[station_id]
	var species: Array=[];var shares: Array=[]
	for id in count:
		species.append(id)
		var share := 0
		if id<goods.size() and goods[id].size()>2:
			var home := int(goods[id][2])
			if home>=0 and home<stations.size():
				share=byte(100-distance(int(here[2]),int(here[3]),int(stations[home][2]),int(stations[home][3])))
		shares.append(share if share>=50 else 0)
	# The phone's bubble sort: stable, highest share first.
	var sorted := false
	while not sorted:
		sorted=true
		for i in range(1,count):
			if shares[i-1]>=shares[i]:continue
			var share: int=shares[i-1];shares[i-1]=shares[i];shares[i]=share
			var id: int=species[i-1];species[i-1]=species[i];species[i]=id
			sorted=false
	var result: Array=[]
	for i in count:
		result.append(species[i])
		result.append(byte(shares[i]-2*i) if shares[i]>0 else shares[i])
	return result

static func alga(data: Dictionary, station_id: int) -> Dictionary:
	"""cy.b: the most common of the five algae (13..17) here and its share.
	With none in reach the first alga listed still wins, at nothing."""
	var table: Array=prevalence(data,station_id)
	for i in range(0,table.size(),2):
		if int(table[i])>=13 and int(table[i])<=17:return {"species":int(table[i]),"percent":int(table[i+1])}
	return {}
