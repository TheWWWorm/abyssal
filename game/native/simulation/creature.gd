extends RefCounted
## A creature of the water, as the phone game keeps it (af/cj): it swims its
## own way until it is hurt or hooked, then flees, thrashing, until its
## strength is spent; on the line it is subdued, off it it calms. Killed, it
## turns to a drifting carcass. The water is never empty: any creature the
## camera leaves four hundred metres behind is set down again three hundred
## metres out, so there is always something to catch. Units are the game's
## own, a centimetre each, and directions are Q12.
const Math = preload("res://native/simulation/fixed_math.gd")
const Transform = preload("res://native/simulation/ship_transform.gd")
const Health = preload("res://native/simulation/health.gd")
## How far a creature may drift from the camera before it is placed anew,
## and how far out it is then set.
const LEAVE_DISTANCE := 40000
const RETURN_DISTANCE := 30000
## A carcass rises a third of a unit a millisecond.
## Set when the creature has just been set down somewhere new; the view
## takes it as the cue to bring the body in out of the haze.
var fresh := true
const CARCASS_RISE := 3
var pose := Transform.new()
var turn := Transform.new()
var secondary_pose := Transform.new()
## The second part's pose before its own swing, and that swing as an axis
## and an angle in the game's units, for a view that bends the part at
## the join rather than turning it rigidly.
var hinge_pose := Transform.new()
var hinge_axis := ""
var hinge_angle := 0
var health := Health.new()
var radius := 1500
var model_id := 0
var secondary_model := -1
var species := 0
var is_creature := true
var base_mass := 0
var resistance := 0
var mass := 0
var state := 0
var stationary := false
var constrained := false
var phase := 0
var struggle_total := 0
var struggle_remaining := 0
var struggle_time := 0
var speed := 1.0
var previous_hull := 0
var fleeing := false
var hooked := false
var subdued := false
var towing := false
var capturable := true
var meat := false
var render_scale: Array = [4096,4096,4096]
var secondary_scale: Array = [4096,4096,4096]
## Visual pitch/yaw/roll of the body about its own heading, in 4096 units.
var render_tilt: Array = [0.0,0.0,0.0]
var events: Array = []

func configure(id: int,row: Array,rng,sine: Array,center: Array=[0,0,0]) -> void:
	model_id=id;species=int(row[0]);base_mass=int(row[1]);resistance=int(row[2])
	pose.math.sine_table=sine;turn.math.sine_table=sine
	health.configure(base_mass*2,0,0);previous_hull=health.hull
	# The algae stand on the bed, pitched over, and weigh what the table says;
	# everything else varies a quarter either way.
	stationary=id in [4443,4444,4445,4446,4447]
	if stationary:pose.set_euler(256,0,0);mass=base_mass
	else:mass=maxi(1,base_mass+int(Math.f32(Math.f32(float(-25+rng.next_int(50))/100.0)*float(base_mass))))
	speed=cruise_speed()
	# A creature fights 2.1 s, and a tenth of that again for each point of
	# its resistance.
	struggle_total=2100+int(Math.f32(Math.f32(float(resistance)/10.0)*2100.0))
	if center==[0,0,0]:
		# Anywhere in the six hundred metre cube about the region's centre,
		# heading anywhere.
		pose.face(Math.normalize_vector([-4096+rng.next_int(8192),-4096+rng.next_int(8192),-4096+rng.next_int(8192)]))
		pose.origin=[-30000+rng.next_int(59000),-30000+rng.next_int(59000),-30000+rng.next_int(59000)]
	else:
		pose.origin=[center[0]-8000+rng.next_int(16000),center[1]-8000+rng.next_int(16000),center[2]-8000+rng.next_int(16000)]
	if id in [4424,4427,4430,4432,4434,4440,4436,4438]:secondary_model=id+1
	secondary_pose=pose.copy_pose();release()

func cruise_speed() -> float:
	return Math.f32(1.0+Math.f32(float(resistance)/2.2))

func release() -> void:
	struggle_remaining=0 if stationary else struggle_total
	struggle_time=0;fleeing=false;hooked=false

func hook(slow_percent: int) -> void:
	# On the line the creature runs, slowed by the harpoon's paralysis.
	fleeing=true;hooked=true;struggle_time=0
	speed=Math.f32(cruise_speed()*Math.f32(1.0-Math.f32(float(slow_percent)/100.0)))

func countdown() -> int:
	return struggle_remaining/1000+1

func capture(session) -> bool:
	if state==4:
		# A carcass is a third of the animal in fish meat, if there is room.
		if session.ship.can_carry(mass):
			session.counters.p+=mass
			session.ship.set_cargo(preload("res://native/simulation/goods.gd").merge(session.ship.cargo,[session.make_goods(18,mass)]))
			events.append("meat_collected")
		else:events.append("cargo_full")
		meat=false;health.enabled=false;capturable=false;render_scale.fill(0);secondary_scale.fill(0)
		return true
	if not session.ship.can_carry(mass) or not session.register_catch(species,mass):
		render_scale=[4096,4096,4096];secondary_scale=[4096,4096,4096];hooked=false;subdued=false
		events.append("cargo_full");return false
	health.enabled=false;capturable=false;render_scale.fill(0);secondary_scale.fill(0)
	events.append("caught");events.append("depleted");return true

func advance(delta_ms: int,rng,camera_origin: Array,ahead: Array=[]) -> void:
	if not health.enabled or subdued:return
	var movement := 0
	if not stationary:
		movement=delta_ms
		# A wound sends it running.
		if previous_hull>health.hull and state!=4:fleeing=true
		previous_hull=health.hull
	if fleeing:
		# A fleeing creature gathers speed, and for the first two seconds of
		# each bout of struggle turns the way it last chose; then it spends
		# a second of its strength and picks a new turn.
		speed=Math.f32(speed+0.01)
		struggle_time+=delta_ms
		movement=int(Math.f32(float(delta_ms)*speed))
		if struggle_time<2000:pose.compose_rotation(turn)
		else:
			struggle_remaining-=struggle_time>>1
			if not constrained:
				var amount: int=movement>>1
				turn.set_euler(-(amount>>1)+rng.next_int(maxi(1,amount)),-(amount>>1)+rng.next_int(maxi(1,amount)),0)
			struggle_time=0
		if struggle_remaining<=0:
			if hooked:subdued=true
			else:release()
	if not stationary and health.hull<=0 and state!=4:
		state=4;events.append("killed");events.append("depleted")
		if capturable:
			# What is left floats up, level, as a third of the mass in meat.
			model_id=14;secondary_model=-1;meat=true;mass=mass/3+1
			var resting: Array=pose.origin.duplicate()
			pose=Transform.new();pose.math.sine_table=turn.math.sine_table;pose.origin=resting
			render_scale=[4096,4096,4096];secondary_scale=[4096,4096,4096];render_tilt=[0.0,0.0,0.0]
		return
	if state==4:
		if not hooked:pose.origin[1]+=delta_ms/CARCASS_RISE
		secondary_pose=pose.copy_pose()
		if Math.length_of(Math.subtracted(camera_origin,pose.origin))>LEAVE_DISTANCE:health.enabled=false
		return
	if not stationary and model_id!=4429:
		pose.advance(movement)
		phase=(phase+delta_ms)&0xFFF
		keep_upright()
	animate(delta_ms)
	if not constrained and Math.length_of(Math.subtracted(camera_origin,pose.origin))>LEAVE_DISTANCE:
		reappear(rng,camera_origin,ahead)

func keep_upright() -> void:
	# The phone game's creatures turn by pitch and yaw alone, so one that
	# pitches through the vertical comes out swimming on its back until it
	# happens to pitch through again. A fish is kept belly down here: its
	# heading is its own, its roll is not.
	# Any roll at all is taken out, not only a full inversion: a fish on
	# its side is no better than one on its back.
	var heading: Vector3=Math.vector(pose.forward)
	if absf(heading.normalized().y)>.98:return
	pose.face(pose.forward)

func reappear(rng,camera_origin: Array,_ahead: Array=[]) -> void:
	# Set down three hundred metres from the camera, on a bearing that keeps
	# nearer the camera's level than the vertical, heading somewhere within
	# a hundred and fifty metres of it, as af does: in front as readily as
	# behind, so a traveller sees the water ahead fill. The view brings a
	# creature so set down in out of the haze rather than all at once.
	var bearing: Array=[-2048+rng.next_int(4096),-2048+rng.next_int(4096),-2048+rng.next_int(4096)]
	bearing[1]>>=1
	bearing=Math.normalize_vector(bearing)
	pose.origin=Math.added(Math.scaled(bearing,RETURN_DISTANCE),camera_origin)
	pose.face(Math.normalize_vector([-15000+rng.next_int(30000)-bearing[0],-15000+rng.next_int(30000)-bearing[1],-15000+rng.next_int(30000)-bearing[2]]))
	release();previous_hull=health.hull;fresh=true

func animate(_delta_ms: int=0) -> void:
	# The phone game's own life for each species (af.a): a body scale that
	# breathes, a tail hinged on the body, and a slow wander of the body itself.
	# The cycle is 4096 ms, and every wave is the game's sine in 4096 units.
	secondary_pose=pose.copy_pose()
	render_scale=[4096,4096,4096];secondary_scale=[4096,4096,4096]
	var s:=pose.math.sine(phase)
	match model_id:
		4422:render_scale=[4096,maxi(48,absi(s)/3)*signi(s if s!=0 else 1),4096]
		4426:render_scale=[4096,4096+(pose.math.sine((phase<<1)&0xFFF)>>2),4096]
		4442:render_scale=[4096,4096,4096+(pose.math.sine((phase<<2)&0xFFF)>>2)]
		4424:secondary_scale=[4096,4096,4096+(pose.math.sine((phase<<2)&0xFFF)>>2)]
		4438:secondary_scale=[4096,4096+(pose.math.sine((phase<<2)&0xFFF)>>2),4096]
	# The original turns the body a little every frame, sin/128 or sin/256 of
	# a turn at its fifteen frames a second, which sums to a swing about the
	# heading of about 316 or 158 units either way. That swing is written out
	# directly, centred on the heading, and never fed back into the AI.
	var swing:=-pose.math.cosine(phase)
	render_tilt=[0.0,0.0,0.0]
	match model_id:
		4423:render_tilt[1]=swing*316.0/4096.0
		4427,4432,4436:render_tilt[0]=swing*158.0/4096.0
		4430,4434,4440:render_tilt[1]=-swing*316.0/4096.0
	# Every creature model comes out of the JAR the other way up from how
	# the engine reads the hulls and stations, so each is turned over to be
	# drawn: the phone's creature drawing carried that half turn itself.
	render_tilt[2]+=2048.0
	if secondary_model>=0:
		var fin:=Transform.new();fin.math.sine_table=pose.math.sine_table
		fin.set_euler(roundi(render_tilt[0]),roundi(render_tilt[1]),roundi(render_tilt[2]));secondary_pose.compose_rotation(fin)
		# The second part turns on the body's origin, which is where the two
		# meet; the view may bend it there instead of turning it whole.
		hinge_pose=secondary_pose.copy_pose();hinge_axis="";hinge_angle=0
		match model_id:
			4427,4432,4436:hinge_axis="pitch";hinge_angle=-(s>>6);fin.set_euler(hinge_angle,0,0)
			4430,4434,4440:hinge_axis="yaw";hinge_angle=s>>5;fin.set_euler(0,hinge_angle,0)
			_:fin.set_euler(0,0,0)
		secondary_pose.compose_rotation(fin)
