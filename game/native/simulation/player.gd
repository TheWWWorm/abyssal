extends RefCounted
## Frame-time movement, bounded boost cooldown, regeneration and safe steering.
const Math = preload("res://native/simulation/fixed_math.gd")
const Transform = preload("res://native/simulation/ship_transform.gd")
const Health = preload("res://native/simulation/health.gd")
## Lateral thrusters run at a fraction of cruise speed and ignore the throttle,
## so a stopped submarine can still slide sideways out of trouble.
const STRAFE_RATE := 0.6
var pose := Transform.new()
var health := Health.new()
var stats
var station_depth := 22500
var depth := 22500
var yaw_input := 0.0
var pitch_input := 0.0
var strafe_input := 0.0
var bank := 0
var visual_bank := 0
var strafe_bank := 0.0
var yaw_step := 0
var pitch_total := 0
var speed_factor := 2
var stopped := false
var throttle_target := 100
var throttle := 100.0
var throttle_held_ms := 0
var throttle_direction := 0
var mouse_remainder := Vector2.ZERO
var steering_quiet_ms := 0
## The original turns at its full rate the instant a key goes down and stops
## the instant it comes up, and the mouse here turned the hull one step per
## pixel with no ceiling at all. Smooth steering runs the helm through a short
## lag instead, so the hull leans into a turn and eases out of it, and holds
## the mouse to a multiple of the ship's own steering rate, which also lets
## the steering upgrades mean something to a mouse pilot. Direct restores the
## original response.
var smooth_steering := false
## Touch steering combines yaw and pitch under one thumb. Level the actual
## flight frame while the helm is held so those rotations do not build an
## unintended roll that the chase camera or other players can see.
var touch_horizon_assist := false
## Time for the helm to close about two thirds of the gap to its input.
const STEER_RESPONSE_MS := 150.0
const MOUSE_RESPONSE_MS := 80.0
## Mouse turn ceiling as a multiple of the key-steering rate: three times
## the original's, so a full about-turn still takes the starter hull a
## couple of seconds rather than a flick.
const MOUSE_RATE_FACTOR := 3.0
## Mouse motion still owed once the ceiling bites, in Q12 units. Anything
## beyond it is dropped rather than carried, or a wide flick would leave the
## hull turning for seconds after the hand stopped.
const MOUSE_BACKLOG := 700.0
var yaw_level := 0.0
var pitch_level := 0.0
var yaw_carry := 0.0
var pitch_carry := 0.0
var mouse_carry := Vector2.ZERO
var boost_active := false
var boost_timer := 0
var shield_timer := 0
var repair_timer := 0
var disabled := false
var outside_depth_limits := false
var events: Array = []
var radius := 1200
var collision_groups: Array = []
var autopilot_target = null
var contact := false
var unbounded_world := false

func configure(ship, base_depth: int, sine: Array) -> void:
 stats=ship; station_depth=base_depth; depth=base_depth
 pose.math.sine_table=sine
 health.configure(ship.hull,ship.shield,ship.armor)

func steer(yaw: float,pitch: float,_delta_ms: int) -> void:
 yaw_input=clampf(yaw,-1,1);pitch_input=clampf(pitch,-1,1)

func set_strafe(value: float) -> void:
 strafe_input=clampf(value,-1,1)

func boost() -> bool:
 if boost_active or stats.boost_cooldown<=0 or boost_timer<0:return false
 set_throttle(100);boost_active=true;boost_timer=0;speed_factor=maxi(2,stats.boost_factor)
 events.append("boost_started");return true

func advance(delta_ms: int) -> void:
 if disabled or delta_ms<=0:return
 throttle=move_toward(throttle,float(throttle_target),delta_ms*.1);stopped=throttle<=0
 if boost_timer<0:
  boost_timer=mini(0,boost_timer+delta_ms)
  if boost_timer==0:events.append("boost_ready")
 elif boost_active:
  boost_timer+=delta_ms
  if boost_timer>=stats.boost_duration:
   boost_active=false;speed_factor=2;boost_timer=-stats.boost_cooldown;events.append("boost_finished")
 contact=false
 var avoidance:=Vector3.ZERO
 for group in collision_groups:
  for shape in group:
   if shape.contains(pose.origin):avoidance+=Math.vector(shape.avoidance_normal(pose.origin));contact=true
 var desired:=Vector3.ZERO
 if contact:desired=avoidance.normalized()
 elif autopilot_target!=null:
  var target: Array=autopilot_target if autopilot_target is Array else autopilot_target.pose.origin
  desired=(Math.vector(target)-Math.vector(pose.origin)).normalized()
 if smooth_steering:
  var blend:=1.0-exp(-delta_ms/STEER_RESPONSE_MS)
  yaw_level=lerpf(yaw_level,yaw_input,blend);pitch_level=lerpf(pitch_level,pitch_input,blend)
  # A helm that has all but come to rest is at rest, or the tail of every
  # turn would be a slow creep of single steps.
  if absf(yaw_level)<.01 and yaw_input==0:yaw_level=0.0
  if absf(pitch_level)<.01 and pitch_input==0:pitch_level=0.0
 else:yaw_level=yaw_input;pitch_level=pitch_input
 if desired.length_squared()>.5:
  var facing:=Math.vector(pose.forward).normalized()
  pose.face(Math.array(facing.lerp(desired,1-exp(-delta_ms*.006)).normalized()*4096))
  yaw_carry=0.0;pitch_carry=0.0;mouse_remainder=Vector2.ZERO;mouse_carry=Vector2.ZERO
 else:
  var rate: float=stats.steering()*delta_ms/3.0
  # Carry the fractions: the original rounds each tick, which at full input
  # is exact, but a helm settling through small values must not lose them.
  yaw_carry+=rate*yaw_level;pitch_carry+=rate*pitch_level
  yaw_step=roundi(yaw_carry);var pitch_step:=roundi(pitch_carry)
  yaw_carry-=yaw_step;pitch_carry-=pitch_step
  if not smooth_steering:yaw_carry=0.0;pitch_carry=0.0
  pose.rotate_local("yaw",yaw_step);pose.rotate_local("pitch",pitch_step);pitch_total+=pitch_step
  apply_mouse(delta_ms)
 if yaw_level!=0 or pitch_level!=0:steering_quiet_ms=0
 else:steering_quiet_ms=mini(1000,steering_quiet_ms+delta_ms)
 if touch_horizon_assist or steering_quiet_ms>=600:pose.auto_level(delta_ms)
 pose.advance(roundi(delta_ms*speed_factor*throttle/100.0))
 if strafe_input!=0:pose.strafe(roundi(strafe_input*delta_ms*speed_factor*STRAFE_RATE))
 # bb: the hull leans into a turn a unit a millisecond, to 384 (about
 # thirty-four degrees), holds the lean while the helm is over, and comes
 # back upright at a fifth of that once it centres. The smooth helm's
 # part-way levels lean in at their own share of the rate.
 if yaw_level!=0:bank=roundi(move_toward(float(bank),signf(yaw_level)*384.0,delta_ms*absf(yaw_level)))
 else:bank=roundi(move_toward(float(bank),0.0,delta_ms/5.0))
 # A gentle seven-degree lean follows lateral thrust and settles after release.
 # Only the rendered hull banks; flight, aiming and collision keep the same pose.
 strafe_bank=lerpf(strafe_bank,strafe_input*80.0,1-exp(-delta_ms*.007))
 # The render conversion reverses the roll axis: positive local bank
 # lowers the right side in a right turn, matching the strafe lean.
 visual_bank=bank+roundi(strafe_bank)
 yaw_input=0;pitch_input=0;strafe_input=0
 depth=maxi(500,station_depth+roundi(pose.origin[1]/8.0))
 if stats.shield>0 and stats.shield_interval>0 and depth>=stats.minimum_depth:
  shield_timer+=delta_ms
  while shield_timer>=stats.shield_interval:shield_timer-=stats.shield_interval;health.regenerate("shield")
 if stats.self_repair and health.hull<health.max_hull:
  repair_timer+=delta_ms
  while repair_timer>=600:repair_timer-=600;health.regenerate("hull")
 outside_depth_limits=depth>stats.maximum_depth+200 or depth<stats.minimum_depth-200
 if health.hull<=0:health.enabled=false

func set_throttle(value: int) -> void:
 throttle_target=clampi(value,0,100)
 if throttle_target<100 and boost_active:
  boost_active=false; boost_timer=-stats.boost_cooldown; speed_factor=2
func adjust_throttle(direction: int, milliseconds: int) -> void:
 if direction==0: throttle_held_ms=0; throttle_direction=0; return
 if direction!=throttle_direction: throttle_held_ms=0; throttle_direction=direction
 throttle_held_ms+=milliseconds
 if throttle_held_ms>=240:
  set_throttle(throttle_target+direction*25); throttle_held_ms=0

func mouse_steer(x: float, y: float) -> void:
 """Queues mouse motion, in Q12 units, for the next advance() to turn into
 rotation; steering while the helm is held (contact, autopilot) is dropped
 there, as key steering is."""
 if x!=0 or y!=0:steering_quiet_ms=0
 mouse_remainder+=Vector2(x,y)
 if smooth_steering:mouse_remainder=mouse_remainder.limit_length(MOUSE_BACKLOG)

func apply_mouse(delta_ms: int) -> void:
 var wanted:=mouse_remainder
 if smooth_steering:
  wanted*=1.0-exp(-delta_ms/MOUSE_RESPONSE_MS)
  var ceiling: float=stats.steering()*MOUSE_RATE_FACTOR*delta_ms/3.0
  wanted=Vector2(clampf(wanted.x,-ceiling,ceiling),clampf(wanted.y,-ceiling,ceiling))
  # The tail of the lag is finished outright rather than creeping in
  # fractions of a step for ever.
  if mouse_remainder.length()<3.0:wanted=mouse_remainder
 mouse_remainder-=wanted
 mouse_carry+=wanted
 var yaw:=roundi(mouse_carry.x);var pitch:=roundi(mouse_carry.y)
 mouse_carry-=Vector2(yaw,pitch)
 if yaw==0 and pitch==0:return
 steering_quiet_ms=0
 pose.rotate_local("yaw",yaw);pose.rotate_local("pitch",pitch)
 bank=clampi(bank+yaw*2,-384,384)
