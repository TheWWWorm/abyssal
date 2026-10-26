extends RefCounted
## Bounded projectile pool with swept collision, real-time cooldown and homing.
const Math=preload("res://native/simulation/fixed_math.gd")
var damage := 0
var speed := 0.0
var lifetime := 0
var cooldown := 0
var elapsed := 0
var mount: Array=[0,0,0]
var muzzle: Array=[0,0,0]
var positions: Array=[]
## The last movement step, used only to draw shots between simulation ticks.
var previous_positions: Array=[]
## Bounded launch records also let shared NPC gun pools report nearby fire.
var launch_positions: Array=[]
var launch_serials: Array=[]
var velocities: Array=[]
var remaining: Array=[]
var targets: Array=[]
var impacts: Array=[]
var fired := false
var launch_serial := 0
var active := false
var special_kill := false
var equipment_kind := 0
var equipment_id := -1
var model_id := -1
var fishing := false
var fishing_radius := 0
var hooked_target = null
var hook_busy := false
var terrain_collision: Callable
var slow_percent := 0
var beam := false
var homing := false
var velocity_step_ms := 40
## cos 20°: the widest a launch may swing from the hull's line of fire.
const MAX_AIM_COSINE := 0.94
static func vector(values: Array) -> Vector3:return Vector3(values[0],values[1],values[2])
static func coordinates(value: Vector3) -> Array:return [roundi(value.x),roundi(value.y),roundi(value.z)]
static func sphere_entry(start: Vector3, travel: Vector3, center: Vector3, radius: float) -> float:
 # Return the first contact along the segment, not its nearest approach to
 # the centre: a large or oblique hull may be reached before a nearer centre.
 var offset:=start-center
 var outside:=offset.length_squared()-radius*radius
 if outside<=0.0:return 0.0
 var distance_squared:=travel.length_squared()
 if distance_squared<=0.000001:return -1.0
 var approach:=offset.dot(travel)
 if approach>=0.0:return -1.0
 var discriminant:=approach*approach-distance_squared*outside
 if discriminant<0.0:return -1.0
 var entry:=(-approach-sqrt(discriminant))/distance_squared
 return entry if entry<=1.0 else -1.0
func configure(power: int,pool_size: int,life_ms: int,interval: int,units_per_ms: float,offset: Array) -> void:
 damage=maxi(0,power);lifetime=maxi(1,life_ms);cooldown=maxi(1,interval);speed=maxf(0,units_per_ms);mount=offset.duplicate()
 muzzle=mount.duplicate()
 elapsed=cooldown # Newly equipped weapons are ready on the first press.
 positions.clear();previous_positions.clear();launch_positions.clear();launch_serials.clear();velocities.clear();remaining.clear()
 for index in maxi(1,pool_size):
  positions.append([50000,50000,50000]);previous_positions.append([50000,50000,50000]);velocities.append([0,0,0]);remaining.append(-1)
  launch_positions.append([0,0,0]);launch_serials.append(0)
func launch(pose,delta_ms: int,aim=null,actor_mount=null) -> bool:
 if fishing and hook_busy:return false
 for index in remaining.size():
  if remaining[index]>0:continue
  var start:=vector(pose.origin)+vector(pose.rotate_direction(actor_mount if actor_mount is Array else mount))
  # A torpedo leaves along the hull as in the original (o.a without a
  # target); it finds its own way after the straight run.
  var direction:=vector(pose.forward) if aim==null or (homing and aim is Array) else vector(aim if aim is Array else aim.pose.origin)-start
  # A chase-camera hit can be behind the muzzle when close to salvage, or
  # stale after a sharp turn. Launchers are fixed to the hull: an aim more
  # than a few degrees off its line is parallax, not a target, and goes ahead.
  if direction.normalized().dot(vector(pose.forward).normalized())<MAX_AIM_COSINE:
   direction=vector(pose.forward)
  velocity_step_ms=maxi(1,delta_ms);positions[index]=coordinates(start);velocities[index]=launch_velocity(coordinates(direction),velocity_step_ms);remaining[index]=lifetime
  previous_positions[index]=positions[index].duplicate()
  elapsed=0;fired=true;active=true;launch_serial+=1
  launch_positions[index]=positions[index].duplicate();launch_serials[index]=launch_serial;return true
 return false
func launch_velocity(direction: Array,delta_ms: int) -> Array:
 return coordinates(vector(direction).normalized()*speed*maxi(1,delta_ms))
func request_fire(pose,delta_ms: int,aim=null,actor_mount=null) -> bool:
 return launch(pose,delta_ms,aim,actor_mount) if elapsed>=cooldown else false
func advance(delta_ms: int) -> void:
 elapsed+=maxi(0,delta_ms)
 if not active or hook_busy:return
 hooked_target=null
 for index in remaining.size():
  if remaining[index]<=0:continue
  previous_positions[index]=positions[index].duplicate()
  var start:=vector(positions[index]);var direction:=vector(velocities[index]).normalized()
  # A torpedo runs straight for its first second and a half, then turns
  # after the nearest live target within a hundred and fifty metres (dm.b).
  # Creatures are never chosen (cm.a: af sets the flag), though one in the
  # way is still hit.
  if homing and remaining[index]<lifetime-1500:
   var nearest=null;var squared:=15000.0*15000.0*3
   for actor in targets:
    if actor.is_creature or not actor.health.enabled or actor.health.hull<=0:continue
    var offset:=vector(actor.pose.origin)-start
    if absf(offset.x)>=15000 or absf(offset.y)>=15000 or absf(offset.z)>=15000:continue
    var distance:=offset.length_squared()
    if distance<squared:squared=distance;nearest=actor
   # dm's pursuit: the step's velocity pulled toward the whole offset, so it
   # turns harder the further off the target is and not at all dead ahead.
   if nearest!=null:
    var step:=vector(velocities[index])
    var steered:=step+((vector(nearest.pose.origin)-start)-step)*(float(delta_ms)/4096.0)
    if steered.length_squared()>0.0:direction=steered.normalized()
  var travel:=direction*speed*mini(delta_ms,remaining[index])
  var finish:=start+travel
  var hit=null;var hit_fraction:=1.0
  for actor in targets:
   # A harpoon can strike any enabled body, including a live hull or mine.
   # Fishing decides whether that impact can retain a line; capturable is
   # a salvage flag, not collision eligibility (o.c / cx.a).
   if not actor.health.enabled:continue
   var radius:=maxf(1,fishing_radius if fishing else actor.radius)
   var entry:=sphere_entry(start,travel,vector(actor.pose.origin),radius)
   if entry>=0.0 and (hit==null or entry<hit_fraction):hit=actor;hit_fraction=entry
  # Bounded segment samples prevent ordinary shots crossing station walls.
  var terrain_hit:=false
  if terrain_collision.is_valid():
   var samples:=clampi(ceili(travel.length()/800.0),1,64)
   for sample in range(1,samples+1):
    var fraction:=float(sample)/samples
    if fraction>hit_fraction:break
    if terrain_collision.call(coordinates(start+travel*fraction)):terrain_hit=true;hit=null;hit_fraction=fraction;break
  if hit!=null or terrain_hit:
   positions[index]=coordinates(start+travel*hit_fraction);remaining[index]=-1
   if hit!=null:
    if fishing:hooked_target=hit
    else:hit.health.damage(damage,"combined",special_kill)
   impacts.append({"target":hit,"position":positions[index].duplicate(),"direction":coordinates(direction*4096),"impulse":coordinates(-travel)})
  else:
   positions[index]=coordinates(finish);remaining[index]-=delta_ms
  velocities[index]=coordinates(direction*speed*velocity_step_ms)
 active=hooked_target!=null or remaining.any(func(value):return value>0)
func values() -> Array:return [elapsed,positions,velocities,remaining]
