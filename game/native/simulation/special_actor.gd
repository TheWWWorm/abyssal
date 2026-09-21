extends "res://native/simulation/npc.gd"
## The water's other things, as the phone game keeps them: mines (d) that
## bob at their moorings and arm when a ship comes within thirty metres,
## going off two seconds later; debris (ci) of random size and set; supply
## capsules (df) that fall through the water and are dropped in again from
## the top once they are past its floor; and freighters (cf), long hulls
## that wake when anyone comes within five hundred metres and blow up in a
## staggered chain when they die.
var kind := "debris"
var moving := false
var timer := 0
var acceleration := 0
var trigger_delta: Array=[0,0,0]
var mine_yaw := 0
var animation_range: Array=[]
## The mine's mooring, and the rise of its bob: the phone game lifted it by
## sin(t)/64 a frame, which over half a cycle at its frame rate comes to
## about thirteen metres.
var mooring: Array=[]
const BOB_RISE := 632
const MINE_TRIGGER := 3000
const MINE_FUSE := 2000
const MINE_BLAST := 25
const CAPSULE_FLOOR := 75000

func configure_special(type_name: String,id: int,enemy: bool,location: Array,data: Dictionary,source_rng) -> void:
	kind=type_name;model_id=id;original_model_id=id;hostile=enemy;rng=source_rng
	pose.math.sine_table=data.constants.dt["a:[S"];set_position(location)
	capturable=false
	match kind:
		"debris":
			var size: int=4096+rng.next_int(8096);render_scale.fill(size)
			pose.set_euler(location[0],location[1],location[2])
		"capsule":
			# Dropped from anywhere above the floor, twice life size, nose down;
			# its resting mark, thirty metres below the drop, is where it
			# starts again each time.
			origin[1]+=3000
			pose.origin[1]=rng.next_int(CAPSULE_FLOOR);render_scale.fill(8192)
			pose.set_euler(-1024,0,0)
		"mine":
			state=5;animation_range=[0,0];mooring=location.duplicate()

func set_position(location: Array) -> void:
	super.set_position(location)
	if kind=="mine":mooring=location.duplicate()
	for shape in shapes:shape.origin=location.duplicate()

func reset_capsule() -> void:
	state=0;health.enabled=true;pose.origin=origin.duplicate();acceleration=0
	health.hull=health.max_hull

func detonate() -> void:
	# The blast reaches the ship that set it off if it is still within thirty
	# metres, measured as the phone game does, on the signed offsets.
	if target!=null and trigger_delta.all(func(value):return value<MINE_TRIGGER):target.health.damage(MINE_BLAST)
	state=999;health.enabled=false;events.append("killed")

func capture(_session) -> bool:
	if kind=="mine":detonate()
	return true

func advance(delta_ms: int) -> void:
	match kind:
		"mine":advance_mine(delta_ms)
		"capsule":advance_capsule(delta_ms)
		"freighter":advance_freighter(delta_ms)
		"debris":
			if health.hull<=0 and state not in [3,4]:
				health.enabled=false;state=3;events.append("debris_destroyed")
			if state==3:
				if not has_explosion or explosion_ms>explosion_duration:state=4
				else:explosion_ms+=delta_ms

func advance_capsule(delta_ms: int) -> void:
	if health.hull<=0 and state not in [3,4]:
		health.enabled=false;state=3;events.append("capsule_destroyed")
	match state:
		0:
			# Falling ever faster, until the floor, then dropped in again.
			pose.origin[1]+=delta_ms+acceleration;acceleration+=1
			if pose.origin[1]>CAPSULE_FLOOR:reset_capsule()
		3:
			if not has_explosion or explosion_ms>explosion_duration:state=4
			else:explosion_ms+=delta_ms
		4:reset_capsule()

func advance_freighter(delta_ms: int) -> void:
	if moving and state not in [3,4]:
		pose.advance(delta_ms)
		for shape in shapes:shape.origin=pose.origin.duplicate()
	if health.hull<=0 and state not in [3,4]:
		health.enabled=false;state=3;events.append("killed")
	if state==5:
		target=null
		for actor in targets:
			if actor.health.enabled and within(origin,actor.pose.origin,NOTICE_DISTANCE):
				target=actor;target_position=actor.pose.origin.duplicate();break
		if within(target_position,origin,NOTICE_DISTANCE):activate()
	elif state==3:
		if not has_explosion or explosion_ms>explosion_duration:state=4
		else:explosion_ms+=delta_ms

func advance_mine(delta_ms: int) -> void:
	if state==4:return
	if state not in [3,4,999]:
		if not targets.is_empty():
			var found := 0
			target=null
			for index in targets.size():
				if not targets[index].health.enabled:continue
				trigger_delta=Math.subtracted(pose.origin,targets[index].pose.origin)
				if state==1 or not within(trigger_delta,[0,0,0],MINE_TRIGGER):continue
				state=1;animation_range=[1,1];timer=0;health.hull=health.max_hull;found=index;break
			target=targets[found]
		if health.hull<=0 and state not in [5,3,4]:
			health.enabled=false;state=3;timer=0;events.append("killed")
	timer+=delta_ms
	if not mooring.is_empty():
		pose.origin[0]=mooring[0];pose.origin[2]=mooring[2]
		pose.origin[1]=mooring[1]+roundi(BOB_RISE*(1.0-cos(timer*TAU/4096.0)))
	match state:
		0:state=5
		5:health.hull=health.max_hull
		1:
			# Armed: it spins a full turn over its two-second fuse.
			timer+=delta_ms;mine_yaw+=delta_ms<<1;pose.set_euler(0,mine_yaw,0)
			if timer>MINE_FUSE:detonate()
		999:
			for axis in 3:render_scale[axis]=Math.product(render_scale[axis],2048)
			mine_yaw+=delta_ms<<1;pose.set_euler(0,mine_yaw,0)
			if not has_explosion or explosion_ms>explosion_duration:state=4;health.hull=0
			else:explosion_ms+=delta_ms
		3:
			timer+=delta_ms
			if timer>2000:state=4;health.hull=0

func contains(point: Array) -> bool:
	if kind!="freighter" or state==4:return false
	return shapes.any(func(shape):return shape.contains(point))
