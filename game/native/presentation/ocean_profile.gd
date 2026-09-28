extends RefCounted
## Regional hues come from the imported plankton palette and origin stations.
## Their strength and continuous blending are presentation choices. Sampling
## never consumes the campaign RNG or changes the gameplay habitat tables.
static func corner(point: Vector2, salt: float) -> float:
	return fposmod(sin(point.dot(Vector2(127.1,311.7))+salt)*43758.5453,1.0)

static func field(point: Vector2, salt: float=0.0) -> float:
	var cell := point.floor()
	var blend := point-cell
	blend=blend*blend*(Vector2.ONE*3.0-blend*2.0)
	return lerpf(lerpf(corner(cell,salt),corner(cell+Vector2.RIGHT,salt),blend.x),
		lerpf(corner(cell+Vector2.DOWN,salt),corner(cell+Vector2.ONE,salt),blend.x),blend.y)

static func sample(chart: Vector2, data: Dictionary={}) -> Dictionary:
	var stations: Array=data.get("tables",{}).get("stations",[])
	var goods: Array=data.get("tables",{}).get("goods",[])
	var palette: Array=data.get("water_palette",[])
	var hue := Vector3.ZERO;var total := 0.0;var suspended := 0.0
	for i in mini(5,palette.size()):
		var species := i+13
		if species>=goods.size() or palette[i].size()!=3:continue
		var origin := int(goods[species][2])
		if origin<0 or origin>=stations.size():continue
		var station: Array=stations[origin]
		var influence := maxf(0.0,1.0-chart.distance_to(Vector2(station[2],station[3]))/50.0)
		# The original selects the nearest plankton region. A soft overlap
		# avoids a visible seam while swimming across its station boundaries.
		var weight := pow(influence,4.0)
		hue+=Vector3(palette[i][0],palette[i][1],palette[i][2])*weight
		total+=weight;suspended=maxf(suspended,influence)
	var tint := Vector3.ONE
	if total>.00001:
		hue/=total
		hue/=maxf(1.0,maxf(hue.x,maxf(hue.y,hue.z)))
		# Attenuate gently instead of amplifying green over the whole scene.
		tint=tint.lerp(hue,.22*smoothstep(0.0,.3,suspended))
	var direction := field(chart/22.0,91.0)*TAU
	return {"tint":tint,
		"haze":lerpf(.96,1.06,suspended),"snow":lerpf(.9,1.1,suspended),
		"sun":lerpf(1.0,.86,suspended),
		"current":Vector3(cos(direction),0,sin(direction))*lerpf(.15,.38,suspended)}

static func bloom(absolute_position: Vector3) -> float:
	# Small, sparse patches inside the much larger water masses. Depth offsets
	# the pattern so a descent does not follow a luminous column indefinitely.
	var point := Vector2(absolute_position.x,absolute_position.z)+Vector2(absolute_position.y*.37,absolute_position.y*.21)
	return smoothstep(.65,.86,field(point/190.0,137.0))*smoothstep(.3,.65,field(point/730.0,59.0))
