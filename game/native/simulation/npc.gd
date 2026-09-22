extends RefCounted
## A ship of the water, as the phone game drives it (bl): it takes the
## first live target in its list, or now and then one at random, every five
## seconds; runs at it, veers off when it gets within eighty metres, and
## fires whenever its nose is on it inside three hundred and fifty metres.
## Pirates past the fifteenth chapter throw in bursts of speed. A dead ship
## becomes a wreck that sinks, and can be hooked for its salvage until it is
## three hundred metres down.
const Math = preload("res://native/simulation/fixed_math.gd")
const Transform = preload("res://native/simulation/ship_transform.gd")
const Health = preload("res://native/simulation/health.gd")
const Goods = preload("res://native/simulation/goods.gd")
## The reach of a ship's attention, and of its guns, in units.
const NOTICE_DISTANCE := 50000
const GUN_DISTANCE := 35000
const VEER_DISTANCE := 8000
const WAKE_DISTANCE := 10000
const WRECK_SINK := 30000
var pose := Transform.new()
var health := Health.new()
var radius := 2000
var model_id := 0
var original_model_id := 0
var faction := 0
var hostile := false
var excluded_from_objectives := false
var state := 0
var targets: Array = []
var weapons: Array = []
var shapes: Array = []
var obstacle_groups: Array = []
var route = null
var player = null
var rng
var base_speed := 2.1
var base_turn := 2.0
var speed := 2.1
var turn_speed := 2.0
var smart_boost := false
var boost_timer := 0
var boost_duration := 0
var target_timer := 0
var target_index := 0
var target_lock := false
var straight := false
var following := false
var target = null
var target_position: Array = [0,0,0]
var collision_enabled := true
var origin: Array = [0,0,0]
var capturable := true
var protected_target := false
var escaped := false
var towing := false
var subdued := false
var is_creature := false
var render_scale: Array = [4096,4096,4096]
var loot = null
var explosion_ms := 0
var explosion_duration := 4000
var explosion_delays: Array = [0]
var explosion_offsets: Array = [[0,0,0]]
var has_explosion := true
var events: Array = []
var trail := preload("res://native/simulation/bubble_trail.gd").new()

func configure(id: int,team: int,enemy: bool,location: Array,data: Dictionary,chapter: int,source_rng) -> void:
	model_id=id;original_model_id=id;faction=team;hostile=enemy;rng=source_rng
	pose.math.sine_table=data.constants.dt["a:[S"];set_position(location)
	# The aquar (19) is a creature-ship: it leaves no wreck, never boosts and
	# turns more slowly than a hull does.
	capturable=id!=19;smart_boost=enemy and chapter>15 and id!=19
	base_speed=Math.f32(2.1);base_turn=2.0;speed=base_speed;turn_speed=1.5 if id==19 else base_turn
	# What it carries: any goods but the story's own, each as likely as its
	# availability, one to seven units (a single figure for the collectible).
	while true:
		var item: int=rng.next_int(data.tables.goods.size())
		if item in [36,37,38]:continue
		if rng.next_int(100)>=int(data.tables.goods[item][4]):continue
		loot=Goods.new();loot.configure(data.tables.goods[item])
		loot.owned=1 if item==40 else 1+rng.next_int(7)
		loot.price=loot.maximum_price
		break

static func within(a: Array,b: Array,distance: int) -> bool:
	# Reach is a cube, as the phone game measures it.
	for axis in 3:
		var difference: int=a[axis]-b[axis]
		if difference>=distance or difference<=-distance:return false
	return true

func dormant() -> void:state=5;health.enabled=false
func activate() -> void:state=1;health.enabled=true
func protect(value: bool) -> void:
	protected_target=value
	if value:loot=null
func rescued() -> bool:return protected_target and not capturable
func set_position(value: Array) -> void:
	pose.origin=value.duplicate();origin=value.duplicate()
func set_speed(value: int) -> void:
	smart_boost=false;base_speed=float(value);speed=base_speed
func release() -> void:pass
func hook(_slow: int) -> void:pass

func capture(session) -> bool:
	# Taking a wreck spends it whether or not its salvage fits.
	capturable=false;health.enabled=false;state=4
	if protected_target:events.append("rescued");return true
	if loot!=null and session.ship.can_carry(loot.owned):
		session.counters.r+=1
		session.ship.set_cargo(Goods.merge(session.ship.cargo,[loot]))
		events.append("salvaged")
	else:events.append("cargo_full")
	return true

func live(actor) -> bool:
	return actor.health.enabled and actor.health.hull>0

func choose_target(delta_ms: int) -> void:
	target_timer+=delta_ms
	if targets.is_empty():
		# Nothing to fight: follow the route, or stand down without one.
		if route!=null:
			route.advance(pose.origin)
			if route.current()!=null:target_position=route.current().duplicate();following=true
		else:state=5
		return
	if not target_lock:target_index=-1
	elif target_index>=0 and not targets[target_index].health.enabled:target_lock=false
	target=null
	if target_timer>5000:
		# Every five seconds: a one in five chance of holding its course, and
		# a three in ten chance of picking a target at random, kept only if
		# that one is alive and within notice.
		straight=false if straight else rng.next_int(100)<20
		target_timer=0
		if rng.next_int(100)<30 and targets.size()>1:
			target_lock=false
			for _try in 5:
				target_index=rng.next_int(targets.size())
				if targets[target_index].health.enabled and within(pose.origin,targets[target_index].pose.origin,NOTICE_DISTANCE):target_lock=true;break
			if not target_lock:target_index=0
		else:target_index=0
		if not live(targets[target_index]) or not within(pose.origin,targets[target_index].pose.origin,NOTICE_DISTANCE):target_index=-1
	elif not target_lock:
		for index in targets.size():
			if live(targets[index]) and within(pose.origin,targets[index].pose.origin,NOTICE_DISTANCE):target_index=index;break
	following=false
	if target_index==-1 and route!=null:
		if route.current()!=null and health.enabled:
			route.advance(pose.origin)
			if route.current()!=null:target_position=route.current().duplicate();following=true
		else:
			target_index=0;target=targets[0];target_position=target.pose.origin.duplicate()
	else:
		target_index=maxi(0,target_index);target=targets[target_index];target_position=target.pose.origin.duplicate()

func advance(delta_ms: int) -> void:
	if state==4 and not capturable:health.enabled=false;return
	boost_timer+=delta_ms
	var exhaust: Array=pose.origin.duplicate()
	if state not in [3,4]:
		var heading: Array=Math.normalize_vector(pose.forward)
		for axis in 3:exhaust[axis]-=Math.i32(heading[axis]<<12)/32768
	trail.advance(exhaust,delta_ms,rng)
	if state not in [3,4]:choose_target(delta_ms)
	else:target_timer+=delta_ms
	var difference: Array=Math.subtracted(target_position,pose.origin)
	# A friendly ship waiting in the wings wakes when the player comes within
	# a hundred metres of it.
	if not hostile and state==5 and player!=null:
		difference=Math.subtracted(player.pose.origin,pose.origin)
		if within(difference,[0,0,0],WAKE_DISTANCE):activate()
	for shape in shapes:shape.origin=pose.origin.duplicate()
	if health.hull<=0 and state not in [3,4]:
		events.append("killed");state=3;explosion_ms=0
		if capturable:
			# The wreck lies level where the ship died.
			origin=pose.origin.duplicate();model_id=17
			var sine: Array=pose.math.sine_table
			pose=Transform.new();pose.math.sine_table=sine;pose.origin=origin.duplicate()
	match state:
		5:
			if hostile and within(difference,[0,0,0],NOTICE_DISTANCE):activate()
		0:state=1
		1:
			if smart_boost:
				# Every five seconds a pirate may go to full speed for five to
				# eight seconds, turning wider while it does.
				if boost_timer>5000 and speed!=4.0:
					if rng.next_int(100)<20:boost_duration=rng.next_int(3000)+5000
					boost_timer=0;speed=4.0;turn_speed=Math.f32(1.3)
				if speed==4.0 and boost_timer>boost_duration:boost_timer=0;speed=base_speed;turn_speed=base_turn
			# Close in on a target, it breaks off to its own right.
			if target!=null and not following and within(difference,[0,0,0],VEER_DISTANCE):difference=pose.right.duplicate()
			var desired: Array=Math.normalize_vector(difference)
			var local: Array=[Math.dot_long(pose.right,desired),-Math.dot_long(pose.up,desired),Math.dot_long(pose.forward,desired)]
			if not following and target!=null and absi(local[0])<500 and absi(local[1])<500 and within(target_position,pose.origin,GUN_DISTANCE):
				if live(target):
					for weapon in weapons:weapon.request_fire(pose,delta_ms)
				else:target_lock=false
			if not straight:
				var change: Array=Math.normalize_vector(Math.subtracted(desired,pose.forward))
				change=Math.scaled(change,int(Math.f32(float(delta_ms)*turn_speed)))
				pose.face(Math.normalize_vector(Math.added(pose.forward,change)))
			pose.advance(int(Math.f32(float(delta_ms)*speed)))
		3:
			collision_enabled=false
			if not has_explosion or explosion_ms>explosion_duration:state=4
		4:
			if capturable and health.enabled:
				if not towing:pose.origin[1]+=delta_ms/2
				if pose.origin[1]>origin[1]+WRECK_SINK:escaped=true;health.enabled=false
			else:health.enabled=false
	if collision_enabled:
		for volume in obstacle_groups:
			if not volume.contains(pose.origin):continue
			var away: Array=volume.avoidance_normal(pose.origin)
			away=Math.scaled(Math.subtracted(away,pose.forward),int(Math.f32(float(delta_ms)*5.0)))
			pose.face(Math.normalize_vector(Math.added(pose.forward,away)))
			pose.advance(int(Math.f32(float(delta_ms)*speed)))
	if state==3:explosion_ms+=delta_ms

func contains(point: Array) -> bool:
	if state in [3,4]:return false
	return shapes.any(func(shape):return shape.contains(point))

func avoidance_normal(point: Array) -> Array:
	return shapes[0].avoidance_normal(point) if not shapes.is_empty() else [0,0,0]
