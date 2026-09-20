extends RefCounted
## Station assembly as the original grows it: a tree of imported modules from
## the record's seed. A hangar of either kind sits at the root, turned about;
## every child stands 63.09 m from its parent along one of the parent's
## sockets, facing back into it; hangars and habitats may carry a like habitat,
## a bottom module, or a top or cannon at 45 m above or below; twenty parts at
## most. Part transforms stay in source units, 0.01 m.
const Random = preload("res://native/simulation/linear_congruential.gd")
const Math = preload("res://native/simulation/fixed_math.gd")
var rng := Random.new()
var sine: Array = []
var parts: Array = []
var remaining := 20
## Socket yaws per module family: bridges pass straight through; the
## engine, side habitat and starter are ends; habitats fan out.
const PORTS := [[0,2048],[0],[682,2048,-682],[0,1024,2048,3072],[682,-682],[0,1024,3072]]
const PORT_TABLE := {3301:0,3302:0,3305:2,3306:3,3307:4,3308:5}
## What may hang off a bridge, and what may hang off a hangar or habitat.
const CANDIDATES := [[3301,3302,3304,3309,3310,3305,3306],[3301,3302,3304,3309,3310]]
const SPACING := 6309
const STACK := 4500
const HANGARS := [3307,3308]
const HUBS := [3305,3306,3307,3308]

func generate(station_id: int, depth: int, tech: int, sine_table: Array) -> Array:
	sine=sine_table; parts=[]; remaining=19
	rng.seed_from(station_id+depth+tech)
	var root := 3307 if rng.next_int(2)==0 else 3308
	var part := {"model_id":root,"yaw":2048,"origin":[0,0,0],"upper":false}
	parts.append(part)
	branch(part)
	return parts

func chance(model_id: int) -> int:
	return {3301:90,3302:90,3304:30,3309:30,3310:30,3305:70,3306:50,3307:70,3308:70}.get(model_id,50)

func branch(part: Dictionary) -> void:
	var id: int = part.model_id
	if not PORT_TABLE.has(id): return
	var ports: Array = PORTS[PORT_TABLE[id]]
	var hub := id in HUBS
	var hangar := id in HANGARS
	var candidates: Array = CANDIDATES[1 if hub else 0]
	var count := ports.size()+(2 if hub else 0)
	var connected: Array = []
	connected.resize(count); connected.fill(false)
	for i in count:
		# A hangar fills every socket; the rest roll for each. The first socket
		# is the one that faces the parent, and the roll for the stacked slots
		# clears it on the hangar too, which is why a hangar never uses it.
		if hangar and i<=count-3:
			connected[i]=true
			continue
		connected[i]=rng.next_int(100)<chance(id)
		connected[0]=false
	for i in count:
		if remaining<=0: return
		if not connected[i]: continue
		var child_id := 3301
		var vertical := hub and i>count-3
		if vertical:
			# Only the outermost habitat of a run stacks, and only downward
			# unless it is the hangar itself, which stacks both ways.
			if not hangar and ((i==count-1 and part.upper) or not part.upper): return
			child_id=3305 if id in [3305,3307] else 3306
			if rng.next_int(2)==0:
				if i==count-1:
					if part.upper and not hangar: return
					child_id=3311 if rng.next_int(2)==0 else 3303
				else:
					if not part.upper and not hangar: return
					child_id=3300
		else:
			if not hub: child_id=3305 if rng.next_int(2)==0 else 3306
			# The original tests the candidate it holds, then draws the next
			# regardless: what it keeps is the draw made after acceptance.
			var accepted := false
			while not accepted:
				accepted=rng.next_int(100)<chance(child_id)
				child_id=candidates[rng.next_int(candidates.size())]
		remaining-=1
		var yaw: int = part.yaw
		var offset: Array = [0,STACK if i==count-1 else -STACK,0]
		if not vertical:
			yaw+=2048-int(ports[i])
			# The spacing turned through the socket's heading in the source's
			# own arithmetic: its sine table and a floor on the product, which
			# a rounded float rotation misses by a centimetre or so.
			var heading: int=int(part.yaw)-int(ports[i])
			offset=[(table_sine(heading)*SPACING)>>12,0,(table_sine(heading+1024)*SPACING)>>12]
		var child := {"model_id":child_id,"yaw":yaw,"origin":[part.origin[0]+offset[0],part.origin[1]+offset[1],part.origin[2]+offset[2]],"upper":i!=count-1}
		parts.append(child)
		branch(child)

func table_sine(angle: int) -> int:
	"""The imported quarter-wave table, unfolded as the original reads it."""
	angle=angle&0xfff
	if angle>=3072: return -int(sine[4096-angle])
	if angle>=2048: return -int(sine[angle-2048])
	if angle>=1024: return int(sine[2048-angle])
	return int(sine[angle])

static func seed_depth(percent: int) -> int:
	"""The depth the original derives from a station's percentage, in the
	single-precision arithmetic it uses, which lands a metre short of the
	round figure for some stations. The seed is made from this depth, so a
	round figure would grow a different station."""
	return 15000+int(Math.f32(Math.f32(float(percent)/100.0)*15000.0))

static func animation_range(model_id: int, colonist: bool) -> Array:
	"""The frames the original selects for a part: the emblem and configuration
	a holding shows are its faction's, and hangars, caps and engines run a short
	loop of their own. Bridges and the cannon have no animation."""
	match model_id:
		3307,3308: return [0,2] if colonist else [3,5]
		3305,3306,3309,3310: return [0,0] if colonist else [2,2]
		3300,3311: return [0,1] if colonist else [2,3]
		3304: return [0,2]
	return []

static func frame_interval(model_id: int) -> int:
	return 60 if model_id==3304 else (800 if model_id==3300 else 170)
