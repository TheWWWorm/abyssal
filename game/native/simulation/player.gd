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
var depth_direction := -1 # Original reference adapter; the rendered ocean uses +1.
var yaw_input := 0.0
var pitch_input := 0.0
var strafe_input := 0.0
var bank := 0
var visual_bank := 0
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
 if desired.length_squared()>.5:
  var facing:=Math.vector(pose.forward).normalized()
  pose.face(Math.array(facing.lerp(desired,1-exp(-delta_ms*.006)).normalized()*4096))
 else:
  yaw_step=roundi(stats.steering()*yaw_input*delta_ms/3.0)
  var pitch_step:=roundi(stats.steering()*pitch_input*delta_ms/3.0)
  pose.rotate_local("yaw",yaw_step);pose.rotate_local("pitch",pitch_step);pitch_total+=pitch_step
 # Mouse steering is applied before advance(), so axis inputs alone cannot
 # tell whether the pilot is maneuvering. Never level against an active loop.
 if yaw_input!=0 or pitch_input!=0:steering_quiet_ms=0
 else:steering_quiet_ms=mini(1000,steering_quiet_ms+delta_ms)
 if steering_quiet_ms>=600:pose.auto_level(delta_ms)
 pose.advance(roundi(delta_ms*speed_factor*throttle/100.0))
 if strafe_input!=0:pose.strafe(roundi(strafe_input*delta_ms*speed_factor*STRAFE_RATE))
 bank=roundi(move_toward(float(bank),yaw_input*320.0,delta_ms*1.2));visual_bank=-bank
 yaw_input=0;pitch_input=0;strafe_input=0
 depth=maxi(500,station_depth+roundi(depth_direction*pose.origin[1]/8.0))
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
 if x!=0 or y!=0:steering_quiet_ms=0
 mouse_remainder+=Vector2(x,y)
 var yaw := int(mouse_remainder.x); var pitch := int(mouse_remainder.y)
 mouse_remainder-=Vector2(yaw,pitch)
 if yaw==0 and pitch==0: return
 pose.rotate_local("yaw",yaw); pose.rotate_local("pitch",pitch)
 bank=clampi(bank+yaw*2,-384,384)
